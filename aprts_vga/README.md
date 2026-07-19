# aprts_vga

`aprts_vga` je jednoduchý VGA řadič pro SBC Project65. Modul běží v FPGA Intel MAX 10, generuje VGA obraz 640x480 @ 60 Hz, používá externí SRAM jako video RAM a poskytuje 6502 CPU rozhraní ve stylu VERA: adresní latch, datový registr, řídicí registr a auto-increment po přístupu do VRAM.

Tento dokument popisuje hlavně kontrakt pro firmware/programátora: jak modul připojit do adresního prostoru 6502, jak zapisovat do VRAM, jak nastavit textový/bitmapový režim, jak plnit paletu a jak číst diagnostiku.

## Rychlý přehled

- Výstup: VGA 640x480 @ 60 Hz, 25 MHz pixel clock.
- Barvy: interní 256položková paleta, 12 bitů na barvu, na VGA DAC jde 9 bitů.
- Textový režim: 80x60 znaků, znak 8x8 bodů, každý znak má 1 bajt kódu a 1 bajt atributu.
- Bitmapový režim: 320x240 logických pixelů, každý pixel je 8bitový index do palety, obraz je 2x zvětšen na 640x480.
- VRAM: externí SRAM adresovaná 19 bity.
- Palette RAM: interní FPGA RAM na adresách `0x1F000-0x1F1FF`.
- CPU rozhraní: 16 registrů přes `lv_addr[3:0]`, typicky mapovaných jako `$C000-$C00F` v I/O prostoru SBC.
- Po resetu je aktivní splash/BIST obrazec, první zápis do datového registru VRAM jej vypne.

## Soubory

- [aprts_vga.v](aprts_vga.v) - vlastní Verilog modul.
- [aprts_vga.qsf](aprts_vga.qsf) - Quartus nastavení, piny a cílový čip `10M02SCE144C8G`.
- [aprts_vga.qpf](aprts_vga.qpf) - Quartus project file.

## Top-level porty

```verilog
module aprts_vga (
    input  wire        clk_25mhz,
    input  wire        phi2,

    output reg  [2:0]  red,
    output reg  [2:0]  green,
    output reg  [2:0]  blue,
    output reg         hsync,
    output reg         vsync,

    output reg  [18:0] sram_addr,
    inout  wire [7:0]  sram_data,
    output reg         sram_ce_n,
    output reg         sram_oe_n,
    output reg         sram_we_n,

    input  wire        lv_cs,
    input  wire        lv_mem_r,
    input  wire        cpu_rw,
    input  wire [3:0]  lv_addr,
    inout  wire [7:0]  lv_data
);
```

### Hodiny

`clk_25mhz` je pixel clock a zároveň hlavní clock doména modulu. Všechny interní stavové automaty, VGA časování, arbitráž SRAM a synchronizace CPU write toggle běží proti této hraně.

`phi2` je hodinový signál 6502. Modul zapisovací cyklus zachytává takto:

1. Na náběžné hraně `phi2` uloží, zda je vybraný zápis (`lv_cs == 0 && cpu_rw == 0`) a jaký je `lv_addr`.
2. Na sestupné hraně `phi2` vzorkuje `lv_data`.
3. Do 25MHz domény předá zápis pomocí toggle synchronizace a vytvoří jednopulsní `reg_write_pulse`.

Čtecí cyklus se povoluje v době, kdy je synchronizované `phi2` vysoké, `lv_cs == 0` a `cpu_rw == 1`. FPGA pak aktivně řídí `lv_data` jen během čtení.

`lv_mem_r` je v aktuální implementaci pouze vstup top-level entity, ale uvnitř modulu se nepoužívá. Směr cyklu řídí `cpu_rw`.

## CPU adresní mapa registrů

Pokud je `lv_addr[3:0]` připojeno na CPU adresy `A0-A3` a `lv_cs` dekóduje začátek bloku, CPU vidí tento register map:

