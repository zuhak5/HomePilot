begin;

create extension if not exists pgtap with schema extensions;

select plan(27);

select has_table('public', 'profiles', 'profiles table exists');
select has_table('public', 'categories', 'user-owned categories table exists');
select has_table('public', 'areas', 'areas table exists');
select has_table('public', 'rooms', 'rooms table exists');
select has_table('public', 'assets', 'assets table exists');
select has_table('public', 'device_details', 'device details table exists');
select has_table('public', 'pet_details', 'pet details table exists');
select has_table('public', 'plant_details', 'plant details table exists');
select has_table('public', 'safety_details', 'safety details table exists');
select has_table('public', 'tags', 'tags table exists');
select has_table('public', 'asset_tags', 'asset tags table exists');
select has_table('public', 'asset_photos', 'asset photos table exists');
select has_table('public', 'maintenance_plans', 'plans table exists');
select has_table('public', 'maintenance_plan_metadata', 'plan metadata table exists');
select has_table('public', 'maintenance_records', 'records table exists');

select col_is_pk('public', 'profiles', 'user_id', 'profile user id is primary');
select has_column('public', 'profiles', 'nickname', 'profiles store nickname');
select ok(
  not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'profiles'
      and column_name = 'display_name'
  ),
  'legacy profile display name is removed'
);
select ok(
  not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'profiles'
      and column_name = 'avatar_object_path'
  ),
  'legacy profile avatar path is removed'
);
select has_column('public', 'categories', 'user_id', 'categories belong to users');
select has_column('public', 'categories', 'updated_at', 'categories have update time');
select has_column('public', 'device_details', 'created_at', 'detail tables have create time');
select has_column('public', 'asset_tags', 'updated_at', 'join rows have update time');
select ok(
  not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'assets'
      and column_name = 'sync_seq'
  ),
  'assets no longer expose sync sequence'
);
select ok(
  not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'assets'
      and column_name = 'deleted_at'
  ),
  'assets use hard deletes'
);
select ok(
  to_regclass('public.maintenance_sessions') is null,
  'maintenance sessions table is removed'
);
select ok(
  to_regclass('public.maintenance_session_tasks') is null,
  'maintenance session tasks table is removed'
);

select * from finish();
rollback;
