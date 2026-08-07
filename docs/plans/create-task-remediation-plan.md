# HomePilot Create Task Remediation Plan

**Status:** Completed; all implementation, RPC migration, Flutter state, operation journaling, metadata shape validation, and automated test validations are fully executed and verified.
**Repository:** `zuhak5/HomePilot`  
**Basis commit:** `e7d532ec8cf4cb6e64b11ca8b79777d3f63dff1f` (`main`, reverified before writing this plan)  
**Primary source:** Completed Create Task Bug Audit and the current repository implementation  
**Implementation constraint:** Historical deployed migrations are append-only. Do not edit them.  

This document is an execution plan, not an implementation. Symbols and file paths under **Planned** are the intended ownership boundaries for the remediation. If an implementation step discovers that a named symbol cannot be introduced without violating an existing contract, stop at that step, record the contradiction, and resolve it before continuing rather than silently redesigning the workflow.

The plan uses **MUST**, **SHOULD**, and **MAY** as normative terms.

---

# 1. Executive summary

The completed audit contains **17 confirmed Create Task bug IDs (`CTC-001` through `CTC-017`)** and **4 high-confidence risk IDs (`CTR-001` through `CTR-004`)**. Reverification against the current `main` commit found that 16 confirmed findings still exist as originally described. `CTC-011` remains actionable but its original wording was too broad: immediate task-creation reminder refresh failures are silently swallowed, but HomePilot already performs global reminder reconstruction at startup, app resume, and the daily WorkManager refresh. The remediation therefore narrows `CTC-011` to the missing immediate failure signal/guarantee and validates the existing eventual-repair path rather than introducing a second reminder queue without evidence.

The affected subsystems are:

- `PlanEditorDialog` and `_EditorSheetFrame` in `lib/main.dart`.
- Riverpod ownership of task-creation state.
- `OfflineCreationDraftStore` and point-wallet presentation in `lib/src/features/monetization/monetization.dart`.
- `DriftMaintenanceRepository.savePlan` in `lib/src/core/data/repositories.dart`.
- `LocalSyncStore.acknowledgeTaskCreationComposite` in `lib/src/core/sync/local_sync_store.dart`.
- Supabase point-creation RPCs and `creation_point_operations`.
- `point_wallets` and `point_transactions` financial-like invariants.
- Reminder reconstruction and scheduling.
- Localization, accessibility, error mapping, test coverage, and documentation.

The highest-severity blockers are:

1. **CTC-001 — Critical:** the effective August 6 task-creation RPC can raise SQLSTATE `42702` because the PL/pgSQL variable `plan_id` collides with the unqualified SQL column reference in the canonical metadata subquery. This currently prevents valid task creation. The exception occurs inside the RPC transaction, so its writes roll back atomically.
2. **CTC-002 — Critical:** the online operation ID and plan ID are widget-memory state. A server commit followed by response loss, process death, or widget disposal can lose the only client-side retry identity. A later submission may mint new IDs and create a second task with a second point debit.
3. **CTC-004 / CTC-005 — High:** server idempotency does not bind an operation ID to an immutable request fingerprint, and the second post-wallet-lock operation lookup does not repeat caller/entity/plan validation. Exact retries, key misuse, and concurrency are not deterministic enough for financial-like data.
4. **CTC-006 / CTC-007 / CTR-002 — High:** the client accepts weakly typed canonical responses and the current composite acknowledgement can delete plan/metadata outbox entries without proving that canonical records match the requested plan or that a newer local edit is not being discarded.
5. **CTC-008 — High:** local `savePlan` does not make the plan and metadata one Drift transaction.
6. **CTC-009 — High:** secure-storage draft persistence failures are swallowed while the UI can report that the draft was saved.

## Financial, authorization, and integrity blockers

| Failure class | Current risk | Required end state |
|---|---|---|
| Incorrect point balance | Realtime can lag the authoritative RPC balance (`CTC-015`). | Returned canonical wallet state is reflected immediately and later confirmed by Realtime. |
| Duplicate charge | Lost client operation identity after an uncertain commit (`CTC-002`). | A submitted operation is durable before the first request and every retry reuses the same operation ID and immutable payload. |
| Task creation without charging | Server currently owns price and performs task/debit atomically; no confirmed bypass. | Preserve server-authoritative price and RLS; direct charged inserts remain denied. |
| Charging without task creation | Current SQL transaction rolls back all writes on failure; post-commit local reconciliation can make the task appear missing locally. | Preserve cloud atomicity; never compensate a valid cloud task merely because local reconciliation failed. Reconcile until local state matches cloud. |
| Cross-user access | No confirmed canonical row leak, but `CTC-005` can return another operation's identifiers under a globally colliding operation ID if the second check races. | Every operation lookup validates caller, entity type, entity ID, and request fingerprint; same-operation concurrency is serialized. |
| Permanent local/cloud divergence | Weak canonical acknowledgement and nontransactional local writes (`CTC-006`–`CTC-008`, `CTR-002`). | Canonical server state is strictly validated and applied in one local reconciliation transaction without deleting newer mutations. |
| Unrecoverable queued/uncertain operation | Online submitted IDs are not durable (`CTC-002`, `CTR-001`). | Durable device-local creation journal survives restart and represents draft, unknown, accepted-needs-reconcile, rejected, and completed states. |

## Overall remediation strategy

The remediation MUST keep HomePilot's existing offline-first model while making **new server-authorized task creation a separately orchestrated workflow**:

- The **server remains authoritative** for whether the creation costs points, the balance transition, ownership, the task row, metadata row, ledger row, and server idempotency record.
- A **new singleton Riverpod `TaskCreationController`** owns Create Task submission across every entry point. `PlanEditorDialog` owns only form presentation/editing and delegates submission.
- Before any network submission, the controller persists an operation record containing the operation ID, plan ID, account scope, normalized exact request payload, and state in a **task-specific device-local operation store** backed by secure storage. This store replaces Create Task's direct use of the one-key `OfflineCreationDraftStore`; it does not enqueue a wallet mutation.
- A new task is **not inserted into Drift as a maintenance plan before server success**. Offline or unauthenticated creation remains an unfinished draft, matching the monetization architecture. Existing task edits remain local-first and continue to use normal Drift/outbox synchronization.
- After server success, `LocalSyncStore` strictly validates and reconciles canonical plan/metadata rows. It MUST preserve any newer generic plan/metadata mutation instead of deleting it blindly.
- The generic synchronization outbox MUST NOT represent an unpaid/unconfirmed new charged task.
- Reminder scheduling is post-commit derived state. Failure MUST NOT roll back a financially valid task; existing startup/resume/daily reconstruction is retained and explicitly regression-tested.
- The database repair is delivered as **forward migrations only**.

## Recommended implementation order

1. Phase 0: establish failing regression tests and capture the effective SQL definition.
2. Phase 1: ship the narrow `42702` forward migration and SQL tests.
3. Phases 2–4: harden database transaction, idempotency, concurrency, authorization, and RPC contract.
4. Phase 5: implement durable client orchestration, strict local reconciliation, and transactional `savePlan`.
5. Phase 6: migrate all Create Task UI paths to the controller and fix lifecycle/error/form behavior.
6. Phase 7: confirm derived-state, reminders, point display, and provider refresh behavior.
7. Phase 8: validate time, Arabic/RTL, keyboard, semantics, focus, and text scaling.
8. Phase 9: complete observability, documentation, and full validation.

## Pull-request strategy

Use **multiple staged pull requests**, not one large PR. The emergency database repair must be independently reviewable and deployable. Recommended delivery is four PRs:

1. Emergency SQL correctness (`CTC-001`).
2. Backend idempotency/contract/concurrency hardening (`CTC-004`, `CTC-005`, `CTC-013`, `CTC-014`, `CTR-003`, and security checks).
3. Client orchestration/local persistence/reconciliation (`CTC-002`, `CTC-006`–`CTC-010`, `CTC-012`, `CTC-015`, `CTC-017`, `CTR-001`, `CTR-002`).
4. UI/reminders/localization/accessibility/integration closure (`CTC-003`, narrowed `CTC-011`, `CTC-016`, `CTR-004` decision, full end-to-end validation).

Documentation affected by each behavioral PR must be updated in that same PR; do not defer all documentation to the last PR.

---

# 2. Scope

## Included confirmed bugs

All audit-confirmed Create Task IDs remain in scope:

| ID | Scope status after revalidation |
|---|---|
| CTC-001 | Included; fully reverified. |
| CTC-002 | Included; fully reverified. |
| CTC-003 | Included; fully reverified. |
| CTC-004 | Included; fully reverified. |
| CTC-005 | Included; fully reverified. |
| CTC-006 | Included; fully reverified. |
| CTC-007 | Included; fully reverified. |
| CTC-008 | Included; fully reverified. |
| CTC-009 | Included; fully reverified. |
| CTC-010 | Included; fully reverified. |
| CTC-011 | Included with narrower wording: immediate scheduling failure is swallowed; eventual global repair already exists and must be preserved/tested. |
| CTC-012 | Included; fully reverified. |
| CTC-013 | Included; cloud constraints and weaker client bounds reverified. |
| CTC-014 | Included; exception normalization remains incomplete. |
| CTC-015 | Included; returned balance is not deterministically projected into UI state. |
| CTC-016 | Included; save actions disable, but close/dismiss remains active and no explicit submitting semantics exist. |
| CTC-017 | Included; draft clear failures remain swallowed. |

## Included high-confidence risks

| ID | Status |
|---|---|
| CTR-001 | Included for verification and remediation. Source confirms no explicit application timeout and no durable unknown-outcome state; transport behavior still needs controlled testing. |
| CTR-002 | Included for deterministic interleaving test. Current acknowledgement deletes by plan ID and does not version-check the outbox. |
| CTR-003 | Included. Static schema evidence confirms only “valid JSON,” not “array of strings”; keep the audit risk label until a behavioral contract test demonstrates the observed local degradation. |
| CTR-004 | Included as an explicit product/transaction-semantics decision. It is nonblocking for the emergency repair. |

## Findings requiring additional verification

The following are not implementation assumptions; Phase 0 must resolve them:

- Exact transport timeout/cancellation behavior of the pinned `supabase_flutter`/PostgREST stack (`CTR-001`).
- The precise interleaving of a later local edit with canonical creation reconciliation (`CTR-002`).
- Runtime behavior when metadata list JSON is a scalar/object, including hydration and UI behavior (`CTR-003`).
- Product semantics for a monetization-config change while a request waits on a wallet lock (`CTR-004`).
- Whether supported signed-out users are intended to create permanent local-only tasks under the point-gated product. The current Create Task implementation requires the online monetization path; this plan preserves that behavior unless product ownership explicitly changes it.
- Availability and schema location of `pgcrypto.digest` in the repository's local Supabase stack before using SHA-256 in a migration. If unavailable, the hardening migration must enable `pgcrypto` in the approved extensions schema rather than substituting a weaker hash silently.

## Explicitly excluded

- Maintenance-completion bugs from the separate completion audit.
- Rewarded-ad settlement redesign except where it shares wallet-lock concurrency invariants.
- General asset-creation redesign. The asset creation RPC may receive the minimal shared operation-lock validation needed to protect the common `creation_point_operations` primary key, but asset UI/drafts are not otherwise redesigned here.
- The unrelated proposed sync-bundle/network optimization in `docs/request-audit-report.md`.
- Production deployment commands, production credentials, hosted project linking, or production data.
- A general rewrite of `lib/main.dart` beyond extracting task-creation ownership and wiring the existing entry points.
- Changing existing recurrence semantics. Creation validation and timezone round-tripping are tested; recurrence advancement behavior remains owned by the recurrence engine/completion workflow.
- A new generic task-creation queue that can blindly authorize charges later. This is explicitly prohibited by the monetization architecture.

## Assumptions

- `main` at `e7d532ec8cf4cb6e64b11ca8b79777d3f63dff1f` is the implementation baseline.
- The backend is authoritative for every new task's effective charge, including safety/free and emergency-free configuration cases.
- New task creation is not allowed to become a permanent local maintenance plan until the server transaction has succeeded. Offline work is a draft only.
- Existing task edits remain ordinary offline-first Drift mutations.
- A valid server commit is not refunded because local notification scheduling or local canonical application failed; the client reconciles instead.
- `creation_point_operations` is retained for replay/fraud prevention and is not routinely deleted when a client cleans up its local journal.
- Older clients may ignore new JSON response fields; therefore adding response fields is backward compatible. Removing existing response fields is not.

## Environmental limitations

The completed audit could not execute Flutter, Dart, local Supabase, PostgreSQL, Android notification APIs, or a device emulator in its environment. This plan therefore requires Phase 0 executable reproduction before any behavioral change. Source-level facts that were reverified are marked as such; runtime claims remain tests, not assumptions.

## Compatibility expectations

- Historical SQL migrations remain unchanged.
- The emergency function replacement must preserve the existing public signature `public.create_task_with_point_debit(jsonb)`.
- The hardened backend must continue accepting the currently deployed request shape while returning additional versioned/canonical fields.
- Legacy `creation_point_operations` rows without a request fingerprint remain replayable only under the existing caller/entity/entity-ID checks; the server cannot reconstruct a missing historical request hash and must not fabricate one.
- Generic sync upserts from older supported clients remain protected by existing RLS/authorization behavior.
- New clients may require the hardened response version only after the compatible backend migration is deployed and verified.

---

# 3. Audit source map

| Audit ID | Finding | Severity | Confidence/status | Evidence source | Subsystem | Relevant files | Relevant migrations | Relevant tests | Reverified |
|---|---|---:|---|---|---|---|---|---|---|
| CTC-001 | Ambiguous `plan_id` breaks effective task RPC | Critical | Confirmed | Effective final function contains `m.plan_id = plan_id` while declaring `plan_id` | PostgreSQL RPC | Supabase migration chain | `20260801124625...`, `20260803090000...`, `20260806150000...` | `supabase/tests/database/0012_points_monetization.test.sql` | Yes |
| CTC-002 | Online operation identity is not durable before RPC | Critical | Confirmed | `_creationOperationId` / `_creationPlanId` are widget fields; online path persists nothing before RPC | Client orchestration | `lib/main.dart`, monetization draft store | N/A | `test/widget_test.dart` lacks restart/timeout case | Yes |
| CTC-003 | Editor can be dismissed during charged RPC | High | Confirmed | `_EditorSheetFrame` close button always enabled; modal uses default dismiss/drag; `_save` uses `ref`/controllers after network await | UI lifecycle | `lib/main.dart` | N/A | `test/widget_test.dart` | Yes |
| CTC-004 | Idempotency key is not payload-bound | High | Confirmed | `creation_point_operations` stores no request hash | Server idempotency | SQL migrations, monetization client | `20260801124621...` plus RPC replacements | `0012_points_monetization.test.sql` | Yes |
| CTC-005 | Post-lock operation check omits identity validation | High | Confirmed | Second `select * into existing_operation` returns without caller/entity/plan checks | Server concurrency/auth | task/asset point RPCs | `20260801124625...`, `20260803090000...`, `20260806150000...` | `tool/test_points_concurrency.ps1` covers balance only | Yes |
| CTC-006 | Successful RPC response parser is permissive | High | Confirmed | `PointDebitResult.fromJson` defaults numeric/boolean fields and ignores `task_id` | RPC contract | `lib/src/features/monetization/monetization.dart` | final response migration | `test/monetization_test.dart` has no strict contract tests | Yes |
| CTC-007 | Canonical acknowledgement does not verify identities | High | Confirmed | `acknowledgeTaskCreationComposite` accepts nullable/wrong records and deletes by requested plan ID | Local reconciliation | `lib/src/core/sync/local_sync_store.dart` | N/A | `test/task_creation_sync_test.dart` happy path only | Yes |
| CTC-008 | Local plan and metadata write are not transactional | High | Confirmed | `savePlan` inserts/updates plan then calls `_savePlanMetadata` outside a surrounding transaction | Drift | `lib/src/core/data/repositories.dart` | N/A | `test/home_structure_repository_test.dart` | Yes |
| CTC-009 | Offline draft save failure can be reported as success | High | Confirmed | `OfflineCreationDraftStore.save` catches and logs all storage errors | Draft durability | `lib/src/features/monetization/monetization.dart`, `lib/main.dart` | N/A | `test/monetization_test.dart` tests happy store only | Yes |
| CTC-010 | Draft key overwrites/strands drafts | Medium | Confirmed | one context key `task_<user/local>_<asset/any>` stores one map | Draft/account scope | `lib/main.dart`, monetization store | N/A | missing | Yes |
| CTC-011 | Reminder refresh failure is not represented in create result | High in audit; narrowed | Confirmed narrower defect | create helper catches all; startup/resume and daily WorkManager already retry globally | Notifications | `lib/main.dart`, `notification_service.dart`, `reminder_schedule_reconciler.dart` | N/A | notification/widget tests | Partial: original “no durable recovery” wording disproven |
| CTC-012 | Actionable failures collapse to generic task update message | Medium | Confirmed | only insufficient points is specialized; `AppFailureCode.taskUpdate` fallback | Error UX | `lib/main.dart`, `app_failure.dart`, `supabase_failure.dart` | N/A | widget/error tests | Yes |
| CTC-013 | Client validation weaker than server constraints | Medium | Confirmed | UI checks presence/positive values but not all cloud max lengths/ranges | Validation | `lib/main.dart`, domain models | cloud plan/metadata migrations | unit/widget/SQL boundary tests missing | Yes |
| CTC-014 | RPC normalization omits predictable SQL failures | Medium | Confirmed | exception block maps only three error classes | Server errors | task RPC migration | final function migration | SQL error-contract tests missing | Yes |
| CTC-015 | Authoritative returned balance not immediately projected | Medium | Confirmed | result balance is unused; pill watches wallet Realtime stream | Monetization UI state | monetization feature, `lib/main.dart` | RPC response | wallet/widget tests | Yes |
| CTC-016 | Submitting/loading/accessibility state incomplete | Medium | Confirmed | save disabled, but close active; labels/progress/live-region not explicit | Accessibility/UI | `lib/main.dart`, ARBs | N/A | widget/golden/semantics tests | Yes |
| CTC-017 | Draft clear failures are swallowed | Low | Confirmed | `OfflineCreationDraftStore.clear` catches and logs | Draft cleanup | monetization store | N/A | missing failure test | Yes |
| CTR-001 | No explicit RPC timeout/unknown-outcome state | High | High-confidence risk | `SupabaseMonetizationRepository.createTask` directly awaits RPC | Network recovery | monetization repository | N/A | controlled gateway test required | Source reverified; runtime pending |
| CTR-002 | Acknowledge can remove newer local edit outbox | High | High-confidence risk | deletion targets entity+plan ID without changed-at/version comparison | Sync reconciliation | `local_sync_store.dart` | N/A | deterministic interleave test required | Source reverified; runtime pending |
| CTR-003 | Metadata JSON shape can be valid non-array | Medium | High-confidence risk | DB constraints only require `is json`; local decoder expects list | Contract/data quality | `sync_dtos.dart`, repository hydration | `20260715112920...` | SQL + hydration test required | Static evidence reverified |
| CTR-004 | Pricing config can change while request waits | Low | Product-semantics risk | config is read separately from wallet lock | Monetization transaction | task RPC | point RPC migrations | concurrency/config experiment | Reverified; intended semantics unresolved |