| Offset | Přístup | Název | Popis |
|---:|:---:|---|---|
| `+0` | W | `ADDR_L` | Dolní bajt VRAM adresy. |
| `+1` | W | `ADDR_M` | Prostřední bajt VRAM adresy. |
| `+2` | W | `ADDR_H` | Horní bajt adresy a krok auto-incrementu. Bity `[2:0]` jsou adresa `[18:16]`, bity `[7:4]` vybírají krok. |
| `+3` | R/W | `DATA` | Čtení/zápis bajtu z/do VRAM nebo Palette RAM na aktuální adrese. Po dokončení se adresa zvýší o vybraný krok. První zápis sem vypne splash/BIST obrazec. |
| `+4` | R/W | `CTRL` | Řídicí registr videa. |
| `+5` | R/W | `DEBUG_CTRL` / `STATUS` | Zápis nastavuje debug overlay a SRAM clear. Čtení vrací status. |
| `+6` | R | `DIAG_FAIL_ADDR_L` | Dolní bajt adresy první chyby SRAM diagnostiky. |
| `+7` | R | `DIAG_FAIL_ADDR_M` | Prostřední bajt adresy první chyby SRAM diagnostiky. |
| `+8` | R | `DIAG_FAIL_ADDR_H` | Bity `[2:0]` jsou horní adresa chyby `[18:16]`. |
| `+9` | R | `DIAG_EXPECTED` | Očekávaná hodnota při chybě SRAM diagnostiky. |
| `+10` | R | `DIAG_ACTUAL` | Skutečně přečtená hodnota při chybě SRAM diagnostiky. |
| `+11` | R | `DIAG_STATE` | Dolní 4 bity obsahují aktuální stav diagnostického automatu. |
| `+12` | R | `DEBUG_LAST_WRITE_ADDR` | Poslední zapsaný register offset. |
| `+13` | R | `DEBUG_LAST_WRITE_DATA` | Poslední zapsaná hodnota. |
| `+14` | R | `DEBUG_WRITE_COUNT` | 8bitové počítadlo CPU zápisů do registrů. |
| `+15` | - | Rezervováno | Čtení vrací high-Z; nepoužívat. |

Při mapování na Project65 je přirozený blok `VERA_CS` prostor `$C000-$C3FF`. Pro tento modul dávejte firmware symboly ideálně na `$C000-$C00F`, například:

```asm
APRTS_ADDR_L      = $C000
APRTS_ADDR_M      = $C001
APRTS_ADDR_H      = $C002
APRTS_DATA        = $C003
APRTS_CTRL        = $C004
APRTS_DEBUG       = $C005
APRTS_DIAG_ADDR_L = $C006
APRTS_DIAG_ADDR_M = $C007
APRTS_DIAG_ADDR_H = $C008
APRTS_DIAG_EXP    = $C009
APRTS_DIAG_ACT    = $C00A
APRTS_DIAG_STATE  = $C00B
```

Pozor: starší soubory [Firmware/src/vdp_low.asm](../Firmware/src/vdp_low.asm) a [Firmware/src/io.inc65](../Firmware/src/io.inc65) používají historické TMS9918/VDP aliasy `VDP_MODE0 = $C000`, `VDP_MODE1 = $C001`. To není přímá register mapa tohoto FPGA modulu. Pro `aprts_vga` je potřeba low-level driver upravit na offsety výše.

## VRAM adresa a auto-increment

Aktuální VRAM adresa je složená z registrů:

```text
current_vram_addr = { ADDR_H[2:0], ADDR_M, ADDR_L }
```

Adresa má 19 bitů, tedy rozsah `0x00000-0x7FFFF`. Modul reálně používá hlavně spodní část pro obraz a horní malý blok pro paletu.

Bity `ADDR_H[7:4]` vybírají auto-increment krok po přístupu přes `DATA`:

