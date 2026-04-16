/// Full W65C02S CPU emulation.
///
/// Implements all documented 65C02 opcodes including:
///   BRA, PHX, PHY, PLX, PLY, STZ, TRB, TSB
///   (zp) addressing mode, (abs,X) for JMP
///   RMB0-7, SMB0-7, BBR0-7, BBS0-7
///   WAI, STP
///   INC A, DEC A (65C02 INA/DEA)
///
/// Corrections vs MOS 6502:
///   JMP ($xxFF) page-wrap bug is FIXED
///   D flag cleared on reset, BRK, NMI, IRQ entry

use crate::bus::Bus;

// Processor status flag masks
const FLAG_N: u8 = 0x80;
const FLAG_V: u8 = 0x40;
const FLAG_U: u8 = 0x20; // always 1
const FLAG_B: u8 = 0x10;
const FLAG_D: u8 = 0x08;
const FLAG_I: u8 = 0x04;
const FLAG_Z: u8 = 0x02;
const FLAG_C: u8 = 0x01;

#[derive(Clone, Debug)]
pub struct CpuState {
    pub a: u8,
    pub x: u8,
    pub y: u8,
    pub sp: u8,
    pub pc: u16,
    pub p: u8,
    pub cycles: u64,
    pub halted: bool, // STP instruction
    pub waiting: bool, // WAI instruction
}

impl Default for CpuState {
    fn default() -> Self {
        Self { a: 0, x: 0, y: 0, sp: 0xFD, pc: 0xFFFC, p: FLAG_U | FLAG_I,
               cycles: 0, halted: false, waiting: false }
    }
}

pub struct Cpu {
    pub a: u8,
    pub x: u8,
    pub y: u8,
    pub sp: u8,
    pub pc: u16,
    pub p: u8,
    pub cycles: u64,
    pub halted: bool,
    pub waiting: bool,
    pub nmi_pending: bool,
    nmi_prev: bool,
}

impl Cpu {
    pub fn new() -> Self {
        Self {
            a: 0, x: 0, y: 0, sp: 0xFD,
            pc: 0xFFFC, p: FLAG_U | FLAG_I,
            cycles: 0, halted: false, waiting: false,
            nmi_pending: false, nmi_prev: false,
        }
    }

    pub fn reset(&mut self, bus: &mut Bus) {
        let lo = bus.read(0xFFFC) as u16;
        let hi = bus.read(0xFFFD) as u16;
        self.pc = lo | (hi << 8);
        self.sp = 0xFD;
        self.p = FLAG_U | FLAG_I;
        self.p &= !FLAG_D; // D cleared on reset
        self.halted = false;
        self.waiting = false;
        self.nmi_pending = false;
        self.cycles += 7;
    }

    pub fn snapshot(&self) -> CpuState {
        CpuState { a: self.a, x: self.x, y: self.y, sp: self.sp,
                   pc: self.pc, p: self.p, cycles: self.cycles,
                   halted: self.halted, waiting: self.waiting }
    }

    // ── Helpers ────────────────────────────────────────────────────────────

    fn fetch(&mut self, bus: &mut Bus) -> u8 {
        let v = bus.read(self.pc);
        self.pc = self.pc.wrapping_add(1);
        v
    }

    fn fetch16(&mut self, bus: &mut Bus) -> u16 {
        let lo = self.fetch(bus) as u16;
        let hi = self.fetch(bus) as u16;
        lo | (hi << 8)
    }

    fn read16(bus: &mut Bus, addr: u16) -> u16 {
        let lo = bus.read(addr) as u16;
        let hi = bus.read(addr.wrapping_add(1)) as u16;
        lo | (hi << 8)
    }

    fn push(&mut self, bus: &mut Bus, val: u8) {
        bus.write(0x0100 | self.sp as u16, val);
        self.sp = self.sp.wrapping_sub(1);
    }

    fn pop(&mut self, bus: &mut Bus) -> u8 {
        self.sp = self.sp.wrapping_add(1);
        bus.read(0x0100 | self.sp as u16)
    }

    fn set_nz(&mut self, v: u8) {
        self.p = (self.p & !(FLAG_N | FLAG_Z))
                 | if v & 0x80 != 0 { FLAG_N } else { 0 }
                 | if v == 0         { FLAG_Z } else { 0 };
    }

    fn flag(&self, f: u8) -> bool { self.p & f != 0 }

    fn set_flag(&mut self, f: u8, v: bool) {
        if v { self.p |= f; } else { self.p &= !f; }
    }

    // ── Addressing modes ───────────────────────────────────────────────────

    fn addr_zp(&mut self, bus: &mut Bus) -> u16 {
        self.fetch(bus) as u16
    }

    fn addr_zpx(&mut self, bus: &mut Bus) -> u16 {
        self.fetch(bus).wrapping_add(self.x) as u16
    }

    fn addr_zpy(&mut self, bus: &mut Bus) -> u16 {
        self.fetch(bus).wrapping_add(self.y) as u16
    }

    fn addr_abs(&mut self, bus: &mut Bus) -> u16 {
        self.fetch16(bus)
    }

