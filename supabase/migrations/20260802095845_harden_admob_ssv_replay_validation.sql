-- Harden the database boundary behind the public AdMob SSV Edge Function.
-- Signature verification remains in the Edge Function; this RPC independently
-- enforces payload shape, freshness, exact idempotency, and atomic settlement.
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
    or p_transaction_id ~ '[[:cntrl:]]'
    or p_claim_id is null
    or p_user_id is null
    or p_ad_unit_id is null
    or p_reward_amount is null
    or p_reward_item is distinct from 'points'
    or p_google_timestamp is null
    or p_google_timestamp > now() + interval '5 minutes'
    or p_ad_unit_id not in (
      'ca-app-pub-5274007212820203/3342599731',
      'ca-app-pub-5274007212820203/2197039025'
    )
    or (
      p_ad_unit_id = 'ca-app-pub-5274007212820203/3342599731'
      and p_reward_amount <> 1
    )
    or (
      p_ad_unit_id = 'ca-app-pub-5274007212820203/2197039025'
      and p_reward_amount <> 2
    )
  then
    raise exception using errcode = '22023', message = 'INVALID_SSV_PAYLOAD';
  end if;

  -- Serialize callbacks for the same Google transaction. This closes the gap
  -- where two simultaneous first deliveries could both miss the dedupe row.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_transaction_id, 0)
  );

  select * into existing_claim
  from public.ad_reward_claims
  where transaction_id = p_transaction_id;
  if found then
    if existing_claim.claim_id is distinct from p_claim_id
      or existing_claim.user_id is distinct from p_user_id
      or existing_claim.ad_unit_id is distinct from p_ad_unit_id
      or existing_claim.reward_amount is distinct from p_reward_amount
      or existing_claim.google_timestamp is distinct from p_google_timestamp
    then
      raise exception using errcode = '23505', message = 'TRANSACTION_ID_REUSED';
    end if;

    select balance into new_balance
    from public.point_wallets
    where user_id = p_user_id;
    if not found then
      raise exception using message = 'SSV_SERVER_STATE_INVALID';
    end if;
    return jsonb_build_object(
      'credited', true,
      'duplicate', true,
      'balance', new_balance,
      'reward_amount', existing_claim.reward_amount
    );
  end if;

  -- The client claim expires after 15 minutes. The extra five-minute window is
  -- only clock/queue tolerance; an already-expired claim still fails below.
  if p_google_timestamp < now() - interval '20 minutes' then
    raise exception using errcode = '22023', message = 'SSV_TIMESTAMP_EXPIRED';
  end if;

  select * into claim_row
  from public.reward_claim_requests
  where claim_id = p_claim_id
  for update;
  if not found
    or claim_row.user_id is distinct from p_user_id
    or claim_row.status is distinct from 'pending'
    or claim_row.expires_at <= now()
    or claim_row.ad_unit_id is distinct from p_ad_unit_id
    or claim_row.reward_amount is distinct from p_reward_amount
    or p_google_timestamp < claim_row.created_at - interval '5 minutes'
    or p_google_timestamp > claim_row.expires_at + interval '5 minutes'
  then
    raise exception using errcode = '22023', message = 'INVALID_REWARD_CLAIM';
  end if;

  select * into wallet_row
  from public.point_wallets
  where user_id = p_user_id
  for update;
  if not found then
    raise exception using message = 'SSV_SERVER_STATE_INVALID';
  end if;

  select * into config_row
  from public.monetization_config
  where singleton = true;
  if not found then
    raise exception using message = 'SSV_SERVER_STATE_INVALID';
  end if;

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
    select 1
    from public.point_transactions
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
