create or replace function public.claim_ai_chat_request(
  p_user_id uuid,
  p_request_id uuid,
  p_config_version bigint,
  p_provider_kind text,
  p_model text,
  p_input_chars integer,
  p_history_messages integer,
  p_now timestamptz,
  p_daily_limit integer,
  p_burst_limit integer,
  p_burst_window_seconds integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_existing_status text;
  v_daily_start timestamptz;
  v_burst_start timestamptz;
  v_daily_count integer;
  v_burst_count integer;
begin
  if p_user_id is null or p_request_id is null or p_now is null
     or p_daily_limit <= 0 or p_burst_limit <= 0
     or p_burst_window_seconds <= 0 or p_input_chars < 0
     or p_history_messages < 0 then
    raise exception using errcode = '22023', message = 'invalid ai chat claim';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 928431));

  select status into v_existing_status
  from homepilot_private.ai_chat_request_ledger
  where user_id = p_user_id and request_id = p_request_id;

  if v_existing_status = 'completed' then
    return jsonb_build_object('status', 'duplicate_completed');
  elsif v_existing_status is not null then
    return jsonb_build_object('status', 'duplicate_in_progress');
  end if;

  v_daily_start := date_trunc('day', p_now at time zone 'UTC') at time zone 'UTC';
  v_burst_start := to_timestamp(
    floor(extract(epoch from p_now) / p_burst_window_seconds)
    * p_burst_window_seconds
  );

  select coalesce(max(request_count), 0) into v_daily_count
  from homepilot_private.ai_chat_usage_windows
  where user_id = p_user_id and window_kind = 'daily' and window_start = v_daily_start;

  if v_daily_count >= p_daily_limit then
    return jsonb_build_object(
      'status', 'daily_limit_reached',
      'retryAfterSeconds', greatest(0, floor(extract(epoch from (v_daily_start + interval '1 day' - p_now)))::integer)
    );
  end if;

  select coalesce(max(request_count), 0) into v_burst_count
  from homepilot_private.ai_chat_usage_windows
  where user_id = p_user_id and window_kind = 'burst' and window_start = v_burst_start;

  if v_burst_count >= p_burst_limit then
    return jsonb_build_object(
      'status', 'burst_limit_reached',
      'retryAfterSeconds', greatest(1, ceil(extract(epoch from (v_burst_start + make_interval(secs => p_burst_window_seconds) - p_now)))::integer)
    );
  end if;

  insert into homepilot_private.ai_chat_request_ledger (
    user_id, request_id, status, config_version, provider_kind, model,
    input_chars, history_messages, created_at
  ) values (
    p_user_id, p_request_id, 'claimed', p_config_version, p_provider_kind,
    p_model, p_input_chars, p_history_messages, p_now
  );

  insert into homepilot_private.ai_chat_usage_windows (
    user_id, window_kind, window_start, request_count, updated_at
  ) values (p_user_id, 'daily', v_daily_start, 1, p_now)
  on conflict (user_id, window_kind, window_start) do update
    set request_count = homepilot_private.ai_chat_usage_windows.request_count + 1,
        updated_at = excluded.updated_at
  returning request_count into v_daily_count;

  insert into homepilot_private.ai_chat_usage_windows (
    user_id, window_kind, window_start, request_count, updated_at
  ) values (p_user_id, 'burst', v_burst_start, 1, p_now)
  on conflict (user_id, window_kind, window_start) do update
    set request_count = homepilot_private.ai_chat_usage_windows.request_count + 1,
        updated_at = excluded.updated_at
  returning request_count into v_burst_count;

  return jsonb_build_object(
    'status', 'claimed',
    'dailyRemaining', greatest(0, p_daily_limit - v_daily_count),
    'burstRemaining', greatest(0, p_burst_limit - v_burst_count),
    'dailyResetsAt', v_daily_start + interval '1 day',
    'burstResetsAt', v_burst_start + make_interval(secs => p_burst_window_seconds)
  );
end;
$$;

