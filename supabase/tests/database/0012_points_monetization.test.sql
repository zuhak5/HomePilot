begin;

create extension if not exists pgtap with schema extensions;
set local role postgres;
set search_path = public, extensions, pg_catalog;

select extensions.plan(60);

select extensions.has_table('public', 'point_wallets', 'point wallet table exists');
select extensions.has_table('public', 'point_transactions', 'point ledger table exists');
select extensions.has_table('public', 'reward_claim_requests', 'reward claim table exists');
select extensions.ok(
  (select bool_and(relrowsecurity)
   from pg_class
   where oid in (
     'public.point_wallets'::regclass,
     'public.point_transactions'::regclass,
     'public.reward_claim_requests'::regclass,
     'public.ad_reward_claims'::regclass,
     'public.creation_point_operations'::regclass,
     'public.monetization_config'::regclass,
     'public.monetization_events'::regclass
   )),
  'every monetization table has RLS enabled'
);
select extensions.ok(
  has_table_privilege('authenticated', 'public.point_wallets', 'SELECT'),
  'authenticated users can read their wallet'
);
select extensions.ok(
  not has_table_privilege('authenticated', 'public.point_wallets', 'UPDATE'),
  'clients cannot mutate wallet balances'
);
select extensions.ok(
  not has_table_privilege(
    'authenticated', 'public.monetization_config', 'UPDATE'
  ),
  'clients cannot alter monetization kill switches or limits'
);
select extensions.ok(
  has_table_privilege('authenticated', 'public.assets', 'INSERT'),
  'sync retains INSERT privilege while RLS requires an authorized debit'
);
select extensions.has_function(
  'public', 'create_asset_with_point_debit', array['jsonb'],
  'atomic asset creation RPC exists'
);
select extensions.has_function(
  'public', 'create_task_with_point_debit', array['jsonb'],
  'atomic task creation RPC exists'
);
select extensions.has_function(
  'public', 'create_reward_claim_request', array['text', 'text'],
  'reward claim request RPC exists'
);
select extensions.ok(
  has_function_privilege(
    'service_role',
    'public.process_admob_ssv_reward(text,uuid,uuid,text,integer,text,timestamptz)',
    'EXECUTE'
  ) and not has_function_privilege(
    'authenticated',
    'public.process_admob_ssv_reward(text,uuid,uuid,text,integer,text,timestamptz)',
    'EXECUTE'
  ),
  'SSV settlement is service-role only'
);

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
) values
  (
    '00000000-0000-0000-0000-000000000000',
    '44444444-4444-4444-4444-444444444444',
    'authenticated', 'authenticated', 'points-one@example.test', '',
    now(), now(), now()
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    '55555555-5555-5555-5555-555555555555',
    'authenticated', 'authenticated', 'points-two@example.test', '',
    now(), now(), now()
  );

insert into public.areas (
  user_id, id, name, kind, sort_order, created_at, updated_at
) values (
  '44444444-4444-4444-4444-444444444444',
  'points-area', 'Points test area', 'indoor', 0, now(), now()
);
insert into public.rooms (
  user_id, id, area_id, name, room_type, sort_order, created_at, updated_at
) values (
  '44444444-4444-4444-4444-444444444444',
  'points-room', 'points-area', 'Points test room', 'other', 0, now(), now()
);

create temporary table monetization_test_claim (payload jsonb);
create temporary table monetization_test_claim_regular_two (payload jsonb);
create temporary table monetization_test_claim_daily (payload jsonb);
grant all on monetization_test_claim,
  monetization_test_claim_regular_two,
  monetization_test_claim_daily to authenticated, service_role;

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '44444444-4444-4444-4444-444444444444',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);

select extensions.is(
  (select balance from public.point_wallets)::integer,
  7,
  'a new account starts with seven points'
);
select extensions.is(
  (select count(*) from public.point_transactions
   where transaction_type = 'initial_grant')::integer,
  1,
  'the starting grant is recorded exactly once'
);

