@echo off
rem SPDX-License-Identifier: Apache-2.0
rem Copyright 2026 Liviu Silaghe
rem Wrapper for flash_app.ps1 - see there for what it does and for the boot
rem mode the board has to be in.
rem
rem Usage:  flash_app.bat COM6 [ml-dsa-44|ml-dsa-65|ml-dsa-87]
rem                            [r5f|r5fstack|pqclean] [acvp|multest] [paint] [align] [trap]
rem
rem The scheme names the algorithm and its parameter set in one token, so a
rem pair that does not exist cannot be asked for. A bare 44, 65 or 87 is
rem accepted as shorthand for the ML-DSA set of that size, and a leading dash
rem is ignored, so -acvp and acvp both work.
rem
rem Arguments are matched by what they say, not by position. Anything not
rem recognised is an error: silently falling back to a default would flash a
rem different image than the one asked for, and the directory for that image
rem usually exists.
rem
rem Defaults: ml-dsa-87, r5f, the benchmark.

setlocal EnableDelayedExpansion
if "%~1"=="" (
    echo Usage: flash_app.bat ^<COM port^> [ml-dsa-44^|ml-dsa-65^|ml-dsa-87] [r5f^|r5fstack^|pqclean] [acvp^|multest] [paint] [align] [trap]
    echo   The console UART of the LP-AM243 is the "XDS110 Class Application/User UART".
    exit /b 1
)

set "SCHEME=ml-dsa-87"
set "VARIANT=r5f"
set "MULTEST="
set "PAINT="
set "ACVP="
set "ALIGN="
set "TRAP="

for %%k in (%2 %3 %4 %5 %6 %7) do (
    set "TOK=%%~k"
    if "!TOK:~0,1!"=="-" set "TOK=!TOK:~1!"
    if "!TOK:~0,1!"=="-" set "TOK=!TOK:~1!"
    if "!TOK:~0,1!"=="/" set "TOK=!TOK:~1!"
    set "MATCHED="

    if /i "!TOK!"=="ml-dsa-44" ( set "SCHEME=ml-dsa-44" & set "MATCHED=1" )
    if /i "!TOK!"=="ml-dsa-65" ( set "SCHEME=ml-dsa-65" & set "MATCHED=1" )
    if /i "!TOK!"=="ml-dsa-87" ( set "SCHEME=ml-dsa-87" & set "MATCHED=1" )
    if /i "!TOK!"=="44"        ( set "SCHEME=ml-dsa-44" & set "MATCHED=1" )
    if /i "!TOK!"=="65"        ( set "SCHEME=ml-dsa-65" & set "MATCHED=1" )
    if /i "!TOK!"=="87"        ( set "SCHEME=ml-dsa-87" & set "MATCHED=1" )
    if /i "!TOK!"=="r5f"       ( set "VARIANT=r5f"      & set "MATCHED=1" )
    if /i "!TOK!"=="fast"      ( set "VARIANT=r5f"      & set "MATCHED=1" )
    if /i "!TOK!"=="r5fstack"  ( set "VARIANT=r5fstack" & set "MATCHED=1" )
    if /i "!TOK!"=="stack"     ( set "VARIANT=r5fstack" & set "MATCHED=1" )
    if /i "!TOK!"=="pqclean"   ( set "VARIANT=pqclean"  & set "MATCHED=1" )
    if /i "!TOK!"=="clean"     ( set "VARIANT=pqclean"  & set "MATCHED=1" )
    if /i "!TOK!"=="acvp"      ( set "ACVP=-Acvp"       & set "MATCHED=1" )
    if /i "!TOK!"=="multest"   ( set "MULTEST=-Multest" & set "MATCHED=1" )
    if /i "!TOK!"=="paint"     ( set "PAINT=-Paint"     & set "MATCHED=1" )
    if /i "!TOK!"=="align"     ( set "ALIGN=-Align"     & set "MATCHED=1" )
    if /i "!TOK!"=="trap"      ( set "TRAP=-Trap"       & set "MATCHED=1" )

    if not defined MATCHED (
        echo Unrecognised argument: %%k
        echo   scheme:  ml-dsa-44 ^| ml-dsa-65 ^| ml-dsa-87   ^(or 44 ^| 65 ^| 87^)
        echo   variant: r5f ^| fast ^| r5fstack ^| stack ^| pqclean ^| clean
        echo   build:   acvp ^| multest ^| paint ^| align ^| trap
        exit /b 1
    )
)

echo Flashing %SCHEME% %VARIANT%%ACVP%%MULTEST%%PAINT%%ALIGN%%TRAP%
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0flash_app.ps1" -Port %1 -Scheme %SCHEME% -Variant %VARIANT% %MULTEST% %PAINT% %ACVP% %ALIGN% %TRAP%
endlocal
