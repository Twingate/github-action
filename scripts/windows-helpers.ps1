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

    $response = Invoke-WebRequest -Uri $msiUrl -Method Head -UseBasicParsing

    # 5.1 returns HttpWebResponse (ResponseUri); 6+ uses HttpClient (RequestMessage.RequestUri).
    $base = $response.BaseResponse
    $finalUrl = if ($base -is [System.Net.HttpWebResponse]) {
      $base.ResponseUri.AbsoluteUri
    } else {
      $base.RequestMessage.RequestUri.AbsoluteUri
    }

    log DEBUG "Resolved download URL: $finalUrl"

    if ($finalUrl -match 'versions/([\d.]+)/') {
      $version = $matches[1]
      log DEBUG "Latest Twingate version: $version"
      return $version
    } else {
      log WARNING "Could not extract version from download URL, proceeding without cache"
      return "unknown"
    }
  } catch {
    log WARNING "Version detection failed, proceeding without cache: $_"
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
  param([string]$CacheDir, [string]$ExpectedVersion)

  $msiFiles = Get-ChildItem -Path $CacheDir -Filter "twingate*.msi" -ErrorAction SilentlyContinue

  if ($msiFiles.Count -eq 0) {
    log WARNING "Cache was restored but contains no MSI, re-downloading"
    return $false
  }

  $msiFile = $msiFiles[0].FullName
  $installer = $null
  $database = $null
  $view = $null
  $record = $null

  try {
    # OpenDatabase parses the MSI, so a truncated or corrupt file throws here rather
    # than surviving to msiexec. Mode 0 is read-only.
    $installer = New-Object -ComObject WindowsInstaller.Installer
    $database = $installer.GetType().InvokeMember('OpenDatabase', 'InvokeMethod', $null, $installer, @($msiFile, 0))

    # ProductVersion is not usable for this check: MSI caps the major field at 255, so
    # a client version like 2026.239.5147 is stored as 20.26.239.5147. ProductName
    # ("Twingate <version>") carries the upstream version verbatim.
    $view = $database.GetType().InvokeMember('OpenView', 'InvokeMethod', $null, $database,
      @("SELECT Value FROM Property WHERE Property = 'ProductName'"))
    $view.GetType().InvokeMember('Execute', 'InvokeMethod', $null, $view, $null) | Out-Null
    $record = $view.GetType().InvokeMember('Fetch', 'InvokeMethod', $null, $view, $null)

    if ($null -eq $record) {
      log WARNING "Cached MSI has no ProductName property, re-downloading"
      Clear-CacheWindows -CacheDir $CacheDir
      return $false
    }

    $productName = $record.GetType().InvokeMember('StringData', 'GetProperty', $null, $record, @(1))
    log DEBUG "Cached MSI ProductName: $productName"

    if ($ExpectedVersion -and $ExpectedVersion -ne 'unknown' -and
        $productName -notmatch ('\b' + [regex]::Escape($ExpectedVersion) + '\b')) {
      log WARNING "Cached MSI is version-mismatched (wanted $ExpectedVersion), re-downloading"
      Clear-CacheWindows -CacheDir $CacheDir
      return $false
    }

    log DEBUG "Cache is valid"
    return $true
  } catch {
    log WARNING "Cached MSI is corrupted, re-downloading: $_"
    Clear-CacheWindows -CacheDir $CacheDir
    return $false
  } finally {
    # Release the COM handles so nothing holds the MSI open for the copy that follows.
    foreach ($obj in @($record, $view, $database, $installer)) {
      if ($obj) { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($obj) }
    }
  }
}

function Clear-CacheWindows {
  param([string]$CacheDir)

  # Clear the contents but keep the directory, matching validate_cache_linux and
  # leaving the path in place for the download step and the cache save.
  Remove-Item -Path (Join-Path $CacheDir '*') -Recurse -Force -ErrorAction SilentlyContinue
}
