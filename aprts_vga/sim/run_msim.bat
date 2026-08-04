@echo off
setlocal
cd /d "%~dp0"

REM Try common Questa/ModelSim Intel install locations + PATH
set VSIM=
where vsim >nul 2>&1 && set VSIM=vsim
if not defined VSIM if exist "%QUARTUS_ROOTDIR%\..\questa_fse\win64\vsim.exe" set VSIM=%QUARTUS_ROOTDIR%\..\questa_fse\win64\vsim.exe
if not defined VSIM if exist "%QUARTUS_ROOTDIR%\..\modelsim_ase\win32aloem\vsim.exe" set VSIM=%QUARTUS_ROOTDIR%\..\modelsim_ase\win32aloem\vsim.exe
if not defined VSIM if exist "C:\intelFPGA_lite\24.1std\questa_fse\win64\vsim.exe" set VSIM=C:\intelFPGA_lite\24.1std\questa_fse\win64\vsim.exe
if not defined VSIM if exist "C:\intelFPGA_lite\23.1std\questa_fse\win64\vsim.exe" set VSIM=C:\intelFPGA_lite\23.1std\questa_fse\win64\vsim.exe

if not defined VSIM (
  echo ModelSim/Questa vsim not found.
  echo Add vsim to PATH or set QUARTUS_ROOTDIR, or use run_iverilog.bat
  exit /b 1
)

echo Using: %VSIM%
"%VSIM%" -c -do "do run_msim.do"
exit /b %ERRORLEVEL%
