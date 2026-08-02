begin;

-- Storage policies need a privileged lookup into auth.sessions, but that
-- helper must not be exposed as a public Data API RPC.
create schema if not exists homepilot_security;
revoke all on schema homepilot_security from public, anon;
grant usage on schema homepilot_security to authenticated;

alter function public.current_homepilot_session_is_active()
  set schema homepilot_security;

revoke all on function
  homepilot_security.current_homepilot_session_is_active()
from public, anon;
grant execute on function
  homepilot_security.current_homepilot_session_is_active()
to authenticated;

-- Cover every new Auth foreign key so cascading account deletion and
-- ownership lookups remain efficient as retained metadata grows.
create index profiles_legacy_media_user_id_idx
  on homepilot_archive.profiles_legacy_media_20260720 (user_id);

create index asset_photo_upload_metadata_user_id_idx
  on homepilot_archive.asset_photo_upload_metadata_20260720 (user_id);

create index account_deletion_cleanup_jobs_user_id_idx
  on homepilot_private.account_deletion_cleanup_jobs (user_id);

notify pgrst, 'reload schema';

commit;
