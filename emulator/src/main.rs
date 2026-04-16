/// Project65 SBC 65C02 Emulator — entry point.
///
/// Usage:
///   p65emu [OPTIONS] [ROM]
///
/// Options:
///   -s, --speed <HZ>      Initial CPU speed in Hz (default 1000000)
///   -p, --port  <PORT>    TCP serial port (default 6551, 0 = disabled)
///   -h, --help
///
/// The emulator exposes two interfaces to the ACIA serial port:
///   1. Built-in TUI terminal panel (keyboard → RX, TX → display)
///   2. TCP server — connect with PuTTY / nc / minicom to localhost:<PORT>

mod cpu;
mod bus;
mod ram;
mod rom;
mod acia;
mod via;
mod irq_latch;
mod app;

use std::sync::{Arc, Mutex, mpsc};
use std::thread;
use std::time::{Duration, Instant};
use std::net::{TcpListener, TcpStream};
use std::io::{Read, Write};

use clap::Parser;

use acia::AciaIo;
use app::{App, Cmd, SharedState};
use bus::{Bus, ChipFamily};
use cpu::Cpu;

#[derive(Parser)]
#[command(name = "p65emu", about = "Project65 SBC 65C02 Emulator")]
struct Cli {
    /// ROM binary file to load at $E000
    rom: Option<String>,

    /// CPU speed in Hz (0 = unlimited)
    #[arg(short, long, default_value_t = 1_000_000)]
    speed: u64,

    /// TCP port for virtual serial port (0 = disabled)
    #[arg(short, long, default_value_t = 6551)]
    port: u16,

    /// Adresní dekodér — rodina logických obvodů IC9/IC11
    /// Hodnoty: LS, ALS, HCT, HC, AC, ACT  (výchozí: HCT)
    #[arg(short = 'f', long = "family", default_value = "HCT")]
    family: String,
}

fn main() {
    let cli = Cli::parse();

    // ── ACIA I/O queues ───────────────────────────────────────────────────
    let acia_io = Arc::new(Mutex::new(AciaIo::default()));

    // ── Build bus and initial state ───────────────────────────────────────
    let acia = acia::Acia::new(Arc::clone(&acia_io));
    let mut bus = Bus::new(acia);

    // Set chip family (address decoder timing model)
    let family: ChipFamily = cli.family.parse().unwrap_or_else(|e| {
        eprintln!("Warning: {e}. Používám HCT.");
        ChipFamily::HCT
    });
    bus.chip_family = family;
    eprintln!("Chip family: {}  (decode delay: {} ns)",
        family.name(), bus.decode_delay_ns());

    // Load ROM if provided
    if let Some(path) = &cli.rom {
        match std::fs::read(path) {
            Ok(data) => {
                bus.rom.load(&data);
                eprintln!("Loaded ROM: {} ({} bytes)", path, data.len());
            }
            Err(e) => {
                eprintln!("Warning: could not load ROM '{}': {}", path, e);
            }
        }
    }

    let shared   = Arc::new(Mutex::new(SharedState::new(bus)));
    let (cmd_tx, cmd_rx) = mpsc::channel::<Cmd>();

    // ── TCP virtual serial port thread ────────────────────────────────────
    if cli.port != 0 {
        let io_clone = Arc::clone(&acia_io);
        let port = cli.port;
        thread::Builder::new().name("tcp-serial".into()).spawn(move || {
            tcp_serial_server(io_clone, port);
        }).unwrap();
    }

    // ── CPU emulation thread ──────────────────────────────────────────────
    {
        let shared_cpu = Arc::clone(&shared);
        thread::Builder::new().name("cpu".into()).spawn(move || {
            cpu_thread(shared_cpu, cmd_rx, cli.speed);
        }).unwrap();
    }

    // ── TUI (main thread) ─────────────────────────────────────────────────
    {
        let mut lock = shared.lock().unwrap();
        lock.speed_hz = cli.speed;
    }

    let mut app = App::new(Arc::clone(&shared), Arc::clone(&acia_io), cmd_tx.clone());
    app.speed_hz = cli.speed;

    if let Err(e) = app::run(&mut app) {
        eprintln!("TUI error: {}", e);
    }

    // Signal CPU thread to quit
    let _ = cmd_tx.send(Cmd::Quit);
}

// ── CPU thread ────────────────────────────────────────────────────────────────

