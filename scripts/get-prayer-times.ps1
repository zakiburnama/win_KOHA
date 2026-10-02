<#
    Fetches today's prayer times and writes them to $PrayerTimesFile,
    pipe-delimited: key|DisplayName|HH:mm -- one line per prayer.

    Called SYNCHRONOUSLY from koha.ahk (RunWait(..., "Hide"),
    same pattern as list-reminders.ps1/GetPendingReminders()) right before
    showing the Waktu Sholat submenu, purely for DISPLAY -- the actual
    scheduling of reminder notifications is sync-prayer-reminders.ps1's
    job, not this script's.

    On fetch failure (offline, API down), writes an empty file rather than
    throwing -- the submenu then just shows prayer names without times
    instead of failing to open at all.
#>

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib.ps1"

try {
    $times = Get-PrayerTimesToday
    $lines = foreach ($key in $PrayerDisplayNames.Keys) {
        "$key|$($PrayerDisplayNames[$key])|$($times[$key])"
    }
    Set-FileContent -Path $PrayerTimesFile -Content ($lines -join "`n")
} catch {
    Write-Log "prayer times fetch FAILED: $_"
    Set-FileContent -Path $PrayerTimesFile -Content ''
}
