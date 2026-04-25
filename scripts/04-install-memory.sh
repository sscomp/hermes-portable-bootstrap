#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/lib.sh"
load_bootstrap_env "${1:-}"

: "${LANCEDB_PRO_HERMES_DIR:?missing LANCEDB_PRO_HERMES_DIR}"
: "${LANCEDB_DB_PATH:?missing LANCEDB_DB_PATH}"
: "${LANCEDB_SCOPE_NAME:?missing LANCEDB_SCOPE_NAME}"
: "${LANCEDB_NODE_BIN:?missing LANCEDB_NODE_BIN}"

if [ ! -d "$LANCEDB_PRO_HERMES_DIR/node_modules" ]; then
  note "Installing Node dependencies for lancedb-pro-hermes"
  npm --prefix "$LANCEDB_PRO_HERMES_DIR" install
fi

note "Installing LanceDB Pro Hermes plugin into $PROFILE_HOME"
"$LANCEDB_PRO_HERMES_DIR/scripts/install-profile.sh" "$PROFILE_NAME" "$PROFILE_HOME"

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
    block = ["memory:", "  provider: lancedb_pro_hermes"]
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
    block.append("  provider: lancedb_pro_hermes")
else:
    block[provider_idx] = "  provider: lancedb_pro_hermes"

updated = lines[:memory_idx] + block + lines[end:]
config_path.write_text("\n".join(updated).rstrip() + "\n", encoding="utf-8")
PY

if [ ! -f "$PROFILE_HOME/.env" ]; then
  cp "$ROOT_DIR/templates/profile.env.example" "$PROFILE_HOME/.env"
  note "Created placeholder profile .env at $PROFILE_HOME/.env"
fi

cat <<EOF
[bootstrap] Update $PROFILE_HOME/.env with real values:
  LANCEDB_PRO_HERMES_DB_PATH=$LANCEDB_DB_PATH
  LANCEDB_PRO_HERMES_NODE_BIN=$LANCEDB_NODE_BIN
  LANCEDB_PRO_HERMES_SCOPE_MAP={"$PROFILE_NAME":"$LANCEDB_SCOPE_NAME"}
  LANCEDB_PRO_HERMES_LANCEDB_MODULE=$LANCEDB_PRO_HERMES_DIR/node_modules/@lancedb/lancedb/dist/index.js
EOF
