begin;

create extension if not exists pgtap with schema extensions;
set local role postgres;
set search_path = public, extensions, pg_catalog;

select extensions.plan(29);

select extensions.has_table('public', 'profiles', 'profiles table exists');
select extensions.has_table('public', 'categories', 'user-owned categories table exists');
select extensions.has_table('public', 'areas', 'areas table exists');
select extensions.has_table('public', 'rooms', 'rooms table exists');
select extensions.has_table('public', 'assets', 'assets table exists');
select extensions.has_table('public', 'device_details', 'device details table exists');
select extensions.has_table('public', 'pet_details', 'pet details table exists');
select extensions.has_table('public', 'plant_details', 'plant details table exists');
select extensions.has_table('public', 'safety_details', 'safety details table exists');
select extensions.has_table('public', 'tags', 'tags table exists');
select extensions.has_table('public', 'asset_tags', 'asset tags table exists');
select extensions.has_table('public', 'asset_photos', 'asset photos table exists');
select extensions.has_table('public', 'maintenance_plans', 'plans table exists');
select extensions.has_table('public', 'maintenance_plan_metadata', 'plan metadata table exists');
select extensions.has_table('public', 'maintenance_records', 'records table exists');

select extensions.col_is_pk('public', 'profiles', 'user_id', 'profile user id is primary');
select extensions.has_column('public', 'profiles', 'nickname', 'profiles store nickname');
select extensions.ok(
  not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'profiles'
      and column_name = 'display_name'
  ),
  'legacy profile display name is removed'
);
select extensions.ok(
  not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'profiles'
      and column_name = 'avatar_object_path'
  ),
  'legacy profile avatar path is removed'
);
select extensions.has_column('public', 'categories', 'user_id', 'categories belong to users');
select extensions.has_column('public', 'categories', 'updated_at', 'categories have update time');
select extensions.has_column('public', 'device_details', 'created_at', 'detail tables have create time');
select extensions.has_column('public', 'asset_tags', 'updated_at', 'join rows have update time');
select extensions.ok(
  not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'assets'
      and column_name = 'sync_seq'
  ),
  'assets no longer expose sync sequence'
);
select extensions.ok(
  not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'assets'
      and column_name = 'deleted_at'
  ),
  'assets use hard deletes'
);
select extensions.ok(
  to_regclass('public.maintenance_sessions') is null,
  'maintenance sessions table is removed'
);
select extensions.ok(
  to_regclass('public.maintenance_session_tasks') is null,
  'maintenance session tasks table is removed'
);
select extensions.ok(
  exists (
    select 1
    from information_schema.triggers
    where trigger_schema = 'auth'
      and event_object_schema = 'auth'
      and event_object_table = 'users'
      and trigger_name = 'initialize_homepilot_profile_for_user'
  ),
  'new Auth users initialize a HomePilot profile'
);

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
) values (
  '00000000-0000-0000-0000-000000000000',
  '11111111-1111-1111-1111-111111111111',
  'authenticated',
  'authenticated',
  'profile-init@example.test',
  '',
  now(),
  now(),
  now()
);
select extensions.is(
  (
    select count(*)::integer
    from public.profiles
    where user_id = '11111111-1111-1111-1111-111111111111'
  ),
  1,
  'Auth registration creates exactly one profile row'
);

select * from extensions.finish();
rollback;
