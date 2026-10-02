<#
    Fired once, at prayer time, by the one-time Task Scheduler task
    sync-prayer-reminders.ps1 registers for it. Shows the notification +
    beep, then unregisters its own task -- same pattern as
    show-reminder.ps1, nothing left behind after it fires.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Prayer,

    [Parameter(Mandatory)]
    [string]$Time
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib.ps1"

$taskName = "KOHA - Sholat $Prayer $(Get-Date -Format 'yyyy-MM-dd')"

try {
    Show-Notification -Title 'Waktu Sholat' -Text "Waktu $Prayer telah masuk ($Time) -- $PrayerCityName" -Beep
    Write-Log "sholat: fired $Prayer ($Time)"
} catch {
    Write-Log "sholat fire FAILED: $_"
} finally {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
}
