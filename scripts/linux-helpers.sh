#!/bin/bash
# Linux helper functions for logging, version detection, and cache validation
# Usage: source ./scripts/linux-helpers.sh

log() {
  local level=$1
  shift
  if [ "$level" = "DEBUG" ] && [ "$DEBUG_MODE" != "true" ]; then
    return
  fi
  echo "[$level] $@" >&2
}

get_twingate_version() {
  local version
  version=$(curl -sf https://packages.twingate.com/apt/Packages | awk '/^Package: twingate$/,/^Version:/ {if (/^Version:/) print $2}' | sort -V | tail -1)

  if [ -z "$version" ]; then
    log DEBUG "Failed to fetch version, proceeding without cache"
    echo "unknown"
  else
    log DEBUG "Latest Twingate version: $version"
    echo "$version"
  fi
}

get_os_version() {
  grep VERSION_ID /etc/os-release | cut -d= -f2 | tr -d '"'
}

validate_cache_linux() {
  local deb_file
  deb_file=$(ls ~/.twingate-cache/twingate*.deb 2>/dev/null | head -1)

  if [ -z "$deb_file" ]; then
    log DEBUG "No .deb file found in cache"
    echo "false"
  elif ! dpkg-deb --info "$deb_file" >/dev/null 2>&1; then
    log DEBUG "Cached .deb is corrupted"
    rm -rf ~/.twingate-cache/*
    echo "false"
  else
    log DEBUG "Cache is valid"
    echo "true"
  fi
}
