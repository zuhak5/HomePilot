begin;

create table if not exists public.categories (
  user_id uuid not null references auth.users(id) on delete cascade,
  id text not null,
  name text not null check (char_length(name) between 1 and 120),
  health_group text not null
    check (health_group in ('safety', 'pets', 'appliances', 'plants', 'cleaning', 'other')),
  icon_name text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  archived_at timestamptz,
  revision bigint not null default 1 check (revision > 0),
  primary key (user_id, id)
);

create schema if not exists homepilot_private;
revoke all on schema homepilot_private from public, anon, authenticated;

create table if not exists homepilot_private.default_categories (
  id text primary key,
  name text not null,
  health_group text not null,
  icon_name text not null
);

revoke all on table homepilot_private.default_categories from public, anon, authenticated;

insert into homepilot_private.default_categories (
  id, name, health_group, icon_name
)
values
  ('category_safety', 'Safety', 'safety', 'shield'),
  ('category_pets', 'Pets', 'pets', 'pets'),
  ('category_appliances', 'Appliances', 'appliances', 'kitchen'),
  ('category_plants', 'Plants', 'plants', 'yard'),
  ('category_cleaning', 'Cleaning', 'cleaning', 'cleaning_services'),
  ('category_general', 'General', 'other', 'home')
on conflict (id) do update set
  name = excluded.name,
  health_group = excluded.health_group,
  icon_name = excluded.icon_name;

create or replace function homepilot_private.seed_homepilot_categories_for_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.categories (
    user_id, id, name, health_group, icon_name, created_at, updated_at
  )
  select
    new.id,
    defaults.id,
    defaults.name,
    defaults.health_group,
    defaults.icon_name,
    now(),
    now()
  from homepilot_private.default_categories as defaults
  on conflict (user_id, id) do nothing;

  return new;
end;
$$;

revoke all on function homepilot_private.seed_homepilot_categories_for_user()
from public, anon, authenticated;

drop trigger if exists seed_homepilot_categories_for_user on auth.users;
create trigger seed_homepilot_categories_for_user
after insert on auth.users
for each row execute function homepilot_private.seed_homepilot_categories_for_user();

alter table public.categories enable row level security;
revoke all on table public.categories from anon, authenticated;
grant select, insert, update, delete on table public.categories to authenticated;

drop policy if exists categories_select_own on public.categories;
drop policy if exists categories_insert_own on public.categories;
drop policy if exists categories_update_own on public.categories;
drop policy if exists categories_delete_own on public.categories;

create policy categories_select_own
on public.categories for select
to authenticated
using ((select auth.uid()) = user_id);

create policy categories_insert_own
on public.categories for insert
to authenticated
with check ((select auth.uid()) = user_id);

create policy categories_update_own
on public.categories for update
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

create policy categories_delete_own
on public.categories for delete
to authenticated
using ((select auth.uid()) = user_id);

create index if not exists categories_user_updated_idx
on public.categories (user_id, updated_at desc);

with users_with_data as (
  select id as user_id from auth.users
  union select user_id from public.profiles
  union select user_id from public.areas
  union select user_id from public.rooms
  union select user_id from public.assets
  union select user_id from public.device_details
  union select user_id from public.pet_details
  union select user_id from public.plant_details
  union select user_id from public.safety_details
  union select user_id from public.tags
  union select user_id from public.asset_tags
  union select user_id from public.asset_photos
  union select user_id from public.maintenance_plans
  union select user_id from public.maintenance_records
  union select user_id from public.maintenance_plan_metadata
  union select user_id from public.maintenance_sessions
  union select user_id from public.maintenance_session_tasks
  union select user_id from public.notification_inbox
  union select user_id from public.user_settings
  union select user_id from public.streaks
),
catalog as (
  select id, name, health_group, icon_name, created_at, updated_at
  from public.catalog_categories
)
insert into public.categories (
  user_id, id, name, health_group, icon_name, created_at, updated_at
)
select
  users_with_data.user_id,
  catalog.id,
  catalog.name,
  catalog.health_group,
  catalog.icon_name,
  catalog.created_at,
  catalog.updated_at
from users_with_data
cross join catalog
on conflict (user_id, id) do nothing;

