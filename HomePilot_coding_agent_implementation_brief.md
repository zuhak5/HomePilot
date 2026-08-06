# HomePilot Remediation Implementation Brief for Coding Agent

**Prepared:** 2026-08-06  
**Evidence window:** 2026-08-04, approximately 10 minutes  
**Audited application:** HomePilot 1.3.5, Android package `com.homepilot.app`  
**Audited repository reference:** `zuhak5/HomePilot` at commit `e5bbddc98fcc2f0843008f8c0152c3b967492a1b`  
**Purpose:** Implement the confirmed and strongly supported fixes from the supplied Android, Supabase, forensic, and adversarial evidence.

---

## 1. Agent mission

Modify the current HomePilot repository to eliminate the confirmed sync/schema defect, prevent RPC-created rows from re-entering the generic insert path, make durable sync conflicts diagnosable and actionable, harden AdMob consent/SSV behavior, reduce privacy-sensitive logging, and add the missing tests and instrumentation.

Treat this document as an implementation specification, not as permission to apply snippets blindly. The repository may have changed after the audited commit. Inspect current code, migrations, tests, and deployment assumptions before editing.

### Required result

Produce a reviewable patch set that includes:

1. Forward-only database migrations.
2. Flutter/Dart sync and monetization changes.
3. Supabase Edge Function changes where applicable.
4. Automated tests for every required behavior in this brief.
5. Privacy-safe structured diagnostics and metrics.
6. A final implementation report listing changed files, migration safety, test results, residual risks, and operator-only actions.

---

## 2. Non-negotiable constraints

1. **Do not delete or auto-dismiss the four existing failed mutations.** Add a safe diagnostic/export and reason-specific repair path first.
2. **Do not claim data loss occurred.** The evidence proves four unresolved durable queue entries, not discarded or overwritten data.
3. **Do not claim no data loss occurred.** The four payloads and final local/remote states were not inspected.
4. **Do not invent a new maintenance RPC outcome model.** Typed status, retryability, conflict reason, current revision, and canonical payload support already exist in the audited implementation. Expose and use the existing contract.
5. **Do not treat every `23505` as an existing primary key.** Distinguish the violated constraint or use a bounded canonical-fetch recovery specific to the expected primary-key case.
6. **Do not bypass SSV signature verification because sentinel debug values are present.** A debug no-op is allowed only after successful cryptographic verification and strict classification.
7. **Return HTTP `200` for an intentionally accepted SSV callback.** Do not use `204` for the accepted no-op path described here.
8. **Do not edit an already-applied migration in place.** Create a new forward migration.
9. **Do not log raw user IDs, row IDs, plan IDs, titles, notes, dates, addresses, callback signatures, cookies, tokens, complete URLs, object paths, or request payloads.**
10. **Preserve current point-debit and SSV idempotency/replay controls.** Extend them; do not weaken them.
11. **Keep ads fail-closed when consent state is unavailable or misconfigured.**
12. **Use the same stable operation ID when retrying an uncertain server-authoritative RPC commit.** Never fall back to an ordinary insert merely because the RPC response was lost.

---

## 3. Evidence summary and confidence boundaries

### Confirmed runtime evidence

| Finding | Reproduced evidence | Meaning |
|---|---:|---|
| Durable failed sync queue | `failed_visible` rises `0 → 1 → 2 → 3 → 4`, remains `4` through process recreation and near session end | Four unresolved durable queue entries exist |
| Settings constraint failure | One `POST /user_settings` returned HTTP `400`; PostgreSQL emitted SQLSTATE `23514` for `user_settings_key_check` | At least one client/server setting-key contract violation occurred |
| Maintenance conflicts | Three operation-specific business conflicts returned HTTP `200` transport responses but became failed-visible | Transport success did not mean business success |
| Duplicate insert flow | Six logical failed POSTs: four `maintenance_plans`, two `maintenance_plan_metadata`; each represented by paired Edge `409` and PostgreSQL `23505` records | RPC-created rows re-entered the generic writer; batch fallback amplified attempts |
| UMP misconfiguration | “No consent forms configured” occurred twice, once per process | Publisher-side consent form configuration is missing for the tested app ID |
| SSV debug-shaped retries | Nine HTTP `400` deliveries in groups `4/4/1` | Non-success responses caused repeated debug-shaped callback delivery |
| Startup jank | 84 skipped frames; first frame 1,508 ms | Cold startup has significant pre-first-frame work |
| Faster second process | Second first frame 127 ms | One later process was faster; cause is not established |
| Process stability | First process killed with reason `remove task`; no crash/ANR/fatal signal in interval | No crash or ANR in the captured window |
| Privacy exposure | Unfiltered all-buffer logcat plus full ad/callback diagnostics and unrelated device/app data | Current capture/logging procedure is unsafe for broad sharing |

### Confirmed repository evidence at audited commit

| Repository fact | Implication |
|---|---|
| Client remote setting allowlist includes `permission_education_seen_v2`; migration constraint omits it | This is the strongly supported cause of the observed settings rejection, but the rejected request body is absent |
| Maintenance completion already has typed outcomes and a one-retry path | Fix observability/resolution, not the contract shape |
| Failed-visible rows already persist error code/message fields | Surface these safely rather than adding a parallel error store |
| Batch insert returns an ambiguous/null result on `23505`, then coordinator retries rows individually | Existing-row recovery produces a second insert attempt per row |
| SSV handler verifies signatures before its current setup/no-op logic; settlement has replay controls | Preserve verification order and replay protections |

