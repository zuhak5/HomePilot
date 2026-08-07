# HomePilot Recurring Maintenance Completion — Full Fix Plan

**Repository:** `zuhak5/HomePilot`  
**Target:** current `main` after release `1.4.6 (Build 32)`  
**Primary affected flow:** recurring maintenance task `Complete` / sync / next recurrence / `Complete`  
**Observed symptom:** the first completion succeeds, but a later completion can appear locally, then revert within roughly one second and never persist to Supabase.  
**Additional observation:** `Complete → Undo → Complete` can succeed, which is consistent with Undo cancelling/restoring the original occurrence before the next precision-divergent occurrence becomes authoritative.

---

## 1. Objective

Fix recurring task completion so that:

1. Every recurrence uses one canonical timestamp representation across Flutter, Drift/SQLite, the sync outbox, and Supabase.
2. Sequential completions cannot fail because one side kept microseconds while another side truncated to seconds.
3. Completion dependencies are actually enforced, not merely included in payload JSON.
4. Rejected/remote-winner reconciliation cannot overwrite newer local work.
5. Undo behavior is explicitly defined and safe for both pending and already-synced completions.
6. Duplicate user actions cannot create overlapping completion operations for the same plan.
7. Sync telemetry distinguishes successful acknowledgements from rejected-and-compensated mutations.
8. Regression tests reproduce the real Flutter → SQLite → Supabase timestamp round-trip instead of testing only `.000Z` timestamps.

The fix should preserve offline-first behavior and should not require destructive database rewrites.

---

# 2. Confirmed Primary Root Cause

## 2.1 Timestamp precision mismatch

HomePilot's local synchronization layer stores synced `DateTime` values in SQLite at **whole-second precision**.

The relevant conversion in `lib/src/core/sync/local_sync_store.dart` converts a date to:

```dart
date.toUtc().millisecondsSinceEpoch ~/ 1000
```

and reconstructs it later by multiplying the stored seconds by `1000`.

This means a cloud timestamp such as:

```text
2026-08-08T18:13:27.842731Z
```

becomes locally:

```text
2026-08-08T18:13:27.000000Z
```

The lost `.842731` fraction cannot be recovered.

## 2.2 Completion currently generates sub-second recurrence timestamps

In `lib/src/core/data/repositories.dart`, the completion flow currently uses a fresh completion timestamp:

```dart
final completed = completedAt ?? _now();
```

The recurrence engine preserves milliseconds and microseconds when computing the next due date.

Therefore:

```text
completed = 2026-08-07T18:13:27.842731Z
next due = 2026-08-08T18:13:27.842731Z
```

The local database stores that next due date as whole seconds, while the completion RPC payload sends the full in-memory microsecond value.

Supabase therefore stores the full-precision value.

## 2.3 Why the first completion normally works

A task created through the UI is normally initialized from a date/time picker that creates a `DateTime` only through minute/hour fields, so the original due date has zero milliseconds and microseconds.

Example:

```text
Initial due:
cloud = 2026-08-07T18:00:00.000000Z
local = 2026-08-07T18:00:00.000000Z
```

The first completion compares the same exact due date and succeeds.

## 2.4 Why the second completion fails

After the first completion:

```text
Supabase next_due_date:
2026-08-08T18:13:27.842731Z

SQLite next_due_date:
2026-08-08T18:13:27.000000Z
```

The next completion sends the SQLite value as:

```json
"expected_next_due_date": "2026-08-08T18:13:27.000Z"
```

The RPC compares it against the exact PostgreSQL value:

```text
2026-08-08T18:13:27.842731Z
```

They are different, so the RPC returns an occurrence conflict such as `occurrence_changed`.

The local completion was already optimistically applied, so the UI briefly shows success; the automatic sync runs shortly afterward, the RPC rejects the mutation, and local conflict compensation deletes the optimistic record and restores the cloud plan.

That is the visible "complete, then revert" behavior.

---

# 3. Why `Complete → Undo → Complete` Can Work

`undoLastCompletion()` currently acts primarily as a **local cancellation/restoration path**.

For a still-pending completion it:

1. Deletes the `maintenance_completion` outbox row for the latest completion.
2. Deletes the local maintenance record.
3. Restores the plan's previous due date.
4. Updates the plan locally.

If Undo happens before the first completion has become an authoritative cloud state, the task returns to the original due date, which was typically whole-second aligned.

