/// Generic RAM device
pub struct Ram {
    data: Vec<u8>,
    base: u16,
    size: usize,
}

impl Ram {
    pub fn new(base: u16, size: usize) -> Self {
        Self { data: vec![0u8; size], base, size }
    }

    pub fn read(&self, addr: u16) -> u8 {
        let off = addr.wrapping_sub(self.base) as usize;
        if off < self.size { self.data[off] } else { 0xFF }
    }

    pub fn write(&mut self, addr: u16, val: u8) {
        let off = addr.wrapping_sub(self.base) as usize;
        if off < self.size { self.data[off] = val; }
    }

    /// Direct slice access for TUI memory dump
    pub fn slice(&self, from: u16, len: usize) -> &[u8] {
        let off = from.wrapping_sub(self.base) as usize;
        let end = (off + len).min(self.size);
        &self.data[off.min(self.size)..end]
    }
}
