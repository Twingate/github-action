#!/bin/bash
# Logging utility functions for bash scripts
# Usage: source ./scripts/logging.sh
#        log DEBUG "message"
#        log INFO "message"
#        log ERROR "message"

log() {
  local level=$1
  shift
  if [ "$level" = "DEBUG" ] && [ "$DEBUG_MODE" != "true" ]; then
    return
  fi
  echo "[$level] $@"
}
