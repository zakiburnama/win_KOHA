<#
    One-time setup: registers a Windows Scheduled Task that runs
    rotate-wallpaper.ps1 every 30 minutes (via run-hidden.vbs, so no
    console window flash -- see that file), advancing the desktop
    wallpaper through whichever global theme (catppuccin-mocha/gruvbox) is
    currently active. Re-run this any time -- e.g. after moving this repo
    -- to re-register with the current script path; Register-ScheduledTask
    -Force overwrites the existing task rather than erroring.

    Run once, manually, from a normal (non-elevated) PowerShell prompt --
    a per-user scheduled task doesn't need admin rights. The task runs as
    the current user (not SYSTEM), which is required: SYSTEM runs in
    session 0 and can't change the interactive desktop's wallpaper.

    To remove it later: Unregister-ScheduledTask -TaskName 'KOHA - Wallpaper Rotation'
#>

$ErrorActionPreference = 'Stop'

$TaskName = 'KOHA - Wallpaper Rotation'
$LauncherPath = Join-Path $PSScriptRoot 'run-hidden.vbs'

# wscript.exe + run-hidden.vbs, not powershell.exe directly -- see that
# file's header comment. powershell.exe's own -WindowStyle Hidden still
# flashes a console window briefly when Task Scheduler launches it; wscript
# (a GUI-subsystem app) never creates one in the first place.
$action = New-ScheduledTaskAction -Execute 'wscript.exe' `
    -Argument "`"$LauncherPath`" `"rotate-wallpaper.ps1`""

# -Once + a repetition interval is the standard idiom for "run every N
# minutes, indefinitely" -- there's no direct -Minutes option on -Daily/etc.
# RepetitionDuration uses ~10 years rather than [TimeSpan]::MaxValue, which
# the underlying Task Scheduler COM API rejects on some Windows versions.
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) `
    -RepetitionInterval (New-TimeSpan -Minutes 30) `
    -RepetitionDuration (New-TimeSpan -Days 3650)

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings `
    -Description "Rotates KOHA's global-theme desktop wallpaper. Managed by the KOHA repo -- see README.md." `
    -Force | Out-Null

Write-Output "Registered scheduled task '$TaskName' -- runs rotate-wallpaper.ps1 every 30 min."
