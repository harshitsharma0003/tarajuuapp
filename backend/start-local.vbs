' Runs start-local.ps1 hidden. A copy of this launcher sits in the Windows Startup folder.
Set fso = CreateObject("Scripting.FileSystemObject")
dir = fso.GetParentFolderName(WScript.ScriptFullName)
CreateObject("WScript.Shell").Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -File """ & dir & "\start-local.ps1""", 0, False
