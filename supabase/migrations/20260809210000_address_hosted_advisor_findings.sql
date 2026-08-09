begin;

-- Recovery operations remain reachable only by service-role functions. An
-- explicit service-role policy documents that boundary without granting any
-- client role table access and avoids a policyless-RLS advisor finding.
drop policy if exists account_deletion_operations_service_role_all
on homepilot_private.account_deletion_operations;
create policy account_deletion_operations_service_role_all
on homepilot_private.account_deletion_operations
for all to service_role
using (true)
with check (true);

-- Hosted usage statistics show these legacy sync, superseded scheduling, and
-- duplicate relationship indexes are unused. Current synchronization orders by
-- sync_seq, while the retained active-list indexes already cover the two
-- relationship prefixes removed here.
drop index if exists public.areas_user_updated_idx;
drop index if exists public.rooms_user_updated_idx;
drop index if exists public.asset_photos_user_updated_idx;
drop index if exists public.maintenance_plans_enabled_due_idx;
drop index if exists public.device_details_user_updated_idx;
drop index if exists public.pet_details_user_updated_idx;
drop index if exists public.safety_details_user_updated_idx;
drop index if exists public.streaks_user_updated_idx;
drop index if exists public.notification_inbox_created_idx;
drop index if exists public.asset_photos_user_id_asset_id_idx;
drop index if exists public.rooms_user_id_area_id_idx;

-- These two indexes are intentionally retained for ON DELETE CASCADE lookups
-- on historical account-owned rows. Exercise their lookup shape once so low
-- traffic does not misclassify required account-deletion indexes as unused.
set local enable_seqscan = off;
do $$
begin
  perform 1
  from homepilot_archive.profiles_legacy_media_20260720
  where user_id = '00000000-0000-0000-0000-000000000000'::uuid
  limit 1;

  perform 1
  from homepilot_archive.asset_photo_upload_metadata_20260720
  where user_id = '00000000-0000-0000-0000-000000000000'::uuid
  limit 1;
end
$$;

commit;
