<#
    Enables or disables the "KOHA - Wallpaper Rotation" Scheduled
    Task (the automatic 30-min rotation) to match the toggle picked in
    KOHA's main menu. Only touches that one task -- has no
    effect on wallpaper changes from switching themes (apply-theme.ps1) or
    "Next Wallpaper" (rotate-wallpaper.ps1 called directly), which are
    separate code paths entirely.

    koha.ahk already wrote the new state to koha_settings.ini
    before calling this -- this script's only job is to make the real
    Scheduled Task match that.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet(0, 1)]
    [int]$Enabled
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib.ps1"

$TaskName = 'KOHA - Wallpaper Rotation'

try {
    if ($Enabled) {
        Enable-ScheduledTask -TaskName $TaskName | Out-Null
    } else {
        Disable-ScheduledTask -TaskName $TaskName | Out-Null
    }
    Write-Log "wallpaper slideshow: $(if ($Enabled) { 'enabled' } else { 'disabled' })"
} catch {
    Write-Log "wallpaper slideshow toggle FAILED: $_"
}