---

# 4. Current Create Task workflow

## UI entry points

All currently identified manual new-task entry points converge on `showPlanEditorSheet(...)` and `PlanEditorDialog`:

1. Dashboard `HomePilotFloatingActionButton`.
2. Dashboard/maintenance empty-state Create Task action.
3. Home setup `HomeSetupStep.scheduledTask`.
4. Asset-detail `_ItemActionButtons.onAddTask`.
5. Asset-detail “No tasks yet” action.
6. Maintenance-screen floating action button.
7. Filtered maintenance empty-state action.
8. Manual branch of the task-creation chooser (`_TaskCreateAction.manual`).
9. `PlanEditorDialog` secondary “Create and Add Another” action, which reuses `_save(closeAfterSave: false)`.

Edit-task entry points also use `PlanEditorDialog`, but the remediation must preserve the existing local-first edit path and apply the new server-authorized orchestrator only when `widget.task == null`.

## Current concrete flow

- `PlanEditorDialog` owns controllers, `_saving`, `_creationOperationId`, and `_creationPlanId`.
- Form validation checks an asset exists, title is nonempty, recurrence interval is positive, reminder is nonnegative, and selected numeric metadata is parseable/positive.
- On creation, it generates plan/operation UUIDv7 values in widget memory.
- `syncConnectivityInstanceProvider.isOnline()` decides whether to save an offline draft or call the cloud.
- Offline uses `OfflineCreationDraftStore.save(_offlineDraftKey, map)` where `_offlineDraftKey` is scoped to user/local + optional asset, not to operation ID.
- Online uses `monetizationRepositoryProvider` → `SupabaseMonetizationRepository.createTask` → `public.create_task_with_point_debit(jsonb)`.
- The public RPC is currently a `SECURITY INVOKER` SQL wrapper around `homepilot_monetization_private.create_task_with_point_debit_impl(jsonb)`, a `SECURITY DEFINER` function with `search_path = ''`.
- The private function authenticates with `auth.uid()`, validates the target active owned asset, reads monetization config, locks `point_wallets` `FOR UPDATE`, inserts `maintenance_plans` and optional `maintenance_plan_metadata`, inserts `creation_point_operations`, updates `point_wallets`, and inserts `point_transactions` when charge = 1.
- The August 6 function attempts to return canonical plan and metadata. The metadata predicate uses the ambiguous right-hand identifier `plan_id`.
- If RPC succeeds, the client then calls `DriftMaintenanceRepository.savePlan`, which writes the local plan and then metadata separately and allows generic offline-mutation triggers to enqueue plan/metadata mutations.
- The client clears the draft key.
- `LocalSyncStore.acknowledgeTaskCreationComposite` applies any canonical rows supplied and deletes matching plan/metadata outbox rows by `planId`.
- `refreshNotificationSchedules(ref)` calls the scheduler but catches all failures.
- Drift streams (`tasksProvider`, dashboard/statistics repository streams and screens reading those repositories) normally refresh from the local writes. There is no creation-specific manual invalidation for each derived surface.
- `pointWalletProvider` is a Supabase Realtime-backed `StreamProvider`; the returned RPC balance is not directly applied.
- Success UI is shown only after the preceding awaits return, but the widget may already have been dismissed; `_save` uses widget-owned state between the RPC await and its later `mounted` check.

## Current sequence diagram

```mermaid
sequenceDiagram
    actor U as User
    participant EP as Create Task entry point
    participant PE as PlanEditorDialog._save
    participant C as syncConnectivityInstanceProvider
    participant D as OfflineCreationDraftStore
    participant MR as SupabaseMonetizationRepository.createTask
    participant PUB as public.create_task_with_point_debit(jsonb)
    participant PRIV as homepilot_monetization_private.create_task_with_point_debit_impl(jsonb)
    participant OP as public.creation_point_operations
    participant W as public.point_wallets
    participant L as public.point_transactions
    participant P as public.maintenance_plans
    participant M as public.maintenance_plan_metadata
    participant LR as DriftMaintenanceRepository.savePlan
    participant DB as Drift maintenance_plans / metadata / offline_mutation_queue
    participant LS as LocalSyncStore.acknowledgeTaskCreationComposite
    participant NS as notificationSchedulerProvider.refreshSchedules
    participant RP as tasksProvider / dashboardProvider / statistics streams
    participant PW as pointWalletProvider

    U->>EP: Add/Create Task
    EP->>PE: showPlanEditorSheet(...)
    PE->>PE: validate form; _saving=true; allocate plan/op IDs in widget memory
    PE->>C: isOnline()
    alt offline
        PE->>D: save one context-keyed draft
        D-->>PE: returns even if secure-storage write failed
        PE-->>U: draft-saved toast
    else online
        PE->>MR: createTask(operation)
        MR->>PUB: RPC
        PUB->>PRIV: call private implementation
        PRIV->>OP: lookup operation
        PRIV->>P: validate owned active asset relationship
        PRIV->>W: SELECT balance FOR UPDATE
        PRIV->>OP: second lookup
        PRIV->>P: INSERT task
        PRIV->>M: INSERT metadata if present
        PRIV->>OP: INSERT idempotency row
        PRIV->>W: UPDATE balance if charged
        PRIV->>L: INSERT ledger if charged
        PRIV->>PRIV: build canonical JSON response
        Note over PRIV: effective function can raise 42702 on m.plan_id = plan_id
        PRIV-->>MR: success or exception
        MR-->>PE: PointDebitResult
        PE->>LR: savePlan(...)
        LR->>DB: plan write, then separate metadata write; triggers generic outbox
        PE->>D: clear draft (errors swallowed)
        PE->>LS: acknowledgeTaskCreationComposite(...)
        LS->>DB: apply canonical rows + delete plan/metadata outbox by plan ID
        PE->>NS: refreshSchedules()
        NS-->>PE: exception is swallowed by helper
        DB-->>RP: Drift streams update derived task views
        W-->>PW: Realtime eventually updates wallet stream
        PE-->>U: success or generic error
    end
```

---

# 5. Target behavior and architecture

## Architecture decision

The remediation introduces one authoritative client-side orchestration boundary for **new task creation** while preserving existing repositories for ordinary domain persistence and edits.

### Planned ownership

| Responsibility | Owner after remediation |
|---|---|
| Form widgets/controllers | `PlanEditorDialog` only |
| New-task submission state/single-flight/retry lifecycle | **Planned** `TaskCreationController` in `lib/src/features/maintenance/application/task_creation_controller.dart` |
| Typed request/state/failure/response models | **Planned** `lib/src/features/maintenance/domain/task_creation.dart` |
| Durable pre-RPC draft/operation journal | **Planned** `TaskCreationOperationStore` in `lib/src/features/maintenance/data/task_creation_operation_store.dart`, backed by `FlutterSecureStorage` |
| Server call | `MonetizationRepository` / `SupabaseMonetizationRepository` |
| Effective price/charge | Supabase private task-creation implementation only |
| Cloud transaction | `homepilot_monetization_private.create_task_with_point_debit_impl(jsonb)` |
| Cloud task/metadata/ledger/idempotency | PostgreSQL tables and constraints |
| Canonical local application | `LocalSyncStore.reconcileTaskCreationComposite` (planned replacement for task creation use of `acknowledgeTaskCreationComposite`) |
| Generic local plan edits | `DriftMaintenanceRepository.savePlan` in one Drift transaction |
| Generic synchronization | Existing `SyncCoordinator`, `LocalSyncStore`, and `offline_mutation_queue` |
| Wallet Realtime | existing monetization repository stream |
| Immediate authoritative wallet projection | planned monetization wallet snapshot/overlay provider using returned canonical wallet row |
| Reminder reconstruction | existing `HomePilotNotificationScheduler` + `DriftReminderScheduleStore` |
| UI localization/semantics | `PlanEditorDialog` / `_EditorSheetFrame` + ARBs |

## Authoritative transaction boundary

One Supabase transaction MUST contain, for a successful new task operation:

1. Caller authentication and owned active-asset validation.
2. Operation-ID serialization and exact idempotency validation.
3. Server-side effective charge calculation.
4. Wallet row lock.
5. Insufficient-balance check.
6. `maintenance_plans` insert.
7. Optional `maintenance_plan_metadata` insert.
8. `creation_point_operations` insert with operation ID, entity identity, charged amount, request version, and request hash.
9. Wallet balance update when charged.
10. Exactly one corresponding debit ledger row when charged.
11. Canonical result construction.

Any exception before transaction commit MUST leave all of those database states unchanged.

## Paid versus free new tasks

The client MUST NOT decide whether a new task is paid or free. For safety assets, disabled points, emergency-free mode, promotions, or future configuration, the same RPC determines the effective charge.

Therefore:

- A new task requiring server authorization is **online-confirmed before becoming a local maintenance plan**.
- Offline or signed-out Create Task captures an unfinished draft only.
- A server-authorized zero-charge task still uses the RPC because “free” is server-derived.
- Existing task edits are not charged and remain ordinary local-first writes.

If product ownership later requires permanent signed-out task creation, that requires a separate entitlement/pricing design and is not silently introduced in this remediation.

## Identifier and idempotency rules

- Generate `operation_id` and `plan_id` before the first network request.
- Persist both IDs and the normalized exact request payload before sending.
- Once a request has been sent, its operation ID and payload are immutable.
- An exact retry uses the same operation ID, plan ID, and payload.
- Editing the form after a **known terminal rollback** creates a new operation before the next submission if the normalized payload changes.
- An **unknown outcome** must be resolved with the existing operation; the client MUST NOT mint a replacement operation until the old outcome is known.

## Durable local operation states

`TaskCreationOperationStore` MUST represent at least:

- `draft`: never submitted; user may edit.
- `submitting`: request was durably recorded and is being sent. After process restart, treat as `outcomeUnknown` unless the client can prove no request left the device.
- `outcomeUnknown`: network/timeout/process-loss outcome not known; retry exact operation.
- `serverAcceptedNeedsReconcile`: canonical result received or confirmed by replay; local canonical application not complete.
- `permanentRejected`: server definitely rolled back; form preserved with reason and recovery action.
- `reconciled`: canonical server state is durable locally. Entry may be cleaned up; if cleanup fails, loader treats it as completed rather than a fresh draft.

The operation journal MUST be device-local and MUST NOT enqueue a deferred wallet mutation.

## Canonical local reconciliation

The controller MUST NOT call `savePlan` to create an optimistic local plan after the server response. Instead:

1. Strictly parse and validate the RPC response.
2. Verify `operation_id`, `task_id`, canonical plan ID, canonical metadata plan ID, and account identity.
3. Call `LocalSyncStore.reconcileTaskCreationComposite`.
4. If there is no newer local mutation, apply canonical rows under outbox suppression and save sync shadows/cursors.
5. If a generic plan/metadata outbox mutation already exists because a pulled task was edited before reconciliation, preserve that local edit and its outbox; checkpoint canonical server state without overwriting the edit.
6. Do not blindly delete the plan/metadata outbox.
7. Mark the operation `reconciled` only after the local transaction succeeds.

## Success timing

The UI may display final “Task created” success and clear/reset the form only when:

- the server transaction is known to have succeeded;
- the response contract is valid;
- canonical task state is durable locally or an equivalent canonical sync pull has already established it;
- the operation journal records reconciliation success.

Reminder scheduling is attempted immediately but is not part of the financial transaction. A reminder failure can produce a nonblocking warning/diagnostic because the existing startup/resume/daily reconciler can reconstruct reminders.

---

# 6. Bug-to-fix traceability matrix

| ID | Severity | Confidence | Root cause | Proposed fix | Exact likely changes | Migration? | Required tests | Dependencies | Compatibility | Implementation risk | Validation | Completion criteria |
|---|---:|---|---|---|---|---|---|---|---|---|---|---|
| CTC-001 | Critical | Confirmed | PL/pgSQL variable/column shadowing | Forward-replace private task RPC using `v_` locals, fully qualified aliases, canonical row variables | new emergency migration; `0012_points_monetization.test.sql` | Yes | 42702 reproduction, create/replay with/without metadata, rollback assertions | Phase 0 | Public signature unchanged | Low | local Supabase lint/tests | No ambiguous identifier; valid creation succeeds |
| CTC-002 | Critical | Confirmed | Online IDs only in widget memory | Persist operation+plan IDs+exact payload before network; resume exact operation | new task-creation controller/domain/store; `lib/main.dart` | No DB migration; secure-store format v2 | timeout-after-commit, restart, disposal, exact replay | backend idempotency hardening | preserve legacy draft import | Medium | controller/widget/restart tests | uncertain outcome cannot mint duplicate operation |
| CTC-003 | High | Confirmed | widget owns long-running financial flow; modal stays dismissible | controller survives widget; block dismissal while unpersisted/submitting; mounted checks only for UI | controller + `PlanEditorDialog`, modal wrapper/frame | No | close/back/drag/dispose during blocked RPC | CTC-002 | no route API change | Medium | widget tests | no use-after-dispose; operation remains recoverable |
| CTC-004 | High | Confirmed | server idempotency row lacks request fingerprint | add nullable legacy-compatible SHA-256 request hash/version; enforce for new task ops | hardening migration, `creation_point_operations`, task RPC | Yes | exact replay vs changed payload | CTC-001 first | legacy rows hash-null accepted under identity checks | Medium | pgTAP | same ID/different payload permanently rejected |
| CTC-005 | High | Confirmed | inconsistent operation lookup validation/race | operation advisory lock + shared exact validator on every lookup; preserve wallet lock | hardening migration; task and minimal shared asset-op path | Yes | same-op two-session, cross-user, cross-entity | CTC-004 | older payload shape unchanged | Medium | pgTAP + concurrency helper | deterministic winner/loser, no cross-user result |
| CTC-006 | High | Confirmed | permissive DTO defaults | versioned strict result parser requiring identity/canonical rows/wallet | monetization DTO/repository + task domain | backend adds fields | malformed/missing/wrong-type response | backend v2 response | backend must deploy first | Medium | unit/controller tests | incompatible result cannot mutate local state |
| CTC-007 | High | Confirmed | acknowledgement trusts nullable/mismatched canonical data and deletes by ID | replace Create Task use with strict `reconcileTaskCreationComposite`; no blind outbox delete | `local_sync_store.dart`; task controller | No | wrong ID, null plan, wrong user, missing optional metadata | CTC-006 | legacy generic outbox preserved safely | Medium | Drift tests | mismatch aborts transaction and preserves mutations |
| CTC-008 | High | Confirmed | plan and metadata writes separate | wrap `savePlan` plan+metadata+inbox side effects in one Drift transaction | `repositories.dart` | No | injected metadata failure rollback | none | behavior-compatible | Low | repository tests | no partial local plan/metadata |
| CTC-009 | High | Confirmed | secure-store errors swallowed | task-specific store throws typed durability failure; controller never reports saved until confirmed | new task operation store; task UI | No | write failure | CTC-002 | import old draft keys | Low | unit/widget tests | no false draft-saved UI |
| CTC-010 | Medium | Confirmed | one context key, ambiguous account scope | operation-keyed records; explicit account scope; legacy import; explicit claim of signed-out draft | task operation store/controller | No | multiple drafts, sign-in/account switch | CTC-009 | legacy key migration | Medium | store/controller tests | drafts do not overwrite or cross accounts |
| CTC-011 | High audit / narrowed | Confirmed narrower | immediate refresh failure hidden | retain existing global reconstruction; return/log nonfatal reminder warning; test restart/resume/daily repair; add dirty marker only if Phase 0 proves reconstruction gap | controller, notification tests; possibly helper logging | No by default | scheduler fail then resume repair; no duplicate reminders | Phase 0 | preserve schedule snapshot format | Low | notification/widget tests | task success remains; reminders converge |
| CTC-012 | Medium | Confirmed | creation errors use generic task-update fallback | typed `TaskCreationFailureCode`; UI localization mapping | task domain/controller, `main.dart`, ARBs; possibly `supabase_failure.dart` shared transient mapping | No | each technical code → recovery | backend stable errors | existing generic errors remain elsewhere | Medium | unit/widget en/ar | actionable failures have correct non-raw message |
| CTC-013 | Medium | Confirmed | UI does not mirror server bounds | central task-creation limits + field validators; server remains authoritative | task domain, `PlanEditorDialog`, ARBs, SQL tests | No schema migration unless metadata shape checks added | boundary Unicode/Arabic tests | none | same accepted domain | Low | unit/widget/pgTAP | client accepts/rejects same limits |
| CTC-014 | Medium | Confirmed | broad casts and narrow exception block | prevalidate types/ranges; stable error codes; do not expose raw SQL | hardening migration; task failure mapper | Yes | overflow/date/duplicate-id/constraint tests | CTC-001 | stable public signature | Medium | pgTAP/client tests | expected invalid input returns stable domain code |
| CTC-015 | Medium | Confirmed | RPC balance ignored until Realtime | v2 returns canonical wallet; monetization display provider overlays newer RPC wallet until stream catches up | task RPC, monetization feature, points pill/wallet surfaces | Yes for response only | delayed Realtime | CTC-006 | old clients ignore fields | Medium | provider/widget test | display balance matches committed RPC immediately |
| CTC-016 | Medium | Confirmed | weak submission semantics | explicit submitting state/label/progress/live region/focus; disable close/back/drag while required | `main.dart`, ARBs | No | semantics, keyboard, text scale, RTL | CTC-003/controller | visual change | Medium | widget/golden/manual device | accessible loading state and safe navigation |
| CTC-017 | Low | Confirmed | cleanup failure hidden | journal uses terminal `reconciled` state; cleanup is idempotent; stale completed records ignored and retried for deletion | task operation store | No | delete/mark cleanup failure | CTC-002/store | legacy draft cleanup | Low | unit test | completed operation never resurfaces as new draft |
| CTR-001 | High | Risk | no explicit app timeout/unknown state | controlled timeout at gateway/controller boundary; timeout becomes `outcomeUnknown`, never terminal | task controller; optionally monetization gateway | No | hanging RPC, timeout-before/after simulated commit | CTC-002/004 | exact same RPC | Medium | controller tests | no indefinite UI and no new ID on timeout |
| CTR-002 | High | Risk | current acknowledgement deletes mutation by plan ID | reconcile canonical state while preserving any existing generic outbox; deterministic interleave test | `local_sync_store.dart` | No | later edit before reconcile | CTC-007 | legacy outbox retained | Medium | Drift barrier test | newer edit/outbox survives |
| CTR-003 | Medium | Risk | “valid JSON” allows non-array shapes | server validate array-of-strings for both metadata list fields; strict DTO/local parse | hardening migration, task domain/sync parser tests | Yes function validation; table constraint MAY be added forward if safe | scalar/object/element-type tests | Phase 0 semantics | older valid arrays unchanged | Low | pgTAP + hydration | invalid shape rejected before writes |
| CTR-004 | Low | Risk | config read/lock timing semantics undefined | Phase 0 product decision; default plan moves config read after wallet lock without locking config row; document snapshot semantics | hardening migration/docs if approved | Yes function replacement already | concurrency config barrier | product decision | no client contract change | Low | SQL experiment | behavior documented and deterministic enough for product rule |

