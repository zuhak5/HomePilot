begin;

alter table public.profiles
  add column if not exists display_name text,
  add column if not exists avatar_object_path text;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.profiles'::regclass
      and conname = 'profiles_display_name_check'
  ) then
    alter table public.profiles
      add constraint profiles_display_name_check
      check (display_name is null or char_length(display_name) between 1 and 120);
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.profiles'::regclass
      and conname = 'profiles_avatar_owned_path'
  ) then
    alter table public.profiles
      add constraint profiles_avatar_owned_path
      check (
        avatar_object_path is null
        or avatar_object_path like (user_id::text || '/profile/%')
      );
  end if;
end $$;

update public.profiles as p
set
  display_name = a.display_name,
  avatar_object_path = a.avatar_object_path
from homepilot_archive.profiles_legacy_media_20260720 as a
where a.user_id = p.user_id;

alter table public.asset_photos
  add column if not exists content_sha256 text,
  add column if not exists mime_type text,
  add column if not exists byte_size bigint;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.asset_photos'::regclass
      and conname = 'asset_photos_mime_type_check'
  ) then
    alter table public.asset_photos
      add constraint asset_photos_mime_type_check
      check (
        mime_type is null
        or mime_type in ('image/jpeg', 'image/png', 'image/webp')
      );
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.asset_photos'::regclass
      and conname = 'asset_photos_byte_size_check'
  ) then
    alter table public.asset_photos
      add constraint asset_photos_byte_size_check
      check (byte_size is null or byte_size between 0 and 10485760);
  end if;
end $$;

update public.asset_photos as p
set
  content_sha256 = a.content_sha256,
  mime_type = a.mime_type,
  byte_size = a.byte_size
from homepilot_archive.asset_photo_upload_metadata_20260720 as a
where a.user_id = p.user_id
  and a.id = p.id;

create or replace function homepilot_private.finalize_soft_delete()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  execute format(
    'delete from %I.%I where ctid = $1',
    tg_table_schema,
    tg_table_name
  )
  using new.ctid;
  return null;
end;
$function$;

revoke all on function homepilot_private.finalize_soft_delete()
from public, anon, authenticated;

create or replace function public.protect_homepilot_device_id()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  if new.device_id is distinct from old.device_id then
    raise exception 'device_id cannot be changed'
      using errcode = '42501';
  end if;
  return new;
end;
$function$;

revoke all on function public.protect_homepilot_device_id() from public;

notify pgrst, 'reload schema';

commit;
