/// TUI application using ratatui + crossterm.
///
/// Layout:
///   ┌─ Title / speed bar ──────────────────────────────────┐
///   │ TERMINAL (6551)  │ CPU REGISTERS                     │
///   │                  ├───────────────────────────────────┤
///   │                  │ MEMORY DUMP [tabs]                │
///   │                  │ hex + ascii                       │
///   ├──────────────────┴───────────────────────────────────┤
///   │ STATUS: IRQ NMI VIA1-T1 VIA2-T1 ACIA cycles         │
///   └──────────────────────────────────────────────────────┘
///
/// Modály:
///   Ctrl+O  → file browser (navigace po adresářích, Enter = načíst ROM)
///   Ctrl+G  → vstup hex adresy pro memory dump
///
/// Klávesy (normální režim):
///   F2          Jeden krok
///   F3          Run / Pause
///   F4          Reset CPU
///   F5-F9       Speed: 1K / 10K / 100K / 1M / MAX
///   +/-         Speed ×2 / ÷2
///   Tab         Přepnout záložku paměti
///   PgUp/PgDn   Scroll paměti
///   Shift+Pg    Scroll terminálu
///   F10/Ctrl+Q  Quit

use std::collections::VecDeque;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};
use std::io;

use crossterm::{
    event::{self, Event, KeyCode, KeyModifiers, KeyEvent},
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
};
use ratatui::{
    backend::CrosstermBackend,
    layout::{Alignment, Constraint, Direction, Layout, Rect},
    style::{Color, Modifier, Style},
    text::{Line, Span, Text},
    widgets::{Block, Borders, Clear, List, ListItem, ListState, Paragraph, Tabs, Wrap},
    Terminal,
    Frame,
};

use crate::acia::AciaIo;
use crate::cpu::CpuState;
use crate::bus::{Bus, TimingStatus};

// ── Shared state ─────────────────────────────────────────────────────────────

pub struct SharedState {
    pub cpu:      CpuState,
    pub bus:      Bus,
    pub running:  bool,
    pub speed_hz: u64,
    pub nmi:      bool,
    pub irq:      bool,
}

impl SharedState {
    pub fn new(bus: Bus) -> Self {
        Self {
            cpu: CpuState::default(),
            bus,
            running: false,
            speed_hz: 1_000_000,
            nmi: false,
            irq: false,
        }
    }
}

// ── Command channel: TUI → CPU thread ────────────────────────────────────────

#[derive(Debug)]
pub enum Cmd {
    Step,
    Run,
    Pause,
    Reset,
    SetSpeed(u64),
    /// Load `data` into memory starting at `addr`.
    /// If `reset` is true, CPU is reset after loading.
    LoadAt { data: Vec<u8>, addr: u16, reset: bool },
    /// Set a single CPU register.
    /// field: 0=A 1=X 2=Y 3=SP 4=PC 5=P
    SetReg { field: u8, val: u16 },
    Quit,
}

// ── Memory view tabs ─────────────────────────────────────────────────────────

#[derive(Clone, Copy, PartialEq)]
pub enum MemTab { Zp, Ram, HiRam, Io, Rom, Custom }

impl MemTab {
    const ALL: &'static [MemTab] =
        &[MemTab::Zp, MemTab::Ram, MemTab::HiRam, MemTab::Io, MemTab::Rom, MemTab::Custom];

    fn label(self) -> &'static str {
        match self {
            MemTab::Zp     => "ZP",
            MemTab::Ram    => "RAM",
            MemTab::HiRam  => "HiRAM",
            MemTab::Io     => "I/O",
            MemTab::Rom    => "ROM",
            MemTab::Custom => "Addr",
        }
    }

    fn base(self, custom: u16) -> u16 {
        match self {
            MemTab::Zp     => 0x0000,
            MemTab::Ram    => 0x0200,
            MemTab::HiRam  => 0x8000,
            MemTab::Io     => 0xC000,
            MemTab::Rom    => 0xE000,
            MemTab::Custom => custom,
        }
    }
}

// ── Right-panel tabs ─────────────────────────────────────────────────────────

#[derive(Clone, Copy, PartialEq)]
pub enum RightTab { Cpu, Via1, Via2, Acia, Irq, Vdp, Saa }

impl RightTab {
    const ALL: &'static [RightTab] =
        &[RightTab::Cpu, RightTab::Via1, RightTab::Via2, RightTab::Acia,
          RightTab::Irq, RightTab::Vdp, RightTab::Saa];

    fn label(self) -> &'static str {
        match self {
            RightTab::Cpu  => " CPU ",
            RightTab::Via1 => " VIA1 ",
            RightTab::Via2 => " VIA2 ",
            RightTab::Acia => " ACIA ",
            RightTab::Irq  => " IRQ ",
            RightTab::Vdp  => " VDP ",
            RightTab::Saa  => " SAA ",
        }
    }
}

// ── File browser ──────────────────────────────────────────────────────────────

/// One item in the file browser list.
#[derive(Clone)]
struct FsEntry {
    name: String,
    is_dir: bool,
    full_path: PathBuf,
}

pub struct FileBrowser {
    pub dir:      PathBuf,
    entries:      Vec<FsEntry>,
    pub selected: usize,
    pub scroll:   usize,
    pub error:    Option<String>,
}

impl FileBrowser {
    /// Open browser at `start_dir`; falls back to cwd on error.
    pub fn open(start_dir: &Path) -> Self {
        let dir = if start_dir.is_dir() {
            start_dir.to_path_buf()
        } else {
            std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."))
        };
        let mut fb = FileBrowser {
            dir: dir.clone(),
            entries: vec![],
            selected: 0,
            scroll: 0,
            error: None,
        };
        fb.refresh();
        fb
    }

    /// Read directory and rebuild entry list.
    pub fn refresh(&mut self) {
        self.entries.clear();

        // Parent entry
        if let Some(parent) = self.dir.parent() {
            self.entries.push(FsEntry {
                name: "..".into(),
                is_dir: true,
                full_path: parent.to_path_buf(),
            });
        }

        let rd = match std::fs::read_dir(&self.dir) {
            Ok(r) => r,
            Err(e) => { self.error = Some(e.to_string()); return; }
        };

        let mut dirs:  Vec<FsEntry> = vec![];
        let mut files: Vec<FsEntry> = vec![];

        for entry in rd.flatten() {
            let path = entry.path();
            let name = entry.file_name().to_string_lossy().to_string();
            let is_dir = path.is_dir();

            if is_dir {
                dirs.push(FsEntry { name, is_dir: true, full_path: path });
            } else {
                // Show all files (user can load any binary)
                files.push(FsEntry { name, is_dir: false, full_path: path });
            }
        }

        dirs.sort_by(|a, b| a.name.to_lowercase().cmp(&b.name.to_lowercase()));
        files.sort_by(|a, b| a.name.to_lowercase().cmp(&b.name.to_lowercase()));

        self.entries.extend(dirs);
        self.entries.extend(files);
        self.error = None;
    }

    pub fn move_up(&mut self) {
        if self.selected > 0 {
            self.selected -= 1;
            if self.selected < self.scroll {
                self.scroll = self.selected;
            }
        }
    }

    pub fn move_down(&mut self, visible_rows: usize) {
        if self.selected + 1 < self.entries.len() {
            self.selected += 1;
            if self.selected >= self.scroll + visible_rows {
                self.scroll = self.selected - visible_rows + 1;
            }
        }
    }

    /// Enter selected directory; returns None (stays open).
    /// If selected is a file, returns its path.
    pub fn activate(&mut self) -> Option<PathBuf> {
        if let Some(e) = self.entries.get(self.selected).cloned() {
            if e.is_dir {
                self.dir = e.full_path;
                self.selected = 0;
                self.scroll = 0;
                self.refresh();
                None
            } else {
                Some(e.full_path)
            }
        } else {
            None
        }
    }
}

// ── Load-target list ──────────────────────────────────────────────────────────

pub struct Target {
    pub label: &'static str,
    pub desc:  &'static str,
    pub addr:  u16,
    pub reset: bool,
}

pub const TARGETS: &[Target] = &[
    Target { label: "$E000", desc: "ROM — EEPROM (8 KB)  [+ Reset]",        addr: 0xE000, reset: true  },
    Target { label: "$8000", desc: "HiRAM — IC7 (32 KB)",                   addr: 0x8000, reset: false },
    Target { label: "$6000", desc: "RAM — bootloader oblast ($6000-$7FFF)",  addr: 0x6000, reset: false },
    Target { label: "$0200", desc: "RAM — pracovní oblast ($0200-$5FFF)",    addr: 0x0200, reset: false },
    Target { label: "$0000", desc: "RAM — od nuly (ZP + stack + RAM)",       addr: 0x0000, reset: false },
];

// ── Modal mode ────────────────────────────────────────────────────────────────

