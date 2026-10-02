<#
    Cancels one pending reminder by its exact Task Scheduler task name.
    Triggered (hidden, non-blocking) from KOHA's Cancel Reminder
    submenu -- the task name comes from list-reminders.ps1's output, shown
    via that submenu, so it's always a real, currently-pending task.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$TaskName
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib.ps1"

try {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Log "reminder: cancelled '$TaskName'"
    Show-Notification -Title 'KOHA' -Text 'Reminder cancelled.'
} catch {
    Write-Log "reminder cancel FAILED: $_"
}
