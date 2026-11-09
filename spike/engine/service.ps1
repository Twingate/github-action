# Stands in for the engine in the Windows service. Reads the variables the CLI
# would forward over engine IPC from a file only SYSTEM and Administrators can
# read, deletes the file, then asks for a token every 5 s for 5 minutes.
# With -Source - it uses its own environment. With -Once it prints one result.
# Never prints a token.
param([string]$Source = '-', [string]$Log, [switch]$Once)
$ErrorActionPreference = 'Continue'

function Now { [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() }

function Probe($url, $token) {
    if (-not $url -or -not $token) { return 'fail variables missing' }
    try {
        $r = Invoke-RestMethod -Uri "$url&audience=https%3A%2F%2Fwif-spike.twingate.invalid" -TimeoutSec 10 -Headers @{
            Authorization = "Bearer $token"
            Accept        = 'application/json; api-version=2.0'
        }
        $p = $r.value.Split('.')[1].Replace('-', '+').Replace('_', '/')
        $p += '=' * ((4 - $p.Length % 4) % 4)
        $d = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($p)) | ConvertFrom-Json
        "ok aud=$($d.aud) lifetime=$($d.exp - $d.iat)s"
    }
    catch {
        $code = $_.Exception.Response.StatusCode.value__
        if ($code) { "fail http=$code" } else { "fail $($_.Exception.GetType().Name)" }
    }
}

$own = if ($env:ACTIONS_ID_TOKEN_REQUEST_TOKEN) { 'yes' } else { 'no' }
$url = $env:ACTIONS_ID_TOKEN_REQUEST_URL
$token = $env:ACTIONS_ID_TOKEN_REQUEST_TOKEN
$forwarded = 'no'
if ($Source -ne '-' -and (Test-Path $Source)) {
    $f = Get-Content -Raw $Source | ConvertFrom-Json
    $url = $f.url
    $token = $f.token
    Remove-Item -Force $Source
    $forwarded = 'yes'
}

if ($Once) {
    Probe $url $token
    exit 0
}

$left = if ($Source -ne '-' -and (Test-Path $Source)) { 'yes' } else { 'no' }
"$(Now) context user=$(whoami) session=$((Get-Process -Id $PID).SessionId) variables-in-own-environment=$own forwarded=$forwarded file-left-on-disk=$left" | Add-Content $Log
for ($i = 0; $i -lt 60; $i++) {
    "$(Now) $(Probe $url $token)" | Add-Content $Log
    Start-Sleep -Seconds 5
}
