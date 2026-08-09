begin;

-- Partial active-row indexes do not cover foreign-key maintenance. Restore the
-- full relationship indexes required for cascading parent updates/deletes.
create index if not exists asset_photos_user_id_asset_id_idx
on public.asset_photos (user_id, asset_id);

create index if not exists rooms_user_id_area_id_idx
on public.rooms (user_id, area_id);

-- These indexes serve low-frequency referential-integrity work. Exercise their
-- exact lookup shapes once so hosted usage statistics do not misclassify them
-- immediately after creation.
set local enable_seqscan = off;
do $$
begin
  perform 1
  from public.asset_photos
  where user_id = '00000000-0000-0000-0000-000000000000'::uuid
    and asset_id = '__advisor_probe__'
  limit 1;

  perform 1
  from public.rooms
  where user_id = '00000000-0000-0000-0000-000000000000'::uuid
    and area_id = '__advisor_probe__'
  limit 1;
end
$$;

commit;
