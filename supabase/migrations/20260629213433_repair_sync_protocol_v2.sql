create table public.sync_devices (
  user_id uuid not null references auth.users(id) on delete cascade,
  device_id text not null check (char_length(device_id) between 1 and 200),
  protocol_version integer not null check (protocol_version >= 2),
  last_seen_at timestamptz not null default now(),
  last_ack_sync_seq bigint not null default 0 check (last_ack_sync_seq >= 0),
  revoked_at timestamptz,
  primary key (user_id, device_id)
);

create table public.sync_tombstones (
  user_id uuid not null references auth.users(id) on delete cascade,
  entity text not null,
  record_key text not null,
  device_id text not null default '',
  client_modified_at timestamptz not null,
  origin_device_id text not null,
  sync_seq bigint not null default nextval('public.homepilot_sync_seq'),
  server_updated_at timestamptz not null default clock_timestamp(),
  primary key (user_id, entity, device_id, record_key)
);

alter table public.sync_devices enable row level security;
alter table public.sync_tombstones enable row level security;

create policy "Users select own sync devices"
on public.sync_devices for select
to authenticated
using ((select auth.uid()) = user_id);

create policy "Users insert own sync devices"
on public.sync_devices for insert
to authenticated
with check ((select auth.uid()) = user_id);

create policy "Users update own sync devices"
on public.sync_devices for update
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

create policy "Users select own sync tombstones"
on public.sync_tombstones for select
to authenticated
using ((select auth.uid()) = user_id);

revoke all on public.sync_devices from anon, authenticated;
revoke all on public.sync_tombstones from anon, authenticated;
grant select, insert, update on public.sync_devices to authenticated;
grant select on public.sync_tombstones to authenticated;

create function public.protect_homepilot_sync_device()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.user_id := old.user_id;
  new.device_id := old.device_id;
  new.revoked_at := old.revoked_at;
  return new;
end;
$$;

create trigger protect_sync_device
before update on public.sync_devices
for each row execute function public.protect_homepilot_sync_device();

revoke all on function public.protect_homepilot_sync_device() from public;

create index sync_devices_user_seen_idx
on public.sync_devices (user_id, last_seen_at desc);

create index sync_tombstones_cursor_idx
on public.sync_tombstones (user_id, entity, device_id, sync_seq);

create or replace function public.set_homepilot_sync_metadata()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  request_user uuid := (select auth.uid());
begin
  if new.client_modified_at > clock_timestamp() + interval '5 minutes' then
    raise exception 'client_modified_at is too far in the future'
      using errcode = '22007';
  end if;

  if request_user is not null and not exists (
    select 1
    from public.sync_devices
    where user_id = request_user
      and device_id = new.origin_device_id
      and protocol_version >= 2
      and revoked_at is null
  ) then
    raise exception 'This HomePilot client must be upgraded before syncing'
      using errcode = '0A000';
  end if;

  if tg_op = 'UPDATE' then
    new.user_id := old.user_id;
    if new.client_modified_at is not distinct from old.client_modified_at then
      new.client_modified_at := clock_timestamp();
      new.origin_device_id := 'server';
    end if;
    new.revision := old.revision + 1;
  else
    new.revision := 1;
  end if;

  new.sync_seq := nextval('public.homepilot_sync_seq');
  new.server_updated_at := clock_timestamp();
  return new;
end;
$$;

revoke all on function public.set_homepilot_sync_metadata() from public;

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'profiles', 'areas', 'rooms', 'assets', 'device_details', 'pet_details',
    'plant_details', 'safety_details', 'tags', 'asset_tags', 'asset_photos',
    'maintenance_plans', 'maintenance_records', 'device_notifications',
    'notification_inbox', 'ai_provider_settings',
    'device_ai_provider_status', 'ai_usage_logs', 'user_settings',
    'device_settings', 'streaks'
  ]
  loop
    execute format(
      'alter table public.%I alter column origin_device_id set default %L',
      table_name,
      'server'
    );
    execute format('grant delete on public.%I to authenticated', table_name);
    execute format(
      'create policy %I on public.%I for delete to authenticated '
      'using ((select auth.uid()) = user_id)',
      'Users delete own ' || table_name,
      table_name
    );
  end loop;
end
$$;

create schema if not exists homepilot_private;
revoke all on schema homepilot_private from public, anon, authenticated;

create function homepilot_private.capture_sync_tombstone()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  old_row jsonb := to_jsonb(old);
  tombstone_entity text := tg_argv[0];
  key_one text := old_row ->> tg_argv[1];
  key_two text := case when tg_nargs > 3 then old_row ->> tg_argv[2] end;
  scoped boolean := tg_argv[tg_nargs - 1] = 'device';
  tombstone_key text;
  tombstone_device text;
  modified_at timestamptz;
  origin_id text;