pub enum Modal {
    None,
    FileBrowser(FileBrowser),
    /// Second step after file browser: choose target address/page.
    LoadTarget {
        data:       Vec<u8>,
        filename:   String,
        selected:   usize,
        /// When Some, user is typing a custom hex address instead of picking from list.
        custom_buf: Option<String>,
    },
    GotoAddr { buf: String },
    /// Edit a single memory byte: phase=false → enter addr, phase=true → enter value.
    EditMem { addr_buf: String, val_buf: String, phase: bool },
    /// Edit CPU registers: sel = register index (0=A…5=P).
    EditReg { sel: usize, val_buf: String },
}

// ── App state ─────────────────────────────────────────────────────────────────

pub struct App {
    pub shared:      Arc<Mutex<SharedState>>,
    pub acia_io:     Arc<Mutex<AciaIo>>,   // přímý přístup bez shared — nesmí blokovat CPU
    pub cmd_tx:      std::sync::mpsc::Sender<Cmd>,

    // Serial terminal
    pub term_lines:  VecDeque<String>,
    pub term_cur:    String,
    pub term_scroll: usize,

    // Memory view
    pub mem_tab:     MemTab,
    pub mem_scroll:  usize,
    pub custom_addr: u16,

    pub speed_hz:    u64,
    pub status_msg:  String,
    pub right_tab:   RightTab,

    pub modal:       Modal,
}

impl App {
    pub fn new(
        shared:  Arc<Mutex<SharedState>>,
        acia_io: Arc<Mutex<AciaIo>>,
        cmd_tx:  std::sync::mpsc::Sender<Cmd>,
    ) -> Self {
        let speed = shared.lock().unwrap().speed_hz;
        Self {
            shared,
            acia_io,
            cmd_tx,
            term_lines: VecDeque::with_capacity(1000),
            term_cur: String::new(),
            term_scroll: 0,
            mem_tab: MemTab::Zp,
            mem_scroll: 0,
            custom_addr: 0x0000,
            speed_hz: speed,
            status_msg: "F3=Run F2=Step F4=Reset Ctrl+O=ROM Ctrl+M=EditMem Ctrl+R=EditReg ShiftTab=Panel F10=Quit".into(),
            right_tab: RightTab::Cpu,
            modal: Modal::None,
        }
    }

    /// Přečte ACIA TX buffer přímo — nečeká na `shared` mutex (CPU ho drží při běhu).
    pub fn drain_acia(&mut self) {
        let bytes: Vec<u8> = if let Ok(mut io) = self.acia_io.try_lock() {
            io.tx_buf.drain(..).collect()
        } else {
            return;
        };

        // EWOZ ECHO stripuje bit 7 (AND #$7F) před zápisem do ACIA,
        // takže dostáváme standardní 7-bit ASCII.
        // Odřádkování: EWOZ posílá pouze CR (0x0D) — LF (0x0A) se nepoužívá.
        // Backspace: EWOZ posílá sekvenci BS(0x08) + SPACE(0x20) + BS(0x08).
        //   BS·SPC přeskočíme, druhý BS ignorujeme (kurzor je již na správném místě).

        let mut prev_was_bs = false;
        let mut ewoz_bs_seq = false; // viděli jsme BS·SPC, čekáme na druhý BS k ignorování

        for raw in bytes {
            let b = raw & 0x7F; // strip bit 7 pro jistotu
            match b {
                0x0D => {
                    // CR → odřádkování (EWOZ newline)
                    let line = std::mem::take(&mut self.term_cur);
                    if self.term_lines.len() >= 500 { self.term_lines.pop_front(); }
                    self.term_lines.push_back(line);
                    // auto-scroll na konec pokud uživatel nestroloval nahoru
                    if self.term_scroll == 0 { /* already at bottom */ }
                    prev_was_bs = false;
                    ewoz_bs_seq = false;
                }
                0x0A => {
                    // LF → odřádkování (jen pokud nepředcházel CR, aby se předešlo dvojitému \r\n)
                    if !prev_was_bs {
                        let line = std::mem::take(&mut self.term_cur);
                        if self.term_lines.len() >= 500 { self.term_lines.pop_front(); }
                        self.term_lines.push_back(line);
                    }
                    prev_was_bs = false;
                    ewoz_bs_seq = false;
                }
                0x08 | 0x7F => {
                    if ewoz_bs_seq {
                        // Druhý BS v EWOZ sekvenci BS·SPC·BS — kurzor je již zpět, přeskočit
                        ewoz_bs_seq = false;
                    } else {
                        // Samostatný BS nebo DEL → smaž poslední znak
                        self.term_cur.pop();
                    }
                    prev_was_bs = true;
                }
                0x20 if prev_was_bs => {
                    // SPACE bezprostředně po BS = část EWOZ BS-sekvence (BS·SPC·BS)
                    // → přeskočíme mezeru a nastavíme flag pro ignorování druhého BS
                    ewoz_bs_seq = true;
                    prev_was_bs = false;
                }
                c if c < 0x20 => {
                    // ostatní řídicí znaky ignoruj (BEL, TAB bez rozšíření atd.)
                    prev_was_bs = false;
                    ewoz_bs_seq = false;
                }
                c => {
                    self.term_cur.push(c as char);
                    prev_was_bs = false;
                    ewoz_bs_seq = false;
                }
            }
        }
    }

    /// Pošle bajt do ACIA RX přímo — funguje i když CPU drží `shared` mutex.
    pub fn send_key(&self, b: u8) {
        if let Ok(mut io) = self.acia_io.lock() {
            io.rx_buf.push_back(b);
        }
    }

    pub fn set_speed(&mut self, hz: u64) {
        self.speed_hz = hz;
        let _ = self.cmd_tx.send(Cmd::SetSpeed(hz));
        self.status_msg = format!("Speed: {}", fmt_hz(hz));
    }

    pub fn current_tab_idx(&self) -> usize {
        MemTab::ALL.iter().position(|t| *t == self.mem_tab).unwrap_or(0)
    }

    pub fn open_file_browser(&mut self) {
        let start = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
        self.modal = Modal::FileBrowser(FileBrowser::open(&start));
    }
}

fn fmt_hz(hz: u64) -> String {
    if hz >= 1_000_000 { format!("{:.1} MHz", hz as f64 / 1e6) }
    else if hz >= 1_000 { format!("{:.0} KHz", hz as f64 / 1e3) }
    else                { format!("{} Hz", hz) }
}

// ── Rendering ─────────────────────────────────────────────────────────────────

pub fn draw(f: &mut Frame, app: &mut App) {
    let size = f.area();

    let outer = Layout::default()
        .direction(Direction::Vertical)
        .constraints([Constraint::Length(1), Constraint::Min(10), Constraint::Length(1)])
        .split(size);

    draw_title(f, app, outer[0]);
    draw_content(f, app, outer[1]);
    draw_status(f, app, outer[2]);

    // Modal overlays (rendered last = on top)
    match &app.modal {
        Modal::FileBrowser(_)    => draw_file_browser(f, app, size),
        Modal::LoadTarget { .. } => draw_load_target(f, app, size),
        Modal::GotoAddr { .. }   => draw_goto_addr(f, app, size),
        Modal::EditMem { .. }    => draw_edit_mem(f, app, size),
        Modal::EditReg { .. }    => draw_edit_reg(f, app, size),
        Modal::None => {}
    }
}

fn draw_title(f: &mut Frame, app: &App, area: Rect) {
    let (running, spd, cycles, pc, family_name, timing) = {
        match app.shared.try_lock() {
            Ok(st) => {
                let ts = st.bus.timing_status(st.speed_hz);
                (st.running, st.speed_hz, st.cpu.cycles, st.cpu.pc,
                 st.bus.chip_family.name(), ts)
            }
            Err(_) => (false, app.speed_hz, 0, 0, "???", TimingStatus::Ok),
        }
    };
    let state = if running { "▶ RUN " } else { "⏸ PAUSE" };
    let (timing_str, timing_color) = match timing {
        TimingStatus::Ok       => (format!("[{} OK]",    family_name), Color::Green),
        TimingStatus::Marginal => (format!("[{} ~MRG]",  family_name), Color::Yellow),
        TimingStatus::Fail     => (format!("[{} SLOW!]", family_name), Color::Red),
    };
    let title = format!(
        " Project65 │ {} │ {} │ PC:{:04X} │ Cycles:{} │ {}",
        state, fmt_hz(spd), pc, cycles, timing_str
    );
    f.render_widget(
        Paragraph::new(title).style(Style::default().bg(Color::DarkGray).fg(timing_color)),
        area,
    );
}

fn draw_content(f: &mut Frame, app: &mut App, area: Rect) {
    let cols = Layout::default()
        .direction(Direction::Horizontal)
        .constraints([Constraint::Percentage(55), Constraint::Percentage(45)])
        .split(area);

    draw_terminal(f, app, cols[0]);

    let right = Layout::default()
        .direction(Direction::Vertical)
        .constraints([Constraint::Length(15), Constraint::Min(5)])
        .split(cols[1]);

    draw_right_panel(f, app, right[0]);
    draw_memory(f, app, right[1]);
}

