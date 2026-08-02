-- Align existing active plant watering tasks with the plant detail watering
-- interval. This intentionally updates only clear watering/moisture tasks and
-- leaves fertilizing, pruning, light, pest, and other plant tasks untouched.

with latest_completion as (
  select distinct on (record.user_id, record.plan_id)
    record.user_id,
    record.plan_id,
    record.completed_at
  from public.maintenance_records as record
  where record.deleted_at is null
  order by record.user_id, record.plan_id, record.completed_at desc
),
candidate as (
  select
    plan.user_id,
    plan.id as plan_id,
    detail.watering_interval_days,
    latest_completion.completed_at,
    regexp_replace(
      lower(concat_ws(' ', plan.title, metadata.task_type)),
      '[^a-z0-9]+',
      ' ',
      'g'
    ) as primary_text
  from public.maintenance_plans as plan
  join public.plant_details as detail
    on detail.user_id = plan.user_id
    and detail.asset_id = plan.asset_id
    and detail.deleted_at is null
  left join public.maintenance_plan_metadata as metadata
    on metadata.user_id = plan.user_id
    and metadata.plan_id = plan.id
    and metadata.deleted_at is null
  left join latest_completion
    on latest_completion.user_id = plan.user_id
    and latest_completion.plan_id = plan.id
  where plan.deleted_at is null
    and plan.archived_at is null
    and plan.health_group = 'plants'
    and plan.recurrence_unit = 'days'
    and detail.watering_interval_days is not null
    and detail.watering_interval_days > 0
    and plan.recurrence_interval <> detail.watering_interval_days
)
update public.maintenance_plans as plan
set
  recurrence_interval = candidate.watering_interval_days,
  recurrence_unit = 'days',
  next_due_date = coalesce(
    candidate.completed_at + make_interval(days => candidate.watering_interval_days),
    plan.next_due_date
  ),
  updated_at = clock_timestamp(),
  client_modified_at = clock_timestamp(),
  origin_device_id = 'server-consistency-repair'
from candidate
where plan.user_id = candidate.user_id
  and plan.id = candidate.plan_id
  and candidate.primary_text ~ '(^|[^a-z0-9])(water|watering|moisture|irrigat|hydrate|hydro)([^a-z0-9]|$)'
  and candidate.primary_text !~ '(^|[^a-z0-9])(fertiliz|feed|prun|trim|repot|sunlight|light|pest|leaf|leaves|temperature|aquarium|fish|gravel)([^a-z0-9]|$)';
