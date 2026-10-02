' Launches a sibling .ps1 script via a genuinely hidden process -- no
' console window flash, unlike powershell.exe's own -WindowStyle Hidden
' (which still flashes briefly: Windows creates the console host window as
' part of process startup, before PowerShell gets a chance to hide it).
' wscript.exe is a GUI-subsystem app, so no console window is ever created
' in the first place.
'
' Used only for the two Task Scheduler-triggered scripts (wallpaper
' rotation, reminder firing) -- everything KOHA itself launches
' directly via AHK's Run(..., "Hide") goes straight to powershell.exe.
'
' Usage: wscript.exe run-hidden.vbs <script.ps1> [-Flag value ...]
' Each argument after the script name is re-quoted as its own PowerShell
' argument -- this is what lets a value containing spaces (a reminder's
' task name, e.g.) survive the round trip intact.

Dim fso, shell, scriptDir, target, cmd, i

Set fso = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")

scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
target = scriptDir & "\" & WScript.Arguments(0)

cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File """ & target & """"

For i = 1 To WScript.Arguments.Count - 1
    cmd = cmd & " """ & WScript.Arguments(i) & """"
Next

shell.Run cmd, 0, False
