# Project65 — SBC 65C02 IRQ BigBoard

A fully custom **W65C02-based single-board computer** featuring an 8-priority-level IRQ subsystem, three ISA-8 expansion slots, a PS/2 keyboard interface, RS-232 serial port, and a complete firmware stack — including an interactive OS with a RAM-disk filesystem. Accompanied by a **full-featured Rust emulator** with a terminal UI and an **FPGA VGA + audio controller** (`APARTS_BUS`) for Intel MAX 10.

---

## Features

- **CPU:** W65C02S @ up to 8 MHz (jumper-selectable from 32 MHz main oscillator)
- **Memory:** 64 KB total — 32 KB lower RAM + 32 KB upper RAM + 8 KB EEPROM ROM
- **Serial:** R6551 ACIA with a 1.8432 MHz crystal for accurate baud rates
- **Parallel I/O:** 2× W65C22S VIA controllers (keyboard polling + parallel port)
- **PS/2 Keyboard:** ATtiny26 co-processor bridge
- **Interrupt system:** 74HC148 priority encoder + 74HC574 latch — 8 prioritized IRQ lines + NMI
- **Expansion:** 3× ISA-8 slots (TMS9918A, GameDuino, APARTS_BUS FPGA card)
- **FPGA video/audio:** `APARTS_BUS` — VGA 640×480, external SRAM framebuffer, font RAM, 4-ch DDS/ADSR → PCM5102A I²S
- **Firmware:** Two build targets — minimal bootloader and full AppartusOS
- **Emulator:** Rust TUI emulator (`p65emu`) with cycle-accurate peripherals

---

## Repository Structure

```text
Project65/
├── Eagle/              # PCB schematics and board layouts (Eagle CAD)
│   ├── SBC_65C02_IRQ_BigBoard_v10-2-1.*
│   ├── EXP_TMS9918A_V1.*
│   └── EXP_GameDuino_V1.*
├── Firmware/           # 65C02 firmware (cc65 / ca65 toolchain)
│   ├── src/            # Assembly + C sources (drivers, OS, shell, EWOZ)
│   │   └── os/         # AppartusOS modules
│   ├── config/         # ld65 linker configurations
│   ├── output/         # Build artifacts (*.bin, *.map)
│   ├── build_minimal.bat
│   └── build_appartus.bat
├── emulator/           # Rust emulator (p65emu)
│   └── src/            # cpu, bus, ram, rom, acia, via, irq_latch, tui
├── aprts_vga/          # APARTS_BUS FPGA RTL (Verilog) + Quartus + sim
│   ├── aprts_bus.v     # Top-level 6502 bus interface
│   ├── vga_timing.v    # VGA 640×480 @ 60 Hz timing (25 MHz)
│   ├── vga_video_gen.v # Graphics/text pixel path + font RAM
│   ├── sram_controller.v
│   ├── aprts_audio.v   # 4-ch DDS/ADSR + I²S (PCM5102A)
│   ├── 10M02_test.qsf  # Quartus project (MAX 10 10M02SCE144C8G)
│   └── sim/            # ModelSim / Icarus testbenches
├── GAL/                # Glue logic (PLD)
├── tools/
│   ├── uploader.py     # Python/tkinter firmware uploader (COM or TCP)
│   ├── aprts_vga/      # 6502 demo for FPGA VGA
│   ├── audio/          # Audio driver + samples (ca65)
│   └── …               # hello, mem_mon, vera_test, vga_test, …
└── CLAUDE.md           # Full hardware reference (address map, ICs, bugs)
```

---

## Hardware Overview