The following completion therefore compares against the clean original occurrence and succeeds.

This observation strongly supports the timestamp-divergence diagnosis.

However, the implementation plan must distinguish two cases:

### Case A — Undo before completion syncs

This can safely mean "cancel the pending local completion."

### Case B — Undo after completion has already synced

This is a different operation. Deleting only local state is not enough, because Supabase already contains the completion record and advanced plan.

The product must either:

- support a real server-side undo/reversal operation, or
- disable/reject Undo once a completion is acknowledged by the server.

Do not leave the behavior ambiguous.

---

# 4. Required Fixes

The work is divided into:

- **P0:** required to fix the user's recurring rollback.
- **P1:** required to make the completion protocol robust.
- **P2:** hardening and observability.

---

# 5. P0 — Canonicalize Completion Timestamps

## 5.1 Define one protocol timestamp precision

Use **whole seconds** for maintenance completion protocol timestamps.

This matches the precision already retained by the local Drift/SQLite representation and avoids an invasive storage migration.

Create one canonical helper instead of scattered ad-hoc conversions.

Suggested API:

```dart
DateTime canonicalSyncSecond(DateTime value) {
  final utc = value.toUtc();
  final micros =
      (utc.microsecondsSinceEpoch ~/ Duration.microsecondsPerSecond) *
      Duration.microsecondsPerSecond;

  return DateTime.fromMicrosecondsSinceEpoch(
    micros,
    isUtc: true,
  );
}
```

The exact helper name/location can follow project conventions.

Preferred location:

```text
lib/src/core/sync/
```

or an existing date/sync utility module if one already owns serialization rules.

### Rule

For the maintenance completion protocol, the following fields must always be canonicalized before either persistence or payload creation:

- completion timestamp
- expected current due date
- record due date
- record completed-at
- next recurrence due date
- any timestamp used as a strict occurrence identity

---

## 5.2 Fix `completePlanResult()`

File:

```text
lib/src/core/data/repositories.dart
```

Current logical flow:

```dart
final completed = completedAt ?? _now();
final previousDueDate = plan.nextDueDate;
final nextDue = recurrenceEngine.nextDueDate(completed, recurrence);
```

Change it conceptually to:

```dart
final completed =
    canonicalSyncSecond(completedAt ?? _now());

final previousDueDate =
    canonicalSyncSecond(plan.nextDueDate);

final nextDue = canonicalSyncSecond(
  recurrenceEngine.nextDueDate(
    completed,
    recurrence,
  ),
);
```

### Important

Canonicalize `completed` **before** passing it to the recurrence engine.

Do not compute recurrence from a microsecond timestamp and merely truncate the result afterward unless there is a compelling domain requirement.

The recurrence anchor itself should be canonical.

---

## 5.3 Build the RPC payload only from canonical values

The local persisted values and outgoing payload values must be identical.

For example:

```dart
'expected_next_due_date':
    previousDueDate.toUtc().toIso8601String(),

'record': {
  'due_date':
      previousDueDate.toUtc().toIso8601String(),
  'completed_at':
      completed.toUtc().toIso8601String(),
},

'plan': {
  'next_due_date':
      nextDue.toUtc().toIso8601String(),
}
```

The critical invariant is:

```text
value written to Drift == value serialized to outbox == value sent to RPC
```

Do not use the original non-canonical `DateTime` after canonicalization.

---

# 6. P0 — Server-Side Compatibility Migration

A client-only fix is not sufficient because existing cloud plans may already contain fractional `next_due_date` values created by older clients.

Add an **append-only Supabase migration**.

Do not edit previously deployed migration files.

Suggested migration purpose:

```text
canonicalize maintenance completion timestamps to whole-second precision
```

---

## 6.1 Normalize incoming timestamps inside the RPC

For:

- `expected_next_due_date`
- `record_due_date`
- `record_completed_at`
- `plan_next_due_date`

normalize to whole-second precision after parsing.

In PostgreSQL, use a consistent expression such as:

```sql
date_trunc('second', parsed_timestamp)
```

Use explicit variable names indicating canonicalized values.

Example conceptual structure:

```sql
v_expected_next_due_date :=
  date_trunc('second', (p_operation->>'expected_next_due_date')::timestamptz);
```

Apply the same normalization to all completion occurrence timestamps.

---

## 6.2 Compare the current cloud plan at canonical precision

