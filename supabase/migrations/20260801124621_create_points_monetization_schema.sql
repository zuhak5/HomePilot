-- Server-authoritative HomePilot points, ad reward claims, kill switches, and
-- monetization analytics. Clients get read-only access to their wallet data;
-- all mutations are performed by narrowly scoped SECURITY DEFINER RPCs.

create schema if not exists homepilot_monetization_private;
revoke all on schema homepilot_monetization_private from public, anon, authenticated;

create table public.point_wallets (
  user_id uuid primary key references auth.users(id) on delete cascade,
  balance integer not null default 7 check (balance between 0 and 20),
  reward_time_zone text not null default 'UTC' check (
    char_length(reward_time_zone) between 1 and 100
  ),
  reward_time_zone_updated_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.point_transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  amount integer not null check (amount <> 0),
  balance_before integer not null check (balance_before between 0 and 20),
  balance_after integer not null check (
    balance_after between 0 and 20
    and balance_after = balance_before + amount
  ),
  transaction_type text not null check (
    transaction_type in (
      'initial_grant',
      'task_creation',
      'asset_creation',
      'rewarded_ad',
      'rewarded_interstitial',
      'refund',
      'admin_adjustment'
    )
  ),
  reference_id text,
  idempotency_key text not null check (char_length(idempotency_key) between 1 and 200),
  reward_day date,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (user_id, idempotency_key)
);

create unique index point_transactions_daily_reward_uidx
on public.point_transactions (user_id, transaction_type, reward_day)
where transaction_type in ('rewarded_ad', 'rewarded_interstitial')
  and reward_day is not null;

create index point_transactions_user_created_idx
on public.point_transactions (user_id, created_at desc);

create table public.reward_claim_requests (
  claim_id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  reward_type text not null check (
    reward_type in ('rewarded_ad', 'rewarded_interstitial')
  ),
  ad_unit_id text not null check (char_length(ad_unit_id) between 1 and 120),
  reward_amount integer not null check (reward_amount in (1, 2)),
  status text not null default 'pending' check (
    status in ('pending', 'processed', 'expired', 'rejected')
  ),
  reward_day date not null default (timezone('utc', now()))::date,
  expires_at timestamptz not null default (now() + interval '15 minutes'),
  created_at timestamptz not null default now(),
  processed_at timestamptz,
  rejection_reason text check (
    rejection_reason is null or char_length(rejection_reason) <= 200
  )
);

create unique index reward_claim_requests_one_pending_uidx
on public.reward_claim_requests (user_id, reward_type)
where status = 'pending';

create index reward_claim_requests_user_created_idx
on public.reward_claim_requests (user_id, created_at desc);

create table public.ad_reward_claims (
  transaction_id text primary key check (char_length(transaction_id) between 1 and 200),
  claim_id uuid not null unique references public.reward_claim_requests(claim_id),
  user_id uuid not null references auth.users(id) on delete cascade,
  reward_type text not null check (
    reward_type in ('rewarded_ad', 'rewarded_interstitial')
  ),
  ad_unit_id text not null,
  reward_amount integer not null check (reward_amount in (1, 2)),
  reward_day date not null,
  google_timestamp timestamptz not null,
  created_at timestamptz not null default now()
);

create table public.creation_point_operations (
  operation_id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  entity_type text not null check (entity_type in ('task', 'asset')),
  entity_id text not null check (char_length(entity_id) between 1 and 200),
  charged_amount integer not null check (charged_amount in (0, 1)),
  created_at timestamptz not null default now(),
  unique (user_id, entity_type, entity_id)
);

create table public.monetization_config (
  singleton boolean primary key default true check (singleton),
  ads_enabled boolean not null default true,
  native_ads_enabled boolean not null default true,
  interstitial_ads_enabled boolean not null default true,
  rewarded_ads_enabled boolean not null default true,
  rewarded_interstitial_enabled boolean not null default true,
  points_enabled boolean not null default true,
  emergency_free_creation_mode boolean not null default false,
  wallet_cap integer not null default 20 check (wallet_cap = 20),
  interstitial_cooldown_seconds integer not null default 180 check (
    interstitial_cooldown_seconds between 0 and 86400
  ),
  rapid_completion_window_seconds integer not null default 60 check (
    rapid_completion_window_seconds between 0 and 3600
  ),
  reward_claim_cooldown_seconds integer not null default 45 check (
    reward_claim_cooldown_seconds between 0 and 3600
  ),
  interstitial_session_cap integer not null default 3 check (
    interstitial_session_cap between 0 and 20
  ),
  updated_at timestamptz not null default now()
);

