-- HomePilot Chat with AI gateway foundation.
-- Fail closed: the seeded runtime row is disabled, in maintenance mode, and uses
-- intentionally invalid provider settings. Hosted values require an authorized
-- post-migration operation.

create schema if not exists homepilot_private;
revoke all on schema homepilot_private from public, anon, authenticated;
grant usage on schema homepilot_private to service_role;

create table homepilot_private.ai_chat_prompt_versions (
  version text primary key,
  locale text not null check (locale in ('default', 'en', 'ar')),
  system_instructions text not null check (
    length(btrim(system_instructions)) between 1 and 12000
  ),
  enabled boolean not null default false,
  created_at timestamptz not null default now(),
  created_by text not null check (length(btrim(created_by)) between 1 and 200)
);

create table homepilot_private.ai_chat_runtime_config (
  id smallint primary key check (id = 1),
  contract_version integer not null check (contract_version between 1 and 10),
  config_version bigint not null check (config_version >= 1),
  visible boolean not null default true,
  enabled boolean not null default false,
  maintenance_mode boolean not null default true,
  provider_kind text not null check (provider_kind in ('cliproxyapi')),
  provider_base_url text not null check (length(provider_base_url) between 1 and 2048),
  provider_api_path text not null default '/v1/responses' check (
    provider_api_path in ('/v1/responses')
  ),
  primary_model text not null check (length(btrim(primary_model)) between 1 and 200),
  fallback_models jsonb not null default '[]'::jsonb check (
    jsonb_typeof(fallback_models) = 'array'
    and jsonb_array_length(fallback_models) <= 4
    and not jsonb_path_exists(fallback_models, '$[*] ? (@.type() != "string")')
  ),
  active_prompt_version text not null references homepilot_private.ai_chat_prompt_versions(version),
  max_input_chars integer not null check (max_input_chars between 1 and 8000),
  max_history_messages integer not null check (max_history_messages between 1 and 40),
  max_history_chars integer not null check (max_history_chars between 1 and 40000),
  max_output_tokens integer not null check (max_output_tokens between 1 and 4096),
  provider_timeout_ms integer not null check (provider_timeout_ms between 1000 and 60000),
  transport_retry_count integer not null default 0 check (transport_retry_count between 0 and 1),
  daily_request_limit integer not null check (daily_request_limit between 1 and 1000),
  burst_request_limit integer not null check (burst_request_limit between 1 and 100),
  burst_window_seconds integer not null check (burst_window_seconds between 10 and 3600),
  rollout_percentage integer not null default 0 check (rollout_percentage between 0 and 100),
  rollout_salt text not null check (length(btrim(rollout_salt)) between 16 and 200),
  min_client_build integer not null check (min_client_build > 0),
  max_client_build integer,
  disclosure_version text not null check (length(btrim(disclosure_version)) between 1 and 200),
  disclosure_required boolean not null default true,
  circuit_failure_threshold integer not null check (circuit_failure_threshold between 1 and 50),
  circuit_cooldown_seconds integer not null check (circuit_cooldown_seconds between 10 and 86400),
  usage_retention_days integer not null check (usage_retention_days between 1 and 365),
  updated_at timestamptz not null default now(),
  updated_by text not null check (length(btrim(updated_by)) between 1 and 200),
  constraint ai_chat_runtime_config_client_build_range check (
    max_client_build is null or max_client_build >= min_client_build
  )
);

create table homepilot_private.ai_chat_localized_content (
  content_key text not null check (content_key in (
    'maintenance_message', 'disabled_message', 'unsupported_version_message',
    'rollout_unavailable_message', 'disclosure_title', 'disclosure_body',
    'service_disclaimer', 'welcome_message'
  )),
  locale text not null check (locale in ('en', 'ar')),
  content text not null check (length(btrim(content)) between 1 and 6000),
  enabled boolean not null default true,
  updated_at timestamptz not null default now(),
  updated_by text not null check (length(btrim(updated_by)) between 1 and 200),
  primary key (content_key, locale)
);

create table homepilot_private.ai_chat_suggestions (
  id uuid primary key default gen_random_uuid(),
  suggestion_key text not null check (length(btrim(suggestion_key)) between 1 and 120),
  locale text not null check (locale in ('en', 'ar')),
  title text not null check (length(btrim(title)) between 1 and 160),
  prompt text not null check (length(btrim(prompt)) between 1 and 2000),
  sort_order integer not null check (sort_order between 0 and 10000),
  enabled boolean not null default true,
  min_client_build integer,
  max_client_build integer,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (suggestion_key, locale),
  check (min_client_build is null or min_client_build > 0),
  check (max_client_build is null or max_client_build > 0),
  check (max_client_build is null or min_client_build is null or max_client_build >= min_client_build)
);

create table homepilot_private.ai_chat_rollout_allowlist (
  user_id uuid primary key references auth.users(id) on delete cascade,
  enabled boolean not null default true,
  reason text check (reason is null or length(reason) <= 500),
  expires_at timestamptz,
  created_at timestamptz not null default now(),
  created_by text not null check (length(btrim(created_by)) between 1 and 200)
);

create table homepilot_private.ai_chat_user_disclosures (
  user_id uuid not null references auth.users(id) on delete cascade,
  disclosure_version text not null check (length(btrim(disclosure_version)) between 1 and 200),
  accepted_at timestamptz not null default now(),
  client_build integer not null check (client_build > 0),
  locale text not null check (locale in ('en', 'ar')),
  primary key (user_id, disclosure_version)
);