Existing plans may contain fractional timestamps.

Instead of exact raw comparison:

```sql
current_plan.next_due_date IS DISTINCT FROM expected_next_due_date
```

compare canonicalized values:

```sql
date_trunc('second', current_plan.next_due_date)
IS DISTINCT FROM
v_expected_next_due_date
```

This allows an existing cloud value:

```text
18:13:27.842731
```

to match a canonical client value:

```text
18:13:27
```

for the same logical occurrence.

---

## 6.3 Normalize the persisted next due date on successful completion

When the RPC successfully advances the plan, write:

```sql
v_plan_next_due_date
```

where that value is already truncated to seconds.

This causes affected plans to **self-heal on the next valid completion**.

Avoid a broad `UPDATE maintenance_plans SET next_due_date = ...` migration unless absolutely necessary, because the table's metadata trigger may:

- increment revisions,
- update `updated_at`,
- generate realtime activity,
- create unnecessary sync churn.

Prefer lazy normalization through normal completion writes.

---

## 6.4 Normalize idempotency comparisons

The RPC's operation-id reuse/idempotency check must compare occurrence timestamps using the same canonical precision.

A retried operation must not be rejected because one stored timestamp includes microseconds while the retry does not.

Canonicalize:

```text
existing record due date
incoming record due date
```

before equality comparison.

---

## 6.5 Fix remote-winner lookup

When the RPC detects that the plan has already advanced, it searches for a maintenance record with the requested occurrence due date.

That lookup currently must not depend on raw microsecond equality.

Change conceptually from:

```sql
where due_date = v_record_due_date
```

to canonical occurrence equality:

```sql
where date_trunc('second', due_date) = v_record_due_date
```

This is required for correct cross-device reconciliation.

Otherwise another client can successfully complete the occurrence, while a second client with a second-truncated local timestamp fails to recognize the winner.

---

# 7. P0 Regression Tests

## 7.1 Dart repository test reproducing the exact precision bug

Add a test using a completion time with non-zero milliseconds and microseconds.

Example:

```dart
DateTime.utc(
  2026,
  8,
  7,
  18,
  13,
  27,
  842,
  731,
)
```

Test:

1. Start plan at a whole-second due date.
2. Complete occurrence.
3. Assert local record `completedAt` is whole-second canonical.
4. Assert local next due date is whole-second canonical.
5. Parse queued outbox JSON.
6. Assert payload `record.completed_at` equals persisted local record.
7. Assert payload `plan.next_due_date` equals persisted local plan.
8. Assert payload `expected_next_due_date` equals persisted previous due occurrence.

The test must fail against the old implementation.

---

## 7.2 Database integration/pgTAP test with a legacy fractional cloud plan

Existing tests using only:

```text
.000Z
```

are insufficient.

Create a test where the database already contains:

```text
2026-08-08T18:13:27.842731Z
```

and the client submits:

```text
2026-08-08T18:13:27.000000Z
```

for the same occurrence.

Expected after fix:

```text
RPC accepts the occurrence
record is inserted
plan advances
new plan.next_due_date is stored at whole-second precision
```

---

## 7.3 Sequential version-2 completion test

The real client uses payload version 2.

Add a test that:

1. submits completion A using payload v2,
2. advances the plan,
3. submits completion B for the resulting recurrence,
4. confirms both complete successfully.

The test must include a fractional completion timestamp for A so that it exercises the original defect.

---

## 7.4 Cross-device winner test

Test:

1. Device A completes occurrence `T.842731`.
2. Device B submits the same occurrence as `T.000000`.
3. Server recognizes the existing winner.
4. Device B receives the `occurrence_completed_elsewhere` outcome instead of `occurrence_changed`.

---

# 8. P1 — Enforce Completion Dependencies

The client currently includes:

```json
"depends_on_operation_id": "..."
```

in payload v2, but this is not sufficient unless the queue and/or server actually enforce it.

---

## 8.1 Local queue must block dependent mutations

File likely involved:

```text
lib/src/core/sync/local_sync_store.dart
```

When selecting pending mutations, a `maintenance_completion` with:

```text
depends_on_operation_id = A
```

must not be returned as ready while operation A is:

- still pending,
- in retry backoff,
- failed-visible/unresolved,
- otherwise not known to be successfully applied.

### Existing dangerous scenario