    fn addr_absx(&mut self, bus: &mut Bus) -> (u16, bool) {
        let base = self.fetch16(bus);
        let ea = base.wrapping_add(self.x as u16);
        (ea, (base & 0xFF00) != (ea & 0xFF00))
    }

    fn addr_absy(&mut self, bus: &mut Bus) -> (u16, bool) {
        let base = self.fetch16(bus);
        let ea = base.wrapping_add(self.y as u16);
        (ea, (base & 0xFF00) != (ea & 0xFF00))
    }

    fn addr_indx(&mut self, bus: &mut Bus) -> u16 {
        let zp = self.fetch(bus).wrapping_add(self.x) as u16;
        let lo = bus.read(zp) as u16;
        let hi = bus.read((zp + 1) & 0xFF) as u16;
        lo | (hi << 8)
    }

    fn addr_indy(&mut self, bus: &mut Bus) -> (u16, bool) {
        let zp = self.fetch(bus) as u16;
        let lo = bus.read(zp) as u16;
        let hi = bus.read((zp + 1) & 0xFF) as u16;
        let base = lo | (hi << 8);
        let ea = base.wrapping_add(self.y as u16);
        (ea, (base & 0xFF00) != (ea & 0xFF00))
    }

    fn addr_zpi(&mut self, bus: &mut Bus) -> u16 {
        // 65C02 (zp) mode
        let zp = self.fetch(bus) as u16;
        let lo = bus.read(zp) as u16;
        let hi = bus.read((zp + 1) & 0xFF) as u16;
        lo | (hi << 8)
    }

    // ── ALU operations ─────────────────────────────────────────────────────

    fn op_adc(&mut self, val: u8) {
        if self.flag(FLAG_D) {
            // BCD
            let lo = (self.a & 0x0F) + (val & 0x0F) + self.flag(FLAG_C) as u8;
            let lo_carry = if lo > 9 { 1u8 } else { 0 };
            let lo_bcd   = if lo > 9 { lo + 6 } else { lo };
            let hi = (self.a >> 4) + (val >> 4) + lo_carry;
            let hi_carry = if hi > 9 { 1u8 } else { 0 };
            let hi_bcd   = if hi > 9 { hi + 6 } else { hi };
            let result = (hi_bcd << 4) | (lo_bcd & 0x0F);
            self.set_flag(FLAG_C, hi_carry != 0);
            self.set_flag(FLAG_V, false); // V undefined in BCD on NMOS, W65C02 handles it
            self.set_nz(result);
            self.a = result;
        } else {
            let sum = self.a as u16 + val as u16 + self.flag(FLAG_C) as u16;
            let result = sum as u8;
            self.set_flag(FLAG_C, sum > 0xFF);
            self.set_flag(FLAG_V, (!(self.a ^ val) & (self.a ^ result) & 0x80) != 0);
            self.set_nz(result);
            self.a = result;
        }
    }

    fn op_sbc(&mut self, val: u8) {
        if self.flag(FLAG_D) {
            let val_bcd = val;
            let borrow = 1 - self.flag(FLAG_C) as u8;
            let mut lo = (self.a & 0x0F) as i16 - (val_bcd & 0x0F) as i16 - borrow as i16;
            let lo_borrow = if lo < 0 { 1i16 } else { 0 };
            if lo < 0 { lo += 10; }
            let mut hi = (self.a >> 4) as i16 - (val_bcd >> 4) as i16 - lo_borrow;
            let hi_borrow = if hi < 0 { 1i16 } else { 0 };
            if hi < 0 { hi += 10; }
            let result = ((hi as u8) << 4) | (lo as u8 & 0x0F);
            self.set_flag(FLAG_C, hi_borrow == 0);
            self.set_nz(result);
            self.a = result;
        } else {
            self.op_adc(!val);
        }
    }

    fn op_cmp(&mut self, a: u8, b: u8) {
        let r = a.wrapping_sub(b);
        self.set_flag(FLAG_C, a >= b);
        self.set_nz(r);
    }

    fn op_asl(&mut self, bus: &mut Bus, addr: u16, acc: bool) {
        let v = if acc { self.a } else { bus.read(addr) };
        self.set_flag(FLAG_C, v & 0x80 != 0);
        let r = v << 1;
        self.set_nz(r);
        if acc { self.a = r; } else { bus.write(addr, r); }
    }

    fn op_lsr(&mut self, bus: &mut Bus, addr: u16, acc: bool) {
        let v = if acc { self.a } else { bus.read(addr) };
        self.set_flag(FLAG_C, v & 0x01 != 0);
        let r = v >> 1;
        self.set_nz(r);
        if acc { self.a = r; } else { bus.write(addr, r); }
    }

    fn op_rol(&mut self, bus: &mut Bus, addr: u16, acc: bool) {
        let v = if acc { self.a } else { bus.read(addr) };
        let old_c = self.flag(FLAG_C) as u8;
        self.set_flag(FLAG_C, v & 0x80 != 0);
        let r = (v << 1) | old_c;
        self.set_nz(r);
        if acc { self.a = r; } else { bus.write(addr, r); }
    }

