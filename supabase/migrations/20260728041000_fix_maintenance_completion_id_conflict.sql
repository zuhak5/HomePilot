-- Convert the deterministic reused-completion-ID conflict to a terminal
-- PostgREST conflict code. RPC execution remains revoked until the fixed
-- client build is validated and released.
begin;

create or replace function public.complete_maintenance_task(
  p_operation jsonb,
  p_device_id text
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  request_user uuid := (select auth.uid());

  plan_payload jsonb;
  record_payload jsonb;

  operation_id text;
  plan_id text;
  record_id text;
  record_plan_id text;

  expected_next_due_date timestamptz;
  plan_next_due_date timestamptz;
  plan_created_at timestamptz;
  plan_updated_at timestamptz;
  plan_archived_at timestamptz;

  record_due_date timestamptz;
  record_completed_at timestamptz;

  plan_recurrence_interval integer;
  plan_reminder_days_before integer;
  plan_is_enabled boolean;

  current_plan public.maintenance_plans%rowtype;
  current_record public.maintenance_records%rowtype;
begin
  if request_user is null then
    raise exception 'Authentication is required'
      using errcode = '42501';
  end if;

  if coalesce(length(trim(p_device_id)), 0) = 0
      or length(p_device_id) > 200 then
    raise exception 'A valid device identifier is required'
      using errcode = '22023';
  end if;

  if jsonb_typeof(p_operation) is distinct from 'object' then
    raise exception 'The maintenance completion payload must be an object'
      using errcode = '22023';
  end if;

  if p_operation ->> 'version' is distinct from '1' then
    raise exception 'Unsupported maintenance completion payload version'
      using errcode = '22023';
  end if;

  plan_payload := p_operation -> 'plan';
  record_payload := p_operation -> 'record';

  if jsonb_typeof(plan_payload) is distinct from 'object'
      or jsonb_typeof(record_payload) is distinct from 'object' then
    raise exception 'The maintenance completion payload is incomplete'
      using errcode = '22023';
  end if;

  operation_id := nullif(trim(p_operation ->> 'operation_id'), '');
  plan_id := nullif(trim(plan_payload ->> 'id'), '');
  record_id := nullif(trim(record_payload ->> 'id'), '');
  record_plan_id := nullif(trim(record_payload ->> 'plan_id'), '');

  if operation_id is null
      or plan_id is null
      or record_id is null
      or record_plan_id is null then
    raise exception 'The maintenance completion identifiers are required'
      using errcode = '22023';
  end if;

  if operation_id <> record_id then
    raise exception 'The operation identifier must equal the record identifier'
      using errcode = '22023';
  end if;

  if record_plan_id <> plan_id then
    raise exception 'The maintenance record belongs to another plan'
      using errcode = '22023';
  end if;

  begin
    expected_next_due_date :=
      nullif(p_operation ->> 'expected_next_due_date', '')::timestamptz;

    plan_next_due_date :=
      nullif(plan_payload ->> 'next_due_date', '')::timestamptz;

    plan_created_at :=
      nullif(plan_payload ->> 'created_at', '')::timestamptz;

    plan_updated_at :=
      nullif(plan_payload ->> 'updated_at', '')::timestamptz;

    plan_archived_at := case
      when plan_payload -> 'archived_at' is null
        or plan_payload -> 'archived_at' = 'null'::jsonb
        then null
      else nullif(plan_payload ->> 'archived_at', '')::timestamptz
    end;

    record_due_date :=
      nullif(record_payload ->> 'due_date', '')::timestamptz;

    record_completed_at :=
      nullif(record_payload ->> 'completed_at', '')::timestamptz;

    plan_recurrence_interval :=
      nullif(plan_payload ->> 'recurrence_interval', '')::integer;

    plan_reminder_days_before :=
      nullif(plan_payload ->> 'reminder_days_before', '')::integer;

    plan_is_enabled :=
      nullif(plan_payload ->> 'is_enabled', '')::boolean;
  exception
    when others then
      raise exception 'The maintenance completion payload contains invalid values'
        using errcode = '22023';
  end;

  if expected_next_due_date is null
      or plan_next_due_date is null
      or plan_created_at is null
      or plan_updated_at is null
      or record_due_date is null
      or record_completed_at is null
      or plan_recurrence_interval is null
      or plan_reminder_days_before is null
      or plan_is_enabled is null then
    raise exception 'The maintenance completion payload is missing required values'
      using errcode = '22023';
  end if;

  if record_due_date is distinct from expected_next_due_date then
    raise exception 'The maintenance record due date does not match the expected plan state'
      using errcode = '22023';
  end if;

  if plan_recurrence_interval <= 0
      or plan_reminder_days_before < 0 then
    raise exception 'The maintenance recurrence values are invalid'
      using errcode = '22023';
  end if;

  if plan_is_enabled is not true or plan_archived_at is not null then
    raise exception 'An inactive maintenance plan cannot be completed'
      using errcode = 'PT409';
  end if;

  if plan_updated_at > clock_timestamp() + interval '5 minutes'
      or record_completed_at > clock_timestamp() + interval '5 minutes' then
    raise exception 'The maintenance completion timestamp is too far in the future'
      using errcode = '22007';
  end if;

  if coalesce(length(plan_payload ->> 'title'), 0) = 0
      or plan_payload ->> 'asset_id' is null
      or plan_payload ->> 'recurrence_unit' is null
      or plan_payload ->> 'priority' is null
      or plan_payload ->> 'health_group' is null then
    raise exception 'The maintenance plan payload is incomplete'
      using errcode = '22023';
  end if;

  /*
   * Serialize all completions for one account and plan. This also covers a
   * plan that has not yet been inserted into the cloud, where SELECT FOR
   * UPDATE alone could not provide a lock.
   */
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      request_user::text || ':' || plan_id,
      0
    )
  );

  /*
   * The locally generated maintenance-record ID is the idempotency key.
   * A retry after a committed but unacknowledged RPC returns the same
   * canonical rows without advancing the plan again.
   */
  select *
  into current_record
  from public.maintenance_records
  where user_id = request_user
    and id = record_id;

  if found then
    if current_record.plan_id <> plan_id
        or current_record.due_date is distinct from record_due_date
        or current_record.completed_at is distinct from record_completed_at
        or current_record.notes is distinct from (record_payload ->> 'notes') then
      raise exception
        'The maintenance completion identifier is already in use by another completion'
        using errcode = 'PT409';
    end if;

    select *
    into current_plan
    from public.maintenance_plans
    where user_id = request_user
      and id = plan_id;

    if not found then
      raise exception 'The completed maintenance record has no plan'
        using errcode = '23503';
    end if;

    return jsonb_build_object(
      'plan', to_jsonb(current_plan),
      'record', to_jsonb(current_record)
    );
  end if;

  select *
  into current_plan
  from public.maintenance_plans
  where user_id = request_user
    and id = plan_id
  for update;

  if not found then
    /*
     * A locally created plan may not have reached the cloud yet. The
     * composite payload carries the complete post-completion snapshot so the
     * plan and its first completion can be created atomically.
     */
    insert into public.maintenance_plans (
      user_id,
      id,
      asset_id,
      title,
      instructions,
      recurrence_interval,
      recurrence_unit,
      priority,
      next_due_date,
      reminder_days_before,
      is_enabled,
      health_group,
      created_at,
      updated_at,
      archived_at
    )
    values (
      request_user,
      plan_id,
      plan_payload ->> 'asset_id',
      plan_payload ->> 'title',
      plan_payload ->> 'instructions',
      plan_recurrence_interval,
      plan_payload ->> 'recurrence_unit',
      plan_payload ->> 'priority',
      plan_next_due_date,
      plan_reminder_days_before,
      plan_is_enabled,
      plan_payload ->> 'health_group',
      plan_created_at,
      plan_updated_at,
      plan_archived_at
    )
    returning * into current_plan;
  else
    /*
     * Multiple offline completions are processed in order:
     * completion N expects exactly the due date produced by N - 1.
     */
    if current_plan.next_due_date is distinct from expected_next_due_date then
      raise exception
        'The maintenance plan changed before this completion reached the cloud'
        using errcode = 'PT409';
    end if;

    if current_plan.archived_at is not null
        or current_plan.is_enabled is not true then
      raise exception 'The cloud maintenance plan is no longer active'
        using errcode = 'PT409';
    end if;

    /*
     * Completion owns only the due-date transition. Other plan fields may
     * have been edited by another device after this operation was queued.
     */
    update public.maintenance_plans
    set next_due_date = plan_next_due_date
    where user_id = request_user
      and id = plan_id
    returning * into current_plan;
  end if;

  insert into public.maintenance_records (
    user_id,
    id,
    plan_id,
    due_date,
    completed_at,
    notes
  )
  values (
    request_user,
    record_id,
    plan_id,
    record_due_date,
    record_completed_at,
    record_payload ->> 'notes'
  )
  returning * into current_record;

  return jsonb_build_object(
    'plan', to_jsonb(current_plan),
    'record', to_jsonb(current_record)
  );
end;
$$;

comment on function public.complete_maintenance_task(jsonb, text) is
  'Atomically and idempotently applies one offline maintenance completion. Deterministic plan-state conflicts use SQLSTATE PT409.';

/*
 * Emergency circuit breaker:
 * keep the RPC unavailable until the fixed client has completed
 * production-device validation. A later migration will restore
 * only the required execution grants.
 */
revoke all on function public.complete_maintenance_task(jsonb, text)
from public, anon, authenticated, service_role;

commit;