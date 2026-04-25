#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/lib.sh"
load_bootstrap_env "${1:-}"

require_path() {
  local path="$1"
  if [ ! -e "$path" ]; then
    echo "Missing expected path: $path" >&2
    exit 1
  fi
  note "OK: $path"
}

require_grep() {
  local pattern="$1"
  local file="$2"
  if ! rg -n "$pattern" "$file" >/dev/null 2>&1; then
    echo "Missing expected pattern '$pattern' in $file" >&2
    exit 1
  fi
  note "OK pattern '$pattern' in $file"
}

require_path "$PROFILE_HOME/bin/nb"
require_path "$PROFILE_HOME/skills/research/notebooklm"
require_path "$PROFILE_HOME/plugins/lancedb_pro_hermes"
require_path "$PROFILE_HOME/plugins/codex-dispatch"
require_path "$PROFILE_HOME/codex-dispatch/config.json"
require_path "$PROFILE_HOME/codex-dispatch/codex-projects.json"
require_path "$PROFILE_HOME/config.yaml"

require_grep "provider: lancedb_pro_hermes" "$PROFILE_HOME/config.yaml"
require_grep "codex-dispatch" "$PROFILE_HOME/config.yaml"
require_grep "nb-list:" "$PROFILE_HOME/config.yaml"

cat <<EOF

Smoke test completed.

Remaining manual validations:
1. Fill $PROFILE_HOME/.env with real secrets and LanceDB values.
2. Run: HERMES_HOME=$PROFILE_HOME $PROFILE_HOME/bin/nb login
3. Restart gateway: $HERMES_BIN --profile $PROFILE_NAME gateway restart
4. Test in messaging platform:
   - /nb-list
   - /nb-login
   - /codex-projects
5. Optional CLI check:
   - $HERMES_BIN --profile $PROFILE_NAME memory status

EOF