1. Completion A fails transiently.
2. A receives `nextAttemptAt` in the future.
3. User completes the next local occurrence B.
4. B depends on A.
5. Generic ready query excludes A because it is in backoff.
6. Generic ready query can still return B.
7. B reaches Supabase before A.
8. Cloud plan has not advanced to B's occurrence.
9. B conflicts.

### Required behavior

B remains blocked until A is resolved.

---

## 8.2 Implement topological readiness

For `maintenance_completion` rows:

1. Parse payload JSON.
2. Read `depends_on_operation_id`.
3. If no dependency, mutation may be ready normally.
4. If dependency exists:
   - if predecessor still exists in outbox and is unresolved: block.
   - if predecessor is failed-visible: block and expose recovery state.
   - if predecessor is known applied/deleted-successfully: allow.
5. Preserve stable ordering among multiple ready operations.

Do not rely only on `changedAt`.

---

## 8.3 Add server-side defense in depth

Prefer the RPC to validate the predecessor when `depends_on_operation_id` is provided.

Possible server behavior:

```text
dependency_applied       -> continue
dependency_not_applied   -> retryable dependency_pending
dependency_invalid       -> explicit validation error
```

This prevents a buggy/old client from applying B ahead of A.

The server should not silently treat a missing predecessor as an ordinary occurrence mismatch.

---

# 9. P1 — Deterministic Ordering for Same-Second Operations

`changedAt` itself is stored at whole-second precision.

Two operations created within the same second can therefore compare equal.

Do not use second-precision `changedAt` as the only causal ordering key.

Preferred options:

1. explicit dependency graph for maintenance completions,
2. plus a stable tie-breaker such as operation UUID/order sequence,
3. or a local monotonic sequence if the project already has a suitable mechanism.

For recurring completion operations, dependency ordering is the authoritative mechanism.

---

# 10. P1 — Protect Newer Local Plan State During Reconciliation

## 10.1 Success path

Current success handling attempts to preserve a newer local plan by comparing:

```dart
currentPlan.updatedAt.isAfter(mutation.changedAt)
```

This is unsafe for changes occurring in the same second because both timestamps can be equal after Drift precision loss.

Replace timestamp-only causality with a stronger criterion.

Potential approaches:

- explicit pending mutation lookup for the same plan,
- operation dependency lineage,
- local mutation revision/sequence,
- shadow revision plus pending local state.

Do not decide "newer local state exists" exclusively by second-precision wall-clock timestamps.

---

## 10.2 Rejection path

`reconcileRejectedMaintenanceCompletion()` is more dangerous because it can apply the canonical cloud plan unconditionally.

Required behavior:

1. Remove only the optimistic artifacts belonging to the rejected operation.
2. Determine whether newer local work exists for the same plan.
3. If newer local work exists:
   - do not overwrite the current local plan with older canonical state,
   - update remote shadow/canonical metadata instead,
   - rebase or block dependent operations.
4. If no newer local work exists:
   - apply canonical plan normally.

---

## 10.3 Remote winner path

Apply the same protection when handling:

```text
occurrence_completed_elsewhere
```

A remote winner should reconcile the relevant occurrence without destroying a later unsynced local mutation.

---

# 11. P1 — Define and Fix Undo Semantics

Undo needs a precise state machine.

---

## 11.1 Pending completion undo

If the completion is still local/pending:

Expected behavior:

1. remove pending completion outbox operation,
2. remove optimistic maintenance record,
3. restore previous plan due date,
4. restore any locally changed derived state,
5. cancel/update notifications as appropriate,
6. do not contact Supabase because the operation was never acknowledged.

This is effectively cancellation.

---

## 11.2 Synced completion undo

If the completion has already been acknowledged remotely, local deletion is not enough.

Choose one of these explicit product behaviors:

### Option A — Implement real cloud undo

Preferred if Undo should remain available after sync.

Add an idempotent server-side operation/RPC that:

1. locks the plan,
2. identifies the specific completion operation/record,
3. verifies that it is safe to reverse,
4. deletes or marks the completion reversed,
5. restores the prior due date,
6. increments plan revision normally,
7. returns canonical plan state,
8. supports retries/idempotency.

This must be concurrency-safe.

### Option B — Restrict Undo to unacknowledged operations

If a full distributed undo is out of scope:

1. expose Undo only during a clearly pending cancellation window,
2. once server acknowledgment arrives, remove/disable Undo,
3. do not perform a local-only reversal of an acknowledged cloud mutation.