### Facts that remain unproven

- The rejected settings payload was definitely `permission_education_seen_v2`.
- The audited repository exactly matches the captured APK or deployed Supabase code.
- The three maintenance conflicts were application bugs rather than legitimate multi-device semantic conflicts.
- Debug-shaped SSV requests passed signature validation.
- Debug traffic received or did not receive point credit conclusively; no credit was observed, but relevant database rows were not supplied.
- Eight realtime WebSocket upgrades were harmful reconnect churn.
- Cloud hydration caused first-frame jank. It began about 19 seconds after the first frame and therefore did not cause that delay.

---

## 4. Preflight: inspect before modifying

Complete these steps first and record the results in the final implementation report.

1. Run `git status`, identify the current branch and full commit SHA, and compare it to the audited commit.
2. Locate the current equivalents of:
   - `lib/src/core/sync/sync_dtos.dart`
   - `lib/src/core/database/app_database.dart`
   - `lib/src/core/sync/local_sync_store.dart`
   - `lib/src/core/sync/sync_coordinator.dart`
   - `lib/src/core/sync/supabase_sync_gateway.dart`
   - `lib/src/features/monetization/monetization.dart`
   - `supabase/functions/admob-ssv-handler/index.ts`
   - setting, maintenance-completion, point-debit, and SSV migrations
3. Inspect migrations created after `20260803120000_add_permission_education_setting.sql`. Do not add a duplicate fix if a later migration already resolves the contract.
4. Inspect the current `create_task_with_point_debit` response and its Dart DTO. Determine whether canonical plan/metadata rows are already returned.
5. Inspect current batch-write result types and `23505` handling. Confirm whether the null/fallback amplification still exists.
6. Inspect current maintenance conflict UI and local failed queue schema. Confirm which fields are stored and which are exposed.
7. Inspect the SSV handler’s exact signature-verification order, debug/setup probe logic, status mapping, and tests.
8. Run the repository’s existing formatter, analyzer, unit tests, database tests, Edge Function tests, and integration tests before changing anything. Preserve baseline failures separately from introduced failures.
9. Determine how UMP/AdMob publisher configuration is managed. The consent form itself is an operator action and may not be changeable from code.
10. Check whether release builds can enable Google Mobile Ads verbose debug output. Identify all flags, initialization paths, and capture scripts that permit it.

---

# 5. Implementation work order

## P0-A — Repair the client/database settings-key contract

### Problem

The audited Dart sync allowlist includes `permission_education_seen_v2`, while the database check constraint recreated by `20260803120000_add_permission_education_setting.sql` omits it. Runtime evidence shows one `user_settings_key_check` violation immediately before the first durable failed-visible mutation.

### Required implementation

1. Create a **new forward migration** that aligns the production-equivalent `user_settings_key_check` with the complete current set of remotely synchronized keys.
2. Preserve both `permission_education_seen` and `permission_education_seen_v2` until product semantics are explicitly confirmed. Do not delete or rewrite existing rows automatically.
3. Reload the PostgREST schema after replacing the constraint.
4. Add client-side validation that rejects an unknown remote setting key **before enqueueing** a mutation.
5. Add a contract test proving every client-declared remotely synchronized setting key is accepted by the production-equivalent database schema.
6. Add a negative test proving an undeclared key is rejected by the client before it reaches the outbox.
7. Add a safe recovery path for the existing failed settings mutation:
   - inspect the stored type and error code;
   - retry only after the schema is compatible;
   - preserve the row until success or an explicit, evidence-based dismissal;
   - never bulk-clear failed rows.

### Migration shape

Adapt this to the current schema. Do not copy it without verifying the full current key list.

```sql
begin;

alter table public.user_settings
  drop constraint if exists user_settings_key_check;

alter table public.user_settings
  add constraint user_settings_key_check
  check (key in (
    'theme',
    'app_language',
    'app_language_explicit',
    'theme_time_of_day_enabled',
    'notifications_enabled',
    'notification_preferences',
    'onboarding_completed',
    'permission_education_seen',
    'permission_education_seen_v2',
    'home_location'
  ));

notify pgrst, 'reload schema';
commit;
```

### Acceptance criteria

- Every currently declared remote setting key inserts successfully against a clean production-equivalent schema.
- An unknown key is rejected locally and never enters the outbox.
- No new `23514 user_settings_key_check` event occurs in the integration reproduction.
- A previously failed valid settings mutation can be retried safely and acknowledged.
- Existing v1/v2 rows are preserved unless a separately reviewed deterministic migration is implemented.

### Rollback/safety

- Make the migration additive with respect to accepted values.
- Do not remove accepted keys in the same release.
- If current product semantics require collapsing v1/v2, implement that as a separate reviewed data migration with deterministic conflict rules.

---

## P0-B — Add a safe failed-mutation diagnostic and resolution surface

### Problem

