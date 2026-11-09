# Engine-side libwif on a Windows runner: can a process running as SYSTEM in
# session 0, like the Twingate service, get the job's OIDC token? Prints results
# only, never a value.
# Usage: windows.ps1 start | check
param([string]$Mode)
$ErrorActionPreference = 'Continue'

$Dir = 'C:\ProgramData\wif-spike'
$End = Join-Path $env:RUNNER_TEMP 'forward_step_end'
$Summary = if ($env:GITHUB_STEP_SUMMARY) { $env:GITHUB_STEP_SUMMARY } else { 'NUL' }
$Pwsh = (Get-Command pwsh).Source
$Svc = 'wif-spike-svc'

function Now { [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() }
function Result($text) { Write-Host "RESULT: $text"; Add-Content -Path $Summary -Value "- $text" }

function Start-SystemTask($name, $source, $log) {
    $action = New-ScheduledTaskAction -Execute $Pwsh -Argument "-NoProfile -NonInteractive -File `"$Dir\service.ps1`" -Source `"$source`" -Log `"$log`""
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 10)
    Register-ScheduledTask -TaskName $name -Action $action -Principal $principal -Settings $settings -Force | Out-Null
    Start-ScheduledTask -TaskName $name
}

function Report($name, $log) {
    $end = [long](Get-Content $End)
    $lines = @(Get-Content $log -ErrorAction SilentlyContinue)
    if (-not $lines) { Result "windows ${name}: no log"; return $false }
    $after = @($lines | Where-Object { [long]($_.Split(' ')[0]) -gt $end })
    $ok = @($after | Where-Object { $_ -match ' ok ' }).Count
    $fail = @($after | Where-Object { $_ -match ' fail' }).Count
    $last = if ($after) { $after[-1].Split(' ', 2)[1] } else { 'none' }
    Result "windows ${name}: $($lines[0].Split(' ', 2)[1])"
    Result "windows ${name}, after the forwarding step ended: $ok ok, $fail fail; last: $last"
    return ($ok -gt 0 -and $fail -eq 0)
}

if ($Mode -eq 'start') {
    Add-Content -Path $Summary -Value '## Windows'
    New-Item -ItemType Directory -Force $Dir | Out-Null
    icacls $Dir /inheritance:r /grant:r 'SYSTEM:(OI)(CI)F' 'Administrators:(OI)(CI)F' | Out-Null
    Copy-Item spike/engine/service.ps1 $Dir

    Result "windows: a step gets a token: $(& $Pwsh -NoProfile -File "$Dir\service.ps1" -Once)"

    Start-SystemTask 'wif-spike-control' '-' "$Dir\control.log"

    # Option A: the CLI forwards the variables over IPC. A file only SYSTEM and Administrators can read stands in for IPC.
    @{ url = $env:ACTIONS_ID_TOKEN_REQUEST_URL; token = $env:ACTIONS_ID_TOKEN_REQUEST_TOKEN } | ConvertTo-Json | Set-Content "$Dir\forward.json"
    Start-SystemTask 'wif-spike' "$Dir\forward.json" "$Dir\service.log"

    # Option C: the action writes the variables into the service's Environment value and starts it.
    # pwsh is not a real service, so the service manager gives up on it after 30 s; the first lines are enough.
    sc.exe create $Svc binPath= "`"$Pwsh`" -NoProfile -NonInteractive -File `"$Dir\service.ps1`" -Source - -Log `"$Dir\optionc.log`"" start= demand | ForEach-Object { "sc create: $_" }
    New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\$Svc" -Name Environment -PropertyType MultiString -Force -Value @(
        "ACTIONS_ID_TOKEN_REQUEST_URL=$env:ACTIONS_ID_TOKEN_REQUEST_URL",
        "ACTIONS_ID_TOKEN_REQUEST_TOKEN=$env:ACTIONS_ID_TOKEN_REQUEST_TOKEN"
    ) | Out-Null
    sc.exe start $Svc | ForEach-Object { "sc start: $_" }
    sc.exe qc $Svc | Select-String BINARY_PATH_NAME | ForEach-Object { "sc qc: $($_.Line.Trim())" }

    Start-Sleep -Seconds 10
    Get-Content "$Dir\control.log", "$Dir\service.log", "$Dir\optionc.log" -ErrorAction SilentlyContinue
    Now | Set-Content $End
    exit 0
}

if ($Mode -eq 'check') {
    Start-Sleep -Seconds 30
    $null = Report 'control (SYSTEM task, nothing forwarded)' "$Dir\control.log"
    $a = Report 'option A (SYSTEM task, session 0)' "$Dir\service.log"
    $lines = @(Get-Content "$Dir\optionc.log" -ErrorAction SilentlyContinue)
    if ($lines) {
        Result "windows option C (service Environment value): $($lines[0].Split(' ', 2)[1]); first probe: $(if ($lines.Count -gt 1) { $lines[1].Split(' ', 2)[1] } else { 'none' })"
    }
    else {
        Result 'windows option C (service Environment value): no log'
    }
    sc.exe delete $Svc | Out-Null
    Unregister-ScheduledTask -TaskName 'wif-spike-control' -Confirm:$false -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName 'wif-spike' -Confirm:$false -ErrorAction SilentlyContinue
    if ($a) { exit 0 } else { exit 1 }
}
