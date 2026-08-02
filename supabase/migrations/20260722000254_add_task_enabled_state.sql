alter table public.maintenance_plans
add column if not exists is_enabled boolean not null default true;

create index if not exists maintenance_plans_enabled_due_idx
on public.maintenance_plans (user_id, next_due_date)
where archived_at is null
  and is_enabled;
