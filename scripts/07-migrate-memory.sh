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
: "${MEMORY_REVIEW_DIR:?missing MEMORY_REVIEW_DIR}"
: "${MEMORY_REVIEW_DECISIONS_FILE:?missing MEMORY_REVIEW_DECISIONS_FILE}"
: "${LANCEDB_DB_PATH:?missing LANCEDB_DB_PATH}"
: "${LANCEDB_NODE_BIN:?missing LANCEDB_NODE_BIN}"
: "${LANCEDB_PRO_HERMES_DIR:?missing LANCEDB_PRO_HERMES_DIR}"

case "$MEMORY_MIGRATION_MODE" in
  plan|apply|apply-reviewed)
    ;;
  *)
    echo "Unsupported MEMORY_MIGRATION_MODE: $MEMORY_MIGRATION_MODE" >&2
    echo "Expected plan, apply, or apply-reviewed" >&2
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

mkdir -p "$MIGRATION_REPORT_DIR" "$MEMORY_REVIEW_DIR"
STAMP="$(date +%Y%m%d-%H%M%S)"
REPORT_PATH="$MIGRATION_REPORT_DIR/memory-migration-${PROFILE_NAME}-${STAMP}.md"
REVIEW_CANDIDATES_PATH="$MEMORY_REVIEW_DIR/review-candidates-${PROFILE_NAME}-${STAMP}.json"
REVIEW_TEMPLATE_PATH="$MEMORY_REVIEW_DIR/review-decisions-template-${PROFILE_NAME}-${STAMP}.json"
LATEST_REVIEW_CANDIDATES_PATH="$MEMORY_REVIEW_DIR/review-candidates-latest.json"
LATEST_REVIEW_TEMPLATE_PATH="$MEMORY_REVIEW_DIR/review-decisions-template-latest.json"

python3 - "$SOURCE_FILE" "$REPORT_PATH" "$PROFILE_NAME" "$MEMORY_SOURCE_SCOPE" "$MEMORY_TARGET_SCOPE" "$MEMORY_MIGRATION_MODE" "$LANCEDB_DB_PATH" "$LANCEDB_NODE_BIN" "$LANCEDB_PRO_HERMES_DIR" "$MEMORY_ALLOW_N2_REMAP" "$REVIEW_CANDIDATES_PATH" "$REVIEW_TEMPLATE_PATH" "$MEMORY_REVIEW_DECISIONS_FILE" <<'PY'
import json
import os
import shutil
import subprocess
import sys
from collections import Counter, defaultdict
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
review_candidates_path = Path(sys.argv[11])
review_template_path = Path(sys.argv[12])
review_decisions_path = Path(sys.argv[13]).expanduser()

payload = json.loads(source_file.read_text(encoding="utf-8"))
memories = payload.get("memories", [])

keep_categories = {"decision", "preference", "profile", "architecture", "debug", "fact", "user"}
review_categories = {"entity", "other"}
duplicate_time_window_ms = 7 * 24 * 60 * 60 * 1000

bridge_path = lancedb_pro_repo / "plugins" / "lancedb_pro_hermes" / "lancedb_bridge.mjs"
module_path = lancedb_pro_repo / "node_modules" / "@lancedb" / "lancedb" / "dist" / "index.js"

if mode in {"apply", "apply-reviewed"} and source_scope == "agent:n2" and target_scope != "agent:n2" and not allow_n2_remap:
    raise SystemExit("Refusing to import agent:n2 memory into a different target scope without MEMORY_ALLOW_N2_REMAP=1")

if mode in {"apply", "apply-reviewed"} and not bridge_path.exists():
    raise SystemExit(f"Bridge file not found: {bridge_path}")

if mode in {"apply", "apply-reviewed"} and not module_path.exists():
    raise SystemExit(f"LanceDB module not found: {module_path}. Run npm install in lancedb-pro-hermes first.")

if mode == "apply-reviewed" and not review_decisions_path.exists():
    raise SystemExit(f"Review decisions file not found: {review_decisions_path}")

def parse_metadata(value):
    if isinstance(value, dict):
        return value
    if isinstance(value, str) and value.strip():
        try:
            parsed = json.loads(value)
            return parsed if isinstance(parsed, dict) else {}
        except Exception:
            return {}
    return {}

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

def normalize_timestamp(value):
    parsed = int(float(value or 0))
    return parsed if parsed > 0 else 0

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

def summarize_text(text, limit=140):
    value = str(text or "").replace("\n", " ").strip()
    if len(value) > limit:
        return value[: limit - 3] + "..."
    return value

def target_scope_for(record):
    scope = str(record.get("scope") or "").strip()
    if scope in {"", "global"}:
        return "global"
    if scope == source_scope:
        return target_scope
    return scope