select extensions.is(
  (
    public.create_asset_with_point_debit(
      jsonb_build_object(
        'operation_id', '44444444-0000-0000-0000-000000000001',
        'asset', jsonb_build_object(
          'id', 'points-general-asset',
          'name', 'General item',
          'asset_type', 'general',
          'category_id', 'category_general',
          'room_id', 'points-room'
        ),
        'initial_plans', jsonb_build_array(
          jsonb_build_object(
            'id', 'points-bundled-task-one',
            'asset_id', 'points-general-asset',
            'title', 'Bundled task one',
            'recurrence_interval', 1,
            'recurrence_unit', 'months',
            'priority', 'medium',
            'next_due_date', now() + interval '1 day',
            'reminder_days_before', 0,
            'health_group', 'other'
          ),
          jsonb_build_object(
            'id', 'points-bundled-task-two',
            'asset_id', 'points-general-asset',
            'title', 'Bundled task two',
            'recurrence_interval', 3,
            'recurrence_unit', 'months',
            'priority', 'low',
            'next_due_date', now() + interval '2 days',
            'reminder_days_before', 0,
            'health_group', 'other'
          )
        )
      )
    )->>'charged'
  )::integer,
  1,
  'ordinary asset creation costs one point'
);
select extensions.is(
  (select balance from public.point_wallets)::integer,
  6,
  'asset creation debits the wallet atomically'
);
select extensions.is(
  (select count(*) from public.maintenance_plans
   where asset_id = 'points-general-asset'
     and id in ('points-bundled-task-one', 'points-bundled-task-two'))::integer,
  2,
  'initial maintenance plans are committed in the asset transaction'
);
select extensions.is(
  (select (metadata->>'initial_task_count')::integer
   from public.point_transactions
   where transaction_type = 'asset_creation'
     and reference_id = 'points-general-asset'),
  2,
  'all bundled initial plans are covered by the single asset debit'
);
select extensions.is(
  (
    public.create_asset_with_point_debit(
      jsonb_build_object(
        'operation_id', '44444444-0000-0000-0000-000000000001',
        'asset', jsonb_build_object(
          'id', 'points-general-asset',
          'name', 'General item',
          'asset_type', 'general',
          'category_id', 'category_general',
          'room_id', 'points-room'
        )
      )
    )->>'already_processed'
  )::boolean,
  true,
  'replaying an asset operation is idempotent'
);
select extensions.is(
  (select count(*) from public.assets where id = 'points-general-asset')::integer,
  1,
  'an idempotent asset replay creates no duplicate'
);

select extensions.is(
  (
    public.create_task_with_point_debit(
      jsonb_build_object(
        'operation_id', '44444444-0000-0000-0000-000000000002',
        'plan', jsonb_build_object(
          'id', 'points-general-task',
          'asset_id', 'points-general-asset',
          'title', 'General task',
          'recurrence_interval', 1,
          'recurrence_unit', 'months',
          'priority', 'medium',
          'next_due_date', now() + interval '1 day',
          'reminder_days_before', 0,
          'health_group', 'other'
        )
      )
    )->>'charged'
  )::integer,
  1,
  'ordinary task creation costs one point'
);
select extensions.is(
  (select balance from public.point_wallets)::integer,
  5,
  'task creation debits the wallet atomically'
);

select extensions.is(
  (
    public.create_asset_with_point_debit(
      jsonb_build_object(
        'operation_id', '44444444-0000-0000-0000-000000000003',
        'asset', jsonb_build_object(
          'id', 'points-safety-asset',
          'name', 'Smoke alarm',
          'asset_type', 'safety',
          'category_id', 'category_safety',
          'room_id', 'points-room'
        ),
        'details', jsonb_build_object('safety_type', 'smoke_alarm')
      )
    )->>'charged'
  )::integer,
  0,
  'server-derived safety asset creation is free'
);
select extensions.is(
  (select balance from public.point_wallets)::integer,
  5,
  'a safety asset does not change the balance'
);
select extensions.is(
  (
    public.create_task_with_point_debit(
      jsonb_build_object(
        'operation_id', '44444444-0000-0000-0000-000000000004',
        'plan', jsonb_build_object(
          'id', 'points-safety-task',
          'asset_id', 'points-safety-asset',
          'title', 'Test smoke alarm',
          'recurrence_interval', 1,
          'recurrence_unit', 'months',
          'priority', 'critical',
          'next_due_date', now() + interval '1 day',
          'reminder_days_before', 0,
          'health_group', 'other'
        )
      )
    )->>'charged'
  )::integer,
  0,
  'task safety is derived from its owned asset and is free'
);
select extensions.is(
  (select balance from public.point_wallets)::integer,
  5,
  'a safety task does not change the balance'
);
select extensions.is(
  (select count(*) from public.point_transactions)::integer,
  3,
  'only the starting grant and two charged creations enter the ledger'
);