Do not allow UI to imply a successful undo that only changed SQLite.

---

## 11.3 Add Undo tests

Test both:

```text
Complete -> immediate Undo -> Complete
```

and:

```text
Complete -> wait for server acknowledgement -> Undo -> Complete
```

The second flow must have an explicitly defined expected outcome.

---

# 12. P1 — Completion Single-Flight

The controller currently guards the notes-collection path, but the actual `complete()` method must also enforce single-flight.

File:

```text
lib/src/features/maintenance/presentation/task_completion_controller.dart
```

Required:

```text
at most one active completion commit per plan/controller
```

At entry to `complete()`:

1. if completion is already committing, return/ignore deterministically,
2. otherwise acquire the in-progress state,
3. release state only when local commit outcome is finalized.

Do not depend exclusively on the UI disabling a button.

Add a rapid double-tap regression test.

---

# 13. P1 — Protect Pending Composite Completion From Pull

A pending `maintenance_completion` mutates both:

- `maintenance_records`
- `maintenance_plans`

but its outbox entity key is the completion operation, not necessarily the plan entity itself.

Pull conflict shielding that only checks:

```text
pendingChangedAt('maintenance_plan', planId)
```

may fail to realize that the plan is currently owned by an optimistic composite mutation.

Required:

1. teach pending-state lookup that a pending `maintenance_completion` protects its `plan_id`,
2. or maintain explicit affected-entity metadata for composite operations,
3. prevent pull from applying stale remote plan state over an optimistic completion.

This is especially relevant for:

- manual sync,
- broad pull,
- realtime-triggered pull,
- app resume during a pending completion.

---

# 14. P2 — Preserve Rejection Diagnostics

Current rejected completion reconciliation deletes the completion outbox row after compensating local state.

That makes the failure difficult to diagnose.

Before deletion, preserve:

- operation id
- plan id
- server error code
- message
- occurrence due date
- retryability classification
- timestamp
- whether optimistic compensation was applied

Storage options:

- dedicated sync event/error table,
- existing diagnostics/telemetry facility,
- failed-operation history if the project already has one.

Do not retain a permanently blocking outbox row unless that matches the intended UX.

---

# 15. P2 — Fix Sync Telemetry

Do not infer "acknowledged" exclusively from:

```text
outbox count before - outbox count after
```

because rejected-and-compensated operations also disappear from the outbox.

Track explicit outcomes:

```text
applied
already_applied
remote_winner
retry_scheduled
rejected_reconciled
failed_visible
validation_failed
```

Then emit metrics such as:

```text
sync_push_applied_count
sync_push_remote_winner_count
sync_push_rejected_reconciled_count
sync_push_retry_count
```

This prevents dashboards from reporting a rejection as a successful acknowledgement.

---

# 16. P2 — Notes Idempotency Normalization

Review operation reuse/idempotency comparison for notes.

If the server stores normalized notes such as:

```text
trimmed
blank -> null
```

then the reuse comparison must normalize the incoming value the same way before comparing it to the existing record.

Otherwise:

```text
""
```

and:

```text
null
```

can represent the same canonical note but be treated as different operation payloads.

Add a small regression test if this mismatch still exists in the current migration.

---

# 17. Server Authority / Recurrence Validation

The current completion RPC should not trust arbitrary client-computed `plan_next_due_date` indefinitely.

At minimum, document this as a protocol weakness.

Preferred future hardening:

1. server receives completion occurrence + recurrence parameters,
2. server computes canonical next due date,
3. client-provided next due is either omitted or validated,
4. server returns authoritative next due.

This becomes especially important when server time clamps a client future `completed_at`.

If the RPC clamps:

```text
record_completed_at -> server current time
```

but still accepts a next due calculated from the client's skewed future time, the record and recurrence anchor can disagree.

This can be separated from the immediate rollback fix if required, but it should be tracked.

---

# 18. Files Expected to Change

At minimum inspect and likely modify:

```text
lib/src/core/data/repositories.dart
lib/src/core/sync/local_sync_store.dart
lib/src/core/sync/sync_coordinator.dart
lib/src/features/maintenance/presentation/task_completion_controller.dart
supabase/migrations/<new_append_only_migration>.sql
supabase/tests/database/0011_complete_maintenance_task.test.sql
```