| Reference | Part | Description |
| --------- | ---- | ----------- |
| IC4 | W65C02SP | Main CPU (CMOS 65C02, DIP-40) |
| IC5 | AT28C64B | 8 KB EEPROM — ROM (`$E000–$FFFF`) |
| IC6 | 62256 | 32 KB SRAM — lower RAM (`$0000–$7FFF`) |
| IC7 | 62256 | 32 KB SRAM — upper RAM (`$8000–$BFFF`) |
| IC8 | DS1233 | Power-on reset supervisor |
| IC16 | W65C22S6TP | VIA #2 (`$CC80`) — parallel port JP8, generates **IRQ1** |
| IC18 | W65C22S6TP | VIA #1 (`$CC00`) — ATtiny26 keyboard bridge, generates **NMI** |
| IC19 | R6551 | ACIA serial (`$C800–$CBFF`) |
| IC14 | ATtiny26 | PS/2 keyboard co-processor (PB3=CLK, PB4=DATA) |
| U$1 | MCP2221A | USB-C ↔ UART/I²C bridge |
| IC9/IC11 | 74HCT139N | Two-stage address decoder |
| IC17 | 74HC148N | 8→3 priority IRQ encoder |
| IC27 | 74HC574N | IRQ status latch (readable at `$C480`) |
| QG1 | 32 MHz | Main system oscillator |
| Q1 | 1.8432 MHz | ACIA baud-rate crystal |
| X1–X3 | ISA-8 slots | Three 8-bit ISA expansion slots |

### ISA Expansion Cards

| Card | Description |
| ---- | ----------- |
| `EXP_TMS9918A_V1` | TMS9918A video card |
| `EXP_GameDuino_V1` | GameDuino graphics card |
| **APARTS_BUS** (`aprts_vga/`) | FPGA VGA 640×480 + external SRAM + 4-ch audio (MAX 10) |

---

## Address Map

```text
$0000–$7FFF   IC6 SRAM — lower 32 KB       (!CS = A15 low)
$8000–$BFFF   IC7 SRAM — upper 32 KB       (!CS = !HRAM_CS)
$C000–$C3FF   VERA / ISA video             (!VERA_CS)
$C400–$C7FF   IRQ latch                    read $C480–$C4FF / ack $C400–$C47F
$C800–$CBFF   ACIA R6551
$CC00–$CC7F   VIA1 (IC18) — keyboard/NMI
$CC80–$CCFF   VIA2 (IC16) — parallel/IRQ1
$CD00–$CDFF   ISA DEV0
$CE00–$CEFF   ISA DEV1
$CF00–$CFFF   ISA DEV2   ← typical APARTS_BUS decode (tools use $CF00 / $CE00)
$D000–$DFFF   ISA extended
$E000–$FFFF   EEPROM ROM (8 KB)
```

### IRQ Priority Table

| Level | Signal | Source |
| ----- | ------ | ------ |
| 0 (highest) | IRQ0 | R6551 ACIA |
| 1 | IRQ1 | VIA2 (IC16, `$CC80`) |
| 2–6 | IRQ2–6 | ISA slots |
| 7 (lowest) | IRQ7 | Button S1 |
| — | **NMI** | **VIA1 (IC18, `$CC00`)** |

---

## APARTS_BUS — FPGA VGA & Audio (`aprts_vga/`)

RTL controller for the 6502/ISA bus: **VGA output**, **external SRAM framebuffer (up to 512 KB / 19-bit address)**, **internal font RAM**, and a **4-channel synthesizer** driving a **PCM5102A** over I²S.

Detailed programmer manual: [`aprts_vga/README.md`](aprts_vga/README.md).

### Target & RTL modules

| Item | Value |
| ---- | ----- |
| FPGA | Intel **MAX 10** — `10M02SCE144C8G` |
| Quartus project | `aprts_vga/10M02_test.qsf` |
| Top entity | `aprts_bus` |
| Pixel clock | **25 MHz** — VGA **640×480 @ 60 Hz** |

| File | Module | Role |
| ---- | ------ | ---- |
| `aprts_bus.v` | `aprts_bus` | Top: 4-bit port decode, CPU R/W, submodule wiring |
| `vga_timing.v` | `vga_timing` | H/V counters, HSYNC/VSYNC, `video_on` |
| `vga_video_gen.v` | `vga_video_gen` | Graphics/text RGB, font RAM (128×8 = 1024 B), cursor blink |
| `sram_controller.v` | `sram_controller` | CPU ↔ VGA arbiter, hardware clear engine |
| `aprts_audio.v` | `aprts_audio` | 4-ch DDS + ADSR, I²S (`pcm_bck` / `pcm_din` / `pcm_lrck`) |

### External interfaces (from `aprts_bus`)

