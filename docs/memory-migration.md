# Memory Migration Specification

This document defines how memory migration should be handled when rebuilding a
Hermes profile on a fresh machine.

## Purpose

Separate **portable install bootstrap** from **memory migration**.

The bootstrap process installs code, plugins, skills, and config structure.
Memory migration handles historical durable data.

Do not treat these as the same operation.

## Source and target

Current source-side reality:

- the local `m2` profile still uses `openclaw_lancedb`
- `openclaw_lancedb` is a migration adapter
- exported source data currently lives under:
  - `~/.hermes/migration/openclaw-lancedb-pro-export/`

Target-side design:

- the fresh Hermes profile should use `hermes_lancedb` or `lancedb_pro_hermes`
  as the formal memory provider
- migrated data should end up in the target LanceDB table with explicit scope
  mapping

## Migration goals

The migration should preserve:

- durable user facts
- profile-specific preferences
- important decisions
- architecture and debugging conclusions
- high-value long-term notes

The migration should avoid carrying over:

- transient chat filler
- duplicate records
- stale low-value operational noise
- records that only existed for OpenClaw compatibility glue

## Required inputs

An agent must not begin memory migration until the human provides or confirms:

- source export directory
- target LanceDB database path
- target table name
- target profile name
- target scope mapping
- whether this is full import or selective import

## Scope mapping rules

Suggested mapping model:

- `global` stays `global`
- `agent:main` becomes `agent:<target-profile>`
- `agent:n2` should only migrate into another explicitly approved target

The agent must not silently merge `n2` memory into a non-`n2` profile.

## Migration modes

### Mode A: Fresh install only

Use when:

- the new machine only needs the memory provider installed
- old durable memory does not need to be imported yet

Result:

- provider installed
- empty or new LanceDB table

### Mode B: Full durable import

Use when:

- the human wants historical durable memory brought forward
- the target profile is a continuity profile

Result:

- source records imported into the target table
- scope mapping applied
- duplicate handling required

### Mode C: Selective import

Use when:

- the human wants only part of the old memory
- the old memory contains mixed-value or profile-misaligned data

Result:

- only approved categories or scopes are imported

## Category guidance

Recommended to keep:

- `decision`
- `preference`
- `profile`
- `architecture`
- `debug`
- `fact`
- `user`

Recommended to review before import:

- `entity`
- `other`
- unknown categories

Recommended to drop unless explicitly requested:

- greeting-like filler
- one-off status chatter
- migration-only trace records

## Deduplication policy

Before importing into the target table, compare candidate rows by:

1. normalized text
2. scope
3. category
4. approximate timestamp proximity

If two rows are materially the same:

- keep the higher-importance row
- keep the newer row when importance is tied

Do not import obvious duplicates.

## Write safety

Before import:

1. back up the target LanceDB directory
2. record the target row count
3. record the source file list

After import:

1. record imported row count
2. record skipped row count
3. record duplicate row count
4. record final row count

## Validation checklist

After migration, validate:

1. target table opens successfully
2. target profile can query memory without errors
3. profile-scoped recall returns expected known records
4. global-scope recall still works
5. no obvious cross-profile leakage occurred

Recommended human spot checks:

- one known user preference
- one known architecture decision
- one known debugging conclusion

## Rollback expectation

If validation fails:

- restore the backed-up LanceDB directory
- do not leave the partially imported table in place
- document the failing record set or transform step

## Agent constraints

An AI agent following this spec must:

- separate install work from migration work
- never invent a scope mapping
- never import data without a named source path
- never import `n2` memory into another profile without explicit approval
- produce a short import report when migration is done

## Out of scope for this document

This document does not yet define:

- exact JSON export schema transform code
- a production import script
- automatic rollback tooling

Those should be added later as implementation artifacts once the target memory
provider is finalized.

