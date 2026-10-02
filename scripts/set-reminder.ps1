<#
    Schedules a one-shot reminder N minutes from now. Triggered by picking a
    duration from KOHA's Reminder submenu.

    Registers a ONE-TIME Task Scheduler task (self-deleting once it fires,
    see show-reminder.ps1) rather than a script that Start-Sleep's for the
    duration -- same reasoning as the wallpaper rotation task
    (rotate-wallpaper.ps1): nothing of ours sits idle in memory while the
    timer is "waiting", Task Scheduler does that part.

    Each reminder gets a unique task name (timestamp suffix) so multiple
    overlapping reminders don't collide/overwrite each other.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet(5, 10, 15, 30, 60)]
    [int]$Minutes
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib.ps1"

$fireAt = (Get-Date).AddMinutes($Minutes)
$taskName = "KOHA - Reminder $(Get-Date -Format 'yyyyMMddHHmmssfff')"
$launcherPath = Join-Path $PSScriptRoot 'run-hidden.vbs'

try {
    # wscript.exe + run-hidden.vbs, not powershell.exe directly -- avoids
    # the console-window flash Task-Scheduler-launched powershell.exe
    # processes get even with -WindowStyle Hidden. See that file's header.
    $action = New-ScheduledTaskAction -Execute 'wscript.exe' `
        -Argument "`"$launcherPath`" `"show-reminder.ps1`" -TaskName `"$taskName`" -Minutes $Minutes"

    $trigger = New-ScheduledTaskTrigger -Once -At $fireAt

    $settings = New-ScheduledTaskSettingsSet `
        -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings `
        -Description "One-shot KOHA reminder ($Minutes min), fires at $fireAt then deletes itself." `
        -Force | Out-Null

    Write-Log "reminder: scheduled '$taskName' for $fireAt ($Minutes min)"

    Show-Notification -Title 'KOHA' `
        -Text "Reminder set for $($fireAt.ToString('h:mm tt')) ($Minutes min)"
} catch {
    Write-Log "reminder scheduling FAILED: $_"
}
