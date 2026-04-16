/// TMS9918A Video Display Processor emulation.
///
/// Bus mapping (EXP_TMS9918A_V1 ISA card → !VERA_CS $C000–$C3FF):
///   $C000  Data port        (A0 = 0)
///   $C001  Address/mode port (A0 = 1)
///
/// Write to address port: two bytes
///   1st byte: address low (bits 0–7)
///   2nd byte: bits 5–0 = address high (bits 13–8)
///             bit 6 = 1 → register write (reg# in bits 2–0 of 1st byte)
///             bit 6 = 0 → VRAM address set (read if bit 7=0 of 2nd byte? no — TMS9918 has no R/W bit here)
///   After VRAM address is set:  read data port = VRAM read, write data port = VRAM write
///
/// Registers R0–R7:
///   R0[1]   M3 (Graphics II when set with R1[4] M2=1)
///   R0[0]   External video enable (ignored)
///   R1[7]   4/16K RAM select (we always use 16K)
///   R1[6]   Screen blanked when 0
///   R1[5]   IRQ enable (VBlank)
///   R1[4]   M2 (Text mode when set with R1[3] M1=1)
///   R1[3]   M1 (Text mode when set alone; Multicolor when M3=0, M2=0, M1=1)
///   R1[1]   Sprite size (0=8×8, 1=16×16)
///   R1[0]   Sprite magnification (0=×1, 1=×2)
///   R2[3:0] Name table base >> 10  ($000–$3C00 in VRAM)
///   R3[7:0] Color table base >> 6  ($000–$3FC0 in VRAM)
///   R4[2:0] Pattern generator base >> 11 ($0000–$3800)
///   R5[6:0] Sprite attribute table base >> 7 ($0000–$3F80)
///   R6[2:0] Sprite pattern generator base >> 11
///   R7[7:4] Text color (Mode 1 foreground)
///   R7[3:0] Backdrop/border color

pub const WIDTH:  usize = 256;
pub const HEIGHT: usize = 192;
pub const FB_LEN: usize = WIDTH * HEIGHT;

/// ARGB8888 palette (index 0 = transparent rendered as backdrop).
pub const PALETTE: [u32; 16] = [
    0xFF000000, // 0  transparent → backdrop
    0xFF000000, // 1  black
    0xFF3EB849, // 2  medium green
    0xFF74D07D, // 3  light green
    0xFF5955E0, // 4  dark blue
    0xFF8076F1, // 5  light blue
    0xFFB95E51, // 6  dark red
    0xFF65DBEF, // 7  cyan
    0xFFDB6559, // 8  medium red
    0xFFFF897D, // 9  light red
    0xFFCCC35E, // 10 dark yellow
    0xFFDED087, // 11 light yellow
    0xFF3AA241, // 12 dark green
    0xFFB766B5, // 13 magenta
    0xFFCCCCCC, // 14 gray
    0xFFFFFFFF, // 15 white
];

pub struct Tms9918a {
    pub vram:     Box<[u8; 0x4000]>,   // 16 KB
    pub regs:     [u8; 8],
    pub status:   u8,
    // Address latch for two-byte write to mode port
    addr_latch:   Option<u8>,
    pub vram_addr: u16,
    // read-ahead buffer (TMS9918 pre-fetches on read)
    read_buf:     u8,
    // pending IRQ output
    pub irq:      bool,
    // cycle counter for ~60 Hz frame timing (at 1 MHz CPU: ~16667 cycles/frame)
    cycle_accum:  u32,
    // rendered framebuffer (ARGB8888, shared with video thread)
    pub framebuf: Vec<u32>,
    pub frame_dirty: bool,
}

impl Default for Tms9918a {
    fn default() -> Self {
        Self {
            vram:        Box::new([0u8; 0x4000]),
            regs:        [0u8; 8],
            status:      0,
            addr_latch:  None,
            vram_addr:   0,
            read_buf:    0,
            irq:         false,
            cycle_accum: 0,
            framebuf:    vec![0xFF000000u32; FB_LEN],
            frame_dirty: false,
        }
    }
}