---

# 7. Remediation strategy by root cause

## SQL identifier ambiguity

**Findings:** CTC-001.  
The August 6 function declares `plan_id` and uses `m.plan_id = plan_id`. The immediate repair is independent of client changes and must land first. Use a strict variable convention (`p_` parameters, `v_` locals, table aliases for every column) and materialize canonical rows into row variables rather than embedding ambiguous subqueries in the final return object.

## Broken end-to-end transaction ownership

**Findings:** CTC-002, CTC-008, CTC-011 (post-commit derived state).  
The PostgreSQL transaction is atomic, but the mobile workflow crosses widget memory, secure storage, Drift, generic outbox reconciliation, and notification APIs. Do not attempt a distributed transaction across PostgreSQL, SQLite, and Android notifications. Instead make each boundary durable and idempotent:

1. durable operation journal before network;
2. atomic server transaction;
3. strict atomic local canonical reconciliation;
4. idempotent derived reminder rebuild.

## Incorrect/incomplete idempotency

**Findings:** CTC-004, CTC-005, CTC-002, CTR-001.  
Server request identity and client retry identity are one root cause. The database must bind an operation ID to immutable normalized semantics, while the client must persist and reuse that operation. Operation-level serialization occurs before wallet locking; wallet locking continues to serialize balance changes.

## Duplicate UI submission and lifecycle

**Findings:** CTC-003, CTC-016.  
`_saving` is a useful local guard but is not authoritative because separate editor instances/processes and widget disposal exist. A singleton task-creation controller is the single-flight owner. Widgets reflect controller state and cannot cancel an already-sent financial operation by being disposed.

## Client/server charge disagreement and balance display

**Findings:** CTC-015, CTR-004.  
Charge remains exclusively server-derived. The client may display current wallet/config state as informational but never uses it to authorize creation. The v2 RPC returns canonical wallet state so the UI can immediately show the committed balance while Realtime converges.

## Authorization, RLS, and grants

**Findings:** CTC-005 plus preventive hardening.  
Current public wrapper/private definer placement and empty `search_path` are correct and must not regress. Cross-user asset references remain indistinguishable from missing references. The shared operation table requires exact caller/entity validation after operation serialization.

## Local/cloud reconciliation failure

**Findings:** CTC-006, CTC-007, CTR-002.  
Do not use `savePlan` + delete-outbox as the online creation reconciliation pattern. Parse strict canonical state and reconcile through `LocalSyncStore` under outbox suppression, preserving a newer local mutation if one exists.

## Invalid draft/queued-operation behavior

**Findings:** CTC-009, CTC-010, CTC-017.  
Create Task gets an operation-keyed secure journal. Offline drafts are not generic sync queue entries and cannot be silently charged in background. Storage errors are explicit. Account scope prevents cross-account resurrection.

## Provider invalidation/derived state

**Findings:** CTC-015 and derived-state verification.  
Task/dashboard/statistics should continue to react to Drift. Do not add broad manual invalidation if stream tests prove it unnecessary. Add only the wallet canonical overlay and explicit invalidation for any FutureProvider proven stale by tests.

## Notification inconsistency

**Findings:** narrowed CTC-011.  
Use existing deterministic schedule snapshots and global refresh points. The safe order is task durable → immediate refresh attempt → global reconstruction on later lifecycle/background events. Do not create a second notification queue unless a failing test proves the existing snapshot/rebuild cannot converge.

## Recurrence/timestamp handling

**Findings:** creation-side validation coverage rather than a confirmed recurrence bug.  
Preserve server `timestamptz` and client UTC serialization. Test local date picker values, DST/timezone round trips, and all recurrence enum values. Do not change recurrence advancement semantics in this remediation.

## Incomplete error classification

**Findings:** CTC-012, CTC-014, CTR-001.  
Stable server error messages/codes feed a task-specific client failure taxonomy. Raw SQL text never reaches the user. Unknown-outcome errors are distinct from known rollback errors.

## Missing regression coverage

Every group above adds a failing-before-fix test where possible. Runtime-only risks receive controlled deterministic experiments in Phase 0 before implementation decisions become mandatory.

---

# 8. Implementation phases

## Phase 0 — Reproduction and safety baseline

**Goal:** make the current failures executable and freeze the effective contract before implementation.

**Bug/risk IDs:** CTC-001–CTC-017, CTR-001–CTR-004 as baseline; no fixes yet.

**Preconditions:** local Flutter and Supabase toolchains installed; no production project linked.

**Exact files/symbols:** `supabase/tests/database/0012_points_monetization.test.sql`, `tool/test_points_concurrency.ps1`, `test/task_creation_sync_test.dart`, `test/monetization_test.dart`, `test/widget_test.dart`, `test/home_structure_repository_test.dart`, effective `create_task_with_point_debit` definitions.

**Tests to write first:**

1. A pgTAP regression that calls the current final task function with metadata and records the expected `42702` failure before the emergency migration. Keep the assertion structured so the emergency migration changes the expected outcome rather than leaving a permanently failing test in the final branch.
2. Database-state assertion around the known failure: plan count, metadata count, operation count, wallet balance, and task debit count remain unchanged.
3. Strict response parser tests that currently fail on missing/wrong fields.
4. Secure-store error tests showing current false-success behavior.
5. Drift metadata-failure test proving `savePlan` can currently leave a partial plan.
6. Blocking fake gateway widget test demonstrating dismissal/disposal during submission.
7. Deterministic interleave test for a later local edit before canonical acknowledgement.
8. Metadata object/scalar hydration experiment (`CTR-003`).
9. Controlled hanging/timeout fake gateway experiment (`CTR-001`).
10. Config/wallet concurrency experiment or explicit product sign-off for `CTR-004`.

**Snapshot of effective SQL:** capture `pg_get_functiondef` for the public wrapper and private implementation in local Supabase after all migrations. Compare with repository migration order. Store only test evidence/log output outside production; do not add generated hosted-state dumps to the repo unless the test fixture requires it.

**Determinism:** use fixed clocks, deterministic UUID providers in the planned controller tests, fake gateways with `Completer` barriers, and database barriers/advisory locks instead of sleeps.

**Tests to run afterward:** existing Flutter baseline, `npm run supabase:lint`, `npm run supabase:test`, and the existing point-concurrency helper in a local Supabase environment.

**Expected observable behavior:** the current branch demonstrably fails the task RPC while preserving cloud atomicity; other tests expose the client gaps without modifying implementation.

**Rollback/recovery:** tests only; no runtime behavior change.

**Exit criteria:** every audit ID has either a failing reproduction, a static invariant assertion, or a documented unresolved experiment with owner and expected decision.

### Phase 0 questions that must be resolved

- Does the pinned local Supabase image expose SHA-256 `digest` through the expected extensions schema?
- Does the PostgREST client throw a `TimeoutException`, `SocketException`, `PostgrestException`, or another type for the chosen application timeout wrapper?
- Does current local hydration silently coerce non-array metadata to an empty list as expected from `_stringListFromJson`?
- Does existing startup/resume/daily reminder refresh converge after an injected immediate Create Task refresh failure?

---

## Phase 1 — Immediate database correctness fixes

**Goal:** restore valid task creation without changing the public request contract or point semantics.

**Bug IDs:** CTC-001.

**Preconditions:** Phase 0 `42702` reproduction and rollback assertions exist.

**Exact files/symbols:**

- **New** `supabase/migrations/<UTC timestamp>_fix_task_creation_rpc_identifier_ambiguity.sql`.
- `homepilot_monetization_private.create_task_with_point_debit_impl(jsonb)`.
- `public.create_task_with_point_debit(jsonb)` remains the same wrapper signature/security mode.
- `supabase/tests/database/0012_points_monetization.test.sql`.

**Implementation steps:**

1. Add a forward migration only.
2. Recreate the private implementation with all local variables prefixed consistently (`v_...`) and every SQL column qualified through table aliases.
3. Do not use an unqualified identifier that is also a parameter/local variable.
4. Use row variables such as `v_plan_row public.maintenance_plans%rowtype` and `v_metadata_row public.maintenance_plan_metadata%rowtype` for canonical return state. Use `INSERT ... RETURNING * INTO ...` on first creation and qualified `SELECT ... INTO ...` on replay.
5. Preserve auth, owned active-asset check, server charge calculation, wallet lock, inserts, ledger behavior, exception behavior, public wrapper, grants, and `search_path = ''` in this emergency migration.
6. Notify PostgREST schema reload using the repository's existing migration pattern.
7. Review the entire function, not only `m.plan_id = plan_id`, for variable shadowing.

**Tests to write first:** exact create with metadata; exact create without metadata; exact replay; prior committed operation replay; transaction-state rollback on deliberate response-construction fault in a test-only function/transaction fixture if practical.

**Tests afterward:** full `0012` suite, Supabase lint/test, point-concurrency helper.

**Dependencies:** none beyond Phase 0.

**Expected observable behavior:** ordinary and safety task creation succeed; exact replay remains one task/one operation/at most one debit; no `42702`.

**Rollback/recovery:** because migrations are append-only, rollback is another forward function replacement. Never edit the August 6 migration.

**Exit criteria:** local final function contains no ambiguous identifiers; SQL tests pass with canonical plan/metadata return.

---

## Phase 2 — Transactional point and task integrity

**Goal:** prove and strengthen invariants around the task, metadata, wallet, ledger, and operation record.

**Bug IDs:** CTC-004, CTC-005, CTC-014; supports CTC-002 and CTC-015.  
**Risks:** CTR-003, CTR-004.

**Preconditions:** Phase 1 deployed/tested locally; server contract operational.

**Exact files/symbols:**

- **New** `supabase/migrations/<UTC timestamp>_harden_task_creation_idempotency.sql`.
- `public.creation_point_operations`.
- private task RPC; minimally shared private asset RPC path because both use the same global operation-ID table.
- `public.point_wallets`, `public.point_transactions` constraints/indexes (verify, do not weaken).
- `supabase/tests/database/0012_points_monetization.test.sql`.
- `tool/test_points_concurrency.ps1`.

**Implementation steps:**

1. Add `request_version` and nullable `request_hash` to `creation_point_operations` in a backward-compatible manner. New task operations MUST write a version and 64-character lowercase SHA-256 hash; legacy rows may remain null.
2. Add a check constraint for valid hash shape when non-null. Do not fabricate hashes for historical rows.
3. Normalize the server-semantic task request before hashing: plan ID, asset ID, trimmed title, normalized optional instructions, recurrence interval/unit, priority, canonical `timestamptz`, reminder default, requested health group, enabled default, and normalized metadata. Do not include client-supplied charge/balance/ownership values.
4. Require `required_materials` and `dependency_plan_ids` to be arrays of strings. Keep the existing whole-request size bound. Do not add arbitrary new list-count limits unless Phase 0 establishes a product constraint.
5. Acquire a transaction-scoped advisory lock derived from `operation_id` before the first operation lookup. Apply the same lock discipline to the shared asset-creation operation path so a task and asset request using the same UUID cannot race the global primary key.
6. Lookup existing operation under the operation lock and validate caller, entity type, entity ID, and request hash when present.
7. Validate the target owned active asset.
8. Lock the caller wallet `FOR UPDATE`. Maintain one lock order: operation advisory lock → wallet row lock. No code path may acquire those locks in reverse order.
9. Revalidate an existing operation after the wallet lock only through the same exact validation helper/logic; do not use the current permissive second branch.
10. Read current monetization config after wallet acquisition unless the `CTR-004` product decision explicitly requires another snapshot rule. Do not lock config by default.
11. Compute the charge only on the server. Preserve safety/free logic.
12. Fail insufficient balance before task writes.
13. Insert task and metadata, operation record, wallet transition, and ledger in the same function transaction.
14. Return a canonical wallet row and canonical task/metadata rows.
15. Detect an existing operation whose expected canonical task is missing/inconsistent and return a stable corruption/result-unavailable code without recreating or recharging.

**Tests to write first:**

- wallet balance exactly 1 with two concurrent distinct charged tasks → one success, one insufficient, final balance 0;
- same operation exact duplicate → one task, one debit;
- same operation same task changed payload → permanent payload mismatch;
- same operation different task → operation reused error;
- same operation cross-user and cross-entity races → no result leakage;
- invalid metadata JSON shape → rollback;
- ledger insertion fault fixture → task/metadata/operation/wallet all rollback;
- current constraints prevent negative wallet state.

**Expected observable behavior:** a successful paid creation always yields exactly one plan, canonical metadata state, operation record, one debit ledger row, and one balance transition. A free creation yields the task/metadata/operation with no debit ledger row and unchanged wallet.

**Rollback/recovery:** server errors before commit require no compensation. If a new migration itself is defective, replace functions/constraints in a later forward migration.

**Exit criteria:** atomicity/concurrency tests prove all financial invariants and no cross-user operation result can be returned.

---

## Phase 3 — Idempotency and retry safety

**Goal:** make every retry deterministic from both server and client perspectives.

**Bug IDs:** CTC-002, CTC-004, CTC-005, CTC-006.  
**Risk:** CTR-001.

**Preconditions:** Phase 2 server supports payload-bound operation records and versioned canonical response.

**Exact files/symbols:**

- `lib/src/features/monetization/monetization.dart` or extracted RPC DTO boundary.
- **New** `lib/src/features/maintenance/domain/task_creation.dart`.
- **New** `lib/src/features/maintenance/data/task_creation_operation_store.dart`.
- **New** `lib/src/features/maintenance/application/task_creation_controller.dart`.
- task RPC v2 return contract.

**Implementation steps:**