select extensions.throws_ok(
  $$insert into public.assets (
      user_id, id, name, asset_type, category_id, room_id, created_at, updated_at
    ) values (
      '44444444-4444-4444-4444-444444444444', 'bypass', 'Bypass', 'general',
      'category_general', 'points-room', now(), now()
    )$$,
  '42501',
  null,
  'direct charged entity inserts are denied'
);
select extensions.lives_ok(
  $$insert into public.assets
      select * from public.assets
      where user_id = '44444444-4444-4444-4444-444444444444'
        and id = 'points-general-asset'
      on conflict (user_id, id) do update
      set updated_at = excluded.updated_at$$,
  'offline sync can reconcile a row already created by an atomic RPC'
);

insert into monetization_test_claim (payload)
select public.create_reward_claim_request('rewarded_ad', 'Asia/Baghdad');
select extensions.is(
  (select (payload->>'reward_amount')::integer from monetization_test_claim),
  1,
  'a standard rewarded ad claim is worth one point'
);

set local role service_role;
select set_config('request.jwt.claim.role', 'service_role', true);
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select extensions.is(
  (
    public.process_admob_ssv_reward(
      'test-transaction-1',
      (select (payload->>'claim_id')::uuid from monetization_test_claim),
      '44444444-4444-4444-4444-444444444444',
      'ca-app-pub-5274007212820203/3342599731',
      1,
      'points',
      now()
    )->>'credited'
  )::boolean,
  true,
  'a valid verified SSV callback credits the wallet'
);
set local role postgres;
select extensions.is(
  (select balance from public.point_wallets
   where user_id = '44444444-4444-4444-4444-444444444444')::integer,
  6,
  'the reward credit is persisted'
);
set local role service_role;
select set_config('request.jwt.claim.role', 'service_role', true);
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select extensions.is(
  (
    public.process_admob_ssv_reward(
      'test-transaction-1',
      (select (payload->>'claim_id')::uuid from monetization_test_claim),
      '44444444-4444-4444-4444-444444444444',
      'ca-app-pub-5274007212820203/3342599731',
      1,
      'points',
      now()
    )->>'duplicate'
  )::boolean,
  true,
  'an SSV transaction retry is a known successful duplicate'
);
set local role postgres;
select extensions.is(
  (select count(*) from public.ad_reward_claims)::integer,
  1,
  'an SSV retry creates no duplicate reward claim'
);

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select extensions.throws_ok(
  $$select public.create_reward_claim_request('rewarded_ad', 'Asia/Baghdad')$$,
  'P0001',
  'REWARD_COOLDOWN',
  'a regular reward is limited only by the configured cooldown'
);

set local role postgres;
update public.reward_claim_requests
set created_at = now() - interval '46 seconds'
where user_id = '44444444-4444-4444-4444-444444444444';
set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
insert into monetization_test_claim_regular_two (payload)
select public.create_reward_claim_request('rewarded_ad', 'Asia/Baghdad');
select extensions.is(
  (
    select (payload->>'reward_amount')::integer
    from monetization_test_claim_regular_two
  ),
  1,
  'regular rewarded ads remain renewable on the same local day'
);