fn cpu_thread(shared: Arc<Mutex<SharedState>>, cmd_rx: mpsc::Receiver<Cmd>, initial_speed: u64) {
    let mut cpu = Cpu::new();
    let mut speed_hz = initial_speed;
    let mut running = false;
    let mut quit = false;

    // Reset CPU on startup
    {
        let mut st = shared.lock().unwrap();
        st.speed_hz = speed_hz;
        cpu.reset(&mut st.bus);
        st.cpu = cpu.snapshot();
    }

    let mut cycle_budget: i64 = 0;
    let mut last_tick = Instant::now();

    while !quit {
        // ── Drain commands ────────────────────────────────────────────────
        loop {
            match cmd_rx.try_recv() {
                Ok(cmd) => match cmd {
                    Cmd::Run   => running = true,
                    Cmd::Pause => running = false,
                    Cmd::Step  => {
                        // Single step even if paused
                        let mut st = shared.lock().unwrap();
                        let (nmi, irq) = st.bus.tick(1);
                        cpu.poll_interrupts(&mut st.bus, nmi, irq);
                        cpu.step(&mut st.bus);
                        st.cpu = cpu.snapshot();
                        st.nmi = nmi;
                        st.irq = irq;
                        running = false;
                    }
                    Cmd::Reset => {
                        let mut st = shared.lock().unwrap();
                        cpu.reset(&mut st.bus);
                        st.cpu = cpu.snapshot();
                    }
                    Cmd::SetSpeed(hz) => {
                        speed_hz = hz;
                        let mut st = shared.lock().unwrap();
                        st.speed_hz = hz;
                        cycle_budget = 0;
                    }
                    Cmd::LoadAt { data, addr, reset } => {
                        let mut st = shared.lock().unwrap();
                        if addr >= 0xE000 {
                            // Load into ROM struct (writes to ROM are ignored by bus)
                            st.bus.rom.load(&data);
                        } else {
                            // Write into RAM through normal bus write path
                            for (i, &b) in data.iter().enumerate() {
                                let target = addr.wrapping_add(i as u16);
                                st.bus.write(target, b);
                            }
                        }
                        if reset {
                            cpu.reset(&mut st.bus);
                        }
                        st.cpu = cpu.snapshot();
                    }
                    Cmd::SetReg { field, val } => {
                        match field {
                            0 => cpu.a  = val as u8,
                            1 => cpu.x  = val as u8,
                            2 => cpu.y  = val as u8,
                            3 => cpu.sp = val as u8,
                            4 => cpu.pc = val,
                            5 => cpu.p  = (val as u8) | 0x20, // U flag always set
                            _ => {}
                        }
                        let mut st = shared.lock().unwrap();
                        st.cpu = cpu.snapshot();
                    }
                    Cmd::Quit => { quit = true; break; }
                },
                Err(mpsc::TryRecvError::Empty) => break,
                Err(mpsc::TryRecvError::Disconnected) => { quit = true; break; }
            }
        }

        if quit { break; }

        if running {
            let elapsed = last_tick.elapsed();
            last_tick = Instant::now();

            // How many cycles should we execute this slice?
            let slice_cycles = if speed_hz == u64::MAX {
                100_000i64 // unlimited: run in big chunks
            } else {
                let c = (speed_hz as f64 * elapsed.as_secs_f64()) as i64;
                c.min(100_000) // cap per slice to stay responsive
            };

            cycle_budget += slice_cycles;

            // Execute cycles
            if cycle_budget > 0 {
                let mut st = shared.lock().unwrap();
                let mut executed = 0i64;

                while executed < cycle_budget && !cpu.halted {
                    let (nmi, irq) = st.bus.tick(1);
                    cpu.poll_interrupts(&mut st.bus, nmi, irq);
                    let c = cpu.step(&mut st.bus) as i64;
                    executed += c;
                    st.nmi = nmi;
                    st.irq = irq;
                }

                cycle_budget -= executed;
                if cycle_budget > 200_000 { cycle_budget = 0; } // prevent runaway

                st.cpu = cpu.snapshot();
                st.running = true;
            }

            // Short sleep to yield to other threads
            if speed_hz != u64::MAX {
                thread::sleep(Duration::from_micros(500));
            } else {
                thread::yield_now();
            }
        } else {
            // Paused — just sleep
            last_tick = Instant::now();
            {
                let mut st = shared.lock().unwrap();
                st.running = false;
            }
            thread::sleep(Duration::from_millis(10));
        }
    }
}

// ── TCP virtual serial port ───────────────────────────────────────────────────

fn tcp_serial_server(io: Arc<Mutex<AciaIo>>, port: u16) {
    let addr = format!("127.0.0.1:{}", port);
    let listener = match TcpListener::bind(&addr) {
        Ok(l) => { eprintln!("[serial] Listening on {}", addr); l }
        Err(e) => { eprintln!("[serial] Could not bind {}: {}", addr, e); return; }
    };

    for stream in listener.incoming() {
        match stream {
            Ok(stream) => {
                eprintln!("[serial] Client connected: {}", stream.peer_addr().unwrap());
                let io2 = Arc::clone(&io);
                thread::spawn(move || { handle_tcp_client(stream, io2); });
            }
            Err(_) => break,
        }
    }
}

fn handle_tcp_client(mut stream: TcpStream, io: Arc<Mutex<AciaIo>>) {
    stream.set_nonblocking(true).ok();
    let mut rx_buf = [0u8; 64];

    loop {
        // Forward TCP → ACIA RX
        match stream.read(&mut rx_buf) {
            Ok(0) => break, // disconnected
            Ok(n) => {
                if let Ok(mut io) = io.lock() {
                    for &b in &rx_buf[..n] { io.rx_buf.push_back(b); }
                }
            }
            Err(ref e) if e.kind() == std::io::ErrorKind::WouldBlock => {}
            Err(_) => break,
        }

        // Forward ACIA TX → TCP
        let bytes: Vec<u8> = {
            if let Ok(mut io) = io.try_lock() {
                io.tx_buf.drain(..).collect()
            } else { vec![] }
        };
        if !bytes.is_empty() {
            if stream.write_all(&bytes).is_err() { break; }
        }

        thread::sleep(Duration::from_millis(2));
    }
    eprintln!("[serial] Client disconnected.");
}
