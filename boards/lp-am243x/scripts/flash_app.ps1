# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Liviu Silaghe
<#
    Flash the signed application into OSPI so the board boots it on its own,
    instead of having it dropped into RAM by the debugger.

        .\flash_app.ps1 -Port COM6 [-Scheme ml-dsa-87] [-Variant r5f]
                        [-Acvp] [-Multest] [-Paint] [-Align] [-Trap] [-Sdk <path>]

    -Scheme names the algorithm and its parameter set together, so there is no
    way to ask for a pair that does not exist.

    Two images go into flash:
      0x00000  sbl_ospi          the SDK's prebuilt secondary boot loader
      0x80000  our application   build/<scheme>-<variant>/pqr5f-*.mcelf.hs_fs

    Build it first with: make SCHEME=<scheme> VARIANT=<variant>

    The board must be in UART BOOT MODE for this - a different switch setting
    from the DEV BOOT MODE used for JTAG loading; see the SDK's EVM Setup page,
    section "UART BOOT MODE / AM243X-LP", where the positions are pictured.
    Afterwards, switch to OSPI BOOT MODE and power-cycle to run what you wrote.

    Needs pyserial: pip install pyserial
#>
param(
    [Parameter(Mandatory=$true)][string]$Port,
    [ValidateSet("ml-dsa-44", "ml-dsa-65", "ml-dsa-87")]
    [string]$Scheme = "ml-dsa-87",
    [ValidateSet("r5f", "r5fstack", "pqclean")]
    [string]$Variant = "r5f",
    [switch]$Multest,
    [switch]$Paint,
    [switch]$Acvp,
    [switch]$Align,
    [switch]$Trap,
    [string]$Sdk = "C:/ti/mcu_plus_sdk_am243x_12_00_00_27"
)

$ErrorActionPreference = "Stop"
# The build tree is one level up: this script lives in scripts/.
$here = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$boot = Join-Path $Sdk "tools/boot"
$prebuilt = "sbl_prebuilt/am243x-lp"

# MULTEST=1 builds into its own directory, so the image name alone does not
# say which one it is - the suffix has to be carried here too.
$suffix = $(if ($Paint) { "-paint" } else { "" }) +
          $(if ($Acvp) { "-acvp" } else { "" }) +
          $(if ($Multest) { "-multest" } else { "" }) +
          $(if ($Align) { "-align" } else { "" }) +
          $(if ($Trap) { "-trap" } else { "" })
$make   = "make SCHEME=$Scheme VARIANT=$Variant" +
          $(if ($Paint)   { " STACKPAINT=1" }  else { "" }) +
          $(if ($Acvp)    { " ACVP=1" }        else { "" }) +
          $(if ($Multest) { " MULTEST=1" }     else { "" }) +
          $(if ($Align)   { " STRICT_ALIGN=1" } else { "" }) +
          $(if ($Trap)    { " ALIGN_TRAP=1" }   else { "" })
$name   = "$Scheme-$Variant"
$app    = Join-Path $here "build\$name$suffix\pqr5f-$name.mcelf.hs_fs"

if (-not (Test-Path $app)) {
    throw "Missing $app - build it first with: $make"
}

# The config is generated rather than checked in: it has to carry absolute
# paths to this working copy, and those differ per machine.
$cfg = Join-Path $env:TEMP "pqr5f_flash.cfg"
@"
--flash-writer=$prebuilt/sbl_uart_uniflash.release.hs_fs.tiimage
--operation=flash-phy-tuning-data
--file=$prebuilt/sbl_ospi.release.hs_fs.tiimage --operation=flash --flash-offset=0x0
--file=$($app -replace '\\','/') --operation=flash --flash-offset=0x80000
"@ | Set-Content -Encoding ASCII $cfg

$python = (& py -3 -c "import sys; print(sys.executable)") 2>$null
if (-not $python) { $python = "python" }

Write-Host "Flashing through $Port. The board must be in UART BOOT MODE."
Push-Location $boot
try {
    & $python "uart_uniflash.py" "-p" $Port "--cfg=$cfg"
    $rc = $LASTEXITCODE
} finally {
    Pop-Location
}

# uart_uniflash.py reports missing modules and a failed transfer on stdout and
# still exits, so the result has to be checked before telling anyone the board
# is ready to boot from flash.
if ($rc -ne 0) {
    Write-Host ""
    Write-Host "Flashing FAILED (exit $rc). The board still holds whatever it held before."
    Write-Host "If it complains about missing modules: pip install pyserial tqdm xmodem pyelftools"
    exit $rc
}

Write-Host ""
Write-Host "Now set OSPI BOOT MODE and power-cycle the board."
