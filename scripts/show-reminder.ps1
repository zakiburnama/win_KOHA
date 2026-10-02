<#
    Fired once, at the scheduled time, by the one-shot Task Scheduler task
    that set-reminder.ps1 registers. Shows the "time's up" notification +
    beep, then unregisters its own task -- nothing left behind after it
    fires; Task Scheduler doesn't clean up one-time tasks on its own.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$TaskName,

    [Parameter(Mandatory)]
    [int]$Minutes
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib.ps1"

try {
    Show-Notification -Title 'KOHA' -Text "Reminder: $Minutes minute(s) is up." -Beep
    Write-Log "reminder: fired ($Minutes min, task '$TaskName')"
} catch {
    Write-Log "reminder fire FAILED: $_"
} finally {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
}
