<#
.SYNOPSIS
    Creates the Start Menu shortcut (KOHA.lnk) that lets Lenovo Vantage's
    "User defined key" picker find KOHA.exe.

.DESCRIPTION
    Lenovo Vantage only lists apps registered in the Start Menu, not
    arbitrary exe paths. This drops KOHA.lnk into
    %APPDATA%\Microsoft\Windows\Start Menu\Programs, pointing at KOHA.exe
    in the repo root (the folder above scripts\). The shortcut stores an
    absolute path, so re-run this if the repo folder ever moves.
    Overwrites an existing KOHA.lnk. Needs KOHA.exe to be built already
    (see README.md "Running it").
#>

$repoRoot = Split-Path $PSScriptRoot -Parent
$exe = Join-Path $repoRoot 'KOHA.exe'
if (-not (Test-Path -LiteralPath $exe)) {
    throw "KOHA.exe not found at $exe -- build it first (README.md, 'Running it')."
}

$programs = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
$lnk = Join-Path $programs 'KOHA.lnk'
$shell = New-Object -ComObject WScript.Shell
$sc = $shell.CreateShortcut($lnk)
$sc.TargetPath = $exe
$sc.WorkingDirectory = $repoRoot
$sc.Description = 'KOHA - native AHK quick action popup, instant'
$sc.Save()
Write-Output "Created $lnk -> $exe"