begin
  tombstone_key := case
    when tombstone_entity = 'profile' then 'profile'
    when key_two is null then key_one
    else key_one || '|' || key_two
  end;
  tombstone_device := case
    when scoped then coalesce(old_row ->> 'device_id', '')
    else ''
  end;
  modified_at := coalesce(
    nullif(current_setting('homepilot.delete_modified_at', true), '')::timestamptz,
    old.deleted_at,
    clock_timestamp()
  );
  origin_id := coalesce(
    nullif(current_setting('homepilot.delete_origin_device_id', true), ''),
    old.origin_device_id,
    'server'
  );

  insert into public.sync_tombstones (
    user_id,
    entity,
    record_key,
    device_id,
    client_modified_at,
    origin_device_id
  )
  values (
    old.user_id,
    tombstone_entity,
    tombstone_key,
    tombstone_device,
    modified_at,
    origin_id
  )
  on conflict (user_id, entity, device_id, record_key) do update
  set
    client_modified_at = excluded.client_modified_at,
    origin_device_id = excluded.origin_device_id,
    sync_seq = nextval('public.homepilot_sync_seq'),
    server_updated_at = clock_timestamp()
  where
    (excluded.client_modified_at, excluded.origin_device_id) >
    (
      public.sync_tombstones.client_modified_at,
      public.sync_tombstones.origin_device_id
    );

  return old;
end;
$$;

create function homepilot_private.finalize_soft_delete()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  execute format(
    'delete from %I.%I where ctid = $1',
    tg_table_schema,
    tg_table_name
  )
  using new.ctid;
  return null;
end;
$$;

revoke all on function homepilot_private.capture_sync_tombstone()
from public, anon, authenticated;
revoke all on function homepilot_private.finalize_soft_delete()
from public, anon, authenticated;

do $$
declare
  definition record;
  trigger_arguments text;
begin
  for definition in
    select *
    from (values
      ('profiles', 'profile', 'user_id', null, 'shared'),
      ('areas', 'area', 'id', null, 'shared'),
      ('rooms', 'room', 'id', null, 'shared'),
      ('assets', 'asset', 'id', null, 'shared'),
      ('device_details', 'device_detail', 'asset_id', null, 'shared'),
      ('pet_details', 'pet_detail', 'asset_id', null, 'shared'),
      ('plant_details', 'plant_detail', 'asset_id', null, 'shared'),
      ('safety_details', 'safety_detail', 'asset_id', null, 'shared'),
      ('tags', 'tag', 'id', null, 'shared'),
      ('asset_tags', 'asset_tag', 'asset_id', 'tag_id', 'shared'),
      ('asset_photos', 'asset_photo', 'id', null, 'shared'),
      ('maintenance_plans', 'maintenance_plan', 'id', null, 'shared'),
      ('maintenance_records', 'maintenance_record', 'id', null, 'shared'),
      ('device_notifications', 'device_notification', 'id', null, 'device'),
      ('notification_inbox', 'notification_inbox', 'id', null, 'shared'),
      ('ai_provider_settings', 'ai_provider_setting', 'provider', null, 'shared'),
      ('device_ai_provider_status', 'device_ai_provider_status', 'provider', null, 'device'),
      ('ai_usage_logs', 'ai_usage_log', 'id', null, 'shared'),
      ('user_settings', 'user_setting', 'key', null, 'shared'),
      ('device_settings', 'device_setting', 'key', null, 'device'),
      ('streaks', 'streak', 'id', null, 'shared')
    ) as rows(table_name, entity, key_one, key_two, scope)
  loop
    trigger_arguments := format(
      '%L, %L%s, %L',
      definition.entity,
      definition.key_one,
      case
        when definition.key_two is null then ''
        else format(', %L', definition.key_two)
      end,
      definition.scope
    );
    execute format(
      'create trigger capture_sync_tombstone after delete on public.%I '
      'for each row execute function '
      'homepilot_private.capture_sync_tombstone(%s)',
      definition.table_name,
      trigger_arguments
    );
    execute format(
      'create trigger finalize_soft_delete '
      'after update of deleted_at on public.%I '
      'for each row when (old.deleted_at is null and new.deleted_at is not null) '
      'execute function homepilot_private.finalize_soft_delete()',
      definition.table_name
    );
  end loop;
end
$$;

create function public.delete_homepilot_record(
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
    ('maintenance_record', 'maintenance_records', 't.id::text = $2', false),
    ('device_notification', 'device_notifications', 't.id::text = $2', true),
    ('notification_inbox', 'notification_inbox', 't.id::text = $2', false),
    ('ai_provider_setting', 'ai_provider_settings', 't.provider::text = $2', false),
    ('device_ai_provider_status', 'device_ai_provider_status',
      't.provider::text = $2', true),
    ('ai_usage_log', 'ai_usage_logs', 't.id::text = $2', false),
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

-- Convert only existing logical tombstones. Active rows are never removed.
do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'device_notifications', 'notification_inbox', 'maintenance_records',
    'device_details', 'pet_details', 'plant_details', 'safety_details',
    'asset_tags', 'asset_photos', 'maintenance_plans', 'assets', 'tags',
    'rooms', 'areas', 'device_ai_provider_status', 'ai_usage_logs',
    'ai_provider_settings', 'device_settings', 'user_settings', 'streaks',
    'profiles'
  ]
  loop
    execute format(
      'delete from public.%I where deleted_at is not null',
      table_name
    );
  end loop;
end
$$;

alter table public.sync_tombstones replica identity full;

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'sync_tombstones'
  ) then
    alter publication supabase_realtime
      add table public.sync_tombstones;
  end if;
end
$$;
