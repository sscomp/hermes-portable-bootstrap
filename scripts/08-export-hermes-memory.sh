#!/usr/bin/env bash
set -euo pipefail

if [ "${1:-}" = "" ] || [ "${2:-}" = "" ]; then
  echo "Usage: scripts/08-export-hermes-memory.sh <profile-home> <plugin-repo-dir> [output-file]" >&2
  exit 2
fi

PROFILE_HOME="$1"
PLUGIN_REPO_DIR="$2"
OUTPUT_FILE="${3:-$PROFILE_HOME/hermes-memory-export.json}"
PROFILE_ENV="$PROFILE_HOME/.env"
PROFILE_NAME="$(basename "$PROFILE_HOME")"

if [ ! -d "$PROFILE_HOME" ]; then
  echo "Profile home not found: $PROFILE_HOME" >&2
  exit 1
fi

if [ ! -f "$PROFILE_ENV" ]; then
  echo "Profile .env not found: $PROFILE_ENV" >&2
  exit 1
fi

if [ ! -d "$PLUGIN_REPO_DIR" ]; then
  echo "Plugin repo dir not found: $PLUGIN_REPO_DIR" >&2
  exit 1
fi

python3 - "$PROFILE_HOME" "$PLUGIN_REPO_DIR" "$OUTPUT_FILE" "$PROFILE_ENV" "$PROFILE_NAME" <<'PY'
import json
import os
import shlex
import subprocess
import sys
from pathlib import Path

profile_home = Path(sys.argv[1]).expanduser()
plugin_repo_dir = Path(sys.argv[2]).expanduser()
output_file = Path(sys.argv[3]).expanduser()
profile_env = Path(sys.argv[4]).expanduser()
profile_name = sys.argv[5]

bridge_path = plugin_repo_dir / "plugins" / "hermes_lancedb" / "lancedb_bridge.mjs"
if not bridge_path.exists():
    raise SystemExit(f"Bridge file not found: {bridge_path}")

def load_env(path: Path):
    result = {}
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        value = value.strip()
        try:
            value = shlex.split(value)[0] if value else ""
        except Exception:
            value = value.strip("\"'")
        result[key.strip()] = value
    return result

env_file = load_env(profile_env)
node_bin = env_file.get("HERMES_LANCEDB_NODE_BIN", "/opt/homebrew/bin/node")
db_path = env_file.get("HERMES_LANCEDB_DB_PATH", "")
module_path = env_file.get("HERMES_LANCEDB_LANCEDB_MODULE", "")
table_name = env_file.get("HERMES_LANCEDB_TABLE_NAME", "memories")
global_scope = env_file.get("HERMES_LANCEDB_GLOBAL_SCOPE", "global") or "global"
scope_map_raw = env_file.get("HERMES_LANCEDB_SCOPE_MAP", "")

if not db_path:
    raise SystemExit("HERMES_LANCEDB_DB_PATH is missing in source profile .env")
if not module_path:
    raise SystemExit("HERMES_LANCEDB_LANCEDB_MODULE is missing in source profile .env")

source_scope = f"agent:{profile_name}"
if scope_map_raw:
    try:
        scope_map = json.loads(scope_map_raw)
        if isinstance(scope_map, dict):
            source_scope = str(scope_map.get(profile_name) or scope_map.get("default") or source_scope)
    except Exception:
        pass

bridge_env = os.environ.copy()
bridge_env["HERMES_LANCEDB_DB_PATH"] = db_path
bridge_env["HERMES_LANCEDB_TABLE_NAME"] = table_name
bridge_env["HERMES_LANCEDB_NODE_BIN"] = node_bin
bridge_env["HERMES_LANCEDB_LANCEDB_MODULE"] = module_path
bridge_env["HERMES_LANCEDB_EMBEDDING_BASE_URL"] = env_file.get("HERMES_LANCEDB_EMBEDDING_BASE_URL", "http://127.0.0.1:11434/v1")
bridge_env["HERMES_LANCEDB_EMBEDDING_MODEL"] = env_file.get("HERMES_LANCEDB_EMBEDDING_MODEL", "mxbai-embed-large:latest")
bridge_env["HERMES_LANCEDB_EMBEDDING_API_KEY"] = env_file.get("HERMES_LANCEDB_EMBEDDING_API_KEY", "ollama-local")
bridge_env["HERMES_LANCEDB_DECAY_HALF_LIFE_DAYS"] = env_file.get("HERMES_LANCEDB_DECAY_HALF_LIFE_DAYS", "180")

def bridge_call(command, args):
    proc = subprocess.run(
        [node_bin, str(bridge_path), command, json.dumps(args, ensure_ascii=False)],
        text=True,
        capture_output=True,
        env=bridge_env,
        check=False,
    )
    payload = json.loads((proc.stdout or "").strip() or "{}")
    if proc.returncode != 0 or not payload.get("ok"):
        raise RuntimeError(payload.get("error") or proc.stderr or f"bridge call failed: {command}")
    return payload.get("result")

records = []
offset = 0
page_size = 100
scopes = [global_scope, source_scope]
while True:
    batch = bridge_call("list", {"scopes": scopes, "limit": page_size, "offset": offset}) or []
    if not batch:
        break
    records.extend(batch)
    if len(batch) < page_size:
        break
    offset += page_size

payload = {
    "version": "1.0",
    "exportedAt": __import__("datetime").datetime.utcnow().isoformat(timespec="milliseconds") + "Z",
    "count": len(records),
    "filters": {
        "profileName": profile_name,
        "scopes": scopes,
        "source": "lancedb-pro-hermes-plugin",
    },
    "memories": records,
}

output_file.parent.mkdir(parents=True, exist_ok=True)
output_file.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(output_file)
PY

printf '[hermes-export] Exported Hermes memory to %s\n' "$OUTPUT_FILE"