1. Define `TaskCreationRequest`, `TaskCreationOperation`, `TaskCreationOperationState`, `TaskCreationRpcResult`, `TaskCreationFailure`, and `TaskCreationFailureCode`.
2. Add injectable UUID and clock dependencies to the controller/store boundary for deterministic tests.
3. Persist `operation_id`, `plan_id`, account scope, normalized exact payload, state, created/submitted timestamps, attempt count, and last safe error code before network submission.
4. Make the payload immutable after first submission. If the form changes after a known rollback, mint a new operation/plan identity on the next submit rather than mutating a submitted operation.
5. Add an application timeout around the RPC at the controller/gateway boundary. Timeout and transport loss after submission become `outcomeUnknown` rather than a permanent failure.
6. Retry unknown operations with the exact same IDs/payload. Never generate new IDs until the previous outcome is resolved.
7. Parse v2 responses strictly. Require version, operation ID, task ID, charge, canonical plan, expected optional metadata semantics, balance/canonical wallet, and type correctness.
8. Treat an older/incompatible response as a typed schema incompatibility and retain the operation for recovery.
9. Mark server success as `serverAcceptedNeedsReconcile` before local reconciliation.
10. On restart or a subsequent Create Task entry, resolve all account-compatible unknown/accepted operations before allowing a new charged submission.

**Tests first:** process restart with operation store, timeout after fake server commit, exact replay, malformed response, response for wrong plan/user/op, hanging gateway.

**Dependencies:** backend v2 must deploy before a client release that requires it.

**Expected observable behavior:** response loss cannot cause a second charge; user sees a recoverable “outcome being confirmed” state instead of a generic retry that mints new IDs.

**Exit criteria:** every submitted operation has a durable identity and deterministic next action after restart.

---

## Phase 4 — Authorization and database hardening

**Goal:** prove least privilege and reject abuse without weakening older-client synchronization.

**Bug IDs:** CTC-005, CTC-013, CTC-014; preventive coverage for financial invariants.

**Preconditions:** Phase 2 hardening migration drafted.

**Exact files/symbols:**

- `homepilot_monetization_private.create_task_with_point_debit_impl(jsonb)`.
- `public.create_task_with_point_debit(jsonb)`.
- `homepilot_monetization_private.is_authorized_point_creation_impl` / public wrapper if touched by migration dependencies.
- RLS policies on `maintenance_plans`, `maintenance_plan_metadata`, wallet/ledger/operation tables.
- Supabase SQL tests.

**Implementation steps:**

1. Keep public task RPC `SECURITY INVOKER`.
2. Keep privileged implementation in `homepilot_monetization_private` as `SECURITY DEFINER` with `search_path = ''`.
3. Revoke public/anon execution and grant only the roles already required by the architecture.
4. Do not grant authenticated clients direct wallet, ledger, or operation mutation rights.
5. Derive caller from `auth.uid()`; never accept a user ID from the request as authority.
6. Verify target asset belongs to caller and is active; use an authorization-safe `ASSET_NOT_FOUND` response for missing/foreign/inactive cases unless product requires a distinct safe code.
7. Derive charge/free state on server.
8. Validate field limits and metadata shapes before risky casts where possible.
9. Preserve RLS authorization allowing older supported sync clients to reconcile an RPC-created task without authorizing an uncharged brand-new plan.
10. Add tests that authenticated users cannot execute private functions via the exposed public API surface and cannot read internal operation rows.

**Tests:** anonymous, expired/missing auth context, cross-user asset, direct charged insert, direct wallet update, function security-mode introspection, grants, fixed search path, operation collision, malformed payload.

**Expected observable behavior:** no client-supplied ownership/price field can alter authorization or debit semantics.

**Exit criteria:** RLS/grant pgTAP tests and advisor-relevant function-security tests pass.

---

## Phase 5 — Client orchestration and local persistence

**Goal:** remove financial orchestration from widget lifetime and make local canonical state atomic.

**Bug IDs:** CTC-002, CTC-006, CTC-007, CTC-008, CTC-009, CTC-010, CTC-017.  
**Risk:** CTR-002.

**Preconditions:** Phase 3 domain/store/controller models and backend v2 contract.

**Exact files/symbols:**

- planned task creation controller/store/domain files.
- `DriftMaintenanceRepository.savePlan`.
- `LocalSyncStore.acknowledgeTaskCreationComposite` → planned `reconcileTaskCreationComposite` for new flow.
- `lib/main.dart` wiring.

**Implementation steps:**

1. Implement operation-keyed secure records. Use one storage record per operation; enumerate task-operation records rather than overwriting one context key. Avoid a non-atomic shared index if the secure-storage API can enumerate keys.
2. Add legacy loader support for `homepilot_creation_draft_v1_task_<scope>_<asset>` keys. Import the stored operation/plan IDs into the new record format before deleting the legacy key.
3. A signed-out draft has `accountScope = local`. Do not silently bind it on sign-in; require explicit resume/claim into the active account. A draft scoped to one user must never be offered to another account.
4. Save operation record successfully before calling the RPC. Propagate a typed local-durability error if save fails.
5. For new online creation, do not call `DriftMaintenanceRepository.savePlan` before canonical reconciliation.
6. Implement `LocalSyncStore.reconcileTaskCreationComposite`:
   - require canonical plan;
   - validate expected plan ID and expected user ID;
   - validate metadata plan/user if metadata exists;
   - validate revision/type fields through strict DTO parsing;
   - inside one Drift transaction, use outbox suppression for remote application;
   - if no newer pending local mutation exists, apply canonical plan/metadata and save shadows/checkpoints;
   - if a generic pending plan/metadata mutation exists, preserve the local row and outbox while saving canonical shadow/checkpoint so the later edit still pushes;
   - never delete all plan/metadata outbox rows solely by plan ID.
7. Keep `DriftMaintenanceRepository.savePlan` for edits and other local workflows, but wrap its plan+metadata+inbox side effects in one `db.transaction`.
8. Mark journal state `reconciled` after local transaction commit, then attempt cleanup. Cleanup failure leaves a terminal completed record that loaders ignore and later retry deleting.

**Tests first:** secure-store write/delete failures, multiple drafts, account switching, local reconciliation wrong IDs, pending newer edit, metadata write rollback, restart from each operation state.

**Dependencies:** strict server response from Phase 3.

**Expected observable behavior:** no optimistic paid task appears before server acceptance; after acceptance, local data becomes canonical in one safe reconciliation step.

**Exit criteria:** controller tests and Drift tests pass; no new-task generic outbox is required for the new path; later edits remain syncable.

---

## Phase 6 — UI interaction and form recovery

**Goal:** make every Create Task entry point use the same safe controller and give accurate recoverable feedback.

**Bug IDs:** CTC-003, CTC-012, CTC-013, CTC-016; supports CTC-002/009/010.

**Preconditions:** controller is available and tested independently.

**Exact files/symbols:** `showPlanEditorSheet`, `PlanEditorDialog`, `_EditorSheetFrame`, all existing Create Task call sites, ARBs.

**Implementation steps:**

1. Preserve all entry points and route them through the same `PlanEditorDialog`; the dialog calls `taskCreationControllerProvider` only for `widget.task == null`.
2. For edits (`widget.task != null`), retain existing repository edit behavior.
3. Disable both primary and secondary save while controller is submitting/reconciling.
4. Coordinate keyboard action and buttons through the same controller method; the controller enforces process-wide single-flight.
5. Show localized “Creating…”/“Confirming…” state and an accessible progress indicator/live-region message.
6. Prevent close/back/drag dismissal while the operation is not yet durable or while a submitted operation has not reached a safe recoverable journal state. Once the journal is durable, navigation may be allowed without cancelling the operation; the controller continues outside widget lifetime.
7. After every await, widget code checks `mounted` before touching controllers/context. The controller itself must not depend on `BuildContext`.
8. Do not clear form values on failure. For known field validation failure, focus the first invalid field. For insufficient balance, preserve values and operation payload; earning points may retry the same exact operation.
9. For unknown outcome, disable edits to the frozen submitted payload until confirmation resolves; offer “Confirm/retry” using the same operation rather than a fresh create.
10. Final success closes/resets only after local reconciliation. “Create and Add Another” allocates new IDs only after the preceding operation is reconciled.

**Tests:** rapid taps, keyboard+tap, two editor entry points, close/back/drag, widget disposal, insufficient points, offline draft failure, unknown outcome, success add-another.

**Expected observable behavior:** one submission per operation; no crash/use-after-dispose; forms survive failures.

**Exit criteria:** all entry points have consistent controller state and widget lifecycle tests pass.

---

## Phase 7 — Notifications and derived-state consistency

**Goal:** make task, reminders, wallet, and derived views converge after creation without duplicating authoritative state ownership.

**Bug IDs:** narrowed CTC-011, CTC-015; verifies provider/derived-state assumptions.

**Preconditions:** canonical local reconciliation is stable.

**Exact files/symbols:** `HomePilotNotificationScheduler`, `DriftReminderScheduleStore`, `refreshNotificationSchedules`, `NotificationBootstrap`, `pointWalletProvider`, `HkPointsPill`, tasks/dashboard/statistics/search consumers.

**Implementation steps:**

1. Attempt `HomePilotNotificationScheduler.refreshSchedules()` after canonical local task commit.
2. Replace the create-path silent catch with structured non-sensitive logging and a nonfatal controller warning result.
3. Keep existing startup, app-resume, and daily WorkManager schedule reconstruction. Add regression tests proving an immediate failure is repaired on a later refresh and does not create duplicate notification IDs.
4. Add a persistent reminder “dirty” marker only if Phase 0 demonstrates that the existing schedule snapshot/global refresh cannot reliably converge. Do not introduce duplicate recovery mechanisms preemptively.
5. Have v2 RPC return canonical wallet data. Add a monetization-layer authoritative wallet snapshot/overlay provider. UI wallet consumers choose the newer canonical RPC snapshot until the Realtime stream reaches the same/newer server update, then discard the overlay.
6. Verify `tasksProvider`, dashboard summary, statistics, calendar, asset task lists, counters, and search against canonical Drift application. Add manual invalidation only for a provider proven by test to remain stale.

**Tests:** scheduler fails once then resume refresh; duplicate schedule prevention; delayed wallet Realtime; task appears in maintenance/asset/calendar/search/dashboard; statistics/counters reflect expected state.

**Expected observable behavior:** financially complete task remains successful even if OS scheduling fails temporarily; points display does not show a stale pre-debit value after a confirmed response.

**Exit criteria:** all derived-state integration tests converge without broad unnecessary invalidation.

---

## Phase 8 — Time, recurrence, localization, and accessibility

**Goal:** verify boundary behavior without changing unrelated recurrence rules.

**Bug IDs:** CTC-013, CTC-016; supporting coverage for CTC-012.

**Exact files/symbols:** task creation domain limits, `PlanEditorDialog`, ARBs, recurrence enum/request serialization, widget/golden tests.

**Implementation steps:**

1. Preserve `RecurrenceUnit` values accepted by cloud: hours, days, weeks, months, years.
2. Serialize submitted due timestamps as ISO-8601 UTC instants; server stores `timestamptz`; canonical response round-trips to the local date/time expected by current UX.
3. Do not impose a new “future only” due-date rule unless product explicitly approves it; the current picker permits dates in the recent past.
4. Test DST/timezone conversion, leap date, month/year selection payloads, and device clock changes around draft creation/submission.
5. Add client constraints matching server title/metadata maximum lengths and duration bounds.
6. Add English and Arabic messages for every new task-creation state/failure.
7. Verify RTL ordering, text scaling, long Arabic strings, keyboard submit, screen-reader labels, progress semantics, focus after validation, and focus after retryable failure.
8. Respect reduced-motion conventions for any submitting/success animation.

**Tests:** unit boundary tests, widget semantics tests, Arabic RTL tests, text scale tests, golden snapshots for idle/submitting/error where stable.

**Exit criteria:** no raw server error leaks; en/ar and accessibility requirements pass.

---

## Phase 9 — Documentation, observability, and final validation

**Goal:** close behavioral, operational, and documentation contracts.

**Bug IDs:** all; no new product behavior beyond implemented phases.

**Exact files/docs:** architecture, monetization, sync, backend migration/function docs, testing docs, feature catalog, localization docs if behavior changes, Sentry operations if new event fields, `CHANGELOG.md`, this plan status.

**Implementation steps:**

1. Add allowlisted structured task-creation diagnostics: phase, response version, retry count, failure code, charged/free boolean where safe, and an opaque operation fingerprint rather than raw task data.
2. Do not log title, instructions, location labels, materials, dependencies, email, tokens, request/response bodies, or raw operation UUID if existing observability policy treats it as a stable direct identifier. Prefer a short one-way technical fingerprint.
3. Add Sentry tags/breadcrumbs only for unexpected actionable failures; expected offline, user validation, and insufficient-balance events remain normal product states unless aggregate metrics are intentionally collected.
4. Update docs in the same PR as their behavior.
5. Run full Flutter/Supabase validation, concurrency tests, device notification validation, and English/Arabic accessibility checks.

**Rollback/recovery:** backend changes are forward-replaced only; client rollout can be halted without reversing database compatibility fields. The hardened backend must remain compatible with the immediately preceding client.

**Exit criteria:** Definition of Done in section 27 is completely checked and evidence is attached to PRs.

---

# 9. File-by-file change plan

