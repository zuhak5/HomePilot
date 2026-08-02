create table public.user_settings (
  user_id uuid not null references auth.users(id) on delete cascade,
  key text not null check (key in (
    'theme', 'app_language', 'theme_time_of_day_enabled', 'ai_routing_mode',
    'notifications_enabled', 'notification_preferences',
    'onboarding_completed', 'home_location'
  )),
  value text not null check (octet_length(value) <= 1048576),
  updated_at timestamptz not null,
  client_modified_at timestamptz not null default now(),
  origin_device_id text not null,
  revision bigint not null default 1 check (revision > 0),
  sync_seq bigint not null default nextval('public.homepilot_sync_seq'),
  server_updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  primary key (user_id, key)
);

create table public.notification_inbox (
  user_id uuid not null references auth.users(id) on delete cascade,
  id text not null,
  title text not null check (char_length(title) between 1 and 500),
  body text not null check (char_length(body) <= 20000),
  kind text not null check (char_length(kind) between 1 and 80),
  route text check (route is null or char_length(route) <= 1000),
  plan_id text,
  dedupe_key text not null check (char_length(dedupe_key) between 1 and 128),
  read_at timestamptz,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  client_modified_at timestamptz not null default now(),
  origin_device_id text not null,
  revision bigint not null default 1 check (revision > 0),
  sync_seq bigint not null default nextval('public.homepilot_sync_seq'),
  server_updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  primary key (user_id, id),
  foreign key (user_id, plan_id)
    references public.maintenance_plans(user_id, id)
);

create table public.device_notifications (
  user_id uuid not null references auth.users(id) on delete cascade,
  device_id text not null check (char_length(device_id) between 1 and 200),
  id text not null,
  plan_id text not null,
  channel text not null check (char_length(channel) between 1 and 120),
  scheduled_for timestamptz not null,
  delivered_at timestamptz,
  created_at timestamptz not null,
  client_modified_at timestamptz not null default now(),
  origin_device_id text not null,
  revision bigint not null default 1 check (revision > 0),
  sync_seq bigint not null default nextval('public.homepilot_sync_seq'),
  server_updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  primary key (user_id, device_id, id),
  foreign key (user_id, plan_id)
    references public.maintenance_plans(user_id, id)
);

create table public.ai_provider_settings (
  user_id uuid not null references auth.users(id) on delete cascade,
  provider text not null check (char_length(provider) between 1 and 120),
  enabled boolean not null,
  model text not null check (char_length(model) between 1 and 300),
  updated_at timestamptz not null,
  client_modified_at timestamptz not null default now(),
  origin_device_id text not null,
  revision bigint not null default 1 check (revision > 0),
  sync_seq bigint not null default nextval('public.homepilot_sync_seq'),
  server_updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  primary key (user_id, provider)
);

create table public.device_ai_provider_status (
  user_id uuid not null references auth.users(id) on delete cascade,
  device_id text not null check (char_length(device_id) between 1 and 200),
  provider text not null check (char_length(provider) between 1 and 120),
  health_score double precision not null check (
    health_score >= 0 and health_score <= 1
  ),
  average_latency_ms integer not null check (average_latency_ms >= 0),
  last_error text check (
    last_error is null or char_length(last_error) <= 4000
  ),
  last_checked_at timestamptz,
  updated_at timestamptz not null,
  client_modified_at timestamptz not null default now(),
  origin_device_id text not null,
  revision bigint not null default 1 check (revision > 0),
  sync_seq bigint not null default nextval('public.homepilot_sync_seq'),
  server_updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  primary key (user_id, device_id, provider)
);

create table public.ai_usage_logs (
  user_id uuid not null references auth.users(id) on delete cascade,
  id text not null,
  provider text not null check (char_length(provider) between 1 and 120),
  model text not null check (char_length(model) between 1 and 300),
  prompt_tokens integer check (prompt_tokens is null or prompt_tokens >= 0),
  completion_tokens integer check (
    completion_tokens is null or completion_tokens >= 0
  ),
  latency_ms integer not null check (latency_ms >= 0),
  success boolean not null,
  error_code text check (
    error_code is null or char_length(error_code) <= 300
  ),
  created_at timestamptz not null,
  client_modified_at timestamptz not null default now(),
  origin_device_id text not null,
  revision bigint not null default 1 check (revision > 0),
  sync_seq bigint not null default nextval('public.homepilot_sync_seq'),
  server_updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  primary key (user_id, id)
);

