#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/lib.sh"
load_bootstrap_env "${1:-}"

if [ -d "$PROFILE_HOME" ]; then
  note "Profile already exists: $PROFILE_HOME"
else
  note "Creating Hermes profile: $PROFILE_NAME"
  "$HERMES_BIN" profile create "$PROFILE_NAME"
fi

if [ ! -d "$PROFILE_HOME" ]; then
  echo "Profile creation failed: $PROFILE_HOME does not exist" >&2
  exit 1
fi

note "Profile ready: $PROFILE_HOME"