Likely tests:

```text
test/sync_store_test.dart
test/sync_coordinator_test.dart
```

and the repository/controller test files that already cover maintenance completion.

Before editing anything, read:

```text
AGENTS.md
```

and follow repository-specific instructions.

---

# 19. Implementation Order

Use this order to minimize risk.

## Phase 1 — Reproduce

Add a failing test for:

```text
fractional first completion -> second completion
```

Do not implement the fix until the test demonstrably catches the old behavior.

## Phase 2 — Client timestamp canonicalization

Implement the canonical second helper and update maintenance completion local persistence/payload generation.

Run focused Dart tests.

## Phase 3 — Server compatibility migration

Add append-only RPC migration that:

- accepts v1/v2 as currently required,
- canonicalizes completion timestamps,
- compares legacy cloud dates at second precision,
- normalizes successful writes,
- fixes winner/idempotency comparisons.

Run database tests.

## Phase 4 — Sequential and cross-device tests

Add v2 sequential fractional test and remote-winner precision test.

## Phase 5 — Dependency enforcement

Implement local topological readiness and server-side dependency defense.

Add backoff/dependent test.

## Phase 6 — Reconciliation protection

Fix newer-local-state preservation for:

- success acknowledgement,
- rejected completion,
- remote winner.

## Phase 7 — Undo state machine

Implement or explicitly restrict post-ack Undo.

Add pre-ack and post-ack tests.

## Phase 8 — Single-flight and pull shielding

Add completion controller guard and composite pending-plan protection.

## Phase 9 — Observability

Persist rejection diagnostics and fix outcome telemetry.

---

# 20. Required Tests Matrix

The final PR should cover at least the following matrix.

| Scenario | Expected |
|---|---|
| First completion from minute-aligned task | succeeds |
| Second recurring completion | succeeds |
| Completion timestamp has milliseconds/microseconds | canonicalized to whole second |
| Legacy cloud next due contains microseconds | canonical client completion still succeeds |
| Local persisted next due vs outbox next due | exactly equal |
| Payload v2 sequential A -> B | both succeed |
| A retry is in backoff and B depends on A | B remains blocked |
| Two same-second completions | deterministic ordering |
| Same operation retried | idempotent |
| Another device already completed occurrence | remote winner is adopted |
| Remote winner uses fractional due, local uses whole second | still recognized |
| Rejected older completion with newer local plan | newer local state preserved |
| Older success ack arrives after newer local plan mutation | newer local state preserved |
| Rapid double tap Complete | one logical completion operation |
| Pull occurs while completion is pending | optimistic plan is not overwritten |
| Complete -> immediate Undo -> Complete | behaves deterministically and succeeds |
| Complete -> server ack -> Undo | explicitly defined cloud-safe behavior |
| Rejected completion | diagnostic reason remains observable |
| Rejected-and-compensated outbox deletion | not counted as successful acknowledgement |

---

# 21. Acceptance Criteria

The fix is complete only when all of these are true:

1. Repeating the user's original test no longer produces a rollback on the second recurrence.
2. Supabase receives and stores the second completion record.
3. Local plan and cloud plan have the same logical next due date.
4. Completion protocol dates are whole-second canonical on both sides.
5. A legacy fractional cloud `next_due_date` does not make the next completion fail.
6. Successful completion no longer relies on exact equality of incompatible timestamp precision.
7. Dependency B cannot be pushed while predecessor A remains unresolved.
8. Conflict compensation cannot erase later local work.
9. Undo has defined behavior before and after server acknowledgement.
10. A rapid double press cannot create concurrent completion commits.
11. Database tests use payload v2 and at least one non-zero fractional timestamp.
12. Sync telemetry can distinguish success from rejection/reconciliation.

---

# 22. Do Not Implement These Shortcuts

Do **not** fix the bug by:

- adding an arbitrary tolerance such as `±1 second` without defining a canonical protocol,
- globally rewriting every maintenance plan timestamp in one migration unless proven necessary,
- disabling conflict detection entirely,
- removing `expected_next_due_date`,
- retrying `occurrence_changed` blindly,
- adding delays before sync,
- extending the UI Undo window as a workaround,
- keeping microseconds in payload while silently truncating only SQLite,
- assuming payload v2 dependency metadata automatically enforces ordering,
- relying only on `updatedAt` to determine causal recency,
- treating outbox deletion as proof of server acknowledgement.