Four failed-visible rows persisted through process recreation. Existing storage reportedly contains error code/message fields, but runtime logs and the user-facing resolution path do not expose enough information to determine what happened or choose a safe action.

### Required implementation

1. Add a read-only, privacy-safe diagnostic export for failed mutations. For each row include only:
   - mutation type/category;
   - state;
   - short one-way operation fingerprint;
   - created/updated timestamps or age;
   - attempt count;
   - `last_error_code` category;
   - sanitized reason category;
   - retryable flag;
   - payload hash, never the payload;
   - supported resolution actions.
2. Add reason-specific resolution behavior:
   - retry after a known compatible schema fix;
   - refresh/re-evaluate for retryable stale revision;
   - acknowledge an already-applied idempotent result;
   - present an explicit conflict action for semantic incompatibility;
   - dismiss only with an explicit user/admin action and audit event.
3. Preserve exact cause and resolution state across process death/relaunch.
4. Ensure resolving one row cannot clear unrelated rows.
5. Add a diagnostic screen or controlled support export reachable only through an appropriate debug/support path.
6. Add metrics for current failed-visible count, oldest age, type, and sanitized reason.

### Required structured event

Use existing logger conventions and a schema version. Example:

```json
{
  "event": "sync_mutation_result",
  "schema_version": 1,
  "operation_fingerprint": "short one-way digest",
  "mutation_type": "maintenance_completion",
  "result": "failed_visible",
  "reason": "occurrence_changed",
  "retryable": false,
  "attempt": 1,
  "queue_age_ms": 1234,
  "resolution": "user_decision_required",
  "process_instance": "ephemeral random ID"
}
```

### Acceptance criteria

- A support engineer can identify the type and reason of each failed row without raw user data.
- Process recreation preserves the same reason and available action.
- Resolving one mutation changes only that mutation.
- Export contains no raw UUIDs, entity IDs, values, titles, notes, dates, addresses, paths, tokens, or URLs.
- `sync_failed_visible_current` returns to zero only after each row is legitimately resolved.

---

## P0-C — Configure UMP consent and enforce fail-closed client behavior

### Problem

UMP reported twice that no consent form was configured for the installed AdMob app ID. The application reduced the detailed diagnostic to a generic `FormError`.

### Operator action

The coding agent may not have access to AdMob/UMP console configuration. Record this as a blocking operator action:

- Configure and publish the appropriate consent message/form for the production AdMob application.
- Verify regulated and non-regulated test geography behavior using a release-like build.

### Required code changes

1. Keep ad initialization and requests gated behind authoritative consent readiness.
2. Fail closed when UMP reports missing/misconfigured forms, unavailable consent state, or an unrecoverable consent error.
3. Emit a controlled diagnostic category such as `publisher_form_missing`, not only `FormError`.
4. Do not log the AdMob app ID or full SDK error text if it contains identifiers.
5. Ensure remote ad-disable configuration can halt ads without bypassing consent.
6. Add tests for:
   - form available and consent obtained;
   - form not required;
   - form missing/misconfigured;
   - network failure;
   - stale cached consent;
   - app restart.

### Acceptance criteria

- No ad request is made before the application is permitted to request ads.
- Missing form configuration produces a sanitized actionable diagnostic and leaves ads disabled.
- The release-like geography test no longer produces the publisher misconfiguration after console configuration.
- There is no fallback that silently treats consent failure as consent success.

---

## P0-D — Stop privacy-sensitive release logging and unsafe capture behavior

### Problem

The supplied Android capture contains 88,432 physical lines, including historical radio/event buffers, unrelated applications, device/carrier/network information, and complete Google Mobile Ads diagnostic material. The Supabase export includes complete callback URLs and signatures. These artifacts are sensitive.

### Required implementation

1. Disable Google Mobile Ads verbose/debug request logging outside isolated test builds.
2. Ensure release builds cannot enable raw ad debug logging through an accidental runtime flag.
3. Add a centralized release-log redaction policy and automated scanner.
4. Replace complete identifiers with short one-way fingerprints only when correlation is required.
5. Provide a controlled capture script that:
   - clears relevant buffers correctly;
   - captures only HomePilot, lifecycle, crash/ANR, Choreographer, Flutter, and Supabase-relevant tags;
   - avoids a fixed PID-only filter so process recreation remains visible;
   - redacts URLs, UUIDs, cookies, signatures, tokens, and bearer values;
   - deletes the unredacted temporary file after producing the protected output.
6. Add retention/access guidance for diagnostic exports.
7. Ensure synthetic fixtures are used in committed tests; never commit copied production callback/query data.

### Acceptance criteria

- Automated scan of release logs finds no token, cookie, signature, complete URL, UUID, project hostname, object path, device serial, user-entered text, or raw row ID.
- Controlled capture still shows process start/death, first-frame timing, structured sync results, and crash/ANR signals.
- Raw GMA debug output is impossible in production/release configuration.
- Diagnostic artifacts are explicitly labeled sensitive and access-controlled.

---

## P1-A — Make server-authoritative task creation operation-aware

### Problem

Two of four observed `create_task_with_point_debit` calls produced this sequence:

