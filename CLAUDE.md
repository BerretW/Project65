# Project65 — SBC 65C02 IRQ BigBoard

Tento soubor obsahuje kompletní přehled hardwaru desky, adresní mapu a seznam bugů.
Netlist a BOM **není potřeba znovu zpracovávat** — vše relevantní je zde.

---

## Hardware — přehled součástek

| Reference | Hodnota / Part | Popis |
|-----------|---------------|-------|
| IC4 | W65C02SP | Hlavní CPU (65C02, DIL40) |
| IC5 | 28C64AP (AT28C64B) | EEPROM 8 KB — ROM |
| IC6 | 62256 | SRAM 32 KB — spodní RAM ($0000–$7FFF), !CS = A15 |
| IC7 | 62256 | SRAM 32 KB — horní RAM ($8000–$BFFF), !CS = !HRAM_CS |
| IC8 | DS1233 (SOT223) | Power-on reset |
| IC16 | W65C22S6TP | VIA #1 dle schématu → v FW **VIA2_BASE = $CC80** |
| IC18 | W65C22S6TP | VIA #2 dle schématu → v FW **VIA1_BASE = $CC00**, generuje **NMI** |
| IC19 | R6551 | Rockwell ACIA, sériová linka |
| IC14 | ATtiny26-16PU | AVR — PS/2 klávesnice (PB3=CLK, PB4=DATA z X4) |
| U$1 | MCP2221A-I/P | USB-C ↔ UART/I2C bridge (J4) |
| IC1 | REG1117 3V3 | LDO regulátor 3,3 V pro USB sekci |
| IC9 | 74HCT139N | Dekodér 2. úrovně — IO prostor |
| IC11 | 74HCT139N | Dekodér 1. úrovně — horní adresní prostor |
| IC10 | 74AC00N | NAND — generuje !MEMR, !MEMW, !A7 |
| IC12 | 74AC00N | NAND — generuje !ROM_CS (E-F range) |
| IC21 | 74AC32N | OR — generuje !AA_CS, !AA_CS_WR, !IRQ_CS |
| IC2, IC3 | 74HC74N | D flip-flopy — dělička hodin (32→16→8→4→2 MHz) |
| IC17 | 74HC148N | Priority encoder (8→3) — IRQ logika |
| IC27 | 74HC574N | 8-bit latch — IRQ stavový registr pro CPU |
| Q1 | 1,8432 MHz | Krystal pro ACIA (přesné baudové rychlosti) |
| QG1 | 32 MHz | Hlavní systémový oscilátor |
| X1–X3 | ISA-SLOT (ISA-8) | Tři ISA-8 sloty |
| J3 | DB9 Male | Sériový port RS-232 |
| J4 | USB-C 16P | USB-C konektor |
| X4 | Mini DIN 6 | PS/2 konektor (klávesnice) |

### ISA expanzní karty (v Eagle/)
- `EXP_TMS9918A_V1` — TMS9918A video karta
- `EXP_GameDuino_V1` — GameDuino grafická karta

---

## Adresní mapa (rekonstruováno z netlisu v10-2-1)

```
$0000–$7FFF   IC6 RAM (32 KB)    !CS = A15 přímo; aktivní kdykoli A15=0
$8000–$BFFF   IC7 RAM (32 KB)    !CS = !HRAM_CS  (A15=1, A14=0)
$C000–$C3FF   VERA / ISA video   !VERA_CS  (IC9 Y0: A11=0, A10=0 v IO prostoru)
$C400–$C7FF   IRQ latch          !$C4-7    (IC9 Y1: A11=0, A10=1)
                                   čtení IC27 na $C480–$C4FF (A7=1)
                                   zápis/ACK na $C400–$C47F  (A7=0)
$C800–$CBFF   ACIA R6551         !ACIA_CS  (IC9 Y2: A11=1, A10=0)
$CC00–$CC7F   VIA1 FW (IC18)     !VIA_CS + A7=0  ← ATtiny26, NMI zdroj
$CC80–$CCFF   VIA2 FW (IC16)     !VIA_CS + A7=1  ← JP8 parallel port, IRQ1 zdroj
$CD00–$CDFF   ISA DEV0           !DEV0_CS (IC9 sec2 Y1: A9=0, A8=1)
$CE00–$CEFF   ISA DEV1           !DEV1_CS (IC9 sec2 Y2: A9=1, A8=0)
$CF00–$CFFF   ISA DEV2           !DEV2_CS (IC9 sec2 Y3: A9=1, A8=1)
$D000–$DFFF   ISA extended       !$DXXX_CS (IC11 sec2 Y1: A13=0, A12=1)
$E000–$FFFF   EEPROM ROM (8 KB)  !ROM_CS  (IC12 NAND: E-F range, A13=1 v C-F)
```

