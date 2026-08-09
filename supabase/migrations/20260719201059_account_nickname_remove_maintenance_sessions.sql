begin;

alter table public.profiles
  alter column display_name drop not null;

alter table public.profiles
  add column if not exists nickname text;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.profiles'::regclass
      and conname = 'profiles_nickname_length'
  ) then
    alter table public.profiles
      add constraint profiles_nickname_length
      check (
        nickname is null
        or (
          char_length(nickname) between 1 and 120
          and nickname = btrim(nickname)
        )
      );
  end if;
end
$$;

alter table public.profiles enable row level security;
revoke all on table public.profiles from anon, authenticated;
grant select, insert, update, delete on table public.profiles to authenticated;

drop policy if exists profiles_select_own on public.profiles;
drop policy if exists profiles_insert_own on public.profiles;
drop policy if exists profiles_update_own on public.profiles;
drop policy if exists profiles_delete_own on public.profiles;

create policy profiles_select_own
on public.profiles for select
to authenticated
using ((select auth.uid()) = user_id);

create policy profiles_insert_own
on public.profiles for insert
to authenticated
with check ((select auth.uid()) = user_id);

create policy profiles_update_own
on public.profiles for update
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

create policy profiles_delete_own
on public.profiles for delete
to authenticated
using ((select auth.uid()) = user_id);

do $$
declare
  app_table text;
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    foreach app_table in array array[
      'maintenance_session_tasks',
      'maintenance_sessions'
    ]
    loop
      if exists (
        select 1
        from pg_publication_tables
        where pubname = 'supabase_realtime'
          and schemaname = 'public'
          and tablename = app_table
      ) then
        execute format(
          'alter publication supabase_realtime drop table public.%I',
          app_table
        );
      end if;
    end loop;
  end if;
end
$$;

drop table if exists public.maintenance_session_tasks cascade;
drop table if exists public.maintenance_sessions cascade;

commit;
