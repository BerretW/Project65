/// System bus — address decoding matching Project65 BigBoard hardware.
///
/// Memory map:
///   $0000–$7FFF  IC6  RAM lo  (32 KB)
///   $8000–$BFFF  IC7  RAM hi  (32 KB)
///   $C000–$C3FF  VERA / ISA video  (stub: open bus)
///   $C400–$C7FF  IRQ latch
///   $C800–$CBFF  ACIA R6551
///   $CC00–$CC7F  VIA1 (IC18, NMI source)
///   $CC80–$CCFF  VIA2 (IC16, IRQ1 source)
///   $CD00–$CFFF  ISA DEV0-2  (stub)
///   $D000–$DFFF  ISA extended (stub)
///   $E000–$FFFF  ROM EEPROM (8 KB, mirrored)

use crate::ram::Ram;
use crate::rom::Rom;
use crate::acia::Acia;
use crate::via::Via;
use crate::irq_latch::IrqLatch;

// ── Address-decoder chip family ───────────────────────────────────────────────
//
// IC9 and IC11 on the BigBoard are 74HCT139N (decoder ICs).
// IC10/IC12/IC21 are 74AC00/32 — those are fixed-fast; we model only the decoders.
// Total decode chain for worst-case IO path:
//   IC11 sec1 + IC11 sec2 + IC9 sec1 + IC9 sec2  = 4 stages of `tpd`
//   IC10/IC12 NAND/NOR final stage ≈ 7 ns (AC fixed)

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum ChipFamily { LS, ALS, HCT, HC, AC, ACT }

impl ChipFamily {
    /// Typical propagation delay [ns] for one 74xxx139 stage.
    pub fn tpd_ns(self) -> u32 {
        match self {
            ChipFamily::LS  => 25,
            ChipFamily::ALS => 11,
            ChipFamily::HCT => 16,
            ChipFamily::HC  => 12,
            ChipFamily::AC  =>  7,
            ChipFamily::ACT =>  7,
        }
    }
    pub fn name(self) -> &'static str {
        match self {
            ChipFamily::LS  => "LS",
            ChipFamily::ALS => "ALS",
            ChipFamily::HCT => "HCT",
            ChipFamily::HC  => "HC",
            ChipFamily::AC  => "AC",
            ChipFamily::ACT => "ACT",
        }
    }
}

