/// W65C22 VIA emulation.
///
/// Registers (offsets from chip base address):
///   0x0 ORB / IRB   Port B output/input
///   0x1 ORA / IRA   Port A output/input (with handshake)
///   0x2 DDRB        Port B data direction (1=output)
///   0x3 DDRA        Port A data direction
///   0x4 T1CL        Timer 1 counter low  (R) / latch low  (W)
///   0x5 T1CH        Timer 1 counter high (R) / latch high (W) + start
///   0x6 T1LL        Timer 1 latch low
///   0x7 T1LH        Timer 1 latch high
///   0x8 T2CL        Timer 2 counter low  (R) / latch low  (W)
///   0x9 T2CH        Timer 2 counter high (R) / latch high (W) + start
///   0xA SR          Shift register
///   0xB ACR         Auxiliary control register
///   0xC PCR         Peripheral control register
///   0xD IFR         Interrupt flag register  (bit 7 = any active)
///   0xE IER         Interrupt enable register
///   0xF ORA_NH      Port A output/input (no handshake)
///
/// ACR bits:
///   7   T1 PB7 output enable
///   6   T1 continuous free-run (0=one-shot, 1=free-run)
///   5   T2 pulse counting (0=timer, 1=pulse)
///   4-2 SR control
///   1   PB latch
///   0   PA latch
///
/// IFR / IER bits:
///   7  IRQ (IFR: any active; IER: set/clear mode bit)
///   6  T1  Timer 1
///   5  T2  Timer 2
///   4  CB1
///   3  CB2
///   2  SR
///   1  CA1
///   0  CA2

pub struct Via {
    // I/O registers
    pub ora: u8,
    pub orb: u8,
    pub ddra: u8,
    pub ddrb: u8,
    pub sr: u8,
    pub acr: u8,
    pub pcr: u8,
    pub ifr: u8,
    pub ier: u8,

    // Timer 1
    pub t1_counter: u16,
    pub t1_latch:   u16,
    pub t1_running: bool,

    // Timer 2
    pub t2_counter:  u16,
    pub t2_latch_lo: u8,
    pub t2_running:  bool,

    // Which interrupt line this VIA drives
    // false = drives CPU IRQ, true = drives CPU NMI
    pub drives_nmi: bool,
}

impl Via {
    pub fn new(drives_nmi: bool) -> Self {
        Self {
            ora: 0, orb: 0, ddra: 0xFF, ddrb: 0xFF,
            sr: 0, acr: 0, pcr: 0,
            ifr: 0, ier: 0,
            t1_counter: 0xFFFF, t1_latch: 0xFFFF, t1_running: false,
            t2_counter: 0xFFFF, t2_latch_lo: 0xFF, t2_running: false,
            drives_nmi,
        }
    }

    pub fn read(&mut self, addr: u16) -> u8 {
        match addr & 0x0F {
            0x0 => {
                // ORB — read IFR CB1/CB2 clear
                self.ifr &= !0x18;
                self.update_ifr7();
                self.orb
            }
            0x1 | 0xF => {
                // ORA
                self.ifr &= !0x03;
                self.update_ifr7();
                self.ora
            }
            0x2 => self.ddrb,
            0x3 => self.ddra,
            0x4 => {
                // T1CL — clear T1 interrupt
                self.ifr &= !0x40;
                self.update_ifr7();
                (self.t1_counter & 0xFF) as u8
            }
            0x5 => (self.t1_counter >> 8) as u8,
            0x6 => (self.t1_latch & 0xFF) as u8,
            0x7 => (self.t1_latch >> 8) as u8,
            0x8 => {
                // T2CL — clear T2 interrupt
                self.ifr &= !0x20;
                self.update_ifr7();
                (self.t2_counter & 0xFF) as u8
            }
            0x9 => (self.t2_counter >> 8) as u8,
            0xA => self.sr,
            0xB => self.acr,
            0xC => self.pcr,
            0xD => self.ifr,
            0xE => self.ier | 0x80, // bit 7 always 1 when reading IER
            _ => 0xFF,
        }
    }