set local role postgres;
update public.reward_claim_requests
set created_at = now() - interval '46 seconds'
where user_id = '44444444-4444-4444-4444-444444444444';
set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select extensions.lives_ok(
  $$select public.create_reward_claim_request('rewarded_ad', 'Asia/Baghdad')$$,
  'a delayed SSV callback does not block a later claim after cooldown'
);
select extensions.is(
  (select count(*) from public.reward_claim_requests
   where status = 'pending')::integer,
  2,
  'multiple short-lived pending claims can coexist safely'
);

set local role postgres;
update public.reward_claim_requests
set created_at = now() - interval '46 seconds'
where user_id = '44444444-4444-4444-4444-444444444444';
set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
insert into monetization_test_claim_daily (payload)
select public.create_reward_claim_request(
  'rewarded_interstitial', 'Asia/Baghdad'
);
select extensions.is(
  (select (payload->>'reward_amount')::integer from monetization_test_claim_daily),
  2,
  'the daily completion rewarded interstitial is worth two points'
);

set local role service_role;
select set_config('request.jwt.claim.role', 'service_role', true);
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select extensions.is(
  (
    public.process_admob_ssv_reward(
      'test-transaction-daily-1',
      (select (payload->>'claim_id')::uuid from monetization_test_claim_daily),
      '44444444-4444-4444-4444-444444444444',
      'ca-app-pub-5274007212820203/2197039025',
      2,
      'points',
      now()
    )->>'credited'
  )::boolean,
  true,
  'a verified daily completion callback credits exactly two points'
);
set local role postgres;
select extensions.is(
  (select balance from public.point_wallets
   where user_id = '44444444-4444-4444-4444-444444444444')::integer,
  8,
  'the daily completion reward updates the cached wallet'
);
update public.reward_claim_requests
set created_at = now() - interval '46 seconds'
where user_id = '44444444-4444-4444-4444-444444444444';
set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select extensions.throws_ok(
  $$select public.create_reward_claim_request(
      'rewarded_interstitial', 'Asia/Baghdad'
    )$$,
  'P0001',
  'REWARD_ALREADY_CLAIMED',
  'the completion reward is limited to once per local calendar day'
);

select set_config(
  'request.jwt.claim.sub',
  '55555555-5555-5555-5555-555555555555',
  true
);
select extensions.is(
  (select count(*) from public.point_wallets)::integer,
  1,
  'RLS exposes only the caller wallet'
);
select set_config(
  'request.jwt.claim.sub',
  '44444444-4444-4444-4444-444444444444',
  true
);
select extensions.lives_ok(
  $$select public.record_monetization_event(
      'points_debited', '{"source":"database_test"}'::jsonb
    )$$,
  'allowlisted analytics events can be recorded'
);

set local role postgres;
select extensions.is(
  (select count(*) from public.monetization_events
   where event_name = 'points_debited')::integer,
  1,
  'analytics events are stored server-side'
);
select extensions.is(
  (select wallet_cap from public.monetization_config where singleton),
  20,
  'the production wallet cap defaults to twenty'
);
select extensions.lives_ok(
  $$update public.monetization_config set wallet_cap = 25 where singleton$$,
  'the service-side wallet cap is remotely configurable'
);
select extensions.is(
  (select wallet_cap from public.monetization_config where singleton),
  25,
  'a remote wallet cap update is persisted'
);
select extensions.lives_ok(
  $$insert into public.point_transactions (
      user_id, amount, balance_before, balance_after, transaction_type,
      idempotency_key
    ) values (
      '44444444-4444-4444-4444-444444444444', 16, 8, 24,
      'admin_adjustment', 'database-test-cap-24'
    );
    update public.point_wallets set balance = 24
    where user_id = '44444444-4444-4444-4444-444444444444'$$,
  'ledger and wallet storage accept a balance above the old fixed cap'
);
select extensions.is(
  (select balance from public.point_wallets
   where user_id = '44444444-4444-4444-4444-444444444444')::integer,
  24,
  'the remotely configured wallet cap is effective in storage'
);
delete from public.point_transactions
where idempotency_key = 'database-test-cap-24';
update public.point_wallets set balance = 8
where user_id = '44444444-4444-4444-4444-444444444444';
update public.monetization_config set wallet_cap = 20 where singleton;

