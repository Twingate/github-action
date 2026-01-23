# Logging utility functions for PowerShell scripts
# Usage: . ./scripts/logging.ps1
#        log DEBUG "message"
#        log INFO "message"
#        log ERROR "message"

function log {
  param([string]$Level, [string]$Message)
  if ($Level -eq 'DEBUG' -and $env:DEBUG_MODE -ne 'true') {
    return
  }
  Write-Host "[$Level] $Message"
}
