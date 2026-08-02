create schema if not exists homepilot_private;

revoke all on schema homepilot_private from public;
revoke all on schema homepilot_private from anon;
revoke all on schema homepilot_private from authenticated;
grant usage on schema homepilot_private to service_role;

create table if not exists homepilot_private.ai_provider_runtime_status (
  provider text primary key
    check (provider in ('groq', 'huggingFace', 'openRouter')),
  model text not null,
  state text not null
    check (state in ('closed', 'open', 'half_open', 'unconfigured')),
  healthy boolean not null default false,
  failure_count integer not null default 0 check (failure_count >= 0),
  cooldown_until timestamptz,
  last_success_at timestamptz,
  last_failure_at timestamptz,
  latency_ms integer check (latency_ms is null or latency_ms >= 0),
  last_error_code text,
  checked_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists homepilot_private.ai_provider_events (
  id uuid primary key default gen_random_uuid(),
  request_id text not null,
  phase text not null,
  provider text
    check (provider is null or provider in ('groq', 'huggingFace', 'openRouter')),
  model text,
  status text not null check (status in ('success', 'error')),
  latency_ms integer check (latency_ms is null or latency_ms >= 0),
  retryable boolean not null default false,
  error_code text,
  created_at timestamptz not null default now()
);

create table if not exists homepilot_private.ai_request_idempotency (
  user_id uuid not null references auth.users(id) on delete cascade,
  action text not null,
  idempotency_key text not null,
  request_id text not null,
  status text not null
    check (status in ('in_progress', 'completed', 'error')),
  error_code text,
  expires_at timestamptz not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, action, idempotency_key)
);

create index if not exists ai_provider_events_request_id_idx
  on homepilot_private.ai_provider_events (request_id, created_at desc);

create index if not exists ai_provider_events_provider_created_at_idx
  on homepilot_private.ai_provider_events (provider, created_at desc);

create index if not exists ai_request_idempotency_expires_at_idx
  on homepilot_private.ai_request_idempotency (expires_at);

alter table homepilot_private.ai_provider_runtime_status enable row level security;
alter table homepilot_private.ai_provider_events enable row level security;
alter table homepilot_private.ai_request_idempotency enable row level security;

revoke all on homepilot_private.ai_provider_runtime_status
  from public, anon, authenticated;
revoke all on homepilot_private.ai_provider_events
  from public, anon, authenticated;
revoke all on homepilot_private.ai_request_idempotency
  from public, anon, authenticated;

grant select, insert, update, delete
  on homepilot_private.ai_provider_runtime_status
  to service_role;
grant select, insert, update, delete
  on homepilot_private.ai_provider_events
  to service_role;
grant select, insert, update, delete
  on homepilot_private.ai_request_idempotency
  to service_role;