insert into public.categories (
  user_id, id, name, health_group, icon_name, created_at, updated_at
)
select distinct
  assets.user_id,
  assets.category_id,
  coalesce(catalog_categories.name, initcap(replace(assets.category_id, '_', ' '))),
  coalesce(catalog_categories.health_group, 'other'),
  coalesce(catalog_categories.icon_name, 'category'),
  now(),
  now()
from public.assets
left join public.catalog_categories on catalog_categories.id = assets.category_id
on conflict (user_id, id) do nothing;

do $$
declare
  constraint_name text;
begin
  for constraint_name in
    select conname
    from pg_constraint
    where conrelid = 'public.assets'::regclass
      and confrelid = 'public.catalog_categories'::regclass
  loop
    execute format('alter table public.assets drop constraint %I', constraint_name);
  end loop;
end
$$;

alter table public.assets
  add constraint assets_category_owned_fkey
  foreign key (user_id, category_id)
  references public.categories(user_id, id);

do $$
declare
  table_name text;
  trigger_name text;
begin
  foreach table_name in array array[
    'profiles', 'areas', 'rooms', 'assets', 'device_details', 'pet_details',
    'plant_details', 'safety_details', 'tags', 'asset_tags', 'asset_photos',
    'maintenance_plans', 'maintenance_records', 'maintenance_plan_metadata',
    'maintenance_sessions', 'maintenance_session_tasks', 'notification_inbox',
    'user_settings', 'streaks', 'device_notifications', 'device_settings'
  ]
  loop
    if to_regclass(format('public.%I', table_name)) is null then
      continue;
    end if;

    foreach trigger_name in array array[
      'set_sync_metadata',
      'capture_sync_tombstone',
      'finalize_soft_delete',
      'bump_sync_activity',
      'protect_device_id'
    ]
    loop
      execute format(
        'drop trigger if exists %I on public.%I',
        trigger_name,
        table_name
      );
    end loop;
  end loop;
end
$$;

create or replace function public.set_homepilot_row_metadata()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' then
    new.user_id := old.user_id;
    if to_jsonb(new) ? 'revision' then
      new.revision := old.revision + 1;
    end if;
  elsif to_jsonb(new) ? 'revision' then
    new.revision := coalesce(new.revision, 1);
  end if;

  if to_jsonb(new) ? 'updated_at' then
    new.updated_at := case
      when tg_op = 'UPDATE' then clock_timestamp()
      else coalesce(new.updated_at, clock_timestamp())
    end;
  end if;

  return new;
end;
$$;

revoke all on function public.set_homepilot_row_metadata() from public;

do $$
declare
  app_table text;
begin
  foreach app_table in array array[
    'profiles', 'areas', 'rooms', 'assets', 'device_details', 'pet_details',
    'plant_details', 'safety_details', 'tags', 'asset_tags', 'asset_photos',
    'maintenance_plans', 'maintenance_records', 'maintenance_plan_metadata',
    'maintenance_sessions', 'maintenance_session_tasks', 'notification_inbox',
    'user_settings', 'streaks', 'categories'
  ]
  loop
    if to_regclass(format('public.%I', app_table)) is null then
      continue;
    end if;

    if not exists (
      select 1
      from information_schema.columns
      where table_schema = 'public'
        and table_name = app_table
        and column_name = 'created_at'
    ) then
      execute format(
        'alter table public.%I add column created_at timestamptz not null default now()',
        app_table
      );
    end if;

    if not exists (
      select 1
      from information_schema.columns
      where table_schema = 'public'
        and table_name = app_table
        and column_name = 'updated_at'
    ) then
      execute format(
        'alter table public.%I add column updated_at timestamptz not null default now()',
        app_table
      );
    end if;

    execute format('drop trigger if exists set_row_metadata on public.%I', app_table);
    execute format(
      'create trigger set_row_metadata before insert or update on public.%I ' ||
      'for each row execute function public.set_homepilot_row_metadata()',
      app_table
    );
  end loop;
end
$$;

do $$
declare
  app_table text;
  sync_column text;