1. RPC commits authoritative plan/metadata rows.
2. Realtime announces inserted rows.
3. Pending local generic inserts remain queued.
4. Batch insert hits `23505`.
5. Current batch path returns an ambiguous/null result.
6. Coordinator retries the same existing row individually, causing a second insert attempt.
7. Client fetches the canonical row and patches it.

This produced six logical failed insert requests: four plan and two metadata. It recovered in the captured session, but uses constraint failures as ordinary control flow and creates stale-patch risk, latency, and noise.

### Target behavior

A server-authoritative composite RPC must acknowledge all local mutations covered by that operation. Its canonical result must be applied atomically to local state, and a realtime echo must merge idempotently without re-enqueueing a write.

### Required backend changes

1. Make the task-creation RPC return either:
   - canonical `maintenance_plans` and `maintenance_plan_metadata` rows; or
   - enough stable identifiers for the client to fetch the canonical aggregate immediately.
2. Prefer returning canonical rows to remove an extra round trip.
3. Preserve all existing operation-ID idempotency and point-debit locking behavior.
4. Keep response additions backward-compatible during rollout.
5. On a duplicate RPC invocation with the same operation ID, return the same authoritative aggregate and `already_processed=true` or equivalent.

Illustrative response extension:

```sql
return jsonb_build_object(
  'task_id', plan_id,
  'balance', next_balance,
  'charged', charge,
  'already_processed', false,
  'plan', to_jsonb((
    select p from public.maintenance_plans p
    where p.user_id = caller_id and p.id = plan_id
  )),
  'metadata', (
    select to_jsonb(m) from public.maintenance_plan_metadata m
    where m.user_id = caller_id and m.plan_id = plan_id
  )
);
```

### Required client/local-store changes

1. Represent server-authoritative creation as an explicit composite operation with:
   - stable operation ID;
   - covered entity keys;
   - covered outbox mutation IDs or a deterministic association.
2. After the RPC succeeds, execute one SQLite transaction that:
   - validates and saves canonical plan/metadata rows;
   - updates local shadows/revisions;
   - acknowledges only the covered pending mutations;
   - records the operation result;
   - leaves unrelated mutations untouched.
3. Treat later realtime delivery as an idempotent canonical merge.
4. On an uncertain timeout or lost response, retain the same operation ID and retry the RPC. Do not issue ordinary inserts.
5. If the RPC confirms `already_processed`, apply the returned/fetched canonical aggregate and acknowledge covered mutations exactly once.

Illustrative local flow:

```dart
final operation = await localDrafts.prepareTaskCreation(input);

final result = await monetization.createTask(
  operation.rpcPayload,
  operationId: operation.operationId,
);

await database.transaction(() async {
  final canonical = result.hasCanonicalAggregate
      ? result.canonicalAggregate
      : await syncGateway.fetchTaskAggregate(result.taskId);

  await localStore.applyCanonicalTask(canonical);
  await localStore.acknowledgeCreationMutations(
    operationId: operation.operationId,
    entityIds: canonical.entityIds,
  );
});
```

### Required generic-writer changes

1. Replace ambiguous/null batch outcomes with a typed result.
2. For the expected primary-key-existing case, fetch/merge canonical rows directly instead of blindly issuing an individual second insert.
3. Do not classify all unique violations identically. Capture the constraint category safely.
4. Bound conflict recovery and make every fallback observable.
5. Add a metric for unexpected server-created-row duplicate insert attempts. The release target is zero.

Illustrative result type:

```dart
sealed class BatchWriteResult {
  const BatchWriteResult();
}

final class BatchWriteSuccess extends BatchWriteResult {
  const BatchWriteSuccess(this.rows);
  final List<CanonicalRow> rows;
}

final class BatchWriteConflict extends BatchWriteResult {
  const BatchWriteConflict({required this.reason});
  final BatchConflictReason reason;
}
```

### Required tests

- Realtime arrives before RPC response.
- RPC response arrives before realtime.
- RPC commits but response is lost.
- RPC is retried with the same operation ID.
- Process dies after commit but before local acknowledgment.
- Duplicate realtime delivery.
- Metadata absent/present.
- Existing canonical row has a newer revision.
- Two concurrent UI submissions with the same operation ID.
- Two distinct operation IDs cannot double-debit or create duplicate task rows.

### Acceptance criteria

- One logical task creation produces one persisted plan and at most one metadata row.
- No generic `POST maintenance_plans` or `POST maintenance_plan_metadata` occurs after the RPC has authoritatively created those rows.
- Zero expected `409/23505` events in all ordering tests.
- Lost responses do not cause double debit, duplicate rows, or ordinary insert fallback.
- Realtime echo is idempotent.
- Local canonical rows, shadows, outbox acknowledgments, and wallet result remain consistent across process death.

---

## P1-B — Expose existing maintenance conflict outcomes safely

### Problem

Three completion operations became durable failed-visible rows after typed business conflicts. The transport status was HTTP `200`. The audited repository already models typed outcomes and persists reason fields, but the captured logs emitted only operation fingerprint and `retryable=false`.

### Required implementation

