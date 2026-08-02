-- Keep the documented production default while allowing operators to tune the
-- cap through the service-role-only monetization configuration row.
alter table public.monetization_config
  drop constraint if exists monetization_config_wallet_cap_check;

alter table public.monetization_config
  add constraint monetization_config_wallet_cap_check
  check (wallet_cap between 1 and 1000);
