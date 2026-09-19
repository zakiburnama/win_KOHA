<#
    One-time setup: registers a Windows Scheduled Task that runs
    sync-prayer-reminders.ps1 every day at 00:05, setting up that day's
    prayer-time reminders (subject to the Waktu Sholat toggles in
    QuickMenu Light's Reminder submenu). Re-run this any time -- e.g.
    after moving this repo -- to re-register with the current script
    path; Register-ScheduledTask -Force overwrites rather than erroring.

    Run once, manually, from a normal (non-elevated) PowerShell prompt --
    a per-user scheduled task doesn't need admin rights.

    00:05 rather than 00:00 -- gives a few minutes' buffer past midnight
    so a still-settling system clock/network at the exact rollover moment
    doesn't fetch prayer times for the wrong day.

    To remove it later: Unregister-ScheduledTask -TaskName 'QuickMenu Light - Sholat Daily Refresh'
#>

$ErrorActionPreference = 'Stop'

$TaskName = 'QuickMenu Light - Sholat Daily Refresh'
$LauncherPath = Join-Path $PSScriptRoot 'run-hidden.vbs'

# wscript.exe + run-hidden.vbs, not powershell.exe directly -- same
# console-window-flash fix as the wallpaper rotation task, see that
# script's install-wallpaper-rotation.ps1 comment and README.md Gotchas.
$action = New-ScheduledTaskAction -Execute 'wscript.exe' `
    -Argument "`"$LauncherPath`" `"sync-prayer-reminders.ps1`""

$trigger = New-ScheduledTaskTrigger -Daily -At '00:05'

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings `
    -Description "Refreshes QuickMenu Light's prayer-time reminders daily. Managed by the ahk/quickmenu repo -- see README.md." `
    -Force | Out-Null

Write-Output "Registered scheduled task '$TaskName' -- runs sync-prayer-reminders.ps1 daily at 00:05."