impl Tms9918a {
    // ── Bus interface ─────────────────────────────────────────────────────────

    /// Read — A0=0 → data port, A0=1 → status port.
    pub fn read(&mut self, addr: u16) -> u8 {
        if addr & 1 == 0 {
            // Data port: return pre-fetched byte, then fetch next
            let v = self.read_buf;
            self.read_buf = self.vram[self.vram_addr as usize & 0x3FFF];
            self.vram_addr = self.vram_addr.wrapping_add(1) & 0x3FFF;
            self.addr_latch = None;
            v
        } else {
            // Status port: read clears INT flag and sprite flags
            let s = self.status;
            self.status &= 0x1F;  // clear F (bit7), 5th sprite (bit6), coincidence (bit5)
            self.irq = false;
            self.addr_latch = None;
            s
        }
    }

    /// Write — A0=0 → data port, A0=1 → address/register port.
    pub fn write(&mut self, addr: u16, val: u8) {
        if addr & 1 == 0 {
            // Data port → write to VRAM
            self.vram[self.vram_addr as usize & 0x3FFF] = val;
            self.read_buf = val;
            self.vram_addr = self.vram_addr.wrapping_add(1) & 0x3FFF;
            self.addr_latch = None;
        } else {
            // Address/register port — two-byte sequence
            match self.addr_latch.take() {
                None => {
                    // First byte: latch it
                    self.addr_latch = Some(val);
                }
                Some(lo) => {
                    // Second byte
                    if val & 0x80 != 0 {
                        // Register write (bit 7 set in 2nd byte for TMS9918A)
                        // Note: bit6 also used by some TI docs; use bit7 per TMS9918A datasheet
                        let reg = val & 0x07;
                        self.regs[reg as usize] = lo;
                    } else {
                        // VRAM address set
                        let hi = (val & 0x3F) as u16;
                        self.vram_addr = ((hi << 8) | lo as u16) & 0x3FFF;
                        // Pre-fetch
                        self.read_buf = self.vram[self.vram_addr as usize];
                        // Don't advance on address set — advance happens on first data read
                    }
                }
            }
        }
    }

    // ── Tick ──────────────────────────────────────────────────────────────────

    /// Called from bus.tick() with CPU cycles elapsed.
    /// Returns true when a VBlank IRQ fires.
    pub fn tick(&mut self, cycles: u32) -> bool {
        self.cycle_accum += cycles;
        // ~59.94 Hz at 3.579545 MHz pixel clock; at 1 MHz CPU approx 16667 cycles/frame
        if self.cycle_accum >= 16_667 {
            self.cycle_accum -= 16_667;
            self.render_frame();
            self.frame_dirty = true;
            // Set VBlank flag in status
            self.status |= 0x80;
            // Fire IRQ if IE set (R1 bit 5)
            if self.regs[1] & 0x20 != 0 {
                self.irq = true;
                return true;
            }
        }
        false
    }

    // ── Rendering ─────────────────────────────────────────────────────────────

    pub fn render_frame(&mut self) {
        let blank    = self.regs[1] & 0x40 == 0;
        let backdrop = (self.regs[7] & 0x0F) as usize;
        let bg_color = PALETTE[if backdrop == 0 { 1 } else { backdrop }];

        if blank {
            self.framebuf.fill(bg_color);
            return;
        }

        let mode = self.video_mode();
        match mode {
            VideoMode::GraphicsI  => self.render_g1(bg_color),
            VideoMode::GraphicsII => self.render_g2(bg_color),
            VideoMode::Text       => self.render_text(),
            VideoMode::Multicolor => self.render_mc(bg_color),
        }

        // Sprites (all modes except Text)
        if mode != VideoMode::Text {
            self.render_sprites();
        }
    }

