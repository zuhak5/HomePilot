create or replace function public.get_ai_chat_runtime_config(
  p_locale text,
  p_client_build integer,
  p_user_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_config homepilot_private.ai_chat_runtime_config%rowtype;
  v_locale text := case when p_locale = 'ar' then 'ar' else 'en' end;
  v_prompt homepilot_private.ai_chat_prompt_versions%rowtype;
  v_content jsonb;
  v_suggestions jsonb;
  v_allowlisted boolean;
  v_disclosure_accepted boolean;
  v_daily_start timestamptz := date_trunc('day', now() at time zone 'UTC') at time zone 'UTC';
  v_daily_count integer := 0;
  v_burst_start timestamptz;
  v_burst_count integer := 0;
begin
  if p_user_id is null or p_client_build is null or p_client_build <= 0 then
    raise exception using errcode = '22023', message = 'invalid ai chat config request';
  end if;

  select * into strict v_config
  from homepilot_private.ai_chat_runtime_config
  where id = 1;

  select * into strict v_prompt
  from homepilot_private.ai_chat_prompt_versions
  where version = v_config.active_prompt_version;

  v_burst_start := to_timestamp(
    floor(extract(epoch from now()) / v_config.burst_window_seconds)
    * v_config.burst_window_seconds
  );

  select coalesce(jsonb_object_agg(content_key, content), '{}'::jsonb)
    into v_content
  from (
    select distinct on (content_key) content_key, content
    from homepilot_private.ai_chat_localized_content
    where enabled
      and locale in (v_locale, 'en')
    order by content_key, (locale = v_locale) desc
  ) localized;

  select coalesce(jsonb_agg(jsonb_build_object(
    'key', suggestion_key,
    'title', title,
    'prompt', prompt
  ) order by sort_order, suggestion_key), '[]'::jsonb)
    into v_suggestions
  from homepilot_private.ai_chat_suggestions
  where enabled
    and locale = v_locale
    and (min_client_build is null or p_client_build >= min_client_build)
    and (max_client_build is null or p_client_build <= max_client_build);

  select exists (
    select 1 from homepilot_private.ai_chat_rollout_allowlist
    where user_id = p_user_id
      and enabled
      and (expires_at is null or expires_at > now())
  ) into v_allowlisted;

  select exists (
    select 1 from homepilot_private.ai_chat_user_disclosures
    where user_id = p_user_id
      and disclosure_version = v_config.disclosure_version
  ) into v_disclosure_accepted;

  select request_count into v_daily_count
  from homepilot_private.ai_chat_usage_windows
  where user_id = p_user_id and window_kind = 'daily' and window_start = v_daily_start;

  select request_count into v_burst_count
  from homepilot_private.ai_chat_usage_windows
  where user_id = p_user_id and window_kind = 'burst' and window_start = v_burst_start;

  return jsonb_build_object(
    'config', to_jsonb(v_config),
    'prompt', jsonb_build_object(
      'version', v_prompt.version,
      'locale', v_prompt.locale,
      'instructions', v_prompt.system_instructions,
      'enabled', v_prompt.enabled
    ),
    'localizedContent', v_content,
    'suggestions', v_suggestions,
    'allowlisted', v_allowlisted,
    'disclosureAccepted', v_disclosure_accepted,
    'quota', jsonb_build_object(
      'dailyCount', coalesce(v_daily_count, 0),
      'burstCount', coalesce(v_burst_count, 0),
      'dailyResetsAt', v_daily_start + interval '1 day',
      'burstResetsAt', v_burst_start + make_interval(secs => v_config.burst_window_seconds)
    ),
    'providerHealth', (
      select to_jsonb(health)
      from homepilot_private.ai_chat_provider_health health
      where provider_kind = v_config.provider_kind
    )
  );
end;
$$;

create or replace function public.claim_ai_chat_provider_access(
  p_provider_kind text,
  p_now timestamptz,
  p_probe_lease_seconds integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_health homepilot_private.ai_chat_provider_health%rowtype;
  v_retry_after integer;
begin
  if p_provider_kind is null or p_now is null
     or p_probe_lease_seconds <= 0 or p_probe_lease_seconds > 300 then
    raise exception using errcode = '22023', message = 'invalid provider access claim';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_provider_kind, 928432));
  select * into strict v_health
  from homepilot_private.ai_chat_provider_health
  where provider_kind = p_provider_kind
  for update;

  if v_health.state = 'closed' then
    return jsonb_build_object('allowed', true, 'probe', false, 'state', 'closed');
  end if;

  if v_health.state = 'unconfigured' then
    return jsonb_build_object('allowed', false, 'probe', false, 'state', 'unconfigured');
  end if;

  if v_health.state = 'open' and coalesce(v_health.cooldown_until, p_now) > p_now then
    v_retry_after := greatest(
      1,
      ceil(extract(epoch from (v_health.cooldown_until - p_now)))::integer
    );
    return jsonb_build_object(
      'allowed', false,
      'probe', false,
      'state', 'open',
      'retryAfterSeconds', v_retry_after
    );
  end if;

  if v_health.state = 'half_open'
     and v_health.half_open_probe_claimed_at is not null
     and v_health.half_open_probe_claimed_at + make_interval(secs => p_probe_lease_seconds) > p_now then
    v_retry_after := greatest(
      1,
      ceil(extract(epoch from (
        v_health.half_open_probe_claimed_at
        + make_interval(secs => p_probe_lease_seconds)
        - p_now
      )))::integer
    );
    return jsonb_build_object(
      'allowed', false,
      'probe', false,
      'state', 'half_open',
      'retryAfterSeconds', v_retry_after
    );
  end if;

  update homepilot_private.ai_chat_provider_health
  set state = 'half_open',
      cooldown_until = null,
      half_open_probe_claimed_at = p_now,
      updated_at = p_now
  where provider_kind = p_provider_kind;

  return jsonb_build_object('allowed', true, 'probe', true, 'state', 'half_open');
end;
$$;
