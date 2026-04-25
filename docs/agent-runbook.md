# Hermes Portable Bootstrap Runbook

This document is optimized for AI agents.

## Mission

Build one fresh Hermes profile on a new machine with these capabilities:

- NotebookLM skill stack
- NotebookLM Python runtime source checkout
- LanceDB Pro memory plugin
- Codex dispatch plugin

## Required behavior

When executing this runbook, the agent must:

1. Read `bootstrap.env`
2. Refuse to invent secrets or tokens
3. Stop on the first destructive ambiguity
4. Prefer idempotent actions
5. Verify each stage before moving on

## Inputs

The agent must obtain these values from `bootstrap.env`:

- `HERMES_BIN`
- `HERMES_ROOT`
- `PROFILE_NAME`
- `PROFILE_HOME`
- `REPOS_DIR`
- `NOTEBOOKLM_HERMES_SKILL_REPO`
- `NOTEBOOKLM_PY_REPO`
- `LANCEDB_PRO_HERMES_REPO`
- `CODEX_DISPATCH_HERMES_PLUGIN_REPO`
- `LANCEDB_DB_PATH`
- `LANCEDB_SCOPE_NAME`
- `CODEX_ALLOWED_ROOT`
- `MEMORY_MIGRATION_MODE`
- `MEMORY_SOURCE_MAIN_EXPORT`
- `MEMORY_SOURCE_N2_EXPORT`
- `MEMORY_SOURCE_SCOPE`
- `MEMORY_TARGET_SCOPE`
- `MEMORY_ALLOW_N2_REMAP`

## Do not assume

Do not assume:

- the target profile name is `m2`
- tokens already exist
- Google NotebookLM auth is already complete
- the memory provider should be copied from the old machine without review
- the target machine has the same filesystem layout as the source machine

Do not treat `openclaw_lancedb` as a GitHub-installable dependency unless the
human explicitly provides a repository URL. In the current source machine, it is
a local migration adapter backed by:

- `~/.hermes/migration/openclaw-lancedb-pro-export/`

For any historical-memory carry-over task, also read:

- [memory-migration.md](/Users/sscomp/hermes-portable-bootstrap/docs/memory-migration.md)

## Execution order

Run these scripts in order:

```bash
bash scripts/01-prepare-repos.sh bootstrap.env
bash scripts/02-create-profile.sh bootstrap.env
bash scripts/03-install-notebooklm.sh bootstrap.env
bash scripts/04-install-memory.sh bootstrap.env
bash scripts/05-install-codex-dispatch.sh bootstrap.env
bash scripts/06-smoke-test.sh bootstrap.env
```

Optional memory-planning step:

```bash
bash scripts/07-migrate-memory.sh bootstrap.env
```

## Manual checkpoints the agent must announce

After script 03:

- NotebookLM login is still required
- human must run or approve `nb login`

After script 04:

- the real profile `.env` must be filled in
- LanceDB data migration is still a separate decision
- if migration is requested, follow `docs/memory-migration.md`

After script 05:

- Hermes gateway must be restarted before slash commands are tested

After script 07:

- if mode is `plan`, review the generated migration report before any real import work
- if mode is `apply`, only claim import completion after reviewing the import report
- do not silently remap `agent:n2` into another scope unless `MEMORY_ALLOW_N2_REMAP=1`

## Expected result

At the end, the target profile should have:

- `<PROFILE_HOME>/bin/nb`
- `<PROFILE_HOME>/skills/research/notebooklm`
- `<PROFILE_HOME>/plugins/lancedb_pro_hermes`
- `<PROFILE_HOME>/plugins/codex-dispatch`
- `<PROFILE_HOME>/codex-dispatch/config.json`
- `<PROFILE_HOME>/codex-dispatch/codex-projects.json`
- `memory.provider: lancedb_pro_hermes` in `<PROFILE_HOME>/config.yaml`
- `plugins.enabled` includes `codex-dispatch`
- NotebookLM quick commands in `<PROFILE_HOME>/config.yaml`

## Human-required validations

The agent should ask the human to validate these after gateway restart:

- `/nb-list`
- `/nb-login`
- `/codex-projects`
- `hermes --profile <profile> memory status`

## Failure handling

If a script fails:

1. report the exact command
2. report the exact file that caused the failure
3. do not silently skip to the next stage
