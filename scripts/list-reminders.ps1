<#
    Lists pending one-time reminder tasks (registered by set-reminder.ps1)
    to $PendingRemindersFile, one per line, pipe-delimited: TaskName|Label.

    Called SYNCHRONOUSLY from quickmenu_light.ahk -- via RunWait(..., "Hide"),
    same window-hiding mechanism as every other Run()/RunWait() call in this
    app -- right before showing the Cancel Reminder submenu. Writes to a
    file instead of printing to stdout specifically so AHK can read it via
    RunWait+FileRead: the alternative (WScript.Shell.Exec + StdOut.ReadAll,
    used here originally) has no way to hide the console window at all,
    which is what caused it to steal focus from the QuickMenu popup and
    trigger the dismiss-on-blur close -- see README.md Gotchas.
#>

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib.ps1"

$lines = Get-ScheduledTask | Where-Object { $_.TaskName -like 'QuickMenu Light - Reminder *' } | ForEach-Object {
    $task = $_
    $info = $task | Get-ScheduledTaskInfo
    $minutesMatch = [regex]::Match($task.Actions.Arguments, '-Minutes\s+(\d+)')
    $minutes = if ($minutesMatch.Success) { $minutesMatch.Groups[1].Value } else { '?' }
    $fireTime = $info.NextRunTime.ToString('h:mm tt')
    "$($task.TaskName)|$minutes min -> $fireTime"
}

Set-FileContent -Path $PendingRemindersFile -Content ($lines -join "`n")
