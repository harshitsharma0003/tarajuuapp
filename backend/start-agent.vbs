' Starts the Tarajuu scrape agent hidden (no console window), logging to backend\agent.log.
' Registered to run at logon by: schtasks /Create /SC ONLOGON /TN "Tarajuu Scrape Agent" /TR "wscript.exe \"<path>\start-agent.vbs\""
Set fso = CreateObject("Scripting.FileSystemObject")
dir = fso.GetParentFolderName(WScript.ScriptFullName)
Set sh = CreateObject("WScript.Shell")
sh.CurrentDirectory = dir
sh.Environment("PROCESS")("PYTHONIOENCODING") = "utf-8"
sh.Run "cmd /c "".venv\Scripts\python.exe -m app.agent >> agent.log 2>&1""", 0, False
