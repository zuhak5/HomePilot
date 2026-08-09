begin;

create extension if not exists pgcrypto with schema extensions;
create extension if not exists pg_cron with schema pg_catalog;

create table homepilot_private.account_deletion_operations (
  id uuid primary key default gen_random_uuid(),
  request_hash text not null unique,
  subject_binding text not null,
  active_user_id uuid,
  stage text not null default 'prepared',
  last_error_code text,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  completed_at timestamptz,
  expires_at timestamptz not null default (
    clock_timestamp() + interval '7 days'
  ),
  constraint account_deletion_operations_request_hash_check
    check (request_hash ~ '^[0-9a-f]{64}$'),
  constraint account_deletion_operations_subject_binding_check
    check (subject_binding ~ '^[0-9a-f]{64}$'),
  constraint account_deletion_operations_stage_check check (
    stage in (
      'prepared',
      'storage_cleanup',
      'storage_complete',
      'auth_delete_started',
      'completed'
    )
  ),
  constraint account_deletion_operations_error_code_check check (
    last_error_code is null
    or (
      char_length(last_error_code) between 1 and 120
      and last_error_code ~ '^[a-z0-9_]+$'
    )
  ),
  constraint account_deletion_operations_completion_check check (
    (
      stage = 'completed'
      and active_user_id is null
      and completed_at is not null
      and last_error_code is null
    )
    or (
      stage <> 'completed'
      and active_user_id is not null
      and completed_at is null
    )
  )
);

alter table homepilot_private.account_deletion_operations
  enable row level security;

revoke all on homepilot_private.account_deletion_operations
from public, anon, authenticated;
grant select, insert, update, delete
on homepilot_private.account_deletion_operations
to service_role;

create function public.prune_homepilot_account_deletion_operations()
returns integer
language plpgsql
security invoker
set search_path = ''
as $$
declare
  deleted_count integer;
begin
  delete from homepilot_private.account_deletion_operations
  where expires_at <= clock_timestamp();
  get diagnostics deleted_count = row_count;
  return deleted_count;
end;
$$;

