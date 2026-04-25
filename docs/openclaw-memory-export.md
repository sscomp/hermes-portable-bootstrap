# OpenClaw Memory Export

This document describes the **source-side export** step for legacy OpenClaw
memory data.

Use this on the old OpenClaw machine before any Hermes-side import or migration
work begins.

## Terminology

Keep these terms separate:

- `export`: read memory from the OpenClaw store and write JSON files
- `import`: load a prepared JSON file into a target memory store
- `migration`: apply mapping, review, dedupe, and validation rules while moving
  historical data into the new Hermes memory provider

The current bootstrap repo handles Hermes-side migration. This document handles
OpenClaw-side export.

## When to use

Use this document when:

- the source machine still has a working OpenClaw environment
- `memory-lancedb-pro` is installed and responding
- you want JSON export files such as `agent-main.json` and `agent-n2.json`

Do not use Hermes-side migration scripts as a substitute for source-side export.

## Expected output

By default, the export step should generate:

- `agent-main.json`
- `agent-n2.json`

Recommended output directory:

- `~/.hermes/migration/openclaw-lancedb-pro-export/`

This keeps the source-side export path aligned with the Hermes bootstrap and
migration documentation.

## Prerequisites

The old machine should satisfy:

- `openclaw` CLI is available
- `memory-lancedb-pro` is installed
- `openclaw memory-pro stats` succeeds

Useful preflight commands:

```bash
openclaw memory-pro version
openclaw memory-pro stats
```

## Recommended command

The bootstrap repo includes:

- [scripts/00-export-openclaw-memory.sh](/Users/sscomp/hermes-portable-bootstrap/scripts/00-export-openclaw-memory.sh)

Run it on the old machine:

```bash
bash scripts/00-export-openclaw-memory.sh
```

Optional custom output directory:

```bash
bash scripts/00-export-openclaw-memory.sh /path/to/export-dir
```

## What the script does

The export script:

1. verifies `openclaw` is available
2. verifies `openclaw memory-pro stats` succeeds
3. creates the output directory
4. exports `agent:main` to `agent-main.json`
5. exports `agent:n2` to `agent-n2.json`

It does not mutate the source memory store.

## Manual equivalent

If you do not use the script, the equivalent commands are:

```bash
mkdir -p ~/.hermes/migration/openclaw-lancedb-pro-export

openclaw memory-pro export \
  --scope agent:main \
  --output ~/.hermes/migration/openclaw-lancedb-pro-export/agent-main.json

openclaw memory-pro export \
  --scope agent:n2 \
  --output ~/.hermes/migration/openclaw-lancedb-pro-export/agent-n2.json
```

## Hand-off to Hermes

After export is complete:

1. copy the JSON files to the new Hermes machine if needed
2. point `bootstrap.env` to those files
3. run Hermes-side migration planning or migration

Relevant follow-up documents:

- [docs/memory-migration.md](/Users/sscomp/hermes-portable-bootstrap/docs/memory-migration.md)
- [docs/agent-runbook.md](/Users/sscomp/hermes-portable-bootstrap/docs/agent-runbook.md)
