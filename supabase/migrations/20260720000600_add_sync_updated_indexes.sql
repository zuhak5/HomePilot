create index if not exists areas_user_updated_idx
on public.areas (user_id, updated_at);

create index if not exists rooms_user_updated_idx
on public.rooms (user_id, updated_at);

create index if not exists assets_user_updated_idx
on public.assets (user_id, updated_at);

create index if not exists asset_photos_user_updated_idx
on public.asset_photos (user_id, updated_at);

create index if not exists asset_tags_user_updated_idx
on public.asset_tags (user_id, updated_at);

create index if not exists device_details_user_updated_idx
on public.device_details (user_id, updated_at);

create index if not exists pet_details_user_updated_idx
on public.pet_details (user_id, updated_at);

create index if not exists plant_details_user_updated_idx
on public.plant_details (user_id, updated_at);

create index if not exists safety_details_user_updated_idx
on public.safety_details (user_id, updated_at);

create index if not exists tags_user_updated_idx
on public.tags (user_id, updated_at);

create index if not exists maintenance_plans_user_updated_idx
on public.maintenance_plans (user_id, updated_at);

create index if not exists maintenance_plan_metadata_user_updated_idx
on public.maintenance_plan_metadata (user_id, updated_at);

create index if not exists maintenance_records_user_updated_idx
on public.maintenance_records (user_id, updated_at);

create index if not exists notification_inbox_user_updated_idx
on public.notification_inbox (user_id, updated_at);

create index if not exists user_settings_user_updated_idx
on public.user_settings (user_id, updated_at);

create index if not exists streaks_user_updated_idx
on public.streaks (user_id, updated_at);