1. Use the existing RPC/Dart outcome fields. Do not redesign the response unless a field is genuinely missing in the current code.
2. Emit a sanitized structured result event containing:
   - operation fingerprint;
   - typed status;
   - conflict reason category;
   - retryable flag;
   - expected and current revision numbers if safe;
   - resolution chosen;
   - whether canonical rows were applied;
   - queue age/attempt.
3. Map each known typed outcome to deterministic behavior:
   - **applied**: save canonical state and acknowledge exactly once;
   - **already applied**: save canonical state and acknowledge idempotently;
   - **retryable stale revision**: targeted pull/re-evaluation and at most one safe retry when the existing contract says retryable;
   - **non-retryable semantic conflict**: preserve failed-visible row, reconcile optimistic state/preimage, and present a reason-specific action;
   - **unknown outcome**: fail closed, preserve diagnostics, do not blind-retry.
4. Ensure the UI can distinguish at minimum:
   - task already completed elsewhere;
   - occurrence/schedule changed;
   - task deleted/archived remotely;
   - revision changed and retry is safe;
   - unknown conflict requiring support.
5. Add a controlled “refresh and review” action rather than a generic infinite retry.
6. Add metrics by typed status and reason.

Illustrative event:

```dart
AppLogger.warning(
  'sync_maintenance_completion_result',
  fields: {
    'operation': diagnosticId(mutation.operationId),
    'status': result.status.name,
    'reason': result.conflictReason ?? 'none',
    'retryable': result.retryable,
    'expected_revision': expectedRevision,
    'current_revision': result.currentPlanRevision,
    'resolution': selectedResolution.name,
  },
);
```

### Required tests

- Applied.
- Already applied.
- Retryable stale revision with exactly one retry.
- Non-retryable occurrence changed.
- Remote deletion/archive.
- Double tap.
- Two-device completion/edit race.
- Process death before and after local reconciliation.
- Unknown/forward-compatible reason.

### Acceptance criteria

- Every failed completion row has a reason category and supported next action.
- No semantic conflict is retried blindly.
- Already-applied operations do not remain failed-visible.
- Optimistic completion state is reconciled deterministically.
- Process recreation preserves exact reason/action.
- Logs contain no raw plan, record, user, or date values.

---

## P1-C — Harden AdMob SSV debug callback handling

### Problem

Nine debug-shaped SSV requests containing sentinel values received HTTP `400` in three transaction groups (`4/4/1`). The Supabase export does not prove that signatures were valid. A blanket sentinel bypass would be unsafe. The audited repository verifies signatures before its existing setup-probe logic and has meaningful replay controls.

### Required implementation

1. Instrument the validation pipeline with privacy-safe stages:
   - envelope parsed;
   - key selected;
   - signature valid/invalid;
   - timestamp valid/invalid;
   - ad-unit/reward mapping valid/invalid;
   - debug classifier accepted/rejected;
   - replay/duplicate decision;
   - settlement invoked/skipped;
   - final HTTP status.
2. Add a **narrow verified debug no-op** only if current product/test requirements confirm the sentinel shape is expected.
3. The no-op branch must execute only after:
   - successful parsing;
   - trusted key lookup;
   - successful ECDSA signature verification;
   - bounded timestamp validation;
   - expected ad unit and reward shape validation;
   - both required sentinel/debug fields match the documented test shape;
   - any additional expected user-agent/network constraints are satisfied.
4. Accepted verified debug callbacks must:
   - return HTTP `200`;
   - set `credited=false`;
   - skip settlement RPC and all reward/point writes;
   - emit only a one-way transaction fingerprint and decision category.
5. Invalid signatures must remain rejected, normally `401` according to existing policy.
6. Malformed or production-invalid callbacks must remain `400`.
7. Preserve replay protection and payload-equality checks for production callbacks.
8. For an already-settled valid production callback, return the existing idempotent success response and never credit twice.

Illustrative branch:

```ts
// Only after parsing, key lookup, ECDSA verification, and bounded validation.
if (isNarrowVerifiedDebugCallback(request, parsed, now())) {
  emit("info", "debug_callback_accepted", {
    transaction_fingerprint: await identifierFingerprint(parsed.transactionId),
    database_operation: "skipped",
  });

  return respond(200, {
    accepted: true,
    credited: false,
    duplicate: false,
    mode: "verified_debug_noop",
  });
}
```

### Required tests

- Valid signed debug callback → `200`, no DB write.
- Invalid signature with sentinel fields → rejected, no bypass.
- Missing one sentinel field → not classified as debug no-op.
- Stale/future timestamp → rejected.
- Unknown key ID → rejected.
- Unknown ad unit or reward mismatch → rejected.
- Production callback → normal settlement path.
- Replay of same valid production payload → idempotent success, no second credit.
- Reuse of transaction ID with altered payload → rejected.
- Debug callback replay → `200` no-op with no writes.
- Handler logs contain no callback query, signature, key ID, raw transaction ID, custom data, user ID, or complete URL.

### Acceptance criteria

- Verified debug traffic no longer creates repeated `400` delivery storms.
- Sentinel values alone never bypass authentication.
- No debug callback invokes settlement or changes point/reward tables.
- Invalid signatures never reach debug classification success.
- Production replay/idempotency behavior is unchanged or stronger.

---

## P1-D — Improve ad-load and realtime diagnostics

