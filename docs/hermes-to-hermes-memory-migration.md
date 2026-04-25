# Hermes to Hermes Memory Migration

This document describes how to move Hermes long-term memory from one Hermes
machine to another Hermes machine.

## Use both repos

This flow uses both repos, with different roles:

- [sscomp/lancedb-pro-hermes-plugin](https://github.com/sscomp/lancedb-pro-hermes-plugin)
  - install the formal `hermes_lancedb` memory provider on the target machine
- [sscomp/hermes-portable-bootstrap](https://github.com/sscomp/hermes-portable-bootstrap)
  - handle export, install order, migration planning, and Hermes-side import

## Terminology

- `export`: read memory from the old Hermes machine and write a JSON file
- `migration`: review, map, dedupe, and import the exported JSON into the new Hermes machine

## Source-side export

On the old Hermes machine, run:

```bash
bash scripts/08-export-hermes-memory.sh <profile-home> <plugin-repo-dir> [output-file]
```

Example:

```bash
bash scripts/08-export-hermes-memory.sh \
  ~/.hermes/profiles/coder \
  ~/src/lancedb-pro-hermes-plugin \
  ~/.hermes/migration/hermes-coder-export.json
```

What it exports:

- the source profile scope
- the global scope

What it needs:

- source profile `.env`
- source plugin repo checkout
- working `hermes_lancedb` bridge

## Target-side install

On the new Hermes machine:

1. install the target profile with the bootstrap flow
2. ensure `scripts/04-install-memory.sh` completes
3. ensure the target profile uses:
   - `memory.provider: hermes_lancedb`

## Target-side migration

In the target machine's `bootstrap.env`, set:

```bash
MEMORY_SOURCE_SCOPE="agent:<source-profile>"
MEMORY_SOURCE_EXPORT="/absolute/path/to/hermes-source-export.json"
MEMORY_TARGET_SCOPE="agent:<target-profile>"
```

Then run planning first:

```bash
bash scripts/07-migrate-memory.sh bootstrap.env
```

If the review output looks correct, continue with:

- `MEMORY_MIGRATION_MODE="apply"`
- or `MEMORY_MIGRATION_MODE="apply-reviewed"`

Then rerun:

```bash
bash scripts/07-migrate-memory.sh bootstrap.env
```

## Recommended order

1. export on old Hermes machine
2. copy JSON to new Hermes machine
3. install target profile and `lancedb-pro-hermes-plugin`
4. run migration in `plan`
5. review candidates
6. run migration in `apply` or `apply-reviewed`
7. validate retrieval on the target machine

## Validation

After migration, verify:

- `hermes --profile <target> memory status`
- one known user preference
- one known architecture decision
- one known debugging conclusion
- no obvious cross-profile leakage

## Related files

- [scripts/08-export-hermes-memory.sh](/Users/sscomp/hermes-portable-bootstrap/scripts/08-export-hermes-memory.sh)
- [scripts/07-migrate-memory.sh](/Users/sscomp/hermes-portable-bootstrap/scripts/07-migrate-memory.sh)
- [docs/memory-migration.md](/Users/sscomp/hermes-portable-bootstrap/docs/memory-migration.md)