| `ADDR_H[7:4]` | Krok |
|---:|---:|
| `0` | `0` |
| `1` | `1` |
| `2` | `2` |
| `3` | `4` |
| `4` | `8` |
| `5` | `16` |
| `6` | `32` |
| `7` | `64` |
| `8` | `128` |
| `9` | `256` |
| jiné | `1` |

Typická hodnota pro lineární zápis bajtů je `ADDR_H = %00010000 | addr[18:16]`, tedy krok 1. Pro zápis pouze atributů textu se hodí krok 2 a start na liché adrese.

## Řídicí registr `CTRL` (`+4`)

Resetová hodnota je `0x80`.

| Bit | Význam |
|---:|---|
| `7` | Splash/BIST obrazec aktivní. První zápis do `DATA` jej automaticky vynuluje. Lze jej znovu nastavit zápisem do `CTRL`. |
| `6:4` | Rezervováno. V aktuální implementaci se ukládají, ale nepoužívají. |
| `3:1` | Výběr aktivní textové palety `0-7`. Používá se jen v textovém režimu. |
| `0` | Video režim: `0` = text, `1` = bitmapa. |

Příklady:

```asm
; textovy rezim, paleta 0, bez splash
lda #%00000000
sta APRTS_CTRL

; bitmapovy rezim, bez splash
lda #%00000001
sta APRTS_CTRL

; textovy rezim, paleta 3
lda #%00000110
sta APRTS_CTRL
```

## Debug/status registr `+5`

Zápis na offset `+5` nastavuje `DEBUG_CTRL`:

| Bit | Význam při zápisu |
|---:|---|
| `7:5` | Ruční debug barva overlaye. `0` znamená automatický debug kód. |
| `4:2` | Rezervováno. |
| `1` | Po zápisu `1` se spustí požadavek na vymazání SRAM oblasti `0x00000-0x12BFF` nulami. Bit funguje jako trigger, ne jako trvalý stav. |
| `0` | Povolit debug overlay v pravém horním rohu obrazu. Resetově je `1`. |

Čtení offsetu `+5` vrací `STATUS`:

| Bit | Název | Význam |
|---:|---|---|
| `7` | `cpu_write_pending` | Čeká zápis CPU do externí SRAM. |
| `6` | `cpu_read_pending` | Čeká čtení CPU z externí SRAM. |
| `5` | `sram_clear_active` | Probíhá nulování SRAM. |
| `4` | `sram_diag_busy` | Po startu FPGA běží vestavěná SRAM diagnostika. |
| `3` | `sram_diag_done` | Diagnostika doběhla. |
| `2` | `sram_diag_error` | Diagnostika našla chybu. |
| `1` | - | Vždy `0`. |
| `0` | `overlay_enable` | Aktuální stav debug overlaye. |

Před hromadným plněním VRAM je vhodné počkat, až `sram_diag_busy == 0`. Při použití SRAM clear počkejte, až `sram_clear_active == 0`.

## VRAM layout

### Textový režim

Textový režim zobrazuje 80 sloupců x 60 řádků. Každý znak zabírá 2 bajty:

```text
adresa = (radek * 80 + sloupec) * 2

+0: character id
+1: atribut
```

Atribut má tento formát:

```text
bit 7:4 = foreground color index 0-15
bit 3:0 = background color index 0-15
```

Skutečný index do 256položkové palety v textovém režimu je:

```text
{ 0, CTRL[3:1], foreground_or_background_nibble }
```

Tím vzniká 8 textových palet po 16 barvách. `CTRL[3:1]` vybírá jednu z nich.

Font je uložen v externí SRAM na adresách:

```text
0x03000 + character_id * 8 + font_row
```

Každý znak má 8 bajtů, jeden bajt na řádek. Bit 7 je levý pixel znaku, bit 0 pravý pixel znaku. Pro 256 znaků je potřeba oblast `0x03000-0x037FF`.

