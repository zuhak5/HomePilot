-- Migration: Align user_settings key constraint with client allowlist and extend task creation RPC
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

-- Update task creation RPC implementation to return canonical plan and metadata
create or replace function homepilot_monetization_private.create_task_with_point_debit_impl(
  p_operation jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  operation_uuid uuid;
  plan_json jsonb;
  metadata_json jsonb;
  plan_id text;
  target_asset_id text;
  current_balance integer;
  next_balance integer;
  charge integer := 1;
  is_safety boolean;
  config_row public.monetization_config%rowtype;
  existing_operation public.creation_point_operations%rowtype;
begin
  if caller_id is null then
    raise exception using errcode = '42501', message = 'AUTH_REQUIRED';
  end if;
  if p_operation is null
    or jsonb_typeof(p_operation) <> 'object'
    or pg_column_size(p_operation) > 65536
  then
    raise exception using errcode = '22023', message = 'INVALID_OPERATION';
  end if;

  begin
    operation_uuid := (p_operation->>'operation_id')::uuid;
  exception when others then
    raise exception using errcode = '22023', message = 'INVALID_OPERATION_ID';
  end;
  plan_json := p_operation->'plan';
  metadata_json := coalesce(p_operation->'metadata', '{}'::jsonb);
  if jsonb_typeof(plan_json) <> 'object'
    or jsonb_typeof(metadata_json) <> 'object'
  then
    raise exception using errcode = '22023', message = 'INVALID_TASK_PAYLOAD';
  end if;

  plan_id := nullif(btrim(plan_json->>'id'), '');
  target_asset_id := nullif(btrim(plan_json->>'asset_id'), '');
  if plan_id is null or target_asset_id is null then
    raise exception using errcode = '22023', message = 'INVALID_TASK_PAYLOAD';
  end if;

  select * into existing_operation
  from public.creation_point_operations
  where operation_id = operation_uuid;
  if found then
    if existing_operation.user_id <> caller_id
      or existing_operation.entity_type <> 'task'
      or existing_operation.entity_id <> plan_id
    then
      raise exception using errcode = '23505', message = 'OPERATION_ID_REUSED';
    end if;
    select balance into current_balance
    from public.point_wallets where user_id = caller_id;
    return jsonb_build_object(
      'task_id', plan_id,
      'balance', current_balance,
      'charged', existing_operation.charged_amount,
      'already_processed', true,
      'plan', (
        select to_jsonb(p) from public.maintenance_plans p
        where p.user_id = caller_id and p.id = plan_id
      ),
      'metadata', (
        select to_jsonb(m) from public.maintenance_plan_metadata m
        where m.user_id = caller_id and m.plan_id = plan_id
      )
    );
  end if;

  select categories.health_group = 'safety'
  into is_safety
  from public.assets
  join public.categories
    on categories.user_id = assets.user_id
   and categories.id = assets.category_id
  where assets.user_id = caller_id
    and assets.id = target_asset_id
    and assets.archived_at is null;
  if not found then
    raise exception using errcode = '23503', message = 'ASSET_NOT_FOUND';
  end if;

  select * into config_row
  from public.monetization_config where singleton = true;
  if not config_row.points_enabled
    or config_row.emergency_free_creation_mode
    or is_safety
  then
    charge := 0;
  end if;

  select balance into current_balance
  from public.point_wallets
  where user_id = caller_id
  for update;
  if not found then
    raise exception using errcode = 'P0001', message = 'WALLET_NOT_FOUND';
  end if;

  select * into existing_operation
  from public.creation_point_operations
  where operation_id = operation_uuid;
  if found then
    return jsonb_build_object(
      'task_id', existing_operation.entity_id,
      'balance', current_balance,
      'charged', existing_operation.charged_amount,
      'already_processed', true,
      'plan', (
        select to_jsonb(p) from public.maintenance_plans p
        where p.user_id = caller_id and p.id = existing_operation.entity_id
      ),
      'metadata', (
        select to_jsonb(m) from public.maintenance_plan_metadata m
        where m.user_id = caller_id and m.plan_id = existing_operation.entity_id
      )
    );
  end if;
  if charge = 1 and current_balance < 1 then
    raise exception using errcode = 'P0001', message = 'INSUFFICIENT_POINTS';
  end if;
  next_balance := current_balance - charge;

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
    caller_id,
    plan_id,
    target_asset_id,
    btrim(plan_json->>'title'),
    nullif(btrim(plan_json->>'instructions'), ''),
    (plan_json->>'recurrence_interval')::integer,
    plan_json->>'recurrence_unit',
    plan_json->>'priority',
    (plan_json->>'next_due_date')::timestamptz,
    coalesce((plan_json->>'reminder_days_before')::integer, 0),
    case when is_safety then 'safety' else plan_json->>'health_group' end,
    now(),
    now(),
    null,
    1,
    coalesce((plan_json->>'is_enabled')::boolean, true)
  );

  if metadata_json <> '{}'::jsonb then
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
      caller_id,
      plan_id,
      nullif(btrim(metadata_json->>'task_type'), ''),
      nullif(btrim(metadata_json->>'location_label'), ''),
      (metadata_json->>'estimated_duration_minutes')::integer,
      coalesce(metadata_json->'required_materials', '[]'::jsonb)::text,
      coalesce(metadata_json->'dependency_plan_ids', '[]'::jsonb)::text,
      nullif(btrim(metadata_json->>'reminder_recommendation'), ''),
      (metadata_json->>'sort_order')::integer,
      now(),
      now(),
      1
    );
  end if;

  insert into public.creation_point_operations (
    operation_id, user_id, entity_type, entity_id, charged_amount
  ) values (operation_uuid, caller_id, 'task', plan_id, charge);

  if charge = 1 then
    update public.point_wallets
    set balance = next_balance, updated_at = now()
    where user_id = caller_id;
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
      caller_id,
      -1,
      current_balance,
      next_balance,
      'task_creation',
      plan_id,
      'create-task:' || operation_uuid::text,
      jsonb_build_object('asset_id', target_asset_id)
    );
  end if;

  return jsonb_build_object(
    'task_id', plan_id,
    'balance', next_balance,
    'charged', charge,
    'already_processed', false,
    'plan', (
      select to_jsonb(p) from public.maintenance_plans p
      where p.user_id = caller_id and p.id = plan_id
    ),
    'metadata', (
      select to_jsonb(m) from public.maintenance_plan_metadata m
      where m.user_id = caller_id and m.plan_id = plan_id
    )
  );
exception
  when check_violation or not_null_violation or invalid_text_representation then
    raise exception using errcode = '22023', message = 'INVALID_TASK_PAYLOAD';
end;
$$;

notify pgrst, 'reload schema';
commit;
