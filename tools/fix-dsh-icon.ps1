# ============================================================================
#  fix-dsh-icon.ps1  --  make Windows show the current dsh-icon.ico
#
#  Why this is needed: Windows keeps a shell icon cache keyed by the icon path
#  and index (for example "assets\dsh-icon.ico,0"). Replacing the contents of
#  an .ico that already has a cache entry often keeps showing the old picture,
#  because the cached render still matches that key.
#
#  What this does:
#    1. verifies the .ico on disk really is the current artwork;
#    2. points every DSH shortcut it can find at the icon, choosing an index
#       that is NOT currently cached so Explorer is forced to re-read the file;
#    3. optionally restarts Explorer, which drops the in-memory icon database
#       and is the reliable cure-all.
#
#  Usage (run from the project root):
#    powershell -ExecutionPolicy Bypass -File tools\fix-dsh-icon.ps1
#    powershell -ExecutionPolicy Bypass -File tools\fix-dsh-icon.ps1 -RestartExplorer
#
#  Keep this file ASCII-only (Windows PowerShell reads BOM-less scripts as ANSI).
# ============================================================================
param(
    [switch]$RestartExplorer,
    [string]$IconPath,
    [int]$IconIndex = 1
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)  # project root
if (-not $IconPath) { $IconPath = Join-Path $here 'assets\dsh-icon.ico' }

Write-Host ''
Write-Host 'DeepSeek Harness icon check' -ForegroundColor Cyan
Write-Host ''

# --- 1. is the file on disk the current artwork? -----------------------------
if (-not (Test-Path -LiteralPath $IconPath)) {
    Write-Host ('ERROR: icon not found: ' + $IconPath) -ForegroundColor Red
    exit 1
}

Add-Type -AssemblyName System.Drawing
$icon = New-Object System.Drawing.Icon($IconPath, 128, 128)
$bitmap = $icon.ToBitmap()
$corner = $bitmap.GetPixel([Math]::Min(4, $bitmap.Width - 1), [Math]::Min(4, $bitmap.Height - 1))
$file = Get-Item -LiteralPath $IconPath

Write-Host ('  file  : ' + $IconPath)
Write-Host ('  size  : ' + $file.Length + ' bytes, modified ' + $file.LastWriteTime)
Write-Host ('  frame : ' + $bitmap.Width + 'x' + $bitmap.Height + ', corner RGB(' + $corner.R + ',' + $corner.G + ',' + $corner.B + ')')

if ($corner.R -gt 60 -and $corner.B -gt 200) {
    Write-Host '  verdict: this looks like the OLD blue artwork.' -ForegroundColor Yellow
    Write-Host '           Run: node tools/make-dsh-icon.mjs' -ForegroundColor Yellow
} elseif ($corner.R -lt 40 -and $corner.G -lt 40 -and $corner.B -lt 70) {
    Write-Host '  verdict: current dark artwork. The file is fine, so a stale' -ForegroundColor Green
    Write-Host '           Windows icon cache is the reason for the old picture.' -ForegroundColor Green
} else {
    Write-Host '  verdict: unrecognised artwork; check the generator.' -ForegroundColor Yellow
}
Write-Host ''

# --- 2. point DSH shortcuts at the icon -------------------------------------
function Get-ShortcutTarget {
    param([string]$Path)
    try {
        $shell = New-Object -ComObject WScript.Shell
        return $shell.CreateShortcut($Path)
    } catch {
        return $null
    }
}

$searchRoots = @(
    [Environment]::GetFolderPath('Desktop'),
    (Join-Path ([Environment]::GetFolderPath('Programs')) 'DeepSeek Harness'),
    $here
)

$repaired = 0
foreach ($root in $searchRoots) {
    if (-not (Test-Path -LiteralPath $root)) { continue }
    $links = @(Get-ChildItem -LiteralPath $root -Filter *.lnk -File -ErrorAction SilentlyContinue)
    foreach ($link in $links) {
        $shortcut = Get-ShortcutTarget -Path $link.FullName
        if ($null -eq $shortcut) { continue }

        # Only touch shortcuts that actually launch the DSH launcher.
        $isDsh = ($shortcut.TargetPath -like '*DSH.cmd') -or ($shortcut.TargetPath -like '*dsh*.cmd')
        if (-not $isDsh) { continue }

        $wanted = $IconPath + ',' + $IconIndex
        if ($shortcut.IconLocation -ne $wanted) {
            Write-Host ('  updating: ' + $link.Name) -ForegroundColor Green
            Write-Host ('      was: ' + $shortcut.IconLocation) -ForegroundColor DarkGray
            $shortcut.IconLocation = $wanted
            $shortcut.Save()
            Write-Host ('      now: ' + $wanted) -ForegroundColor DarkGray
            $repaired++
        } else {
            Write-Host ('  already correct: ' + $link.Name) -ForegroundColor DarkGray
        }
    }
}
Write-Host ''
Write-Host ('  ' + $repaired + ' shortcut(s) updated.') -ForegroundColor Green
Write-Host ''

# --- 3. optionally restart Explorer ------------------------------------------
if ($RestartExplorer) {
    Write-Host '  restarting Explorer to drop the in-memory icon cache ...' -ForegroundColor Cyan
    $explorers = @(Get-Process explorer -ErrorAction SilentlyContinue)
    if ($explorers.Count -eq 0) {
        Write-Host '  Explorer was not running; starting it.' -ForegroundColor Yellow
        Start-Process explorer.exe
    } else {
        $explorers | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 3
        Start-Process explorer.exe
        Write-Host '  Explorer restarted (the taskbar and desktop flicker once).' -ForegroundColor Green
    }
    Start-Sleep -Seconds 2
    $back = @(Get-Process explorer -ErrorAction SilentlyContinue).Count
    Write-Host ('  explorer processes now: ' + $back) -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '  The desktop icon should now show the dark artwork. If it does not,' -ForegroundColor Cyan
    Write-Host '  run the icon generator to get a NEW file name:' -ForegroundColor Cyan
    Write-Host '      node tools/make-dsh-icon.mjs' -ForegroundColor DarkGray
} else {
    Write-Host '  Next step: re-run with -RestartExplorer to clear the icon cache:' -ForegroundColor Yellow
    Write-Host '      powershell -ExecutionPolicy Bypass -File tools\fix-dsh-icon.ps1 -RestartExplorer' -ForegroundColor DarkGray
}

Write-Host ''
