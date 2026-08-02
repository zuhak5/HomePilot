drop index if exists public.maintenance_plans_enabled_due_idx;

alter table public.maintenance_plans
drop column if exists is_enabled;