def migration_metadata(record, group):
    original_metadata = parse_metadata(record.get("metadata"))
    return {
        **original_metadata,
        "migration_bucket": group,
        "migration_profile": profile_name,
        "migration_source_file": str(source_file),
        "migration_source_scope": source_scope,
        "migration_target_scope": target_scope_for(record),
        "migration_exported_at": payload.get("exportedAt", ""),
        "migration_original_id": str(record.get("id") or ""),
        "migration_original_scope": str(record.get("scope") or ""),
        "migration_original_category": str(record.get("category") or ""),
        "migration_original_timestamp": normalize_timestamp(record.get("timestamp")),
    }

def import_payload(record, group):
    text = str(record.get("text") or "").strip()
    importance = float(record.get("importance") or 0.7)
    timestamp = normalize_timestamp(record.get("timestamp"))
    category = normalize_category(record.get("category"))
    metadata = migration_metadata(record, group)
    return {
        "id": f"migration:{source_scope}:{record.get('id')}",
        "content": text,
        "category": category,
        "importance": importance,
        "scope": target_scope_for(record),
        "timestamp": timestamp,
        "validFrom": metadata.get("valid_from") or timestamp,
        "source": "migration-openclaw-export",
        "sessionId": f"migration:{source_scope}",
        "metadata": metadata,
    }

def review_candidate(record):
    group = bucket(record)
    metadata = parse_metadata(record.get("metadata"))
    return {
        "id": str(record.get("id") or ""),
        "bucket": group,
        "category": normalize_category(record.get("category")),
        "sourceScope": str(record.get("scope") or source_scope or "global"),
        "targetScope": target_scope_for(record),
        "importance": float(record.get("importance") or 0.7),
        "timestamp": normalize_timestamp(record.get("timestamp")),
        "text": str(record.get("text") or "").strip(),
        "summary": summarize_text(record.get("text")),
        "metadata": metadata,
        "suggestedDecision": "review",
    }

def load_review_approvals():
    payload = json.loads(review_decisions_path.read_text(encoding="utf-8"))
    if payload.get("sourceFile") and payload.get("sourceFile") != str(source_file):
        raise SystemExit("Review decisions sourceFile does not match current source export")
    if payload.get("sourceScope") and payload.get("sourceScope") != source_scope:
        raise SystemExit("Review decisions sourceScope does not match current run")
    approved = {}
    decisions = payload.get("decisions") or []
    for item in decisions:
        if str(item.get("decision") or "").strip().lower() != "approve":
            continue
        approved[str(item.get("id") or "")] = item
    return approved, payload

existing_records = []
existing_by_source_id = {}
existing_by_text = defaultdict(list)
backup_path = None
imported = 0
duplicates = 0
review_imported = 0
review_duplicates = 0
approved_review_count = 0

category_counts = Counter()
bucket_counts = Counter()
scope_counts = Counter()
samples = {"keep": [], "review": [], "drop": []}
review_candidates = []
records_by_id = {}

for record in memories:
    record_id = str(record.get("id") or "")
    records_by_id[record_id] = record
    category = str(record.get("category") or "unknown")
    scope = str(record.get("scope") or "global")
    group = bucket(record)
    category_counts[category] += 1
    scope_counts[scope] += 1
    bucket_counts[group] += 1
    if len(samples[group]) < 5:
        samples[group].append(f"- [{category}] {summarize_text(record.get('text'))}")
    if group == "review":
        review_candidates.append(review_candidate(record))

review_manifest = {
    "sourceFile": str(source_file),
    "sourceScope": source_scope,
    "targetScope": target_scope,
    "profileName": profile_name,
    "exportedAt": payload.get("exportedAt", ""),
    "generatedAt": report_path.stem.rsplit("-", 1)[-1],
    "candidates": review_candidates,
}
review_template = {
    "sourceFile": str(source_file),
    "sourceScope": source_scope,
    "targetScope": target_scope,
    "profileName": profile_name,
    "instructions": "Change decision to approve or drop for reviewed records before running apply-reviewed.",
    "decisions": [
        {
            "id": item["id"],
            "decision": "pending",
            "category": item["category"],
            "targetScope": item["targetScope"],
            "summary": item["summary"],
            "notes": "",
        }
        for item in review_candidates
    ],
}