create or replace function public.upsert_ai_provider_runtime_status(
  p_provider text,
  p_model text,
  p_state text,
  p_healthy boolean,
  p_failure_count integer,
  p_cooldown_until timestamptz,
  p_last_error_code text,
  p_latency_ms integer,
  p_checked_at timestamptz
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into homepilot_private.ai_provider_runtime_status (
    provider,
    model,
    state,
    healthy,
    failure_count,
    cooldown_until,
    last_success_at,
    last_failure_at,
    latency_ms,
    last_error_code,
    checked_at,
    updated_at
  )
  values (
    p_provider,
    p_model,
    p_state,
    p_healthy,
    greatest(coalesce(p_failure_count, 0), 0),
    p_cooldown_until,
    case when p_healthy then p_checked_at else null end,
    case when p_healthy then null else p_checked_at end,
    p_latency_ms,
    p_last_error_code,
    coalesce(p_checked_at, now()),
    now()
  )
  on conflict (provider) do update
  set
    model = excluded.model,
    state = excluded.state,
    healthy = excluded.healthy,
    failure_count = excluded.failure_count,
    cooldown_until = excluded.cooldown_until,
    last_success_at = case
      when excluded.healthy then excluded.checked_at
      else homepilot_private.ai_provider_runtime_status.last_success_at
    end,
    last_failure_at = case
      when excluded.healthy then homepilot_private.ai_provider_runtime_status.last_failure_at
      else excluded.checked_at
    end,
    latency_ms = excluded.latency_ms,
    last_error_code = excluded.last_error_code,
    checked_at = excluded.checked_at,
    updated_at = now();
end;
$$;

create or replace function public.record_ai_provider_event(
  p_request_id text,
  p_phase text,
  p_provider text,
  p_model text,
  p_status text,
  p_latency_ms integer,
  p_retryable boolean,
  p_error_code text
)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into homepilot_private.ai_provider_events (
    request_id,
    phase,
    provider,
    model,
    status,
    latency_ms,
    retryable,
    error_code
  )
  values (
    p_request_id,
    p_phase,
    p_provider,
    p_model,
    p_status,
    p_latency_ms,
    coalesce(p_retryable, false),
    p_error_code
  );
$$;

create or replace function public.claim_ai_request_idempotency(
  p_user_id uuid,
  p_action text,
  p_idempotency_key text,
  p_request_id text,
  p_expires_at timestamptz
)
returns table(status text)
language plpgsql
security definer
set search_path = ''
as $$
declare
  existing homepilot_private.ai_request_idempotency%rowtype;
begin
  insert into homepilot_private.ai_request_idempotency (
    user_id,
    action,
    idempotency_key,
    request_id,
    status,
    expires_at,
    created_at,
    updated_at
  )
  values (
    p_user_id,
    p_action,
    p_idempotency_key,
    p_request_id,
    'in_progress',
    p_expires_at,
    now(),
    now()
  )
  on conflict do nothing;

  if found then
    status := 'started';
    return next;
    return;
  end if;

  select *
    into existing
  from homepilot_private.ai_request_idempotency as dedupe
  where dedupe.user_id = p_user_id
    and dedupe.action = p_action
    and dedupe.idempotency_key = p_idempotency_key
  for update;

  if existing.expires_at <= now() or existing.status = 'error' then
    update homepilot_private.ai_request_idempotency as dedupe
    set
      request_id = p_request_id,
      status = 'in_progress',
      error_code = null,
      expires_at = p_expires_at,
      updated_at = now()
    where dedupe.user_id = p_user_id
      and dedupe.action = p_action
      and dedupe.idempotency_key = p_idempotency_key;
    status := 'started';
    return next;
    return;
  end if;

  if existing.status = 'in_progress' then
    status := 'duplicate_in_progress';
    return next;
    return;
  end if;

  status := 'duplicate_completed';
  return next;
end;
$$;

create or replace function public.complete_ai_request_idempotency(
  p_user_id uuid,
  p_action text,
  p_idempotency_key text,
  p_status text,
  p_error_code text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_status not in ('completed', 'error') then
    raise exception 'invalid idempotency status';
  end if;

  update homepilot_private.ai_request_idempotency as dedupe
  set
    status = p_status,
    error_code = p_error_code,
    updated_at = now()
  where dedupe.user_id = p_user_id
    and dedupe.action = p_action
    and dedupe.idempotency_key = p_idempotency_key
    and dedupe.status = 'in_progress';
end;
$$;

revoke all on function public.upsert_ai_provider_runtime_status(
  text, text, text, boolean, integer, timestamptz, text, integer, timestamptz
) from public, anon, authenticated;
grant execute on function public.upsert_ai_provider_runtime_status(
  text, text, text, boolean, integer, timestamptz, text, integer, timestamptz
) to service_role;

revoke all on function public.record_ai_provider_event(
  text, text, text, text, text, integer, boolean, text
) from public, anon, authenticated;
grant execute on function public.record_ai_provider_event(
  text, text, text, text, text, integer, boolean, text
) to service_role;

revoke all on function public.claim_ai_request_idempotency(
  uuid, text, text, text, timestamptz
) from public, anon, authenticated;
grant execute on function public.claim_ai_request_idempotency(
  uuid, text, text, text, timestamptz
) to service_role;

revoke all on function public.complete_ai_request_idempotency(
  uuid, text, text, text, text
) from public, anon, authenticated;
grant execute on function public.complete_ai_request_idempotency(
  uuid, text, text, text, text
) to service_role;
