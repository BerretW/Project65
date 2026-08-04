@echo off
setlocal
cd /d "%~dp0"

where iverilog >nul 2>&1
if errorlevel 1 (
  echo Icarus Verilog (iverilog) not found in PATH.
  echo Install from https://bleyer.org/icarus/ or use ModelSim via run_msim.bat
  exit /b 1
)

set SRC=..
set FAIL=0

echo ========== tb_vga_timing ==========
iverilog -g2012 -o tb_vga_timing.vvp %SRC%\vga_timing.v tb_vga_timing.v
if errorlevel 1 set FAIL=1
vvp tb_vga_timing.vvp
if errorlevel 1 set FAIL=1

echo ========== tb_aprts_audio ==========
iverilog -g2012 -o tb_aprts_audio.vvp %SRC%\aprts_audio.v tb_aprts_audio.v
if errorlevel 1 set FAIL=1
vvp tb_aprts_audio.vvp
if errorlevel 1 set FAIL=1

echo ========== tb_aprts_bus ==========
iverilog -g2012 -o tb_aprts_bus.vvp ^
  %SRC%\vga_timing.v ^
  %SRC%\vga_video_gen.v ^
  %SRC%\sram_controller.v ^
  %SRC%\aprts_audio.v ^
  %SRC%\aprts_bus.v ^
  sram_model.v ^
  tb_aprts_bus.v
if errorlevel 1 set FAIL=1
vvp tb_aprts_bus.vvp
if errorlevel 1 set FAIL=1

echo.
if %FAIL%==0 (
  echo ALL TESTS COMPLETED
) else (
  echo SOME TESTS FAILED / COMPILE ERRORS
)
exit /b %FAIL%
