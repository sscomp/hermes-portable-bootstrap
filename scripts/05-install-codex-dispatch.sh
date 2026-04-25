#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/lib.sh"
load_bootstrap_env "${1:-}"

: "${CODEX_DISPATCH_HERMES_PLUGIN_DIR:?missing CODEX_DISPATCH_HERMES_PLUGIN_DIR}"
: "${CODEX_ALLOWED_ROOT:?missing CODEX_ALLOWED_ROOT}"
: "${CODEX_PATH:?missing CODEX_PATH}"

note "Installing Codex dispatch plugin into $PROFILE_HOME"
"$CODEX_DISPATCH_HERMES_PLUGIN_DIR/scripts/install-profile.sh" \
  "$PROFILE_HOME" \
  --allowed-root "$CODEX_ALLOWED_ROOT" \
  --codex-path "$CODEX_PATH"

note "Codex dispatch installed"
note "Manual step still required: restart Hermes gateway before testing /codex-projects"

