# hermes-portable-bootstrap

Portable bootstrap repo for rebuilding a Hermes profile on a fresh machine.

This repository is designed for two audiences at the same time:

- AI agents that need a precise, step-by-step runbook they can execute
- humans who want a short Chinese explanation and a checklist they can review

## Goal

Rebuild a Hermes profile with the following components on a new machine:

- `notebooklm-hermes-skill`
- `notebooklm-py`
- `lancedb-pro-hermes-plugin`
- `codex-dispatch-hermes-plugin`

This repo intentionally treats the target profile as a **portable build target**,
not as a copy of the local `m2` profile.

## Important note about memory

The current local `m2` profile still uses `openclaw_lancedb`.

That component appears to be a **local migration adapter**, not a standalone
public GitHub dependency. The local manifest describes it as:

- `OpenClaw LanceDB migration adapter using exported memory snapshots plus a Hermes overlay store`

It reads from the local export area:

- `~/.hermes/migration/openclaw-lancedb-pro-export/`

This bootstrap repo targets the **new desired stack**:

- `lancedb-pro-hermes-plugin`

So the resulting fresh-machine profile is "m2-like" in capability, but not a
byte-for-byte clone of the current local `m2`.

Practical meaning:

- `notebooklm-hermes-skill`: GitHub dependency
- `notebooklm-py`: GitHub dependency
- `lancedb-pro-hermes-plugin`: GitHub dependency
- `codex-dispatch-hermes-plugin`: GitHub dependency
- `openclaw_lancedb`: local migration-only component, documented for reference only

## Recommended reading order

For AI agents:

- [docs/openclaw-memory-export.md](/Users/sscomp/hermes-portable-bootstrap/docs/openclaw-memory-export.md)
- [docs/hermes-to-hermes-memory-migration.md](/Users/sscomp/hermes-portable-bootstrap/docs/hermes-to-hermes-memory-migration.md)
- [docs/agent-runbook.md](/Users/sscomp/hermes-portable-bootstrap/docs/agent-runbook.md)
- [docs/memory-migration.md](/Users/sscomp/hermes-portable-bootstrap/docs/memory-migration.md)

For human review in Chinese:

- [docs/new-machine-quickstart.zh-TW.md](/Users/sscomp/hermes-portable-bootstrap/docs/new-machine-quickstart.zh-TW.md)
- [docs/portable-sop.zh-TW.md](/Users/sscomp/hermes-portable-bootstrap/docs/portable-sop.zh-TW.md)

## Quick start

1. Copy [templates/bootstrap.env.example](/Users/sscomp/hermes-portable-bootstrap/templates/bootstrap.env.example) to `bootstrap.env`
2. Adjust repo URLs, profile name, and machine-specific paths
3. Run the scripts in order:

```bash
bash scripts/01-prepare-repos.sh bootstrap.env
bash scripts/02-create-profile.sh bootstrap.env
bash scripts/03-install-notebooklm.sh bootstrap.env
bash scripts/04-install-memory.sh bootstrap.env
bash scripts/05-install-codex-dispatch.sh bootstrap.env
bash scripts/06-smoke-test.sh bootstrap.env
```

If the source machine still needs OpenClaw-side export, run:

```bash
bash scripts/00-export-openclaw-memory.sh
```

If historical memory should be reviewed or applied on the Hermes side, run the optional step:

```bash
bash scripts/07-migrate-memory.sh bootstrap.env
```

`07-migrate-memory.sh` is a Hermes-side migration-oriented importer with a staged flow:

- `plan`: generate the migration report plus review candidate files
- `apply`: import only the `keep` bucket with migration checks
- `apply-reviewed`: import `keep` plus review records explicitly marked `approve`

The script also preserves original `timestamp` and source-side metadata in the
imported LanceDB record metadata.

## Scope of automation

This repo automates:

