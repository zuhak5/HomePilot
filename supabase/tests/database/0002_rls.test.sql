begin;

create extension if not exists pgtap with schema extensions;

select plan(9);

select ok(
  (select bool_and(relrowsecurity)
   from pg_class
   where oid in (
     'public.profiles'::regclass,
     'public.categories'::regclass,
     'public.areas'::regclass,
     'public.assets'::regclass,
     'public.maintenance_records'::regclass
   )),
  'core app tables have RLS enabled'
);

select ok(
  (select bool_and(policy_count = 4)
   from (
     select table_name, count(policyname)::integer as policy_count
     from unnest(array[
       'profiles', 'categories', 'areas', 'rooms', 'assets',
       'device_details', 'pet_details', 'plant_details', 'safety_details',
       'tags', 'asset_tags', 'asset_photos', 'maintenance_plans',
       'maintenance_plan_metadata', 'maintenance_records',
       'notification_inbox', 'user_settings', 'streaks'
     ]) as table_name
     left join pg_policies
       on schemaname = 'public'
      and tablename = table_name
     group by table_name
   ) policy_counts),
  'every exposed app table has select, insert, update, and delete policies'
);

select ok(
  has_table_privilege('authenticated', 'public.categories', 'SELECT'),
  'authenticated can select owned categories'
);
select ok(
  has_table_privilege('authenticated', 'public.categories', 'INSERT'),
  'authenticated can insert owned categories'
);
select ok(
  has_table_privilege('authenticated', 'public.categories', 'UPDATE'),
  'authenticated can update owned categories'
);
select ok(
  has_table_privilege('authenticated', 'public.categories', 'DELETE'),
  'authenticated can delete owned categories'
);
select ok(
  not has_table_privilege('anon', 'public.categories', 'SELECT'),
  'unauthenticated clients cannot read categories'
);
select ok(
  not has_table_privilege('anon', 'public.assets', 'SELECT'),
  'unauthenticated clients cannot read assets'
);
select ok(
  not has_table_privilege('anon', 'public.maintenance_records', 'SELECT'),
  'unauthenticated clients cannot read maintenance history'
);

select * from finish();
rollback;