These would mask symptoms while preserving correctness defects.

---

# 23. Suggested Code-Level Invariants

Add comments/assertions around the completion protocol documenting these invariants:

```text
I1. All maintenance occurrence identity timestamps are UTC whole seconds.

I2. A timestamp written optimistically to Drift must be byte-for-byte
    equivalent after serialization to the timestamp included in the
    corresponding completion mutation.

I3. A maintenance completion with an unresolved predecessor cannot be pushed.

I4. Reconciliation may remove only state owned by the operation being
    reconciled; it must not destroy causally newer local state.

I5. An acknowledged cloud completion cannot be undone using a local-only
    mutation.

I6. At most one local completion commit may be active per plan at a time.
```

These invariants are more important than preserving the current implementation shape.

---

# 24. Suggested Commit Structure

Prefer small commits that keep the protocol change reviewable.

Example:

```text
fix: canonicalize maintenance completion timestamps
test: reproduce fractional recurring completion conflict
db: normalize maintenance completion timestamp comparisons
test: cover v2 sequential and remote-winner completion
fix: enforce maintenance completion dependencies
fix: preserve newer local state during completion reconciliation
fix: define synced maintenance completion undo behavior
fix: guard maintenance completion single-flight
chore: improve completion rejection telemetry
```

If the project prefers a single PR, keep these as separate commits inside it.

---

# 25. Verification Procedure on a Real Device

After automated tests pass:

1. Install the build against a clean account/database state.
2. Create a recurring test task.
3. Note the initial due time.
4. Press Complete.
5. Wait for sync acknowledgement.
6. Confirm the maintenance record exists in Supabase.
7. Inspect `maintenance_plans.next_due_date`.
8. Confirm it has no fractional seconds.
9. Press Complete on the next occurrence.
10. Confirm the UI does not revert.
11. Confirm a second Supabase maintenance record exists.
12. Repeat for several recurrences.
13. Test offline completion A, then completion B after A is queued.
14. Reconnect and verify A then B are applied in causal order.
15. Test rapid double-tap Complete.
16. Test Complete -> immediate Undo -> Complete.
17. Test Complete -> confirmed sync -> Undo according to the newly defined product behavior.
18. Test two devices completing the same occurrence.

---

# 26. Optional Diagnostic SQL During Validation

After the first completion and before the second, inspect whether any fractional precision remains:

```sql
select
  id,
  next_due_date as cloud_due,
  date_trunc('second', next_due_date) as canonical_due,
  next_due_date is distinct from date_trunc('second', next_due_date)
    as has_fractional_precision,
  revision
from public.maintenance_plans
where id = '<PLAN_ID>';
```

After the fix, newly advanced plans should normally report:

```text
has_fractional_precision = false
```

Inspect records:

```sql
select
  id,
  plan_id,
  due_date,
  completed_at,
  operation_id
from public.maintenance_records
where plan_id = '<PLAN_ID>'
order by completed_at desc;
```

After two successful recurrences, two corresponding records should exist.

---

# 27. Final Priority Summary

### Must ship for the reported bug

1. Canonical whole-second timestamps in `completePlanResult()`.
2. Append-only RPC migration that canonicalizes comparisons and writes.
3. Legacy fractional-plan compatibility.
4. Fractional sequential v2 regression tests.
5. Cross-device winner precision test.

### Should ship in the same robustness pass

6. Enforce `depends_on_operation_id`.
7. Protect newer local state during rejection/winner reconciliation.
8. Guard `complete()` itself against concurrent execution.
9. Define post-ack Undo behavior.
10. Protect optimistic composite completion state from pull.

### Observability/hardening

11. Preserve rejection diagnostics.
12. Separate successful acknowledgements from compensated rejection metrics.
13. Normalize notes in idempotency checks.
14. Move recurrence authority toward the server in a later protocol hardening step.

---

## Expected Outcome

Once the P0 work is implemented correctly, the user's original sequence:

```text
Create recurring task
-> Complete
-> wait
-> Complete next recurrence
```

must behave exactly like repeated normal operations:

```text
local optimistic update
-> server acknowledgement
-> canonical state remains
```

with **no UI rollback and a corresponding Supabase record for every completion**.

The `Complete -> Undo -> Complete` behavior should also become deterministic because Undo will have explicit semantics rather than accidentally avoiding the precision-divergent state.
