-- Persist first-visit permission education per authenticated account without
-- changing access policies or privileges.
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
    'permission_education_seen',
    'home_location'
  ));