### Ad-load diagnostics

Current app logs collapse three rewarded and three rewarded-interstitial load failures into generic `LoadAdError` warnings.

Implement privacy-safe fields:

- ad format category;
- controlled SDK error domain/code category;
- retry count;
- backoff bucket;
- consent-ready flag;
- network availability category;
- terminal/retryable classification.

Do not log ad unit IDs, response identifiers, full SDK messages, URLs, or request bodies.

Test no-fill, network unavailable, invalid request/configuration, internal error, and success-after-backoff.

### Realtime lifecycle diagnostics

Eight successful WebSocket upgrades were observed, but no close reasons or active-channel counts were available. Do not assume harmful churn.

Add:

- ephemeral process instance ID;
- ephemeral channel lifecycle ID;
- connect/subscribe/ready/close/reconnect events;
- close reason category;
- active subscribed channel gauge;
- channel replacement reason;
- backoff attempt.

Acceptance target: at most one active subscribed sync channel per authenticated process/account unless the architecture explicitly requires more.

---

## P1-E — Add startup tracing and performance budgets

### Problem

The first observed process reported 84 skipped frames and a 1,508 ms first frame. Cloud restoration began about 19 seconds later, so it did not cause the first-frame delay. The second process was 127 ms, but one sample does not prove caching or another cause.

### Required implementation

1. Add release-safe startup spans for:
   - process/main entry;
   - Flutter engine readiness where measurable;
   - plugin registration;
   - dependency injection/service graph setup;
   - database open/migrations;
   - secure storage reads;
   - auth/session restoration;
   - Sentry/telemetry initialization;
   - first widget build;
   - first frame;
   - initial hydration start/end;
   - cloud-ready state.
2. Ensure pre-first-frame work is minimized and noncritical initialization is deferred.
3. Do not move correctness-critical work off the main thread without preserving ordering and failure handling.
4. Add Android API 29 cold-start benchmarks on a representative slow device class and at least one current device class.
5. Record median, p90, and p95 across repeated cold and warm launches.
6. Set explicit budgets based on baseline data; do not infer a cause from the single supplied capture.

### Acceptance criteria

- Startup traces identify the dominant pre-first-frame contributors.
- A repeatable benchmark reproduces baseline and verifies improvement.
- First-frame p95 stays within the agreed device-class budget.
- Cloud-ready time is tracked separately from first-frame time.
- No startup trace includes user or device identifiers.

---

# 6. Medium-term architecture requirements

These may be implemented in the same change set if scope permits; otherwise create tracked follow-up issues with owners and acceptance criteria.

## A. Generate the remote setting contract from one source

Choose a canonical machine-readable manifest or generation pipeline that produces both:

- the Dart remote setting enum/allowlist; and
- the SQL check constraint or equivalent schema validation.

CI must fail when the client and production-equivalent schema diverge.

## B. Model server-authoritative composite operations explicitly

The outbox model should represent an operation and the entity mutations it covers. Successful authoritative RPC completion must acknowledge the covered set atomically. Generic row writers must not replay rows already committed by that operation.

## C. Add cross-layer privacy-safe correlation

Propagate one-way operation/request fingerprints through app, Edge Function, and database diagnostics. The goal is to map one logical operation to its platform records without raw IDs.

## D. Add runtime provenance

- Expose a signed build Git SHA/build identifier in the APK’s diagnostic metadata.
- Record deployed migration versions and Edge Function source hashes/timestamps.
- Make support exports include provenance identifiers, not secrets.

## E. Add reliability/SRE metrics

| Metric | Type | Suggested alert |
|---|---|---|
| `sync_failed_visible_total{reason,type}` | Counter | Any new unknown reason |
| `sync_failed_visible_current` | Gauge | `>0` for 15 minutes |
| `sync_oldest_failed_age_seconds` | Gauge | `>3600` |
| `sync_rpc_created_duplicate_insert_total{table}` | Counter | `>0` in release traffic |
| `maintenance_completion_result_total{status,reason}` | Counter | Sudden conflict-rate increase |
| `ssv_request_total{decision,status}` | Counter | Any 5xx; invalid-signature spike |
| `ssv_duplicate_delivery_total` | Counter | Abnormal growth by fingerprint |
| `realtime_channel_active` | Gauge | `>1` per process/account |
| `realtime_channel_replacement_total{reason}` | Counter | Unknown reason `>0` |
| `startup_first_frame_ms` | Histogram | p95 above agreed device SLO |
| `startup_cloud_ready_ms` | Histogram | p95 regression |
| `log_redaction_violation_total{category}` | Counter | Any release violation |

---

# 7. Issues to monitor, not blindly “fix”

## Realtime upgrades

Eight HTTP `101` upgrades occurred. This is a count, not proof of harmful reconnect churn. Add lifecycle instrumentation first. Change reconnect behavior only if the new evidence shows overlapping channels, rapid replacement, data-integrity impact, or excessive network/battery use.

## PostgREST timeout-manager messages

Ten successful/`200` records contained “Thread killed by timeout manager”; seven fell in the strict app overlap and three followed it. No request context or user impact is proven. Monitor and correlate with provider metrics before modifying application behavior.

## Process stability

