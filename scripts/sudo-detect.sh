#!/bin/bash
# Detects and sets SUDO variable for privilege escalation
# Usage: source sudo-detect.sh

if [ "$(id -u)" -eq 0 ]; then
  SUDO=""
else
  if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
  else
    echo "[ERROR] sudo is not available. Please run this script as root." >&2
    exit 1
  fi
fi

export SUDO
