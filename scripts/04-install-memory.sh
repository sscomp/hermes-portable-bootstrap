#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/lib.sh"
load_bootstrap_env "${1:-}"

: "${LANCEDB_PRO_HERMES_PLUGIN_DIR:?missing LANCEDB_PRO_HERMES_PLUGIN_DIR}"
: "${LANCEDB_DB_PATH:?missing LANCEDB_DB_PATH}"
: "${LANCEDB_SCOPE_NAME:?missing LANCEDB_SCOPE_NAME}"
: "${LANCEDB_NODE_BIN:?missing LANCEDB_NODE_BIN}"

if [ ! -d "$LANCEDB_PRO_HERMES_PLUGIN_DIR/node_modules" ]; then
  note "Installing Node dependencies for lancedb-pro-hermes-plugin"
  npm --prefix "$LANCEDB_PRO_HERMES_PLUGIN_DIR" install
fi

note "Installing lancedb-pro-hermes-plugin into $PROFILE_HOME"
"$LANCEDB_PRO_HERMES_PLUGIN_DIR/scripts/install-profile.sh" "$PROFILE_NAME" "$PROFILE_HOME"

python3 - "$PROFILE_HOME/config.yaml" <<'PY'
import sys
from pathlib import Path

config_path = Path(sys.argv[1])
content = config_path.read_text(encoding="utf-8") if config_path.exists() else ""
lines = content.splitlines()

memory_idx = None
for idx, line in enumerate(lines):
    if line.strip() == "memory:" and not line.startswith((" ", "\t")):
        memory_idx = idx
        break

if memory_idx is None:
    block = ["memory:", "  provider: hermes_lancedb"]
    new_content = content.rstrip()
    if new_content:
        new_content += "\n"
    new_content += "\n".join(block) + "\n"
    config_path.write_text(new_content, encoding="utf-8")
    raise SystemExit(0)

end = len(lines)
for idx in range(memory_idx + 1, len(lines)):
    line = lines[idx]
    if line.strip() and not line.startswith((" ", "\t")) and ":" in line:
        end = idx
        break

block = lines[memory_idx:end]
provider_idx = None
for idx, line in enumerate(block):
    if line.strip().startswith("provider:") and line.startswith("  "):
        provider_idx = idx
        break

if provider_idx is None:
    block.append("  provider: hermes_lancedb")
else:
    block[provider_idx] = "  provider: hermes_lancedb"

updated = lines[:memory_idx] + block + lines[end:]
config_path.write_text("\n".join(updated).rstrip() + "\n", encoding="utf-8")
PY

if [ ! -f "$PROFILE_HOME/.env" ]; then
  cp "$ROOT_DIR/templates/profile.env.example" "$PROFILE_HOME/.env"
  note "Created placeholder profile .env at $PROFILE_HOME/.env"
fi

cat <<EOF
[bootstrap] Update $PROFILE_HOME/.env with real values:
  HERMES_LANCEDB_DB_PATH=$LANCEDB_DB_PATH
  HERMES_LANCEDB_NODE_BIN=$LANCEDB_NODE_BIN
  HERMES_LANCEDB_SCOPE_MAP={"$PROFILE_NAME":"$LANCEDB_SCOPE_NAME"}
  HERMES_LANCEDB_LANCEDB_MODULE=$LANCEDB_PRO_HERMES_PLUGIN_DIR/node_modules/@lancedb/lancedb/dist/index.js
EOF