    fn video_mode(&self) -> VideoMode {
        let m1 = self.regs[1] & 0x10 != 0;
        let m2 = self.regs[1] & 0x08 != 0;
        let m3 = self.regs[0] & 0x02 != 0;
        match (m3, m2, m1) {
            (false, false, false) => VideoMode::GraphicsI,
            (false, false, true)  => VideoMode::Multicolor,
            (false, true,  false) => VideoMode::Text,
            (true,  false, false) => VideoMode::GraphicsII,
            _                     => VideoMode::GraphicsI, // undefined → G1
        }
    }

    /// Graphics I: 32×24 name table, 256 patterns, 32-byte color table (fg/bg per 8 patterns).
    fn render_g1(&mut self, bg_color: u32) {
        let name_base    = (self.regs[2] as usize & 0x0F) << 10;
        let color_base   = (self.regs[3] as usize) << 6;
        let pattern_base = (self.regs[4] as usize & 0x07) << 11;

        for row in 0..24usize {
            for col in 0..32usize {
                let name_addr = name_base + row * 32 + col;
                let tile = self.vram[name_addr & 0x3FFF] as usize;

                let color_byte = self.vram[(color_base + tile / 8) & 0x3FFF];
                let fg = (color_byte >> 4) as usize;
                let bg = (color_byte & 0x0F) as usize;
                let fg_px = PALETTE[if fg == 0 { 1 } else { fg }];
                let bg_px = if bg == 0 { bg_color } else { PALETTE[bg] };

                for py in 0..8usize {
                    let pattern_byte = self.vram[(pattern_base + tile * 8 + py) & 0x3FFF];
                    let screen_y = row * 8 + py;
                    if screen_y >= HEIGHT { break; }
                    for px in 0..8usize {
                        let screen_x = col * 8 + px;
                        if screen_x >= WIDTH { break; }
                        let bit = (pattern_byte >> (7 - px)) & 1;
                        self.framebuf[screen_y * WIDTH + screen_x] =
                            if bit != 0 { fg_px } else { bg_px };
                    }
                }
            }
        }
    }

    /// Graphics II: 256×192 bitmap, pattern and color tables split into three 8KB thirds.
    fn render_g2(&mut self, bg_color: u32) {
        let name_base    = (self.regs[2] as usize & 0x0F) << 10;
        let color_base   = (self.regs[3] as usize & 0x80) << 6;  // mask: upper bit only
        let pattern_base = (self.regs[4] as usize & 0x04) << 11; // mask: upper bit only

        for row in 0..24usize {
            let third = row / 8; // 0,1,2 — each third = 256 patterns
            for col in 0..32usize {
                let name_addr = name_base + row * 32 + col;
                let tile = self.vram[name_addr & 0x3FFF] as usize;

                for py in 0..8usize {
                    let pat_idx  = third * 256 * 8 + tile * 8 + py;
                    let pat_byte = self.vram[(pattern_base + pat_idx) & 0x3FFF];
                    let col_byte = self.vram[(color_base   + pat_idx) & 0x3FFF];
                    let fg = (col_byte >> 4) as usize;
                    let bg = (col_byte & 0x0F) as usize;
                    let fg_px = PALETTE[if fg == 0 { 1 } else { fg }];
                    let bg_px = if bg == 0 { bg_color } else { PALETTE[bg] };

                    let screen_y = row * 8 + py;
                    if screen_y >= HEIGHT { break; }
                    for px in 0..8usize {
                        let screen_x = col * 8 + px;
                        if screen_x >= WIDTH { break; }
                        let bit = (pat_byte >> (7 - px)) & 1;
                        self.framebuf[screen_y * WIDTH + screen_x] =
                            if bit != 0 { fg_px } else { bg_px };
                    }
                }
            }
        }
    }