No crash, ANR, fatal signal, or app OOM was observed in the ten-minute capture. Continue normal crash/ANR monitoring; do not create speculative crash fixes from this evidence.

---

# 8. Mandatory automated test matrix

| Area | Test | Expected result |
|---|---|---|
| Settings contract | Every Dart-declared remote key against local production-equivalent DB | All accepted |
| Settings contract | Unknown key | Rejected before enqueue |
| Settings recovery | Previously failed valid key after migration | Safely retried and acknowledged |
| Queue durability | Process death with failed row | Exact reason/action preserved |
| Queue isolation | Resolve one of several failed rows | Only selected row changes |
| Maintenance | Applied | Canonical rows saved; queue acknowledged once |
| Maintenance | Already applied | Idempotent acknowledgment; no failed-visible row |
| Maintenance | Retryable stale revision | One targeted safe retry only |
| Maintenance | Semantic conflict | Reason/action persisted; optimistic state reconciled |
| Maintenance | Unknown reason | Fail closed; no blind retry |
| Task creation ordering | Realtime before RPC response | Zero generic duplicate POSTs |
| Task creation ordering | RPC response before realtime | Zero generic duplicate POSTs |
| Task creation uncertain commit | Response lost after commit | Same operation ID retried; no double debit/insert |
| Task creation process death | Death before local ack | Relaunch reconciles idempotently |
| Realtime | Duplicate delivery | Local state/shadow/outbox unchanged after first merge |
| Batch writer | Existing primary key | Typed canonical-fetch recovery, not second blind insert |
| Batch writer | Other unique constraint | Distinct error path; no incorrect canonical recovery |
| SSV debug | Valid signed narrow debug shape | `200`, no DB write, `credited=false` |
| SSV debug | Invalid signature + sentinel | Rejected; no debug bypass |
| SSV production | First valid callback | One settlement |
| SSV production | Exact replay | Idempotent success, no second credit |
| SSV production | Same transaction, altered payload | Rejected |
| Consent | Missing UMP form | Ads fail closed; sanitized actionable diagnostic |
| Consent | Form available/not required | Correct ad-gating behavior |
| Ad load | No-fill/network/config/internal | Controlled categories and backoff |
| Realtime lifecycle | Reconnect/replacement | At most one active channel; reason recorded |
| Logging | Release log DLP scan | No prohibited sensitive categories |
| Startup | Repeated API 29 cold launches | Median/p90/p95 recorded; budget enforced |
| Provenance | Build diagnostic | Full audited build ID available without secrets |

---

# 9. Integration reproduction gate

After unit and database tests pass, run a targeted release-like reproduction with synthetic/test data.

1. Start from a clean local database and production-equivalent Supabase schema.
2. Exercise every remote setting key.
3. Create point-debit tasks under all RPC/realtime ordering variants.
4. Force an uncertain RPC response and retry with the same operation ID.
5. Exercise each maintenance completion typed outcome.
6. Kill and relaunch the app with pending and failed mutations.
7. Test UMP regulated and non-regulated geography configurations.
8. Test valid/invalid/replayed SSV callbacks using synthetic signed fixtures.
9. Run controlled ad-load failure simulations.
10. Capture only privacy-safe structured logs.

### Release gate counters

The reproduction must show:

- `user_settings_key_check` violations: **0**
- server-created task duplicate generic inserts: **0**
- unexpected `409/23505` during task creation: **0**
- failed-visible rows without known reason/action: **0**
- debug SSV settlement writes: **0**
- invalid-signature debug bypasses: **0**
- active realtime sync channels per process/account: **≤1**
- release log redaction violations: **0**
- crashes/ANRs introduced by the patch: **0**

---

# 10. Suggested commit structure

Keep changes reviewable and avoid mixing unrelated refactors.

1. `fix(db): align user_settings key constraint and add contract tests`
2. `feat(sync): add sanitized failed-mutation diagnostics and resolution`
3. `fix(sync): acknowledge RPC-created task aggregate atomically`
4. `fix(sync): replace duplicate batch fallback with typed recovery`
5. `fix(sync): expose maintenance conflict reasons and actions`
6. `fix(ads): enforce UMP fail-closed diagnostics`
7. `fix(ssv): add verified debug no-op and validation-stage telemetry`
8. `chore(logging): disable sensitive release diagnostics and add DLP tests`
9. `perf(startup): add startup spans and benchmark coverage`
10. `chore(provenance): expose build/deployment identifiers`

Rebase or combine commits only if repository policy requires it. Preserve a clear migration and security review boundary.

---

# 11. Final report required from the coding agent

At completion, provide:

1. Current repository SHA and how it differs from audited commit `e5bbddc98fcc2f0843008f8c0152c3b967492a1b`.
2. Exact files changed.
3. New migration names and whether they are backward-compatible.
4. Explanation of how existing failed rows are preserved and repaired.
5. Explanation of the new task-creation acknowledgment transaction.
6. Explanation of `23505` classification and why no second blind insert occurs.
7. Maintenance outcome-to-resolution mapping.
8. SSV verification order and status-code table.
9. Proof that debug no-op performs no settlement/database write.
10. Consent gating behavior and the remaining AdMob/UMP console action.
11. Log-redaction rules and DLP test result.
12. Startup benchmark results, including median/p90/p95 and device/API details.
13. Full test commands and pass/fail results.
14. Any unresolved risk, missing access, or deployment prerequisite.
15. Rollback procedure for each migration and feature flag.

