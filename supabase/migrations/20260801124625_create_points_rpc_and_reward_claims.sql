-- Atomic point-gated creation, reward claim issuance/settlement, and analytics.

grant insert on table public.assets to authenticated;
grant insert on table public.maintenance_plans to authenticated;

-- The legacy sync/completion path still needs INSERT privilege when replaying a
-- creation that has already been authorized. RLS binds that privilege to an
-- operation recorded by the debit RPC, closing direct Data API bypasses.
create or replace function public.is_authorized_point_creation(
  p_user_id uuid,
  p_entity_type text,
  p_entity_id text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (select auth.uid()) = p_user_id
    and exists (
      select 1
      from public.creation_point_operations
      where user_id = p_user_id
        and entity_type = p_entity_type
        and entity_id = p_entity_id
    );
$$;

revoke all on function public.is_authorized_point_creation(uuid, text, text)
from public, anon;
grant execute on function public.is_authorized_point_creation(uuid, text, text)
to authenticated;

drop policy if exists assets_insert_own on public.assets;
create policy assets_insert_own
on public.assets for insert to authenticated
with check (
  (select auth.uid()) = user_id
  and public.is_authorized_point_creation(user_id, 'asset', id)
);

drop policy if exists maintenance_plans_insert_own on public.maintenance_plans;
create policy maintenance_plans_insert_own
on public.maintenance_plans for insert to authenticated
with check (
  (select auth.uid()) = user_id
  and public.is_authorized_point_creation(user_id, 'task', id)
);

create or replace function public.create_task_with_point_debit(p_operation jsonb)
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
      'already_processed', true
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

  -- Serialize retries and concurrent creates on the wallet lock, then recheck.
  select * into existing_operation
  from public.creation_point_operations
  where operation_id = operation_uuid;
  if found then
    return jsonb_build_object(
      'task_id', existing_operation.entity_id,
      'balance', current_balance,
      'charged', existing_operation.charged_amount,
      'already_processed', true
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
    'already_processed', false
  );
exception
  when check_violation or not_null_violation or invalid_text_representation then
    raise exception using errcode = '22023', message = 'INVALID_TASK_PAYLOAD';
end;
$$;

revoke all on function public.create_task_with_point_debit(jsonb)
from public, anon;
grant execute on function public.create_task_with_point_debit(jsonb)
to authenticated;

create or replace function public.create_asset_with_point_debit(p_operation jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  operation_uuid uuid;
  asset_json jsonb;
  details_json jsonb;
  plans_json jsonb;
  plan_json jsonb;
  metadata_json jsonb;
  asset_id text;
  asset_kind text;
  category_health_group text;
  current_balance integer;
  next_balance integer;
  charge integer := 1;
  config_row public.monetization_config%rowtype;
  existing_operation public.creation_point_operations%rowtype;
begin
  if caller_id is null then
    raise exception using errcode = '42501', message = 'AUTH_REQUIRED';
  end if;
  if p_operation is null
    or jsonb_typeof(p_operation) <> 'object'
    or pg_column_size(p_operation) > 262144
  then
    raise exception using errcode = '22023', message = 'INVALID_OPERATION';
  end if;
  begin
    operation_uuid := (p_operation->>'operation_id')::uuid;
  exception when others then
    raise exception using errcode = '22023', message = 'INVALID_OPERATION_ID';
  end;

  asset_json := p_operation->'asset';
  details_json := coalesce(p_operation->'details', '{}'::jsonb);
  plans_json := coalesce(p_operation->'initial_plans', '[]'::jsonb);
  if jsonb_typeof(asset_json) <> 'object'
    or jsonb_typeof(details_json) <> 'object'
    or jsonb_typeof(plans_json) <> 'array'
    or jsonb_array_length(plans_json) > 50
  then
    raise exception using errcode = '22023', message = 'INVALID_ASSET_PAYLOAD';
  end if;
  asset_id := nullif(btrim(asset_json->>'id'), '');
  asset_kind := asset_json->>'asset_type';
  if asset_id is null then
    raise exception using errcode = '22023', message = 'INVALID_ASSET_PAYLOAD';
  end if;

  select * into existing_operation
  from public.creation_point_operations
  where operation_id = operation_uuid;
  if found then
    if existing_operation.user_id <> caller_id
      or existing_operation.entity_type <> 'asset'
      or existing_operation.entity_id <> asset_id
    then
      raise exception using errcode = '23505', message = 'OPERATION_ID_REUSED';
    end if;
    select balance into current_balance
    from public.point_wallets where user_id = caller_id;
    return jsonb_build_object(
      'asset_id', asset_id,
      'balance', current_balance,
      'charged', existing_operation.charged_amount,
      'already_processed', true
    );
  end if;

  if not exists (
    select 1 from public.rooms
    where user_id = caller_id
      and id = asset_json->>'room_id'
      and archived_at is null
  ) then
    raise exception using errcode = '23503', message = 'ROOM_NOT_FOUND';
  end if;
  select health_group into category_health_group
  from public.categories
  where user_id = caller_id and id = asset_json->>'category_id';
  if not found then
    raise exception using errcode = '23503', message = 'CATEGORY_NOT_FOUND';
  end if;

  select * into config_row
  from public.monetization_config where singleton = true;
  if not config_row.points_enabled
    or config_row.emergency_free_creation_mode
    or category_health_group = 'safety'
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
      'asset_id', existing_operation.entity_id,
      'balance', current_balance,
      'charged', existing_operation.charged_amount,
      'already_processed', true
    );
  end if;
  if charge = 1 and current_balance < 1 then
    raise exception using errcode = 'P0001', message = 'INSUFFICIENT_POINTS';
  end if;
  next_balance := current_balance - charge;

  insert into public.assets (
    user_id,
    id,
    name,
    asset_type,
    category_id,
    room_id,
    placement,
    notes,
    purchase_date,
    created_at,
    updated_at,
    archived_at,
    revision
  ) values (
    caller_id,
    asset_id,
    btrim(asset_json->>'name'),
    asset_kind,
    asset_json->>'category_id',
    asset_json->>'room_id',
    nullif(btrim(asset_json->>'placement'), ''),
    nullif(btrim(asset_json->>'notes'), ''),
    (asset_json->>'purchase_date')::timestamptz,
    now(),
    now(),
    null,
    1
  );

  case asset_kind
    when 'device' then
      insert into public.device_details (
        user_id, asset_id, brand, model, serial_number, power_source,
        warranty_until, manual_url, consumable, revision
      ) values (
        caller_id, asset_id,
        nullif(btrim(details_json->>'brand'), ''),
        nullif(btrim(details_json->>'model'), ''),
        nullif(btrim(details_json->>'serial_number'), ''),
        nullif(btrim(details_json->>'power_source'), ''),
        (details_json->>'warranty_until')::timestamptz,
        nullif(btrim(details_json->>'manual_url'), ''),
        nullif(btrim(details_json->>'consumable'), ''), 1
      );
    when 'pet' then
      insert into public.pet_details (
        user_id, asset_id, species, breed, birth_date, microchip_id, vet_name,
        vet_phone, feeding_notes, medical_notes, revision
      ) values (
        caller_id, asset_id,
        nullif(btrim(details_json->>'species'), ''),
        nullif(btrim(details_json->>'breed'), ''),
        (details_json->>'birth_date')::timestamptz,
        nullif(btrim(details_json->>'microchip_id'), ''),
        nullif(btrim(details_json->>'vet_name'), ''),
        nullif(btrim(details_json->>'vet_phone'), ''),
        nullif(btrim(details_json->>'feeding_notes'), ''),
        nullif(btrim(details_json->>'medical_notes'), ''), 1
      );
    when 'plant' then
      insert into public.plant_details (
        user_id, asset_id, species, sunlight, watering_interval_days, pot_size,
        last_repotted_at, toxicity_notes, revision
      ) values (
        caller_id, asset_id,
        nullif(btrim(details_json->>'species'), ''),
        nullif(btrim(details_json->>'sunlight'), ''),
        (details_json->>'watering_interval_days')::integer,
        nullif(btrim(details_json->>'pot_size'), ''),
        (details_json->>'last_repotted_at')::timestamptz,
        nullif(btrim(details_json->>'toxicity_notes'), ''), 1
      );
    when 'safety' then
      insert into public.safety_details (
        user_id, asset_id, safety_type, installed_at, expires_at, battery_type,
        test_interval_days, revision
      ) values (
        caller_id, asset_id,
        nullif(btrim(details_json->>'safety_type'), ''),
        (details_json->>'installed_at')::timestamptz,
        (details_json->>'expires_at')::timestamptz,
        nullif(btrim(details_json->>'battery_type'), ''),
        (details_json->>'test_interval_days')::integer, 1
      );
    when 'general' then null;
    else raise exception using errcode = '22023', message = 'INVALID_ASSET_TYPE';
  end case;

  -- Tasks generated as part of one asset creation are included in its single
  -- debit. They are still fully validated by the same table constraints.
  for plan_json in select value from jsonb_array_elements(plans_json)
  loop
    if jsonb_typeof(plan_json) <> 'object'
      or plan_json->>'asset_id' <> asset_id
    then
      raise exception using errcode = '22023', message = 'INVALID_INITIAL_TASK';
    end if;
    insert into public.maintenance_plans (
      user_id, id, asset_id, title, instructions, recurrence_interval,
      recurrence_unit, priority, next_due_date, reminder_days_before,
      health_group, created_at, updated_at, archived_at, revision, is_enabled
    ) values (
      caller_id,
      plan_json->>'id',
      asset_id,
      btrim(plan_json->>'title'),
      nullif(btrim(plan_json->>'instructions'), ''),
      (plan_json->>'recurrence_interval')::integer,
      plan_json->>'recurrence_unit',
      plan_json->>'priority',
      (plan_json->>'next_due_date')::timestamptz,
      coalesce((plan_json->>'reminder_days_before')::integer, 0),
      case
        when category_health_group = 'safety' then 'safety'
        else plan_json->>'health_group'
      end,
      now(), now(), null, 1,
      coalesce((plan_json->>'is_enabled')::boolean, true)
    );
    metadata_json := coalesce(plan_json->'metadata', '{}'::jsonb);
    if metadata_json <> '{}'::jsonb then
      insert into public.maintenance_plan_metadata (
        user_id, plan_id, task_type, location_label,
        estimated_duration_minutes, required_materials_json,
        dependency_plan_ids_json, reminder_recommendation, sort_order,
        created_at, updated_at, revision
      ) values (
        caller_id, plan_json->>'id',
        nullif(btrim(metadata_json->>'task_type'), ''),
        nullif(btrim(metadata_json->>'location_label'), ''),
        (metadata_json->>'estimated_duration_minutes')::integer,
        coalesce(metadata_json->'required_materials', '[]'::jsonb)::text,
        coalesce(metadata_json->'dependency_plan_ids', '[]'::jsonb)::text,
        nullif(btrim(metadata_json->>'reminder_recommendation'), ''),
        (metadata_json->>'sort_order')::integer,
        now(), now(), 1
      );
    end if;
  end loop;

  insert into public.creation_point_operations (
    operation_id, user_id, entity_type, entity_id, charged_amount
  ) values (operation_uuid, caller_id, 'asset', asset_id, charge);

  if charge = 1 then
    update public.point_wallets
    set balance = next_balance, updated_at = now()
    where user_id = caller_id;
    insert into public.point_transactions (
      user_id, amount, balance_before, balance_after, transaction_type,
      reference_id, idempotency_key, metadata
    ) values (
      caller_id, -1, current_balance, next_balance, 'asset_creation',
      asset_id, 'create-asset:' || operation_uuid::text,
      jsonb_build_object('initial_task_count', jsonb_array_length(plans_json))
    );
  end if;

  return jsonb_build_object(
    'asset_id', asset_id,
    'balance', next_balance,
    'charged', charge,
    'already_processed', false
  );
exception
  when check_violation or not_null_violation or invalid_text_representation then
    raise exception using errcode = '22023', message = 'INVALID_ASSET_PAYLOAD';
end;
$$;

revoke all on function public.create_asset_with_point_debit(jsonb)
from public, anon;
grant execute on function public.create_asset_with_point_debit(jsonb)
to authenticated;

create or replace function public.create_reward_claim_request(
  p_reward_type text,
  p_time_zone text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  wallet_row public.point_wallets%rowtype;
  config_row public.monetization_config%rowtype;
  reward_amount integer;
  ad_unit_id text;
  requested_time_zone text;
  local_reward_day date;
  claim_row public.reward_claim_requests%rowtype;
begin
  if caller_id is null then
    raise exception using errcode = '42501', message = 'AUTH_REQUIRED';
  end if;
  if p_reward_type not in ('rewarded_ad', 'rewarded_interstitial') then
    raise exception using errcode = '22023', message = 'INVALID_REWARD_TYPE';
  end if;

  select * into config_row
  from public.monetization_config where singleton = true;
  if not config_row.ads_enabled or not config_row.rewarded_ads_enabled
    or (p_reward_type = 'rewarded_interstitial'
      and not config_row.rewarded_interstitial_enabled)
  then
    raise exception using errcode = 'P0001', message = 'REWARDS_DISABLED';
  end if;

  reward_amount := case when p_reward_type = 'rewarded_ad' then 1 else 2 end;
  ad_unit_id := case
    when p_reward_type = 'rewarded_ad'
      then 'ca-app-pub-5274007212820203/3342599731'
    else 'ca-app-pub-5274007212820203/2197039025'
  end;

  select * into wallet_row
  from public.point_wallets where user_id = caller_id
  for update;
  if not found then
    raise exception using errcode = 'P0001', message = 'WALLET_NOT_FOUND';
  end if;

  requested_time_zone := nullif(btrim(p_time_zone), '');
  if requested_time_zone is not null
    and not exists (
      select 1 from pg_catalog.pg_timezone_names
      where name = requested_time_zone
    )
  then
    raise exception using errcode = '22023', message = 'INVALID_TIME_ZONE';
  end if;
  if requested_time_zone is not null
    and requested_time_zone <> wallet_row.reward_time_zone
  then
    if exists (
      select 1 from public.point_transactions
      where user_id = caller_id
        and transaction_type in ('rewarded_ad', 'rewarded_interstitial')
    ) and wallet_row.reward_time_zone_updated_at > now() - interval '30 days'
    then
      raise exception using errcode = 'P0001', message = 'TIME_ZONE_CHANGE_COOLDOWN';
    end if;
    update public.point_wallets
    set reward_time_zone = requested_time_zone,
        reward_time_zone_updated_at = now(),
        updated_at = now()
    where user_id = caller_id;
    wallet_row.reward_time_zone := requested_time_zone;
  end if;
  local_reward_day := (timezone(wallet_row.reward_time_zone, now()))::date;

  update public.reward_claim_requests
  set status = 'expired', rejection_reason = 'expired'
  where user_id = caller_id and status = 'pending' and expires_at <= now();

  if wallet_row.balance + reward_amount > config_row.wallet_cap then
    raise exception using errcode = 'P0001', message = 'WALLET_CAP_REACHED';
  end if;
  if exists (
    select 1 from public.point_transactions
    where user_id = caller_id
      and transaction_type = p_reward_type
      and reward_day = local_reward_day
  ) then
    raise exception using errcode = 'P0001', message = 'REWARD_ALREADY_CLAIMED';
  end if;
  if exists (
    select 1 from public.reward_claim_requests
    where user_id = caller_id
      and created_at > now() - make_interval(
        secs => config_row.reward_claim_cooldown_seconds
      )
  ) then
    raise exception using errcode = 'P0001', message = 'REWARD_COOLDOWN';
  end if;

  insert into public.reward_claim_requests (
    user_id, reward_type, ad_unit_id, reward_amount, reward_day
  ) values (
    caller_id, p_reward_type, ad_unit_id, reward_amount, local_reward_day
  ) returning * into claim_row;

  return jsonb_build_object(
    'claim_id', claim_row.claim_id,
    'user_id', caller_id,
    'custom_data', claim_row.claim_id::text,
    'reward_type', claim_row.reward_type,
    'reward_amount', claim_row.reward_amount,
    'ad_unit_id', claim_row.ad_unit_id,
    'expires_at', claim_row.expires_at,
    'reward_day', claim_row.reward_day,
    'time_zone', wallet_row.reward_time_zone
  );
end;
$$;

revoke all on function public.create_reward_claim_request(text, text)
from public, anon;
grant execute on function public.create_reward_claim_request(text, text)
to authenticated;

create or replace function public.process_admob_ssv_reward(
  p_transaction_id text,
  p_claim_id uuid,
  p_user_id uuid,
  p_ad_unit_id text,
  p_reward_amount integer,
  p_reward_item text,
  p_google_timestamp timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  claim_row public.reward_claim_requests%rowtype;
  wallet_row public.point_wallets%rowtype;
  config_row public.monetization_config%rowtype;
  new_balance integer;
  existing_claim public.ad_reward_claims%rowtype;
begin
  if auth.role() <> 'service_role' then
    raise exception using errcode = '42501', message = 'SERVICE_ROLE_REQUIRED';
  end if;
  if p_transaction_id is null
    or char_length(p_transaction_id) not between 1 and 200
    or p_reward_item <> 'points'
    or p_google_timestamp > now() + interval '5 minutes'
  then
    raise exception using errcode = '22023', message = 'INVALID_SSV_PAYLOAD';
  end if;

  select * into existing_claim
  from public.ad_reward_claims
  where transaction_id = p_transaction_id;
  if found then
    if existing_claim.claim_id <> p_claim_id
      or existing_claim.user_id <> p_user_id
    then
      raise exception using errcode = '23505', message = 'TRANSACTION_ID_REUSED';
    end if;
    select balance into new_balance
    from public.point_wallets where user_id = p_user_id;
    return jsonb_build_object(
      'credited', true,
      'duplicate', true,
      'balance', new_balance,
      'reward_amount', existing_claim.reward_amount
    );
  end if;

  select * into claim_row
  from public.reward_claim_requests
  where claim_id = p_claim_id
  for update;
  if not found
    or claim_row.user_id <> p_user_id
    or claim_row.status <> 'pending'
    or claim_row.expires_at <= now()
    or claim_row.ad_unit_id <> p_ad_unit_id
    or claim_row.reward_amount <> p_reward_amount
  then
    raise exception using errcode = '22023', message = 'INVALID_REWARD_CLAIM';
  end if;

  select * into wallet_row
  from public.point_wallets where user_id = p_user_id
  for update;
  select * into config_row
  from public.monetization_config where singleton = true;

  if wallet_row.balance + claim_row.reward_amount > config_row.wallet_cap then
    update public.reward_claim_requests
    set status = 'rejected', processed_at = now(),
        rejection_reason = 'wallet_cap_reached'
    where claim_id = p_claim_id;
    return jsonb_build_object(
      'credited', false,
      'duplicate', false,
      'balance', wallet_row.balance,
      'reason', 'wallet_cap_reached'
    );
  end if;
  if exists (
    select 1 from public.point_transactions
    where user_id = p_user_id
      and transaction_type = claim_row.reward_type
      and reward_day = claim_row.reward_day
  ) then
    update public.reward_claim_requests
    set status = 'rejected', processed_at = now(),
        rejection_reason = 'daily_reward_already_claimed'
    where claim_id = p_claim_id;
    return jsonb_build_object(
      'credited', false,
      'duplicate', false,
      'balance', wallet_row.balance,
      'reason', 'daily_reward_already_claimed'
    );
  end if;

  new_balance := wallet_row.balance + claim_row.reward_amount;
  insert into public.ad_reward_claims (
    transaction_id, claim_id, user_id, reward_type, ad_unit_id,
    reward_amount, reward_day, google_timestamp
  ) values (
    p_transaction_id, p_claim_id, p_user_id, claim_row.reward_type,
    p_ad_unit_id, claim_row.reward_amount, claim_row.reward_day,
    p_google_timestamp
  );
  update public.point_wallets
  set balance = new_balance, updated_at = now()
  where user_id = p_user_id;
  insert into public.point_transactions (
    user_id, amount, balance_before, balance_after, transaction_type,
    reference_id, idempotency_key, reward_day, metadata
  ) values (
    p_user_id,
    claim_row.reward_amount,
    wallet_row.balance,
    new_balance,
    claim_row.reward_type,
    p_transaction_id,
    'ssv:' || p_transaction_id,
    claim_row.reward_day,
    jsonb_build_object(
      'claim_id', p_claim_id,
      'ad_unit_id', p_ad_unit_id,
      'google_timestamp', p_google_timestamp
    )
  );
  update public.reward_claim_requests
  set status = 'processed', processed_at = now(), rejection_reason = null
  where claim_id = p_claim_id;

  return jsonb_build_object(
    'credited', true,
    'duplicate', false,
    'balance', new_balance,
    'reward_amount', claim_row.reward_amount
  );
end;
$$;

revoke all on function public.process_admob_ssv_reward(
  text, uuid, uuid, text, integer, text, timestamptz
) from public, anon, authenticated;
grant execute on function public.process_admob_ssv_reward(
  text, uuid, uuid, text, integer, text, timestamptz
) to service_role;

create or replace function public.record_monetization_event(
  p_event_name text,
  p_properties jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
begin
  if caller_id is null then
    raise exception using errcode = '42501', message = 'AUTH_REQUIRED';
  end if;
  if p_event_name not in (
    'ad_native_impression',
    'ad_native_click',
    'ad_interstitial_shown',
    'ad_rewarded_watched',
    'point_shortage_encountered',
    'points_debited'
  ) or p_properties is null
    or jsonb_typeof(p_properties) <> 'object'
    or pg_column_size(p_properties) > 8192
  then
    raise exception using errcode = '22023', message = 'INVALID_EVENT';
  end if;
  insert into public.monetization_events (user_id, event_name, properties)
  values (caller_id, p_event_name, p_properties);
end;
$$;

revoke all on function public.record_monetization_event(text, jsonb)
from public, anon;
grant execute on function public.record_monetization_event(text, jsonb)
to authenticated;
