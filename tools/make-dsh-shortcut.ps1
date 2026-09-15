# ============================================================================
#  make-dsh-shortcut.ps1  --  create a launcher shortcut with the DSH icon
#
#  Creates a .lnk pointing at the launcher .cmd in the project root, with
#  assets\dsh-icon.ico, so the icon shows on the desktop / Start menu / taskbar.
#
#  Usage (run from the project root):
#    powershell -ExecutionPolicy Bypass -File tools\make-dsh-shortcut.ps1
#    powershell -ExecutionPolicy Bypass -File tools\make-dsh-shortcut.ps1 -StartMenu
#    powershell -ExecutionPolicy Bypass -File tools\make-dsh-shortcut.ps1 -Desktop 0 -StartMenu 1
#    powershell -ExecutionPolicy Bypass -File tools\make-dsh-shortcut.ps1 -Launcher other.cmd
#
#  Keep this file ASCII-only. Windows PowerShell reads a BOM-less script as
#  ANSI/GBK, so a non-ASCII filename written here would be mangled; the
#  launcher is therefore discovered by listing the project root instead.
# ============================================================================
param(
    [switch]$Desktop = $true,
    [switch]$StartMenu,
    [string]$Launcher,
    [string]$Name = 'dsh-keepup',
    [string]$Directory
)

$ErrorActionPreference = 'Stop'
$here   = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)  # project root
$icon   = Join-Path $here 'assets\dsh-icon.ico'

# Discover the launcher: an explicit -Launcher, else the known entry name, else
# the project root's only .cmd.
function Resolve-Launcher {
    param([string]$Explicit)
    if ($Explicit) {
        $candidate = Join-Path $here $Explicit
        if (Test-Path -LiteralPath $candidate) { return $candidate }
        $candidate = Join-Path (Join-Path $here 'tools') $Explicit
        if (Test-Path -LiteralPath $candidate) { return $candidate }
        throw ('launcher not found: ' + $Explicit)
    }
    foreach ($known in @('dsh-keepup.cmd', 'dsh.cmd')) {
        $preferred = Join-Path $here $known
        if (Test-Path -LiteralPath $preferred) { return $preferred }
    }
    $found = @(Get-ChildItem -LiteralPath $here -Filter *.cmd -File)
    if ($found.Count -eq 1) { return $found[0].FullName }
    if ($found.Count -eq 0) { throw ('no launcher .cmd found in ' + $here) }
    throw ('several .cmd files in ' + $here + '; pass -Launcher <name>')
}

$target = Resolve-Launcher -Explicit $Launcher

if (-not (Test-Path -LiteralPath $icon)) {
    Write-Host ('ERROR: icon not found: ' + $icon) -ForegroundColor Red
    Write-Host 'Run: node tools/make-dsh-icon.mjs' -ForegroundColor Yellow
    exit 1
}

function New-DshShortcut {
    param([string]$Directory, [string]$Label)

    if (-not (Test-Path -LiteralPath $Directory)) {
        New-Item -ItemType Directory -Path $Directory -Force | Out-Null
    }
    $path = Join-Path $Directory ($Name + '.lnk')

    $shell    = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($path)
    $shortcut.TargetPath       = $target
    $shortcut.WorkingDirectory = (Split-Path -Parent $target)
    $shortcut.IconLocation     = $icon + ',0'
    $shortcut.Description      = 'Launch DeepSeek Harness (checks for updates first)'
    $shortcut.WindowStyle      = 1
    $shortcut.Save()

    if (-not (Test-Path -LiteralPath $path)) { throw ('shortcut was not written: ' + $path) }

    $check = $shell.CreateShortcut($path)
    Write-Host ('  ' + $Label + ': ' + $path) -ForegroundColor Green
    Write-Host ('      target -> ' + $check.TargetPath) -ForegroundColor DarkGray
    Write-Host ('      icon   -> ' + $check.IconLocation) -ForegroundColor DarkGray
    return $path
}

Write-Host ''
Write-Host 'DeepSeek Harness shortcut' -ForegroundColor Cyan
Write-Host ('  target: ' + $target) -ForegroundColor DarkGray
Write-Host ('  icon  : ' + $icon) -ForegroundColor DarkGray
Write-Host ''

$made = @()
if ($Directory) {
    $made += New-DshShortcut -Directory $Directory -Label 'custom'
} else {
    if ($Desktop)  { $made += New-DshShortcut -Directory ([Environment]::GetFolderPath('Desktop')) -Label 'desktop' }
    if ($StartMenu) {
        $programs = Join-Path ([Environment]::GetFolderPath('Programs')) 'DeepSeek Harness'
        $made += New-DshShortcut -Directory $programs -Label 'start menu'
    }
}

Write-Host ''
Write-Host ($made.Count.ToString() + ' shortcut(s) created.') -ForegroundColor Green
Write-Host 'Tip: right-click the desktop icon and pick "Pin to taskbar" for one-click access.' -ForegroundColor DarkGray
Write-Host ''
