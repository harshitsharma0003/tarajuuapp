# Starts the whole Tarajuu stack on this PC:
#   1. Postgres  (data in %LOCALAPPDATA%\Tarajuu\pgdata, port 5433, localhost only)
#   2. API       (uvicorn on 127.0.0.1:8000, SCRAPE_MODE=direct -> this PC fetches amazon.in)
#   3. ngrok     (public HTTPS URL for the phone; domain from NGROK_DOMAIN in backend\.env)
# Safe to run repeatedly: anything already running is left alone.
# Logs: %LOCALAPPDATA%\Tarajuu\*.log
$ErrorActionPreference = 'Continue'
$backend = $PSScriptRoot
$data = Join-Path $env:LOCALAPPDATA 'Tarajuu'
$pgBin = 'C:\Program Files\PostgreSQL\17\bin'

# 1. Postgres
& "$pgBin\pg_isready.exe" -h localhost -p 5433 *> $null
if ($LASTEXITCODE -ne 0) {
    Start-Process -WindowStyle Hidden -FilePath "$pgBin\pg_ctl.exe" `
        -ArgumentList @('-D', "`"$data\pgdata`"", '-l', "`"$data\postgres.log`"", 'start')
    for ($i = 0; $i -lt 30; $i++) {
        Start-Sleep -Seconds 1
        & "$pgBin\pg_isready.exe" -h localhost -p 5433 *> $null
        if ($LASTEXITCODE -eq 0) { break }
    }
}

# 2. API
$apiUp = $false
try { $apiUp = (Invoke-WebRequest -UseBasicParsing -TimeoutSec 3 http://127.0.0.1:8000/api/health).StatusCode -eq 200 } catch {}
if (-not $apiUp) {
    $env:PYTHONIOENCODING = 'utf-8'
    Start-Process -WindowStyle Hidden -WorkingDirectory $backend -FilePath "$backend\.venv\Scripts\python.exe" `
        -ArgumentList @('-m', 'uvicorn', 'app.main:app', '--host', '127.0.0.1', '--port', '8000') `
        -RedirectStandardOutput "$data\api.log" -RedirectStandardError "$data\api.err.log"
}

# 3. ngrok (only if a fixed domain is configured)
$domain = $null
$m = Select-String -Path "$backend\.env" -Pattern '^NGROK_DOMAIN=(.+)$' -ErrorAction SilentlyContinue | Select-Object -First 1
if ($m) { $domain = $m.Matches[0].Groups[1].Value.Trim() }
if ($domain -and -not (Get-Process ngrok -ErrorAction SilentlyContinue)) {
    Start-Process -WindowStyle Hidden -FilePath 'ngrok' `
        -ArgumentList @('http', '8000', "--url=https://$domain", '--log', "`"$data\ngrok.log`"")
}
