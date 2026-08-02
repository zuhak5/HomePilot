create extension if not exists vector with schema extensions;

create schema if not exists homepilot_private;
revoke all on schema homepilot_private from public;
revoke all on schema homepilot_private from anon;
revoke all on schema homepilot_private from authenticated;

create table public.ai_context_preferences (
  user_id uuid primary key references auth.users(id) on delete cascade,
  home_context_enabled boolean not null default false,
  rag_chat_enabled boolean not null default false,
  whole_home_generation_enabled boolean not null default false,
  last_indexed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.ai_context_chunks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  source_table text not null,
  source_id text not null,
  chunk_index integer not null check (chunk_index >= 0),
  source_hash text not null,
  prompt_safe_text text not null check (char_length(prompt_safe_text) between 1 and 8192),
  token_count integer not null check (token_count between 1 and 512),
  embedding extensions.halfvec(384) not null,
  prompt_version text not null default 'ai-context-v1',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, source_table, source_id, chunk_index, prompt_version)
);

create table public.ai_context_dirty_queue (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  source_table text not null,
  source_key text not null,
  row_op text not null default 'UPSERT' check (row_op in ('INSERT', 'UPDATE', 'DELETE', 'UPSERT')),
  attempts integer not null default 0 check (attempts >= 0),
  last_error_code text,
  available_at timestamptz not null default now(),
  processed_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.ai_invocations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  request_id text not null unique,
  action text not null,
  provider text,
  model text,
  status text not null check (status in ('started', 'success', 'error', 'cache_hit')),
  latency_ms integer not null default 0 check (latency_ms >= 0),
  prompt_tokens integer check (prompt_tokens is null or prompt_tokens >= 0),
  completion_tokens integer check (completion_tokens is null or completion_tokens >= 0),
  estimated_cost_micros integer check (estimated_cost_micros is null or estimated_cost_micros >= 0),
  cache_hit boolean not null default false,
  rag_chunk_count integer not null default 0 check (rag_chunk_count >= 0),
  prompt_version text not null,
  error_code text,
  created_at timestamptz not null default now()
);

create table public.ai_response_cache (
  cache_key text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  action text not null,
  provider text not null,
  model text not null,
  routing_mode text not null,
  prompt_version text not null,
  context_hash text not null,
  result_json jsonb not null,
  usage_json jsonb not null default '{}'::jsonb,
  expires_at timestamptz not null,
  created_at timestamptz not null default now(),
  last_hit_at timestamptz
);

create table homepilot_private.ai_user_provider_key_refs (
  user_id uuid not null references auth.users(id) on delete cascade,
  provider text not null check (provider in ('google', 'groq', 'openRouter', 'huggingFace')),
  encrypted_api_key text not null,
  encryption_nonce text not null,
  key_fingerprint text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, provider)
);

alter table public.ai_context_preferences enable row level security;
alter table public.ai_context_chunks enable row level security;
alter table public.ai_context_dirty_queue enable row level security;
alter table public.ai_invocations enable row level security;
alter table public.ai_response_cache enable row level security;
alter table homepilot_private.ai_user_provider_key_refs enable row level security;

create policy "ai context preferences are readable by owner"
on public.ai_context_preferences
for select
to authenticated
using ((select auth.uid()) = user_id);

create policy "ai context preferences are insertable by owner"
on public.ai_context_preferences
for insert
to authenticated
with check ((select auth.uid()) = user_id);

create policy "ai context preferences are updatable by owner"
on public.ai_context_preferences
for update
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

create policy "ai context preferences are deletable by owner"
on public.ai_context_preferences
for delete
to authenticated
using ((select auth.uid()) = user_id);

create policy "ai context chunks are readable by owner"
on public.ai_context_chunks
for select
to authenticated
using (
  (select auth.uid()) = user_id
  and exists (
    select 1
    from public.ai_context_preferences preferences
    where preferences.user_id = ai_context_chunks.user_id
      and preferences.home_context_enabled
  )
);

create policy "ai context dirty queue is readable by owner"
on public.ai_context_dirty_queue
for select
to authenticated
using ((select auth.uid()) = user_id);

create policy "ai invocations are readable by owner"
on public.ai_invocations
for select
to authenticated
using ((select auth.uid()) = user_id);

create policy "ai response cache is readable by owner"
on public.ai_response_cache
for select
to authenticated
using ((select auth.uid()) = user_id);

grant select, insert, update, delete on public.ai_context_preferences to authenticated;
grant select on public.ai_context_chunks to authenticated;
grant select on public.ai_context_dirty_queue to authenticated;
grant select on public.ai_invocations to authenticated;
grant select on public.ai_response_cache to authenticated;
revoke all on public.ai_context_preferences from anon;
revoke all on public.ai_context_chunks from anon;
revoke all on public.ai_context_dirty_queue from anon;
revoke all on public.ai_invocations from anon;
revoke all on public.ai_response_cache from anon;