fn draw_terminal(f: &mut Frame, app: &App, area: Rect) {
    let inner_h = area.height.saturating_sub(2) as usize;
    let scroll = app.term_scroll;

    let mut lines: Vec<Line> = app.term_lines.iter()
        .map(|l| Line::from(l.as_str()))
        .collect();
    lines.push(Line::from(format!("{}_", app.term_cur)));

    let start = if lines.len() > inner_h {
        let max = lines.len() - inner_h;
        max.saturating_sub(scroll)
    } else {
        0
    };
    let display: Vec<Line> = lines[start..].iter().take(inner_h).cloned().collect();

    let block = Block::default()
        .title(" SERIAL TERMINAL (6551) ")
        .borders(Borders::ALL)
        .border_style(Style::default().fg(Color::Green));
    f.render_widget(
        Paragraph::new(Text::from(display)).block(block).wrap(Wrap { trim: false }),
        area,
    );
}

// ── Right panel (tabbed: CPU / VIA1 / VIA2 / ACIA / IRQ) ─────────────────────

fn draw_right_panel(f: &mut Frame, app: &mut App, area: Rect) {
    let tabs_area  = Rect { height: 1, ..area };
    let block_area = Rect { y: area.y + 1, height: area.height.saturating_sub(1), ..area };

    let labels: Vec<Line> = RightTab::ALL.iter().map(|t| Line::from(t.label())).collect();
    let sel_idx = RightTab::ALL.iter().position(|t| *t == app.right_tab).unwrap_or(0);
    f.render_widget(
        Tabs::new(labels)
            .select(sel_idx)
            .style(Style::default().fg(Color::DarkGray))
            .highlight_style(Style::default().fg(Color::White).add_modifier(Modifier::BOLD)),
        tabs_area,
    );

    match app.right_tab {
        RightTab::Cpu  => draw_cpu_panel(f, app, block_area),
        RightTab::Via1 => draw_via_panel(f, app, block_area, true),
        RightTab::Via2 => draw_via_panel(f, app, block_area, false),
        RightTab::Acia => draw_acia_panel(f, app, block_area),
        RightTab::Irq  => draw_irq_panel(f, app, block_area),
        RightTab::Vdp  => draw_vdp_panel(f, app, block_area),
        RightTab::Saa  => draw_saa_panel(f, app, block_area),
    }
}

fn draw_cpu_panel(f: &mut Frame, app: &App, area: Rect) {
    let cpu = match app.shared.try_lock() {
        Ok(s) => s.cpu.clone(),
        Err(_) => CpuState::default(),
    };

    let p = cpu.p;
    let flags = format!("{}{}{}{}{}{}{}{}",
        if p & 0x80 != 0 { 'N' } else { 'n' },
        if p & 0x40 != 0 { 'V' } else { 'v' },
        '-',
        if p & 0x10 != 0 { 'B' } else { 'b' },
        if p & 0x08 != 0 { 'D' } else { 'd' },
        if p & 0x04 != 0 { 'I' } else { 'i' },
        if p & 0x02 != 0 { 'Z' } else { 'z' },
        if p & 0x01 != 0 { 'C' } else { 'c' },
    );
    let halt = if cpu.halted { " [STP]" } else if cpu.waiting { " [WAI]" } else { "" };

    let text = vec![
        Line::from(vec![
            Span::styled(" PC ", Style::default().fg(Color::Yellow)),
            Span::raw(format!("{:04X}  ", cpu.pc)),
            Span::styled("A ", Style::default().fg(Color::Yellow)),
            Span::raw(format!("{:02X}  ", cpu.a)),
            Span::styled("X ", Style::default().fg(Color::Yellow)),
            Span::raw(format!("{:02X}  ", cpu.x)),
            Span::styled("Y ", Style::default().fg(Color::Yellow)),
            Span::raw(format!("{:02X}", cpu.y)),
        ]),
        Line::from(vec![
            Span::styled(" SP ", Style::default().fg(Color::Yellow)),
            Span::raw(format!("{:02X}   ", cpu.sp)),
            Span::styled("P  ", Style::default().fg(Color::Yellow)),
            Span::raw(format!("{:02X}  {}{}", cpu.p, flags, halt)),
        ]),
        Line::from(""),
        Line::from(Span::styled(" NV-BDIZC", Style::default().fg(Color::DarkGray))),
        Line::from(vec![
            Span::raw(" "),
            Span::styled(&flags, Style::default().fg(Color::Cyan).add_modifier(Modifier::BOLD)),
        ]),
        Line::from(""),
        Line::from(vec![
            Span::styled(" Cycles ", Style::default().fg(Color::DarkGray)),
            Span::raw(cpu.cycles.to_string()),
        ]),
    ];

    f.render_widget(
        Paragraph::new(text)
            .block(Block::default().title(" CPU REGISTERS ").borders(Borders::ALL)
                .border_style(Style::default().fg(Color::Cyan))),
        area,
    );
}

fn draw_memory(f: &mut Frame, app: &mut App, area: Rect) {
    // Tab bar above the block
    let tabs_area   = Rect { height: 1, ..area };
    let block_area  = Rect { y: area.y + 1, height: area.height.saturating_sub(1), ..area };
    let content_h   = block_area.height.saturating_sub(2) as usize; // inner (excl. borders)

    let tab_labels: Vec<Line> = MemTab::ALL.iter().map(|t| Line::from(t.label())).collect();
    f.render_widget(
        Tabs::new(tab_labels)
            .select(app.current_tab_idx())
            .style(Style::default().fg(Color::DarkGray))
            .highlight_style(Style::default().fg(Color::White).add_modifier(Modifier::BOLD)),
        tabs_area,
    );

    let bytes_per_row = 8usize;
    let base          = app.mem_tab.base(app.custom_addr);
    let offset        = app.mem_scroll * bytes_per_row;
    let show_bytes    = content_h * bytes_per_row;

    let data: Vec<u8> = if let Ok(mut st) = app.shared.try_lock() {
        st.bus.dump(base.wrapping_add(offset as u16), show_bytes)
    } else {
        vec![0xFF; show_bytes]
    };

    let mut lines: Vec<Line> = Vec::new();
    for row in 0..content_h {
        let row_addr = base.wrapping_add((offset + row * bytes_per_row) as u16);
        let start    = row * bytes_per_row;
        let end      = (start + bytes_per_row).min(data.len());
        let slice    = &data[start..end];

        let mut spans = vec![
            Span::styled(format!("{:04X}: ", row_addr), Style::default().fg(Color::Yellow)),
        ];
        let mut ascii = String::new();
        for (i, b) in slice.iter().enumerate() {
            spans.push(Span::styled(format!("{:02X} ", b), Style::default().fg(Color::White)));
            ascii.push(if *b >= 0x20 && *b < 0x7F { *b as char } else { '.' });
            if i == 3 { spans.push(Span::raw(" ")); }
        }
        spans.push(Span::styled(format!(" {}", ascii), Style::default().fg(Color::DarkGray)));
        lines.push(Line::from(spans));
    }

    f.render_widget(
        Paragraph::new(lines)
            .block(Block::default()
                .title(format!(" MEMORY [{:#06X}] ", base))
                .borders(Borders::ALL)
                .border_style(Style::default().fg(Color::Blue))),
        block_area,
    );
}

fn draw_status(f: &mut Frame, app: &App, area: Rect) {
    let (nmi, irq, v1, v2, ast) = if let Ok(st) = app.shared.try_lock() {
        (st.nmi, st.irq, st.bus.via1.t1_counter, st.bus.via2.t1_counter, st.bus.acia.status)
    } else {
        (false, false, 0, 0, 0)
    };

    let msg = format!(
        " NMI:{} IRQ:{} │ VIA1-T1:{:04X} VIA2-T1:{:04X} │ ACIA:{:02X} │ {}",
        if nmi { "!" } else { "-" },
        if irq { "!" } else { "-" },
        v1, v2, ast, app.status_msg
    );
    f.render_widget(
        Paragraph::new(msg).style(Style::default().bg(Color::DarkGray).fg(Color::Gray)),
        area,
    );
}

// ── VIA panel ─────────────────────────────────────────────────────────────────

fn via_flag_str(v: u8) -> String {
    format!("T1:{} T2:{} CB1:{} CB2:{} SR:{} CA1:{} CA2:{}",
        (v >> 6) & 1, (v >> 5) & 1, (v >> 4) & 1,
        (v >> 3) & 1, (v >> 2) & 1, (v >> 1) & 1, v & 1)
}