Textová obrazovka používá adresy `0x00000-0x0257F`:

```text
80 * 60 * 2 = 9600 bajtu = 0x2580
```

Oblast fontu leží mimo textovou obrazovku, ale pořád ve stejné externí SRAM.

### Bitmapový režim

Bitmapový režim čte framebuffer jako 320x240 bajtů. Každý bajt je 8bitový index do palety. Každý logický pixel se zobrazí jako 2x2 fyzické VGA pixely, takže výsledný obraz vyplní 640x480.

Adresa pixelu:

```text
adresa = y * 320 + x
x = 0-319
y = 0-239
```

Rozsah framebufferu je:

```text
0x00000-0x12BFF
320 * 240 = 76800 bajtu = 0x12C00
```

## Palette RAM

Paleta má 256 položek. Každá položka má 12bitovou barvu ve formátu:

```text
RRRR GGGG BBBB
```

V paměťovém prostoru CPU se paleta zapisuje přes `DATA` na speciální VRAM adresy:

```text
0x1F000-0x1F1FF
```

Každá barva zabírá 2 bajty:

```text
0x1F000 + index * 2 + 0: low byte  = GGGG BBBB
0x1F000 + index * 2 + 1: high byte = ---- RRRR
```

Interně se low byte ukládá do `palette_ram_low[index]`, horní nibble do `palette_ram_high[index]`. Při výstupu na 9bitový VGA DAC se používají horní 3 bity každé 4bitové složky:

```text
red   = R[3:1]
green = G[3:1]
blue  = B[3:1]
```

Příklad zápisu jedné barvy:

```asm
; nastav palette[0] = bila: R=F, G=F, B=F
lda #<$1F000
sta APRTS_ADDR_L
lda #>$1F000
sta APRTS_ADDR_M
lda #%00010001      ; addr[18:16] = 1, auto-increment = 1
sta APRTS_ADDR_H
lda #$FF            ; GGGG BBBB
sta APRTS_DATA
lda #$0F            ; ---- RRRR
sta APRTS_DATA
```

Poznámka k assembleru: cc65/ca65 neumí přímo `#<$1F000` jako 19bit adresu podle očekávání ve všech kontextech. V praxi si raději připravte makra nebo konstanty pro low/mid/high část 19bitové VRAM adresy.

## Základní programovací sekvence

### Nastavení VRAM adresy

```asm
; vstup: addr = 19bit konstanta, step nibble = 1 pro auto-increment +1
lda #addr_low
sta APRTS_ADDR_L
lda #addr_mid
sta APRTS_ADDR_M
lda #(addr_high3 | $10)
sta APRTS_ADDR_H
```

Kde:

```text
addr_low   = addr & 0xFF
addr_mid   = (addr >> 8) & 0xFF
addr_high3 = (addr >> 16) & 0x07
```

### Zápis bajtu do VRAM

```asm
lda value
sta APRTS_DATA
```

Po dokončení zápisu modul zvýší interní VRAM adresu podle kroku v `ADDR_H[7:4]`.

### Čtení bajtu z VRAM

```asm
lda APRTS_DATA
```

I čtení přes `DATA` zvýší adresu podle kroku. Čtení z externí SRAM je arbitrováno mezi VGA fetch a CPU přístupem, takže pro velmi rychlé CPU je rozumné držet v driveru malé zpoždění nebo číst status `cpu_read_pending`/`cpu_write_pending`, pokud se objeví nestabilita.

### Vymazání obrazové SRAM přes hardware

```asm
lda #%00000011      ; overlay enable + SRAM clear trigger
sta APRTS_DEBUG

wait_clear:
    lda APRTS_DEBUG ; cteni vraci STATUS
    and #%00100000  ; sram_clear_active
    bne wait_clear
```

Clear nuluje rozsah `0x00000-0x12BFF`, tedy bitmap framebuffer. Paletu nemaže.