grant usage on schema homepilot_private to service_role;
grant select, insert, update, delete on all tables in schema homepilot_private to service_role;
revoke all on all tables in schema homepilot_private from public;
revoke all on all tables in schema homepilot_private from anon;
revoke all on all tables in schema homepilot_private from authenticated;

create index ai_context_chunks_user_source_idx
on public.ai_context_chunks (user_id, source_table, source_id);

create index ai_context_chunks_embedding_hnsw_idx
on public.ai_context_chunks
using hnsw (embedding extensions.halfvec_cosine_ops);

create index ai_context_dirty_queue_ready_idx
on public.ai_context_dirty_queue (available_at, created_at)
where processed_at is null;

create index ai_invocations_user_created_idx
on public.ai_invocations (user_id, created_at desc);

create index ai_response_cache_user_action_idx
on public.ai_response_cache (user_id, action, expires_at);

create or replace function public.match_ai_context_chunks(
  p_query_embedding extensions.halfvec(384),
  p_match_count integer default 5,
  p_threshold double precision default 0.72
)
returns table (
  id uuid,
  source_table text,
  source_id text,
  chunk_index integer,
  prompt_safe_text text,
  similarity double precision
)
language sql
stable
security invoker
set search_path = ''
as $$
  select
    chunks.id,
    chunks.source_table,
    chunks.source_id,
    chunks.chunk_index,
    chunks.prompt_safe_text,
    1 - (chunks.embedding operator(extensions.<=>) p_query_embedding) as similarity
  from public.ai_context_chunks chunks
  where chunks.user_id = (select auth.uid())
    and exists (
      select 1
      from public.ai_context_preferences preferences
      where preferences.user_id = chunks.user_id
        and preferences.home_context_enabled
    )
    and 1 - (chunks.embedding operator(extensions.<=>) p_query_embedding) >= p_threshold
  order by chunks.embedding operator(extensions.<=>) p_query_embedding
  limit least(greatest(coalesce(p_match_count, 5), 1), 20);
$$;

revoke all on function public.match_ai_context_chunks(extensions.halfvec, integer, double precision) from public;
grant execute on function public.match_ai_context_chunks(extensions.halfvec, integer, double precision) to authenticated;

create or replace function homepilot_private.enqueue_ai_context_dirty()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  row_data jsonb;
  row_user_id uuid;
  row_key text;
begin
  row_data := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;
  row_user_id := nullif(row_data ->> 'user_id', '')::uuid;
  if row_user_id is null then
    return coalesce(new, old);
  end if;

  if not exists (
    select 1
    from public.ai_context_preferences preferences
    where preferences.user_id = row_user_id
      and preferences.home_context_enabled
  ) then
    return coalesce(new, old);
  end if;

  row_key := coalesce(
    nullif(row_data ->> 'id', ''),
    nullif(row_data ->> 'asset_id', ''),
    nullif(row_data ->> 'plan_id', ''),
    concat_ws(':', row_data ->> 'asset_id', row_data ->> 'tag_id')
  );

  if row_key is null or row_key = '' then
    return coalesce(new, old);
  end if;

  insert into public.ai_context_dirty_queue (
    user_id,
    source_table,
    source_key,
    row_op,
    available_at
  )
  values (
    row_user_id,
    tg_table_name,
    row_key,
    tg_op,
    now()
  );

  return coalesce(new, old);
end;
$$;

revoke all on function homepilot_private.enqueue_ai_context_dirty() from public;
revoke all on function homepilot_private.enqueue_ai_context_dirty() from anon;
revoke all on function homepilot_private.enqueue_ai_context_dirty() from authenticated;

create trigger enqueue_ai_context_dirty_assets
after insert or update or delete on public.assets
for each row execute function homepilot_private.enqueue_ai_context_dirty();

create trigger enqueue_ai_context_dirty_device_details
after insert or update or delete on public.device_details
for each row execute function homepilot_private.enqueue_ai_context_dirty();

create trigger enqueue_ai_context_dirty_pet_details
after insert or update or delete on public.pet_details
for each row execute function homepilot_private.enqueue_ai_context_dirty();

create trigger enqueue_ai_context_dirty_plant_details
after insert or update or delete on public.plant_details
for each row execute function homepilot_private.enqueue_ai_context_dirty();

create trigger enqueue_ai_context_dirty_safety_details
after insert or update or delete on public.safety_details
for each row execute function homepilot_private.enqueue_ai_context_dirty();

create trigger enqueue_ai_context_dirty_tags
after insert or update or delete on public.tags
for each row execute function homepilot_private.enqueue_ai_context_dirty();

create trigger enqueue_ai_context_dirty_asset_tags
after insert or update or delete on public.asset_tags
for each row execute function homepilot_private.enqueue_ai_context_dirty();

create trigger enqueue_ai_context_dirty_maintenance_plans
after insert or update or delete on public.maintenance_plans
for each row execute function homepilot_private.enqueue_ai_context_dirty();

create trigger enqueue_ai_context_dirty_maintenance_records
after insert or update or delete on public.maintenance_records
for each row execute function homepilot_private.enqueue_ai_context_dirty();