fn draw_via_panel(f: &mut Frame, app: &App, area: Rect, is_via1: bool) {
    let (title, border_color) = if is_via1 {
        (" VIA1 $CC00  IC18 — NMI ", Color::Yellow)
    } else {
        (" VIA2 $CC80  IC16 — IRQ1 ", Color::Magenta)
    };

    let text: Vec<Line> = if let Ok(st) = app.shared.try_lock() {
        let via = if is_via1 { &st.bus.via1 } else { &st.bus.via2 };
        let freerun  = if via.acr & 0x40 != 0 { "free-run" } else { "one-shot" };
        let irq_out  = via.irq();
        vec![
            Line::from(vec![
                Span::styled(" ORA:", Style::default().fg(Color::Yellow)),
                Span::raw(format!("{:02X}  ", via.ora)),
                Span::styled("DDRA:", Style::default().fg(Color::DarkGray)),
                Span::raw(format!("{:02X}   ", via.ddra)),
                Span::styled("ORB:", Style::default().fg(Color::Yellow)),
                Span::raw(format!("{:02X}  ", via.orb)),
                Span::styled("DDRB:", Style::default().fg(Color::DarkGray)),
                Span::raw(format!("{:02X}", via.ddrb)),
            ]),
            Line::from(vec![
                Span::styled(" T1:", Style::default().fg(Color::Cyan)),
                Span::raw(format!(" cnt:{:04X}  latch:{:04X}  {}", via.t1_counter, via.t1_latch,
                    if via.t1_running { "run" } else { "---" })),
                Span::styled(format!("  {}", freerun), Style::default().fg(Color::DarkGray)),
            ]),
            Line::from(vec![
                Span::styled(" T2:", Style::default().fg(Color::Cyan)),
                Span::raw(format!(" cnt:{:04X}  {}", via.t2_counter,
                    if via.t2_running { "run" } else { "---" })),
            ]),
            Line::from(vec![
                Span::styled(" ACR:", Style::default().fg(Color::DarkGray)),
                Span::raw(format!("{:02X}  ", via.acr)),
                Span::styled("PCR:", Style::default().fg(Color::DarkGray)),
                Span::raw(format!("{:02X}  ", via.pcr)),
                Span::styled("SR:", Style::default().fg(Color::DarkGray)),
                Span::raw(format!("{:02X}", via.sr)),
            ]),
            Line::from(vec![
                Span::styled(" IFR:", Style::default().fg(Color::DarkGray)),
                Span::raw(format!("{:02X}  ", via.ifr)),
                Span::styled(
                    format!("[{}]", via_flag_str(via.ifr)),
                    Style::default().fg(if via.ifr & 0x80 != 0 { Color::Red } else { Color::DarkGray }),
                ),
            ]),
            Line::from(vec![
                Span::styled(" IER:", Style::default().fg(Color::DarkGray)),
                Span::raw(format!("{:02X}  ", via.ier)),
                Span::styled(format!("[{}]", via_flag_str(via.ier)), Style::default().fg(Color::DarkGray)),
            ]),
            Line::from(""),
            Line::from(vec![
                Span::styled(" Výstup: ", Style::default().fg(Color::DarkGray)),
                Span::styled(
                    if irq_out { if is_via1 { "NMI !" } else { "IRQ !" } }
                    else { "---" },
                    Style::default().fg(if irq_out { Color::Red } else { Color::DarkGray })
                        .add_modifier(if irq_out { Modifier::BOLD } else { Modifier::empty() }),
                ),
            ]),
        ]
    } else {
        vec![Line::from(" [CPU thread běží — zkus znovu] ")]
    };

    f.render_widget(
        Paragraph::new(text)
            .block(Block::default().title(title).borders(Borders::ALL)
                .border_style(Style::default().fg(border_color))),
        area,
    );
}

// ── ACIA panel ────────────────────────────────────────────────────────────────

fn draw_acia_panel(f: &mut Frame, app: &App, area: Rect) {
    let text: Vec<Line> = if let Ok(st) = app.shared.try_lock() {
        let a = &st.bus.acia;
        let baud = if a.baud_divider > 0 { 1_000_000 / a.baud_divider } else { 0 };
        let word_bits = match (a.control >> 5) & 0x03 {
            0 => 8u8, 1 => 7, 2 => 6, _ => 5,
        };
        let stop_bits = if a.control & 0x80 != 0 { 2u8 } else { 1 };
        let parity = match (a.control >> 5) & 0x07 {
            3 => "O", 5 => "E", _ => "N",
        };
        let rxirq_mode = match (a.command >> 1) & 0x03 {
            0 => "off", 1 => "on ", 2 => "on+RTS↓", 3 => "on(brk)",
            _ => "???",
        };
        vec![
            Line::from(vec![
                Span::styled(" STATUS:  ", Style::default().fg(Color::Yellow)),
                Span::raw(format!("${:02X}  ", a.status)),
                Span::styled(
                    format!("IRQ:{}  TDRE:{}  RDRF:{}  OVRN:{}",
                        (a.status >> 7) & 1,
                        (a.status >> 4) & 1,
                        (a.status >> 3) & 1,
                        (a.status >> 2) & 1,
                    ),
                    Style::default().fg(if a.status & 0x88 != 0 { Color::Red } else { Color::DarkGray }),
                ),
            ]),
            Line::from(vec![
                Span::styled(" COMMAND: ", Style::default().fg(Color::DarkGray)),
                Span::raw(format!("${:02X}  ", a.command)),
                Span::styled(
                    format!("RxIRQ:{}  RTS:{}  DTR:{}",
                        rxirq_mode,
                        (a.command >> 3) & 1,
                        a.command & 1,
                    ),
                    Style::default().fg(Color::DarkGray),
                ),
            ]),
            Line::from(vec![
                Span::styled(" CONTROL: ", Style::default().fg(Color::DarkGray)),
                Span::raw(format!("${:02X}  ", a.control)),
                Span::styled(
                    format!("{} Bd  {}{}{}",
                        baud, word_bits, parity, stop_bits),
                    Style::default().fg(Color::Cyan),
                ),
            ]),
            Line::from(vec![
                Span::styled(" RX DATA: ", Style::default().fg(Color::DarkGray)),
                Span::raw(format!("${:02X} '{}'  rdrf:{}  irq_pend:{}",
                    a.rx_data,
                    if a.rx_data >= 0x20 && a.rx_data < 0x7F { a.rx_data as char } else { '.' },
                    a.rdrf as u8, a.irq_pending as u8,
                )),
            ]),
            Line::from(vec![
                Span::styled(" baud_div:", Style::default().fg(Color::DarkGray)),
                Span::raw(format!(" {}  (~{} Bd @ 1 MHz clk)", a.baud_divider, baud)),
            ]),
        ]
    } else {
        vec![Line::from(" [CPU thread běží — zkus znovu] ")]
    };

    f.render_widget(
        Paragraph::new(text)
            .block(Block::default()
                .title(" ACIA $C800  IC19 — R6551 ")
                .borders(Borders::ALL)
                .border_style(Style::default().fg(Color::Green))),
        area,
    );
}

// ── IRQ latch panel ───────────────────────────────────────────────────────────

fn draw_irq_panel(f: &mut Frame, app: &App, area: Rect) {
    const SOURCES: &[(&str, u8)] = &[
        ("ACIA   IRQ0", 0),
        ("VIA2   IRQ1", 1),
        ("ISA DEV0   ", 2),
        ("ISA DEV1   ", 3),
        ("ISA DEV2   ", 4),
        ("ISA EXT    ", 5),
        ("ISA ?      ", 6),
        ("S1 btn IRQ7", 7),
    ];

    let text: Vec<Line> = if let Ok(st) = app.shared.try_lock() {
        let latch = &st.bus.irq_latch;
        let active = latch.active;
        let encoded = latch.read_encoded();

        let mut lines = vec![
            Line::from(vec![
                Span::styled(" Active: ", Style::default().fg(Color::Yellow)),
                Span::raw(format!("${:02X}   ", active)),
                Span::styled(
                    if active != 0 { "[ IRQ ACTIVE ]" } else { "[ žádný IRQ  ]" },
                    Style::default().fg(if active != 0 { Color::Red } else { Color::DarkGray })
                        .add_modifier(if active != 0 { Modifier::BOLD } else { Modifier::empty() }),
                ),
            ]),
            Line::from(""),
        ];

        for (name, bit) in SOURCES {
            let set = active & (1 << bit) != 0;
            lines.push(Line::from(vec![
                Span::raw(format!("  [{}] ", bit)),
                Span::styled(
                    format!("{}", name),
                    Style::default().fg(if set { Color::White } else { Color::DarkGray }),
                ),
                Span::styled(
                    if set { "  ●  AKTIVNÍ" } else { "  ·" },
                    Style::default().fg(if set { Color::Red } else { Color::DarkGray })
                        .add_modifier(if set { Modifier::BOLD } else { Modifier::empty() }),
                ),
            ]));
        }

        lines.push(Line::from(""));
        lines.push(Line::from(vec![
            Span::styled(" Enkodér: ", Style::default().fg(Color::DarkGray)),
            Span::raw(format!("${:02X}  priorita={}", encoded, encoded & 0x07)),
        ]));
        lines
    } else {
        vec![Line::from(" [CPU thread běží] ")]
    };

    f.render_widget(
        Paragraph::new(text)
            .block(Block::default()
                .title(" IRQ Latch $C400 — IC17+IC27 ")
                .borders(Borders::ALL)
                .border_style(Style::default().fg(Color::Red))),
        area,
    );
}

// ── VDP panel ─────────────────────────────────────────────────────────────────

