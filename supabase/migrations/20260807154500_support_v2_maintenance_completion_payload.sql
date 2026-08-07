-- Migration: Support Payload Version 2 in complete_maintenance_task
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

  operation_id_value text;
  plan_id_value text;
  record_id_value text;
  record_plan_id_value text;

  expected_plan_revision bigint;
  expected_next_due_date timestamptz;
  plan_next_due_date timestamptz;
  record_due_date timestamptz;
  record_completed_at timestamptz;

  plan_created_at timestamptz;
  plan_updated_at timestamptz;
  plan_archived_at timestamptz;
  plan_recurrence_interval integer;
  plan_reminder_days_before integer;
  plan_is_enabled boolean;
  resulting_next_due_date timestamptz;

  current_plan public.maintenance_plans%rowtype;
  current_record public.maintenance_records%rowtype;
  occurrence_record public.maintenance_records%rowtype;
  plan_was_created boolean := false;
begin
  if request_user is null then
    raise exception 'Authentication is required'
      using errcode = '42501';
  end if;

  if coalesce(length(trim(p_device_id)), 0) = 0
      or length(p_device_id) > 200 then
    return jsonb_build_object(
      'status', 'invalid',
      'retryable', false,
      'conflict_reason', 'invalid_device_id'
    );
  end if;

  -- Support payload version 1 and version 2 (CT-003 / CT-010 causal ordering)
  if jsonb_typeof(p_operation) is distinct from 'object'
      or (p_operation ->> 'version' is distinct from '1' and p_operation ->> 'version' is distinct from '2') then
    return jsonb_build_object(
      'status', 'invalid',
      'retryable', false,
      'conflict_reason', 'invalid_payload_version'
    );
  end if;

  plan_payload := p_operation -> 'plan';
  record_payload := p_operation -> 'record';
  if jsonb_typeof(plan_payload) is distinct from 'object'
      or jsonb_typeof(record_payload) is distinct from 'object' then
    return jsonb_build_object(
      'status', 'invalid',
      'retryable', false,
      'conflict_reason', 'incomplete_payload'
    );
  end if;

  operation_id_value := nullif(trim(p_operation ->> 'operation_id'), '');
  plan_id_value := nullif(trim(plan_payload ->> 'id'), '');
  record_id_value := nullif(trim(record_payload ->> 'id'), '');
  record_plan_id_value := nullif(trim(record_payload ->> 'plan_id'), '');

  if operation_id_value is null
      or plan_id_value is null
      or record_id_value is null
      or record_plan_id_value is null
      or record_plan_id_value <> plan_id_value then
    return jsonb_build_object(
      'status', 'invalid',
      'retryable', false,
      'conflict_reason', 'invalid_identifiers'
    );
  end if;

  begin
    expected_plan_revision :=
      nullif(p_operation ->> 'expected_plan_revision', '')::bigint;
    expected_next_due_date :=
      nullif(p_operation ->> 'expected_next_due_date', '')::timestamptz;
    plan_next_due_date :=
      nullif(plan_payload ->> 'next_due_date', '')::timestamptz;
    record_due_date :=
      nullif(record_payload ->> 'due_date', '')::timestamptz;
    record_completed_at :=
      nullif(record_payload ->> 'completed_at', '')::timestamptz;
    plan_created_at :=
      nullif(plan_payload ->> 'created_at', '')::timestamptz;
    plan_updated_at := coalesce(
      nullif(plan_payload ->> 'updated_at', '')::timestamptz,
      clock_timestamp()
    );
    plan_archived_at := case
      when plan_payload -> 'archived_at' is null
        or plan_payload -> 'archived_at' = 'null'::jsonb
        then null
      else nullif(plan_payload ->> 'archived_at', '')::timestamptz
    end;
    plan_recurrence_interval :=
      nullif(plan_payload ->> 'recurrence_interval', '')::integer;
    plan_reminder_days_before := coalesce(
      nullif(plan_payload ->> 'reminder_days_before', '')::integer,
      0
    );
    plan_is_enabled :=
      nullif(plan_payload ->> 'is_enabled', '')::boolean;
  exception
    when others then
      return jsonb_build_object(
        'status', 'invalid',
        'retryable', false,
        'conflict_reason', 'invalid_values'
      );
  end;

  if record_completed_at is not null and record_completed_at > clock_timestamp() then
    record_completed_at := clock_timestamp();
  end if;

  if expected_next_due_date is null
      or record_due_date is null
      or record_completed_at is null
      or plan_next_due_date is null
      or plan_created_at is null
      or plan_recurrence_interval is null
      or plan_is_enabled is null
      or record_due_date is distinct from expected_next_due_date
      or plan_next_due_date <= record_due_date
      or plan_recurrence_interval <= 0
      or plan_reminder_days_before < 0 then
    return jsonb_build_object(
      'status', 'invalid',
      'retryable', false,
      'conflict_reason', 'invalid_completion'
    );
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      request_user::text || ':' || plan_id_value,
      0
    )
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      request_user::text || ':operation:' || operation_id_value,
      0
    )
  );

  select *
  into current_record
  from public.maintenance_records
  where user_id = request_user
    and operation_id = operation_id_value;

  if found then
    select *
    into current_plan
    from public.maintenance_plans
    where user_id = request_user
      and id = current_record.plan_id;

    if current_record.id <> record_id_value
        or current_record.plan_id <> plan_id_value
        or current_record.due_date is distinct from record_due_date
        or current_record.notes is distinct from (record_payload ->> 'notes') then
      return jsonb_build_object(
        'status', 'conflict',
        'retryable', false,
        'conflict_reason', 'operation_id_reused',
        'current_plan_revision', current_plan.revision,
        'resulting_record_id', current_record.id,
        'resulting_next_due_date', current_plan.next_due_date,
        'plan', to_jsonb(current_plan),
        'record', to_jsonb(current_record)
      );
    end if;

    return jsonb_build_object(
      'status', 'already_applied',
      'retryable', false,
      'conflict_reason', null,
      'current_plan_revision', current_plan.revision,
      'resulting_record_id', current_record.id,
      'resulting_next_due_date', current_plan.next_due_date,
      'plan', to_jsonb(current_plan),
      'record', to_jsonb(current_record)
    );
  end if;

  select *
  into current_plan
  from public.maintenance_plans
  where user_id = request_user
    and id = plan_id_value
  for update;

  if found then
    if current_plan.archived_at is not null
        or current_plan.is_enabled is not true then
      return jsonb_build_object(
        'status', 'conflict',
        'retryable', false,
        'conflict_reason', 'plan_inactive',
        'current_plan_revision', current_plan.revision,
        'resulting_record_id', null,
        'resulting_next_due_date', current_plan.next_due_date,
        'plan', to_jsonb(current_plan),
        'record', null
      );
    end if;

    if current_plan.next_due_date is distinct from expected_next_due_date then
      select *
      into occurrence_record
      from public.maintenance_records
      where user_id = request_user
        and plan_id = plan_id_value
        and due_date = record_due_date
      order by completed_at desc, id desc limit 1;

      if found then
        return jsonb_build_object(
          'status', 'conflict',
          'retryable', false,
          'conflict_reason', 'occurrence_completed_elsewhere',
          'current_plan_revision', current_plan.revision,
          'resulting_record_id', occurrence_record.id,
          'resulting_next_due_date', current_plan.next_due_date,
          'plan', to_jsonb(current_plan),
          'record', to_jsonb(occurrence_record)
        );
      end if;

      return jsonb_build_object(
        'status', 'conflict',
        'retryable', false,
        'conflict_reason', 'occurrence_changed',
        'current_plan_revision', current_plan.revision,
        'resulting_record_id', null,
        'resulting_next_due_date', current_plan.next_due_date,
        'plan', to_jsonb(current_plan),
        'record', null
      );
    end if;

    if expected_plan_revision is not null
        and current_plan.revision is distinct from expected_plan_revision then
      return jsonb_build_object(
        'status', 'conflict',
        'retryable', true,
        'conflict_reason', 'stale_plan_revision',
        'current_plan_revision', current_plan.revision,
        'resulting_record_id', null,
        'resulting_next_due_date', current_plan.next_due_date,
        'plan', to_jsonb(current_plan),
        'record', null
      );
    end if;
  else
    insert into public.maintenance_plans (
      id,
      user_id,
      asset_id,
      title,
      instructions,
      recurrence_interval,
      recurrence_unit,
      priority,
      next_due_date,
      reminder_days_before,
      health_group,
      created_at,
      updated_at,
      archived_at,
      revision,
      is_enabled
    ) values (
      plan_id_value,
      request_user,
      nullif(trim(plan_payload ->> 'asset_id'), ''),
      nullif(trim(plan_payload ->> 'title'), ''),
      nullif(trim(plan_payload ->> 'instructions'), ''),
      plan_recurrence_interval,
      nullif(trim(plan_payload ->> 'recurrence_unit'), ''),
      nullif(trim(plan_payload ->> 'priority'), ''),
      plan_next_due_date,
      plan_reminder_days_before,
      nullif(trim(plan_payload ->> 'health_group'), ''),
      plan_created_at,
      plan_updated_at,
      plan_archived_at,
      coalesce(expected_plan_revision, 1),
      plan_is_enabled
    )
    returning * into current_plan;

    plan_was_created := true;
  end if;

  insert into public.maintenance_records (
    id,
    user_id,
    plan_id,
    due_date,
    completed_at,
    notes,
    created_at,
    operation_id
  ) values (
    record_id_value,
    request_user,
    plan_id_value,
    record_due_date,
    record_completed_at,
    nullif(trim(record_payload ->> 'notes'), ''),
    coalesce(nullif(trim(record_payload ->> 'created_at'), '')::timestamptz, clock_timestamp()),
    operation_id_value
  )
  returning * into current_record;

  if not plan_was_created then
    update public.maintenance_plans
    set next_due_date = plan_next_due_date,
        updated_at = plan_updated_at,
        archived_at = plan_archived_at,
        revision = current_plan.revision + 1,
        is_enabled = plan_is_enabled
    where user_id = request_user
      and id = plan_id_value
    returning * into current_plan;
  end if;

  update public.notification_inbox
  set read_at = coalesce(read_at, clock_timestamp()),
      updated_at = clock_timestamp()
  where user_id = request_user
    and plan_id = plan_id_value;

  return jsonb_build_object(
    'status', 'applied',
    'retryable', false,
    'conflict_reason', null,
    'current_plan_revision', current_plan.revision,
    'resulting_record_id', current_record.id,
    'resulting_next_due_date', current_plan.next_due_date,
    'plan', to_jsonb(current_plan),
    'record', to_jsonb(current_record)
  );
end;
$$;

commit;
