create sequence public.homepilot_sync_seq;

create table public.catalog_categories (
  id text primary key,
  name text not null,
  health_group text not null
    check (health_group in ('safety', 'pets', 'appliances', 'plants', 'cleaning', 'other')),
  icon_name text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null check (char_length(display_name) between 1 and 120),
  avatar_object_path text,
  client_modified_at timestamptz not null default now(),
  origin_device_id text not null,
  revision bigint not null default 1 check (revision > 0),
  sync_seq bigint not null default nextval('public.homepilot_sync_seq'),
  server_updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.areas (
  user_id uuid not null references auth.users(id) on delete cascade,
  id text not null,
  name text not null check (char_length(name) between 1 and 120),
  kind text not null check (kind in ('indoor', 'outdoor')),
  sort_order integer not null default 0,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  archived_at timestamptz,
  client_modified_at timestamptz not null default now(),
  origin_device_id text not null,
  revision bigint not null default 1 check (revision > 0),
  sync_seq bigint not null default nextval('public.homepilot_sync_seq'),
  server_updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  primary key (user_id, id)
);

create table public.rooms (
  user_id uuid not null references auth.users(id) on delete cascade,
  id text not null,
  area_id text not null,
  name text not null check (char_length(name) between 1 and 120),
  room_type text not null,
  notes text,
  sort_order integer not null default 0,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  archived_at timestamptz,
  client_modified_at timestamptz not null default now(),
  origin_device_id text not null,
  revision bigint not null default 1 check (revision > 0),
  sync_seq bigint not null default nextval('public.homepilot_sync_seq'),
  server_updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  primary key (user_id, id),
  foreign key (user_id, area_id) references public.areas(user_id, id)
);

create table public.assets (
  user_id uuid not null references auth.users(id) on delete cascade,
  id text not null,
  name text not null check (char_length(name) between 1 and 200),
  asset_type text not null check (asset_type in ('device', 'pet', 'plant', 'safety', 'general')),
  category_id text not null references public.catalog_categories(id),
  room_id text not null,
  placement text,
  notes text,
  purchase_date timestamptz,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  archived_at timestamptz,
  client_modified_at timestamptz not null default now(),
  origin_device_id text not null,
  revision bigint not null default 1 check (revision > 0),
  sync_seq bigint not null default nextval('public.homepilot_sync_seq'),
  server_updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  primary key (user_id, id),
  foreign key (user_id, room_id) references public.rooms(user_id, id)
);

create table public.device_details (
  user_id uuid not null references auth.users(id) on delete cascade,
  asset_id text not null,
  brand text,
  model text,
  serial_number text,
  power_source text,
  warranty_until timestamptz,
  manual_url text,
  consumable text,
  client_modified_at timestamptz not null default now(),
  origin_device_id text not null,
  revision bigint not null default 1 check (revision > 0),
  sync_seq bigint not null default nextval('public.homepilot_sync_seq'),
  server_updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  primary key (user_id, asset_id),
  foreign key (user_id, asset_id) references public.assets(user_id, id)
);

create table public.pet_details (
  user_id uuid not null references auth.users(id) on delete cascade,
  asset_id text not null,
  species text,
  breed text,
  birth_date timestamptz,
  microchip_id text,
  vet_name text,
  vet_phone text,
  feeding_notes text,
  medical_notes text,
  client_modified_at timestamptz not null default now(),
  origin_device_id text not null,
  revision bigint not null default 1 check (revision > 0),
  sync_seq bigint not null default nextval('public.homepilot_sync_seq'),
  server_updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  primary key (user_id, asset_id),
  foreign key (user_id, asset_id) references public.assets(user_id, id)
);

create table public.plant_details (
  user_id uuid not null references auth.users(id) on delete cascade,
  asset_id text not null,
  species text,
  sunlight text,
  watering_interval_days integer check (watering_interval_days is null or watering_interval_days > 0),
  pot_size text,
  last_repotted_at timestamptz,
  toxicity_notes text,
  client_modified_at timestamptz not null default now(),
  origin_device_id text not null,
  revision bigint not null default 1 check (revision > 0),
  sync_seq bigint not null default nextval('public.homepilot_sync_seq'),
  server_updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  primary key (user_id, asset_id),
  foreign key (user_id, asset_id) references public.assets(user_id, id)
);

create table public.safety_details (
  user_id uuid not null references auth.users(id) on delete cascade,
  asset_id text not null,
  safety_type text,
  installed_at timestamptz,
  expires_at timestamptz,
  battery_type text,
  test_interval_days integer check (test_interval_days is null or test_interval_days > 0),
  client_modified_at timestamptz not null default now(),
  origin_device_id text not null,
  revision bigint not null default 1 check (revision > 0),
  sync_seq bigint not null default nextval('public.homepilot_sync_seq'),
  server_updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  primary key (user_id, asset_id),
  foreign key (user_id, asset_id) references public.assets(user_id, id)
);

create table public.tags (
  user_id uuid not null references auth.users(id) on delete cascade,
  id text not null,
  name text not null check (char_length(name) between 1 and 80),
  created_at timestamptz not null,
  client_modified_at timestamptz not null default now(),
  origin_device_id text not null,
  revision bigint not null default 1 check (revision > 0),
  sync_seq bigint not null default nextval('public.homepilot_sync_seq'),
  server_updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  primary key (user_id, id)
);

create table public.asset_tags (
  user_id uuid not null references auth.users(id) on delete cascade,
  asset_id text not null,
  tag_id text not null,
  client_modified_at timestamptz not null default now(),
  origin_device_id text not null,
  revision bigint not null default 1 check (revision > 0),
  sync_seq bigint not null default nextval('public.homepilot_sync_seq'),
  server_updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  primary key (user_id, asset_id, tag_id),
  foreign key (user_id, asset_id) references public.assets(user_id, id),
  foreign key (user_id, tag_id) references public.tags(user_id, id)
);

create table public.asset_photos (
  user_id uuid not null references auth.users(id) on delete cascade,
  id text not null,
  asset_id text not null,
  object_path text not null,
  caption text,
  is_primary boolean not null default false,
  created_at timestamptz not null,
  content_sha256 text,
  mime_type text check (mime_type is null or mime_type in ('image/jpeg', 'image/png', 'image/webp')),
  byte_size bigint check (byte_size is null or byte_size between 0 and 10485760),
  client_modified_at timestamptz not null default now(),
  origin_device_id text not null,
  revision bigint not null default 1 check (revision > 0),
  sync_seq bigint not null default nextval('public.homepilot_sync_seq'),
  server_updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  primary key (user_id, id),
  foreign key (user_id, asset_id) references public.assets(user_id, id)
);

create table public.maintenance_plans (
  user_id uuid not null references auth.users(id) on delete cascade,
  id text not null,
  asset_id text not null,
  title text not null check (char_length(title) between 1 and 200),
  instructions text,
  recurrence_interval integer not null check (recurrence_interval > 0),
  recurrence_unit text not null check (recurrence_unit in ('hours', 'days', 'weeks', 'months', 'years')),
  priority text not null check (priority in ('low', 'medium', 'high', 'critical')),
  next_due_date timestamptz not null,
  reminder_days_before integer not null default 0 check (reminder_days_before >= 0),
  health_group text not null
    check (health_group in ('safety', 'pets', 'appliances', 'plants', 'cleaning', 'other')),
  created_at timestamptz not null,
  updated_at timestamptz not null,
  archived_at timestamptz,
  client_modified_at timestamptz not null default now(),
  origin_device_id text not null,
  revision bigint not null default 1 check (revision > 0),
  sync_seq bigint not null default nextval('public.homepilot_sync_seq'),
  server_updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  primary key (user_id, id),
  foreign key (user_id, asset_id) references public.assets(user_id, id)
);

create table public.maintenance_records (
  user_id uuid not null references auth.users(id) on delete cascade,
  id text not null,
  plan_id text not null,
  due_date timestamptz not null,
  completed_at timestamptz not null,
  notes text,
  client_modified_at timestamptz not null default now(),
  origin_device_id text not null,
  revision bigint not null default 1 check (revision > 0),
  sync_seq bigint not null default nextval('public.homepilot_sync_seq'),
  server_updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  primary key (user_id, id),
  foreign key (user_id, plan_id) references public.maintenance_plans(user_id, id)
);

create function public.set_homepilot_sync_metadata()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.client_modified_at > clock_timestamp() + interval '5 minutes' then
    raise exception 'client_modified_at is too far in the future'
      using errcode = '22007';
  end if;

  if tg_op = 'UPDATE' then
    new.user_id := old.user_id;
    new.revision := old.revision + 1;
  else
    new.revision := 1;
  end if;

  new.sync_seq := nextval('public.homepilot_sync_seq');
  new.server_updated_at := clock_timestamp();
  return new;
end;
$$;

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'profiles', 'areas', 'rooms', 'assets', 'device_details', 'pet_details',
    'plant_details', 'safety_details', 'tags', 'asset_tags', 'asset_photos',
    'maintenance_plans', 'maintenance_records'
  ]
  loop
    execute format(
      'create trigger set_sync_metadata before insert or update on public.%I '
      'for each row execute function public.set_homepilot_sync_metadata()',
      table_name
    );
  end loop;
end
$$;

revoke all on function public.set_homepilot_sync_metadata() from public;
