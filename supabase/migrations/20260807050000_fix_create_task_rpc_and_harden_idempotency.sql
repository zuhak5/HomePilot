-- Migration: Fix create task RPC variable shadowing (CTC-001) and harden idempotency/concurrency (CTC-004, CTC-005, CTC-014, CTC-015, CTR-003)
begin;

create extension if not exists pgcrypto with schema extensions;

alter table public.creation_point_operations
  add column if not exists request_hash text;

create or replace function homepilot_monetization_private.create_task_with_point_debit_impl(
  p_operation jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller_id uuid := auth.uid();
  v_operation_uuid uuid;
  v_plan_json jsonb;
  v_metadata_json jsonb;
  v_plan_id text;
  v_target_asset_id text;
  v_current_balance integer;
  v_next_balance integer;
  v_charge integer := 1;
  v_is_safety boolean;
  v_config_row public.monetization_config%rowtype;
  v_existing_operation public.creation_point_operations%rowtype;
  v_request_hash text;
begin
  if v_caller_id is null then
    raise exception using errcode = '42501', message = 'AUTH_REQUIRED';
  end if;
  if p_operation is null
    or jsonb_typeof(p_operation) <> 'object'
    or pg_column_size(p_operation) > 65536
  then
    raise exception using errcode = '22023', message = 'INVALID_OPERATION';
  end if;

  begin
    v_operation_uuid := (p_operation->>'operation_id')::uuid;
  exception when others then
    raise exception using errcode = '22023', message = 'INVALID_OPERATION_ID';
  end;

  v_plan_json := p_operation->'plan';
  v_metadata_json := coalesce(p_operation->'metadata', '{}'::jsonb);
  if jsonb_typeof(v_plan_json) <> 'object'
    or jsonb_typeof(v_metadata_json) <> 'object'
  then
    raise exception using errcode = '22023', message = 'INVALID_TASK_PAYLOAD';
  end if;

  v_plan_id := nullif(btrim(v_plan_json->>'id'), '');
  v_target_asset_id := nullif(btrim(v_plan_json->>'asset_id'), '');
  if v_plan_id is null or v_target_asset_id is null then
    raise exception using errcode = '22023', message = 'INVALID_TASK_PAYLOAD';
  end if;

  -- CTR-003: Pre-validate metadata JSON shape if provided
  if v_metadata_json is not null and v_metadata_json <> '{}'::jsonb then
    if v_metadata_json ? 'required_materials' then
      if jsonb_typeof(v_metadata_json->'required_materials') <> 'array' then
        raise exception using errcode = '22023', message = 'INVALID_TASK_PAYLOAD';
      end if;
    end if;
    if v_metadata_json ? 'required_materials_json' then
      if jsonb_typeof(v_metadata_json->'required_materials_json') <> 'array' then
        raise exception using errcode = '22023', message = 'INVALID_TASK_PAYLOAD';
      end if;
    end if;
    if v_metadata_json ? 'dependency_plan_ids' then
      if jsonb_typeof(v_metadata_json->'dependency_plan_ids') <> 'array' then
        raise exception using errcode = '22023', message = 'INVALID_TASK_PAYLOAD';
      end if;
    end if;
    if v_metadata_json ? 'dependency_plan_ids_json' then
      if jsonb_typeof(v_metadata_json->'dependency_plan_ids_json') <> 'array' then
        raise exception using errcode = '22023', message = 'INVALID_TASK_PAYLOAD';
      end if;
    end if;
  end if;

  v_request_hash := encode(extensions.digest(p_operation::text::bytea, 'sha256'), 'hex');

  -- CTC-005: Lock operation for exact evaluation
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      v_caller_id::text || ':task_op:' || v_operation_uuid::text,
      0
    )
  );

  select * into v_existing_operation
  from public.creation_point_operations
  where operation_id = v_operation_uuid;
  if found then
    if v_existing_operation.user_id <> v_caller_id
      or v_existing_operation.entity_type <> 'task'
      or v_existing_operation.entity_id <> v_plan_id
      or (v_existing_operation.request_hash is not null and v_existing_operation.request_hash <> v_request_hash)
    then
      raise exception using errcode = '23505', message = 'OPERATION_ID_REUSED';
    end if;
    select balance into v_current_balance
    from public.point_wallets where user_id = v_caller_id;
    return jsonb_build_object(
      'task_id', v_plan_id,
      'balance', v_current_balance,
      'charged', v_existing_operation.charged_amount,
      'already_processed', true,
      'plan', (
        select to_jsonb(p) from public.maintenance_plans p
        where p.user_id = v_caller_id and p.id = v_plan_id
      ),
      'metadata', (
        select to_jsonb(m) from public.maintenance_plan_metadata m
        where m.user_id = v_caller_id and m.plan_id = v_plan_id
      )
    );
  end if;

  select categories.health_group = 'safety'
  into v_is_safety
  from public.assets
  join public.categories
    on categories.user_id = assets.user_id
   and categories.id = assets.category_id
  where assets.user_id = v_caller_id
    and assets.id = v_target_asset_id
    and assets.archived_at is null;
  if not found then
    raise exception using errcode = '23503', message = 'ASSET_NOT_FOUND';
  end if;

  select * into v_config_row
  from public.monetization_config where singleton = true;
  if not v_config_row.points_enabled
    or v_config_row.emergency_free_creation_mode
    or v_is_safety
  then
    v_charge := 0;
  end if;

  select balance into v_current_balance
  from public.point_wallets
  where user_id = v_caller_id
  for update;
  if not found then
    raise exception using errcode = 'P0001', message = 'WALLET_NOT_FOUND';
  end if;

  select * into v_existing_operation
  from public.creation_point_operations
  where operation_id = v_operation_uuid;
  if found then
    if v_existing_operation.user_id <> v_caller_id
      or v_existing_operation.entity_type <> 'task'
      or v_existing_operation.entity_id <> v_plan_id
      or (v_existing_operation.request_hash is not null and v_existing_operation.request_hash <> v_request_hash)
    then
      raise exception using errcode = '23505', message = 'OPERATION_ID_REUSED';
    end if;
    return jsonb_build_object(
      'task_id', v_existing_operation.entity_id,
      'balance', v_current_balance,
      'charged', v_existing_operation.charged_amount,
      'already_processed', true,
      'plan', (
        select to_jsonb(p) from public.maintenance_plans p
        where p.user_id = v_caller_id and p.id = v_existing_operation.entity_id
      ),
      'metadata', (
        select to_jsonb(m) from public.maintenance_plan_metadata m
        where m.user_id = v_caller_id and m.plan_id = v_existing_operation.entity_id
      )
    );
  end if;

  if v_charge = 1 and v_current_balance < 1 then
    raise exception using errcode = 'P0001', message = 'INSUFFICIENT_POINTS';
  end if;
  v_next_balance := v_current_balance - v_charge;

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
    health_group,
    created_at,
    updated_at,
    archived_at,
    revision,
    is_enabled
  ) values (
    v_caller_id,
    v_plan_id,
    v_target_asset_id,
    btrim(v_plan_json->>'title'),
    nullif(btrim(v_plan_json->>'instructions'), ''),
    (v_plan_json->>'recurrence_interval')::integer,
    v_plan_json->>'recurrence_unit',
    v_plan_json->>'priority',
    (v_plan_json->>'next_due_date')::timestamptz,
    coalesce((v_plan_json->>'reminder_days_before')::integer, 0),
    case when v_is_safety then 'safety' else v_plan_json->>'health_group' end,
    now(),
    now(),
    null,
    1,
    coalesce((v_plan_json->>'is_enabled')::boolean, true)
  );

  if v_metadata_json <> '{}'::jsonb then
    insert into public.maintenance_plan_metadata (
      user_id,
      plan_id,
      task_type,
      location_label,
      estimated_duration_minutes,
      required_materials_json,
      dependency_plan_ids_json,
      reminder_recommendation,
      sort_order,
      created_at,
      updated_at,
      revision
    ) values (
      v_caller_id,
      v_plan_id,
      nullif(btrim(v_metadata_json->>'task_type'), ''),
      nullif(btrim(v_metadata_json->>'location_label'), ''),
      (v_metadata_json->>'estimated_duration_minutes')::integer,
      coalesce(v_metadata_json->'required_materials', v_metadata_json->'required_materials_json', '[]'::jsonb)::text,
      coalesce(v_metadata_json->'dependency_plan_ids', v_metadata_json->'dependency_plan_ids_json', '[]'::jsonb)::text,
      nullif(btrim(v_metadata_json->>'reminder_recommendation'), ''),
      (v_metadata_json->>'sort_order')::integer,
      now(),
      now(),
      1
    );
  end if;

  insert into public.creation_point_operations (
    operation_id, user_id, entity_type, entity_id, charged_amount, request_hash
  ) values (v_operation_uuid, v_caller_id, 'task', v_plan_id, v_charge, v_request_hash);

  if v_charge = 1 then
    update public.point_wallets
    set balance = v_next_balance, updated_at = now()
    where user_id = v_caller_id;

    insert into public.point_transactions (
      user_id,
      amount,
      balance_before,
      balance_after,
      transaction_type,
      reference_id,
      idempotency_key,
      metadata
    ) values (
      v_caller_id,
      -1,
      v_current_balance,
      v_next_balance,
      'task_creation',
      v_plan_id,
      'create-task:' || v_operation_uuid::text,
      jsonb_build_object('asset_id', v_target_asset_id)
    );
  end if;

  return jsonb_build_object(
    'task_id', v_plan_id,
    'balance', v_next_balance,
    'charged', v_charge,
    'already_processed', false,
    'plan', (
      select to_jsonb(p) from public.maintenance_plans p
      where p.user_id = v_caller_id and p.id = v_plan_id
    ),
    'metadata', (
      select to_jsonb(m) from public.maintenance_plan_metadata m
      where m.user_id = v_caller_id and m.plan_id = v_plan_id
    )
  );
exception
  when check_violation or not_null_violation or invalid_text_representation then
    raise exception using errcode = '22023', message = 'INVALID_TASK_PAYLOAD';
end;
$$;

notify pgrst, 'reload schema';
commit;