fn draw_vdp_panel(f: &mut Frame, app: &App, area: Rect) {
    let text: Vec<Line> = if let Ok(st) = app.shared.try_lock() {
        let v = &st.bus.vdp;
        let irq_str = if v.irq { "VBlank !" } else { "---" };
        vec![
            Line::from(vec![
                Span::styled(" Mode:  ", Style::default().fg(Color::Yellow)),
                Span::raw(v.mode_str()),
                Span::styled("  Screen:", Style::default().fg(Color::DarkGray)),
                Span::styled(
                    if v.screen_enabled() { " ON " } else { " OFF" },
                    Style::default().fg(if v.screen_enabled() { Color::Green } else { Color::DarkGray }),
                ),
            ]),
            Line::from(vec![
                Span::styled(" Status: ", Style::default().fg(Color::DarkGray)),
                Span::raw(format!("${:02X}  ", v.status)),
                Span::styled(
                    irq_str,
                    Style::default().fg(if v.irq { Color::Red } else { Color::DarkGray })
                        .add_modifier(if v.irq { Modifier::BOLD } else { Modifier::empty() }),
                ),
                Span::styled("  IRQ_EN:", Style::default().fg(Color::DarkGray)),
                Span::raw(if v.irq_enabled() { "1" } else { "0" }),
            ]),
            Line::from(vec![
                Span::styled(" VRAMptr:", Style::default().fg(Color::DarkGray)),
                Span::raw(format!("${:04X}", v.vram_addr)),
            ]),
            Line::from(""),
            Line::from(vec![
                Span::styled(" R0:", Style::default().fg(Color::DarkGray)),
                Span::raw(format!("{:02X}  ", v.regs[0])),
                Span::styled("R1:", Style::default().fg(Color::DarkGray)),
                Span::raw(format!("{:02X}  ", v.regs[1])),
                Span::styled("R2:", Style::default().fg(Color::DarkGray)),
                Span::raw(format!("{:02X}  ", v.regs[2])),
                Span::styled("R3:", Style::default().fg(Color::DarkGray)),
                Span::raw(format!("{:02X}", v.regs[3])),
            ]),
            Line::from(vec![
                Span::styled(" R4:", Style::default().fg(Color::DarkGray)),
                Span::raw(format!("{:02X}  ", v.regs[4])),
                Span::styled("R5:", Style::default().fg(Color::DarkGray)),
                Span::raw(format!("{:02X}  ", v.regs[5])),
                Span::styled("R6:", Style::default().fg(Color::DarkGray)),
                Span::raw(format!("{:02X}  ", v.regs[6])),
                Span::styled("R7:", Style::default().fg(Color::DarkGray)),
                Span::raw(format!("{:02X}", v.regs[7])),
            ]),
            Line::from(""),
            Line::from(vec![
                Span::styled(" Name:   ", Style::default().fg(Color::DarkGray)),
                Span::raw(format!("${:04X}", v.name_table_addr())),
                Span::styled("  Color: ", Style::default().fg(Color::DarkGray)),
                Span::raw(format!("${:04X}", v.color_table_addr())),
            ]),
            Line::from(vec![
                Span::styled(" Pattern:", Style::default().fg(Color::DarkGray)),
                Span::raw(format!("${:04X}", v.pattern_gen_addr())),
                Span::styled("  SprAt: ", Style::default().fg(Color::DarkGray)),
                Span::raw(format!("${:04X}", v.sprite_attr_addr())),
            ]),
            Line::from(vec![
                Span::styled(" SprPat: ", Style::default().fg(Color::DarkGray)),
                Span::raw(format!("${:04X}", v.sprite_pat_addr())),
            ]),
        ]
    } else {
        vec![Line::from(" [CPU thread běží] ")]
    };

    f.render_widget(
        Paragraph::new(text)
            .block(Block::default()
                .title(" VDP $C000  TMS9918A (EXP_TMS9918A_V1) ")
                .borders(Borders::ALL)
                .border_style(Style::default().fg(Color::LightBlue))),
        area,
    );
}

// ── SAA1099 panel ──────────────────────────────────────────────────────────────

fn draw_saa_panel(f: &mut Frame, app: &App, area: Rect) {
    let text: Vec<Line> = if let Ok(st) = app.shared.try_lock() {
        let s = &st.bus.saa;
        let mut lines = vec![
            Line::from(vec![
                Span::styled(" Addr:   ", Style::default().fg(Color::DarkGray)),
                Span::raw(format!("${:02X}  ", s.addr)),
                Span::styled("Tone_EN:", Style::default().fg(Color::DarkGray)),
                Span::raw(format!("{:06b}  ", s.tone_enable)),
                Span::styled("Noise_EN:", Style::default().fg(Color::DarkGray)),
                Span::raw(format!("{:06b}", s.noise_enable)),
            ]),
            Line::from(vec![
                Span::styled(" Envelope:", Style::default().fg(Color::DarkGray)),
                Span::raw(format!(" EG0: {}  EG1: {}",
                    s.envelope_shape_str(0), s.envelope_shape_str(1))),
            ]),
            Line::from(""),
            Line::from(vec![
                Span::styled(" Ch ", Style::default().fg(Color::Yellow)),
                Span::styled(" Freq(Hz) ", Style::default().fg(Color::DarkGray)),
                Span::styled(" Amp L ", Style::default().fg(Color::DarkGray)),
                Span::styled(" Amp R ", Style::default().fg(Color::DarkGray)),
                Span::styled(" T N", Style::default().fg(Color::DarkGray)),
            ]),
        ];

        for ch in 0..6usize {
            let freq  = s.channel_freq_hz(ch);
            let amp_l = (s.amplitude[ch] & 0x0F) as usize;
            let amp_r = (s.amplitude[ch] >> 4)   as usize;
            let tone  = if s.channel_enabled(ch) { '●' } else { '·' };
            let noise = if s.noise_on_channel(ch) { '●' } else { '·' };
            // VU bar (0..15 → 0..8 chars)
            let bar_l: String = "█".repeat(amp_l / 2).chars().take(8).collect();
            let bar_r: String = "█".repeat(amp_r / 2).chars().take(8).collect();
            let active = s.channel_enabled(ch) && amp_l.max(amp_r) > 0;
            let style  = if active { Style::default().fg(Color::Cyan) }
                         else      { Style::default().fg(Color::DarkGray) };
            lines.push(Line::from(vec![
                Span::styled(format!(" {:1}  ", ch), Style::default().fg(Color::Yellow)),
                Span::styled(format!("{:8.1}  ", freq), style),
                Span::styled(format!("{:<8} ", bar_l), Style::default().fg(Color::Green)),
                Span::styled(format!("{:<8} ", bar_r), Style::default().fg(Color::LightBlue)),
                Span::styled(format!("{} {}", tone, noise), style),
            ]));
        }
        lines
    } else {
        vec![Line::from(" [CPU thread běží] ")]
    };

    f.render_widget(
        Paragraph::new(text)
            .block(Block::default()
                .title(" SAA1099 $CD00  (ISA DEV0) ")
                .borders(Borders::ALL)
                .border_style(Style::default().fg(Color::Magenta))),
        area,
    );
}

// ── EditMem modal ─────────────────────────────────────────────────────────────

fn draw_edit_mem(f: &mut Frame, app: &mut App, area: Rect) {
    let (phase, addr_buf, val_buf) = match &app.modal {
        Modal::EditMem { phase, addr_buf, val_buf } =>
            (*phase, addr_buf.clone(), val_buf.clone()),
        _ => return,
    };

    // Peek current byte if address is complete (4 hex digits)
    let cur_val: Option<u8> = if addr_buf.len() == 4 {
        if let Ok(a) = u16::from_str_radix(&addr_buf, 16) {
            if let Ok(mut st) = app.shared.try_lock() {
                Some(st.bus.dump(a, 1)[0])
            } else { None }
        } else { None }
    } else { None };

    let popup = centered_rect(50, 0, 44, 9, area);
    f.render_widget(Clear, popup);

    let mut lines = vec![Line::from("")];
    if !phase {
        lines.push(Line::from(format!(
            "  Adresa: ${:_<4}{}",
            addr_buf,
            cur_val.map(|v| format!("   [=${:02X}]", v)).unwrap_or_default(),
        )));
        lines.push(Line::from(""));
        lines.push(Line::from(Span::styled(
            "  Enter=Potvrdit  Esc=Zrušit  0-9/A-F=hex",
            Style::default().fg(Color::DarkGray),
        )));
    } else {
        lines.push(Line::from(format!(
            "  Adresa: ${}   [=${:02X}]",
            addr_buf, cur_val.unwrap_or(0),
        )));
        lines.push(Line::from(format!("  Hodnota: ${:_<2}", val_buf)));
        lines.push(Line::from(""));
        lines.push(Line::from(Span::styled(
            "  Enter=Zapsat  Esc=Zpět  0-9/A-F=hex",
            Style::default().fg(Color::DarkGray),
        )));
    }

    f.render_widget(
        Paragraph::new(lines)
            .block(Block::default()
                .title(" Editace paměti — Ctrl+M ")
                .borders(Borders::ALL)
                .border_style(Style::default().fg(Color::Cyan))),
        popup,
    );
}

// ── EditReg modal ─────────────────────────────────────────────────────────────

