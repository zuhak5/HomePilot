alter table public.ai_review_sessions
  add column if not exists applied_at timestamptz,
  add column if not exists cancelled_at timestamptz,
  add column if not exists superseded_by_session_id uuid
    references public.ai_review_sessions(id);

alter table public.ai_review_suggestions
  add column if not exists decision_state text not null default 'pending',
  add column if not exists final_value jsonb,
  add column if not exists rejection_reason text check (
    rejection_reason is null or char_length(rejection_reason) <= 500
  ),
  add column if not exists superseded_by_session_id uuid
    references public.ai_review_sessions(id),
  add column if not exists cancelled_at timestamptz,
  add column if not exists failed_at timestamptz,
  add column if not exists request_id text check (
    request_id is null or char_length(request_id) <= 120
  );

alter table public.ai_review_apply_attempts
  add column if not exists request_id text check (
    request_id is null or char_length(request_id) <= 120
  );

alter table public.ai_review_sessions
  drop constraint if exists ai_review_sessions_status_check;

alter table public.ai_review_sessions
  add constraint ai_review_sessions_status_check
  check (
    status in (
      'pending',
      'success',
      'error',
      'applied',
      'partially_applied',
      'cancelled',
      'superseded'
    )
  );

alter table public.ai_review_suggestions
  drop constraint if exists ai_review_suggestions_status_check;

alter table public.ai_review_suggestions
  add constraint ai_review_suggestions_status_check
  check (
    status in (
      'pending',
      'accepted',
      'rejected',
      'applied',
      'failed',
      'cancelled',
      'superseded'
    )
  );

alter table public.ai_review_suggestions
  drop constraint if exists ai_review_suggestions_decision_state_check;

alter table public.ai_review_suggestions
  add constraint ai_review_suggestions_decision_state_check
  check (
    decision_state in (
      'pending',
      'accepted_unchanged',
      'accepted_after_edit',
      'explicitly_rejected',
      'superseded',
      'cancelled',
      'failed_to_apply'
    )
  );

update public.ai_review_suggestions
set decision_state = case
  when status in ('accepted', 'applied') then 'accepted_unchanged'
  when status = 'rejected' then 'explicitly_rejected'
  when status = 'failed' then 'failed_to_apply'
  when status = 'cancelled' then 'cancelled'
  when status = 'superseded' then 'superseded'
  else 'pending'
end
where decision_state = 'pending'
  and status <> 'pending';

update public.ai_review_suggestions
set final_value = coalesce(editable_value, proposed_value)
where final_value is null
  and status in ('accepted', 'applied');

update public.ai_review_sessions
set applied_at = coalesce(applied_at, updated_at)
where status = 'applied'
  and applied_at is null;

create index if not exists ai_review_suggestions_decision_state_idx
on public.ai_review_suggestions (user_id, session_id, decision_state, created_at);

create index if not exists ai_review_sessions_superseded_idx
on public.ai_review_sessions (user_id, superseded_by_session_id)
where superseded_by_session_id is not null;

create index if not exists ai_review_suggestions_request_idx
on public.ai_review_suggestions (user_id, request_id)
where request_id is not null;

create or replace function homepilot_private.record_ai_review_decisions(
  p_user_id uuid,
  p_session_id uuid,
  p_idempotency_key text,
  p_request_id text,
  p_decisions jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_attempt_id uuid;
  v_started_at timestamptz := now();
begin
  if p_user_id is null or p_session_id is null then
    raise exception 'review session is required' using errcode = '22023';
  end if;
  if p_idempotency_key is null or char_length(trim(p_idempotency_key)) = 0 then
    raise exception 'idempotency key is required' using errcode = '22023';
  end if;
  if jsonb_typeof(coalesce(p_decisions, '[]'::jsonb)) <> 'array' then
    raise exception 'decisions must be an array' using errcode = '22023';
  end if;

  insert into public.ai_review_apply_attempts (
    user_id,
    session_id,
    idempotency_key,
    request_id,
    status,
    request_json,
    created_at
  )
  values (
    p_user_id,
    p_session_id,
    p_idempotency_key,
    p_request_id,
    'started',
    jsonb_build_object('decisions', p_decisions),
    v_started_at
  )
  on conflict (user_id, idempotency_key) do update
  set request_id = excluded.request_id,
      request_json = excluded.request_json
  returning id into v_attempt_id;

  return jsonb_build_object(
    'attemptId', v_attempt_id,
    'startedAt', v_started_at
  );
end;
$$;

revoke all on function homepilot_private.record_ai_review_decisions(
  uuid,
  uuid,
  text,
  text,
  jsonb
) from public;

grant execute on function homepilot_private.record_ai_review_decisions(
  uuid,
  uuid,
  text,
  text,
  jsonb
) to service_role;