- local repo checkout/update
- Hermes profile creation
- NotebookLM skill install
- LanceDB memory plugin install
- Codex dispatch plugin install
- basic config patching
- file-based smoke tests
- staged memory migration artifacts for human review

This repo does not automate secrets:

- profile `.env` real values
- Telegram / LINE / Slack tokens
- Google / NotebookLM login session
- existing LanceDB data migration

Those are documented as manual or semi-manual steps in the runbook.

## Included files

- [docs/agent-runbook.md](/Users/sscomp/hermes-portable-bootstrap/docs/agent-runbook.md): AI-agent-first execution contract
- [docs/new-machine-quickstart.zh-TW.md](/Users/sscomp/hermes-portable-bootstrap/docs/new-machine-quickstart.zh-TW.md): short human quickstart for a new machine
- [docs/openclaw-memory-export.md](/Users/sscomp/hermes-portable-bootstrap/docs/openclaw-memory-export.md): source-side OpenClaw export step
- [docs/hermes-to-hermes-memory-migration.md](/Users/sscomp/hermes-portable-bootstrap/docs/hermes-to-hermes-memory-migration.md): Hermes-to-Hermes memory migration flow
- [docs/memory-migration.md](/Users/sscomp/hermes-portable-bootstrap/docs/memory-migration.md): formal memory migration specification
- [docs/portable-sop.zh-TW.md](/Users/sscomp/hermes-portable-bootstrap/docs/portable-sop.zh-TW.md): Chinese review version
- [templates/bootstrap.env.example](/Users/sscomp/hermes-portable-bootstrap/templates/bootstrap.env.example): machine-local variables
- [templates/profile.env.example](/Users/sscomp/hermes-portable-bootstrap/templates/profile.env.example): placeholder profile env values
- [scripts/lib.sh](/Users/sscomp/hermes-portable-bootstrap/scripts/lib.sh): shared shell helpers
- [scripts/00-export-openclaw-memory.sh](/Users/sscomp/hermes-portable-bootstrap/scripts/00-export-openclaw-memory.sh)
- [scripts/08-export-hermes-memory.sh](/Users/sscomp/hermes-portable-bootstrap/scripts/08-export-hermes-memory.sh)
- [scripts/01-prepare-repos.sh](/Users/sscomp/hermes-portable-bootstrap/scripts/01-prepare-repos.sh)
- [scripts/02-create-profile.sh](/Users/sscomp/hermes-portable-bootstrap/scripts/02-create-profile.sh)
- [scripts/03-install-notebooklm.sh](/Users/sscomp/hermes-portable-bootstrap/scripts/03-install-notebooklm.sh)
- [scripts/04-install-memory.sh](/Users/sscomp/hermes-portable-bootstrap/scripts/04-install-memory.sh)
- [scripts/05-install-codex-dispatch.sh](/Users/sscomp/hermes-portable-bootstrap/scripts/05-install-codex-dispatch.sh)
- [scripts/06-smoke-test.sh](/Users/sscomp/hermes-portable-bootstrap/scripts/06-smoke-test.sh)
- [scripts/07-migrate-memory.sh](/Users/sscomp/hermes-portable-bootstrap/scripts/07-migrate-memory.sh)

## 中文簡述

這個 repo 的目的，是讓一台全新的 Hermes 機器可以按照固定步驟，重建出你要的 profile 能力組合。

重點不是複製 `m2` 目錄，而是用一套可重跑、可校對、可交給 AI agent 的流程，把需要的能力重新安裝起來。這樣之後換機、改 profile 名稱、交給 Claude / Codex 幫忙佈署，都比較穩。

另外，OpenClaw 端的 export 與 Hermes 端的 migration 現在已經拆開整理：

- [docs/openclaw-memory-export.md](/Users/sscomp/hermes-portable-bootstrap/docs/openclaw-memory-export.md)
- [docs/memory-migration.md](/Users/sscomp/hermes-portable-bootstrap/docs/memory-migration.md)
