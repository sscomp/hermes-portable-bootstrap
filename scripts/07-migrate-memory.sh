#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/lib.sh"
load_bootstrap_env "${1:-}"

: "${MEMORY_MIGRATION_MODE:?missing MEMORY_MIGRATION_MODE}"
: "${MEMORY_SOURCE_MAIN_EXPORT:?missing MEMORY_SOURCE_MAIN_EXPORT}"
: "${MEMORY_SOURCE_N2_EXPORT:?missing MEMORY_SOURCE_N2_EXPORT}"
: "${MEMORY_SOURCE_SCOPE:?missing MEMORY_SOURCE_SCOPE}"
: "${MEMORY_TARGET_SCOPE:?missing MEMORY_TARGET_SCOPE}"
: "${MIGRATION_REPORT_DIR:?missing MIGRATION_REPORT_DIR}"
: "${LANCEDB_DB_PATH:?missing LANCEDB_DB_PATH}"
: "${LANCEDB_NODE_BIN:?missing LANCEDB_NODE_BIN}"
: "${LANCEDB_PRO_HERMES_DIR:?missing LANCEDB_PRO_HERMES_DIR}"

case "$MEMORY_MIGRATION_MODE" in
  plan|apply)
    ;;
  *)
    echo "Unsupported MEMORY_MIGRATION_MODE: $MEMORY_MIGRATION_MODE" >&2
    echo "Expected plan or apply" >&2
    exit 2
    ;;
esac

case "$MEMORY_SOURCE_SCOPE" in
  agent:main)
    SOURCE_FILE="$MEMORY_SOURCE_MAIN_EXPORT"
    ;;
  agent:n2)
    SOURCE_FILE="$MEMORY_SOURCE_N2_EXPORT"
    ;;
  *)
    echo "Unsupported MEMORY_SOURCE_SCOPE: $MEMORY_SOURCE_SCOPE" >&2
    echo "Expected agent:main or agent:n2" >&2
    exit 2
    ;;
esac

if [ ! -f "$SOURCE_FILE" ]; then
  echo "Source export not found: $SOURCE_FILE" >&2
  exit 1
fi

mkdir -p "$MIGRATION_REPORT_DIR"
REPORT_PATH="$MIGRATION_REPORT_DIR/memory-migration-${PROFILE_NAME}-$(date +%Y%m%d-%H%M%S).md"

python3 - "$SOURCE_FILE" "$REPORT_PATH" "$PROFILE_NAME" "$MEMORY_SOURCE_SCOPE" "$MEMORY_TARGET_SCOPE" "$MEMORY_MIGRATION_MODE" "$LANCEDB_DB_PATH" "$LANCEDB_NODE_BIN" "$LANCEDB_PRO_HERMES_DIR" "$MEMORY_ALLOW_N2_REMAP" <<'PY'
import json
import os
import shutil
import subprocess
import sys
from collections import Counter
from pathlib import Path

source_file = Path(sys.argv[1])
report_path = Path(sys.argv[2])
profile_name = sys.argv[3]
source_scope = sys.argv[4]
target_scope = sys.argv[5]
mode = sys.argv[6]
lancedb_db_path = Path(sys.argv[7]).expanduser()
node_bin = sys.argv[8]
lancedb_pro_repo = Path(sys.argv[9]).expanduser()
allow_n2_remap = sys.argv[10] == "1"

payload = json.loads(source_file.read_text(encoding="utf-8"))
memories = payload.get("memories", [])

keep_categories = {"decision", "preference", "profile", "architecture", "debug", "fact", "user"}
review_categories = {"entity", "other"}

bridge_path = lancedb_pro_repo / "plugins" / "lancedb_pro_hermes" / "lancedb_bridge.mjs"
module_path = lancedb_pro_repo / "node_modules" / "@lancedb" / "lancedb" / "dist" / "index.js"

if mode == "apply" and source_scope == "agent:n2" and target_scope != "agent:n2" and not allow_n2_remap:
    raise SystemExit("Refusing to import agent:n2 memory into a different target scope without MEMORY_ALLOW_N2_REMAP=1")

if mode == "apply" and not bridge_path.exists():
    raise SystemExit(f"Bridge file not found: {bridge_path}")

if mode == "apply" and not module_path.exists():
    raise SystemExit(f"LanceDB module not found: {module_path}. Run npm install in lancedb-pro-hermes first.")

def bucket(record):
    category = str(record.get("category") or "").strip().lower()
    text = str(record.get("text") or "").strip()
    if len(text) < 12:
      return "drop"
    if category in keep_categories:
      return "keep"
    if category in review_categories or not category:
      return "review"
    return "review"

def normalize_text(text):
    return " ".join(str(text or "").lower().split())

def normalize_category(category):
    value = str(category or "").strip().lower()
    if value == "entities":
        return "entity"
    if value == "preferences":
        return "preference"
    if value == "decisions":
        return "decision"
    return value or "other"

def bridge_env():
    env = os.environ.copy()
    env["LANCEDB_PRO_HERMES_DB_PATH"] = str(lancedb_db_path)
    env["LANCEDB_PRO_HERMES_TABLE_NAME"] = "memories"
    env["LANCEDB_PRO_HERMES_NODE_BIN"] = node_bin
    env["LANCEDB_PRO_HERMES_LANCEDB_MODULE"] = str(module_path)
    return env

