create table public.maintenance_plan_metadata (
  user_id uuid not null references auth.users(id) on delete cascade,
  plan_id text not null,
  task_type text check (
    task_type is null or char_length(task_type) between 1 and 80
  ),
  location_label text check (
    location_label is null or char_length(location_label) <= 200
  ),
  estimated_duration_minutes integer check (
    estimated_duration_minutes is null
    or estimated_duration_minutes between 1 and 1440
  ),
  required_materials_json text not null default '[]',
  dependency_plan_ids_json text not null default '[]',
  reminder_recommendation text check (
    reminder_recommendation is null or char_length(reminder_recommendation) <= 500
  ),
  sort_order integer,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  client_modified_at timestamptz not null default now(),
  origin_device_id text not null,
  revision bigint not null default 1 check (revision > 0),
  sync_seq bigint not null default nextval('public.homepilot_sync_seq'),
  server_updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  primary key (user_id, plan_id),
  foreign key (user_id, plan_id)
    references public.maintenance_plans(user_id, id)
    on delete cascade,
  constraint maintenance_plan_metadata_required_materials_json_check
    check (required_materials_json is json),
  constraint maintenance_plan_metadata_dependency_plan_ids_json_check
    check (dependency_plan_ids_json is json)
);

create table public.ai_review_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  asset_id text not null,
  request_id text not null,
  idempotency_key text not null,
  status text not null default 'pending'
    check (status in ('pending', 'success', 'error', 'applied')),
  prompt_version text not null,
  provider text,
  model text,
  context_hash text not null,
  context_metadata jsonb not null default '{}'::jsonb,
  usage_json jsonb not null default '{}'::jsonb,
  assumptions jsonb not null default '[]'::jsonb,
  missing_information jsonb not null default '[]'::jsonb,
  warnings jsonb not null default '[]'::jsonb,
  additional_context text check (
    additional_context is null or char_length(additional_context) <= 4000
  ),
  error_code text check (error_code is null or char_length(error_code) <= 120),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  completed_at timestamptz,
  foreign key (user_id, asset_id) references public.assets(user_id, id),
  unique (user_id, request_id),
  unique (user_id, idempotency_key)
);

create table public.ai_review_suggestions (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.ai_review_sessions(id)
    on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  suggestion_key text not null check (char_length(suggestion_key) between 1 and 160),
  target_type text not null check (
    target_type in (
      'item_field',
      'new_task',
      'task_update',
      'task_remove',
      'task_merge',
      'task_split',
      'profile_field'
    )
  ),
  operation text not null check (
    operation in ('add', 'edit', 'remove', 'merge', 'split', 'reschedule')
  ),
  target_id text,
  field_path text check (
    field_path is null or char_length(field_path) between 1 and 160
  ),
  current_value jsonb,
  proposed_value jsonb not null,
  editable_value jsonb,
  reason text not null check (char_length(reason) between 1 and 2000),
  confidence numeric(4, 3) check (confidence is null or confidence between 0 and 1),
  context_used jsonb not null default '[]'::jsonb,
  assumptions jsonb not null default '[]'::jsonb,
  missing_information jsonb not null default '[]'::jsonb,
  status text not null default 'pending'
    check (status in ('pending', 'accepted', 'rejected', 'applied', 'failed')),
  decided_at timestamptz,
  applied_at timestamptz,
  error_code text check (error_code is null or char_length(error_code) <= 120),
  created_at timestamptz not null default now(),
  unique (session_id, suggestion_key)
);

create table public.ai_review_apply_attempts (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.ai_review_sessions(id)
    on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  idempotency_key text not null,
  status text not null check (status in ('started', 'success', 'error')),
  request_json jsonb not null default '{}'::jsonb,
  result_json jsonb not null default '{}'::jsonb,
  error_code text check (error_code is null or char_length(error_code) <= 120),
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  unique (user_id, idempotency_key)
);

alter table public.maintenance_plan_metadata enable row level security;
alter table public.ai_review_sessions enable row level security;
alter table public.ai_review_suggestions enable row level security;
alter table public.ai_review_apply_attempts enable row level security;

revoke all on public.maintenance_plan_metadata from anon, authenticated;
revoke all on public.ai_review_sessions from anon, authenticated;
revoke all on public.ai_review_suggestions from anon, authenticated;
revoke all on public.ai_review_apply_attempts from anon, authenticated;

grant select, insert, update on public.maintenance_plan_metadata to authenticated;
grant select on public.ai_review_sessions to authenticated;
grant select on public.ai_review_suggestions to authenticated;
grant select on public.ai_review_apply_attempts to authenticated;

create policy maintenance_plan_metadata_select_own
on public.maintenance_plan_metadata
for select
to authenticated
using ((select auth.uid()) = user_id);

create policy maintenance_plan_metadata_insert_own
on public.maintenance_plan_metadata
for insert
to authenticated
with check ((select auth.uid()) = user_id);

create policy maintenance_plan_metadata_update_own
on public.maintenance_plan_metadata
for update
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

create policy ai_review_sessions_select_own
on public.ai_review_sessions
for select
to authenticated
using ((select auth.uid()) = user_id);

create policy ai_review_suggestions_select_own
on public.ai_review_suggestions
for select
to authenticated
using ((select auth.uid()) = user_id);

create policy ai_review_apply_attempts_select_own
on public.ai_review_apply_attempts
for select
to authenticated
using ((select auth.uid()) = user_id);

grant select, insert, update, delete on public.maintenance_plan_metadata to service_role;
grant select, insert, update, delete on public.ai_review_sessions to service_role;
grant select, insert, update, delete on public.ai_review_suggestions to service_role;
grant select, insert, update, delete on public.ai_review_apply_attempts to service_role;

create trigger set_sync_metadata
before insert or update on public.maintenance_plan_metadata
for each row execute function public.set_homepilot_sync_metadata();

create trigger enqueue_ai_context_dirty_maintenance_plan_metadata
after insert or update or delete on public.maintenance_plan_metadata
for each row execute function homepilot_private.enqueue_ai_context_dirty();

do $$
begin
  if exists (
    select 1
    from pg_proc procedure
    join pg_namespace namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'homepilot_private'
      and procedure.proname = 'bump_sync_activity'
  ) then
    create trigger bump_sync_activity
    after insert or update or delete on public.maintenance_plan_metadata
    for each row execute function homepilot_private.bump_sync_activity();
  end if;
exception
  when duplicate_object then null;
end
$$;

create index maintenance_plan_metadata_sync_idx
on public.maintenance_plan_metadata (user_id, sync_seq);

create index maintenance_plan_metadata_plan_idx
on public.maintenance_plan_metadata (user_id, plan_id)
where deleted_at is null;

create index ai_review_sessions_user_asset_created_idx
on public.ai_review_sessions (user_id, asset_id, created_at desc);

create index ai_review_sessions_user_status_idx
on public.ai_review_sessions (user_id, status, created_at desc);

create index ai_review_suggestions_session_idx
on public.ai_review_suggestions (session_id, created_at);

create index ai_review_suggestions_user_pending_idx
on public.ai_review_suggestions (user_id, session_id, created_at)
where status = 'pending';

create index ai_review_suggestions_target_idx
on public.ai_review_suggestions (user_id, target_type, target_id);

create index ai_review_apply_attempts_session_idx
on public.ai_review_apply_attempts (session_id, created_at desc);

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

do $$
begin
  alter publication supabase_realtime add table public.maintenance_plan_metadata;
exception
  when duplicate_object then null;
  when undefined_object then null;
end
$$;

select pg_notify('pgrst', 'reload schema');
