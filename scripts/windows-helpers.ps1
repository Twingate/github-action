# Windows helper functions for logging, version detection, and cache validation
# Usage: . ./scripts/windows-helpers.ps1

function log {
  param([string]$Level, [string]$Message)
  if ($Level -eq 'DEBUG' -and $env:DEBUG_MODE -ne 'true') {
    return
  }
  Write-Host "[$Level] $Message"
}

function Get-TwingateVersion {
  try {
    $msiUrl = "https://api.twingate.com/download/windows?installer=msi"
    log DEBUG "Fetching from $msiUrl"

    # The download URL redirects twice (api.twingate.com -> api.<region>.twingate.com
    # -> binaries.twingate.com/.../versions/<x.y.z>/...), and only the last hop carries
    # the version. HEAD follows the whole chain without pulling down the 30MB body.
    $ProgressPreference = 'SilentlyContinue'
    $response = Invoke-WebRequest -Uri $msiUrl -Method Head -UseBasicParsing

    # Windows PowerShell 5.1 exposes the resolved URI as BaseResponse.ResponseUri;
    # PowerShell 6+ swaps in HttpClient, where it is RequestMessage.RequestUri.
    $finalUrl = if ($response.BaseResponse.ResponseUri) {
      $response.BaseResponse.ResponseUri.AbsoluteUri
    } else {
      $response.BaseResponse.RequestMessage.RequestUri.AbsoluteUri
    }

    log DEBUG "Resolved download URL: $finalUrl"

    if ($finalUrl -match 'versions/([\d.]+)/') {
      $version = $matches[1]
      log DEBUG "Latest Twingate version: $version"
      return $version
    } else {
      log DEBUG "Could not extract version from URL"
      return "unknown"
    }
  } catch {
    log DEBUG "Error: $_"
    return "unknown"
  }
}

function Get-OSVersion {
  try {
    $osVersion = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").CurrentBuildNumber
    log DEBUG "Windows build number: $osVersion"
    return $osVersion
  } catch {
    log DEBUG "Failed to read Windows build number from registry: $_"
    return "unknown"
  }
}

function Validate-CacheWindows {
  param([string]$CacheDir)

  $msiFiles = Get-ChildItem -Path $CacheDir -Filter "twingate*.msi" -ErrorAction SilentlyContinue

  if ($msiFiles.Count -eq 0) {
    log DEBUG "No MSI file found in cache"
    return $false
  }

  try {
    $msiFile = $msiFiles[0].FullName

    # Try to get MSI properties - this validates the MSI file
    $msiInfo = Get-ItemProperty -Path $msiFile
    if (-not $msiInfo) {
      log DEBUG "Cached MSI is corrupted"
      Remove-Item -Path $CacheDir -Recurse -Force -ErrorAction SilentlyContinue
      return $false
    } else {
      log DEBUG "Cache is valid"
      return $true
    }
  } catch {
    log DEBUG "Cached MSI is corrupted: $_"
    Remove-Item -Path $CacheDir -Recurse -Force -ErrorAction SilentlyContinue
    return $false
  }
}
