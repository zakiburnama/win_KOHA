<#
    Reconciles today's prayer-reminder Scheduled Tasks with current
    settings (koha_settings.ini: SholatEnabled master toggle + 5
    individual SholatSubuh/SholatDzuhur/SholatAshar/SholatMaghrib/
    SholatIsya toggles, all read via Get-IniValue in lib.ps1) and today's
    actual prayer times (myQuran API).

    Idempotent -- always starts by cancelling every "KOHA -
    Sholat * <today>" task, then re-registers one-time tasks only for
    prayers that are (a) master + individually enabled and (b) haven't
    already happened today. Safe to call repeatedly; the AHK side does,
    every time a Waktu Sholat toggle changes.

    Called two ways:
    - Daily at 00:05, via a recurring Scheduled Task (install-prayer-
      schedule.ps1 registers it) -- sets up each new day's reminders.
    - Immediately (hidden, non-blocking) from koha.ahk whenever
      a Waktu Sholat toggle is flipped, so the change takes effect for
      the rest of TODAY, not just starting tomorrow.
#>

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib.ps1"

$today = Get-Date -Format 'yyyy-MM-dd'
$taskPrefix = 'KOHA - Sholat'

# Idempotent re-sync, not additive -- always clear today's tasks first,
# regardless of what gets (re-)registered below.
Get-ScheduledTask | Where-Object { $_.TaskName -like "$taskPrefix * $today" } | ForEach-Object {
    Unregister-ScheduledTask -TaskName $_.TaskName -Confirm:$false -ErrorAction SilentlyContinue
}

$masterEnabled = (Get-IniValue -Key 'SholatEnabled' -Default '0') -eq '1'
if (-not $masterEnabled) {
    Write-Log 'sholat: master toggle off, nothing scheduled'
    exit
}

try {
    $times = Get-PrayerTimesToday
} catch {
    Write-Log "sholat: fetch times FAILED, nothing scheduled today: $_"
    exit
}

$launcherPath = Join-Path $PSScriptRoot 'run-hidden.vbs'
$now = Get-Date
$scheduledCount = 0

foreach ($key in $PrayerDisplayNames.Keys) {
    $name = $PrayerDisplayNames[$key]
    $enabled = (Get-IniValue -Key "Sholat$name" -Default '1') -eq '1'
    if (-not $enabled) {
        continue
    }

    $timeStr = $times[$key]
    if (-not $timeStr) {
        continue
    }

    $fireAt = [datetime]::ParseExact("$today $timeStr", 'yyyy-MM-dd HH:mm', $null)
    if ($fireAt -le $now) {
        continue
    }

    $taskName = "$taskPrefix $name $today"
    $action = New-ScheduledTaskAction -Execute 'wscript.exe' `
        -Argument "`"$launcherPath`" `"show-prayer-reminder.ps1`" -Prayer `"$name`" -Time `"$timeStr`""
    $trigger = New-ScheduledTaskTrigger -Once -At $fireAt
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings `
        -Description "One-shot KOHA prayer reminder ($name, $timeStr)." -Force | Out-Null

    $scheduledCount++
    Write-Log "sholat: scheduled $name at $timeStr"
}

Write-Log "sholat: sync done, $scheduledCount reminder(s) scheduled for today"
