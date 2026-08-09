-- Reconcile schema objects that already exist in the linked project so future
-- local resets and schema diffs describe production exactly.

create index if not exists asset_photos_user_id_asset_id_idx
on public.asset_photos using btree (user_id, asset_id);

create index if not exists asset_tags_user_id_tag_id_idx
on public.asset_tags using btree (user_id, tag_id);

create index if not exists assets_user_id_category_id_idx
on public.assets using btree (user_id, category_id);

create index if not exists assets_user_id_room_id_idx
on public.assets using btree (user_id, room_id);

create index if not exists maintenance_plans_user_id_asset_id_idx
on public.maintenance_plans using btree (user_id, asset_id);

create index if not exists maintenance_records_user_id_plan_id_idx
on public.maintenance_records using btree (user_id, plan_id);

create index if not exists notification_inbox_user_id_plan_id_idx
on public.notification_inbox using btree (user_id, plan_id);

create index if not exists rooms_user_id_area_id_idx
on public.rooms using btree (user_id, area_id);

grant select, insert, update, delete on table
  public.areas,
  public.asset_photos,
  public.asset_tags,
  public.assets,
  public.categories,
  public.device_details,
  public.maintenance_plans,
  public.maintenance_records,
  public.notification_inbox,
  public.pet_details,
  public.plant_details,
  public.profiles,
  public.rooms,
  public.safety_details,
  public.streaks,
  public.tags,
  public.user_settings
to service_role;
