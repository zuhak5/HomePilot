alter table public.sync_devices
  add column device_label text,
  add column platform text,
  add column app_version text;

alter table public.sync_devices
  add constraint sync_devices_device_label_length
    check (device_label is null or char_length(device_label) <= 120),
  add constraint sync_devices_platform_length
    check (platform is null or char_length(platform) <= 40),
  add constraint sync_devices_app_version_length
    check (app_version is null or char_length(app_version) <= 40);

alter table public.profiles
  add constraint profiles_avatar_owned_path
  check (
    avatar_object_path is null
    or avatar_object_path like user_id::text || '/profile/%'
  ) not valid;

alter table public.asset_photos
  add constraint asset_photos_owned_path
  check (object_path like user_id::text || '/assets/%') not valid;

do $$
begin
  if not exists (
    select 1
    from public.profiles
    where avatar_object_path is not null
      and avatar_object_path not like user_id::text || '/profile/%'
  ) then
    alter table public.profiles
      validate constraint profiles_avatar_owned_path;
  end if;

  if not exists (
    select 1
    from public.asset_photos
    where object_path not like user_id::text || '/assets/%'
  ) then
    alter table public.asset_photos
      validate constraint asset_photos_owned_path;
  end if;
end
$$;

create table homepilot_private.account_deletion_cleanup_jobs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  object_paths text[] not null default '{}',
  attempts integer not null default 0 check (attempts >= 0),
  last_error text,
  created_at timestamptz not null default clock_timestamp(),
  completed_at timestamptz
);

revoke all on homepilot_private.account_deletion_cleanup_jobs
from public, anon, authenticated;
grant usage on schema homepilot_private to service_role;
grant select, insert, update, delete
on homepilot_private.account_deletion_cleanup_jobs
to service_role;

create function public.begin_homepilot_account_cleanup(
  p_user_id uuid,
  p_object_paths text[]
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  job_id uuid;
begin
  insert into homepilot_private.account_deletion_cleanup_jobs (
    user_id,
    object_paths
  )
  values (
    p_user_id,
    coalesce(p_object_paths, '{}')
  )
  returning id into job_id;
  return job_id;
end;
$$;

create function public.complete_homepilot_account_cleanup(
  p_job_id uuid,
  p_error text default null
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if p_error is null then
    delete from homepilot_private.account_deletion_cleanup_jobs
    where id = p_job_id;
  else
    update homepilot_private.account_deletion_cleanup_jobs
    set
      attempts = attempts + 1,
      last_error = left(p_error, 4000)
    where id = p_job_id;
  end if;
end;
$$;

revoke all on function public.begin_homepilot_account_cleanup(uuid, text[])
from public, anon, authenticated;
revoke all on function public.complete_homepilot_account_cleanup(uuid, text)
from public, anon, authenticated;
grant execute on function public.begin_homepilot_account_cleanup(uuid, text[])
to service_role;
grant execute on function public.complete_homepilot_account_cleanup(uuid, text)
to service_role;