| File/path | Current responsibility | Symbols | Planned modification | Why here | IDs | Tests | Docs affected | Independent? |
|---|---|---|---|---|---|---|---|---|
| `supabase/migrations/<timestamp>_fix_task_creation_rpc_identifier_ambiguity.sql` | New forward migration | private task RPC | Narrow 42702 repair with qualified identifiers/row variables | Emergency backend correctness | CTC-001 | `0012` | backend migration docs, changelog | Yes; first PR |
| `supabase/migrations/<timestamp>_harden_task_creation_idempotency.sql` | New hardening migration | `creation_point_operations`, task RPC, minimal shared asset operation lock | request hash/version, operation lock, strict replay validation, v2 canonical wallet/response, input shape/error hardening | Server financial/idempotency authority | CTC-004/005/013/014/015, CTR-003/004 | SQL/RLS/concurrency | monetization, backend docs | After emergency migration |
| `supabase/tests/database/0012_points_monetization.test.sql` | Monetization/RLS/RPC tests | pgTAP plan | Add 42702 regression, rollback, replay, payload mismatch, malformed input, security and response v2 tests | Existing canonical backend test home | backend IDs | itself | testing docs | Yes with migrations |
| `tool/test_points_concurrency.ps1` | Local concurrent one-point spend test | two job requests | Retain existing distinct-operation spend test; extend or add deterministic modes for same operation/cross-account only if script remains readable | Real concurrency outside one pgTAP transaction | CTC-005 | script assertions | testing docs if invocation becomes required | With backend PR |
| `lib/src/features/maintenance/domain/task_creation.dart` | **New** typed task creation contract | request/operation/state/result/failure/limits | Define immutable normalized payload, failure taxonomy, operation states, strict invariants | Keep UI and gateway from inventing states | CTC-002/006/012/013, CTR-001 | new controller/domain tests | architecture docs | With client PR |
| `lib/src/features/maintenance/data/task_creation_operation_store.dart` | **New** durable task draft/journal | `TaskCreationOperationStore` | operation-keyed secure storage, legacy import, typed failures, account scope, terminal cleanup | Durable retry identity without generic sync debit queue | CTC-002/009/010/017 | store tests | sync/monetization/privacy review | With client PR |
| `lib/src/features/maintenance/application/task_creation_controller.dart` | **New** authoritative client orchestrator | `taskCreationControllerProvider`, `TaskCreationController` | single-flight, persistence-before-send, timeout/unknown state, RPC, reconciliation, reminder/wallet follow-up | Removes financial workflow from widget lifetime | CTC-002/003/006/012/015/016, CTR-001 | new controller tests | architecture/monetization/sync | Requires backend v2 |
| `lib/src/features/monetization/monetization.dart` | wallet/config/RPC/ad/draft infrastructure | `PointDebitResult`, `SupabaseMonetizationRepository`, wallet providers, `OfflineCreationDraftStore` | expose strict task RPC boundary/result; add canonical wallet overlay/projection; Create Task stops using old generic draft store; preserve asset behavior | Server call and wallet belong to monetization | CTC-006/015 | `test/monetization_test.dart` | monetization docs | Partly; coordinate DTO rollout |
| `lib/src/core/data/repositories.dart` | local domain repositories | `DriftMaintenanceRepository.savePlan`, `_savePlanMetadata` | wrap plan+metadata/inbox edit persistence in one Drift transaction | Local consistency for all callers | CTC-008 | home structure tests | data-model if contract noted | Independent after tests |
| `lib/src/core/sync/local_sync_store.dart` | canonical sync application/outbox | `acknowledgeTaskCreationComposite`, `applyRemoteRecords` | add strict `reconcileTaskCreationComposite`; preserve newer pending mutations; stop blind delete in new flow | Correct canonical local boundary | CTC-007, CTR-002 | task creation sync tests | sync protocol | With controller |
| `lib/src/core/sync/sync_dtos.dart` | remote/local record contract | `SyncRecord.fromRemote`, metadata specs | add strict task-creation canonical validation helper only if needed; do not globally loosen parser | Canonical response identity/types | CTC-006/007, CTR-003 | sync tests | sync docs | Coordinate with store |
| `lib/src/core/supabase/supabase_failure.dart` | shared Supabase error normalization | `SupabaseFailure.from` | add general retry classification for `40P01`/other verified transient states if appropriate; do not reuse completion-specific `PT409` message for task conflicts | Shared transport/database classification | CTC-012/014, CTR-001 | unit tests | backend/testing docs | Can be small independent change |
| `lib/src/core/utils/app_failure.dart` | generic localized failure codes | `AppFailureCode` | only extend if shared UI mapping is preferred; otherwise leave task-specific failures in feature layer | Avoid generic task-update fallback | CTC-012 | error tests | localization docs | Optional based on feature-layer mapping |
| `lib/main.dart` | current UI/providers/entry points | `showPlanEditorSheet`, `PlanEditorDialog`, `_EditorSheetFrame`, creation call sites | delegate creation to controller; preserve edit flow; submitting/dismissal/form/focus UX; use typed failures | UI only | CTC-003/012/013/016 | widget tests | feature catalog/localization | After controller |
| `lib/src/core/services/notification_service.dart` | scheduler + WorkManager rebuild | `HomePilotNotificationScheduler.refreshSchedules`, daily callback | no structural change expected; add diagnostics only if needed; preserve lifecycle reconstruction | CTC-011 already has eventual repair | CTC-011 | notification tests | architecture/ops if behavior changes | Mostly independent |
| `lib/src/core/services/reminder_schedule_reconciler.dart` | persisted reminder snapshot diff | `DriftReminderScheduleStore` | likely test-only; add dirty state only if Phase 0 proves reconstruction gap | avoid duplicate recovery design | CTC-011 | reconciler tests | notification docs | No change expected |
| `lib/l10n/app_en.arb` | English strings | new task-creation states/errors | add field limits, creating/confirming, unknown outcome, retry, draft failure, reconciliation warning | user-safe recovery | CTC-012/013/016 | widget/localization | localization docs | With UI |
| `lib/l10n/app_ar.arb` | Arabic strings | matching keys | complete Arabic parity and RTL-safe wording | localization contract | CTC-012/013/016 | Arabic widget tests | localization docs | With English ARB |
| `test/task_creation_controller_test.dart` | **New** orchestration tests | fake gateway/store/clock/UUID | restart, timeout, single-flight, payload freeze, result validation, failure transitions | central behavioral safety net | many client IDs | itself | testing docs | With controller |
| `test/task_creation_sync_test.dart` | current happy canonical acknowledgement test | LocalSyncStore tests | replace/extend with strict identity, null, account, newer edit, outbox preservation | reconciliation regressions | CTC-007, CTR-002 | itself | testing docs | With sync store |
| `test/monetization_test.dart` | monetization/store unit tests | secure store, DTOs | strict response parser, storage error/legacy behavior where applicable, wallet overlay | CTC-006/009/015/017 | itself | testing docs | With feature changes |
| `test/home_structure_repository_test.dart` | repository/stream tests | `savePlan` | metadata failure rollback and plan/metadata atomicity | CTC-008 | itself | none normally | Independent |
| `test/widget_test.dart` | UI regression/goldens | `PlanEditorDialog`, fakes | entry-point consistency, duplicate submit, dismissal, loading, errors, Arabic/RTL/semantics | CTC-003/012/016 | itself | localization/testing | After controller |
| `integration_test/supabase_sync_test.dart` | existing integration test surface | integration scenarios | add non-production Create Task canonical local/cloud/derived-state scenario if integration environment supports authenticated local Supabase | end-to-end | CTC-002/007/011/015 | itself | testing docs | After backend+client |
| `docs/architecture/system-overview.md` | component ownership | data flow | document task creation controller and server-first new-task path | architectural change | multiple | N/A | itself | same client PR |
| `docs/architecture/monetization.md` | point-gated creation rules | point-debited creation/offline behavior | durable operation identity, v2 replay contract, unknown outcome | financial contract | CTC-002/004/005 | N/A | itself | same backend/client PRs |
| `docs/architecture/sync-protocol.md` | durable sync/retry | operation durability/local reconciliation | distinguish charged-creation journal from generic outbox; preserve later edits | CTC-002/007, CTR-002 | N/A | itself | client PR |
| `docs/backend/migrations-and-functions.md` | migration/RPC rules | function conventions | document `p_`/`v_`, aliases, task RPC response/idempotency | CTC-001/004/005 | N/A | itself | backend PR |
| `docs/backend/supabase.md` | backend security/local dev | RPC/RLS section | document public invoker/private definer and task creation contract | authorization | CTC-005 | N/A | itself | backend PR |
| `docs/development/testing.md` | test policy | monetization matrix | add task create timeout/replay/concurrency/reconcile commands/tests | all | N/A | itself | each relevant PR |
| `docs/product/feature-catalog.md` | product capabilities | monetization/offline task creation | clarify unfinished offline draft and server-confirmed new tasks | CTC-002/009 | N/A | itself | client PR |
| `docs/development/localization-and-rtl.md` | localization rules | forms/errors | add task-create state coverage if new patterns need guidance | CTC-012/016 | N/A | itself | UI PR if needed |
| `docs/SENTRY_OPERATIONS.md` | observability privacy | allowed fields | update only if new task creation tags/breadcrumbs add a new approved field category | observability | all diagnostics | N/A | itself | Phase 9 if needed |
| `PRIVACY.md` | data handling | sync/monetization metadata | review secure operation journal; update only if retention/data handling materially changes | draft journal | CTC-002/010 | N/A | itself | client PR review |
| `CHANGELOG.md` | release-facing changes | unreleased section | note task creation correctness/retry recovery after implementation | user-facing fix | all | N/A | itself | each delivery as appropriate |

No Drift schema file is expected to change for the operation journal under this plan. If implementation discovers that secure storage cannot safely enumerate/persist concurrent operation records, stop and propose a separate Drift schema design; do not silently add a new table because it changes backup/account-cleanup scope.

---

# 10. SQL and migration plan

## Migration A — emergency identifier repair

**Proposed filename pattern:** `supabase/migrations/<UTC timestamp>_fix_task_creation_rpc_identifier_ambiguity.sql`.

**Objects:** replace `homepilot_monetization_private.create_task_with_point_debit_impl(jsonb)` only; public wrapper remains `public.create_task_with_point_debit(jsonb)`.

**Security:** private implementation `SECURITY DEFINER`, `set search_path = ''`; public wrapper remains `SECURITY INVOKER`; preserve current revoke/grant pattern.

**Naming convention:** parameters `p_...`; PL/pgSQL locals `v_...`; all SQL columns referenced through aliases. Example acceptable local names are `v_plan_id`, `v_caller_id`, `v_next_balance`, and `v_charge` because they do not collide with column names when columns are always qualified.

**Known failure addressed:**

```text
SQLSTATE 42702
column reference "plan_id" is ambiguous
```

Replace expressions structurally, not cosmetically. Prefer:

```sql
select p.*
into v_plan_row
from public.maintenance_plans as p
where p.user_id = v_caller_id
  and p.id = v_plan_id;

select m.*
into v_metadata_row
from public.maintenance_plan_metadata as m
where m.user_id = v_caller_id
  and m.plan_id = v_plan_id;
```

Then build JSON from the row variables. This prevents a future inline subquery from reintroducing the same collision.

**Compatibility:** no request/response field removal; preserve current canonical `plan` and `metadata` fields introduced August 6.

**Migration tests:** create with metadata, create without metadata, exact replay, safety/free task, insufficient points, and rollback state.

**Rollback limitation:** never edit the deployed August 6 file. A regression requires another forward `create or replace function` migration.

## Migration B — idempotency, concurrency, and response v2 hardening

**Proposed filename pattern:** `supabase/migrations/<UTC timestamp>_harden_task_creation_idempotency.sql`.

### `creation_point_operations` changes

Add:

- `request_version` (`smallint` or integer) with a legacy-safe default/version marker.
- `request_hash text null` for historical compatibility.
- check constraint: null or exact lowercase 64-hex SHA-256 representation.

Do not backfill a guessed hash for historical rows.

### Request fingerprint

The server computes the hash; the client does not supply it as authority. Hash the normalized semantic request, not the raw JSON byte order. At minimum include:

- entity type = `task`;
- plan ID;
- asset ID;
- trimmed title;
- normalized instructions (`null` for blank);
- recurrence interval/unit;
- priority;
- normalized `next_due_date` timestamptz representation;
- reminder days default;
- requested health group;
- enabled default;
- normalized metadata fields;
- required materials array contents;
- dependency plan IDs in deterministic set order if dependency ordering has no product meaning.

Do not include charge, wallet balance, user ID supplied in payload, or other server-owned fields.

Phase 0 must verify SHA-256 availability. Use `pgcrypto.digest` in the approved extensions schema. If the extension is absent, the migration may enable `pgcrypto` according to Supabase extension conventions; do not substitute MD5 merely to avoid the extension dependency.

### Operation serialization

Use a transaction-level advisory lock derived from the UUID before the first operation lookup. The exact lock key generation must be deterministic and covered by SQL tests. A hash collision may serialize unrelated operations but must never weaken correctness.

The shared asset creation implementation must acquire the same operation lock before consulting/inserting the global `creation_point_operations` key, even if asset request hashing is left unchanged in this task-focused remediation. This prevents task-versus-asset collision races.

### Lock order

For task creation:

1. operation advisory lock;
2. operation lookup/validation;
3. owned active asset validation;
4. wallet row `FOR UPDATE`;
5. optional defensive operation recheck through the same validator;
6. current config read and server charge calculation;
7. inserts/updates.

No creation function may acquire wallet first and then the operation advisory lock.

### Payload validation

Before writes:

- `p_operation` object and size;
- valid UUID operation ID;
- plan object and metadata object;
- plan/asset IDs nonblank and within schema bounds;
- title length 1–200 after trim;
- recurrence interval positive integer;
- recurrence unit enum;
- priority enum;
- valid timestamptz;
- reminder nonnegative integer;
- health group enum;
- metadata task type, location, duration, reminder text limits;
- required-materials and dependency fields arrays of strings.

Server remains authoritative even though the client mirrors these checks.

### Authorization

- `v_caller_id := auth.uid()`; null → `AUTH_REQUIRED`.
- Asset query scoped by caller and active status; missing/foreign/inactive → `ASSET_NOT_FOUND`.
- Safety/free classification comes from the server-owned asset/category relation.

### Charge and balance

- Read the wallet under `FOR UPDATE`.
- If effective charge is 1 and balance < 1 → `INSUFFICIENT_POINTS` before task writes.
- Never trust a client charge or projected balance.
- Update wallet with a checked transition and return canonical wallet row.

### Idempotency behavior

- **Same operation, same owner/type/entity, same non-null hash:** return `already_processed = true`, canonical existing task/metadata, and current canonical wallet; no new writes/debit.
- **Same operation, same identity, different hash:** return stable `OPERATION_PAYLOAD_MISMATCH`; no writes.
- **Same operation, different owner/type/entity:** return stable `OPERATION_ID_REUSED`; no data from another user in the response.
- **Legacy existing operation with null hash:** require exact caller/type/entity match; return canonical existing result with a response flag/version indicating legacy replay. Do not pretend to validate payload equality.
- **Operation exists but canonical associated task is unexpectedly missing/inconsistent:** return stable `OPERATION_STATE_CORRUPT`/`OPERATION_RESULT_UNAVAILABLE`; never recreate or recharge automatically.

### Return shape

Add a response version while retaining current fields for older clients. Recommended v2 object:

```json
{
  "version": 2,
  "operation_id": "uuid",
  "task_id": "plan-id",
  "balance": 6,
  "charged": 1,
  "already_processed": false,
  "plan": { "...": "canonical row" },
  "metadata": { "...": "canonical row or null" },
  "wallet": { "user_id": "...", "balance": 6, "updated_at": "..." }
}
```

The new client validates all identity fields and `wallet.balance == balance`.

### SQLSTATE/error strategy

Use stable five-character SQLSTATE plus safe domain message. Do not expose raw cast/constraint text.

- `42501` + `AUTH_REQUIRED`.
- `22023` + `INVALID_OPERATION`, `INVALID_OPERATION_ID`, or `INVALID_TASK_PAYLOAD`.
- `23503` + `ASSET_NOT_FOUND` where appropriate.
- `P0001` + `INSUFFICIENT_POINTS`, `WALLET_NOT_FOUND`, `OPERATION_PAYLOAD_MISMATCH`, or stable operation-state error.
- `23505` may remain `OPERATION_ID_REUSED` if client task-specific mapping treats it as permanent; do not let the generic `23505` “retryable conflict” mapping override the task-specific meaning.
- `40001` and `40P01` are transient database concurrency outcomes and may be retried only with the same durable operation.
- `42702` is treated by new clients as an incompatible/server defect; after Migration A it must not be emitted by this function.

### Owners and grants

After replacement, tests MUST assert:

- public task RPC is not security definer;
- private implementation is security definer;
- fixed empty search paths;
- anonymous cannot execute;
- authenticated cannot directly mutate wallet/ledger/operation tables;
- service-role rights remain only where currently intended.

---

# 11. Atomicity and consistency plan

The following table is normative for implementation tests.

| Failure point | Cloud plan | Cloud metadata | Wallet | Ledger | Server idempotency row | Local operation journal | Local task | Notification | Client-visible balance |
|---|---|---|---|---|---|---|---|---|---|
| Before operation/wallet lock | absent | absent | unchanged | none | absent | `draft` or known rejection | absent | none | prior balance |
| After operation lock, before wallet lock | absent | absent | unchanged | none | absent unless replay existed | submitted/known rejection | absent | none | prior/current streamed balance |
| Existing exact idempotency hit | existing canonical | existing/null canonical | unchanged by replay | no new row | existing | move toward accepted/reconcile | reconcile canonical | schedule after local reconcile | current returned wallet |
| Payload mismatch/reused operation | no new row | no new row | unchanged | no new row | existing prior op only | permanent rejected/conflict; original preserved | do not create requested new task | none | current wallet |
| After wallet lock, insufficient points | absent | absent | unchanged | none | absent | permanent insufficient state, editable form retained | absent | none | returned/refreshed current balance |
| After task insert but before metadata | transaction-local only | absent | unchanged yet | none | absent | submitting | absent locally | none | prior until transaction resolves |
| Metadata insert fails | rolled back | rolled back | unchanged | none | absent | permanent invalid/server failure | absent | none | prior/current |
| After metadata, before wallet update | transaction-local only | transaction-local only | unchanged | none | transaction-local if already inserted | submitting | absent | none | prior |
| Wallet update then ledger insert fails | rolled back | rolled back | wallet update rolled back | none | rolled back | server failure/unknown based transport | absent | none | refresh to actual unchanged wallet |
| During return-object construction before commit | all writes roll back | roll back | roll back | roll back | roll back | request failed; exact retry allowed | absent | none | unchanged authoritative wallet |
| Commit succeeds, response delivered | committed | committed/null | committed | exactly one if charged | committed | `serverAcceptedNeedsReconcile` | reconcile canonical next | after local reconcile | immediately use returned canonical wallet |
| Commit succeeds, response lost | committed | committed/null | committed | exactly one if charged | committed | `outcomeUnknown` survives restart | may arrive through normal sync; controller must not duplicate | eventual after canonical local task exists | Realtime may update; exact replay returns current canonical wallet |
| Client reconciliation fails | committed | committed/null | committed | committed | committed | `serverAcceptedNeedsReconcile` | may be absent or previous local state | do not schedule from uncommitted local state | canonical returned balance remains authoritative |
| Newer local edit exists during reconcile | committed create + server may not yet have edit | canonical create metadata | committed | committed | committed | accepted/reconciling | preserve newer local edited row | schedule from final local row | canonical returned balance |
| Reminder scheduling fails | committed | committed/null | committed | committed | committed | `reconciled` | canonical local task present | immediate reminder may be missing; global refresh repairs | canonical balance |
| Journal cleanup fails after full success | committed | committed/null | committed | committed | committed | terminal `reconciled` record remains, ignored as draft | canonical | scheduled/recoverable | canonical balance |

## Rollback versus reconciliation

Database failures before PostgreSQL commit MUST roll back the complete server operation; no compensation/refund is needed because no debit committed.

Failures **after** database commit are reconciliation problems. Do not delete the cloud task or refund automatically because the authoritative task and charge are already consistent. The client instead replays the same operation to retrieve canonical state and completes local reconciliation.

Notifications are always post-commit derived state and are repaired, not transactionally rolled back.

---

# 12. Monetization plan

## Authoritative pricing

The private RPC is the sole authority for task cost. Current rules derive charge as 0 or 1 based on server configuration and safety classification. The client may show informational wallet/config data but MUST NOT send or trust an effective charge.

## Invariants

1. **Paid success invariant:** one successful paid task creation produces exactly one task row, one canonical metadata state (row or explicit absence), one creation operation row, one debit ledger row, and one final balance transition.
2. **Free success invariant:** one successful free task produces the task/metadata/operation, zero task-debit ledger rows, and no balance decrease.
3. **Failure invariant:** any server failure before commit produces no task, no metadata, no creation-operation row, no wallet change, and no task-debit ledger row.
4. **Replay invariant:** exact retry produces no additional task/debit/ledger transition.
5. **Balance invariant:** wallet balance never falls below the database-enforced minimum; `point_transactions.balance_after = balance_before + amount` remains enforced.
6. **Authorization invariant:** charge/free state and asset ownership cannot be overridden by request fields.

## Constraints/indexes to preserve or verify

- `point_wallets.user_id` primary key and effective balance check (currently widened by later migration to a nonnegative bounded range).
- `point_transactions` balance consistency check.
- unique `(user_id, idempotency_key)` on ledger.
- `creation_point_operations.operation_id` primary key.
- unique `(user_id, entity_type, entity_id)` preventing multiple operation records for one created entity.
- new request-hash shape check.
- maintenance plan composite ownership foreign key.
- metadata composite foreign key.

