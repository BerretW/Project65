/// ROM – read-only, loadable from a binary file.
/// Mirrors to fill the entire 8 KB window ($E000-$FFFF).
pub struct Rom {
    data: [u8; 0x2000], // 8 KB
}

impl Rom {
    pub fn new() -> Self {
        Self { data: [0xFF; 0x2000] }
    }

    /// Load raw binary; offset 0 → $E000. Excess bytes are silently ignored.
    pub fn load(&mut self, bytes: &[u8]) {
        let n = bytes.len().min(0x2000);
        self.data[..n].copy_from_slice(&bytes[..n]);
    }

    pub fn read(&self, addr: u16) -> u8 {
        let off = addr.wrapping_sub(0xE000) as usize & 0x1FFF;
        self.data[off]
    }

    pub fn slice(&self, from: u16, len: usize) -> &[u8] {
        let off = from.wrapping_sub(0xE000) as usize & 0x1FFF;
        let end = (off + len).min(0x2000);
        &self.data[off..end]
    }
}