impl std::str::FromStr for ChipFamily {
    type Err = String;
    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s.to_uppercase().as_str() {
            "LS"  => Ok(ChipFamily::LS),
            "ALS" => Ok(ChipFamily::ALS),
            "HCT" => Ok(ChipFamily::HCT),
            "HC"  => Ok(ChipFamily::HC),
            "AC"  => Ok(ChipFamily::AC),
            "ACT" => Ok(ChipFamily::ACT),
            other => Err(format!("Neznámá rodina '{}'. Platné: LS, ALS, HCT, HC, AC, ACT", other)),
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum TimingStatus { Ok, Marginal, Fail }

pub struct Bus {
    pub ram_lo:      Ram,
    pub ram_hi:      Ram,
    pub rom:         Rom,
    pub acia:        Acia,
    pub via1:        Via,        // $CC00-$CC7F — NMI
    pub via2:        Via,        // $CC80-$CCFF — IRQ1
    pub irq_latch:   IrqLatch,
    pub chip_family: ChipFamily,
}

impl Bus {
    pub fn new(acia: Acia) -> Self {
        Self {
            ram_lo:      Ram::new(0x0000, 0x8000),
            ram_hi:      Ram::new(0x8000, 0x4000),
            rom:         Rom::new(),
            acia,
            via1:        Via::new(true),   // drives NMI
            via2:        Via::new(false),  // drives IRQ
            irq_latch:   IrqLatch::new(),
            chip_family: ChipFamily::HCT,  // default — actual board uses 74HCT139
        }
    }

    // ── Timing analysis ───────────────────────────────────────────────────────

    /// Total address-decode delay [ns] for worst-case IO path.
    /// 4 decoder stages × tpd + 7 ns (fixed AC gate).
    pub fn decode_delay_ns(&self) -> u32 {
        4 * self.chip_family.tpd_ns() + 7
    }

    /// Available time [ns] for address decoding at the given CPU speed.
    /// W65C02: address valid ~30 ns after Φ2↑, data must be stable 30 ns before Φ2↓.
    /// Available ≈ half_period − 60 ns.
    pub fn available_decode_ns(speed_hz: u64) -> u32 {
        if speed_hz == 0 || speed_hz == u64::MAX { return 9999; }
        let period_ns = 1_000_000_000u64 / speed_hz;
        (period_ns / 2).saturating_sub(60) as u32
    }

    pub fn timing_status(&self, speed_hz: u64) -> TimingStatus {
        let decode = self.decode_delay_ns();
        let avail  = Self::available_decode_ns(speed_hz);
        if avail >= decode * 3 / 2 { TimingStatus::Ok }
        else if avail >= decode    { TimingStatus::Marginal }
        else                       { TimingStatus::Fail }
    }

    pub fn read(&mut self, addr: u16) -> u8 {
        match addr {
            0x0000..=0x7FFF => self.ram_lo.read(addr),
            0x8000..=0xBFFF => self.ram_hi.read(addr),
            0xC000..=0xC3FF => 0xFF, // VERA stub
            0xC400..=0xC7FF => self.irq_latch.read(addr),
            0xC800..=0xCBFF => self.acia.read(addr),
            0xCC00..=0xCC7F => self.via1.read(addr - 0xCC00),
            0xCC80..=0xCCFF => self.via2.read(addr - 0xCC80),
            0xCD00..=0xCFFF => 0xFF, // ISA stubs
            0xD000..=0xDFFF => 0xFF,
            0xE000..=0xFFFF => self.rom.read(addr),
        }
    }

    pub fn write(&mut self, addr: u16, val: u8) {
        match addr {
            0x0000..=0x7FFF => self.ram_lo.write(addr, val),
            0x8000..=0xBFFF => self.ram_hi.write(addr, val),
            0xC000..=0xC3FF => {}    // VERA stub
            0xC400..=0xC7FF => self.irq_latch.write(addr, val),
            0xC800..=0xCBFF => self.acia.write(addr, val),
            0xCC00..=0xCC7F => self.via1.write(addr - 0xCC00, val),
            0xCC80..=0xCCFF => self.via2.write(addr - 0xCC80, val),
            0xCD00..=0xCFFF => {}    // ISA stubs
            0xD000..=0xDFFF => {}
            0xE000..=0xFFFF => {}    // ROM — writes silently ignored
        }
    }

    /// Tick all peripherals by `cycles` CPU cycles.
    /// Returns (nmi_line, irq_line).
    pub fn tick(&mut self, cycles: u32) -> (bool, bool) {
        let acia_irq = self.acia.tick(cycles);

        let (via2_irq, _)  = self.via2.tick(cycles);
        let (_, via1_nmi)  = self.via1.tick(cycles);

        // Update IRQ latch
        if acia_irq { self.irq_latch.assert(0); } else { self.irq_latch.deassert(0); }
        if via2_irq { self.irq_latch.assert(1); } else { self.irq_latch.deassert(1); }

        let irq = self.irq_latch.irq_active();
        (via1_nmi, irq)
    }

    /// Convenience: read a 16-bit word
    pub fn read16(&mut self, addr: u16) -> u16 {
        let lo = self.read(addr) as u16;
        let hi = self.read(addr.wrapping_add(1)) as u16;
        lo | (hi << 8)
    }

    /// Read up to `len` bytes starting at `addr` for the TUI memory dump.
    /// Crosses region boundaries correctly by calling read() for each byte.
    pub fn dump(&mut self, addr: u16, len: usize) -> Vec<u8> {
        (0..len as u16)
            .map(|i| self.read(addr.wrapping_add(i)))
            .collect()
    }
}
