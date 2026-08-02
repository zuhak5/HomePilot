create table public.maintenance_sessions (
  user_id uuid not null references auth.users(id) on delete cascade,
  id text not null,
  title text not null,
  session_date timestamptz not null,
  notes text,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  archived_at timestamptz,
  client_modified_at timestamptz not null default now(),
  origin_device_id text not null default 'server',
  revision bigint not null default 1 check (revision > 0),
  sync_seq bigint not null default nextval('public.homepilot_sync_seq'),
  server_updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  primary key (user_id, id)
);

create table public.maintenance_session_tasks (
  user_id uuid not null references auth.users(id) on delete cascade,
  session_id text not null,
  plan_id text not null,
  sort_order integer not null default 0,
  completed_at timestamptz,
  record_id text,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  client_modified_at timestamptz not null default now(),
  origin_device_id text not null default 'server',
  revision bigint not null default 1 check (revision > 0),
  sync_seq bigint not null default nextval('public.homepilot_sync_seq'),
  server_updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  primary key (user_id, session_id, plan_id),
  foreign key (user_id, session_id)
    references public.maintenance_sessions(user_id, id),
  foreign key (user_id, plan_id)
    references public.maintenance_plans(user_id, id),
  foreign key (user_id, record_id)
    references public.maintenance_records(user_id, id)
);

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'maintenance_sessions',
    'maintenance_session_tasks'
  ]
  loop
    execute format('alter table public.%I enable row level security', table_name);
    execute format('revoke all on table public.%I from anon, authenticated', table_name);
    execute format(
      'grant select, insert, update, delete on table public.%I to authenticated',
      table_name
    );
    execute format(
      'create policy %I on public.%I for select to authenticated '
      'using ((select auth.uid()) is not null and (select auth.uid()) = user_id)',
      table_name || '_select_own',
      table_name
    );
    execute format(
      'create policy %I on public.%I for insert to authenticated '
      'with check ((select auth.uid()) is not null and (select auth.uid()) = user_id)',
      table_name || '_insert_own',
      table_name
    );
    execute format(
      'create policy %I on public.%I for update to authenticated '
      'using ((select auth.uid()) is not null and (select auth.uid()) = user_id) '
      'with check ((select auth.uid()) is not null and (select auth.uid()) = user_id)',
      table_name || '_update_own',
      table_name
    );
    execute format(
      'create policy %I on public.%I for delete to authenticated '
      'using ((select auth.uid()) is not null and (select auth.uid()) = user_id)',
      table_name || '_delete_own',
      table_name
    );
    execute format(
      'create trigger set_sync_metadata before insert or update on public.%I '
      'for each row execute function public.set_homepilot_sync_metadata()',
      table_name
    );
    execute format(
      'create index %I on public.%I (user_id, sync_seq)',
      table_name || '_user_sync_seq_idx',
      table_name
    );
  end loop;
end
$$;

create index maintenance_sessions_date_idx
on public.maintenance_sessions (user_id, session_date)
where deleted_at is null and archived_at is null;

create index maintenance_session_tasks_session_idx
on public.maintenance_session_tasks (user_id, session_id, sort_order)
where deleted_at is null;

create index maintenance_session_tasks_plan_idx
on public.maintenance_session_tasks (user_id, plan_id)
where deleted_at is null;

create index maintenance_session_tasks_record_idx
on public.maintenance_session_tasks (user_id, record_id)
where deleted_at is null and record_id is not null;

create trigger capture_sync_tombstone
after delete on public.maintenance_sessions
for each row execute function
homepilot_private.capture_sync_tombstone(
  'maintenance_session',
  'id',
  'shared'
);

create trigger finalize_soft_delete
after update of deleted_at on public.maintenance_sessions
for each row when (old.deleted_at is null and new.deleted_at is not null)
execute function homepilot_private.finalize_soft_delete();

create trigger capture_sync_tombstone
after delete on public.maintenance_session_tasks
for each row execute function
homepilot_private.capture_sync_tombstone(
  'maintenance_session_task',
  'session_id',
  'plan_id',
  'shared'
);

create trigger finalize_soft_delete
after update of deleted_at on public.maintenance_session_tasks
for each row when (old.deleted_at is null and new.deleted_at is not null)
execute function homepilot_private.finalize_soft_delete();

alter table public.maintenance_sessions replica identity full;
alter table public.maintenance_session_tasks replica identity full;

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'maintenance_sessions',
    'maintenance_session_tasks'
  ]
  loop
    if not exists (
      select 1
      from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = table_name
    ) then
      execute format(
        'alter publication supabase_realtime add table public.%I',
        table_name
      );
    end if;
  end loop;
end
$$;

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
    ('maintenance_session', 'maintenance_sessions', 't.id::text = $2', false),
    ('maintenance_session_task', 'maintenance_session_tasks',
      't.session_id::text = split_part($2, ''|'', 1) and '
      't.plan_id::text = split_part($2, ''|'', 2)', false),
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