create or replace function public.complete_ai_chat_request(
  p_user_id uuid,
  p_request_id uuid,
  p_status text,
  p_model text,
  p_latency_ms integer,
  p_output_chars integer,
  p_prompt_tokens integer,
  p_completion_tokens integer,
  p_error_code text,
  p_completed_at timestamptz
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_updated integer;
begin
  if p_status not in ('completed', 'failed') or p_model is null or length(p_model) > 200 then
    raise exception using errcode = '22023', message = 'invalid completion status';
  end if;

  update homepilot_private.ai_chat_request_ledger
  set status = p_status,
      model = p_model,
      latency_ms = p_latency_ms,
      output_chars = p_output_chars,
      prompt_tokens = p_prompt_tokens,
      completion_tokens = p_completion_tokens,
      error_code = p_error_code,
      completed_at = p_completed_at
  where user_id = p_user_id
    and request_id = p_request_id
    and status = 'claimed';
  get diagnostics v_updated = row_count;

  if v_updated = 1 then return true; end if;
  return exists (
    select 1 from homepilot_private.ai_chat_request_ledger
    where user_id = p_user_id and request_id = p_request_id
      and status = p_status
  );
end;
$$;

create or replace function public.record_ai_chat_provider_result(
  p_provider_kind text,
  p_success boolean,
  p_retryable_failure boolean,
  p_error_code text,
  p_latency_ms integer,
  p_failure_threshold integer,
  p_cooldown_seconds integer,
  p_now timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_health homepilot_private.ai_chat_provider_health%rowtype;
  v_should_open boolean;
begin
  if p_provider_kind is null or p_now is null
     or p_failure_threshold <= 0 or p_failure_threshold > 100
     or p_cooldown_seconds <= 0 or p_cooldown_seconds > 86400
     or p_latency_ms < 0 then
    raise exception using errcode = '22023', message = 'invalid provider result';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_provider_kind, 928432));
  select * into strict v_health
  from homepilot_private.ai_chat_provider_health
  where provider_kind = p_provider_kind
  for update;

  if p_success then
    update homepilot_private.ai_chat_provider_health
    set state = 'closed',
        consecutive_failures = 0,
        cooldown_until = null,
        half_open_probe_claimed_at = null,
        last_success_at = p_now,
        last_latency_ms = p_latency_ms,
        last_error_code = null,
        updated_at = p_now
    where provider_kind = p_provider_kind;
  else
    v_should_open := v_health.state = 'half_open'
      or p_error_code = 'provider_auth_failed'
      or (p_retryable_failure and v_health.consecutive_failures + 1 >= p_failure_threshold);

    update homepilot_private.ai_chat_provider_health
    set consecutive_failures = case
          when p_retryable_failure or p_error_code = 'provider_auth_failed'
            then consecutive_failures + 1
          else consecutive_failures
        end,
        state = case when v_should_open then 'open' else state end,
        cooldown_until = case
          when v_should_open then p_now + make_interval(secs => p_cooldown_seconds)
          else cooldown_until
        end,
        half_open_probe_claimed_at = null,
        last_failure_at = p_now,
        last_latency_ms = p_latency_ms,
        last_error_code = left(p_error_code, 100),
        updated_at = p_now
    where provider_kind = p_provider_kind;
  end if;

  return (
    select to_jsonb(h)
    from homepilot_private.ai_chat_provider_health h
    where provider_kind = p_provider_kind
  );
end;
$$;

create or replace function public.accept_ai_chat_disclosure(
  p_user_id uuid,
  p_disclosure_version text,
  p_client_build integer,
  p_locale text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_active_version text;
begin
  select disclosure_version into strict v_active_version
  from homepilot_private.ai_chat_runtime_config where id = 1;
  if p_disclosure_version <> v_active_version then return false; end if;

  insert into homepilot_private.ai_chat_user_disclosures (
    user_id, disclosure_version, accepted_at, client_build, locale
  ) values (
    p_user_id, p_disclosure_version, now(), p_client_build,
    case when p_locale = 'ar' then 'ar' else 'en' end
  ) on conflict (user_id, disclosure_version) do update
    set accepted_at = excluded.accepted_at,
        client_build = excluded.client_build,
        locale = excluded.locale;
  return true;
end;
$$;

revoke all on function public.get_ai_chat_runtime_config(text, integer, uuid) from public, anon, authenticated;
revoke all on function public.claim_ai_chat_provider_access(text, timestamptz, integer) from public, anon, authenticated;
revoke all on function public.claim_ai_chat_request(uuid, uuid, bigint, text, text, integer, integer, timestamptz, integer, integer, integer) from public, anon, authenticated;
revoke all on function public.complete_ai_chat_request(uuid, uuid, text, text, integer, integer, integer, integer, text, timestamptz) from public, anon, authenticated;
revoke all on function public.record_ai_chat_provider_result(text, boolean, boolean, text, integer, integer, integer, timestamptz) from public, anon, authenticated;
revoke all on function public.accept_ai_chat_disclosure(uuid, text, integer, text) from public, anon, authenticated;

grant execute on function public.get_ai_chat_runtime_config(text, integer, uuid) to service_role;
grant execute on function public.claim_ai_chat_provider_access(text, timestamptz, integer) to service_role;
grant execute on function public.claim_ai_chat_request(uuid, uuid, bigint, text, text, integer, integer, timestamptz, integer, integer, integer) to service_role;
grant execute on function public.complete_ai_chat_request(uuid, uuid, text, text, integer, integer, integer, integer, text, timestamptz) to service_role;
grant execute on function public.record_ai_chat_provider_result(text, boolean, boolean, text, integer, integer, integer, timestamptz) to service_role;
grant execute on function public.accept_ai_chat_disclosure(uuid, text, integer, text) to service_role;