```text
6502 bus:   n_reset, n_mem_w, n_mem_r, lv_cs, clk, lv_addr[3:0], lv_data[7:0]
VGA:        red[2:0], green[2:0], blue[2:0], hsync, vsync
SRAM:       sram_addr[18:0], sram_data[7:0], sram_ce_n, sram_oe_n, sram_we_n
Audio I²S:  pcm_bck, pcm_din, pcm_lrck, pcm_sck
```

### Register map (ports `$0`–`$F` relative to card base)

| Port | Write | Read |
| ---- | ----- | ---- |
| `$0` | Background color RGB332 | `reg_bg_color` |
| `$1` | Address / cursor hi (`addr_hi`) | same |
| `$2` | Address mid (`addr_mid`) | same |
| `$3` | Address lo (`addr_lo`) | same |
| `$4` | Data → SRAM / font / text cell | Data ← SRAM / font |
| `$5` | Audio register index (`0x00`–`0x17`) | current index |
| `$6` | Audio register data (index auto-inc) | selected audio reg |
| `$D` | Mode | current mode |
| `$F` | Start SRAM clear (any value) | status: bit0 = `addr_ready` |

CPU SRAM pointer is 19-bit: `{addr_hi[2:0], addr_mid, addr_lo}`. After each write to port `$4` (except font mode `$0D`) the address **auto-increments**.

**Background / pixel color:** `[7:5]` R, `[4:2]` G, `[1:0]` B (expanded to 3 bits in HW).

### Mode register (`$D`)

| Value | Behavior |
| ----- | -------- |
| `$00`–`$0C` | Graphics — linear framebuffer from external SRAM |
| `$01` | Text 80×60, static cursor |
| `$02` | Text 80×60, blinking cursor (~2 Hz) |
| `$0D` | Font edit — R/W internal `font_mem` via port `$4` |
| `$0E` | Hardware logic reset (counters, audio, registers) |
| `$0F` | Blank screen (force black) |

Text buffer uses the first **4800** bytes of SRAM (`80×60`, `$0000`–`$12BF`). Font RAM: **128 characters × 8 rows**.

### SRAM clear & status (`$F`)

- **Write:** starts hardware fill of external SRAM with zeros (clear range through `$4AFFF` in RTL).
- **Read bit 0 (`addr_ready`):** `1` = ready for CPU access; `0` = clear/write busy. Poll before further writes.

### Audio (ports `$5` / `$6`)

Four independent DDS channels mixed to I²S (PCM5102A). Sample rate in driver notes: **~48.828 kHz**.

Per channel (base offsets for ch0; +3 per channel for ch1–3):

| Index | Register |
| ----- | -------- |
| `+0` / `+1` | Frequency lo / hi |
| `+2` | Volume |
| `$0C`–`$0F` | Control: wave `[2:0]`, ADSR enable `[3]`, gate/note-on `[4]` |
| `$10`–`$17` | ADSR Attack/Decay and Sustain/Release pairs |

Waveforms: `0` square, `1` triangle, `2` saw, `3` sine, `4` trapezoid. Writing `$6` auto-increments the audio index.

### Simulation (`aprts_vga/sim/`)

| File | Purpose |
| ---- | ------- |
| `tb_aprts_bus.v` | Integration test of full `aprts_bus` |
| `tb_vga_timing.v` | VGA timing unit test |
| `tb_aprts_audio.v` | Audio registers + I²S clocks |
| `sram_model.v` | Behavioral 512 KB SRAM |
| `run_msim.bat` / `run_msim.do` | ModelSim / Questa-Intel |
| `run_iverilog.bat` | Icarus Verilog |

```bat
cd aprts_vga\sim
run_msim.bat
rem or: run_iverilog.bat
```

See [`aprts_vga/sim/README.md`](aprts_vga/sim/README.md).

### Host-side tools

| Path | Description |
| ---- | ----------- |
| `tools/aprts_vga/` | ca65 demo (`demo.asm`) — base often `$CF00` |
| `tools/audio/` | Audio includes (`audio.inc65`) and samples — ports `$5`/`$6` on card base |

Exact ISA slot base (`$CD00` / `$CE00` / `$CF00`) depends on which DEV chip-select the card is wired to.

---

## Firmware

### Prerequisites

