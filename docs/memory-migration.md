# Memory Migration Specification

This document defines how memory migration should be handled when rebuilding a
Hermes profile on a fresh machine.

## Purpose

Separate **portable install bootstrap** from **memory migration**.

The bootstrap process installs code, plugins, skills, and config structure.
Memory migration handles historical durable data.

Do not treat these as the same operation.

## Terminology

Keep these terms separate:

- `export`: read source-side OpenClaw memory and write JSON files
- `import`: load a prepared JSON file into a target store
- `migration`: apply mapping, review, dedupe, and validation rules while
  performing Hermes-side import work

This document is about Hermes-side migration, not OpenClaw-side export.
For Hermes-to-Hermes source export, also see:

- [docs/hermes-to-hermes-memory-migration.md](/Users/sscomp/hermes-portable-bootstrap/docs/hermes-to-hermes-memory-migration.md)

## Source and target

Current source-side reality:

- the local `m2` profile still uses `openclaw_lancedb`
- `openclaw_lancedb` is a migration adapter
- exported source data currently lives under:
  - `~/.hermes/migration/openclaw-lancedb-pro-export/`
- the recommended source-side export instructions live in:
  - [docs/openclaw-memory-export.md](/Users/sscomp/hermes-portable-bootstrap/docs/openclaw-memory-export.md)

Target-side design:

- the fresh Hermes profile should use `hermes_lancedb`
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

- source records imported into the target table through migration rules
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

Recommended to review before Hermes-side import:

- `entity`
- `other`
- unknown categories

Recommended to drop unless explicitly requested:

- greeting-like filler
- one-off status chatter
- migration-only trace records

## Deduplication policy

Before importing into the target table through migration, compare candidate rows by:

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
- never import data without a named source export path
- never import `n2` memory into another profile without explicit approval
- produce a short import report when migration is done

## Out of scope for this document

This document does not yet define:

- exact JSON export schema transform code
- a production import script
- automatic rollback tooling

Those should be added later as implementation artifacts once the target memory
provider is finalized.

## Review and approval flow

The migration should be treated as a staged workflow:

1. `plan`
2. human review
3. `apply`
4. optional `apply-reviewed`

Expected artifacts:

- migration report
- review candidates JSON
- review decisions template JSON
- final review decisions JSON approved by a human

The agent must not treat `review` records as approved by default.

## Metadata preservation

When a record is imported into the target LanceDB table, the importer should
preserve and extend source-side metadata, not discard it.

Minimum preserved fields:

- original source record id
- original source scope
- original timestamp
- source export file
- source export time
- migration bucket

The target record should also preserve the original `timestamp` where possible.

## First implementation artifact

The current bootstrap repo includes:

- [scripts/00-export-openclaw-memory.sh](/Users/sscomp/hermes-portable-bootstrap/scripts/00-export-openclaw-memory.sh)
- [scripts/07-migrate-memory.sh](/Users/sscomp/hermes-portable-bootstrap/scripts/07-migrate-memory.sh)

Current role of that script:

- `00-export-openclaw-memory.sh`
  - run on the old OpenClaw machine
  - export source data into `agent-main.json` and `agent-n2.json`
- `07-migrate-memory.sh`
- read the source export JSON
- generate a migration planning report
- generate review candidates and a decisions template
- count records by category
- classify records into keep / review / drop buckets
- show proposed source-scope to target-scope mapping
- when mode is `apply`, import only `keep` bucket records into the target LanceDB table under Hermes-side migration rules
- when mode is `apply-reviewed`, import `keep` plus explicitly approved review records
- skip obvious duplicates by normalized text + category + target scope
- preserve original timestamp and source metadata in imported records

Current non-goals of that script:

- it does not approve `review` bucket records automatically
- it does not mutate the source export
- it does not claim that review-required data was fully migrated unless `apply-reviewed` used an approved decisions file

Treat it as a conservative first importer plus planning tool, not as the final full-fidelity migration pipeline.