    fn op_ror(&mut self, bus: &mut Bus, addr: u16, acc: bool) {
        let v = if acc { self.a } else { bus.read(addr) };
        let old_c = self.flag(FLAG_C) as u8;
        self.set_flag(FLAG_C, v & 0x01 != 0);
        let r = (v >> 1) | (old_c << 7);
        self.set_nz(r);
        if acc { self.a = r; } else { bus.write(addr, r); }
    }

    fn op_bit(&mut self, val: u8) {
        self.set_flag(FLAG_N, val & 0x80 != 0);
        self.set_flag(FLAG_V, val & 0x40 != 0);
        self.set_flag(FLAG_Z, self.a & val == 0);
    }

    fn op_bit_imm(&mut self, val: u8) {
        // BIT #imm only sets Z (not N or V)
        self.set_flag(FLAG_Z, self.a & val == 0);
    }

    fn op_tsb(&mut self, bus: &mut Bus, addr: u16) {
        let v = bus.read(addr);
        self.set_flag(FLAG_Z, self.a & v == 0);
        bus.write(addr, v | self.a);
    }

    fn op_trb(&mut self, bus: &mut Bus, addr: u16) {
        let v = bus.read(addr);
        self.set_flag(FLAG_Z, self.a & v == 0);
        bus.write(addr, v & !self.a);
    }

    fn branch(&mut self, bus: &mut Bus, cond: bool) -> u8 {
        let rel = self.fetch(bus) as i8;
        if cond {
            let old_pc = self.pc;
            self.pc = self.pc.wrapping_add(rel as u16);
            let extra = if (old_pc & 0xFF00) != (self.pc & 0xFF00) { 2 } else { 1 };
            extra
        } else {
            0
        }
    }

    // ── Interrupt handling ─────────────────────────────────────────────────

    fn handle_nmi(&mut self, bus: &mut Bus) {
        let pc = self.pc;
        self.push(bus, (pc >> 8) as u8);
        self.push(bus, (pc & 0xFF) as u8);
        self.push(bus, self.p & !FLAG_B); // B clear for NMI/IRQ
        self.p |= FLAG_I;
        self.p &= !FLAG_D; // 65C02 clears D on interrupt
        let lo = bus.read(0xFFFA) as u16;
        let hi = bus.read(0xFFFB) as u16;
        self.pc = lo | (hi << 8);
        self.cycles += 7;
    }

    fn handle_irq(&mut self, bus: &mut Bus) {
        let pc = self.pc;
        self.push(bus, (pc >> 8) as u8);
        self.push(bus, (pc & 0xFF) as u8);
        self.push(bus, self.p & !FLAG_B);
        self.p |= FLAG_I;
        self.p &= !FLAG_D;
        let lo = bus.read(0xFFFE) as u16;
        let hi = bus.read(0xFFFF) as u16;
        self.pc = lo | (hi << 8);
        self.cycles += 7;
    }

    /// Poll NMI (edge-triggered) and IRQ (level) and handle them.
    /// Called before instruction fetch.
    pub fn poll_interrupts(&mut self, bus: &mut Bus, nmi: bool, irq: bool) {
        // NMI: falling-edge triggered
        if nmi && !self.nmi_prev {
            self.nmi_pending = true;
        }
        self.nmi_prev = nmi;

        if self.waiting {
            // WAI: exit on any interrupt
            if nmi || irq {
                self.waiting = false;
                // If I flag was set, still service the interrupt
            } else {
                return;
            }
        }

        if self.nmi_pending {
            self.nmi_pending = false;
            self.handle_nmi(bus);
        } else if irq && !self.flag(FLAG_I) {
            self.handle_irq(bus);
        }
    }

    // ── Main execute step ──────────────────────────────────────────────────

