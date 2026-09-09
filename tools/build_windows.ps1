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
    [string]$Godot = "C:\Tools\Godot\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe"
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
        Write-Host "Godot 4.7.2 editor not found at:`n  $Godot" -ForegroundColor Red
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

# Godot embeds the PCK by writing a temporary file then renaming it to the final
# exe. On Windows that rename can transiently fail ("PCK Embedding: Failed to rename
# temporary file ...") when antivirus / a sync client briefly locks the freshly
# written ~1 GB file - so retry a few times. Success is judged by a freshly-written
# exe, not $LASTEXITCODE (Godot logs warnings to stderr and the exit code doesn't
# always propagate through every invocation context). A total failure leaves any
# existing build untouched.
$loopStart = Get-Date
$built = $false
for ($i = 1; $i -le 4; $i++) {
    if ($i -gt 1) {
        Write-Host "`n(rename lock - likely antivirus/sync - retry $i/4)" -ForegroundColor Yellow
        Start-Sleep -Seconds 5
    }
    & $Godot --headless --path $proj --export-release "Windows Desktop" $exe
    Start-Sleep -Milliseconds 500
    $item = Get-Item -LiteralPath $exe -ErrorAction SilentlyContinue
    if ($item -and $item.Length -gt 50MB -and $item.LastWriteTime -ge $loopStart) { $built = $true; break }
}

if ($built) {
    $mb = [math]::Round((Get-Item -LiteralPath $exe).Length / 1MB, 1)
    Write-Host "`nBuild OK -> $exe  ($mb MB)" -ForegroundColor Green
    Write-Host "Single self-contained exe (PCK embedded). Double-click to play."
} else {
    Write-Host "`nExport FAILED after 4 tries. See the log above." -ForegroundColor Red
    Write-Host "If it says 'Failed to rename temporary file', an antivirus/sync client is" -ForegroundColor Yellow
    Write-Host "locking the output - exclude the export folder, or build to a local disk." -ForegroundColor Yellow
    Write-Host "If 'no export template found', install the 4.7 templates (docs/BUILD_WINDOWS.md)." -ForegroundColor Yellow
    exit 1
}
