begin;

create schema if not exists homepilot_archive;

revoke all on schema homepilot_archive from public, anon, authenticated;

create table if not exists homepilot_archive.profiles_legacy_media_20260720 as
select
  user_id,
  display_name,
  avatar_object_path,
  now() as archived_at
from public.profiles
where display_name is not null
   or avatar_object_path is not null;

create table if not exists homepilot_archive.asset_photo_upload_metadata_20260720 as
select
  user_id,
  id,
  asset_id,
  object_path,
  content_sha256,
  mime_type,
  byte_size,
  now() as archived_at
from public.asset_photos
where content_sha256 is not null
   or mime_type is not null
   or byte_size is not null;

alter table public.profiles
  drop column if exists display_name,
  drop column if exists avatar_object_path;

alter table public.asset_photos
  drop column if exists content_sha256,
  drop column if exists mime_type,
  drop column if exists byte_size;

drop function if exists public.protect_homepilot_device_id();
drop function if exists homepilot_private.finalize_soft_delete();

notify pgrst, 'reload schema';

commit;
