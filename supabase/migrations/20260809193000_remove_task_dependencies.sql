-- Retire the user-facing task dependency feature without changing the
-- unrelated depends_on_operation_id field used for causal completion sync.
begin;

do $migration$
declare
  function_id regprocedure;
  definition text;
begin
  foreach function_id in array array[
    'homepilot_monetization_private.create_task_with_point_debit_impl(jsonb)'::regprocedure,
    'homepilot_monetization_private.create_asset_with_point_debit_impl(jsonb)'::regprocedure
  ]
  loop
    select pg_catalog.pg_get_functiondef(function_id) into definition;

    -- The latest task RPC validated both historical dependency payload spellings.
    -- Remove those complete validation blocks before dropping the column.
    definition := replace(definition, $remove$
    if v_metadata_json ? 'dependency_plan_ids' then
      if jsonb_typeof(v_metadata_json->'dependency_plan_ids') <> 'array' then
        raise exception using errcode = '22023', message = 'INVALID_TASK_PAYLOAD';
      end if;
    end if;$remove$, '');
    definition := replace(definition, $remove$
    if v_metadata_json ? 'dependency_plan_ids_json' then
      if jsonb_typeof(v_metadata_json->'dependency_plan_ids_json') <> 'array' then
        raise exception using errcode = '22023', message = 'INVALID_TASK_PAYLOAD';
      end if;
    end if;$remove$, '');

    -- Remove the metadata insert column and its value from both RPCs. Legacy
    -- clients may still send an unknown JSON key; PostgreSQL safely ignores it.
    definition := replace(definition, 'dependency_plan_ids_json,', '');
    definition := replace(definition, $remove$
      coalesce(v_metadata_json->'dependency_plan_ids', v_metadata_json->'dependency_plan_ids_json', '[]'::jsonb)::text,$remove$, '');
    definition := replace(definition, $remove$
        coalesce(metadata_json->'dependency_plan_ids', '[]'::jsonb)::text,$remove$, '');

    -- A depleted wallet is an expected, recoverable business state. Return it
    -- as a successful RPC payload so PostgREST does not classify it as an HTTP
    -- 400 warning. No creation or debit has happened at this point.
    definition := replace(definition, $remove$
  if v_charge = 1 and v_current_balance < 1 then
    raise exception using errcode = 'P0001', message = 'INSUFFICIENT_POINTS';
  end if;$remove$, $replace$
  if v_charge = 1 and v_current_balance < 1 then
    return jsonb_build_object(
      'status', 'insufficient_points',
      'task_id', v_plan_id,
      'balance', v_current_balance,
      'charged', 0,
      'already_processed', false,
      'plan', null,
      'metadata', null
    );
  end if;$replace$);
    definition := replace(definition, $remove$
  if charge = 1 and current_balance < 1 then
    raise exception using errcode = 'P0001', message = 'INSUFFICIENT_POINTS';
  end if;$remove$, $replace$
  if charge = 1 and current_balance < 1 then
    return jsonb_build_object(
      'status', 'insufficient_points',
      'asset_id', asset_id,
      'balance', current_balance,
      'charged', 0,
      'already_processed', false
    );
  end if;$replace$);

    if pg_catalog.strpos(definition, 'dependency_plan_ids') > 0 then
      raise exception 'Could not safely retire task dependencies from function %',
        function_id::text;
    end if;
    if pg_catalog.strpos(definition, 'message = ''INSUFFICIENT_POINTS''') > 0 then
      raise exception 'Could not safely normalize insufficient-points result in function %',
        function_id::text;
    end if;

    execute definition;
  end loop;
end;
$migration$;

alter table public.maintenance_plan_metadata
  drop constraint if exists maintenance_plan_metadata_dependency_plan_ids_json_check;

alter table public.maintenance_plan_metadata
  drop column if exists dependency_plan_ids_json;

notify pgrst, 'reload schema';
commit;