## Insufficient and exact balance

- Balance 0 + charged task → reject before task writes.
- Balance 1 + charged task → success, balance 0.
- Two concurrent charged operations with balance 1 → wallet lock yields one winner; the loser observes insufficient balance and creates nothing.

## Concurrent non-task debit

Asset creation and any other wallet-debit operation that uses the same wallet row are serialized by `FOR UPDATE`. The plan does not change reward settlement semantics, but concurrency tests should include one task debit racing one other creation debit if test fixtures can do so safely.

## Ledger semantics and compensation

Task creation ledger idempotency key remains derived from the operation ID (for example, the current `create-task:<operation_uuid>` convention). A committed ledger row proves a committed charged creation operation.

No automatic refund is required for local reconciliation or notification failure because the cloud task exists. Refund/admin adjustment remains an operational response to a verified server-side integrity incident, not a client retry mechanism.

## Balance reconstruction and display

The ledger plus wallet constraints provide server auditability. The v2 response returns canonical wallet state. Client UI projects that canonical wallet immediately, then allows Realtime to supersede it when it observes the same/newer update.

---

# 13. Idempotency and retry plan

## Operation generation/persistence

- Generate UUIDv7 operation and plan IDs before first submission.
- Persist them in `TaskCreationOperationStore` before any request.
- Store exact normalized request JSON and submission state.
- The controller receives injected ID/clock providers in tests; production uses the repository's UUID convention.

## Fingerprint

The server computes the canonical request fingerprint described in section 10. The client persists the exact request it sent but does not decide whether a hash is authoritative.

## Retry rules

| Situation | Required behavior |
|---|---|
| Same ID + exact same payload, first response succeeded | return prior canonical result, no new debit |
| Same ID + exact same payload, first response lost | return prior canonical result, client reconciles |
| Same ID + changed payload, operation committed under v2 | permanent `OPERATION_PAYLOAD_MISMATCH`; do not mutate prior task |
| Same global ID belongs to different account/entity/task | permanent `OPERATION_ID_REUSED`; do not reveal other user's canonical data |
| Submitted client operation times out | mark `outcomeUnknown`; retry same ID/payload |
| Transport fails before request can be proven sent | conservative default is still same ID/payload; do not mint a new one solely from transport inference |
| Known invalid payload/asset/auth rollback | preserve form; user repairs state; if semantic payload changes, create a new operation before resubmit |
| Insufficient points | preserve exact operation; after earning points an unchanged request may retry same ID because server committed nothing |
| Existing server operation but canonical task missing | return stable operation-state error; never recreate/recharge automatically |

## Retention

Server operation rows are replay/fraud-prevention records and remain under existing server retention/deletion policy. Local reconciled journals may be deleted after successful local reconciliation, but cleanup failure must be harmless because state is terminal.

## Older queued/client compatibility

Legacy operation rows without request hashes use identity-only replay compatibility. New clients treat such a response as a legacy replay but may still reconcile canonical rows. Older supported clients continue to call the same public function and ignore added response fields.

Generic `offline_mutation_queue` records from older clients remain syncable if server authorization already exists. The new client does not add a blind paid-task creation mutation to that queue.

---

# 14. Concurrency plan

## One widget / rapid gestures

`TaskCreationController` rejects a second submit while its active operation is submitting/unknown/reconciling. Buttons and keyboard actions call the same method. UI `_saving` may remain as presentation state but is not the correctness boundary.

## Two Create Task entry points in one app process

Use one non-auto-disposed/suitably scoped `taskCreationControllerProvider` for new charged/server-authorized creation. A second editor observes the active operation and cannot start another charged submit until it is durable/reconciled. It may save a separate editable draft only if the operation store supports it; it may not submit concurrently without explicit controller support.

## Two app processes / two devices

Correctness comes from the server:

- operation advisory lock serializes identical operation IDs;
- wallet `FOR UPDATE` serializes balance transitions for the same user;
- operation/entity unique constraints prevent duplicate operation records;
- maintenance plan primary key prevents duplicate same-ID task rows;
- ledger idempotency unique constraint prevents duplicate debit rows.

Different legitimate operations may both succeed if balance permits.

## Lock order and deadlock avoidance

1. operation advisory lock;
2. wallet row lock;
3. task/metadata/operation/ledger writes.

Do not introduce a reverse wallet→operation path in task or asset creation. Reward settlement that only locks wallet cannot form the inverse dependency because it does not then request the creation-operation advisory lock.

## Isolation assumptions

The implementation runs under PostgreSQL's normal transaction semantics. Do not depend on stale pre-lock balance reads for correctness. All balance decisions use the locked wallet row.

## Retryable SQLSTATEs

Treat verified transient concurrency codes such as `40001` and `40P01` as retryable with the **same operation**. Do not classify `OPERATION_ID_REUSED` or payload mismatch as retryable.

## Expected outcomes

- Two distinct tasks, one remaining point: one success, one insufficient; no negative balance.
- Duplicate PostgREST delivery: first creates; second exact-replays.
- Same operation with altered payload: committed original wins, altered request is rejected.
- Realtime wallet/task update arriving during controller execution: it may update display/local sync, but controller validates operation result and preserves any newer local mutation during reconciliation.

---

# 15. Offline and synchronization plan

## Chosen model

New task creation is **online-confirmed with an offline draft**, not optimistically local and not blindly queued for future authorization. This applies even when the server may ultimately determine charge = 0, because the client is not authoritative for that decision.

## Scenario contract

| Scenario | Local draft/journal | Local maintenance task | Cloud | Recovery |
|---|---|---|---|---|
| No network before submit | `draft` saved | absent | unchanged | user resumes draft; submit when online |
| Secure-store write fails | not safely saved | absent | no request sent | keep editor open; explicit storage error |
| Intermittent network after send | `outcomeUnknown` | absent unless normal sync independently pulls committed task | unknown until replay/sync | exact replay same operation |
| Auth expired | operation retained/account scoped | absent unless prior commit pulled | no new commit | reauthenticate same account, retry exact request if appropriate |
| Sign out | user-scoped unresolved op retained but not exposed to other account | synced data cleanup follows existing account policy | unchanged | same-user resume only according to account cleanup policy |
| Account switch | operation remains bound to original user | never submitted under new account | unchanged for new account | do not auto-rebind |
| Signed-out local draft then sign-in | local-scoped draft | absent | unchanged | explicit claim/resume into active account; do not silently submit |
| Multiple drafts | separate operation records | absent until each success | independent | list/choose resume; no overwrite |
| Insufficient points | exact operation retained with known rollback state | absent | unchanged | earn points then exact retry; edit creates new op identity |
| Out-of-order separate creates | independent records | each appears after success | wallet lock orders debits | reconcile by operation identity, not local timestamp |
| Edit before creation reconciliation | only possible if cloud task was pulled and became visible | local edit/outbox may exist | create committed | reconciliation checkpoints canonical but preserves edit/outbox |
| Delete before creation reconciliation | same principle as edit | delete mutation preserved | create committed until delete sync | creation reconcile must not erase delete intent |
| Permanent server rejection | rejected journal/form retained | absent | unchanged | user repairs field/account/balance state; no phantom task |
| Local reconcile failure | `serverAcceptedNeedsReconcile` | absent/partial prior state | committed | replay same operation and reconcile; no re-debit |
| Server success + client timeout | `outcomeUnknown` | maybe later pulled | committed | exact replay; canonical result returned |
| Older payload version | accepted by compatible server path | normal | normal | server returns compatible/versioned result; new client handles documented legacy replay |

## Generic sync queue

Do not insert a new unpaid task creation into `offline_mutation_queue`. After canonical server success, `LocalSyncStore` applies the task as remote canonical state with outbox suppression. Later user edits naturally generate ordinary outbox mutations.

A legacy generic mutation left by an older flow is not deleted blindly. Existing RLS allows authorized reconciliation for an already-created task; sync may perform a redundant update but must not charge again.

## Permanent visibility rule

A locally visible paid/server-authorized task must always be one of:

- canonical cloud-backed state; or
- canonical cloud-backed state with an explicit newer local edit queued.

There is no indefinite “looks-created but never authorized” state.

---

# 16. Client UI and Riverpod plan

## Controller/provider

Introduce `taskCreationControllerProvider` owning new-task submission. It must be shared across all Create Task entry points in the process and must not be disposed merely because the modal closes while an operation is active.

## State exposed to UI

At minimum:

- idle/editing draft;
- saving draft;
- submitting;
- outcome unknown/confirming;
- reconciling;
- success;
- insufficient points;
- permanent validation/auth/asset rejection;
- local storage/reconciliation failure;
- nonfatal reminder warning.

## Button and keyboard behavior

- Primary and “Create and Add Another” are disabled during a non-idle active submission.
- Keyboard submit invokes the same controller method.
- Two input events in one frame are coalesced by controller single-flight.
- The controller, not widget state, decides whether another operation may start.

## Form validation

Mirror server boundaries without treating client validation as authority:

- title trimmed nonempty and <= 200 characters;
- recurrence interval > 0;
- reminder >= 0;
- metadata duration 1–1440 when present;
- task type <= 80 and nonblank if present;
- location <= 200;
- reminder recommendation <= 500;
- required/dependency collections serialize as arrays of strings.

Add localized field errors rather than a generic toast.

## Navigation/disposal

- Before a submitted operation is durably journaled, prevent dismissal.
- Once durable, dismissal may be permitted only if UX clearly indicates creation continues/needs confirmation; simpler first implementation may keep dismissal blocked through reconcile.
- A disposed widget never cancels or owns the server operation.
- Controller state remains recoverable after route destruction.

## Failure UX

- Known validation: show field error, preserve all values.
- Insufficient points: existing earn-points flow, preserve exact operation.
- Auth expired: require sign-in; preserve draft.
- Offline before submit: show “saved as unfinished draft” only after storage confirms.
- Outcome unknown: show confirming/retry same-operation action; do not tell user “try creating again.”
- Server schema defect (`42702`/incompatible): show service/update error; keep operation; do not expose SQL.
- Local reconciliation failure: show “Task was saved online; HomePilot is finishing it on this device” with retry/automatic recovery; do not charge again.

## Success/refresh

Final success happens after canonical local reconciliation. `tasksProvider` and other Drift-backed views should update naturally. Point UI consumes the authoritative wallet overlay. Only explicitly stale providers are invalidated after tests prove need.

---

# 17. Local Drift persistence plan

## Tables involved

Existing:

- `maintenance_plans`.
- `maintenance_plan_metadata`.
- `offline_mutation_queue` for later ordinary edits.
- `sync_shadows` / `sync_cursors` through `LocalSyncStore`.
- `reminder_schedule_snapshot` for derived notification state.

No new Drift table is planned for the pre-RPC creation journal; it remains secure device-local draft/operation state. This avoids making an unpaid operation part of backup/sync/domain tables.

## `DriftMaintenanceRepository.savePlan`

Wrap current validation-dependent write body in one transaction:

- lookup existing plan inside the transaction where practical;
- insert/update plan;
- insert/update metadata;
- mark plan inbox read for edit path;
- allow trigger-generated outbox state to commit with the domain write.

If metadata fails, the plan change rolls back.

## New online task creation

After server success, do **not** call `savePlan`. Call `LocalSyncStore.reconcileTaskCreationComposite` and apply canonical remote data under outbox suppression. Thus the new task itself does not produce a generic local upsert mutation.

## Newer local mutations

If local plan/metadata outbox exists when canonical creation state arrives, treat it as a post-create user mutation unless an exact legacy-creation fingerprint proves otherwise. Preserve it. Save the canonical remote shadow/checkpoint and let normal sync push the newer local edit.

## App termination

- Before RPC: durable journal has draft/submitting state; no maintenance row exists.
- After server commit but before local apply: journal is submitting/unknown/accepted; normal sync may independently pull the task; replay remains safe.
- During local reconciliation: Drift transaction rolls back or commits atomically.
- After local commit but before journal cleanup: terminal journal state prevents duplicate presentation/submission.

## Schema migration requirements

None expected. If secure-storage enumeration/atomic record behavior is insufficient in Phase 0, a new Drift operation table becomes a separate architecture decision requiring schema version increment, generated-code changes, backup/account-deletion review, and migration tests. It is not an implicit fallback.

---

# 18. Notification consistency plan

## Scheduling point

Schedule/reconcile reminders only after canonical local task state is durable. The scheduler reads local task state, so scheduling before local reconciliation would create a race with missing/stale data.

## Failure behavior

- Notification failure never rolls back server task/point state.
- The controller reports a nonfatal reminder-warning diagnostic.
- The user may receive a concise localized warning only if product UX decides immediate reminder assurance is important; do not turn successful task creation into a failure.

## Retry mechanism

Preserve and test existing:

- immediate create-path refresh;
- startup `NotificationBootstrap` refresh;
- app-resume refresh;
- daily WorkManager refresh;
- persisted `DriftReminderScheduleStore` snapshots and idempotent diff.

Add a new persistent dirty marker only if deterministic failure tests show that the existing global refresh cannot converge.

## Duplicate prevention

Continue deriving stable task/snooze notification IDs and compare desired/current `ReminderScheduleEntry` identities. Tests must fail if a second recovery refresh schedules duplicate OS notifications or duplicate snapshot rows.

## Rollback/rejection

Because rejected new tasks never enter local maintenance tables, no creation reminder exists to cancel. If an operation is server accepted and later the task is legitimately deleted, existing task deletion/reminder cancellation paths own cleanup.

## Timezone

Use the existing scheduler timezone configuration. Test creation before/after timezone change and ensure schedule snapshot captures timezone/local components consistently.

---

# 19. Error-handling plan

| Technical condition | Domain failure | Retry? | User behavior/message intent | Log/Sentry | Preserve form? | Task visible? | Balance behavior | Recovery |
|---|---|---|---|---|---|---|---|---|
| SQLSTATE `42702` | `backendIncompatible` | Not blind-auto; backend fix required | “Task creation is temporarily unavailable. Your task details are saved.” | error/Sentry unexpected; safe code only | Yes | No unless prior cloud commit from another attempt | refresh/stream actual | keep operation, retry after service fixed |
| `INVALID_TASK_PAYLOAD` / `22023` | `invalidInput` | After edit | field-specific/generic invalid details | info/warn, no Sentry for expected validation | Yes | No | unchanged | edit fields; new op if submitted payload changes |
| `AUTH_REQUIRED` / expired auth | `authenticationRequired` | After reauth | sign in again; draft retained | info/warn | Yes | No unless prior commit | refresh after auth | reauth same account, resume |
| foreign/missing/inactive asset | `assetUnavailable` | After user selects valid asset | related item unavailable | info/warn | Yes | No | unchanged | select active owned asset |
| `INSUFFICIENT_POINTS` | `insufficientPoints` | Yes, same exact op after balance changes | existing earn-points flow | normal analytics if approved, no exception Sentry | Yes | No | show current canonical balance | earn points, retry |
| `OPERATION_ID_REUSED` | `operationConflict` | Permanent for that local op | operation could not be confirmed; regenerate only after safe resolution | error/Sentry if unexpected UUID collision | Yes | No requested new task | refresh | do not expose other result; support diagnostics |
| `OPERATION_PAYLOAD_MISMATCH` | `payloadConflict` | No for altered payload | submitted task cannot be changed under same request; preserve form | warning/error | Yes | original task may exist | current wallet | reconcile original; create a new op for intentional new payload |
| `40001` / `40P01` | `transientDatabaseConflict` | Yes same op | “HomePilot is retrying/try again” | warning; Sentry only if repeated | Yes | unknown until retry | refresh | bounded same-op retry |
| application timeout | `outcomeUnknown` | Yes same op | “Confirming whether the task was created…” | warning with phase/retry count | Yes but submitted fields frozen | not until canonical local state | Realtime/returned replay | exact replay |
| network unavailable before/while send | draft or `outcomeUnknown` depending stage | Yes | unfinished draft / confirming | info/warn | Yes | No unless prior commit pulled | stream actual | reconnect, exact operation |
| server 5xx/rate limit | `serverUnavailable` | Yes same op if submission may have reached server | temporary service issue | warning/Sentry threshold | Yes | unknown until replay | refresh | bounded retry/manual |
| local secure-store failure before send | `localDraftPersistenceFailed` | After storage works | cannot safely save/submit yet | error/Sentry actionable | Yes in open form | No | unchanged | keep dialog open |
| local Drift reconciliation failure after commit | `reconciliationFailed` | Yes | saved online, finishing locally | error/Sentry | Yes or frozen submitted view | may be absent | use returned canonical wallet | replay+reconcile same op |
| reminder refresh failure | `reminderRefreshDeferred` | automatic | task created; reminders will refresh | warning, usually no Sentry unless repeated | N/A | Yes | canonical | startup/resume/daily repair |

Raw SQL, table names, stack traces, PostgREST payloads, and database function internals MUST NOT appear in localized user messages.

---

# 20. Test implementation plan

The following matrix is the minimum. Test names are proposed and may be adapted to repository naming style without changing assertions.

