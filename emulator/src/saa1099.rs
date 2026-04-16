/// SAA1099 Sound Generator emulation.
///
/// Bus mapping (ISA DEV0 → $CD00–$CDFF):
///   $CD00  Data register  (write)
///   $CD01  Address latch  (write)
///
/// The SAA1099 has:
///   6 tone channels (independent frequency + amplitude)
///   2 noise channels (fed from tone channels 3 or 5)
///   2 envelope generators (each controls 3 channels)
///   Stereo output (we don't produce actual audio — register state only)
///
/// Register map:
///   $00–$05  Amplitude  ch0–ch5  [7:4]=right, [3:0]=left
///   $08–$0D  Frequency  ch0–ch5  (8-bit, f = clock / (512 * (511 - reg)))
///   $10      Octave ch0/ch1     [6:4]=ch1, [2:0]=ch0
///   $11      Octave ch2/ch3
///   $12      Octave ch4/ch5
///   $14      Tone enable        [5:0] = ch5..ch0
///   $15      Noise enable       [5:0] = ch5..ch0
///   $16      Noise generators   [5:4]=ng1 src, [1:0]=ng0 src
///   $18      Envelope gen 0     [6:4]=shape, [3]=enable, [2]=step, [1]=loop, [0]=ext clock
///   $19      Envelope gen 1
///   $1C      Reset              (write any → reset all channels)

pub struct Saa1099 {
    pub addr:         u8,
    pub amplitude:    [u8; 6],   // R00–R05
    pub frequency:    [u8; 6],   // R08–R0D
    pub octave:       [u8; 3],   // R10–R12  (pairs: [0]=ch0/1, [1]=ch2/3, [2]=ch4/5)
    pub tone_enable:  u8,        // R14 [5:0]
    pub noise_enable: u8,        // R15 [5:0]
    pub noise_gen:    u8,        // R16
    pub envelope:     [u8; 2],   // R18–R19
    pub enabled:      bool,      // set by $1C bit0, cleared by SW reset ($1C bit1) or power-on
    // internal cycle counter for audible frequency (not generating audio, just tracking)
    pub cycle_accum:  u32,
    // Approximate output level 0..255 per channel (L, R) for VU meters in TUI
    pub vu_left:      [u8; 6],
    pub vu_right:     [u8; 6],
}

impl Default for Saa1099 {
    fn default() -> Self {
        Self {
            addr: 0,
            amplitude: [0; 6],
            frequency: [0; 6],
            octave: [0; 3],
            tone_enable: 0,
            noise_enable: 0,
            noise_gen: 0,
            envelope: [0; 2],
            enabled: false,  // chip needs explicit $1C←$01 to enable
            cycle_accum: 0,
            vu_left: [0; 6],
            vu_right: [0; 6],
        }
    }
}

impl Saa1099 {
    // ── Bus interface ─────────────────────────────────────────────────────────

    /// Write: addr=0 → data register, addr=1 → address latch.
    pub fn write(&mut self, port: u16, val: u8) {
        if port & 1 == 0 {
            // Data write
            self.write_reg(self.addr, val);
        } else {
            // Address latch
            self.addr = val;
        }
    }

    /// Read always returns 0xFF (SAA1099 is write-only).
    pub fn read(&self, _port: u16) -> u8 { 0xFF }

    fn write_reg(&mut self, reg: u8, val: u8) {
        match reg {
            0x00..=0x05 => {
                let ch = (reg - 0x00) as usize;
                self.amplitude[ch] = val;
                self.vu_left[ch]   = (val & 0x0F) << 4;
                self.vu_right[ch]  = (val >> 4)   << 4;
            }
            0x08..=0x0D => { self.frequency[(reg - 0x08) as usize] = val; }
            0x10        => { self.octave[0] = val; }
            0x11        => { self.octave[1] = val; }
            0x12        => { self.octave[2] = val; }
            0x14        => { self.tone_enable  = val & 0x3F; }
            0x15        => { self.noise_enable = val & 0x3F; }
            0x16        => { self.noise_gen    = val; }
            0x18        => { self.envelope[0]  = val; }
            0x19        => { self.envelope[1]  = val; }
            0x1C        => {
                // bit1 = SW reset (vynuluj vše), bit0 = sound enable
                if val & 0x02 != 0 {
                    self.reset();               // SW reset — enabled zůstane false
                } else {
                    self.enabled = val & 0x01 != 0;
                }
            }
            _           => {} // ignore unknown
        }
    }

    fn reset(&mut self) {
        self.amplitude    = [0; 6];
        self.frequency    = [0; 6];
        self.octave       = [0; 3];
        self.tone_enable  = 0;
        self.noise_enable = 0;
        self.noise_gen    = 0;
        self.envelope     = [0; 2];
        self.vu_left      = [0; 6];
        self.vu_right     = [0; 6];
        self.enabled      = false;  // po SW resetu čeká na $1C←$01
    }

    // ── Helpers for TUI ───────────────────────────────────────────────────────

    /// Returns approximate frequency [Hz] for channel `ch` (at 8 MHz SAA clock).
    pub fn channel_freq_hz(&self, ch: usize) -> f32 {
        if ch >= 6 { return 0.0; }
        let octave_byte = self.octave[ch / 2];
        let oct = if ch % 2 == 0 { octave_byte & 0x07 } else { (octave_byte >> 4) & 0x07 };
        let freq_reg = self.frequency[ch] as f32;
        // f = (clock / 256) × 2^oct / (511 − freq_reg + 1)
        // SAA1099 clock typically 8 MHz on ISA
        let clock = 8_000_000.0f32;
        let divisor = 512.0 - freq_reg;
        if divisor <= 0.0 { return 0.0; }
        (clock / 256.0) * (1 << oct) as f32 / divisor
    }

    pub fn channel_enabled(&self, ch: usize) -> bool {
        ch < 6 && self.tone_enable & (1 << ch) != 0
    }

    pub fn noise_on_channel(&self, ch: usize) -> bool {
        ch < 6 && self.noise_enable & (1 << ch) != 0
    }

    pub fn envelope_shape_str(&self, eg: usize) -> &'static str {
        if eg >= 2 { return "?"; }
        let v = self.envelope[eg];
        match (v >> 4) & 0x07 {
            0 => "single-decay",
            1 => "repeat-decay",
            2 => "single-tri",
            3 => "repeat-tri",
            4 => "single-attack",
            5 => "repeat-attack",
            6 => "single-alt",
            7 => "repeat-alt",
            _ => "?",
        }
    }
}