const REG_NAMES:  &[&str]  = &["A", "X", "Y", "SP", "PC", "P"];
const REG_IS16:   &[bool]  = &[false, false, false, false, true, false];

fn draw_edit_reg(f: &mut Frame, app: &App, area: Rect) {
    let (sel, val_buf) = match &app.modal {
        Modal::EditReg { sel, val_buf } => (*sel, val_buf.as_str()),
        _ => return,
    };

    let cpu = match app.shared.try_lock() {
        Ok(s) => s.cpu.clone(),
        Err(_) => CpuState::default(),
    };

    let reg_vals: [u16; 6] = [
        cpu.a as u16, cpu.x as u16, cpu.y as u16,
        cpu.sp as u16, cpu.pc, cpu.p as u16,
    ];

    let popup = centered_rect(55, 0, 48, 11, area);
    f.render_widget(Clear, popup);

    let mut lines = vec![Line::from("")];
    for i in 0..REG_NAMES.len() {
        let is16 = REG_IS16[i];
        let cur  = if is16 { format!("${:04X}", reg_vals[i]) }
                   else    { format!("${:02X}",  reg_vals[i] as u8) };

        let max_len = if is16 { 4 } else { 2 };
        let extra = if i == 5 {
            let p = cpu.p;
            format!("  {}{}·{}{}{}{}{}",
                if p & 0x80 != 0 { 'N' } else { 'n' },
                if p & 0x40 != 0 { 'V' } else { 'v' },
                if p & 0x10 != 0 { 'B' } else { 'b' },
                if p & 0x08 != 0 { 'D' } else { 'd' },
                if p & 0x04 != 0 { 'I' } else { 'i' },
                if p & 0x02 != 0 { 'Z' } else { 'z' },
                if p & 0x01 != 0 { 'C' } else { 'c' },
            )
        } else { String::new() };

        let arrow = if i == sel { "▶" } else { " " };

        let mut spans = vec![
            Span::styled(
                format!(" {} {:2} = ", arrow, REG_NAMES[i]),
                if i == sel { Style::default().fg(Color::White).add_modifier(Modifier::BOLD) }
                else { Style::default().fg(Color::DarkGray) },
            ),
            Span::styled(
                cur,
                if i == sel { Style::default().fg(Color::Yellow) }
                else { Style::default().fg(Color::White) },
            ),
            Span::raw(extra),
        ];
        if i == sel && !val_buf.is_empty() {
            let padded = format!("{:_<width$}", val_buf, width = max_len);
            spans.push(Span::styled(
                format!("  ← ${}", padded),
                Style::default().fg(Color::Cyan).add_modifier(Modifier::BOLD),
            ));
        } else if i == sel {
            spans.push(Span::styled(
                format!("  ← ${:_<width$}", "", width = max_len),
                Style::default().fg(Color::DarkGray),
            ));
        }
        lines.push(Line::from(spans));
    }
    lines.push(Line::from(""));
    lines.push(Line::from(Span::styled(
        " ↑↓=Reg  0-9/A-F=Hodnota  Enter=Nastavit  Esc=Zrušit",
        Style::default().fg(Color::DarkGray),
    )));

    f.render_widget(
        Paragraph::new(lines)
            .block(Block::default()
                .title(" Nastavení registrů CPU — Ctrl+R ")
                .borders(Borders::ALL)
                .border_style(Style::default().fg(Color::Cyan))),
        popup,
    );
}

// ── File browser modal ────────────────────────────────────────────────────────

fn draw_file_browser(f: &mut Frame, app: &mut App, area: Rect) {
    let Modal::FileBrowser(ref fb) = app.modal else { return };

    // Centered popup: 70% wide, 60% tall, min 50×20
    let popup = centered_rect(70, 60, 50, 20, area);

    // Visible rows inside the list (minus borders + header + footer)
    let visible = popup.height.saturating_sub(4) as usize;

    // Build list items
    let items: Vec<ListItem> = fb.entries.iter().map(|e| {
        let (icon, style) = if e.is_dir {
            ("📁 ", Style::default().fg(Color::Yellow))
        } else {
            ("   ", Style::default().fg(Color::White))
        };
        ListItem::new(Line::from(vec![
            Span::styled(icon, style),
            Span::styled(&e.name, style),
        ]))
    }).collect();

    let dir_str = fb.dir.to_string_lossy();
    let title = format!(" Open ROM  {}  ", dir_str);
    let footer = " ↑↓=Navigate  Enter=Open/Load  Esc=Cancel ";

    let mut list_state = ListState::default();
    list_state.select(Some(fb.selected));

    // Error line if present
    let error_line = fb.error.as_deref().unwrap_or("");

    // Clear background, then render block, then list
    f.render_widget(Clear, popup);

    let block = Block::default()
        .title(title)
        .title_bottom(Line::from(footer).alignment(Alignment::Center))
        .borders(Borders::ALL)
        .border_style(Style::default().fg(Color::Cyan));

    // Inner area for list (leave room for error line at bottom)
    let inner = block.inner(popup);
    f.render_widget(block, popup);

    // Split inner: list | error (1 row)
    let inner_parts = Layout::default()
        .direction(Direction::Vertical)
        .constraints([Constraint::Min(1), Constraint::Length(if error_line.is_empty() { 0 } else { 1 })])
        .split(inner);

    // Render the list with scroll offset applied via ListState
    // ratatui's List scrolls automatically to the selected item
    let list = List::new(items)
        .highlight_style(
            Style::default().bg(Color::Blue).fg(Color::White).add_modifier(Modifier::BOLD),
        )
        .highlight_symbol("▶ ");

    // We need to offset the list state scroll manually
    // ratatui ListState::offset controls the scroll position
    let mut ls = ListState::default();
    ls.select(Some(fb.selected));
    *ls.offset_mut() = fb.scroll;

    f.render_stateful_widget(list, inner_parts[0], &mut ls);

    if !error_line.is_empty() {
        f.render_widget(
            Paragraph::new(error_line).style(Style::default().fg(Color::Red)),
            inner_parts[1],
        );
    }

    let _ = visible;
}

// ── Load target modal ─────────────────────────────────────────────────────────

fn draw_load_target(f: &mut Frame, app: &App, area: Rect) {
    let Modal::LoadTarget { ref data, ref filename, selected, ref custom_buf } = app.modal
    else { return };

    // +1 for "Vlastní adresa" entry + 1 for optional custom input row
    let list_len   = TARGETS.len() + 1;
    let extra_row  = if custom_buf.is_some() { 1u16 } else { 0 };
    let popup_h    = (list_len as u16 + 4 + extra_row).max(10);
    let popup      = centered_rect(65, 0, 54, popup_h, area);

    f.render_widget(Clear, popup);

    let title  = format!(" Načíst: {}  ({} B) ", filename, data.len());
    let footer = " ↑↓=Vybrat  Enter=Načíst  Esc=Zpět  C=Vlastní adresa ";

    let block = Block::default()
        .title(title)
        .title_bottom(Line::from(footer).alignment(Alignment::Center))
        .borders(Borders::ALL)
        .border_style(Style::default().fg(Color::Magenta));

    let inner = block.inner(popup);
    f.render_widget(block, popup);

    // Build list items
    let mut items: Vec<ListItem> = TARGETS.iter().enumerate().map(|(i, t)| {
        let reset_tag = if t.reset { "  ↺ reset" } else { "" };
        let style = if i == selected {
            Style::default().fg(Color::Black).bg(Color::Magenta).add_modifier(Modifier::BOLD)
        } else {
            Style::default().fg(Color::White)
        };
        ListItem::new(Line::from(vec![
            Span::styled(format!(" {:5}  ", t.label), Style::default()
                .fg(if i == selected { Color::Black } else { Color::Yellow })
                .bg(if i == selected { Color::Magenta } else { Color::Reset })),
            Span::styled(format!("{}{}", t.desc, reset_tag), style),
        ]))
    }).collect();

    // "Vlastní adresa" entry
    let custom_idx = TARGETS.len();
    let custom_sel = selected == custom_idx;
    let custom_style = if custom_sel {
        Style::default().fg(Color::Black).bg(Color::Magenta).add_modifier(Modifier::BOLD)
    } else {
        Style::default().fg(Color::White)
    };
    items.push(ListItem::new(Line::from(vec![
        Span::styled(" ....  ", Style::default()
            .fg(if custom_sel { Color::Black } else { Color::Yellow })
            .bg(if custom_sel { Color::Magenta } else { Color::Reset })),
        Span::styled("Vlastní adresa", custom_style),
    ])));

    // Split inner area: list | optional custom input row
    let (list_area, input_area) = if custom_buf.is_some() {
        let parts = Layout::default()
            .direction(Direction::Vertical)
            .constraints([Constraint::Min(1), Constraint::Length(1)])
            .split(inner);
        (parts[0], Some(parts[1]))
    } else {
        (inner, None)
    };

    f.render_widget(List::new(items), list_area);

    // Custom address input row
    if let (Some(buf), Some(ia)) = (custom_buf, input_area) {
        let input_text = format!("  Hex adresa: ${:<4}  (Enter=OK  Esc=Zrušit)", buf);
        f.render_widget(
            Paragraph::new(input_text)
                .style(Style::default().fg(Color::Yellow).bg(Color::DarkGray)),
            ia,
        );
    }
}

