begin;

drop trigger if exists enqueue_ai_context_dirty_assets on public.assets;
drop trigger if exists enqueue_ai_context_dirty_profiles on public.profiles;
drop trigger if exists enqueue_ai_context_dirty_areas on public.areas;
drop trigger if exists enqueue_ai_context_dirty_rooms on public.rooms;
drop trigger if exists enqueue_ai_context_dirty_asset_photos on public.asset_photos;
drop trigger if exists enqueue_ai_context_dirty_device_details on public.device_details;
drop trigger if exists enqueue_ai_context_dirty_pet_details on public.pet_details;
drop trigger if exists enqueue_ai_context_dirty_plant_details on public.plant_details;
drop trigger if exists enqueue_ai_context_dirty_safety_details on public.safety_details;
drop trigger if exists enqueue_ai_context_dirty_tags on public.tags;
drop trigger if exists enqueue_ai_context_dirty_asset_tags on public.asset_tags;
drop trigger if exists enqueue_ai_context_dirty_maintenance_plans on public.maintenance_plans;
drop trigger if exists enqueue_ai_context_dirty_maintenance_records on public.maintenance_records;
drop trigger if exists enqueue_ai_context_dirty_maintenance_plan_metadata on public.maintenance_plan_metadata;
drop trigger if exists enqueue_ai_context_dirty_notification_inbox on public.notification_inbox;
drop trigger if exists enqueue_ai_context_dirty_device_notifications on public.device_notifications;
drop trigger if exists enqueue_ai_context_dirty_user_settings on public.user_settings;
drop trigger if exists enqueue_ai_context_dirty_device_settings on public.device_settings;
drop trigger if exists enqueue_ai_context_dirty_streaks on public.streaks;
drop trigger if exists enqueue_ai_context_dirty_ai_review_sessions on public.ai_review_sessions;
drop trigger if exists enqueue_ai_context_dirty_ai_review_suggestions on public.ai_review_suggestions;
drop trigger if exists enqueue_ai_context_dirty_ai_review_apply_attempts on public.ai_review_apply_attempts;

drop function if exists public.match_ai_context_chunks(extensions.halfvec, integer, double precision);
drop function if exists homepilot_private.enqueue_ai_context_dirty();
drop function if exists public.ai_user_provider_key_status(uuid);
drop function if exists public.get_ai_user_provider_key_ref(uuid, text);
drop function if exists public.upsert_ai_user_provider_key_ref(uuid, text, text, text, text);
drop function if exists public.delete_ai_user_provider_key_ref(uuid, text);
drop function if exists homepilot_private.record_ai_review_decisions(uuid, uuid, text, text, jsonb);
drop function if exists public.upsert_ai_provider_runtime_status(text, text, text, boolean, integer, timestamptz, text, integer, timestamptz);
drop function if exists public.record_ai_provider_event(text, text, text, text, text, integer, boolean, text);
drop function if exists public.claim_ai_request_idempotency(uuid, text, text, text, timestamptz);
drop function if exists public.complete_ai_request_idempotency(uuid, text, text, text, text);

delete from public.sync_tombstones
where entity in (
  'ai_provider_setting',
  'device_ai_provider_status',
  'ai_usage_log'
);

delete from public.user_settings
where key = 'ai_routing_mode';

do $$
declare
  preference_row record;
  cleaned jsonb;
begin
  for preference_row in
    select user_id, value
    from public.user_settings
    where key = 'notification_preferences'
  loop
    begin
      cleaned := preference_row.value::jsonb
        - 'aiNotificationTextEnabled'
        - 'aiNotificationStyle';

      update public.user_settings
      set
        value = cleaned::text,
        updated_at = now(),
        client_modified_at = now(),
        server_updated_at = now()
      where user_id = preference_row.user_id
        and key = 'notification_preferences';
    exception
      when others then
        null;
    end;
  end loop;
end $$;

alter table public.user_settings
  drop constraint if exists user_settings_key_check;

alter table public.user_settings
  add constraint user_settings_key_check
  check (key in (
    'theme',
    'app_language',
    'theme_time_of_day_enabled',
    'notifications_enabled',
    'notification_preferences',
    'onboarding_completed',
    'home_location'
  ));

