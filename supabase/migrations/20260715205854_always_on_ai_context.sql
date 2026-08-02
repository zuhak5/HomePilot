update public.ai_context_preferences
set
  home_context_enabled = true,
  rag_chat_enabled = true,
  updated_at = now()
where not home_context_enabled
   or not rag_chat_enabled;

alter table public.ai_context_preferences
  alter column home_context_enabled set default true,
  alter column rag_chat_enabled set default true;

drop policy if exists "ai context preferences are insertable by owner"
on public.ai_context_preferences;

drop policy if exists "ai context preferences are updatable by owner"
on public.ai_context_preferences;

drop policy if exists "ai context preferences are deletable by owner"
on public.ai_context_preferences;

drop policy if exists "ai context chunks are readable by owner"
on public.ai_context_chunks;

create policy "ai context chunks are readable by owner"
on public.ai_context_chunks
for select
to authenticated
using ((select auth.uid()) = user_id);

revoke insert, update, delete on public.ai_context_preferences
from authenticated;
revoke insert, update, delete on public.ai_context_preferences
from public;

grant select on public.ai_context_preferences to authenticated;
grant select, insert, update, delete on public.ai_context_preferences to service_role;
grant select, insert, update, delete on public.ai_context_chunks to service_role;
grant select, insert, update, delete on public.ai_context_dirty_queue to service_role;

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
    and 1 - (chunks.embedding operator(extensions.<=>) p_query_embedding) >= p_threshold
  order by chunks.embedding operator(extensions.<=>) p_query_embedding
  limit least(greatest(coalesce(p_match_count, 8), 1), 20);
$$;

revoke all on function public.match_ai_context_chunks(
  extensions.halfvec,
  integer,
  double precision
) from public;
revoke all on function public.match_ai_context_chunks(
  extensions.halfvec,
  integer,
  double precision
) from anon;
grant execute on function public.match_ai_context_chunks(
  extensions.halfvec,
  integer,
  double precision
) to authenticated;
