#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/lib.sh"
load_bootstrap_env "${1:-}"

: "${NOTEBOOKLM_HERMES_SKILL_DIR:?missing NOTEBOOKLM_HERMES_SKILL_DIR}"

note "Installing NotebookLM Hermes skill into $PROFILE_HOME"
"$NOTEBOOKLM_HERMES_SKILL_DIR/scripts/install-profile.sh" "$PROFILE_HOME"

note "NotebookLM skill installed"
note "Manual step still required: HERMES_HOME=$PROFILE_HOME $PROFILE_HOME/bin/nb login"

