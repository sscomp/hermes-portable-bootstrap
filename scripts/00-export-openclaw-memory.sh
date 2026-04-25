#!/usr/bin/env bash
set -euo pipefail

OPENCLAW_BIN="${OPENCLAW_BIN:-openclaw}"
OUTPUT_DIR="${1:-$HOME/.hermes/migration/openclaw-lancedb-pro-export}"

note() {
  printf '[openclaw-export] %s\n' "$*"
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Required command not found: $1" >&2
    exit 1
  fi
}

require_cmd "$OPENCLAW_BIN"

note "Checking OpenClaw memory-pro availability"
"$OPENCLAW_BIN" memory-pro version >/dev/null
"$OPENCLAW_BIN" memory-pro stats >/dev/null

mkdir -p "$OUTPUT_DIR"

note "Exporting agent:main to $OUTPUT_DIR/agent-main.json"
"$OPENCLAW_BIN" memory-pro export \
  --scope agent:main \
  --output "$OUTPUT_DIR/agent-main.json"

note "Exporting agent:n2 to $OUTPUT_DIR/agent-n2.json"
"$OPENCLAW_BIN" memory-pro export \
  --scope agent:n2 \
  --output "$OUTPUT_DIR/agent-n2.json"

note "Export complete"
note "Files written:"
note "  $OUTPUT_DIR/agent-main.json"
note "  $OUTPUT_DIR/agent-n2.json"
