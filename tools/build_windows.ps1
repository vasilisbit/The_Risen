# Build the Windows release of The Risen and place the .exe where you choose.
#
# Usage (from anywhere):
#   powershell -ExecutionPolicy Bypass -File tools\build_windows.ps1
#   powershell -ExecutionPolicy Bypass -File tools\build_windows.ps1 -Out "D:\Games"
#
# Prompts for an export folder (default: your Desktop), then runs a headless
# Godot 4.7 release export of the "Windows Desktop" preset (single embedded-PCK
# exe). Requires the 4.7-stable export templates installed (see docs/BUILD_WINDOWS.md).

param(
    [string]$Out = "",                                   # export folder (skips the prompt)
    [string]$Godot = "C:\Tools\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64.exe"
)

# NOTE: keep this "Continue" - Godot prints import WARNINGs to stderr, and under
# "Stop" PowerShell would abort the build on the first one even though the export
# succeeds. Success is judged by $LASTEXITCODE + the output file below.
$ErrorActionPreference = "Continue"
$proj = Split-Path -Parent $PSScriptRoot            # repo root (tools/..)

# --- locate the Godot editor binary -------------------------------------------
if (-not (Test-Path -LiteralPath $Godot)) {
    $cmd = Get-Command godot -ErrorAction SilentlyContinue
    if ($cmd) { $Godot = $cmd.Source }
    else {
        Write-Host "Godot 4.7 editor not found at:`n  $Godot" -ForegroundColor Red
        Write-Host "Pass its path with -Godot `"C:\path\to\Godot.exe`"." -ForegroundColor Yellow
        exit 1
    }
}

# --- choose the export folder (default: Desktop) ------------------------------
$desktop = [Environment]::GetFolderPath("Desktop")
if (-not $Out) {
    $ans = Read-Host "Export folder [Enter = Desktop: $desktop]"
    $Out = if ([string]::IsNullOrWhiteSpace($ans)) { $desktop } else { $ans.Trim('"') }
}
if (-not (Test-Path -LiteralPath $Out)) { New-Item -ItemType Directory -Force -Path $Out | Out-Null }
$exe = Join-Path $Out "The_Risen.exe"

Write-Host "Building The Risen (Windows Desktop)..." -ForegroundColor Cyan
Write-Host "  Godot : $Godot"
Write-Host "  Proj  : $proj"
Write-Host "  Out   : $exe`n"

& $Godot --headless --path $proj --export-release "Windows Desktop" $exe
$code = $LASTEXITCODE

if ($code -eq 0 -and (Test-Path -LiteralPath $exe)) {
    $mb = [math]::Round((Get-Item -LiteralPath $exe).Length / 1MB, 1)
    Write-Host "`nBuild OK -> $exe  ($mb MB)" -ForegroundColor Green
    Write-Host "Single self-contained exe (PCK embedded). Double-click to play."
} else {
    Write-Host "`nExport FAILED (exit $code). See the log above." -ForegroundColor Red
    Write-Host "Templates missing? See docs/BUILD_WINDOWS.md." -ForegroundColor Yellow
    exit 1
}
