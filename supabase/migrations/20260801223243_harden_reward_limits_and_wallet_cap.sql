-- Align the production reward cadence and wallet storage with the approved
-- product rules. Regular rewarded ads are renewable after the configured
-- cooldown; only the daily completion reward is limited to one local day.

alter table public.point_wallets
  drop constraint if exists point_wallets_balance_check;
alter table public.point_wallets
  add constraint point_wallets_balance_check
  check (balance between 0 and 1000);

alter table public.point_transactions
  drop constraint if exists point_transactions_balance_before_check;
alter table public.point_transactions
  add constraint point_transactions_balance_before_check
  check (balance_before between 0 and 1000);

alter table public.point_transactions
  drop constraint if exists point_transactions_check;
alter table public.point_transactions
  drop constraint if exists point_transactions_balance_after_check;
alter table public.point_transactions
  add constraint point_transactions_balance_after_check
  check (
    balance_after between 0 and 1000
    and balance_after = balance_before + amount
  );

drop index if exists public.point_transactions_daily_reward_uidx;
create unique index point_transactions_daily_reward_uidx
on public.point_transactions (user_id, reward_day)
where transaction_type = 'rewarded_interstitial'
  and reward_day is not null;

-- A completed client ad may wait for SSV while the user starts another reward
-- after the cooldown. Multiple pending claims are safe because each claim is
-- short-lived, SSV transactions are unique, and settlement rechecks the cap.
drop index if exists public.reward_claim_requests_one_pending_uidx;
create index reward_claim_requests_pending_idx
on public.reward_claim_requests (user_id, status, expires_at)
where status = 'pending';

-- RPC-created rows already exist remotely before the offline-first sync layer
-- replays its local upsert. Permit that reconciliation without authorizing a
-- brand-new uncharged entity.
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
    and (
      exists (
        select 1
        from public.creation_point_operations
        where user_id = p_user_id
          and entity_type = p_entity_type
          and entity_id = p_entity_id
      )
      or (
        p_entity_type = 'asset'
        and exists (
          select 1 from public.assets
          where user_id = p_user_id and id = p_entity_id
        )
      )
      or (
        p_entity_type = 'task'
        and exists (
          select 1 from public.maintenance_plans
          where user_id = p_user_id and id = p_entity_id
        )
      )
    );
$$;

revoke all on function public.is_authorized_point_creation(uuid, text, text)
from public, anon;
grant execute on function public.is_authorized_point_creation(uuid, text, text)
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
  if p_reward_type = 'rewarded_interstitial' and exists (
    select 1 from public.point_transactions
    where user_id = caller_id
      and transaction_type = 'rewarded_interstitial'
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
  if coalesce(auth.jwt()->>'role', '') <> 'service_role' then
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
  if claim_row.reward_type = 'rewarded_interstitial' and exists (
    select 1 from public.point_transactions
    where user_id = p_user_id
      and transaction_type = 'rewarded_interstitial'
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