- [cc65](https://cc65.github.io/) toolchain (`cc65`, `ca65`, `ld65`) on `PATH`

### Minimal Build

ACIA serial + EWOZ (WozMon) monitor + serial bootloader (loads to `$6000`).  
No keyboard, VDP, SPI, SD, GameDuino, or SAA1099 dependencies.

```bat
cd Firmware
build_minimal.bat
```

Output: `Firmware/output/MIN_ROM.bin` (8 KB, write to EEPROM IC5)

### AppartusOS Build

Full OS: ACIA + EWOZ (`MON` command) + Intel HEX loader + interactive shell + RAM-disk FS.

```bat
cd Firmware
build_appartus.bat
```

Output: `Firmware/output/APPARTUS_OS.bin` (8 KB, write to EEPROM IC5)

### AppartusOS Shell Commands

```text
HELP / ?                   — help
VER                        — OS version
DIR                        — list RAM-disk files
FREE                       — show free space
FORMAT                     — reinitialize RAM disk (requires Y confirmation)
LOAD                       — receive Intel HEX via ACIA
SAVE <name> <addr> <size>  — save RAM region to RAM disk (hex addresses)
DEL  <name>                — delete file
RUN  <name>                — execute file (program can RTS back to shell)
MON                        — EWOZ / WozMon monitor
RESET                      — soft reset ($FF00)
```

### RAM Disk Layout (`$6000–$BFFF`, 24 KB)

```text
$6000–$600F   Header: "APOS" + num_files + free_ptr
$6010–$610F   Directory: 16 entries × 16 bytes
              +0 name[8]  +8 load_addr  +10 size  +12 flags  +13 stor_addr
$6110–$BFFF   File data (~24 KB usable)
```

### Firmware Memory Map (ROM, `$E000–$FFFF`)

```text
ZP:      $0000–$00FF   (zero page; cc65 $00–$1F, EWOZ $24–$30, ihex $38–$3E, OS $40–$4E)
RAM:     $0200–$5FFF   (working RAM; stack at $5FFF growing down)
ROM:     $E000–$FFFF   (EEPROM, fill $FF)
JMPTBL:  $FF00         (BIOS-style jump table)
VECTORS: $FFFA         (NMI / RESET / IRQ vectors)
```

---

## Emulator — p65emu

A cycle-accurate Rust emulator with a ratatui terminal UI.

### Build Requirements

- [Rust toolchain](https://rustup.rs/) (stable)

### Build & Run

```sh
cargo run --manifest-path emulator/Cargo.toml -- [ROM.bin] [-s SPEED_HZ] [-p TCP_PORT]
```

| Flag | Default | Description |
| ---- | ------- | ----------- |
| `ROM.bin` | — | ROM image to load at `$E000` |
| `-s SPEED_HZ` | `1000000` | Emulation speed in Hz |
| `-p TCP_PORT` | `6551` | TCP serial port (0 = disabled) |
| `--family` | `HCT` | Logic family timing model (`LS`, `ALS`, `HCT`, `HC`, `AC`, `ACT`) |

### Emulated Components

| Module | Hardware |
| ------ | -------- |
| `cpu.rs` | W65C02 — fetch/decode/execute + NMI/IRQ |
| `ram.rs` | IC6 + IC7 SRAM |
| `rom.rs` | 8 KB EEPROM |
| `acia.rs` | R6551 — TX/RX queues shared with TUI and TCP |
| `via.rs` | VIA1 (`$CC00`) + VIA2 (`$CC80`) — T1/T2 timers |
| `irq_latch.rs` | 74HC574 latch + 74HC148 encoder |
| `tms9918a.rs` | TMS9918A video (minifb window) |
| `saa1099.rs` | SAA1099 audio (rodio) |

### TUI Keyboard Shortcuts

| Key | Action |
| --- | ------ |
| F2 | Single step |
| F3 | Run / Pause |
| F4 | Reset CPU |
| F5–F9 | Speed: 1K / 10K / 100K / 1M / MAX Hz |
| +/- | Speed ×2 / ÷2 |
| Tab | Memory view: ZP / RAM / HiRAM / I/O / ROM / Addr |
| Shift+Tab | Right panel: CPU / VIA1 / VIA2 / ACIA / IRQ |
| PgUp/PgDn | Scroll memory |
| Shift+Pg | Scroll terminal |
| Ctrl+O | File browser — load ROM or RAM image |
| Ctrl+G | Jump to hex address in memory dump |
| Ctrl+M | Edit byte at address |
| Ctrl+R | Edit CPU registers (A/X/Y/SP/PC/P) |
| F10 / Ctrl+Q | Quit |

The TCP serial port (default `127.0.0.1:6551`) allows PuTTY, netcat, or `uploader.py` to connect as if it were real hardware.

---

## Tools

### tools/uploader.py

Python/tkinter GUI for uploading firmware to the real board or the emulator.

**Dependencies:**

```sh
pip install pyserial
```

**Connection modes:**

- **COM port** — real hardware (19200 Bd, 8N1)
- **TCP** — emulator (`127.0.0.1:6551`)

**Bootloader protocol:**

| Command | Action |
| ------- | ------ |
| `w` | Raw binary upload — exactly 8192 bytes → `$6000–$7FFF` |
| `h` | Intel HEX upload (any address) |
| `s` | Jump to `$6000` (run program) |
| `m` | Enter EWOZ / WozMon monitor |
| `^R` (`$12`) | Soft-restart bootloader |

### Other tools

| Path | Description |
| ---- | ----------- |
| `tools/aprts_vga/` | APARTS_BUS VGA demo for AppartusOS |
| `tools/audio/` | 4-channel FPGA audio driver and samples |
| `tools/hello/` | Sample user program |
| `tools/ihex_gen.py` | Intel HEX helper |
| `tools/espi_update_fpga.py` | FPGA update helper |
| `tools/vera_test/`, `tools/vga_test/` | Video experiments |

---

## Typical Workflow

```sh
# 1. Build firmware
cd Firmware && build_appartus.bat

# 2. Start emulator
cargo run --manifest-path emulator/Cargo.toml -- Firmware/output/APPARTUS_OS.bin

# 3. In emulator terminal — send a program via Intel HEX
> LOAD
  (paste or send .hex file via uploader.py over TCP)

# 4. Save and run
> SAVE HELLO 6090 0100
> DIR
> RUN HELLO
```

FPGA RTL / sim workflow:

```bat
cd aprts_vga\sim
run_msim.bat
```

---

## Known Issues

| # | Status | Description |
| - | ------ | ----------- |
| 1 | ✅ Fixed | `_nmi_init` in `utils.asm` — NMI Timer1 initialization correctly configures VIA1 (IC18) at $CC00 |
| 2 | ✅ Fixed | NMI ISR correctly reloads VIA1 (IC18) T1 counter — verified in `interrupts.asm:19` |
| 3 | ✅ Fixed | PS/2 keyboard driver in `pckybd.asm:25–28` — now correctly reads from VIA1 (IC18, ATtiny26) |
| 4 | ✅ Fixed | `VDP_MODE0 = $C000` — correctly placed in ISA I/O space, no longer conflicts with IC6 RAM |

All critical hardware bugs have been resolved.

---

## Hardware Files

| File | Description |
| ---- | ----------- |
| `Eagle/SBC_65C02_IRQ_BigBoard_v10-2-1.csv` | Current BOM / netlist |
| `Eagle/SBC_65C02_IRQ_BigBoard_v9-1-3.sch` | Main schematic (Eagle) |
| `Eagle/SBC_65C02_IRQ_BigBoard_v9-1-3.brd` | Main PCB layout (Eagle) |
| `Eagle/EXP_TMS9918A_V1.sch/.brd` | TMS9918A ISA video card |
| `Eagle/EXP_GameDuino_V1.sch/.brd` | GameDuino ISA graphics card |
| `aprts_vga/*.v` | APARTS_BUS FPGA RTL (VGA + SRAM + audio) |
| `aprts_vga/10M02_test.qsf` | Quartus pinout / project for MAX 10 |

Full hardware documentation (address decoding logic, IC cross-reference, IRQ system) is in [`CLAUDE.md`](CLAUDE.md).  
FPGA register-level docs: [`aprts_vga/README.md`](aprts_vga/README.md).

---

## License

See [`Firmware/LICENSE`](Firmware/LICENSE).
