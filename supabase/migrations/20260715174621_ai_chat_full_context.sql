alter table public.ai_context_chunks
  add column if not exists source_kind text not null default 'record'
    check (source_kind in ('record', 'summary', 'memory', 'audit')),
  add column if not exists source_summary text,
  add column if not exists source_metadata jsonb not null default '{}'::jsonb;

create index if not exists ai_context_chunks_user_kind_idx
on public.ai_context_chunks (user_id, source_kind, source_table);

drop function if exists public.match_ai_context_chunks(
  extensions.halfvec,
  integer,
  double precision
);

create function public.match_ai_context_chunks(
  p_query_embedding extensions.halfvec(384),
  p_match_count integer default 8,
  p_threshold double precision default 0.68
)
returns table (
  id uuid,
  source_table text,
  source_id text,
  source_kind text,
  source_summary text,
  source_metadata jsonb,
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
    chunks.source_kind,
    chunks.source_summary,
    chunks.source_metadata,
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
  limit least(greatest(coalesce(p_match_count, 8), 1), 20);
$$;

revoke all on function public.match_ai_context_chunks(extensions.halfvec, integer, double precision) from public;
revoke all on function public.match_ai_context_chunks(extensions.halfvec, integer, double precision) from anon;
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
    nullif(row_data ->> 'key', ''),
    nullif(row_data ->> 'provider', ''),
    nullif(row_data ->> 'session_id', ''),
    nullif(row_data ->> 'user_id', ''),
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

do $$
declare
  table_name text;
  trigger_name text;
begin
  foreach table_name in array array[
    'profiles',
    'areas',
    'rooms',
    'asset_photos',
    'notification_inbox',
    'device_notifications',
    'user_settings',
    'device_settings',
    'streaks',
    'ai_review_sessions',
    'ai_review_suggestions',
    'ai_review_apply_attempts'
  ]
  loop
    if to_regclass(format('public.%I', table_name)) is null then
      continue;
    end if;

    trigger_name := 'enqueue_ai_context_dirty_' || table_name;
    if not exists (
      select 1
      from pg_trigger trg
      join pg_class relation on relation.oid = trg.tgrelid
      join pg_namespace namespace on namespace.oid = relation.relnamespace
      where namespace.nspname = 'public'
        and relation.relname = table_name
        and trg.tgname = trigger_name
    ) then
      execute format(
        'create trigger %I after insert or update or delete on public.%I ' ||
        'for each row execute function homepilot_private.enqueue_ai_context_dirty()',
        trigger_name,
        table_name
      );
    end if;
  end loop;
end;
$$;
