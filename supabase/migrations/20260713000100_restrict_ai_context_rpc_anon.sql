revoke all on function public.match_ai_context_chunks(extensions.halfvec, integer, double precision) from public;
revoke all on function public.match_ai_context_chunks(extensions.halfvec, integer, double precision) from anon;
grant execute on function public.match_ai_context_chunks(extensions.halfvec, integer, double precision) to authenticated;