create table public.streaks (
  user_id uuid not null references auth.users(id) on delete cascade,
  id text not null,
  current_streak integer not null check (current_streak >= 0),
  best_streak integer not null check (
    best_streak >= 0 and best_streak >= current_streak
  ),
  last_completed_date timestamptz,
  updated_at timestamptz not null,
  client_modified_at timestamptz not null default now(),
  origin_device_id text not null,
  revision bigint not null default 1 check (revision > 0),
  sync_seq bigint not null default nextval('public.homepilot_sync_seq'),
  server_updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  primary key (user_id, id)
);

create table public.device_settings (
  user_id uuid not null references auth.users(id) on delete cascade,
  device_id text not null check (char_length(device_id) between 1 and 200),
  key text not null check (key in ('weather_cache', 'feature_flags_version')),
  value text not null check (octet_length(value) <= 1048576),
  updated_at timestamptz not null,
  client_modified_at timestamptz not null default now(),
  origin_device_id text not null,
  revision bigint not null default 1 check (revision > 0),
  sync_seq bigint not null default nextval('public.homepilot_sync_seq'),
  server_updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  primary key (user_id, device_id, key)
);

create function public.protect_homepilot_device_id()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.device_id is distinct from old.device_id then
    raise exception 'device_id cannot be changed'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

revoke all on function public.protect_homepilot_device_id() from public;

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'user_settings', 'notification_inbox', 'device_notifications',
    'ai_provider_settings', 'device_ai_provider_status', 'ai_usage_logs',
    'streaks', 'device_settings'
  ]
  loop
    execute format(
      'create trigger set_sync_metadata before insert or update on public.%I '
      'for each row execute function public.set_homepilot_sync_metadata()',
      table_name
    );
  end loop;

  foreach table_name in array array[
    'device_notifications', 'device_ai_provider_status', 'device_settings'
  ]
  loop
    execute format(
      'create trigger protect_device_id before update on public.%I '
      'for each row execute function public.protect_homepilot_device_id()',
      table_name
    );
  end loop;
end
$$;

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'user_settings', 'notification_inbox', 'device_notifications',
    'ai_provider_settings', 'device_ai_provider_status', 'ai_usage_logs',
    'streaks', 'device_settings'
  ]
  loop
    execute format(
      'alter table public.%I enable row level security',
      table_name
    );
    execute format(
      'revoke all on table public.%I from anon, authenticated',
      table_name
    );
    execute format(
      'grant select, insert, update on table public.%I to authenticated',
      table_name
    );
    execute format(
      'create policy %I on public.%I for select to authenticated '
      'using ((select auth.uid()) is not null '
      'and (select auth.uid()) = user_id)',
      table_name || '_select_own',
      table_name
    );
    execute format(
      'create policy %I on public.%I for insert to authenticated '
      'with check ((select auth.uid()) is not null '
      'and (select auth.uid()) = user_id)',
      table_name || '_insert_own',
      table_name
    );
    execute format(
      'create policy %I on public.%I for update to authenticated '
      'using ((select auth.uid()) is not null '
      'and (select auth.uid()) = user_id) '
      'with check ((select auth.uid()) is not null '
      'and (select auth.uid()) = user_id)',
      table_name || '_update_own',
      table_name
    );
  end loop;
end
$$;

create index user_settings_sync_idx
on public.user_settings (user_id, sync_seq);

create index notification_inbox_sync_idx
on public.notification_inbox (user_id, sync_seq);

create index notification_inbox_created_idx
on public.notification_inbox (user_id, created_at desc)
where deleted_at is null;

create index notification_inbox_plan_idx
on public.notification_inbox (user_id, plan_id)
where plan_id is not null and deleted_at is null;

create unique index notification_inbox_dedupe_uidx
on public.notification_inbox (user_id, dedupe_key)
where deleted_at is null;

create index device_notifications_sync_idx
on public.device_notifications (user_id, device_id, sync_seq);

create index device_notifications_plan_idx
on public.device_notifications (user_id, plan_id)
where deleted_at is null;

create index ai_provider_settings_sync_idx
on public.ai_provider_settings (user_id, sync_seq);

create index device_ai_provider_status_sync_idx
on public.device_ai_provider_status (user_id, device_id, sync_seq);

create index ai_usage_logs_sync_idx
on public.ai_usage_logs (user_id, sync_seq);

create index ai_usage_logs_created_idx
on public.ai_usage_logs (user_id, created_at desc)
where deleted_at is null;

create index streaks_sync_idx
on public.streaks (user_id, sync_seq);

create index device_settings_sync_idx
on public.device_settings (user_id, device_id, sync_seq);