Do not state that a defect is fixed merely because code compiles. Tie every completion claim to an automated test or controlled reproduction result.

---

# 12. Source evidence map

This brief was reconciled from the following supplied artifacts:

| Artifact | Role | SHA-256 |
|---|---|---|
| `HomePilot_independent_adversarial_audit_2026-08-04(2).md` | Primary corrected synthesis and repository audit | `a4776fc8645073ed3f28cae39426cbdd985e15ad96edc4d75d26f127b66c324e` |
| `claim_verification(2).csv` | Claim-by-claim confirmation/correction matrix | `5a1d43d330b9fe10dc630a0e15d7b5ef01abc021dda1a9c52bd63c70821ed6a2` |
| `corrected_evidence_index(2).csv` | Corrected raw/repository evidence index | `b7f0b3b1e260dd8a262903caac9176864f7794ada84f06807400436901558040` |
| `HomePilot_independent_forensic_review(3).md` | Detailed forensic review and code recommendations | `07b26bec15383467e25f7cb226d7a3350cda09c36495384222f44cef115b1dc6` |
| `deep-research-report(3).md` | Earlier analysis; useful but superseded where corrected | `932af95153110885a15cf94bbfb2141cb7de54a8e4b970ecdb6af49d6cc41d44` |
| `HomePilot_logs_2026-08-04_02-32-15(4).txt` | Raw Android evidence | `96445d7633505d5f0e2c24c6307953b5c68c55d4b8ba0f85f648f8ca0a961e34` |
| `supabase_logs(7).json` | Raw Supabase evidence | `bbf2e3078d7b366c893a43bddb0bd8902309b6a8aee7c2aaf7e1a08ae58bf98f` |
| `HomePilot_evidence_index(3).csv` | Original navigation index | `68d8fbdee55ab652fde60522091b34f4842bcfa48354fc48ce31a52f626f942a` |
| `HomePilot_audit_SHA256SUMS(2).txt` | Integrity manifest for primary audit and appendices | `6171118dbfb57d1e8ed710329471b8d2c56b36e55e4535982c1d20add967540c` |

### Reproduced quantitative checks

- Android physical lines: **88,432**
- Android standard threadtime records: **87,916**
- Android non-threadtime lines: **516**
- Supabase events: **387**
- Supabase status counts: `200=307`, `204=36`, `201=6`, `101=8`, `400=10`, `409=6`, `23505=6`, `23514=1`, informational `00000=7`
- Persistent failed-visible mutations: **4**
- Maintenance conflict operations: **3**
- Logical duplicate task-row insert requests: **6**
- Debug-shaped SSV deliveries: **9**, grouped `4/4/1`
- UMP missing-form occurrences: **2**
- First-process skipped frames: **84**
- First-frame durations: **1,508 ms** and **127 ms**
- Cloud restore duration: **7,594 ms**, beginning after first frame

### Evidence references used by this brief

- Android lines: `L6144`, `L6690`, `L6931`, `L9940`, `L10107`, `L10949`, `L11072`, `L11495-L11496`, `L14355`, `L16760-L16792`, `L19879-L20038`, `L24518-L24679`, `L48867-L49102`, `L49474`, `L49962`, `L50639-L50640`, `L51327`, `L83029-L83940`, `L85815-L86857`, `L88116`.
- Corrected evidence index: `EVID-001` through `EVID-038`.
- Repository references at audited commit:
  - `lib/src/core/sync/sync_dtos.dart`, approximately lines 390-405
  - `lib/src/core/database/app_database.dart`, approximately lines 300-380
  - `lib/src/core/sync/local_sync_store.dart`, approximately lines 1000-1120 and 1880-2140
  - `lib/src/core/sync/sync_coordinator.dart`, approximately lines 1100-1530
  - `lib/src/core/sync/supabase_sync_gateway.dart`, approximately lines 430-620
  - `lib/src/features/monetization/monetization.dart`
  - `supabase/migrations/20260803120000_add_permission_education_setting.sql`
  - `supabase/migrations/20260728145152_harden_maintenance_completion_idempotency.sql`
  - `supabase/migrations/20260801124625_create_points_rpc_and_reward_claims.sql`
  - `supabase/migrations/20260802095845_harden_admob_ssv_replay_validation.sql`
  - `supabase/functions/admob-ssv-handler/index.ts`

---

# 13. Completion definition

This remediation is complete only when:

- the setting contract is aligned and protected by CI;
- the existing failed queue is diagnosable and safely resolvable;
- RPC-created rows never enter the generic duplicate insert path;
- maintenance outcomes produce deterministic reason-specific behavior;
- verified debug SSV callbacks can be acknowledged without credit, while invalid callbacks remain rejected;
- consent failure remains fail-closed and the publisher form is configured;
- release logging and support captures pass automated privacy scans;
- startup performance is instrumented and benchmarked;
- runtime provenance is available;
- all mandatory tests and the integration reproduction gate pass.

