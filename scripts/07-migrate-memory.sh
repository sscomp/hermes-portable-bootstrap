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

python3 - "$SOURCE_FILE" "$REPORT_PATH" "$PROFILE_NAME" "$MEMORY_SOURCE_SCOPE" "$MEMORY_TARGET_SCOPE" "$MEMORY_MIGRATION_MODE" <<'PY'
import json
import sys
from collections import Counter
from pathlib import Path

source_file = Path(sys.argv[1])
report_path = Path(sys.argv[2])
profile_name = sys.argv[3]
source_scope = sys.argv[4]
target_scope = sys.argv[5]
mode = sys.argv[6]

payload = json.loads(source_file.read_text(encoding="utf-8"))
memories = payload.get("memories", [])

keep_categories = {"decision", "preference", "profile", "architecture", "debug", "fact", "user"}
review_categories = {"entity", "other"}

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
lines.append("- This report is a planning artifact.")
lines.append("- No records were imported into the target LanceDB table.")
lines.append("- Review `review` records before designing the real import step.")
if source_scope == "agent:n2" and target_scope != "agent:n2":
    lines.append("- Warning: source scope is `agent:n2` but target scope differs. Explicit human approval is required.")

report_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
print(report_path)
PY

note "Memory migration planning report written to $REPORT_PATH"
cat "$REPORT_PATH"