fn handle_load_target_key(app: &mut App, key: KeyEvent) {
    // Borrow helper to get mutable refs to the modal fields
    let Modal::LoadTarget { ref mut selected, ref mut custom_buf, .. } = app.modal
    else { return };

    let total = TARGETS.len() + 1; // +1 for Custom entry
    let custom_idx = TARGETS.len();

    // If we're in custom address input mode
    if custom_buf.is_some() {
        match key.code {
            KeyCode::Esc => { *custom_buf = None; }
            KeyCode::Backspace => {
                if let Some(buf) = custom_buf { buf.pop(); }
            }
            KeyCode::Char(c) if c.is_ascii_hexdigit() => {
                if let Some(buf) = custom_buf {
                    if buf.len() < 4 { buf.push(c.to_ascii_uppercase()); }
                }
            }
            KeyCode::Enter => {
                // Parse and load at custom address
                let addr_str = custom_buf.take().unwrap_or_default();
                let addr = u16::from_str_radix(addr_str.trim(), 16).unwrap_or(0xE000);
                do_load(app, addr, false);
            }
            _ => {}
        }
        return;
    }

    // Normal list navigation
    match key.code {
        KeyCode::Esc => {
            // Go back to file browser in same directory
            let start = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
            app.modal = Modal::FileBrowser(FileBrowser::open(&start));
        }
        KeyCode::Up   => { if *selected > 0 { *selected -= 1; } }
        KeyCode::Down => { if *selected + 1 < total { *selected += 1; } }

        KeyCode::Char('c') | KeyCode::Char('C') => {
            *selected = custom_idx;
            *custom_buf = Some(String::new());
        }

        KeyCode::Enter => {
            let sel = *selected;
            if sel == custom_idx {
                // Open custom address input
                *custom_buf = Some(String::new());
            } else {
                let t = &TARGETS[sel];
                let addr  = t.addr;
                let reset = t.reset;
                do_load(app, addr, reset);
            }
        }
        _ => {}
    }
}

/// Extract data+filename from LoadTarget modal and send the Cmd.
fn do_load(app: &mut App, addr: u16, reset: bool) {
    // Take the modal out, extract data and filename
    let taken = std::mem::replace(&mut app.modal, Modal::None);
    let Modal::LoadTarget { data, filename, .. } = taken else { return };

    let label = if addr >= 0xE000 { "ROM" } else { "RAM" };
    app.status_msg = format!(
        "Načteno {} B ({}) → {} ${:04X}{}",
        data.len(), filename, label, addr,
        if reset { "  [reset]" } else { "" }
    );
    let _ = app.cmd_tx.send(Cmd::LoadAt { data, addr, reset });
    // app.modal is already Modal::None
}

// ── Goto address modal ────────────────────────────────────────────────────────

fn draw_goto_addr(f: &mut Frame, app: &App, area: Rect) {
    let buf = match &app.modal {
        Modal::GotoAddr { buf } => buf.as_str(),
        _ => return,
    };

    let popup = centered_rect(40, 0, 40, 5, area);
    f.render_widget(Clear, popup);

    let text = format!(" Hex adresa: {:_<4}", buf);
    f.render_widget(
        Paragraph::new(text)
            .style(Style::default().fg(Color::Yellow))
            .block(Block::default()
                .title(" Goto address ")
                .borders(Borders::ALL)
                .border_style(Style::default().fg(Color::Yellow))),
        popup,
    );
}

// ── Helper: centered popup ────────────────────────────────────────────────────

/// Returns a Rect centered in `area`, at least `min_w` × `min_h` in size.
fn centered_rect(pct_w: u16, pct_h: u16, min_w: u16, min_h: u16, area: Rect) -> Rect {
    let w = ((area.width  * pct_w) / 100).max(min_w).min(area.width);
    let h = if pct_h == 0 { min_h } else {
        ((area.height * pct_h) / 100).max(min_h).min(area.height)
    };
    let x = area.x + (area.width.saturating_sub(w)) / 2;
    let y = area.y + (area.height.saturating_sub(h)) / 2;
    Rect { x, y, width: w, height: h }
}

// ── Event loop ────────────────────────────────────────────────────────────────

pub fn run(app: &mut App) -> io::Result<()> {
    enable_raw_mode()?;
    let mut stdout = io::stdout();
    execute!(stdout, EnterAlternateScreen)?;
    let mut terminal = Terminal::new(CrosstermBackend::new(stdout))?;

    let tick = Duration::from_millis(16);
    let mut last_draw = Instant::now();

    loop {
        app.drain_acia();

        if last_draw.elapsed() >= tick {
            terminal.draw(|f| draw(f, app))?;
            last_draw = Instant::now();
        }

        if event::poll(Duration::from_millis(8))? {
            if let Event::Key(key) = event::read()? {
                // Ignore Release events — Windows crossterm fires Press + Release for every key.
                if key.kind == event::KeyEventKind::Release { continue; }
                if handle_key(app, key) { break; }
            }
        }
    }

    disable_raw_mode()?;
    execute!(terminal.backend_mut(), LeaveAlternateScreen)?;
    Ok(())
}

// ── Key handler ───────────────────────────────────────────────────────────────

/// Returns true → quit.
fn handle_key(app: &mut App, key: KeyEvent) -> bool {
    match &app.modal {
        Modal::FileBrowser(_)    => { handle_filebrowser_key(app, key);  return false; }
        Modal::LoadTarget { .. } => { handle_load_target_key(app, key);  return false; }
        Modal::GotoAddr { .. }   => { handle_goto_key(app, key);         return false; }
        Modal::EditMem { .. }    => { handle_edit_mem_key(app, key);     return false; }
        Modal::EditReg { .. }    => { handle_edit_reg_key(app, key);     return false; }
        Modal::None => {}
    }
    handle_normal_key(app, key)
}

// ── File browser keys ─────────────────────────────────────────────────────────

fn handle_filebrowser_key(app: &mut App, key: KeyEvent) {
    let Modal::FileBrowser(ref mut fb) = app.modal else { return };

    // Compute visible rows: we don't have frame size here, use a safe estimate
    let visible = 20usize;

    match key.code {
        KeyCode::Esc => {
            app.modal = Modal::None;
            app.status_msg = "Cancelled.".into();
        }
        KeyCode::Up   => { fb.move_up(); }
        KeyCode::Down => { fb.move_down(visible); }

        KeyCode::PageUp => {
            for _ in 0..visible { fb.move_up(); }
        }
        KeyCode::PageDown => {
            for _ in 0..visible { fb.move_down(visible); }
        }

        KeyCode::Enter | KeyCode::Right => {
            // Take ownership out of app.modal temporarily
            let Modal::FileBrowser(mut taken) = std::mem::replace(&mut app.modal, Modal::None)
            else { return };

            if let Some(path) = taken.activate() {
                // File selected — read it, then ask where to load it
                match std::fs::read(&path) {
                    Ok(data) => {
                        let filename = path.file_name()
                            .map(|n| n.to_string_lossy().to_string())
                            .unwrap_or_else(|| path.to_string_lossy().to_string());
                        app.modal = Modal::LoadTarget {
                            data,
                            filename,
                            selected: 0,
                            custom_buf: None,
                        };
                    }
                    Err(e) => {
                        taken.error = Some(format!("Chyba čtení: {}", e));
                        app.modal = Modal::FileBrowser(taken);
                    }
                }
            } else {
                // Was a directory — browser already updated itself
                app.modal = Modal::FileBrowser(taken);
            }
        }

        KeyCode::Backspace | KeyCode::Left => {
            // Go up one directory
            let Modal::FileBrowser(ref mut fb) = app.modal else { return };
            if let Some(parent) = fb.dir.parent().map(|p| p.to_path_buf()) {
                fb.dir = parent;
                fb.selected = 0;
                fb.scroll = 0;
                fb.refresh();
            }
        }

        _ => {}
    }
}

// ── Goto address keys ─────────────────────────────────────────────────────────

fn handle_goto_key(app: &mut App, key: KeyEvent) {
    match key.code {
        KeyCode::Esc => {
            app.modal = Modal::None;
            app.status_msg = "Cancelled.".into();
        }
        KeyCode::Backspace => {
            if let Modal::GotoAddr { ref mut buf } = app.modal { buf.pop(); }
        }
        KeyCode::Char(c) if c.is_ascii_hexdigit() => {
            if let Modal::GotoAddr { ref mut buf } = app.modal {
                if buf.len() < 4 { buf.push(c.to_ascii_uppercase()); }
            }
        }
        KeyCode::Enter => {
            if let Modal::GotoAddr { ref buf } = app.modal {
                let s = buf.clone();
                if let Ok(addr) = u16::from_str_radix(&s, 16) {
                    app.custom_addr = addr;
                    app.mem_tab = MemTab::Custom;
                    app.mem_scroll = 0;
                    app.status_msg = format!("Goto ${:04X}", addr);
                } else {
                    app.status_msg = "Neplatná adresa.".into();
                }
            }
            app.modal = Modal::None;
        }
        _ => {}
    }
}

