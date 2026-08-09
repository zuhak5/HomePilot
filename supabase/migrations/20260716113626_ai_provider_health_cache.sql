create table public.ai_provider_health_cache (
  user_id uuid not null references auth.users(id) on delete cascade,
  provider text not null check (char_length(provider) between 1 and 120),
  model text not null check (char_length(model) between 1 and 300),
  healthy boolean not null,
  error_code text check (
    error_code is null or char_length(error_code) <= 300
  ),
  latency_ms integer not null default 0 check (latency_ms >= 0),
  checked_at timestamptz not null default now(),
  expires_at timestamptz not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, provider, model)
);

alter table public.ai_provider_health_cache enable row level security;

create policy "Users can read their AI provider health"
on public.ai_provider_health_cache
for select
to authenticated
using ((select auth.uid()) = user_id);

revoke all on public.ai_provider_health_cache from anon;
revoke insert, update, delete on public.ai_provider_health_cache from authenticated;
grant select on public.ai_provider_health_cache to authenticated;

create index ai_provider_health_cache_expires_idx
on public.ai_provider_health_cache (expires_at);
