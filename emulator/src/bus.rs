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

pub struct Bus {
    pub ram_lo:    Ram,
    pub ram_hi:    Ram,
    pub rom:       Rom,
    pub acia:      Acia,
    pub via1:      Via,      // $CC00-$CC7F — NMI
    pub via2:      Via,      // $CC80-$CCFF — IRQ1
    pub irq_latch: IrqLatch,
}

impl Bus {
    pub fn new(acia: Acia) -> Self {
        Self {
            ram_lo:    Ram::new(0x0000, 0x8000), // 32 KB
            ram_hi:    Ram::new(0x8000, 0x4000), // 32 KB ($8000-$BFFF)
            rom:       Rom::new(),
            acia,
            via1:      Via::new(true),  // drives NMI
            via2:      Via::new(false), // drives IRQ
            irq_latch: IrqLatch::new(),
        }
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
