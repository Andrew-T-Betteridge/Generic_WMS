\set ON_ERROR_STOP on

DO $dynetic_test_guard$
DECLARE
    v_database text := current_database();
BEGIN
    IF v_database NOT IN ('fulfilment_dev', 'fulfilment_test')
       AND v_database NOT LIKE 'fulfilment_preflight_%' THEN
        RAISE EXCEPTION
            'SAFETY STOP: admin workbench privilege regression may only run against fulfilment_dev, fulfilment_test or fulfilment_preflight_*; current database is "%".',
            v_database;
    END IF;

    RAISE NOTICE
        'SAFETY: admin workbench privilege regression verified database %',
        v_database;
END
$dynetic_test_guard$;

BEGIN;

DO $test$
DECLARE
    v_app_role name;
    v_missing integer;
BEGIN
    SELECT pg_get_userbyid(nspowner)
      INTO v_app_role
      FROM pg_namespace
     WHERE nspname='core';

    IF v_app_role IS NULL THEN
        RAISE EXCEPTION 'CORE_SCHEMA_OWNER_NOT_FOUND';
    END IF;

    SELECT count(*)
      INTO v_missing
      FROM (
          VALUES
              ('core.admin_order_control_workbench'::text),
              ('core.admin_payment_workbench'::text),
              ('core.admin_exception_workbench'::text)
      ) AS expected(object_name)
     WHERE to_regclass(expected.object_name) IS NULL;

    IF v_missing <> 0 THEN
        RAISE EXCEPTION
            'Expected all three admin workbench views to exist; % missing.',
            v_missing;
    END IF;

    SELECT count(*)
      INTO v_missing
      FROM (
          VALUES
              ('core.admin_order_control_workbench'::text),
              ('core.admin_payment_workbench'::text),
              ('core.admin_exception_workbench'::text)
      ) AS expected(object_name)
     WHERE NOT has_table_privilege(
         v_app_role,
         expected.object_name,
         'SELECT'
     );

    IF v_missing <> 0 THEN
        RAISE EXCEPTION
            'Application role % is missing SELECT on % admin workbench view(s).',
            v_app_role,
            v_missing;
    END IF;

    RAISE NOTICE
        'PASS: application role % has SELECT on all admin workbench views.',
        v_app_role;
END
$test$;

ROLLBACK;