    /// Execute one instruction; returns number of cycles consumed.
    pub fn step(&mut self, bus: &mut Bus) -> u32 {
        if self.halted { return 1; }
        if self.waiting { return 1; }

        let opcode = self.fetch(bus);
        let cycles: u32 = match opcode {

            // ── BRK ──────────────────────────────────────────────────────
            0x00 => {
                self.pc = self.pc.wrapping_add(1); // skip padding byte
                let pc = self.pc;
                self.push(bus, (pc >> 8) as u8);
                self.push(bus, (pc & 0xFF) as u8);
                self.push(bus, self.p | FLAG_B);
                self.p |= FLAG_I;
                self.p &= !FLAG_D;
                let lo = bus.read(0xFFFE) as u16;
                let hi = bus.read(0xFFFF) as u16;
                self.pc = lo | (hi << 8);
                7
            }

            // ── ORA ───────────────────────────────────────────────────────
            0x01 => { let ea = self.addr_indx(bus); let v = bus.read(ea); self.a |= v; self.set_nz(self.a); 6 }
            0x05 => { let ea = self.addr_zp(bus);   let v = bus.read(ea); self.a |= v; self.set_nz(self.a); 3 }
            0x09 => { let v  = self.fetch(bus);                           self.a |= v; self.set_nz(self.a); 2 }
            0x0D => { let ea = self.addr_abs(bus);  let v = bus.read(ea); self.a |= v; self.set_nz(self.a); 4 }
            0x11 => { let (ea,p) = self.addr_indy(bus); let v = bus.read(ea); self.a |= v; self.set_nz(self.a); 5+p as u32 }
            0x12 => { let ea = self.addr_zpi(bus);  let v = bus.read(ea); self.a |= v; self.set_nz(self.a); 5 }
            0x15 => { let ea = self.addr_zpx(bus);  let v = bus.read(ea); self.a |= v; self.set_nz(self.a); 4 }
            0x19 => { let (ea,p) = self.addr_absy(bus); let v = bus.read(ea); self.a |= v; self.set_nz(self.a); 4+p as u32 }
            0x1D => { let (ea,p) = self.addr_absx(bus); let v = bus.read(ea); self.a |= v; self.set_nz(self.a); 4+p as u32 }

            // ── AND ───────────────────────────────────────────────────────
            0x21 => { let ea = self.addr_indx(bus); let v = bus.read(ea); self.a &= v; self.set_nz(self.a); 6 }
            0x25 => { let ea = self.addr_zp(bus);   let v = bus.read(ea); self.a &= v; self.set_nz(self.a); 3 }
            0x29 => { let v  = self.fetch(bus);                           self.a &= v; self.set_nz(self.a); 2 }
            0x2D => { let ea = self.addr_abs(bus);  let v = bus.read(ea); self.a &= v; self.set_nz(self.a); 4 }
            0x31 => { let (ea,p) = self.addr_indy(bus); let v = bus.read(ea); self.a &= v; self.set_nz(self.a); 5+p as u32 }
            0x32 => { let ea = self.addr_zpi(bus);  let v = bus.read(ea); self.a &= v; self.set_nz(self.a); 5 }
            0x35 => { let ea = self.addr_zpx(bus);  let v = bus.read(ea); self.a &= v; self.set_nz(self.a); 4 }
            0x39 => { let (ea,p) = self.addr_absy(bus); let v = bus.read(ea); self.a &= v; self.set_nz(self.a); 4+p as u32 }
            0x3D => { let (ea,p) = self.addr_absx(bus); let v = bus.read(ea); self.a &= v; self.set_nz(self.a); 4+p as u32 }

            // ── EOR ───────────────────────────────────────────────────────
            0x41 => { let ea = self.addr_indx(bus); let v = bus.read(ea); self.a ^= v; self.set_nz(self.a); 6 }
            0x45 => { let ea = self.addr_zp(bus);   let v = bus.read(ea); self.a ^= v; self.set_nz(self.a); 3 }
            0x49 => { let v  = self.fetch(bus);                           self.a ^= v; self.set_nz(self.a); 2 }
            0x4D => { let ea = self.addr_abs(bus);  let v = bus.read(ea); self.a ^= v; self.set_nz(self.a); 4 }
            0x51 => { let (ea,p) = self.addr_indy(bus); let v = bus.read(ea); self.a ^= v; self.set_nz(self.a); 5+p as u32 }
            0x52 => { let ea = self.addr_zpi(bus);  let v = bus.read(ea); self.a ^= v; self.set_nz(self.a); 5 }
            0x55 => { let ea = self.addr_zpx(bus);  let v = bus.read(ea); self.a ^= v; self.set_nz(self.a); 4 }
            0x59 => { let (ea,p) = self.addr_absy(bus); let v = bus.read(ea); self.a ^= v; self.set_nz(self.a); 4+p as u32 }
            0x5D => { let (ea,p) = self.addr_absx(bus); let v = bus.read(ea); self.a ^= v; self.set_nz(self.a); 4+p as u32 }

            // ── ADC ───────────────────────────────────────────────────────
            0x61 => { let ea = self.addr_indx(bus); let v = bus.read(ea); self.op_adc(v); 6 }
            0x65 => { let ea = self.addr_zp(bus);   let v = bus.read(ea); self.op_adc(v); 3 }
            0x69 => { let v  = self.fetch(bus);                           self.op_adc(v); 2 }
            0x6D => { let ea = self.addr_abs(bus);  let v = bus.read(ea); self.op_adc(v); 4 }
            0x71 => { let (ea,p) = self.addr_indy(bus); let v = bus.read(ea); self.op_adc(v); 5+p as u32 }
            0x72 => { let ea = self.addr_zpi(bus);  let v = bus.read(ea); self.op_adc(v); 5 }
            0x75 => { let ea = self.addr_zpx(bus);  let v = bus.read(ea); self.op_adc(v); 4 }
            0x79 => { let (ea,p) = self.addr_absy(bus); let v = bus.read(ea); self.op_adc(v); 4+p as u32 }
            0x7D => { let (ea,p) = self.addr_absx(bus); let v = bus.read(ea); self.op_adc(v); 4+p as u32 }

            // ── SBC ───────────────────────────────────────────────────────
            0xE1 => { let ea = self.addr_indx(bus); let v = bus.read(ea); self.op_sbc(v); 6 }
            0xE5 => { let ea = self.addr_zp(bus);   let v = bus.read(ea); self.op_sbc(v); 3 }
            0xE9 => { let v  = self.fetch(bus);                           self.op_sbc(v); 2 }
            0xED => { let ea = self.addr_abs(bus);  let v = bus.read(ea); self.op_sbc(v); 4 }
            0xF1 => { let (ea,p) = self.addr_indy(bus); let v = bus.read(ea); self.op_sbc(v); 5+p as u32 }
            0xF2 => { let ea = self.addr_zpi(bus);  let v = bus.read(ea); self.op_sbc(v); 5 }
            0xF5 => { let ea = self.addr_zpx(bus);  let v = bus.read(ea); self.op_sbc(v); 4 }
            0xF9 => { let (ea,p) = self.addr_absy(bus); let v = bus.read(ea); self.op_sbc(v); 4+p as u32 }
            0xFD => { let (ea,p) = self.addr_absx(bus); let v = bus.read(ea); self.op_sbc(v); 4+p as u32 }

            // ── CMP ───────────────────────────────────────────────────────
            0xC1 => { let ea = self.addr_indx(bus); let v = bus.read(ea); self.op_cmp(self.a, v); 6 }
            0xC5 => { let ea = self.addr_zp(bus);   let v = bus.read(ea); self.op_cmp(self.a, v); 3 }
            0xC9 => { let v  = self.fetch(bus);                           self.op_cmp(self.a, v); 2 }
            0xCD => { let ea = self.addr_abs(bus);  let v = bus.read(ea); self.op_cmp(self.a, v); 4 }
            0xD1 => { let (ea,p) = self.addr_indy(bus); let v = bus.read(ea); self.op_cmp(self.a, v); 5+p as u32 }
            0xD2 => { let ea = self.addr_zpi(bus);  let v = bus.read(ea); self.op_cmp(self.a, v); 5 }
            0xD5 => { let ea = self.addr_zpx(bus);  let v = bus.read(ea); self.op_cmp(self.a, v); 4 }
            0xD9 => { let (ea,p) = self.addr_absy(bus); let v = bus.read(ea); self.op_cmp(self.a, v); 4+p as u32 }
            0xDD => { let (ea,p) = self.addr_absx(bus); let v = bus.read(ea); self.op_cmp(self.a, v); 4+p as u32 }

            // ── CPX ───────────────────────────────────────────────────────
            0xE0 => { let v = self.fetch(bus);      self.op_cmp(self.x, v); 2 }
            0xE4 => { let ea = self.addr_zp(bus); let v = bus.read(ea); self.op_cmp(self.x, v); 3 }
            0xEC => { let ea = self.addr_abs(bus); let v = bus.read(ea); self.op_cmp(self.x, v); 4 }

            // ── CPY ───────────────────────────────────────────────────────
            0xC0 => { let v = self.fetch(bus);      self.op_cmp(self.y, v); 2 }
            0xC4 => { let ea = self.addr_zp(bus); let v = bus.read(ea); self.op_cmp(self.y, v); 3 }
            0xCC => { let ea = self.addr_abs(bus); let v = bus.read(ea); self.op_cmp(self.y, v); 4 }

            // ── LDA ───────────────────────────────────────────────────────
            0xA1 => { let ea = self.addr_indx(bus); self.a = bus.read(ea); self.set_nz(self.a); 6 }
            0xA5 => { let ea = self.addr_zp(bus);   self.a = bus.read(ea); self.set_nz(self.a); 3 }
            0xA9 => { self.a = self.fetch(bus);                             self.set_nz(self.a); 2 }
            0xAD => { let ea = self.addr_abs(bus);  self.a = bus.read(ea); self.set_nz(self.a); 4 }
            0xB1 => { let (ea,p) = self.addr_indy(bus); self.a = bus.read(ea); self.set_nz(self.a); 5+p as u32 }
            0xB2 => { let ea = self.addr_zpi(bus);  self.a = bus.read(ea); self.set_nz(self.a); 5 }
            0xB5 => { let ea = self.addr_zpx(bus);  self.a = bus.read(ea); self.set_nz(self.a); 4 }
            0xB9 => { let (ea,p) = self.addr_absy(bus); self.a = bus.read(ea); self.set_nz(self.a); 4+p as u32 }
            0xBD => { let (ea,p) = self.addr_absx(bus); self.a = bus.read(ea); self.set_nz(self.a); 4+p as u32 }

            // ── LDX ───────────────────────────────────────────────────────
            0xA2 => { self.x = self.fetch(bus);      self.set_nz(self.x); 2 }
            0xA6 => { let ea = self.addr_zp(bus);  self.x = bus.read(ea); self.set_nz(self.x); 3 }
            0xAE => { let ea = self.addr_abs(bus); self.x = bus.read(ea); self.set_nz(self.x); 4 }
            0xB6 => { let ea = self.addr_zpy(bus); self.x = bus.read(ea); self.set_nz(self.x); 4 }
            0xBE => { let (ea,p) = self.addr_absy(bus); self.x = bus.read(ea); self.set_nz(self.x); 4+p as u32 }

            // ── LDY ───────────────────────────────────────────────────────
            0xA0 => { self.y = self.fetch(bus);      self.set_nz(self.y); 2 }
            0xA4 => { let ea = self.addr_zp(bus);  self.y = bus.read(ea); self.set_nz(self.y); 3 }
            0xAC => { let ea = self.addr_abs(bus); self.y = bus.read(ea); self.set_nz(self.y); 4 }
            0xB4 => { let ea = self.addr_zpx(bus); self.y = bus.read(ea); self.set_nz(self.y); 4 }
            0xBC => { let (ea,p) = self.addr_absx(bus); self.y = bus.read(ea); self.set_nz(self.y); 4+p as u32 }

            // ── STA ───────────────────────────────────────────────────────
            0x81 => { let ea = self.addr_indx(bus); bus.write(ea, self.a); 6 }
            0x85 => { let ea = self.addr_zp(bus);   bus.write(ea, self.a); 3 }
            0x8D => { let ea = self.addr_abs(bus);  bus.write(ea, self.a); 4 }
            0x91 => { let (ea,_) = self.addr_indy(bus); bus.write(ea, self.a); 6 }
            0x92 => { let ea = self.addr_zpi(bus);  bus.write(ea, self.a); 5 }
            0x95 => { let ea = self.addr_zpx(bus);  bus.write(ea, self.a); 4 }
            0x99 => { let (ea,_) = self.addr_absy(bus); bus.write(ea, self.a); 5 }
            0x9D => { let (ea,_) = self.addr_absx(bus); bus.write(ea, self.a); 5 }

            // ── STX ───────────────────────────────────────────────────────
            0x86 => { let ea = self.addr_zp(bus);  bus.write(ea, self.x); 3 }
            0x8E => { let ea = self.addr_abs(bus); bus.write(ea, self.x); 4 }
            0x96 => { let ea = self.addr_zpy(bus); bus.write(ea, self.x); 4 }

            // ── STY ───────────────────────────────────────────────────────
            0x84 => { let ea = self.addr_zp(bus);  bus.write(ea, self.y); 3 }
            0x8C => { let ea = self.addr_abs(bus); bus.write(ea, self.y); 4 }
            0x94 => { let ea = self.addr_zpx(bus); bus.write(ea, self.y); 4 }

            // ── STZ (65C02) ───────────────────────────────────────────────
            0x64 => { let ea = self.addr_zp(bus);       bus.write(ea, 0); 3 }
            0x74 => { let ea = self.addr_zpx(bus);      bus.write(ea, 0); 4 }
            0x9C => { let ea = self.addr_abs(bus);      bus.write(ea, 0); 4 }
            0x9E => { let (ea,_) = self.addr_absx(bus); bus.write(ea, 0); 5 }

            // ── ASL ───────────────────────────────────────────────────────
            0x0A => { self.op_asl(bus, 0, true); 2 }
            0x06 => { let ea = self.addr_zp(bus);       self.op_asl(bus, ea, false); 5 }
            0x16 => { let ea = self.addr_zpx(bus);      self.op_asl(bus, ea, false); 6 }
            0x0E => { let ea = self.addr_abs(bus);      self.op_asl(bus, ea, false); 6 }
            0x1E => { let (ea,_) = self.addr_absx(bus); self.op_asl(bus, ea, false); 6 }

            // ── LSR ───────────────────────────────────────────────────────
            0x4A => { self.op_lsr(bus, 0, true); 2 }
            0x46 => { let ea = self.addr_zp(bus);       self.op_lsr(bus, ea, false); 5 }
            0x56 => { let ea = self.addr_zpx(bus);      self.op_lsr(bus, ea, false); 6 }
            0x4E => { let ea = self.addr_abs(bus);      self.op_lsr(bus, ea, false); 6 }
            0x5E => { let (ea,_) = self.addr_absx(bus); self.op_lsr(bus, ea, false); 6 }

            // ── ROL ───────────────────────────────────────────────────────
            0x2A => { self.op_rol(bus, 0, true); 2 }
            0x26 => { let ea = self.addr_zp(bus);       self.op_rol(bus, ea, false); 5 }
            0x36 => { let ea = self.addr_zpx(bus);      self.op_rol(bus, ea, false); 6 }
            0x2E => { let ea = self.addr_abs(bus);      self.op_rol(bus, ea, false); 6 }
            0x3E => { let (ea,_) = self.addr_absx(bus); self.op_rol(bus, ea, false); 6 }

            // ── ROR ───────────────────────────────────────────────────────
            0x6A => { self.op_ror(bus, 0, true); 2 }
            0x66 => { let ea = self.addr_zp(bus);       self.op_ror(bus, ea, false); 5 }
            0x76 => { let ea = self.addr_zpx(bus);      self.op_ror(bus, ea, false); 6 }
            0x6E => { let ea = self.addr_abs(bus);      self.op_ror(bus, ea, false); 6 }
            0x7E => { let (ea,_) = self.addr_absx(bus); self.op_ror(bus, ea, false); 6 }

            // ── INC ───────────────────────────────────────────────────────
            0x1A => { self.a = self.a.wrapping_add(1); self.set_nz(self.a); 2 } // INC A
            0xE6 => { let ea = self.addr_zp(bus);       let v = bus.read(ea).wrapping_add(1); bus.write(ea, v); self.set_nz(v); 5 }
            0xF6 => { let ea = self.addr_zpx(bus);      let v = bus.read(ea).wrapping_add(1); bus.write(ea, v); self.set_nz(v); 6 }
            0xEE => { let ea = self.addr_abs(bus);      let v = bus.read(ea).wrapping_add(1); bus.write(ea, v); self.set_nz(v); 6 }
            0xFE => { let (ea,_) = self.addr_absx(bus); let v = bus.read(ea).wrapping_add(1); bus.write(ea, v); self.set_nz(v); 7 }

            // ── DEC ───────────────────────────────────────────────────────
            0x3A => { self.a = self.a.wrapping_sub(1); self.set_nz(self.a); 2 } // DEC A
            0xC6 => { let ea = self.addr_zp(bus);       let v = bus.read(ea).wrapping_sub(1); bus.write(ea, v); self.set_nz(v); 5 }
            0xD6 => { let ea = self.addr_zpx(bus);      let v = bus.read(ea).wrapping_sub(1); bus.write(ea, v); self.set_nz(v); 6 }
            0xCE => { let ea = self.addr_abs(bus);      let v = bus.read(ea).wrapping_sub(1); bus.write(ea, v); self.set_nz(v); 6 }
            0xDE => { let (ea,_) = self.addr_absx(bus); let v = bus.read(ea).wrapping_sub(1); bus.write(ea, v); self.set_nz(v); 7 }

            // ── INX / INY / DEX / DEY ─────────────────────────────────────
            0xE8 => { self.x = self.x.wrapping_add(1); self.set_nz(self.x); 2 }
            0xC8 => { self.y = self.y.wrapping_add(1); self.set_nz(self.y); 2 }
            0xCA => { self.x = self.x.wrapping_sub(1); self.set_nz(self.x); 2 }
            0x88 => { self.y = self.y.wrapping_sub(1); self.set_nz(self.y); 2 }

            // ── Transfers ─────────────────────────────────────────────────
            0xAA => { self.x = self.a; self.set_nz(self.x); 2 }
            0xA8 => { self.y = self.a; self.set_nz(self.y); 2 }
            0x8A => { self.a = self.x; self.set_nz(self.a); 2 }
            0x98 => { self.a = self.y; self.set_nz(self.a); 2 }
            0xBA => { self.x = self.sp; self.set_nz(self.x); 2 }
            0x9A => { self.sp = self.x; 2 }

            // ── Stack ─────────────────────────────────────────────────────
            0x48 => { let v = self.a;  self.push(bus, v); 3 }
            0x08 => { let v = self.p | FLAG_B | FLAG_U; self.push(bus, v); 3 }
            0x5A => { let v = self.y;  self.push(bus, v); 3 } // PHY
            0xDA => { let v = self.x;  self.push(bus, v); 3 } // PHX
            0x68 => { self.a = self.pop(bus); self.set_nz(self.a); 4 }
            0x28 => { self.p = self.pop(bus) | FLAG_U; 4 }
            0x7A => { self.y = self.pop(bus); self.set_nz(self.y); 4 } // PLY
            0xFA => { self.x = self.pop(bus); self.set_nz(self.x); 4 } // PLX

            // ── Flag operations ───────────────────────────────────────────
            0x18 => { self.set_flag(FLAG_C, false); 2 }
            0x38 => { self.set_flag(FLAG_C, true);  2 }
            0x58 => { self.set_flag(FLAG_I, false); 2 }
            0x78 => { self.set_flag(FLAG_I, true);  2 }
            0xD8 => { self.set_flag(FLAG_D, false); 2 }
            0xF8 => { self.set_flag(FLAG_D, true);  2 }
            0xB8 => { self.set_flag(FLAG_V, false); 2 }

            // ── BIT ───────────────────────────────────────────────────────
            0x24 => { let ea = self.addr_zp(bus);       let v = bus.read(ea); self.op_bit(v); 3 }
            0x2C => { let ea = self.addr_abs(bus);      let v = bus.read(ea); self.op_bit(v); 4 }
            0x34 => { let ea = self.addr_zpx(bus);      let v = bus.read(ea); self.op_bit(v); 4 }
            0x3C => { let (ea,p) = self.addr_absx(bus); let v = bus.read(ea); self.op_bit(v); 4+p as u32 }
            0x89 => { let v = self.fetch(bus);          self.op_bit_imm(v); 2 }

            // ── TSB / TRB (65C02) ─────────────────────────────────────────
            0x04 => { let ea = self.addr_zp(bus);  self.op_tsb(bus, ea); 5 }
            0x0C => { let ea = self.addr_abs(bus); self.op_tsb(bus, ea); 6 }
            0x14 => { let ea = self.addr_zp(bus);  self.op_trb(bus, ea); 5 }
            0x1C => { let ea = self.addr_abs(bus); self.op_trb(bus, ea); 6 }

            // ── Branches ──────────────────────────────────────────────────
            0x80 => { let e = self.branch(bus, true)                           as u32; 2 + e } // BRA
            0x90 => { let e = self.branch(bus, !self.flag(FLAG_C))             as u32; 2 + e } // BCC
            0xB0 => { let e = self.branch(bus,  self.flag(FLAG_C))             as u32; 2 + e } // BCS
            0xF0 => { let e = self.branch(bus,  self.flag(FLAG_Z))             as u32; 2 + e } // BEQ
            0xD0 => { let e = self.branch(bus, !self.flag(FLAG_Z))             as u32; 2 + e } // BNE
            0x30 => { let e = self.branch(bus,  self.flag(FLAG_N))             as u32; 2 + e } // BMI
            0x10 => { let e = self.branch(bus, !self.flag(FLAG_N))             as u32; 2 + e } // BPL
            0x70 => { let e = self.branch(bus,  self.flag(FLAG_V))             as u32; 2 + e } // BVS
            0x50 => { let e = self.branch(bus, !self.flag(FLAG_V))             as u32; 2 + e } // BVC

            // ── JMP ───────────────────────────────────────────────────────
            0x4C => { self.pc = self.fetch16(bus); 3 }
            0x6C => {
                // JMP (abs) — 65C02: page-wrap bug FIXED
                let ptr = self.fetch16(bus);
                self.pc = Self::read16(bus, ptr);
                5
            }
            0x7C => {
                // JMP (abs,X) — 65C02 only
                let base = self.fetch16(bus);
                let ptr  = base.wrapping_add(self.x as u16);
                self.pc = Self::read16(bus, ptr);
                6
            }

            // ── JSR / RTS ─────────────────────────────────────────────────
            0x20 => {
                let target = self.fetch16(bus);
                let ret = self.pc.wrapping_sub(1);
                self.push(bus, (ret >> 8) as u8);
                self.push(bus, (ret & 0xFF) as u8);
                self.pc = target;
                6
            }
            0x60 => {
                let lo = self.pop(bus) as u16;
                let hi = self.pop(bus) as u16;
                self.pc = (lo | (hi << 8)).wrapping_add(1);
                6
            }

            // ── RTI ───────────────────────────────────────────────────────
            0x40 => {
                self.p  = self.pop(bus) | FLAG_U;
                let lo  = self.pop(bus) as u16;
                let hi  = self.pop(bus) as u16;
                self.pc = lo | (hi << 8);
                6
            }

            // ── NOP ───────────────────────────────────────────────────────
            0xEA => 2,

            // ── WAI / STP (65C02) ─────────────────────────────────────────
            0xCB => { self.waiting = true; 3 }
            0xDB => { self.halted  = true; 3 }

            // ── RMB0-7 (65C02) ───────────────────────────────────────────
            0x07 | 0x17 | 0x27 | 0x37 | 0x47 | 0x57 | 0x67 | 0x77 => {
                let bit = (opcode >> 4) as u8;
                let ea = self.addr_zp(bus);
                let v = bus.read(ea) & !(1 << bit);
                bus.write(ea, v);
                5
            }

            // ── SMB0-7 (65C02) ────────────────────────────────────────────
            0x87 | 0x97 | 0xA7 | 0xB7 | 0xC7 | 0xD7 | 0xE7 | 0xF7 => {
                let bit = ((opcode >> 4) - 8) as u8;
                let ea = self.addr_zp(bus);
                let v = bus.read(ea) | (1 << bit);
                bus.write(ea, v);
                5
            }

            // ── BBR0-7 (65C02) — Branch if Bit Reset ─────────────────────
            0x0F | 0x1F | 0x2F | 0x3F | 0x4F | 0x5F | 0x6F | 0x7F => {
                let bit = (opcode >> 4) as u8;
                let ea  = self.addr_zp(bus);
                let v   = bus.read(ea);
                let e   = self.branch(bus, v & (1 << bit) == 0) as u32;
                5 + e
            }

            // ── BBS0-7 (65C02) — Branch if Bit Set ───────────────────────
            0x8F | 0x9F | 0xAF | 0xBF | 0xCF | 0xDF | 0xEF | 0xFF => {
                let bit = ((opcode >> 4) - 8) as u8;
                let ea  = self.addr_zp(bus);
                let v   = bus.read(ea);
                let e   = self.branch(bus, v & (1 << bit) != 0) as u32;
                5 + e
            }

            // ── All other opcodes → NOP (with approximate cycle counts) ───
            0x02 | 0x22 | 0x42 | 0x62 | 0x82 | 0xC2 | 0xE2 => {
                // 2-byte NOPs (consume immediate byte)
                self.pc = self.pc.wrapping_add(1); 2
            }
            0x44 | 0x54 | 0xD4 | 0xF4 => {
                // 2-byte zero-page NOPs
                self.pc = self.pc.wrapping_add(1); 3
            }
            0x5C | 0xDC | 0xFC => {
                // 3-byte absolute NOPs
                self.pc = self.pc.wrapping_add(2); 4
            }
            _ => 1, // All other undefined = 1-cycle NOP
        };

        self.cycles += cycles as u64;
        cycles
    }
}
