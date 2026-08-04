# Backup and Restore

## Goals

HomePilot backups provide a user-controlled way to preserve and transfer local application data and supported media. Restore must protect existing data and treat every imported archive as untrusted.

The backup service and tests are authoritative for exact file names, limits, and schema handling.

## Format

The current design uses a versioned ZIP archive containing:

- A manifest describing format and database compatibility.
- The database payload or exported application data.
- Supported media files.
- Cryptographic hashes used to verify archive content.
- Metadata required to validate and stage restoration.

The format version is independent from the Flutter package version and the Drift schema version. Compatibility must be decided explicitly rather than inferred from application version alone.

## Export sequence

1. Resolve the destination selected by the user or application retention policy.
2. Create a consistent database snapshot.
3. Enumerate allowed media from controlled roots.
4. Build the manifest and content hashes.
5. Write the archive to a temporary path.
6. Verify the completed archive.
7. Move it atomically where supported.
8. Apply automatic-backup retention without deleting the active or safety archive.

Partial archives must not be presented as successful backups.

## Import threat model

An imported archive can contain:

- Absolute or parent-traversal paths.
- Symlinks or path aliases.
- Excessive entry counts.
- Highly compressed data intended to exhaust storage or memory.
- Duplicate paths.
- Corrupted or misleading manifests.
- Hash mismatches.
- Unsupported format or database versions.
- Unexpected file types or media.
- Malformed database content.

Validation must occur before any file is written outside a controlled staging directory.

## Restore sequence

1. Open the archive without trusting names or metadata.
2. Validate the format version and required manifest fields.
3. Enforce entry-count, per-entry, total-expanded-size, and compression limits.
4. Normalize every path and reject absolute, traversal, duplicate, or disallowed entries.
5. Verify hashes and expected file types.
6. Validate database/schema compatibility.
7. Create a pre-restore safety backup of the current state.
8. Extract into a private staging directory.
9. Validate staged database and media.
10. Stop or suspend services that can mutate data during replacement.
11. Apply the staged state transactionally where possible.
12. Rebuild derived runtime state and reminder schedules.
13. Resume services and verify basic reads.
14. Roll back from the safety backup if any application step fails.
15. Clean temporary files without deleting diagnostic evidence needed for a safe user-facing error.

## Compatibility

A restore change must define:

- Which backup format versions are accepted.
- Which Drift schema versions can be migrated.
- Whether newer archives are rejected or partially supported.
- How removed fields or media types are handled.
- Whether synchronized operational state is restored, reset, or reconciled.
- How account binding is handled when the archive and current session differ.

Do not restore stale account credentials or blindly reuse synchronization cursors from another account or environment.

## Synchronization interaction

Restore can introduce local state that differs from the cloud. The implementation must use an explicit policy for signed-in users, such as requiring sign-out, rebuilding outbox work, rehydrating, or reconciling entity revisions. Do not allow restored rows to bypass ownership and conflict rules.

## Media

Restore media only from validated paths and supported MIME/file types. Stage replacement before deleting current files. Metadata must not refer to files that failed verification or extraction.

## Retention

Automatic backup retention should be bounded and deterministic. Safety backups created for restore must not be removed until restore is confirmed. User-exported backups outside application storage remain under user control.

## Privacy

Backups may contain nearly all HomePilot content. Do not upload them automatically, include them in Sentry, or expose their paths or contents in logs. Account deletion cannot remove files the user exported to external storage or shared with another application.

## Tests

Cover valid current and historical archives, corrupted ZIPs, traversal paths, duplicate names, hash mismatch, oversized expansion, unsupported versions, insufficient storage, interrupted extraction, database migration failure, media replacement failure, rollback, retention, account mismatch, and synchronization restart.