### Dekódovací logika (stručně)

```
IC11 sekce 1 (A=A14, B=A15, G=GND — vždy povoleno):
  Y2 → !HRAM_CS  ($8000–$BFFF)
  Y3 → !C-F      ($C000–$FFFF, povoluje IC11 sekci 2)

IC11 sekce 2 (A=A12, B=A13, G=!C-F):
  Y0 → !IO_CS    ($C000–$CFFF, povoluje IC9)
  Y1 → !$DXXX_CS ($D000–$DFFF)

IC9 sekce 1 (A=A10, B=A11, G=!IO_CS):
  Y0 → !VERA_CS  ($C000–$C3FF)
  Y1 → !$C4-7    ($C400–$C7FF)
  Y2 → !ACIA_CS  ($C800–$CBFF)
  Y3 → !OTHER_CS ($CC00–$CFFF, povoluje IC9 sekci 2)

IC9 sekce 2 (A=A8, B=A9, G=!OTHER_CS):
  Y0 → !VIA_CS   ($CC00–$CCFF, dále děleno A7)
  Y1 → !DEV0_CS  ($CD00–$CDFF)
  Y2 → !DEV1_CS  ($CE00–$CEFF)
  Y3 → !DEV2_CS  ($CF00–$CFFF)

VIA výběr uvnitř $CC00–$CCFF:
  IC18 CS1 = !A7  → aktivní $CC00–$CC7F  (FW: VIA1_BASE = $CC00)
  IC16 CS1 =  A7  → aktivní $CC80–$CCFF  (FW: VIA2_BASE = $CC80)
```

---

## IO adresy (z io.inc65)

```
ACIA_BASE    = $C800   ← správně
VIA1_BASE    = $CC00   ← fyzicky IC18 (schéma říká VIA2!) — NMI zdroj, ATtiny
VIA2_BASE    = $CC80   ← fyzicky IC16 (schéma říká VIA1!) — JP8 parallel port
VDP_MODE0    = $7F10   ← POZOR: leží v IC6 RAM prostoru, viz bug #4
```

### POZOR — záměna názvů VIA

Schéma označuje IC16 jako „VIA1" a IC18 jako „VIA2", ale firmware má VIA1/VIA2 prohozeny:

| FW symbol | Adresa | Fyzický čip | Schéma | Připojení |
|-----------|--------|-------------|--------|-----------|
| VIA1 | $CC00 | IC18 | „VIA2" | ATtiny26 (klávesnice), generuje **NMI** |
| VIA2 | $CC80 | IC16 | „VIA1" | JP8 parallel port, generuje **IRQ1** |

---

## IRQ systém

| Signál | Zdroj | Priorita (IC17) |
|--------|-------|-----------------|
| IRQ0 | IC19 R6551 ACIA | 0 (nejvyšší) |
| IRQ1 | IC16 !IRQB (FW VIA2, $CC80) | 1 |
| IRQ2–6 | ISA sloty | 2–6 |
| IRQ7 | S1 (tlačítko) | 7 (nejnižší) |
| **NMI** | **IC18 !IRQB (FW VIA1, $CC00)** | — (nemaskable) |

IC17 (74HC148) kóduje aktivní IRQ do 3 bitů → IC27 (latch) → čitelné CPU na $C480–$C4FF.

---

## Hodiny

IC2+IC3 (74HC74 děličky) z QG1 32 MHz generují: 16 / 8 / 4 / 2 MHz.
Volba CPU taktu přes jumper JP2–JP5.
Q1 1,8432 MHz — přiveden přímo do ACIA (přesné baudové rychlosti).

---

## Firmware — minimal build

**Soubory:** `build_minimal.bat` → `config/MIN_ROM.cfg` → `output/MIN_ROM.bin`

