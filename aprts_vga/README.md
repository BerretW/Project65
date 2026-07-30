

# APARTS_BUS – VGA & SRAM & Audio Controller for 6502

`APARTS_BUS` je pokročilý hardwarový řadič určený pro 8bitové počítače se sběrnicí MOS 6502. Kombinuje v sobě **VGA grafický výstup**, správu **externí SRAM (až 512 KB / 19-bit adresa)**, uživatelsky definovatelný **textový/znakový generátor (font RAM)** a **4kanálový zvukový syntetizátor** kompatibilní s převodníkem PCM5102A (I2S).

---

## 📋 Obsah

1. [Mapa registrů (Port Mapping)](#1-mapa-registrů-port-mapping)
2. [Detailní popis funkcí registrů](#2-detailní-popis-funkcí-registrů)
   - [Pozadí a barvy (Port `0x0`)](#barva-pozadí-port-0x0)
   - [Kurzor a adresa SRAM (Porty `0x1`, `0x2`, `0x3`)](#kurzor--adresa-sram-porty-0x1-0x2-0x3)
   - [Datová brána (Port `0x4`)](#datová-brána-port-0x4)
   - [Správa zvuku (Porty `0x5` a `0x6`)](#správa-zvuku-porty-0x5-a-0x6)
   - [Režimový registr (Port `0xD`)](#režimový-registr-port-0xd)
   - [Status a mazání paměti (Port `0xF`)](#status-a-mazání-paměti-port-0xf)
3. [Grafické a textové režimy](#3-grafické-a-textové-režimy)
4. [Programátorské příklady](#4-programátorské-příklady)
   - [Příklad 1: Inicializace a výpis textu (Commodore BASIC / BASIC V2)](#příklad-1-inicializace-a-výpis-textu-v-basicu)
   - [Příklad 2: Kreslení a zvuk v Assembleru (`ca65`)](#příklad-2-kreslení-a-zvuk-v-assembleru-ca65)

---

## 1. Mapa registrů (Port Mapping)

Řadič je na 6502 sběrnici mapován pomocí 4bitové adresy portu (`lv_addr` 0 až 15, tedy `4'h0` až `4'hF`).

|    Port (Hex)    | Název v HDL             | Funkce při ZÁPISU (`W`)                            | Funkce při ČTENÍ (`R`)                     |
| :--------------: | :----------------------- | :----------------------------------------------------- | :---------------------------------------------- |
| **`$0`** | `reg_bg_color`         | Nastavení barvy pozadí obrazovky                     | Vrací aktuální barvu pozadí                 |
| **`$1`** | `addr_hi`              | Vyšší bity adresy / kurzoru (SRAM[18:16] nebo Font) | Vrací`addr_hi`                               |
| **`$2`** | `addr_mid`             | Prostřední bity adresy / kurzoru (SRAM[15:8])        | Vrací`addr_mid`                              |
| **`$3`** | `addr_lo`              | Nejnižší bity adresy / kurzoru (SRAM[7:0])          | Vrací`addr_lo`                               |
| **`$4`** | `write_val` / `font` | Zápis data do SRAM / zápis definice fontu            | Čtení data ze SRAM / čtení z font RAM       |
| **`$5`** | `aud_addr`             | Výběr indexu zvukového registru (0x00–0x17)        | Vrací aktuální index`aud_addr`             |
| **`$6`** | Zvuková data            | Zápis hodnoty do vybraného zvukového registru       | Čtení hodnoty ze zvukového registru          |
| **`$D`** | `mode`                 | Nastavení provozního režimu (Grafika/Text/Reset)    | Vrací aktuální`mode`                       |
| **`$F`** | Ovládání SRAM         | Spuštění hromadného mazání SRAM (`clear`)      | Status: Bit 0 =`addr_ready` (1 = připraveno) |

---

## 2. Detailní popis funkcí registrů

### 🎨 Barva pozadí (Port `0x0`)

Určuje globální barvu pozadí pro grafické i textové režimy.

* **Formát RGB (8 bitů):** `[7:5]` = Červená (3 bity), `[4:2]` = Zelená (3 bity), `[1:0]` = Modrá (2 bity – v hardware se rozšiřují na 3 bity).

### 📍 Kurzor & Adresa SRAM (Porty `0x1`, `0x2`, `0x3`)

Slouží jako 24bitový ukazatel (reálně využívajících 19 bitů pro SRAM o velikosti 512 KB, nebo bity pro adresaci fontu v režimu `0x0D`).

* **Automatický inkrement:** Po každém zápisu dat na port **`0x4`** se tato 19bitová adresa **automaticky inkrementuje o +1**. Odpadá nutnost neustále ručně nastavovat adresu pro sekvenční zápisy.

### 💾 Datová brána (Port `0x4`)

* **V grafických režimich (`0x00`–`0x0C`):** Zápis zapisuje přímo pixel do externí SRAM na aktuální adresu (`cpu_addr_full`). Hodnota `0x00` vykreslí barvu pozadí, jiné hodnoty definují barvu pixelu (stejný formát RGB jako barva pozadí).
* **V textových režimech (`0x01` / `0x02`):** Zápis ASCII kódu znaku na aktuální pozici kurzoru v SRAM. Adresa se sama posune na další pozici.
* **V režimu editace fontu (`0x0D`):** Zápis/čtení bajtů definice fontu do interní paměti `font_mem` (128 znaků × 8 řádků = 1024 bajtů).

### 🎵 Správa zvuku (Porty `0x5` a `0x6`)

Hardwarový syntetizátor disponuje 4 nezávislými kanály s podporou DDS generování vln, obálky **ADSR** a mixování do I2S (převodník PCM5102A).

1. Na port **`0x5`** zapíšete index registru (0x00 až 0x17). *Poznámka: Index se po každém zápisu na port `0x6` automaticky inkrementuje, což extrémně zrychluje konfiguraci.*
2. Na port **`0x6`** zapíšete hodnotu registru.

**Struktura zvukových registrů (kanály 0 až 3):**

* `+0x00` až `+0x02` (Kanál 0): Frekvence Lo (`0x00`), Frekvence Hi (`0x01`), Hlasitost (`0x02`)
* `+0x03` až `+0x05` (Kanál 1): ...tamtéž pro kanál 1...
* `+0x06` až `+0x08` (Kanál 2): ...tamtéž pro kanál 2...
* `+0x09` až `+0x0B` (Kanál 3): ...tamtéž pro kanál 3...
* `+0x0C` až `+0x0F`: **Řídicí registry (`reg_ctrl_0` až `3`)**
  * `Bit [2:0]`: Typ vlnové délky (`0` = Obdélník, `1` = Trojúhelník, `2` = Pila, `3` = Sinus, `4` = Trapéz)
  * `Bit [3]`: Povolení ADSR obálky (`1` = zapnuto, `0` = vypnuto, hraje čistá hlasitost)
  * `Bit [4]`: **Gate** (Spouštění tónu: `1` = Note On / útok a držení, `0` = Note Off / uvolnění)
* `+0x10` až `+0x17`: ADSR parametry (`Attack/Decay` a `Sustain/Release` pro jednotlivé kanály).

### ⚙️ Režimový registr (Port `0xD`)

Určuje chování celého řadiče:

* **`0x00` až `0x0C`**: Grafické režimy (přímé mapování pixelů ze SRAM na VGA 640x480).
* **`0x01`**: Textový režim 80×60 (statický kurzor).
* **`0x02`**: Textový režim 80×60 s blikajícím kurzorem (~2 Hz).
* **`0x0D`**: Režim editace fontu (přístup k interní `font_mem` přes port `0x4`).
* **`0x0E`**: **Hardwarový reset** FPGA logiky (vyresetuje vnitřní čítače, vymaže audio a nastaví registry do počátečního stavu).
* **`0x0F`**: Vypnutí obrazu (Blank screen – obrazovka zcela zčerná).

### 🧹 Status a mazání paměti (Port `0xF`)

* **Zápis (jakákoliv hodnota):** Spustí bleskové hardwarové vymazání celé externí SRAM (vyplní 512 KB nulami).
* **Čtení:** Vrací stavový bajt `[0]` (`addr_ready`).
  * `1` = Řadič je připraven k přijímání příkazů a zápisům.
  * `0` = Probíhá mazání SRAM (`clear_busy`) nebo zápis. **Před každým dalším zápisem je nutné testovat, zda je `addr_ready == 1`!**

---

## 3. Grafické a textové režimy

* **VGA Rozlišení:** 640 × 480 pixelů (časování 25 MHz pixel clock).
* **Textový režim:** 80 sloupců × 60 řádků (při velikosti fontu 8×8 pixelů). Paměť textového bufferu zabírá v SRAM prvních 4800 bajtů (`0x0000` až `0x12BF`).

---

## 4. Programátorské příklady

Následující ukázky demonstrují ovládání řadiče z 6502 v jazyce **BASIC** a v **assembleru (`ca65`)**.

---

### Příklad 1: Inicializace a výpis textu v BASICu

Předpokládejme, že řídicí porty řadiče jsou namapované na adrese `lví I/O` prostoru např. od `$DE00` do `$DE0F`.

```basic
10 REM Definice adres portu APARTS_BUS (např. base = $DE00)
20 BASE = 56832 
30 REG_BG   = BASE + 0
40 REG_AHI  = BASE + 1
50 REG_AMID = BASE + 2
60 REG_ALO  = BASE + 3
70 REG_DATA = BASE + 4
80 REG_MODE = BASE + 13
90 REG_STAT = BASE + 15

100 REM 1. Test pripravenosti a vymazani SRAM
110 IF (PEEK(REG_STAT) AND 1) = 0 THEN GOTO 110
120 POKE REG_STAT, 1 : REM Spusti mazani SRAM

130 REM 2. Nastaveni barvy pozadi (modra: R=0, G=0, B=3)
140 POKE REG_BG, 3

150 REM 3. Nastaveni kurzoru na zacatek SRAM (adresa 0)
160 POKE REG_AHI, 0
170 POKE REG_AMID, 0
180 POKE REG_ALO, 0

190 REM 4. Prepnuti do textoveho rezimu s blikajicim kurzorem (0x02)
200 POKE REG_MODE, 2

210 REM 5. Vypsani retezce "AHOJ SVETE!"
220 READ A$: IF A$ = "END" THEN GOTO 300
230 FOR I = 1 TO LEN(A$)
240   C = ASC(MID(A$, I, 1))
255   IF (PEEK(REG_STAT) AND 1) = 0 THEN GOTO 255 :REM Čekání na připravenost
260   POKE REG_DATA, C :REM Zápis znaku (adresa se sama posune +1)
270 NEXT I
280 DATA "APARTS_BUS 6502 CONTROLLER READY.", "AHOJ SVETE!", "END"
```

---

### Příklad 2: Kreslení a zvuk v Assembleru (`ca65`)

Tento kód v assembleru nastaví grafický režim `0x00`, nakreslí na obrazovku pixel a spustí jednoduchý tón (Sawtooth wave) na zvukovém kanálu 0 s aktivní ADSR obálkou.

```assembly
; Definice adres I/O portů APARTS_BUS
APARTS_BASE  = $DE00
REG_BG       = APARTS_BASE + 0
REG_AHI      = AParts_BASE + 1
REG_AMID     = APARTS_BASE + 2
REG_ALO      = APARTS_BASE + 3
REG_DATA     = APARTS_BASE + 4
REG_AUD_ADDR = APARTS_BASE + 5
REG_AUD_DATA = APARTS_BASE + 6
REG_MODE     = APARTS_BASE + 13
REG_STAT     = APARTS_BASE + 15

.segment "CODE"
.proc init_system
    ; 1. Počkat na připravenost řadiče
@wait_ready:
    lda REG_STAT
    and #$01
    beq @wait_ready

    ; 2. Vymazat SRAM
    sta REG_STAT

    ; 3. Nastavit černé pozadí
    lda #$00
    sta REG_BG

    ; 4. Přepnout do grafického režimu 0x00
    lda #$00
    sta REG_MODE

    ; 5. Nastavit adresu SRAM na např. 0x000150 (střed obrazovky)
    lda #0
    sta REG_AHI
    lda #$15
    sta REG_AMID
    lda #$50
    sta REG_ALO

    ; 6. Zapsat barvu pixelu (např. jasně červená/zelená -> 0xE0)
@wait_ready2:
    lda REG_STAT
    and #$01
    beq @wait_ready2

    lda #%11111000        ; RGB: R=7, G=7, B=0
    sta REG_DATA          ; Adresa se sama inkrementuje!

    ; --- KONFIGURACE ZVUKU (Kanál 0) ---
    ; Vybereme index registru 0x00 (Frekvence Lo)
    lda #$00
    sta REG_AUD_ADDR

    ; Frekvence Lo (např. $80)
    lda #$80
    sta REG_AUD_DATA      ; automaticky inkrementuje aud_addr na 0x01

    ; Frekvence Hi (např. $02 -> dohromady tvoří pitch)
    lda #$02
    sta REG_AUD_DATA      ; inkrement na 0x02

    ; Hlasitost kanálu (max = 0xFF)
    lda #%11111111
    sta REG_AUD_DATA      ; inkrement na 0x03 (kanál 1 freq_lo) -> posuneme raději ručně na řídicí reg kanálu 0

    ; Nastavíme řídicí registr kanálu 0 (index 0x0C)
    lda #$0C
    sta REG_AUD_ADDR
  
    ; Bits [2:0] = 2 (Sawtooth/Pila), Bit [3] = 1 (ADSR zapnuto), Bit [4] = 1 (Gate ON / Spustit tón)
    lda #%00011010      
    sta REG_AUD_DATA

    rts
.endproc
```
