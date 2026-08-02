do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'profiles', 'areas', 'rooms', 'assets', 'device_details', 'pet_details',
    'plant_details', 'safety_details', 'tags', 'asset_tags', 'asset_photos',
    'maintenance_plans', 'maintenance_records'
  ]
  loop
    execute format('alter table public.%I enable row level security', table_name);
    execute format('revoke all on table public.%I from anon, authenticated', table_name);
    execute format(
      'grant select, insert, update on table public.%I to authenticated',
      table_name
    );
    execute format(
      'create policy %I on public.%I for select to authenticated '
      'using ((select auth.uid()) is not null and (select auth.uid()) = user_id)',
      table_name || '_select_own',
      table_name
    );
    execute format(
      'create policy %I on public.%I for insert to authenticated '
      'with check ((select auth.uid()) is not null and (select auth.uid()) = user_id)',
      table_name || '_insert_own',
      table_name
    );
    execute format(
      'create policy %I on public.%I for update to authenticated '
      'using ((select auth.uid()) is not null and (select auth.uid()) = user_id) '
      'with check ((select auth.uid()) is not null and (select auth.uid()) = user_id)',
      table_name || '_update_own',
      table_name
    );
    execute format(
      'create index %I on public.%I (user_id, sync_seq)',
      table_name || '_user_sync_seq_idx',
      table_name
    );
  end loop;
end
$$;

alter table public.catalog_categories enable row level security;
revoke all on table public.catalog_categories from anon, authenticated;
grant select on table public.catalog_categories to authenticated;
create policy catalog_categories_authenticated_read
on public.catalog_categories
for select
to authenticated
using (true);

revoke all on sequence public.homepilot_sync_seq from public, anon;
grant usage, select on sequence public.homepilot_sync_seq to authenticated;

create unique index areas_active_name_uidx
on public.areas (user_id, lower(name))
where deleted_at is null;

create index areas_active_sort_idx
on public.areas (user_id, archived_at, sort_order, name)
where deleted_at is null;

create unique index rooms_active_name_uidx
on public.rooms (user_id, area_id, lower(name))
where deleted_at is null;

create index rooms_active_sort_idx
on public.rooms (user_id, area_id, archived_at, sort_order, name)
where deleted_at is null;

create index assets_room_active_idx
on public.assets (user_id, room_id, archived_at)
where deleted_at is null;

create index assets_category_idx
on public.assets (user_id, category_id)
where deleted_at is null;

create unique index tags_active_name_uidx
on public.tags (user_id, lower(name))
where deleted_at is null;

create index asset_tags_tag_idx
on public.asset_tags (user_id, tag_id)
where deleted_at is null;

create index asset_photos_asset_created_idx
on public.asset_photos (user_id, asset_id, created_at)
where deleted_at is null;

create unique index asset_photos_one_primary_uidx
on public.asset_photos (user_id, asset_id)
where is_primary and deleted_at is null;

create index maintenance_plans_asset_idx
on public.maintenance_plans (user_id, asset_id)
where deleted_at is null;

create index maintenance_plans_due_idx
on public.maintenance_plans (user_id, next_due_date)
where deleted_at is null and archived_at is null;

create index maintenance_records_plan_completed_idx
on public.maintenance_records (user_id, plan_id, completed_at desc)
where deleted_at is null;