def bridge_call(command, args):
    proc = subprocess.run(
        [node_bin, str(bridge_path), command, json.dumps(args, ensure_ascii=False)],
        text=True,
        capture_output=True,
        env=bridge_env(),
        check=False,
    )
    payload = json.loads((proc.stdout or "").strip() or "{}")
    if proc.returncode != 0 or not payload.get("ok"):
        raise RuntimeError(payload.get("error") or proc.stderr or f"bridge call failed: {command}")
    return payload.get("result")

def load_existing_target_records():
    records = []
    offset = 0
    page_size = 100
    while True:
        batch = bridge_call("list", {"scopes": [target_scope], "limit": page_size, "offset": offset}) or []
        if not batch:
            break
        records.extend(batch)
        if len(batch) < page_size:
            break
        offset += page_size
    return records

category_counts = Counter()
bucket_counts = Counter()
scope_counts = Counter()
samples = {"keep": [], "review": [], "drop": []}

for record in memories:
    category = str(record.get("category") or "unknown")
    scope = str(record.get("scope") or "global")
    group = bucket(record)
    category_counts[category] += 1
    scope_counts[scope] += 1
    bucket_counts[group] += 1
    if len(samples[group]) < 5:
        text = str(record.get("text") or "").replace("\n", " ").strip()
        if len(text) > 140:
            text = text[:137] + "..."
        samples[group].append(f"- [{category}] {text}")

existing_records = []
existing_keys = set()
backup_path = None
imported = 0
duplicates = 0
filtered_out = bucket_counts.get("review", 0) + bucket_counts.get("drop", 0)

if mode == "apply":
    existing_records = load_existing_target_records()
    for row in existing_records:
        key = (
            normalize_text(row.get("text")),
            normalize_category(row.get("category")),
            str(row.get("scope") or ""),
        )
        existing_keys.add(key)

    if lancedb_db_path.exists():
        backup_path = report_path.parent / f"lancedb-backup-{report_path.stem}"
        if backup_path.exists():
            shutil.rmtree(backup_path)
        shutil.copytree(lancedb_db_path, backup_path)

    imported_keys = set()
    for record in memories:
        if bucket(record) != "keep":
            continue
        category = normalize_category(record.get("category"))
        key = (normalize_text(record.get("text")), category, target_scope)
        if key in existing_keys or key in imported_keys:
            duplicates += 1
            continue
        bridge_call(
            "add",
            {
                "content": str(record.get("text") or "").strip(),
                "category": category,
                "importance": float(record.get("importance") or 0.7),
                "scope": target_scope,
                "source": "migration-openclaw-export",
                "sessionId": f"migration:{source_scope}",
            },
        )
        imported += 1
        imported_keys.add(key)

lines = []
lines.append("# Memory Migration Report")
lines.append("")
lines.append(f"- Source file: `{source_file}`")
lines.append(f"- Profile name: `{profile_name}`")
lines.append(f"- Mode: `{mode}`")
lines.append(f"- Source scope: `{source_scope}`")
lines.append(f"- Proposed target scope: `{target_scope}`")
lines.append(f"- Export version: `{payload.get('version', 'unknown')}`")
lines.append(f"- Exported at: `{payload.get('exportedAt', 'unknown')}`")
lines.append(f"- Total records: `{len(memories)}`")
if backup_path is not None:
    lines.append(f"- Backup path: `{backup_path}`")
lines.append("")
lines.append("## Bucket summary")
lines.append("")
for name in ("keep", "review", "drop"):
    lines.append(f"- {name}: `{bucket_counts.get(name, 0)}`")
lines.append("")
lines.append("## Category counts")
lines.append("")
for category, count in sorted(category_counts.items(), key=lambda kv: (-kv[1], kv[0])):
    lines.append(f"- `{category}`: `{count}`")
lines.append("")
lines.append("## Scope counts")
lines.append("")
for scope, count in sorted(scope_counts.items(), key=lambda kv: (-kv[1], kv[0])):
    lines.append(f"- `{scope}`: `{count}`")
lines.append("")
lines.append("## Sample keep candidates")
lines.append("")
lines.extend(samples["keep"] or ["- none"])
lines.append("")
lines.append("## Sample review candidates")
lines.append("")
lines.extend(samples["review"] or ["- none"])
lines.append("")
lines.append("## Sample drop candidates")
lines.append("")
lines.extend(samples["drop"] or ["- none"])
lines.append("")
lines.append("## Interpretation")
lines.append("")
if mode == "plan":
    lines.append("- This report is a planning artifact.")
    lines.append("- No records were imported into the target LanceDB table.")
else:
    lines.append("- This report reflects a conservative apply run.")
    lines.append(f"- Imported keep records: `{imported}`")
    lines.append(f"- Skipped as duplicates: `{duplicates}`")
    lines.append(f"- Left for review/drop buckets: `{filtered_out}`")
    lines.append("- Only `keep` bucket records were imported.")
    lines.append("- `review` bucket records still need explicit review before any later import step.")
if source_scope == "agent:n2" and target_scope != "agent:n2":
    lines.append("- Warning: source scope is `agent:n2` but target scope differs. Explicit human approval is required.")

report_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
print(report_path)
PY

note "Memory migration planning report written to $REPORT_PATH"
cat "$REPORT_PATH"
