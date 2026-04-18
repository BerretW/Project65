# Project65 — SBC 65C02 IRQ BigBoard

A fully custom **W65C02-based single-board computer** featuring an 8-priority-level IRQ subsystem, three ISA-8 expansion slots, a PS/2 keyboard interface, RS-232 serial port, and a complete firmware stack — including an interactive OS with a RAM-disk filesystem. Accompanied by a **full-featured Rust emulator** with a terminal UI.

---

## Features

- **CPU:** W65C02S @ up to 8 MHz (jumper-selectable from 32 MHz main oscillator)
- **Memory:** 64 KB total — 32 KB lower RAM + 32 KB upper RAM + 8 KB EEPROM ROM
- **Serial:** R6551 ACIA with a 1.8432 MHz crystal for accurate baud rates
- **Parallel I/O:** 2× W65C22S VIA controllers (keyboard polling + parallel port)
- **PS/2 Keyboard:** ATtiny26 co-processor bridge
- **Interrupt system:** 74HC148 priority encoder + 74HC574 latch — 8 prioritized IRQ lines + NMI
- **Expansion:** 3× ISA-8 slots (TMS9918A video card, GameDuino graphics card)
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
├── tools/
│   └── uploader.py     # Python/tkinter firmware uploader (COM or TCP)
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
$CD00–$CFFF   ISA DEV0 / DEV1 / DEV2
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

Full hardware documentation (address decoding logic, IC cross-reference, IRQ system) is in [`CLAUDE.md`](CLAUDE.md).

---

## License

See [`Firmware/LICENSE`](Firmware/LICENSE).
