alter table public.notification_inbox
  add column if not exists message_code text,
  add column if not exists message_args jsonb not null default '{}'::jsonb;

alter table public.notification_inbox
  drop constraint if exists notification_inbox_message_code_check,
  drop constraint if exists notification_inbox_message_args_object_check;

alter table public.notification_inbox
  add constraint notification_inbox_message_code_check
    check (
      message_code is null
      or char_length(message_code) between 1 and 120
    ) not valid,
  add constraint notification_inbox_message_args_object_check
    check (jsonb_typeof(message_args) = 'object') not valid;

alter table public.notification_inbox
  validate constraint notification_inbox_message_code_check;

alter table public.notification_inbox
  validate constraint notification_inbox_message_args_object_check;

-- PostgreSQL check constraints cannot be extended in place. Replace the
-- existing allow-list transactionally without changing table privileges or
-- row-level security policies.
alter table public.user_settings
  drop constraint if exists user_settings_key_check;

alter table public.user_settings
  add constraint user_settings_key_check
  check (key in (
    'theme',
    'app_language',
    'app_language_explicit',
    'theme_time_of_day_enabled',
    'notifications_enabled',
    'notification_preferences',
    'onboarding_completed',
    'home_location'
  ));