review_candidates_path.write_text(json.dumps(review_manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
review_template_path.write_text(json.dumps(review_template, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

approved_review = {}
decision_payload = None
if mode == "apply-reviewed":
    approved_review, decision_payload = load_review_approvals()
    approved_review_count = len(approved_review)

def mark_existing(row):
    metadata = parse_metadata(row.get("metadata"))
    source_id = str(metadata.get("migration_original_id") or "")
    if source_id:
        existing_by_source_id[source_id] = row
    key = (
        normalize_text(row.get("text")),
        normalize_category(row.get("category")),
        str(row.get("scope") or ""),
    )
    existing_by_text[key].append(normalize_timestamp(row.get("timestamp")))

def is_duplicate(payload_args):
    metadata = parse_metadata(payload_args.get("metadata"))
    source_id = str(metadata.get("migration_original_id") or "")
    if source_id and source_id in existing_by_source_id:
        return True
    key = (
        normalize_text(payload_args.get("content")),
        normalize_category(payload_args.get("category")),
        str(payload_args.get("scope") or ""),
    )
    candidate_ts = normalize_timestamp(payload_args.get("timestamp"))
    for timestamp in existing_by_text.get(key, []):
        if abs(candidate_ts - timestamp) <= duplicate_time_window_ms:
            return True
    return False

def remember_imported(payload_args):
    metadata = parse_metadata(payload_args.get("metadata"))
    source_id = str(metadata.get("migration_original_id") or "")
    if source_id:
        existing_by_source_id[source_id] = payload_args
    key = (
        normalize_text(payload_args.get("content")),
        normalize_category(payload_args.get("category")),
        str(payload_args.get("scope") or ""),
    )
    existing_by_text[key].append(normalize_timestamp(payload_args.get("timestamp")))

if mode in {"apply", "apply-reviewed"}:
    existing_records = load_existing_target_records()
    for row in existing_records:
        mark_existing(row)

    if lancedb_db_path.exists():
        backup_path = report_path.parent / f"lancedb-backup-{report_path.stem}"
        if backup_path.exists():
            shutil.rmtree(backup_path)
        shutil.copytree(lancedb_db_path, backup_path)

    for record in memories:
        group = bucket(record)
        if group != "keep":
            continue
        args = import_payload(record, group)
        if is_duplicate(args):
            duplicates += 1
            continue
        bridge_call("add", args)
        imported += 1
        remember_imported(args)

    if mode == "apply-reviewed":
        for record_id, decision in approved_review.items():
            record = records_by_id.get(record_id)
            if not record or bucket(record) != "review":
                continue
            args = import_payload(record, "review-approved")
            args["metadata"]["migration_review_notes"] = str(decision.get("notes") or "")
            args["metadata"]["migration_review_decision"] = "approve"
            if is_duplicate(args):
                review_duplicates += 1
                continue
            bridge_call("add", args)
            review_imported += 1
            remember_imported(args)

filtered_out = bucket_counts.get("review", 0) + bucket_counts.get("drop", 0)

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
lines.append(f"- Review candidates file: `{review_candidates_path}`")
lines.append(f"- Review decisions template: `{review_template_path}`")
if decision_payload is not None:
    lines.append(f"- Review decisions file used: `{review_decisions_path}`")
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
    lines.append("- Review candidates were exported for human approval.")
    lines.append("- To continue, copy the latest review decisions template, mark `approve` or `drop`, then rerun in `apply-reviewed` mode.")
elif mode == "apply":
    lines.append("- This report reflects a conservative apply run.")
    lines.append(f"- Imported keep records: `{imported}`")
    lines.append(f"- Skipped as duplicates: `{duplicates}`")
    lines.append(f"- Left for review/drop buckets: `{filtered_out}`")
    lines.append("- Only `keep` bucket records were imported.")
    lines.append("- Original timestamp and source metadata were preserved in imported metadata.")
    lines.append("- `review` bucket records still need explicit review before any later import step.")
else:
    lines.append("- This report reflects a two-stage apply run.")
    lines.append(f"- Imported keep records: `{imported}`")
    lines.append(f"- Keep duplicates skipped: `{duplicates}`")
    lines.append(f"- Approved review decisions loaded: `{approved_review_count}`")
    lines.append(f"- Approved review records imported: `{review_imported}`")
    lines.append(f"- Approved review duplicates skipped: `{review_duplicates}`")
    lines.append(f"- Remaining review/drop buckets: `{filtered_out - approved_review_count}`")
    lines.append("- Review imports only occur for records explicitly marked `approve` in the decisions file.")
    lines.append("- Original timestamp and source metadata were preserved in imported metadata.")
if source_scope == "agent:n2" and target_scope != "agent:n2":
    lines.append("- Warning: source scope is `agent:n2` but target scope differs. Explicit human approval is required.")

report_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
print(json.dumps({
    "reportPath": str(report_path),
    "reviewCandidatesPath": str(review_candidates_path),
    "reviewTemplatePath": str(review_template_path),
    "backupPath": str(backup_path) if backup_path else "",
}, ensure_ascii=False))
PY

python3 - "$REVIEW_CANDIDATES_PATH" "$LATEST_REVIEW_CANDIDATES_PATH" "$REVIEW_TEMPLATE_PATH" "$LATEST_REVIEW_TEMPLATE_PATH" <<'PY'
import shutil
import sys
from pathlib import Path

review_candidates = Path(sys.argv[1])
latest_review_candidates = Path(sys.argv[2])
review_template = Path(sys.argv[3])
latest_review_template = Path(sys.argv[4])

shutil.copyfile(review_candidates, latest_review_candidates)
shutil.copyfile(review_template, latest_review_template)
PY

note "Memory migration report written to $REPORT_PATH"
note "Review candidates written to $REVIEW_CANDIDATES_PATH"
note "Review template written to $REVIEW_TEMPLATE_PATH"
cat "$REPORT_PATH"