**Paměťová mapa linkeru (MIN_ROM.cfg):**
```
ZP:  $0000–$00FF   (zero page)
RAM: $0200–$5FFF   (pracovní RAM, stack na $5FFF roste dolů)
ROM: $E000–$FFFF   (EEPROM, fill $FF)
JMPTBL: $FF00      (jump tabulka)
VECTORS: $FFFA     (NMI/RESET/IRQ vektory)
```

**Obsah minimal buildu:** ACIA serial + WozMon (EWOZ) + sériový bootloader do $6000.  
Klávesnice, VDP, SPI, SD, GameDuino, SAA1099 — **v minimal buildu nejsou**.

---

## TODO — oprava bugů

### Bug #1 — `_nmi_init` konfiguruje špatné VIA
**Soubor:** `Firmware/src/utils.asm` řádky 72–78

```asm
; ŠPATNĚ (aktuální stav):
_nmi_init:  STA VIA2_T1C_H   ; IC16 — ten NMI NEgeneruje!
            STA VIA2_ACR
            STA VIA2_IER

; SPRÁVNĚ (opravit na):
_nmi_init:  STA VIA1_T1C_H   ; IC18 — ten generuje NMI (!IRQB → CPU NMIB)
            STA VIA1_ACR
            STA VIA1_IER
```

**Dopad:** NMI timer nikdy nevznikne. V minimal buildu nevadí (NMI_Event je prázdné),
ale v plném firmware s klávesnicí pollingem přes NMI je to kritická chyba.

---

### Bug #2 — NMI ISR reloaduje špatné VIA
**Soubor:** `Firmware/src/interrupts.asm` řádek 19

```asm
; ŠPATNĚ:
STA VIA2_T1C_H

; SPRÁVNĚ:
STA VIA1_T1C_H
```

**Dopad:** I kdybychom opravili Bug #1, ISR by reloadoval timer na IC16 místo IC18.

---

### Bug #3 — klávesnicový driver čte ze špatného VIA
**Soubor:** `Firmware/src/pckybd.asm` řádky 25–28

```asm
; ŠPATNĚ (aktuální):
kb_data_or  = VIA2_ORA   ; $CC81 = IC16, nemá ATtiny!
kb_data_ddr = VIA2_DDRA
kb_stat_or  = VIA2_ORB
kb_stat_ddr = VIA2_DDRB

; SPRÁVNĚ (opravit na):
kb_data_or  = VIA1_ORA   ; $CC01 = IC18, tam je ATtiny26
kb_data_ddr = VIA1_DDRA
kb_stat_or  = VIA1_ORB
kb_stat_ddr = VIA1_DDRB
```

**Dopad:** Klávesnice nefunguje — driver mluví s IC16 (parallel port JP8), ne s IC18 (ATtiny26).  
**Priorita:** Neopravovat dokud není Bug #1+#2 opraveno. Netýká se minimal buildu.

---

### Bug #4 — VDP adresa konfliktuje s RAM
**Soubor:** `Firmware/src/io.inc65` řádek 154

```asm
VDP_MODE0 = $7F10   ; A15=0 → IC6 RAM range!
```

$7F10 leží v IC6 RAM oblasti ($0000–$7FFF). IC6 !CS = A15 přímo, tedy IC6 reaguje
na $7F10 vždy. TMS9918A na ISA kartě by soutěžil s IC6 na datové sběrnici.

**Co ověřit:** Prohlédnout schéma `Eagle/EXP_TMS9918A_V1.sch` — zjistit jak karta
dekóduje svou CS adresu. Pokud karta neodpojuje IC6 při přístupu, je nutné
VDP přesunout do IO prostoru ($C000–$CFFF) nebo použít !VERA_CS ($C000–$C3FF).  
**Priorita:** Neřešit dokud není hardware ověřen fyzicky.

---

## Soubory schématu

```
Eagle/SBC_65C02_IRQ_BigBoard_v9-1-3.sch/.brd  — starší verze
Eagle/SBC_65C02_IRQ_BigBoard_v10-2-1.csv      — BOM verze 10
Eagle/9-1-3 netlist                            — netlist verze 9 (txt)
Eagle/EXP_GameDuino_V1.sch/.brd
Eagle/EXP_TMS9918A_V1.sch/.brd
```

Netlist pro v10-2-1 byl exportován 13.04.2026 z Eagle 9.6.2.
