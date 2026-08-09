begin;

-- Legacy media metadata is retained for rollback/audit purposes, but it is
-- still user data and must follow the Auth user lifecycle.
delete from homepilot_archive.profiles_legacy_media_20260720 archived
where not exists (
  select 1
  from auth.users users
  where users.id = archived.user_id
);

delete from homepilot_archive.asset_photo_upload_metadata_20260720 archived
where not exists (
  select 1
  from auth.users users
  where users.id = archived.user_id
);

alter table homepilot_archive.profiles_legacy_media_20260720
  add constraint profiles_legacy_media_user_id_fkey
  foreign key (user_id) references auth.users(id) on delete cascade;

alter table homepilot_archive.asset_photo_upload_metadata_20260720
  add constraint asset_photo_upload_metadata_user_id_fkey
  foreign key (user_id) references auth.users(id) on delete cascade;

-- A failed cleanup job may remain only while the owning Auth user exists.
delete from homepilot_private.account_deletion_cleanup_jobs cleanup
where not exists (
  select 1
  from auth.users users
  where users.id = cleanup.user_id
);

alter table homepilot_private.account_deletion_cleanup_jobs
  add constraint account_deletion_cleanup_jobs_user_id_fkey
  foreign key (user_id) references auth.users(id) on delete cascade;

create or replace function public.is_recent_homepilot_session(
  p_user_id uuid,
  p_session_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from auth.sessions sessions
    join auth.users users on users.id = sessions.user_id
    where sessions.id = p_session_id
      and sessions.user_id = p_user_id
      and sessions.created_at >= statement_timestamp() - interval '5 minutes'
      and (
        sessions.not_after is null
        or sessions.not_after > statement_timestamp()
      )
  );
$$;

revoke all on function public.is_recent_homepilot_session(uuid, uuid)
from public, anon, authenticated;
grant execute on function public.is_recent_homepilot_session(uuid, uuid)
to service_role;

create or replace function public.current_homepilot_session_is_active()
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  claimed_session_id text := auth.jwt() ->> 'session_id';
begin
  if auth.uid() is null
     or claimed_session_id is null
     or claimed_session_id !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
    return false;
  end if;

  return exists (
    select 1
    from auth.sessions sessions
    join auth.users users on users.id = sessions.user_id
    where sessions.id = claimed_session_id::uuid
      and sessions.user_id = auth.uid()
      and (
        sessions.not_after is null
        or sessions.not_after > statement_timestamp()
      )
  );
end;
$$;

revoke all on function public.current_homepilot_session_is_active()
from public, anon;
grant execute on function public.current_homepilot_session_is_active()
to authenticated;

drop policy if exists user_media_select_own on storage.objects;
drop policy if exists user_media_insert_own on storage.objects;
drop policy if exists user_media_update_own on storage.objects;
drop policy if exists user_media_delete_own on storage.objects;

create policy user_media_select_own
on storage.objects
for select
to authenticated
using (
  bucket_id = 'user-media'
  and (select auth.uid()) is not null
  and (storage.foldername(name))[1] = (select auth.uid())::text
  and public.current_homepilot_session_is_active()
);

create policy user_media_insert_own
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'user-media'
  and (select auth.uid()) is not null
  and (storage.foldername(name))[1] = (select auth.uid())::text
  and public.current_homepilot_session_is_active()
);

create policy user_media_update_own
on storage.objects
for update
to authenticated
using (
  bucket_id = 'user-media'
  and (select auth.uid()) is not null
  and (storage.foldername(name))[1] = (select auth.uid())::text
  and public.current_homepilot_session_is_active()
)
with check (
  bucket_id = 'user-media'
  and (select auth.uid()) is not null
  and (storage.foldername(name))[1] = (select auth.uid())::text
  and public.current_homepilot_session_is_active()
);

create policy user_media_delete_own
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'user-media'
  and (select auth.uid()) is not null
  and (storage.foldername(name))[1] = (select auth.uid())::text
  and public.current_homepilot_session_is_active()
);

notify pgrst, 'reload schema';

commit;
