create table public.sync_activity (
  user_id uuid primary key references auth.users(id) on delete cascade,
  last_sync_seq bigint not null default 0 check (last_sync_seq >= 0),
  updated_at timestamptz not null default clock_timestamp()
);

alter table public.sync_activity enable row level security;

create policy "Users select own sync activity"
on public.sync_activity for select
to authenticated
using ((select auth.uid()) = user_id);

revoke all on public.sync_activity from anon, authenticated;
grant select on public.sync_activity to authenticated;

create function homepilot_private.bump_sync_activity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.sync_activity (user_id, last_sync_seq, updated_at)
  values (new.user_id, new.sync_seq, clock_timestamp())
  on conflict (user_id) do update
  set
    last_sync_seq = greatest(
      public.sync_activity.last_sync_seq,
      excluded.last_sync_seq
    ),
    updated_at = clock_timestamp();
  return new;
end;
$$;

revoke all on function homepilot_private.bump_sync_activity()
from public, anon, authenticated;

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'profiles', 'areas', 'rooms', 'assets', 'device_details', 'pet_details',
    'plant_details', 'safety_details', 'tags', 'asset_tags', 'asset_photos',
    'maintenance_plans', 'maintenance_records', 'device_notifications',
    'notification_inbox', 'ai_provider_settings',
    'device_ai_provider_status', 'ai_usage_logs', 'user_settings',
    'device_settings', 'streaks', 'sync_tombstones'
  ]
  loop
    execute format(
      'create trigger bump_sync_activity '
      'after insert or update on public.%I '
      'for each row execute function homepilot_private.bump_sync_activity()',
      table_name
    );
    execute format(
      'insert into public.sync_activity (user_id, last_sync_seq) '
      'select user_id, max(sync_seq) from public.%I group by user_id '
      'on conflict (user_id) do update set '
      'last_sync_seq = greatest('
      'public.sync_activity.last_sync_seq, excluded.last_sync_seq), '
      'updated_at = clock_timestamp()',
      table_name
    );
  end loop;
end
$$;

alter table public.sync_activity replica identity full;

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'sync_activity'
  ) then
    alter publication supabase_realtime add table public.sync_activity;
  end if;
end
$$;
