update public.ai_provider_settings
set
  model = 'llama-3.3-70b-versatile',
  updated_at = now(),
  client_modified_at = now(),
  revision = coalesce(revision, 0) + 1
where provider = 'groq'
  and model like 'openai/gpt-oss-120b%';

delete from public.ai_provider_health_cache
where provider = 'groq'
  and model like 'openai/gpt-oss-120b%';