update public.point_wallets set balance = 0
where user_id = '44444444-4444-4444-4444-444444444444';
set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '44444444-4444-4444-4444-444444444444',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
select extensions.throws_ok(
  $$select public.create_task_with_point_debit(
      jsonb_build_object(
        'operation_id', '44444444-0000-0000-0000-000000000005',
        'plan', jsonb_build_object(
          'id', 'points-insufficient-task',
          'asset_id', 'points-general-asset',
          'title', 'Must not be created',
          'recurrence_interval', 1,
          'recurrence_unit', 'days',
          'priority', 'low',
          'next_due_date', now() + interval '1 day',
          'health_group', 'other'
        )
      )
    )$$,
  'P0001',
  'INSUFFICIENT_POINTS',
  'insufficient points reject a charged task'
);
select extensions.is(
  (select count(*) from public.maintenance_plans
   where id = 'points-insufficient-task')::integer,
  0,
  'a rejected debit leaves no task behind'
);

set local role postgres;
update public.monetization_config
set emergency_free_creation_mode = true
where singleton;
set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select extensions.is(
  (
    public.create_task_with_point_debit(
      jsonb_build_object(
        'operation_id', '44444444-0000-0000-0000-000000000006',
        'plan', jsonb_build_object(
          'id', 'points-emergency-free-task',
          'asset_id', 'points-general-asset',
          'title', 'Emergency free task',
          'recurrence_interval', 1,
          'recurrence_unit', 'days',
          'priority', 'low',
          'next_due_date', now() + interval '1 day',
          'health_group', 'other'
        )
      )
    )->>'charged'
  )::integer,
  0,
  'the emergency kill switch makes ordinary creation free'
);
select extensions.is(
  (select count(*) from public.maintenance_plans
   where id = 'points-emergency-free-task')::integer,
  1,
  'emergency free creation still commits the requested task atomically'
);
select extensions.is(
  (select balance from public.point_wallets)::integer,
  0,
  'emergency free creation never creates point debt'
);

set local role postgres;
update public.monetization_config
set emergency_free_creation_mode = false, points_enabled = false
where singleton;
set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select extensions.is(
  (
    public.create_task_with_point_debit(
      jsonb_build_object(
        'operation_id', '44444444-0000-0000-0000-000000000007',
        'plan', jsonb_build_object(
          'id', 'points-disabled-free-task',
          'asset_id', 'points-general-asset',
          'title', 'Points disabled free task',
          'recurrence_interval', 1,
          'recurrence_unit', 'days',
          'priority', 'low',
          'next_due_date', now() + interval '1 day',
          'health_group', 'other'
        )
      )
    )->>'charged'
  )::integer,
  0,
  'the points kill switch makes ordinary creation free'
);
select extensions.is(
  (select count(*) from public.maintenance_plans
   where id = 'points-disabled-free-task')::integer,
  1,
  'points-disabled mode still commits the requested task'
);

set local role postgres;
update public.monetization_config
set points_enabled = true, rewarded_ads_enabled = false
where singleton;
update public.reward_claim_requests
set created_at = now() - interval '46 seconds'
where user_id = '44444444-4444-4444-4444-444444444444';
set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select extensions.throws_ok(
  $$select public.create_reward_claim_request('rewarded_ad', 'Asia/Baghdad')$$,
  'P0001',
  'REWARDS_DISABLED',
  'the rewarded-ad kill switch rejects new claims server-side'
);
set local role postgres;
update public.monetization_config set rewarded_ads_enabled = true
where singleton;
set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select extensions.throws_ok(
  $$select public.record_monetization_event('not_allowed', '{}'::jsonb)$$,
  '22023',
  'INVALID_EVENT',
  'analytics rejects unknown event names'
);
select extensions.throws_ok(
  $$update public.point_wallets set balance = 20$$,
  '42501',
  null,
  'clients cannot update their wallet through the Data API role'
);

select * from extensions.finish();
rollback;
