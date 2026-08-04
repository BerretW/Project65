# APARTS_BUS — RTL testbenche (Quartus / ModelSim / Icarus)

Funkční simulace pro `aprts_vga` bez nutnosti hardwaru.

## Soubory

| Soubor | Popis |
|--------|--------|
| `sram_model.v` | Behaviorální model externí 512 KB SRAM |
| `tb_vga_timing.v` | Unit test VGA 640×480 timing |
| `tb_aprts_audio.v` | Unit test audio registrů + I2S hodin |
| `tb_aprts_bus.v` | Integrační test celého `aprts_bus` |
| `run_msim.do` / `run_msim.bat` | ModelSim / Questa-Intel |
| `run_iverilog.bat` | Icarus Verilog (volitelně) |

## Co se testuje (`tb_aprts_bus`)

1. Výchozí hodnoty registrů a `addr_ready`
2. R/W: barva pozadí, mode, adresa
3. Zápis do SRAM přes port `$4`, auto-inkrement, readback
4. Font RAM v režimu `$0D` (bez auto-inc adresy)
5. Audio porty `$5`/`$6` + auto-inc indexu
6. Blank mode `$0F` (černá)
7. HW reset přes mode `$0E`
8. Clear engine: busy/ready + zápis nul
9. Aktivita HSYNC
10. Žádný zápis při neaktivním `lv_cs`

## Spuštění — ModelSim / Quartus

```bat
cd aprts_vga\sim
run_msim.bat
```

Nebo ručně:

```bat
vsim -c -do run_msim.do
```

V Quartus Prime: přidej TB do projektu jako testbench (`Settings → EDA Tool Settings → Simulation`)  
top-level testbench = `tb_aprts_bus`, a spusť **RTL Simulation**.

Doporučené přiřazení v QSF (volitelné):

```tcl
set_global_assignment -name EDA_SIMULATION_TOOL "ModelSim-Altera (Verilog)"
set_global_assignment -name EDA_TEST_BENCH_ENABLE_STATUS TEST_BENCH_MODE -section_id eda_simulation
set_global_assignment -name EDA_NATIVELINK_SIMULATION_TEST_BENCH tb_aprts_bus -section_id eda_simulation
set_global_assignment -name EDA_TEST_BENCH_NAME tb_aprts_bus -section_id eda_simulation
set_global_assignment -name EDA_DESIGN_INSTANCE_NAME uut -section_id tb_aprts_bus
set_global_assignment -name EDA_TEST_BENCH_MODULE_NAME tb_aprts_bus -section_id tb_aprts_bus
set_global_assignment -name EDA_TEST_BENCH_FILE sim/tb_aprts_bus.v -section_id tb_aprts_bus
set_global_assignment -name EDA_TEST_BENCH_FILE sim/sram_model.v -section_id tb_aprts_bus
```

## Spuštění — Icarus Verilog

```bat
cd aprts_vga\sim
run_iverilog.bat
```

## Hodiny

TB generuje **25 MHz** (`period 40 ns`) — shodné s VGA pixel clock na desce.

## Poznámky

- Plné hardwarové mazání SRAM (až `0x4AFFF`) v sim neběží do konce — TB ověří busy a prvních pár zápisů, pak clear přeruší přes reset `$0E`.
- `pcm_sck` je v `aprts_audio.v` natvrdo `0` (MCLK se nepoužívá); TB kontroluje `pcm_bck` / `pcm_lrck`.
- Čtení SRAM přes CPU během `video_on` může kolidovat s VGA arbiterem — readback zkouší více pokusů.
