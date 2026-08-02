begin;

create extension if not exists pgtap with schema extensions;

select plan(5);

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
)
values (
  '00000000-0000-0000-0000-000000000000',
  '33333333-3333-3333-3333-333333333333',
  'authenticated',
  'authenticated',
  'metadata@example.invalid',
  '',
  now(),
  now(),
  now()
);

set local role authenticated;
set local request.jwt.claims =
  '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated"}';

insert into public.categories (
  user_id, id, name, health_group, icon_name, created_at, updated_at
)
values (
  '33333333-3333-3333-3333-333333333333',
  'filters',
  'Filters',
  'cleaning',
  'filter_alt',
  now(),
  now()
);

select is(
  (select revision::integer from public.categories where id = 'filters'),
  1,
  'new rows start at row version 1'
);

update public.categories
set name = 'Air filters'
where id = 'filters';

select is(
  (select revision::integer from public.categories where id = 'filters'),
  2,
  'updates increment the row version'
);

select is(
  (select user_id::text from public.categories where id = 'filters'),
  '33333333-3333-3333-3333-333333333333',
  'metadata trigger preserves ownership'
);

select hasnt_table('public', 'sync_activity', 'no separate sync activity table remains');
select has_trigger(
  'public',
  'categories',
  'set_row_metadata',
  'row metadata trigger exists on categories'
);

select * from finish();
rollback;