    pub fn write(&mut self, addr: u16, val: u8) {
        match addr & 0x0F {
            0x0 => {
                self.orb = val;
                self.ifr &= !0x18;
                self.update_ifr7();
            }
            0x1 | 0xF => {
                self.ora = val;
                self.ifr &= !0x03;
                self.update_ifr7();
            }
            0x2 => self.ddrb = val,
            0x3 => self.ddra = val,
            0x4 => {
                // Write T1 latch low — does NOT start timer
                self.t1_latch = (self.t1_latch & 0xFF00) | val as u16;
            }
            0x5 => {
                // Write T1 latch high + transfer latch→counter + start + clear IFR T1
                self.t1_latch = (self.t1_latch & 0x00FF) | ((val as u16) << 8);
                self.t1_counter = self.t1_latch;
                self.t1_running = true;
                self.ifr &= !0x40;
                self.update_ifr7();
            }
            0x6 => {
                self.t1_latch = (self.t1_latch & 0xFF00) | val as u16;
            }
            0x7 => {
                self.t1_latch = (self.t1_latch & 0x00FF) | ((val as u16) << 8);
                self.ifr &= !0x40;
                self.update_ifr7();
            }
            0x8 => {
                self.t2_latch_lo = val;
            }
            0x9 => {
                // Write T2 high — transfer lo latch + start + clear IFR T2
                self.t2_counter = self.t2_latch_lo as u16 | ((val as u16) << 8);
                self.t2_running = true;
                self.ifr &= !0x20;
                self.update_ifr7();
            }
            0xA => self.sr = val,
            0xB => self.acr = val,
            0xC => self.pcr = val,
            0xD => {
                // Writing to IFR clears bits (write 1 to clear)
                self.ifr &= !val;
                self.update_ifr7();
            }
            0xE => {
                // IER: bit 7 = 1 → set bits, bit 7 = 0 → clear bits
                if val & 0x80 != 0 {
                    self.ier |= val & 0x7F;
                } else {
                    self.ier &= !(val & 0x7F);
                }
                self.update_ifr7();
            }
            _ => {}
        }
    }

    /// Tick `cycles` CPU cycles.
    /// Returns (irq_out, nmi_out).
    pub fn tick(&mut self, cycles: u32) -> (bool, bool) {
        let mut fired = false;

        // Timer 1
        if self.t1_running {
            let (new_cnt, wrapped) = self.t1_counter.overflowing_sub(cycles as u16);
            if wrapped {
                // Timer 1 underflowed
                self.ifr |= 0x40;
                if self.acr & 0x40 != 0 {
                    // Free-run: reload from latch
                    self.t1_counter = self.t1_latch.wrapping_sub(cycles as u16 - self.t1_counter);
                } else {
                    // One-shot: stop
                    self.t1_running = false;
                    self.t1_counter = new_cnt;
                }
                fired = true;
            } else {
                self.t1_counter = new_cnt;
            }
        }

        // Timer 2 (one-shot only in timer mode; pulse-count mode not implemented)
        if self.t2_running && self.acr & 0x20 == 0 {
            let (new_cnt, wrapped) = self.t2_counter.overflowing_sub(cycles as u16);
            if wrapped {
                self.ifr |= 0x20;
                self.t2_running = false;
                self.t2_counter = new_cnt;
                fired = true;
            } else {
                self.t2_counter = new_cnt;
            }
        }

        if fired { self.update_ifr7(); }

        let irq_out = self.ifr & self.ier & 0x7F != 0;
        if self.drives_nmi {
            (false, irq_out)
        } else {
            (irq_out, false)
        }
    }

    fn update_ifr7(&mut self) {
        if self.ifr & self.ier & 0x7F != 0 {
            self.ifr |= 0x80;
        } else {
            self.ifr &= !0x80;
        }
    }

    pub fn irq(&self) -> bool { self.ifr & self.ier & 0x7F != 0 }
}
