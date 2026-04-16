/// Rockwell R6551 ACIA emulation.
///
/// Known hardware bug: TDRE (Status bit 4) is ALWAYS 1 — firmware must poll,
/// TX interrupts are unusable (just like on the real chip).
///
/// Register map (relative to $C800):
///   +0  Data register  (R = RX data, W = TX data)
///   +1  Status register (R) / Programmed reset (W, any write)
///   +2  Command register
///   +3  Control register
///
/// Status register bits:
///   7 IRQ    6 DSR    5 DCD    4 TDRE(bug=1)  3 RDRF  2 OVRN  1 FE  0 PE
use std::collections::VecDeque;
use std::sync::{Arc, Mutex};

/// Shared queues between ACIA ↔ TUI/TCP.
/// tx_buf: bytes the CPU wrote (ACIA TX → terminal/TCP)
/// rx_buf: bytes typed in terminal/TCP (→ ACIA RX)
#[derive(Default)]
pub struct AciaIo {
    pub tx_buf: VecDeque<u8>, // ACIA→terminal
    pub rx_buf: VecDeque<u8>, // terminal→ACIA
}

pub struct Acia {
    pub io: Arc<Mutex<AciaIo>>,

    // Registers
    pub status: u8,
    pub command: u8,
    pub control: u8,

    // Internal state
    pub rx_data:     u8,
    pub rdrf:        bool,  // receive data register full
    pub irq_pending: bool,

    // Cycle-level timing
    pub baud_divider: u32, // cycles per bit at current baud rate
    rx_timer: u32,
    tx_timer: u32,
}

impl Acia {
    pub fn new(io: Arc<Mutex<AciaIo>>) -> Self {
        Self {
            io,
            status: 0b0001_0000,  // TDRE always set (hardware bug)
            command: 0,
            control: 0,
            rx_data: 0,
            rdrf: false,
            irq_pending: false,
            baud_divider: 8680, // ~19200 baud @ 1 MHz — recalc on control write
            rx_timer: 0,
            tx_timer: 0,
        }
    }

    /// Baud rate divider from control register bits 3-0
    fn calc_baud_div(control: u8, clock_hz: u32) -> u32 {
        let baud = match control & 0x0F {
            0  => 0,        // external clock
            1  => 50,
            2  => 75,
            3  => 109,
            4  => 134,
            5  => 150,
            6  => 300,
            7  => 600,
            8  => 1200,
            9  => 1800,
            10 => 2400,
            11 => 3600,
            12 => 4800,
            13 => 7200,
            14 => 9600,
            15 => 19200,
            _  => 9600,
        };
        if baud == 0 { 52 } else { clock_hz / baud }
    }

    pub fn read(&mut self, addr: u16) -> u8 {
        match addr & 0x03 {
            0 => {
                // RX data
                let v = self.rx_data;
                self.rdrf = false;
                self.update_status();
                v
            }
            1 => self.status,
            2 => self.command,
            3 => self.control,
            _ => 0xFF,
        }
    }

    pub fn write(&mut self, addr: u16, val: u8) {
        match addr & 0x03 {
            0 => {
                // TX data — enqueue to output buffer
                if let Ok(mut io) = self.io.lock() {
                    io.tx_buf.push_back(val);
                }
                // TDRE stays 1 (hardware bug — always ready)
            }
            1 => {
                // Programmed reset (any write to status reg)
                self.status = 0b0001_0000; // TDRE=1, rest clear
                self.command = 0;
                self.rdrf = false;
                self.irq_pending = false;
            }
            2 => {
                self.command = val;
                self.update_status();
            }
            3 => {
                self.control = val;
                self.baud_divider = Self::calc_baud_div(val, 1_000_000);
                self.update_status();
            }
            _ => {}
        }
    }

    /// Called every N CPU cycles from the emulation loop.
    /// Returns true if an IRQ should be raised.
    pub fn tick(&mut self, cycles: u32) -> bool {
        // Check for incoming byte from the terminal/TCP queue
        self.rx_timer = self.rx_timer.saturating_add(cycles);
        if self.rx_timer >= self.baud_divider {
            self.rx_timer -= self.baud_divider;
            if !self.rdrf {
                // Drop the lock guard before calling update_status (avoids borrow conflict)
                let maybe_byte = self.io.try_lock().ok()
                    .and_then(|mut io| io.rx_buf.pop_front());
                if let Some(b) = maybe_byte {
                    self.rx_data = b;
                    self.rdrf = true;
                    self.update_status();
                }
            }
        }
        self.irq_pending && (self.command & 0x0C != 0x04)
    }

    fn update_status(&mut self) {
        // bit 7: IRQ  bit 3: RDRF  bit 4: TDRE always 1
        self.status = 0b0001_0000; // TDRE always 1
        if self.rdrf        { self.status |= 0x08; }
        // IRQ fires on RDRF if RX IRQ enabled (command bits 1-0 != 0)
        self.irq_pending = self.rdrf && (self.command & 0x02 != 0);
        if self.irq_pending { self.status |= 0x80; }
    }

    pub fn irq(&self) -> bool { self.irq_pending }
}
