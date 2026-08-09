create or replace function public.ai_user_provider_key_status(p_user_id uuid)
returns table(provider text)
language sql
stable
security definer
set search_path = ''
as $$
  select refs.provider
  from homepilot_private.ai_user_provider_key_refs as refs
  where refs.user_id = p_user_id;
$$;

create or replace function public.get_ai_user_provider_key_ref(
  p_user_id uuid,
  p_provider text
)
returns table(encrypted_api_key text, encryption_nonce text)
language sql
stable
security definer
set search_path = ''
as $$
  select refs.encrypted_api_key, refs.encryption_nonce
  from homepilot_private.ai_user_provider_key_refs as refs
  where refs.user_id = p_user_id
    and refs.provider = p_provider;
$$;

create or replace function public.upsert_ai_user_provider_key_ref(
  p_user_id uuid,
  p_provider text,
  p_encrypted_api_key text,
  p_encryption_nonce text,
  p_key_fingerprint text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_provider not in ('google', 'groq', 'openRouter', 'huggingFace') then
    raise exception 'Unsupported AI provider' using errcode = '22023';
  end if;

  insert into homepilot_private.ai_user_provider_key_refs (
    user_id,
    provider,
    encrypted_api_key,
    encryption_nonce,
    key_fingerprint,
    updated_at
  )
  values (
    p_user_id,
    p_provider,
    p_encrypted_api_key,
    p_encryption_nonce,
    p_key_fingerprint,
    now()
  )
  on conflict (user_id, provider) do update
  set encrypted_api_key = excluded.encrypted_api_key,
      encryption_nonce = excluded.encryption_nonce,
      key_fingerprint = excluded.key_fingerprint,
      updated_at = now();
end;
$$;

create or replace function public.delete_ai_user_provider_key_ref(
  p_user_id uuid,
  p_provider text
)
returns void
language sql
volatile
security definer
set search_path = ''
as $$
  delete from homepilot_private.ai_user_provider_key_refs as refs
  where refs.user_id = p_user_id
    and refs.provider = p_provider;
$$;

revoke all on function public.ai_user_provider_key_status(uuid) from public;
revoke all on function public.ai_user_provider_key_status(uuid) from anon;
revoke all on function public.ai_user_provider_key_status(uuid) from authenticated;
grant execute on function public.ai_user_provider_key_status(uuid) to service_role;

revoke all on function public.get_ai_user_provider_key_ref(uuid, text) from public;
revoke all on function public.get_ai_user_provider_key_ref(uuid, text) from anon;
revoke all on function public.get_ai_user_provider_key_ref(uuid, text) from authenticated;
grant execute on function public.get_ai_user_provider_key_ref(uuid, text) to service_role;

revoke all on function public.upsert_ai_user_provider_key_ref(uuid, text, text, text, text) from public;
revoke all on function public.upsert_ai_user_provider_key_ref(uuid, text, text, text, text) from anon;
revoke all on function public.upsert_ai_user_provider_key_ref(uuid, text, text, text, text) from authenticated;
grant execute on function public.upsert_ai_user_provider_key_ref(uuid, text, text, text, text) to service_role;

revoke all on function public.delete_ai_user_provider_key_ref(uuid, text) from public;
revoke all on function public.delete_ai_user_provider_key_ref(uuid, text) from anon;
revoke all on function public.delete_ai_user_provider_key_ref(uuid, text) from authenticated;
grant execute on function public.delete_ai_user_provider_key_ref(uuid, text) to service_role;

select pg_notify('pgrst', 'reload schema');