create function public.begin_homepilot_account_deletion_operation(
  p_request_hash text,
  p_subject_binding text,
  p_user_id uuid
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  operation_row homepilot_private.account_deletion_operations%rowtype;
begin
  if p_request_hash is null
    or p_request_hash !~ '^[0-9a-f]{64}$'
    or p_subject_binding is null
    or p_subject_binding !~ '^[0-9a-f]{64}$'
    or p_user_id is null
  then
    raise exception using errcode = '22023',
      message = 'INVALID_DELETION_OPERATION';
  end if;

  perform public.prune_homepilot_account_deletion_operations();

  insert into homepilot_private.account_deletion_operations (
    request_hash,
    subject_binding,
    active_user_id
  ) values (
    p_request_hash,
    p_subject_binding,
    p_user_id
  )
  on conflict (request_hash) do nothing;

  select * into operation_row
  from homepilot_private.account_deletion_operations
  where request_hash = p_request_hash
  for update;

  if not found
    or operation_row.subject_binding is distinct from p_subject_binding
    or (
      operation_row.active_user_id is not null
      and operation_row.active_user_id is distinct from p_user_id
    )
  then
    raise exception using errcode = '42501',
      message = 'DELETION_OPERATION_BINDING_MISMATCH';
  end if;

  return jsonb_build_object(
    'operation_id', operation_row.id,
    'stage', operation_row.stage,
    'completed', operation_row.stage = 'completed'
  );
end;
$$;

create function public.advance_homepilot_account_deletion_operation(
  p_operation_id uuid,
  p_user_id uuid,
  p_stage text
)
returns text
language plpgsql
security invoker
set search_path = ''
as $$
declare
  operation_row homepilot_private.account_deletion_operations%rowtype;
  current_rank integer;
  requested_rank integer;
begin
  select * into operation_row
  from homepilot_private.account_deletion_operations
  where id = p_operation_id
  for update;

  if not found
    or operation_row.active_user_id is distinct from p_user_id
  then
    raise exception using errcode = '42501',
      message = 'DELETION_OPERATION_BINDING_MISMATCH';
  end if;

  current_rank := case operation_row.stage
    when 'prepared' then 0
    when 'storage_cleanup' then 1
    when 'storage_complete' then 2
    when 'auth_delete_started' then 3
    when 'completed' then 4
    else null
  end;
  requested_rank := case p_stage
    when 'prepared' then 0
    when 'storage_cleanup' then 1
    when 'storage_complete' then 2
    when 'auth_delete_started' then 3
    else null
  end;

  if requested_rank is null then
    raise exception using errcode = '22023',
      message = 'INVALID_DELETION_OPERATION_STAGE';
  end if;

  if requested_rank > current_rank then
    update homepilot_private.account_deletion_operations
    set
      stage = p_stage,
      last_error_code = null,
      updated_at = clock_timestamp()
    where id = p_operation_id
    returning * into operation_row;
  end if;

  return operation_row.stage;
end;
$$;

create function public.record_homepilot_account_deletion_operation_error(
  p_operation_id uuid,
  p_user_id uuid,
  p_error_code text
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if p_error_code is null
    or char_length(p_error_code) not between 1 and 120
    or p_error_code !~ '^[a-z0-9_]+$'
  then
    raise exception using errcode = '22023',
      message = 'INVALID_DELETION_OPERATION_ERROR';
  end if;

  update homepilot_private.account_deletion_operations
  set
    last_error_code = p_error_code,
    updated_at = clock_timestamp()
  where id = p_operation_id
    and active_user_id = p_user_id;

  if not found then
    raise exception using errcode = '42501',
      message = 'DELETION_OPERATION_BINDING_MISMATCH';
  end if;
end;
$$;

create function public.lookup_homepilot_account_deletion_operation(
  p_request_hash text,
  p_subject_binding text
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  operation_row homepilot_private.account_deletion_operations%rowtype;
begin
  if p_request_hash is null
    or p_request_hash !~ '^[0-9a-f]{64}$'
    or p_subject_binding is null
    or p_subject_binding !~ '^[0-9a-f]{64}$'
  then
    raise exception using errcode = '22023',
      message = 'INVALID_DELETION_OPERATION';
  end if;

  perform public.prune_homepilot_account_deletion_operations();

  select * into operation_row
  from homepilot_private.account_deletion_operations
  where request_hash = p_request_hash
    and subject_binding = p_subject_binding;

  if not found then
    return null;
  end if;

  return jsonb_build_object(
    'operation_id', operation_row.id,
    'stage', operation_row.stage,
    'active_user_id', operation_row.active_user_id,
    'completed', operation_row.stage = 'completed',
    'expires_at', operation_row.expires_at
  );
end;
$$;

create function public.complete_homepilot_account_deletion_operation(
  p_operation_id uuid,
  p_user_id uuid,
  p_subject_binding text
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  operation_row homepilot_private.account_deletion_operations%rowtype;
begin
  select * into operation_row
  from homepilot_private.account_deletion_operations
  where id = p_operation_id
    and subject_binding = p_subject_binding
  for update;

  if not found
    or (
      operation_row.active_user_id is not null
      and operation_row.active_user_id is distinct from p_user_id
    )
  then
    raise exception using errcode = '42501',
      message = 'DELETION_OPERATION_BINDING_MISMATCH';
  end if;

  if operation_row.stage <> 'completed' then
    if operation_row.stage <> 'auth_delete_started' then
      raise exception using errcode = '55000',
        message = 'DELETION_OPERATION_NOT_READY';
    end if;
    update homepilot_private.account_deletion_operations
    set
      active_user_id = null,
      stage = 'completed',
      last_error_code = null,
      completed_at = clock_timestamp(),
      updated_at = clock_timestamp(),
      expires_at = clock_timestamp() + interval '7 days'
    where id = p_operation_id
    returning * into operation_row;
  end if;

  return jsonb_build_object(
    'operation_id', operation_row.id,
    'stage', operation_row.stage,
    'completed', true,
    'expires_at', operation_row.expires_at
  );
end;
$$;

revoke all on function public.prune_homepilot_account_deletion_operations()
from public, anon, authenticated;
revoke all on function public.begin_homepilot_account_deletion_operation(
  text, text, uuid
) from public, anon, authenticated;
revoke all on function public.advance_homepilot_account_deletion_operation(
  uuid, uuid, text
) from public, anon, authenticated;
revoke all on function public.record_homepilot_account_deletion_operation_error(
  uuid, uuid, text
) from public, anon, authenticated;
revoke all on function public.lookup_homepilot_account_deletion_operation(
  text, text
) from public, anon, authenticated;
revoke all on function public.complete_homepilot_account_deletion_operation(
  uuid, uuid, text
) from public, anon, authenticated;

grant execute on function public.prune_homepilot_account_deletion_operations()
to service_role;
grant execute on function public.begin_homepilot_account_deletion_operation(
  text, text, uuid
) to service_role;
grant execute on function public.advance_homepilot_account_deletion_operation(
  uuid, uuid, text
) to service_role;
grant execute on function public.record_homepilot_account_deletion_operation_error(
  uuid, uuid, text
) to service_role;
grant execute on function public.lookup_homepilot_account_deletion_operation(
  text, text
) to service_role;
grant execute on function public.complete_homepilot_account_deletion_operation(
  uuid, uuid, text
) to service_role;

do $$
declare
  existing_job_id bigint;
begin
  select jobid into existing_job_id
  from cron.job
  where jobname = 'homepilot-account-deletion-operation-prune';
  if existing_job_id is not null then
    perform cron.unschedule(existing_job_id);
  end if;
  perform cron.schedule(
    'homepilot-account-deletion-operation-prune',
    '17 * * * *',
    'select public.prune_homepilot_account_deletion_operations();'
  );
end;
$$;

commit;
