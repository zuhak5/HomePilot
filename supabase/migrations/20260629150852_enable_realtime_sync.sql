-- Realtime is an invalidation signal for the existing cursor-based sync.
-- FULL identity also makes primary keys available for DELETE notifications.
do $$
declare
  table_name text;
  sync_tables constant text[] := array[
    'catalog_categories',
    'profiles',
    'areas',
    'rooms',
    'assets',
    'device_details',
    'pet_details',
    'plant_details',
    'safety_details',
    'tags',
    'asset_tags',
    'asset_photos',
    'maintenance_plans',
    'maintenance_records',
    'device_notifications',
    'notification_inbox',
    'ai_provider_settings',
    'device_ai_provider_status',
    'ai_usage_logs',
    'user_settings',
    'device_settings',
    'streaks'
  ];
begin
  foreach table_name in array sync_tables loop
    execute format(
      'alter table public.%I replica identity full',
      table_name
    );

    if not exists (
      select 1
      from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = table_name
    ) then
      execute format(
        'alter publication supabase_realtime add table public.%I',
        table_name
      );
    end if;
  end loop;
end
$$;
