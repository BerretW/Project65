/// IRQ priority latch — mirrors IC17 (74HC148) + IC27 (74HC574).
///
/// Hardware:
///   Read  $C480-$C4FF → returns priority-encoded IRQ source (bits 2-0)
///   Write $C400-$C47F → acknowledge / clear IRQ
///
/// Bit layout of latch value (read from $C480):
///   bits 2-0 = priority-encoded source (0 = highest):
///     0 = IRQ0 ACIA
///     1 = IRQ1 VIA2
///     2-6 = ISA slots
///     7 = S1 button
///   bit 7 = 1 when any IRQ active
pub struct IrqLatch {
    /// Bitmask of currently active IRQ lines (bit 0 = IRQ0 ACIA, bit 1 = IRQ1 VIA2, …)
    pub active: u8,
}

impl IrqLatch {
    pub fn new() -> Self {
        Self { active: 0 }
    }

    /// Assert an IRQ line (0-7).  Line 0 = highest priority.
    pub fn assert(&mut self, line: u8) {
        self.active |= 1 << line;
    }

    /// Deassert an IRQ line.
    pub fn deassert(&mut self, line: u8) {
        self.active &= !(1 << line);
    }

    /// True when any IRQ line is active.
    pub fn irq_active(&self) -> bool {
        self.active != 0
    }

    /// Read the priority-encoded latch value (IC17 output captured by IC27).
    /// Returns 0xFF if no IRQ is active.
    pub fn read_encoded(&self) -> u8 {
        if self.active == 0 {
            return 0x7F; // no interrupt
        }
        // Find highest-priority (lowest-numbered) active bit
        let mut v = self.active;
        let mut pri = 0u8;
        while v & 1 == 0 {
            v >>= 1;
            pri += 1;
        }
        0x80 | pri // bit 7 set = IRQ active, bits 2-0 = priority
    }

    /// CPU read — $C480-$C4FF → encoded value
    pub fn read(&self, addr: u16) -> u8 {
        if addr & 0x80 != 0 {
            self.read_encoded()
        } else {
            0xFF
        }
    }

    /// CPU write — $C400-$C47F → acknowledge (clear) IRQ line encoded in data bits 2-0
    pub fn write(&mut self, addr: u16, val: u8) {
        if addr & 0x80 == 0 {
            let line = val & 0x07;
            self.deassert(line);
        }
    }
}
