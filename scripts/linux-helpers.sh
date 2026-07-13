#!/bin/bash
# Linux helper functions for logging, version detection, and cache validation
# Usage: source ./scripts/linux-helpers.sh

# Source SUDO detection
source "$(dirname "${BASH_SOURCE[0]}")/sudo-detect.sh"

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

# Verify the runner can actually run a VPN client before we try to start it.
# Twingate needs the TUN device node AND CAP_NET_ADMIN (for ioctl(TUNSETIFF) and
# route setup). Unprivileged container runners (ubuntu-slim, some container jobs)
# have neither, so the daemon starts but never comes online. Fail fast with
# guidance instead of retrying silently for ~75s. Returns non-zero if unusable.
check_network_capabilities() {
  local missing=""

  [ -e /dev/net/tun ] || missing="$missing /dev/net/tun"

  # CAP_NET_ADMIN is capability bit 12. CapBnd is the bounding set: if the cap is
  # absent there, not even root (via sudo) can acquire it. If CapBnd is
  # unreadable we skip this check rather than risk a false failure.
  local cap_bnd
  cap_bnd=$(awk '/^CapBnd:/ {print $2}' /proc/self/status 2>/dev/null)
  if [ -n "$cap_bnd" ] && [ $(( (0x$cap_bnd >> 12) & 1 )) -ne 1 ]; then
    missing="$missing CAP_NET_ADMIN"
  fi

  if [ -n "$missing" ]; then
    log ERROR "Twingate needs a TUN device and CAP_NET_ADMIN, but this runner is missing:$missing"
    log ERROR "This is expected on minimal/unprivileged container runners such as ubuntu-slim."
    log ERROR "For container jobs, grant them via your job's container config:"
    log ERROR "    container:"
    log ERROR "      options: --cap-add NET_ADMIN --device /dev/net/tun"
    log ERROR "See https://www.twingate.com/docs/linux-headless/#working-with-the-linux-client-in-headless-mode"
    return 1
  fi
  return 0
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