// ── Edit-memory keys ─────────────────────────────────────────────────────────

fn handle_edit_mem_key(app: &mut App, key: KeyEvent) {
    let (phase, addr_buf, val_buf) = match &app.modal {
        Modal::EditMem { phase, addr_buf, val_buf } =>
            (*phase, addr_buf.clone(), val_buf.clone()),
        _ => return,
    };

    match key.code {
        // ── Phase 0: enter address ─────────────────────────────────────────
        KeyCode::Esc if !phase => {
            app.modal = Modal::None;
            app.status_msg = "Editace zrušena.".into();
        }
        KeyCode::Char(c) if c.is_ascii_hexdigit() && !phase => {
            if addr_buf.len() < 4 {
                let mut s = addr_buf; s.push(c.to_ascii_uppercase());
                app.modal = Modal::EditMem { phase: false, addr_buf: s, val_buf };
            }
        }
        KeyCode::Backspace if !phase => {
            let mut s = addr_buf; s.pop();
            app.modal = Modal::EditMem { phase: false, addr_buf: s, val_buf };
        }
        KeyCode::Enter if !phase => {
            if !addr_buf.is_empty() {
                let padded = format!("{:0>4}", addr_buf);
                if u16::from_str_radix(&padded, 16).is_ok() {
                    app.modal = Modal::EditMem { phase: true, addr_buf: padded, val_buf };
                }
            }
        }

        // ── Phase 1: enter value ───────────────────────────────────────────
        KeyCode::Esc if phase => {
            app.modal = Modal::EditMem { phase: false, addr_buf, val_buf: String::new() };
        }
        KeyCode::Char(c) if c.is_ascii_hexdigit() && phase => {
            if val_buf.len() < 2 {
                let mut s = val_buf; s.push(c.to_ascii_uppercase());
                app.modal = Modal::EditMem { phase: true, addr_buf, val_buf: s };
            }
        }
        KeyCode::Backspace if phase => {
            let mut s = val_buf; s.pop();
            app.modal = Modal::EditMem { phase: true, addr_buf, val_buf: s };
        }
        KeyCode::Enter if phase => {
            if !val_buf.is_empty() {
                let padded_val = format!("{:0>2}", val_buf);
                if let (Ok(addr), Ok(val)) = (
                    u16::from_str_radix(&addr_buf,  16),
                    u8::from_str_radix(&padded_val, 16),
                ) {
                    app.status_msg = format!("Mem ${:04X} ← ${:02X}", addr, val);
                    let _ = app.cmd_tx.send(Cmd::LoadAt { data: vec![val], addr, reset: false });
                }
                app.modal = Modal::None;
            }
        }
        _ => {}
    }
}

// ── Edit-register keys ────────────────────────────────────────────────────────

fn handle_edit_reg_key(app: &mut App, key: KeyEvent) {
    let (sel, val_buf) = match &app.modal {
        Modal::EditReg { sel, val_buf } => (*sel, val_buf.clone()),
        _ => return,
    };

    match key.code {
        KeyCode::Esc => {
            app.modal = Modal::None;
            app.status_msg = "Editace zrušena.".into();
        }
        KeyCode::Up => {
            let s = if sel > 0 { sel - 1 } else { REG_NAMES.len() - 1 };
            app.modal = Modal::EditReg { sel: s, val_buf: String::new() };
        }
        KeyCode::Down => {
            app.modal = Modal::EditReg { sel: (sel + 1) % REG_NAMES.len(), val_buf: String::new() };
        }
        KeyCode::Char(c) if c.is_ascii_hexdigit() => {
            let max_len = if REG_IS16[sel] { 4 } else { 2 };
            if val_buf.len() < max_len {
                let mut s = val_buf; s.push(c.to_ascii_uppercase());
                app.modal = Modal::EditReg { sel, val_buf: s };
            }
        }
        KeyCode::Backspace => {
            let mut s = val_buf; s.pop();
            app.modal = Modal::EditReg { sel, val_buf: s };
        }
        KeyCode::Enter => {
            if !val_buf.is_empty() {
                let max_len = if REG_IS16[sel] { 4 } else { 2 };
                let padded = format!("{:0>width$}", val_buf, width = max_len);
                if let Ok(val) = u16::from_str_radix(&padded, 16) {
                    app.status_msg = format!("{} ← ${:04X}", REG_NAMES[sel], val);
                    let _ = app.cmd_tx.send(Cmd::SetReg { field: sel as u8, val });
                }
            }
            app.modal = Modal::None;
        }
        _ => {}
    }
}

// ── Normal mode keys ──────────────────────────────────────────────────────────

fn handle_normal_key(app: &mut App, key: KeyEvent) -> bool {
    match (key.modifiers, key.code) {
        // Quit
        (_, KeyCode::F(10)) |
        (KeyModifiers::CONTROL, KeyCode::Char('q')) => {
            let _ = app.cmd_tx.send(Cmd::Quit);
            return true;
        }

        // CPU control
        (_, KeyCode::F(2)) => { let _ = app.cmd_tx.send(Cmd::Step); }
        (_, KeyCode::F(3)) => {
            let running = app.shared.try_lock().map(|s| s.running).unwrap_or(false);
            if running {
                let _ = app.cmd_tx.send(Cmd::Pause);
                app.status_msg = "Paused.".into();
            } else {
                let _ = app.cmd_tx.send(Cmd::Run);
                app.status_msg = "Running.".into();
            }
        }
        (_, KeyCode::F(4)) => {
            let _ = app.cmd_tx.send(Cmd::Reset);
            app.status_msg = "Reset.".into();
        }

        // Speed presets
        (_, KeyCode::F(5)) => app.set_speed(1_000),
        (_, KeyCode::F(6)) => app.set_speed(10_000),
        (_, KeyCode::F(7)) => app.set_speed(100_000),
        (_, KeyCode::F(8)) => app.set_speed(1_000_000),
        (_, KeyCode::F(9)) => app.set_speed(u64::MAX),

        // Speed ×2 / ÷2
        // (_, KeyCode::Char('+')) | (_, KeyCode::Char('=')) => {
        //     let new = app.speed_hz.saturating_mul(2);
        //     app.set_speed(new);
        // }
        // (_, KeyCode::Char('-')) => {
        //     let new = (app.speed_hz / 2).max(100);
        //     app.set_speed(new);
        // }

        // Open ROM → file browser modal
        (KeyModifiers::CONTROL, KeyCode::Char('o')) => {
            app.open_file_browser();
        }

        // Goto address modal
        (KeyModifiers::CONTROL, KeyCode::Char('g')) => {
            app.modal = Modal::GotoAddr { buf: String::new() };
        }

        // Edit single memory byte
        (KeyModifiers::CONTROL, KeyCode::Char('m')) => {
            app.modal = Modal::EditMem {
                addr_buf: String::new(), val_buf: String::new(), phase: false,
            };
        }

        // Edit CPU registers
        (KeyModifiers::CONTROL, KeyCode::Char('r')) => {
            app.modal = Modal::EditReg { sel: 0, val_buf: String::new() };
        }

        // Switch right panel tab (Shift+Tab = BackTab)
        (_, KeyCode::BackTab) => {
            let idx = RightTab::ALL.iter().position(|t| *t == app.right_tab).unwrap_or(0);
            app.right_tab = RightTab::ALL[(idx + 1) % RightTab::ALL.len()];
            let name = app.right_tab.label().trim();
            app.status_msg = format!("Panel: {}", name);
        }

        // Terminal scroll (Shift+Pg before generic Pg)
        (KeyModifiers::SHIFT, KeyCode::PageUp)   => { app.term_scroll = app.term_scroll.saturating_add(5); }
        (KeyModifiers::SHIFT, KeyCode::PageDown) => { app.term_scroll = app.term_scroll.saturating_sub(5); }

        // Memory navigation
        (_, KeyCode::Tab) => {
            let idx = (app.current_tab_idx() + 1) % MemTab::ALL.len();
            app.mem_tab = MemTab::ALL[idx];
            app.mem_scroll = 0;
        }
        (_, KeyCode::PageDown) => { app.mem_scroll = app.mem_scroll.saturating_add(8); }
        (_, KeyCode::PageUp)   => { app.mem_scroll = app.mem_scroll.saturating_sub(8); }
        (_, KeyCode::Down)     => { app.mem_scroll = app.mem_scroll.saturating_add(1); }
        (_, KeyCode::Up)       => { app.mem_scroll = app.mem_scroll.saturating_sub(1); }

        // Serial terminal input → ACIA RX
        (_, KeyCode::Char(c)) => { app.send_key(c as u8); }
        (_, KeyCode::Enter)   => { app.send_key(b'\r'); }
        (_, KeyCode::Backspace) => { app.send_key(0x08); }
        (_, KeyCode::Esc)     => { app.send_key(0x1B); }

        _ => {}
    }
    false
}