insert into public.monetization_config (singleton) values (true)
on conflict (singleton) do nothing;

create table public.monetization_events (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  event_name text not null check (
    event_name in (
      'ad_native_impression',
      'ad_native_click',
      'ad_interstitial_shown',
      'ad_rewarded_watched',
      'point_shortage_encountered',
      'points_debited'
    )
  ),
  properties jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default now()
);

create index monetization_events_user_occurred_idx
on public.monetization_events (user_id, occurred_at desc);

alter table public.point_wallets enable row level security;
alter table public.point_transactions enable row level security;
alter table public.reward_claim_requests enable row level security;
alter table public.ad_reward_claims enable row level security;
alter table public.creation_point_operations enable row level security;
alter table public.monetization_config enable row level security;
alter table public.monetization_events enable row level security;

revoke all on table public.point_wallets from public, anon, authenticated;
revoke all on table public.point_transactions from public, anon, authenticated;
revoke all on table public.reward_claim_requests from public, anon, authenticated;
revoke all on table public.ad_reward_claims from public, anon, authenticated;
revoke all on table public.creation_point_operations from public, anon, authenticated;
revoke all on table public.monetization_config from public, anon, authenticated;
revoke all on table public.monetization_events from public, anon, authenticated;
revoke all on sequence public.monetization_events_id_seq from public, anon, authenticated;

grant select on table public.point_wallets to authenticated;
grant select on table public.point_transactions to authenticated;
grant select on table public.reward_claim_requests to authenticated;
grant select on table public.monetization_config to authenticated;

create policy point_wallets_select_own
on public.point_wallets for select to authenticated
using ((select auth.uid()) = user_id);

create policy point_transactions_select_own
on public.point_transactions for select to authenticated
using ((select auth.uid()) = user_id);

create policy reward_claim_requests_select_own
on public.reward_claim_requests for select to authenticated
using ((select auth.uid()) = user_id);

create policy monetization_config_authenticated_read
on public.monetization_config for select to authenticated
using (true);

create or replace function homepilot_monetization_private.initialize_wallet()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.point_wallets (user_id, balance)
  values (new.id, 7)
  on conflict (user_id) do nothing;

  insert into public.point_transactions (
    user_id,
    amount,
    balance_before,
    balance_after,
    transaction_type,
    idempotency_key,
    metadata
  ) values (
    new.id,
    7,
    0,
    7,
    'initial_grant',
    'initial-grant-v1',
    '{"source":"auth_user_created"}'::jsonb
  )
  on conflict (user_id, idempotency_key) do nothing;

  return new;
end;
$$;

revoke all on function homepilot_monetization_private.initialize_wallet()
from public, anon, authenticated;

drop trigger if exists initialize_homepilot_point_wallet on auth.users;
create trigger initialize_homepilot_point_wallet
after insert on auth.users
for each row execute function homepilot_monetization_private.initialize_wallet();

-- Existing users have never had a wallet, so granting the documented starting
-- balance is safe and idempotent. A conflict never resets an existing balance.
insert into public.point_wallets (user_id, balance)
select id, 7 from auth.users
on conflict (user_id) do nothing;

insert into public.point_transactions (
  user_id,
  amount,
  balance_before,
  balance_after,
  transaction_type,
  idempotency_key,
  metadata
)
select
  users.id,
  7,
  0,
  7,
  'initial_grant',
  'initial-grant-v1',
  '{"source":"migration_backfill"}'::jsonb
from auth.users as users
on conflict (user_id, idempotency_key) do nothing;

alter table public.point_wallets replica identity full;
alter table public.monetization_config replica identity full;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
    and not exists (
      select 1
      from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'point_wallets'
    )
  then
    alter publication supabase_realtime add table public.point_wallets;
  end if;
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
    and not exists (
      select 1
      from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'monetization_config'
    )
  then
    alter publication supabase_realtime add table public.monetization_config;
  end if;
end
$$;