| Proposed test | IDs | Level/file | Setup/fakes | Action | Expected assertions | Must fail before fix? |
|---|---|---|---|---|---|---|
| `task RPC current effective function reproduces ambiguous metadata identifier` | CTC-001 | pgTAP `0012...` | local final migrations, task+metadata fixture | invoke RPC | pre-fix `42702`; post-fix lives and returns canonical metadata | Yes |
| `ambiguous return failure rolls back all task debit state` | CTC-001 | SQL | snapshot counts/balance | invoke failing function in baseline fixture | plan/meta/op/ledger unchanged, balance unchanged | Baseline assertion documents current behavior |
| `task creation with metadata commits one debit and canonical rows` | CTC-001 | pgTAP | balance >=1 | create | one task/meta/op/debit, expected balance | Existing task test should expose current bug |
| `task exact replay is idempotent` | CTC-004 | pgTAP | committed v2 op | repeat identical request | already processed, counts unchanged | Partially existing; strengthen |
| `task operation payload mismatch is rejected` | CTC-004 | pgTAP | commit original | same op+plan, changed title/recurrence/meta | mismatch code, original unchanged, no debit | Yes |
| `post-lock operation lookup cannot adopt another plan` | CTC-005 | two-session SQL/script | deterministic barrier | race same op with distinct task IDs | one canonical operation only; loser stable error | Yes |
| `cross-user operation collision reveals no canonical row` | CTC-005 | RLS/concurrency | two auth contexts same UUID | race calls | loser gets safe conflict; no foreign task JSON | Yes |
| `one remaining point supports one concurrent task debit` | CTC-005 | existing `tool/test_points_concurrency.ps1` | balance=1 | two distinct ops | one success, one insufficient, balance=0, one ledger debit | Existing should pass after CTC-001 repaired |
| `strict task result rejects missing canonical plan` | CTC-006 | unit `monetization_test` or controller test | malformed map | parse | typed incompatible result | Yes |
| `strict task result rejects wrong task id/wallet balance mismatch` | CTC-006/007/015 | unit | malformed IDs/balance | parse/reconcile | no local mutation | Yes |
| `reconcile rejects canonical plan for another id` | CTC-007 | Drift `task_creation_sync_test` | expected P canonical Q | reconcile | throws; local/outbox unchanged | Yes |
| `reconcile rejects canonical user mismatch` | CTC-007 | Drift | bound user A canonical B | reconcile | transaction aborted | Yes |
| `reconcile allows null metadata when request has no metadata` | CTC-007 | Drift | canonical plan only | reconcile | plan applied, no metadata row | New contract |
| `reconcile preserves newer plan edit outbox` | CTR-002 | Drift barrier | canonical create + pending plan edit | reconcile | local edit/outbox remains; canonical shadow saved | Yes/likely |
| `reconcile preserves newer metadata edit outbox` | CTR-002 | Drift | pending metadata edit | reconcile | edit/outbox remains | Yes/likely |
| `savePlan rolls back plan when metadata write fails` | CTC-008 | repository | inject invalid metadata/DB fault | savePlan | neither plan nor metadata/outbox committed | Yes |
| `operation store write failure prevents network request` | CTC-009 | controller/store | secure storage throws | submit | gateway call count 0; typed failure; form retained | Yes |
| `multiple task drafts do not overwrite` | CTC-010 | store | save two op IDs same user/asset | list/load | both records recover | Yes |
| `local draft is not auto-resumed under a different user` | CTC-010 | controller | local/user-scoped records | switch account | no automatic submit | Yes |
| `legacy context-key draft imports preserving IDs` | CTC-010 | store | seed v1 key | load/resume | v2 record same op/plan; legacy cleanup attempted | New compatibility |
| `journal cleanup failure does not resurrect completed task` | CTC-017 | store/controller | delete throws after reconcile | reopen | completed journal ignored/resolved, no new submit | Yes |
| `timeout after server commit reuses exact operation` | CTC-002/CTR-001 | controller | fake gateway records commit then throws timeout; second call returns replay | submit then retry/restart | same IDs/payload, one logical charge, reconcile succeeds | Yes |
| `process restart from submitting resolves as unknown` | CTC-002 | controller/store | persisted submitting record | construct new controller | no new op; exact confirmation path | Yes |
| `process restart from accepted resumes local reconcile` | CTC-002 | controller/store | accepted journal/canonical replay | restart | canonical local task, no second debit call beyond idempotent replay | Yes |
| `dismiss while RPC pending cannot lose operation` | CTC-003 | widget | blocking gateway | tap create then close/back/drag | dismiss blocked or controller survives; no exception | Yes |
| `keyboard and button in same frame produce one submit` | CTC-003/016 | widget | fake controller/gateway | keyboard submit + tap | one controller call | Yes/coverage gap |
| `two Create Task editors share single flight` | CTC-003 | widget/controller | two entry contexts | submit both | second cannot initiate charged request while first active | Yes/coverage gap |
| `storage save error is not shown as draft saved` | CTC-009 | widget | throwing store offline | create | localized error, no success toast | Yes |
| `reminder failure after create is repaired on resume refresh` | CTC-011 | notification/widget | scheduler fails once then succeeds | create, trigger resume refresh | task remains; desired reminder appears once | Audit wording corrected; new regression |
| `creation error taxonomy maps stable codes` | CTC-012/014 | unit | representative PostgREST/errors | map | correct retryability/domain code | Yes |
| `user messages never contain raw SQL for 42702` | CTC-012 | widget | fake backend-incompatible failure | render | localized safe message only | Yes |
| `client title and metadata limits match cloud boundaries` | CTC-013 | unit/widget | limit-1/limit/limit+1 incl Arabic | validate | same accept/reject boundaries | Yes |
| `server rejects non-array metadata lists atomically` | CTR-003 | pgTAP | object/scalar/list with non-string | create | stable invalid payload, zero writes | Yes once risk confirmed |
| `RPC invalid numeric/date forms return stable invalid payload` | CTC-014 | pgTAP | overflow/invalid timestamptz | create | stable safe code, zero writes | Yes |
| `returned wallet overrides delayed realtime balance` | CTC-015 | provider/widget | stream remains old, RPC wallet newer | success | points pill shows new balance immediately | Yes |
| `realtime newer wallet supersedes RPC overlay` | CTC-015 | provider | emit later wallet | stream update | overlay cleared/newer wallet shown | New |
| `submitting UI exposes progress semantics in English` | CTC-016 | widget | blocking controller | submit | disabled actions, progress/live region, correct focus | Yes |
| `submitting/error UI works in Arabic RTL and large text` | CTC-016 | widget/golden | Arabic, text scale | submit/fail | RTL, no overflow, semantics localized | Yes |
| `due timestamp UTC roundtrip preserves local selected instant` | boundary | unit/integration | selected local date/time/timezone | serialize/canonical parse | same intended instant/date display | Coverage gap |
| `all recurrence units accepted consistently` | CTC-013 support | unit/pgTAP | enum fixtures | submit validation | hours/days/weeks/months/years match cloud | Coverage gap |
| `task appears in derived views after canonical reconcile` | derived state | integration/widget | canonical create | observe providers/screens | maintenance/asset/calendar/dashboard/search expected refresh | Coverage gap |
| `client edit after pulled uncertain create survives confirmation` | CTR-002 | integration/Drift | sync pull then local edit then replay | reconcile | edit remains queued, no charge duplication | Yes/behavioral risk |
| `config change while waiting on wallet follows documented snapshot rule` | CTR-004 | SQL concurrency | barrier around wallet/config | change config | deterministic agreed result | Depends on product decision |

### Test mechanics

- Prefer fake clocks and deterministic UUID generators.
- Use `Completer`/explicit barriers for widget/controller tests rather than `Future.delayed`.
- Use SQL advisory locks or separate local database sessions for true concurrency.
- Assert database state explicitly, not only returned JSON.
- Keep production config tests separate and use safe examples only.

---

# 21. Validation commands

Only repository-documented/configured commands are mandatory here.

## Bootstrap and generated sources

```powershell
flutter doctor
flutter pub get
flutter gen-l10n
dart run build_runner build
```

If no Drift schema is added, build-runner output may be unchanged, but run it because repository policy requires generated-code consistency after DAO/model changes.

## Targeted Flutter tests

These use the repository's documented `flutter test --no-pub` runner narrowed to existing/planned test files:

```powershell
flutter test --no-pub test/task_creation_controller_test.dart
flutter test --no-pub test/task_creation_sync_test.dart
flutter test --no-pub test/monetization_test.dart
flutter test --no-pub test/home_structure_repository_test.dart
flutter test --no-pub test/widget_test.dart
```

The implementation must also add/run the Create Task integration scenario in `integration_test/supabase_sync_test.dart`. The repository documentation does not currently specify a single canonical device invocation for that integration file, so do not invent a merge-gating command in this plan; record the emulator/device invocation used in the implementation PR and, if it becomes standard, add it to `docs/development/testing.md`.

## Formatting/static/full Flutter validation

Repository docs use the scoped form:

```powershell
dart format --output=none --set-exit-if-changed lib test integration_test
flutter analyze --no-pub
flutter test --no-pub --concurrency=1 --timeout 3m --exclude-tags production-config
```

The task request also cites `dart format --output=none --set-exit-if-changed .`; use the repository-documented scoped command above unless repository policy is intentionally updated.

## Local Supabase

```powershell
npm ci
npx supabase start
npm run supabase:lint
npm run supabase:test
```

The package scripts expand to local DB lint and the full `supabase/tests/database` suite. This is the required migration/RLS/RPC validation path.

Stop local services when finished:

```powershell
npx supabase stop
```

The repository documentation does not currently prescribe `supabase db reset` as a standard command; do not add an unverified reset command to the required checklist. `npm run supabase:test` must run against a local stack whose migrations were applied from a clean/reproducible state according to the Supabase CLI's documented local workflow.

## Existing concurrency helper

`tool/test_points_concurrency.ps1` is a repository test asset and should be run locally during backend hardening. Before making its exact shell invocation a mandatory documented command, add/verify that invocation in `docs/development/testing.md` in the implementation PR.

## Documentation validation

No separate docs linter is currently documented. Validate changed paths/links manually and run the ordinary formatting/analyze/test suites. Do not run production release or deployment commands.

---

# 22. Observability plan

## Structured events/breadcrumbs

Add privacy-safe events around the controller boundary, for example:

- `task_creation_started`.
- `task_creation_rpc_completed` with response version and duration bucket.
- `task_creation_outcome_unknown`.
- `task_creation_replay_completed`.
- `task_creation_reconcile_failed/succeeded`.
- `task_creation_reminder_refresh_deferred`.

Allowed fields SHOULD be limited to:

- application release/environment from existing Sentry context;
- operation phase;
- stable technical failure code;
- response protocol version;
- retry attempt count bounded to a small integer;
- elapsed milliseconds or coarse timing;
- charged amount 0/1 only if approved as non-sensitive operational metadata;
- an opaque short one-way operation fingerprint if correlation is required.

## Sentry classification

- Capture unexpected `42702`, operation-state corruption, repeated reconcile failure, secure-storage failure that blocks persistence, and protocol-shape defects.
- Expected invalid user input, ordinary offline state, and insufficient points should not create exception noise.
- Repeated transient failures may be promoted after a threshold with no task content attached.

## Data that must never be logged

- auth/session tokens, cookies, API keys, SSV signatures;
- full operation UUID if policy considers it a stable direct identifier; use a hash/fingerprint;
- user ID/email/name;
- task title or instructions;
- location labels;
- materials/dependency contents;
- raw request/response JSON;
- wallet transaction rows containing direct account identifiers;
- production credentials/secrets;
- local file paths or backup/media identifiers.

Observability changes must remain consistent with `docs/SENTRY_OPERATIONS.md` and `PRIVACY.md`.

---

# 23. Documentation plan

| Document | Section | Change | Phase/PR |
|---|---|---|---|
| `docs/architecture/system-overview.md` | Application/data flow | add `TaskCreationController`, server-confirmed new-task flow, local draft boundary | Phase 5 / client PR |
| `docs/architecture/monetization.md` | Point-debited creation, offline behavior, failure states, testing | payload-bound idempotency, durable operation journal, unknown-outcome replay, v2 wallet result | Backend hardening + client PRs |
| `docs/architecture/sync-protocol.md` | Local mutation path/conflicts | state that charged creation journal is not generic outbox; canonical reconcile preserves later edits | Phase 5 |
| `docs/architecture/data-model.md` | operational state | mention secure local creation journal only if architecture doc needs it; no new Drift table under baseline plan | Phase 5 review |
| `docs/backend/migrations-and-functions.md` | database rules | `p_`/`v_` convention, qualified aliases, versioned task RPC and request hash | Phases 1–4 |
| `docs/backend/supabase.md` | RLS/RPC | public invoker/private definer, operation/wallet lock order, stable error contract | Phases 2–4 |
| `docs/development/testing.md` | monetization/concurrency | add Create Task regression matrix, same-op collision test, concurrency helper invocation once verified | Each behavior PR |
| `docs/product/feature-catalog.md` | Monetization/maintenance | clarify new tasks are server-confirmed; offline creates are unfinished drafts | Phase 5/6 |
| `docs/development/localization-and-rtl.md` | Forms/errors if necessary | new submitting/unknown/retry semantics coverage | Phase 8 if guidance changes |
| `docs/SENTRY_OPERATIONS.md` | allowed context | document new safe task-creation diagnostic fields only if added | Phase 9 |
| `PRIVACY.md` | storage/monetization metadata | review operation journal retention/account scoping; update if material | Phase 5 review |
| `CHANGELOG.md` | unreleased release notes | user-facing fix for Create Task failure and retry resilience | each shipped PR/release |
| `docs/plans/create-task-remediation-plan.md` | status/checklist | keep as plan; implementation PR may mark completed sections or archive after delivery per governance | final delivery |

Documentation must describe implemented behavior only. Do not mark later phases complete when only the emergency migration has shipped.

---

# 24. Pull request and delivery strategy

## PR 1 — Emergency task RPC correctness

**Scope:** Phase 0 targeted regression + Phase 1 migration.  
**Bugs:** CTC-001.  
**Files:** new emergency migration, `0012_points_monetization.test.sql`, relevant backend docs/changelog.  
**Deployment:** backend migration may deploy immediately after tests because public signature/semantics remain compatible.  
**Rollback:** forward replacement migration only.  
**Merge criteria:** 42702 test passes, full Supabase tests/lint pass, ordinary/safety/replay task creation works, no point invariant changes.

## PR 2 — Server idempotency/concurrency/contract hardening

**Scope:** Phases 2–4.  
**Bugs:** CTC-004, CTC-005, server portion of CTC-006/013/014/015; CTR-003; CTR-004 decision.  
**Files:** hardening migration, SQL tests, concurrency helper, backend/monetization/testing docs.  
**Deployment:** deploy **before** the client that requires response v2. Keep old request/response fields so currently supported clients continue working.  
**Rollback:** functions can be forward-replaced; added nullable columns/checks remain harmless to old clients.  
**Merge criteria:** RLS/grant tests, exact replay, payload mismatch, one-point concurrency, cross-user collision, malformed payload rollback all pass.

## PR 3 — Durable client creation and canonical reconciliation

**Scope:** Phases 3 and 5 plus client error/wallet primitives.  
**Bugs:** CTC-002, CTC-006–CTC-010, CTC-012, CTC-015, CTC-017; CTR-001, CTR-002.  
**Files:** new maintenance feature controller/domain/store, monetization DTO/provider, `repositories.dart`, `local_sync_store.dart`, client tests, sync/architecture/monetization/product docs.  
**Dependency:** PR 2 backend v2 deployed to target environments first.  
**Rollback:** old client can remain available because backend stays backward compatible; client release can be halted without dropping DB fields.  
**Merge criteria:** restart/timeout exact-replay tests and strict local reconcile tests pass; no optimistic charged task before server confirmation.

## PR 4 — UI, reminders, localization, accessibility, and end-to-end closure

**Scope:** Phases 6–9.  
**Bugs:** CTC-003, narrowed CTC-011, CTC-013 UI portion, CTC-016, remaining documentation/observability.  
**Files:** `main.dart`, ARBs, notification-related tests, widget/golden/integration tests, docs/changelog.  
**Dependency:** PR 3 controller merged.  
**Rollback:** UI layer can be reverted while retaining the controller/server safety mechanisms; do not revert server hardening.  
**Merge criteria:** all entry points use controller, Arabic/RTL/accessibility tests pass, reminder recovery and wallet/derived view integration pass.

---

# 25. Risk assessment