    /// Text mode: 40×24 tiles, 240×192, no sprites. 8-pixel-wide chars but only 6 px used.
    fn render_text(&mut self) {
        let fg_idx = (self.regs[7] >> 4) as usize;
        let bg_idx = (self.regs[7] & 0x0F) as usize;
        let fg_px  = PALETTE[if fg_idx == 0 { 15 } else { fg_idx }];
        let bg_px  = PALETTE[if bg_idx == 0 { 1  } else { bg_idx }];

        let name_base    = (self.regs[2] as usize & 0x0F) << 10;
        let pattern_base = (self.regs[4] as usize & 0x07) << 11;

        // Fill backdrop — text is 240 px centered in 256 (8 px each side)
        self.framebuf.fill(bg_px);

        for row in 0..24usize {
            for col in 0..40usize {
                let tile = self.vram[(name_base + row * 40 + col) & 0x3FFF] as usize;
                for py in 0..8usize {
                    let pat = self.vram[(pattern_base + tile * 8 + py) & 0x3FFF];
                    let screen_y = row * 8 + py;
                    if screen_y >= HEIGHT { break; }
                    for px in 0..6usize {
                        let screen_x = 8 + col * 6 + px;
                        if screen_x >= WIDTH { break; }
                        let bit = (pat >> (7 - px)) & 1;
                        self.framebuf[screen_y * WIDTH + screen_x] =
                            if bit != 0 { fg_px } else { bg_px };
                    }
                }
            }
        }
    }

    /// Multicolor: 64×48 "fat pixels" (4×4 screen pixels each).
    fn render_mc(&mut self, bg_color: u32) {
        let name_base    = (self.regs[2] as usize & 0x0F) << 10;
        let pattern_base = (self.regs[4] as usize & 0x07) << 11;

        for row in 0..24usize {
            for col in 0..32usize {
                let tile = self.vram[(name_base + row * 32 + col) & 0x3FFF] as usize;
                for py in 0..8usize {
                    let pat_byte = self.vram[(pattern_base + tile * 8 + py) & 0x3FFF];
                    let c_left  = (pat_byte >> 4) as usize;
                    let c_right = (pat_byte & 0x0F) as usize;
                    let left_px  = if c_left  == 0 { bg_color } else { PALETTE[c_left ] };
                    let right_px = if c_right == 0 { bg_color } else { PALETTE[c_right] };

                    // Each pattern row = 2 fat pixels high → fat_y = row*8 + py → 2 real rows
                    let base_y = (row * 8 + py) * 1; // 1:1 mapping (192/48 = 4)
                    // Actually: 48 fat rows → each = 4 screen px; name table has 24 rows of 32
                    // py 0..8 in pattern represents half-rows — so each pat row = 2 fat pixels?
                    // Simplification: map directly, 24*8=192 rows, 32*8=256 cols, same as G1
                    // but color comes from nibbles:
                    let screen_y = row * 8 + py;
                    if screen_y >= HEIGHT { break; }
                    for px in 0..8usize {
                        let screen_x = col * 8 + px;
                        if screen_x >= WIDTH { break; }
                        self.framebuf[screen_y * WIDTH + screen_x] =
                            if px < 4 { left_px } else { right_px };
                    }
                    let _ = base_y;
                }
            }
        }
    }

