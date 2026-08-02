begin;

-- The fixed production client invokes this RPC with an authenticated
-- Supabase session. Keep all broader roles denied.
revoke all
on function public.complete_maintenance_task(jsonb, text)
from public, anon, authenticated, service_role;

grant execute
on function public.complete_maintenance_task(jsonb, text)
to authenticated;

notify pgrst, 'reload schema';

commit;