## Inicializace textového režimu

Minimální postup:

1. Po resetu počkat na dokončení SRAM diagnostiky (`STATUS.bit4 == 0`).
2. Volitelně vymazat SRAM přes `DEBUG_CTRL.bit1`.
3. Zapsat paletu do `0x1F000-0x1F1FF`.
4. Zapsat 256znakový font do `0x03000-0x037FF`.
5. Zapsat text screen buffer od `0x00000`.
6. Nastavit `CTRL.bit0 = 0`, vybrat textovou paletu v `CTRL[3:1]`, vypnout splash v `CTRL.bit7`.

Příklad výpočtu adresy znaku:

```c
uint32_t cell = (row * 80u + col) * 2u;
vram[cell + 0] = character_id;
vram[cell + 1] = (foreground << 4) | background;
```

## Inicializace bitmapového režimu

Minimální postup:

1. Po resetu počkat na dokončení SRAM diagnostiky (`STATUS.bit4 == 0`).
2. Zapsat paletu do `0x1F000-0x1F1FF`.
3. Zapsat framebuffer `320*240` bajtů do `0x00000-0x12BFF`.
4. Nastavit `CTRL.bit0 = 1` a vypnout splash (`CTRL.bit7 = 0`).

Příklad výpočtu adresy pixelu:

```c
uint32_t pixel = y * 320u + x;
vram[pixel] = palette_index;
```

## Debug overlay

Když je `DEBUG_CTRL.bit0 = 1`, modul kreslí v pravém horním rohu malý barevný overlay (`x=608-631`, `y=8-31`). Barva ukazuje aktivitu modulu:

| Kód | Barva | Význam |
|---:|---|---|
| `1` | červená | CPU zápis do registru nebo blikající SRAM chyba. |
| `2` | žlutá | CPU čtení registru. |
| `3` | purpurová | Zápis do Palette RAM. |
| `4` | zelená | Dokončený CPU zápis do externí SRAM nebo SRAM diagnostika OK. |
| `5` | azurová | Dokončené CPU čtení z externí SRAM. |
| `6` | modrá | SRAM diagnostika běží nebo video fetch/idle baseline. |
| `0` | bílá | Výchozí/ruční fallback. |

Pokud `DEBUG_CTRL[7:5]` není nula, vynutí ruční kód barvy a automatická signalizace se nepoužije.

## SRAM diagnostika po startu

Po startu je `sram_diag_busy = 1`. Modul zapíše a přečte několik kontrolních bodů:

| Index | Adresa | Hodnota |
|---:|---:|---:|
| `0` | `0x00000` | `0x55` |
| `1` | `0x00001` | `0xAA` |
| `2` | `0x03000` | `0xC3` |
| `3` | `0x037FF` | `0x3C` |
| `4` | `0x12BFE` | `0x5A` |
| `5` | `0x12BFF` | `0xA5` |

Po dokončení nastaví `STATUS.bit3`. Pokud najde chybu, nastaví `STATUS.bit2` a uloží první chybnou adresu i očekávanou/skutečnou hodnotu do diagnostických registrů `+6` až `+10`.

Firmware by měl při inicializaci udělat:

```asm
wait_diag:
    lda APRTS_DEBUG      ; STATUS
    and #%00010000       ; sram_diag_busy
    bne wait_diag

    lda APRTS_DEBUG
    and #%00000100       ; sram_diag_error
    beq diag_ok
    ; cist APRTS_DIAG_ADDR_L/M/H, APRTS_DIAG_EXP, APRTS_DIAG_ACT
diag_ok:
```

## Arbitráž SRAM

Externí SRAM sdílí VGA fetch a CPU přístup.

V bitmapovém režimu používá VGA jednoduchý 2fázový přístup podle `h_cnt[0]`: na sudé fázi nastaví adresu a povolí output enable, na liché fázi vzorkuje pixel. CPU přístup se obsluhuje ve zbývající části této sekvence.