create table homepilot_private.ai_chat_request_ledger (
  user_id uuid not null references auth.users(id) on delete cascade,
  request_id uuid not null,
  status text not null check (status in ('claimed', 'completed', 'failed')),
  config_version bigint not null check (config_version >= 1),
  provider_kind text not null check (provider_kind in ('cliproxyapi')),
  model text not null check (length(btrim(model)) between 1 and 200),
  latency_ms integer check (latency_ms is null or latency_ms >= 0),
  input_chars integer not null check (input_chars >= 0),
  history_messages integer not null check (history_messages >= 0),
  output_chars integer check (output_chars is null or output_chars >= 0),
  prompt_tokens integer check (prompt_tokens is null or prompt_tokens >= 0),
  completion_tokens integer check (completion_tokens is null or completion_tokens >= 0),
  error_code text check (error_code is null or length(error_code) <= 100),
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  primary key (user_id, request_id)
);

create index ai_chat_request_ledger_created_at_idx
  on homepilot_private.ai_chat_request_ledger (created_at);

create table homepilot_private.ai_chat_usage_windows (
  user_id uuid not null references auth.users(id) on delete cascade,
  window_kind text not null check (window_kind in ('daily', 'burst')),
  window_start timestamptz not null,
  request_count integer not null check (request_count >= 0),
  updated_at timestamptz not null default now(),
  primary key (user_id, window_kind, window_start)
);

create index ai_chat_usage_windows_updated_at_idx
  on homepilot_private.ai_chat_usage_windows (updated_at);

create table homepilot_private.ai_chat_provider_health (
  provider_kind text primary key check (provider_kind in ('cliproxyapi')),
  state text not null check (state in ('closed', 'open', 'half_open', 'unconfigured')),
  consecutive_failures integer not null default 0 check (consecutive_failures >= 0),
  cooldown_until timestamptz,
  half_open_probe_claimed_at timestamptz,
  last_success_at timestamptz,
  last_failure_at timestamptz,
  last_latency_ms integer check (last_latency_ms is null or last_latency_ms >= 0),
  last_error_code text check (last_error_code is null or length(last_error_code) <= 100),
  updated_at timestamptz not null default now()
);

create table homepilot_private.ai_chat_config_audit (
  id bigint generated always as identity primary key,
  config_version bigint not null,
  changed_at timestamptz not null default now(),
  changed_by text not null,
  old_config jsonb,
  new_config jsonb not null
);

create or replace function homepilot_private.audit_ai_chat_runtime_config()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into homepilot_private.ai_chat_config_audit (
    config_version, changed_by, old_config, new_config
  ) values (
    new.config_version,
    new.updated_by,
    case when tg_op = 'UPDATE' then to_jsonb(old) else null end,
    to_jsonb(new)
  );
  return new;
end;
$$;

create trigger audit_ai_chat_runtime_config
  after insert or update on homepilot_private.ai_chat_runtime_config
  for each row execute function homepilot_private.audit_ai_chat_runtime_config();

insert into homepilot_private.ai_chat_prompt_versions (
  version, locale, system_instructions, enabled, created_by
) values (
  'unconfigured-v1',
  'default',
  'Unconfigured fail-closed placeholder. No provider request may be sent while this prompt is active.',
  false,
  'migration'
);

insert into homepilot_private.ai_chat_runtime_config (
  id, contract_version, config_version, visible, enabled, maintenance_mode,
  provider_kind, provider_base_url, provider_api_path, primary_model,
  fallback_models, active_prompt_version, max_input_chars,
  max_history_messages, max_history_chars, max_output_tokens,
  provider_timeout_ms, transport_retry_count, daily_request_limit,
  burst_request_limit, burst_window_seconds, rollout_percentage,
  rollout_salt, min_client_build, max_client_build, disclosure_version,
  disclosure_required, circuit_failure_threshold, circuit_cooldown_seconds,
  usage_retention_days, updated_by
) values (
  1, 1, 1, true, false, true,
  'cliproxyapi', 'https://invalid.invalid', '/v1/responses', 'unconfigured',
  '[]'::jsonb, 'unconfigured-v1', 2000,
  12, 12000, 1000,
  30000, 0, 20,
  4, 60, 0,
  'replace-before-enabling-00000000', 24, null, 'ai-chat-disclosure-v1',
  true, 5, 300,
  30, 'migration'
);

insert into homepilot_private.ai_chat_provider_health (
  provider_kind, state
) values ('cliproxyapi', 'unconfigured');

alter table homepilot_private.ai_chat_prompt_versions enable row level security;
alter table homepilot_private.ai_chat_runtime_config enable row level security;
alter table homepilot_private.ai_chat_localized_content enable row level security;
alter table homepilot_private.ai_chat_suggestions enable row level security;
alter table homepilot_private.ai_chat_rollout_allowlist enable row level security;
alter table homepilot_private.ai_chat_user_disclosures enable row level security;
alter table homepilot_private.ai_chat_request_ledger enable row level security;
alter table homepilot_private.ai_chat_usage_windows enable row level security;
alter table homepilot_private.ai_chat_provider_health enable row level security;
alter table homepilot_private.ai_chat_config_audit enable row level security;

revoke all on all tables in schema homepilot_private from public, anon, authenticated;
revoke all on all sequences in schema homepilot_private from public, anon, authenticated;
revoke all on all functions in schema homepilot_private from public, anon, authenticated;
grant select, insert, update, delete on all tables in schema homepilot_private to service_role;
grant usage, select on all sequences in schema homepilot_private to service_role;