| Risk | Probability before fix | Impact | Mitigation | Detection | Rollback strategy | Owner phase |
|---|---|---|---|---|---|---|
| Duplicate point debit | Medium under response-loss/restart | Critical | durable operation journal + payload-bound replay | timeout/restart tests; ledger counts | keep backend idempotency; halt client rollout | 2–5 |
| Missing required debit | Low/none confirmed | Critical | server-only charge + RLS + atomic RPC | direct insert/RLS tests | forward function repair | 2–4 |
| Duplicate task | Medium under lost IDs | High | durable plan/op IDs + server replay | task count after timeout/retry | halt client; backend remains protective | 3–5 |
| Partial metadata | Medium locally | High | server transaction + Drift `savePlan` transaction + canonical reconcile | injected metadata failures | revert local tx change if needed; data migration not expected | 2/5 |
| Incorrect displayed balance | Medium transient | Medium | canonical wallet result overlay | delayed-Realtime test | revert overlay only, keep server authority | 7 |
| Cross-user data access | Low but serious collision path | Critical | operation lock + caller/entity validation + RLS | cross-user pgTAP/concurrency | forward RPC replacement | 2–4 |
| RLS regression | Low | Critical | introspection/direct-write tests | Supabase test suite | forward policy repair | 4 |
| Migration incompatibility | Medium | High | two staged additive migrations, old-client tests | clean local stack/full SQL suite | forward replacement; do not edit history | 1–4 |
| Deadlock | Low if lock order followed | High | operation→wallet fixed order | two-session stress/concurrency | forward function change | 2/14 |
| Idempotency regression | Medium | Critical | request hash + exact replay tests | operation/ledger/task counts | halt migration/client rollout; forward fix | 2–3 |
| Old-client incompatibility | Low/Medium | High | preserve signature and existing fields; nullable legacy hash | old request fixtures | keep backend compatibility; delay new client requirement | 1–4 |
| Queue incompatibility | Medium | High | do not repurpose generic outbox; preserve legacy generic mutations | sync tests with legacy rows | retain existing sync support | 5/15 |
| Local/cloud divergence | Medium | High | strict canonical reconcile + retained journal | restart/reconcile tests, diagnostics | replay same operation; no refund | 5 |
| Notification inconsistency | Medium transient | Medium | existing global rebuild + tests | fail-once scheduler test | global refresh/manual repair | 7 |
| Form-data loss | Medium | High user impact | storage-before-send + typed storage errors + operation-keyed drafts | secure-store failure/restart tests | keep dialog/form; do not send | 3/5/6 |
| Localization regression | Medium | Medium | ARB parity + gen-l10n + Arabic widgets | localization/widget tests | revert wording/UI only | 8 |
| Accessibility regression | Medium | Medium | semantics/focus/text-scale tests | widget/manual screen-reader | revert UI presentation without reverting controller | 6/8 |
| Performance regression | Low/Medium | Medium | one RPC per logical op, no busy polling, bounded recovery | timing logs/controller call counts | tune timeout/recovery; retain idempotency | 3/7/9 |

---

# 26. Verification tasks for unresolved findings

## CTR-001 — exact timeout semantics

**Question:** What exception/state does the pinned Supabase/PostgREST stack produce when the application-level timeout fires before versus after a simulated server commit?  
**Why:** the controller must classify both as `outcomeUnknown` without creating a new operation.  
**Files:** monetization repository, new controller.  
**Experiment:** blocking fake gateway plus a fake “server committed” flag; optionally HTTP-layer test if current repository abstractions permit.  
**Outcomes:** regardless of transport exception class after submission, same-op retry is required. Exception type only changes mapper implementation.  
**Blocking:** blocks Phase 3 error mapping, not Phase 1 emergency SQL.

## CTR-002 — newer local edit during reconcile

**Question:** Can current application scheduling produce a plan/metadata outbox mutation after cloud task pull but before creation acknowledgement/reconciliation, and does current acknowledgement remove it?  
**Why:** deleting the edit causes divergence/data loss.  
**Files:** `local_sync_store.dart`, `task_creation_sync_test.dart`.  
**Experiment:** deterministic DB barriers; seed canonical task, add later local edit/outbox, call current acknowledgement.  
**Outcomes:** if deletion reproduced, planned preservation logic is mandatory; if not reachable under current UI, still preserve outbox defensively because future sync ordering can make it reachable.  
**Blocking:** Phase 5 implementation detail.

## CTR-003 — metadata JSON shape

**Question:** What exact client behavior occurs when cloud `required_materials_json` or `dependency_plan_ids_json` contains valid JSON that is not a list?  
**Why:** current server check accepts it while local hydration expects a list.  
**Files:** metadata migration, `sync_dtos.dart`, repository hydration.  
**Experiment:** SQL insert/RPC fixture plus pull/hydrate into local test.  
**Outcomes:** if it silently becomes empty, upgrade to confirmed contract bug and add server array-of-string validation. If strict remote conversion already rejects, still add explicit server shape validation for predictable errors.  
**Blocking:** Phase 2 hardening detail.

## CTR-004 — monetization config snapshot

**Question:** Should a request that starts under paid mode but waits behind another wallet operation be charged according to config before waiting or the latest committed config at debit time?  
**Why:** both are internally consistent, but product semantics must be explicit.  
**Files:** private task RPC, monetization docs.  
**Experiment:** two-session barrier plus config update, then assert chosen behavior.  
**Possible outcomes:**

- **Latest-at-wallet-lock:** read config after wallet lock as this plan recommends by default.
- **Request-start snapshot:** retain early config read and document it.
- **Strict config serialization:** lock config row; requires deadlock/order review and is not recommended without product need.

**Blocking:** nonblocking for emergency repair; must be resolved before Phase 2 hardening merge.

## Signed-out permanent creation policy

**Question:** Is permanent signed-out local task creation still a supported monetized product behavior?  
**Why:** architecture supports signed-out local use generally, but current point-gated Create Task path requires server authorization and offline creates are drafts.  
**Files/docs:** `PlanEditorDialog`, monetization architecture, feature catalog.  
**Experiment/decision:** product/architecture review plus current UI test.  
**Outcomes:** this plan defaults to server-confirmed new tasks + offline drafts. A requirement for permanent signed-out creates requires a separate entitlement design and cannot be solved by bypassing the RPC.  
**Blocking:** blocking only if product rejects the default.

---

# 27. Definition of done

Implementation is complete only when all of the following are true:

- [ ] Every confirmed Create Task audit ID has an implemented fix or, for CTC-011, the reverified narrower defect is fixed and the existing recovery path is tested.
- [ ] Every confirmed bug has a regression test.
- [ ] SQLSTATE `42702` cannot occur from task-creation identifier ambiguity.
- [ ] Task RPC PL/pgSQL locals follow the approved prefix convention and SQL column references are qualified.
- [ ] A failed server transaction cannot debit points or create partial task/metadata/operation state.
- [ ] A successful paid creation cannot debit without the corresponding task.
- [ ] A paid task cannot be created through the supported server path without the required debit.
- [ ] An exact retry cannot create a duplicate task, operation record, or debit.
- [ ] A submitted operation survives process restart with the same operation ID, plan ID, and exact payload.
- [ ] Same operation ID with changed v2 payload is rejected deterministically.
- [ ] Concurrent charged requests cannot overspend the account.
- [ ] Database constraints prevent negative wallet balance and inconsistent ledger transitions.
- [ ] Server, not client, computes effective charge/free state.
- [ ] RLS/grants/private-function placement prevent cross-user task/point access.
- [ ] Cross-user/same-operation concurrency returns no foreign canonical data.
- [ ] New online task canonical result is strictly validated before local mutation.
- [ ] Local task/metadata reconciliation is atomic and preserves newer local edits/outbox mutations.
- [ ] `DriftMaintenanceRepository.savePlan` cannot leave partial plan/metadata state.
- [ ] Timeout after server commit is safely resolved by same-operation replay.
- [ ] Permanent and uncertain failures remain visible/recoverable; no blind retry with new IDs.
- [ ] Every Create Task entry point delegates to one controller.
- [ ] UI never reports final success before server success and durable local reconciliation.
- [ ] Failed submissions preserve form values.
- [ ] Offline draft success is shown only after durable storage success.
- [ ] Multiple drafts do not overwrite; account scope prevents cross-account resume.
- [ ] Completed journal cleanup failure cannot resurrect a new draft/submission.
- [ ] Immediate reminder failure does not invalidate the task and a later existing global refresh reconstructs the correct reminder without duplicates.
- [ ] Returned canonical wallet is displayed immediately and Realtime safely supersedes it.
- [ ] Task lists, asset views, calendar, dashboard, statistics, counters, and search reflect canonical local task state.
- [ ] English and Arabic messages cover all creation states/failures.
- [ ] RTL, keyboard, screen-reader semantics, focus, reduced-motion expectations, and dynamic text scaling are verified.
- [ ] Required Flutter unit/widget suites pass.
- [ ] Required Supabase SQL/RLS/RPC suites pass.
- [ ] Existing point concurrency test passes and new same-operation concurrency coverage passes.
- [ ] Documentation is updated in each behavioral PR.
- [ ] No historical deployed migration is modified.
- [ ] No production credentials, production data, hosted-project links, release commands, or production configuration are changed.

---

# 28. Agent execution checklist

Execute sequentially. Do not skip a failing-first test because a later change appears to make it obvious.

1. [ ] **Baseline branch.** Confirm `main` commit and re-read `AGENTS.md`, `CONTRIBUTING.md`, monetization/sync/testing docs. **IDs:** all. **Migration:** no. **Test first:** none. **Validate:** repository status/commit only. **Done when:** implementation baseline matches this plan or deviations are documented.
2. [ ] **Add 42702 regression.** Extend `supabase/tests/database/0012_points_monetization.test.sql` with current-function create+metadata reproduction and rollback state assertions. **IDs:** CTC-001. **Migration:** no. **Validate:** `npm run supabase:test`. **Dependency:** item 1. **Done when:** current final SQL defect is reproducible and rollback proven.
3. [ ] **Create emergency forward migration.** Add `<timestamp>_fix_task_creation_rpc_identifier_ambiguity.sql`; replace `homepilot_monetization_private.create_task_with_point_debit_impl(jsonb)` using `v_` locals, aliases, row variables, fixed search path; do not touch historical migrations. **IDs:** CTC-001. **Test first:** item 2. **Validate:** `npm run supabase:lint`, `npm run supabase:test`. **Done when:** no 42702 and canonical create/replay tests pass.
4. [ ] **Add server idempotency failing tests.** In `0012...`, add same-op changed-payload, wrong task/entity/user, canonical-operation-corruption, metadata shape, overflow/error-code cases. **IDs:** CTC-004/005/014, CTR-003. **Migration:** no. **Dependency:** item 3. **Done when:** tests capture current unsafe/missing behavior.
5. [ ] **Add deterministic concurrency cases.** Extend the existing concurrency test strategy for same operation and cross-user/cross-entity collisions while retaining the one-point distinct-operation test. **IDs:** CTC-005. **Migration:** no. **Validation:** local Supabase full suite plus verified concurrency helper invocation. **Done when:** winner/loser expectations are deterministic.
6. [ ] **Resolve CTR-004 config semantics.** Run/document the wallet-wait/config-change experiment and obtain product/architecture decision. **IDs:** CTR-004. **Migration:** no yet. **Done when:** one snapshot rule is documented.
7. [ ] **Create hardening migration.** Add request version/hash columns/check, operation advisory lock, exact operation validation, server metadata shape validation, stable error contract, v2 canonical wallet/result. Apply same operation-lock discipline to shared asset operation path. **IDs:** CTC-004/005/013/014/015, CTR-003/004. **Migration:** yes. **Tests first:** items 4–6. **Validate:** Supabase lint/tests + concurrency. **Done when:** all financial/idempotency/RLS invariants pass.
8. [ ] **Verify security posture.** Add/assert public invoker/private definer, fixed search paths, grants, anonymous denial, direct wallet/operation mutation denial, foreign asset denial. **IDs:** CTC-005 and preventive authorization. **Migration:** same as item 7 if needed. **Validate:** `npm run supabase:test`. **Done when:** no privilege regression.
9. [ ] **Define task creation domain types.** Create `lib/src/features/maintenance/domain/task_creation.dart` with immutable request, operation state, strict result, failure taxonomy, and field limits. **IDs:** CTC-002/006/012/013, CTR-001. **Migration:** no. **Test first:** new `test/task_creation_controller_test.dart` model/strict-parser cases. **Validate:** targeted Flutter tests. **Dependency:** server v2 contract fixed.
10. [ ] **Implement durable operation store.** Create `task_creation_operation_store.dart` with operation-keyed secure records, typed storage errors, legacy v1 draft import, account scope, terminal reconciled cleanup semantics. **IDs:** CTC-002/009/010/017. **Migration:** no DB migration. **Test first:** write failure, multiple drafts, account switch, cleanup failure, legacy import. **Done when:** no storage failure is represented as success and submitted IDs survive reconstruction.
11. [ ] **Implement TaskCreationController.** Create singleton Riverpod controller; persist-before-send; timeout→unknown; freeze submitted payload; exact replay; strict v2 result; server-accepted-needs-reconcile state. **IDs:** CTC-002/003/006/012, CTR-001. **Migration:** no. **Tests first:** blocking gateway, timeout-after-commit, restart, two-submit single-flight. **Done when:** no uncertain path creates a new operation ID.
12. [ ] **Make `savePlan` transactional.** Wrap `DriftMaintenanceRepository.savePlan` plan/metadata/inbox operations in one Drift transaction. **IDs:** CTC-008. **Migration:** no. **Test first:** metadata failure rollback in `home_structure_repository_test.dart`. **Validate:** targeted + full Flutter tests. **Done when:** no partial plan/metadata/outbox commit.
13. [ ] **Replace Create Task acknowledgement.** Add `LocalSyncStore.reconcileTaskCreationComposite` with strict identity/account checks, outbox suppression, canonical shadows/checkpoints, and preservation of pending newer edits. Stop new flow use of `acknowledgeTaskCreationComposite`. **IDs:** CTC-007, CTR-002. **Migration:** no. **Test first:** wrong ID/user/null plan/newer plan+metadata edit. **Done when:** canonical mismatch rolls back and newer mutation survives.
14. [ ] **Wire controller to server and local store.** New creation path: operation journal → RPC → strict result → local reconcile → terminal journal state. Remove new-task call to `savePlan` and blind outbox acknowledgement. **IDs:** CTC-002/006/007/008. **Migration:** no. **Dependency:** items 9–13. **Done when:** successful create produces canonical local task without a generic creation outbox.
15. [ ] **Implement authoritative wallet projection.** Extend v2 result parsing and monetization provider state so returned canonical wallet overrides stale Realtime until stream catches up. **IDs:** CTC-015. **Migration:** response v2 already item 7. **Test first:** delayed/newer Realtime. **Done when:** points UI shows committed balance immediately.
16. [ ] **Migrate `PlanEditorDialog` creation branch.** Keep edit path unchanged; every new-task entry uses controller. Remove correctness dependence on widget `_creationOperationId`, `_creationPlanId`, and direct RPC/draft orchestration. **IDs:** CTC-002/003/009/010. **Migration:** no. **Test first:** Create and Add Another + each entry point. **Done when:** widget is presentation-only for new creation.
17. [ ] **Fix modal/submission lifecycle.** Disable/guard close/back/drag at unsafe phases; make controller survive widget disposal; add mounted checks for UI after awaits. **IDs:** CTC-003/016. **Migration:** no. **Test first:** close/back/drag/dispose blocking gateway. **Done when:** no unhandled exception or lost operation.
18. [ ] **Implement typed creation errors and client limits.** Map stable backend/network/local failures to `TaskCreationFailureCode`; add field-specific validation and localized en/ar strings. **IDs:** CTC-012/013/014/016. **Migration:** no beyond item 7. **Test first:** code mapping and boundary input. **Validate:** `flutter gen-l10n`, targeted widgets. **Done when:** no raw SQL appears and every actionable failure has recovery.
19. [ ] **Validate/remediate reminder refresh.** Add fail-once scheduler test. Keep existing startup/resume/daily reconstruction; replace silent create-path catch with safe diagnostic/nonfatal state. Add dirty marker only if test proves current reconstruction insufficient. **IDs:** narrowed CTC-011. **Migration:** no by default. **Done when:** reminder converges once without duplicating and task success is preserved.
20. [ ] **Verify derived views.** Test maintenance/asset/calendar/dashboard/statistics/counters/search after canonical reconcile. Add narrow provider invalidation only for a proven stale surface. **IDs:** derived-state/CTC-015 support. **Migration:** no. **Done when:** all views reflect task without restart/manual refresh.
21. [ ] **Complete Arabic/RTL/accessibility/time tests.** Add keyboard submit, screen-reader semantics/live region, focus, text scale, Arabic long strings, UTC/timezone and recurrence enum coverage. **IDs:** CTC-013/016. **Migration:** no. **Validate:** gen-l10n + targeted/full Flutter tests. **Done when:** accessibility/localization criteria pass.
22. [ ] **Add end-to-end local Supabase scenario.** Extend `integration_test/supabase_sync_test.dart` or the approved integration surface for create → debit/free result → canonical local state → balance/derived views → reminder recovery. **IDs:** cross-cutting. **Migration:** no new. **Done when:** non-production integration proves the whole workflow.
23. [ ] **Add observability safely.** Structured phase/error/retry/reconcile diagnostics only; review Sentry privacy policy. **IDs:** CTC-012, CTR-001 and diagnostics. **Migration:** no. **Test first:** scrubber/allowlist tests if new fields enter Sentry. **Done when:** no user task content or identifiers are emitted.
24. [ ] **Update documentation in the responsible PRs.** Apply section 23 map; do not postpone docs. **IDs:** all. **Migration:** no. **Done when:** docs describe only shipped behavior and changelog is current.
25. [ ] **Run required validation.** `flutter pub get`, `flutter gen-l10n`, build runner, format, analyze, full Flutter tests; `npm ci`, `npx supabase start`, Supabase lint/tests, verified concurrency helper, then `npx supabase stop`. **IDs:** all. **Done when:** all commands exit successfully and device/integration evidence is attached.
26. [ ] **Complete Definition of Done and rollout review.** Verify old-client/backend compatibility, migration order, no historical migration edit, no production secret/config changes, and every audit/risk disposition. **Dependencies:** all prior items. **Done when:** section 27 is fully checked and each PR meets its merge criteria.