V textovém režimu se používá 8fázové TDM podle `h_cnt[2:0]`:

| Fáze | Činnost |
|---:|---|
| `0` | Čtení character id z text screen bufferu. |
| `1` | Uložení character id, nastavení adresy atributu. |
| `2` | Uložení atributu, nastavení adresy řádku fontu. |
| `3` | Uložení řádku fontu. |
| `4-7` | Volné sloty pro CPU čtení/zápis SRAM. |

CPU zápis do externí SRAM je několikacyklový: setup, `WE` aktivní, hold. Po dokončení vznikne `cpu_write_done` a auto-increment posune VRAM adresu. Zápis do Palette RAM externí SRAM nepoužívá a dokončí se okamžitě v register logice.

## VGA časování

Modul generuje standardní 640x480 @ 60 Hz časování:

| Parametr | Hodnota |
|---|---:|
| Aktivní horizontální pixely | 640 |
| Front porch H | 16 |
| HSYNC | 96 |
| Back porch H | 48 |
| Celkem H | 800 |
| Aktivní vertikální řádky | 480 |
| Front porch V | 10 |
| VSYNC | 2 |
| Back porch V | 33 |
| Celkem V | 525 |

`hsync` a `vsync` jsou aktivní v nule.

## Praktické poznámky pro firmware

- Nepoužívejte starý TMS9918 způsob `VDP_MODE0/VDP_MODE1` jako jediný data/control pár. Tento modul má vlastní 16offsetový register map.
- Před prvním zápisem obrazu počkejte na konec SRAM diagnostiky, jinak se CPU a diagnostika budou přetahovat o externí SRAM.
- Při zápisu lineárních bloků nastavte auto-increment na `+1`; při zápisu textových atributů samostatně použijte `+2`.
- Každý zápis na `DATA` vypne splash obrazec. `CTRL.bit7` tedy není vhodný jako trvalé blankování během plnění framebufferu přes běžné VRAM zápisy.
- Palette RAM je interní, takže ji lze plnit i bez externí SRAM, ale pořád používejte stejnou adresní latch sekvenci.
- Debug overlay je po resetu zapnutý (`DEBUG_CTRL = 0x01`). Pro čistý obraz zapište `0x00` do `DEBUG_CTRL`.

## Doporučené názvy pro nový low-level driver

```c
#define APRTS_BASE          0xC000u
#define APRTS_ADDR_L        (*(volatile uint8_t *)(APRTS_BASE + 0))
#define APRTS_ADDR_M        (*(volatile uint8_t *)(APRTS_BASE + 1))
#define APRTS_ADDR_H        (*(volatile uint8_t *)(APRTS_BASE + 2))
#define APRTS_DATA          (*(volatile uint8_t *)(APRTS_BASE + 3))
#define APRTS_CTRL          (*(volatile uint8_t *)(APRTS_BASE + 4))
#define APRTS_DEBUG_STATUS  (*(volatile uint8_t *)(APRTS_BASE + 5))
```

Pro assembler doporučuji vytvořit samostatný include, například `aprts_vga.inc65`, a nemíchat tyto registry se starými symboly `VDP_MODE0/VDP_MODE1`.

## Známá omezení aktuální implementace

- `lv_mem_r` se zatím nepoužívá.
- Register `+15` není definovaný.
- `CTRL[6:4]` a `DEBUG_CTRL[4:2]` jsou rezervované bez funkce.
- Není zde hardwarový reset vstup; výchozí hodnoty registrů spoléhají na FPGA initial values.
- Čtecí/zapisovací handshake vůči CPU je minimalistický. Pokud firmware poběží na vyšším taktu a objeví se nestabilita, přidejte do low-level driveru krátké čekání nebo polling pending bitů ve `STATUS`.
- Modul není kompatibilní se softwarem pro TMS9918 bez adaptační vrstvy.