    /// Sprite rendering — overlays sprites on top of background.
    fn render_sprites(&mut self) {
        let attr_base    = (self.regs[5] as usize & 0x7F) << 7;
        let pattern_base = (self.regs[6] as usize & 0x07) << 11;
        let size16       = self.regs[1] & 0x02 != 0; // 16×16 sprites
        let magnify      = self.regs[1] & 0x01 != 0; // ×2

        let sprite_size = if size16 { 16usize } else { 8usize };
        let pixel_size  = if magnify { 2usize } else { 1usize };

        let mut line_count = [0u8; HEIGHT];
        let mut coincidence = false;

        'sprite: for s in 0..32usize {
            let attr = attr_base + s * 4;
            let y_raw = self.vram[(attr)     & 0x3FFF];
            let x_raw = self.vram[(attr + 1) & 0x3FFF];
            let pat   = self.vram[(attr + 2) & 0x3FFF] as usize;
            let color_attr = self.vram[(attr + 3) & 0x3FFF];

            if y_raw == 0xD0 { break; }  // terminator

            let color_idx = (color_attr & 0x0F) as usize;
            let early_clock = (color_attr & 0x80) != 0;

            if color_idx == 0 { continue; } // transparent sprite

            // Y: 0xD0 = stop; sprite Y is 1-based (y+1 = first line)
            let y_screen = y_raw.wrapping_add(1) as usize;
            let x_screen: i32 = x_raw as i32 - if early_clock { 32 } else { 0 };

            let pat_idx = if size16 { pat & !0x03 } else { pat }; // 16×16 uses 4 consecutive

            for row in 0..sprite_size {
                for mag_row in 0..pixel_size {
                    let screen_y = y_screen + row * pixel_size + mag_row;
                    if screen_y >= HEIGHT { continue; }

                    // 5th sprite on line
                    if line_count[screen_y] >= 4 {
                        self.status = (self.status & 0xE0) | 0x40 | (s as u8 & 0x1F);
                        break 'sprite;
                    }

                    let pat_row = if size16 && row >= 8 {
                        (pat_idx + 16) * 8 + (row - 8)
                    } else {
                        pat_idx * 8 + row
                    };

                    let pat_byte_h = self.vram[(pattern_base + pat_row) & 0x3FFF];
                    let pat_byte_l = if size16 {
                        self.vram[(pattern_base + pat_row + 8) & 0x3FFF]
                    } else { 0 };

                    let bits: u16 = if size16 {
                        ((pat_byte_h as u16) << 8) | pat_byte_l as u16
                    } else {
                        (pat_byte_h as u16) << 8
                    };

                    for col in 0..(sprite_size * pixel_size) {
                        let px = col / pixel_size;
                        let sx = x_screen + col as i32;
                        if sx < 0 || sx >= WIDTH as i32 { continue; }
                        let sx = sx as usize;
                        let bit_pos = 15 - px;
                        if (bits >> bit_pos) & 1 != 0 {
                            let dst = &mut self.framebuf[screen_y * WIDTH + sx];
                            if *dst != 0xFF000000 && color_idx != 0 {
                                coincidence = true;
                            }
                            *dst = PALETTE[color_idx];
                        }
                    }
                    line_count[screen_y] += 1;
                }
            }
        }

        if coincidence {
            self.status |= 0x20;
        }
    }

    // ── Debug / TUI info ──────────────────────────────────────────────────────

    pub fn mode_str(&self) -> &'static str {
        match self.video_mode() {
            VideoMode::GraphicsI  => "G1 (32×24)",
            VideoMode::GraphicsII => "G2 (bitmap)",
            VideoMode::Text       => "Text (40×24)",
            VideoMode::Multicolor => "MC (64×48)",
        }
    }

    pub fn name_table_addr(&self)    -> u16 { ((self.regs[2] as u16 & 0x0F) << 10) }
    pub fn color_table_addr(&self)   -> u16 { (self.regs[3] as u16) << 6 }
    pub fn pattern_gen_addr(&self)   -> u16 { ((self.regs[4] as u16 & 0x07) << 11) }
    pub fn sprite_attr_addr(&self)   -> u16 { ((self.regs[5] as u16 & 0x7F) << 7) }
    pub fn sprite_pat_addr(&self)    -> u16 { ((self.regs[6] as u16 & 0x07) << 11) }
    pub fn screen_enabled(&self)     -> bool { self.regs[1] & 0x40 != 0 }
    pub fn irq_enabled(&self)        -> bool { self.regs[1] & 0x20 != 0 }
}

#[derive(PartialEq)]
enum VideoMode { GraphicsI, GraphicsII, Text, Multicolor }