create or replace function public.delete_homepilot_record(
  p_entity text,
  p_record_key text,
  p_device_id text,
  p_client_modified_at timestamptz,
  p_origin_device_id text,
  p_expected_revision bigint
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  request_user uuid := (select auth.uid());
  table_name text;
  key_predicate text;
  scope_predicate text;
  device_scoped boolean := false;
  deleted_row jsonb;
  current_row jsonb;
begin
  if request_user is null then
    raise exception 'Authentication is required' using errcode = '42501';
  end if;
  if not exists (
    select 1
    from public.sync_devices
    where user_id = request_user
      and device_id = p_origin_device_id
      and protocol_version >= 2
      and revoked_at is null
  ) then
    raise exception 'This HomePilot client must be upgraded before syncing'
      using errcode = '0A000';
  end if;

  select mapped.table_name, mapped.key_predicate, mapped.device_scoped
  into table_name, key_predicate, device_scoped
  from (values
    ('profile', 'profiles', 'true', false),
    ('area', 'areas', 't.id::text = $2', false),
    ('room', 'rooms', 't.id::text = $2', false),
    ('asset', 'assets', 't.id::text = $2', false),
    ('device_detail', 'device_details', 't.asset_id::text = $2', false),
    ('pet_detail', 'pet_details', 't.asset_id::text = $2', false),
    ('plant_detail', 'plant_details', 't.asset_id::text = $2', false),
    ('safety_detail', 'safety_details', 't.asset_id::text = $2', false),
    ('tag', 'tags', 't.id::text = $2', false),
    ('asset_tag', 'asset_tags',
      't.asset_id::text = split_part($2, ''|'', 1) and '
      't.tag_id::text = split_part($2, ''|'', 2)', false),
    ('asset_photo', 'asset_photos', 't.id::text = $2', false),
    ('maintenance_plan', 'maintenance_plans', 't.id::text = $2', false),
    ('maintenance_plan_metadata', 'maintenance_plan_metadata', 't.plan_id::text = $2', false),
    ('maintenance_record', 'maintenance_records', 't.id::text = $2', false),
    ('device_notification', 'device_notifications', 't.id::text = $2', true),
    ('notification_inbox', 'notification_inbox', 't.id::text = $2', false),
    ('user_setting', 'user_settings', 't.key::text = $2', false),
    ('device_setting', 'device_settings', 't.key::text = $2', true),
    ('streak', 'streaks', 't.id::text = $2', false)
  ) as mapped(entity, table_name, key_predicate, device_scoped)
  where mapped.entity = p_entity;

  if table_name is null then
    raise exception 'Unsupported synchronization entity'
      using errcode = '22023';
  end if;
  if device_scoped and coalesce(p_device_id, '') = '' then
    raise exception 'A device identifier is required'
      using errcode = '22023';
  end if;
  scope_predicate := case
    when device_scoped then 't.device_id = $3'
    else 'true'
  end;

  perform set_config(
    'homepilot.delete_modified_at',
    p_client_modified_at::text,
    true
  );
  perform set_config(
    'homepilot.delete_origin_device_id',
    p_origin_device_id,
    true
  );

  execute format(
    'delete from public.%I t '
    'where t.user_id = $1 and %s and %s '
    'and t.revision = $4 returning to_jsonb(t)',
    table_name,
    key_predicate,
    scope_predicate
  )
  into deleted_row
  using request_user, p_record_key, p_device_id, p_expected_revision;

  if deleted_row is not null then
    return jsonb_build_object('applied', true, 'deleted', deleted_row);
  end if;

  execute format(
    'select to_jsonb(t) from public.%I t '
    'where t.user_id = $1 and %s and %s',
    table_name,
    key_predicate,
    scope_predicate
  )
  into current_row
  using request_user, p_record_key, p_device_id;

  return jsonb_build_object('applied', false, 'current', current_row);
end;
$$;

revoke all on function public.delete_homepilot_record(
  text, text, text, timestamptz, text, bigint
) from public, anon;
grant execute on function public.delete_homepilot_record(
  text, text, text, timestamptz, text, bigint
) to authenticated;

drop table if exists public.ai_review_apply_attempts cascade;
drop table if exists public.ai_review_suggestions cascade;
drop table if exists public.ai_review_sessions cascade;
drop table if exists public.ai_context_dirty_queue cascade;
drop table if exists public.ai_context_chunks cascade;
drop table if exists public.ai_context_preferences cascade;
drop table if exists public.ai_response_cache cascade;
drop table if exists public.ai_invocations cascade;
drop table if exists public.ai_provider_health_cache cascade;
drop table if exists public.ai_usage_logs cascade;
drop table if exists public.device_ai_provider_status cascade;
drop table if exists public.ai_provider_settings cascade;
drop table if exists homepilot_private.ai_request_idempotency cascade;
drop table if exists homepilot_private.ai_provider_events cascade;
drop table if exists homepilot_private.ai_provider_runtime_status cascade;
drop table if exists homepilot_private.ai_user_provider_key_refs cascade;

do $$
begin
  drop extension if exists vector;
exception
  when dependent_objects_still_exist then
    null;
end $$;

commit;