begin
  foreach app_table in array array[
    'profiles', 'areas', 'rooms', 'assets', 'device_details', 'pet_details',
    'plant_details', 'safety_details', 'tags', 'asset_tags', 'asset_photos',
    'maintenance_plans', 'maintenance_records', 'maintenance_plan_metadata',
    'maintenance_sessions', 'maintenance_session_tasks', 'notification_inbox',
    'user_settings', 'streaks', 'categories'
  ]
  loop
    if to_regclass(format('public.%I', app_table)) is null then
      continue;
    end if;

    foreach sync_column in array array[
      'client_modified_at',
      'origin_device_id',
      'sync_seq',
      'server_updated_at',
      'deleted_at'
    ]
    loop
      if exists (
        select 1
        from information_schema.columns
        where table_schema = 'public'
          and table_name = app_table
          and column_name = sync_column
      ) then
        execute format(
          'alter table public.%I drop column %I',
          app_table,
          sync_column
        );
      end if;
    end loop;
  end loop;
end
$$;

create unique index if not exists notification_inbox_dedupe_uidx
on public.notification_inbox (user_id, dedupe_key)
where dedupe_key is not null;

create index if not exists notification_inbox_created_idx
on public.notification_inbox (user_id, created_at desc);

do $$
declare
  app_table text;
  policy_name text;
begin
  foreach app_table in array array[
    'profiles', 'areas', 'rooms', 'assets', 'device_details', 'pet_details',
    'plant_details', 'safety_details', 'tags', 'asset_tags', 'asset_photos',
    'maintenance_plans', 'maintenance_records', 'maintenance_plan_metadata',
    'maintenance_sessions', 'maintenance_session_tasks', 'notification_inbox',
    'user_settings', 'streaks', 'categories'
  ]
  loop
    if to_regclass(format('public.%I', app_table)) is null then
      continue;
    end if;

    execute format('alter table public.%I enable row level security', app_table);
    execute format('revoke all on table public.%I from anon, authenticated', app_table);
    execute format(
      'grant select, insert, update, delete on table public.%I to authenticated',
      app_table
    );

    for policy_name in
      select policyname
      from pg_policies
      where schemaname = 'public'
        and tablename = app_table
    loop
      execute format(
        'drop policy if exists %I on public.%I',
        policy_name,
        app_table
      );
    end loop;

    execute format(
      'create policy %I on public.%I for select to authenticated using ((select auth.uid()) = user_id)',
      app_table || '_select_own',
      app_table
    );
    execute format(
      'create policy %I on public.%I for insert to authenticated with check ((select auth.uid()) = user_id)',
      app_table || '_insert_own',
      app_table
    );
    execute format(
      'create policy %I on public.%I for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id)',
      app_table || '_update_own',
      app_table
    );
    execute format(
      'create policy %I on public.%I for delete to authenticated using ((select auth.uid()) = user_id)',
      app_table || '_delete_own',
      app_table
    );
  end loop;
end
$$;

do $$
declare
  app_table text;
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    foreach app_table in array array[
      'profiles', 'areas', 'rooms', 'assets', 'device_details', 'pet_details',
      'plant_details', 'safety_details', 'tags', 'asset_tags', 'asset_photos',
      'maintenance_plans', 'maintenance_records', 'maintenance_plan_metadata',
      'maintenance_sessions', 'maintenance_session_tasks', 'notification_inbox',
      'user_settings', 'streaks', 'categories'
    ]
    loop
      if to_regclass(format('public.%I', app_table)) is null then
        continue;
      end if;

      execute format('alter table public.%I replica identity full', app_table);

      if not exists (
        select 1
        from pg_publication_tables
        where pubname = 'supabase_realtime'
          and schemaname = 'public'
          and tablename = app_table
      ) then
        execute format(
          'alter publication supabase_realtime add table public.%I',
          app_table
        );
      end if;
    end loop;
  end if;
end
$$;

drop function if exists public.delete_homepilot_record(
  text, text, text, timestamptz, text, bigint
);
drop function if exists public.set_homepilot_sync_metadata();
drop function if exists public.protect_homepilot_sync_device() cascade;
drop function if exists homepilot_private.capture_sync_tombstone() cascade;
drop function if exists homepilot_private.bump_sync_activity() cascade;

drop table if exists public.sync_activity cascade;
drop table if exists public.sync_tombstones cascade;
drop table if exists public.sync_devices cascade;
drop table if exists public.device_notifications cascade;
drop table if exists public.device_settings cascade;
drop table if exists public.catalog_categories cascade;
drop sequence if exists public.homepilot_sync_seq;

update storage.buckets
set
  public = false,
  file_size_limit = 10485760,
  allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp']
where id = 'user-media';

commit;
