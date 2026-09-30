-- WMS 0.3.18 - Admin return/claim runtime contract

DO $$
DECLARE
    v_app_role name;
    v_missing integer;
BEGIN
    SELECT pg_get_userbyid(nspowner)
      INTO v_app_role
      FROM pg_namespace
     WHERE nspname = 'core';

    IF v_app_role IS NULL THEN
        RAISE EXCEPTION 'FAIL: core schema owner not found';
    END IF;

    IF NOT has_table_privilege(v_app_role, 'core.return_case', 'SELECT,INSERT,UPDATE') THEN
        RAISE EXCEPTION 'FAIL: return_case SELECT/INSERT/UPDATE privilege missing';
    END IF;

    IF NOT has_table_privilege(v_app_role, 'core.return_case_line', 'SELECT,INSERT') THEN
        RAISE EXCEPTION 'FAIL: return_case_line SELECT/INSERT privilege missing';
    END IF;

    IF NOT EXISTS (
        SELECT 1
          FROM information_schema.columns
         WHERE table_schema='core'
           AND table_name='return_case'
           AND column_name='operation_id'
    ) THEN
        RAISE EXCEPTION 'FAIL: RETURN_CASE.OPERATION_ID missing';
    END IF;

    SELECT COUNT(*)
      INTO v_missing
      FROM (
            VALUES
                ('return_case_line_id'),
                ('return_case_id'),
                ('client_id'),
                ('order_id'),
                ('line_id'),
                ('sku_id'),
                ('qty'),
                ('issue_type'),
                ('condition_code'),
                ('resolution'),
                ('refund_amount'),
                ('notes')
      ) required(column_name)
     WHERE NOT EXISTS (
           SELECT 1
             FROM information_schema.columns c
            WHERE c.table_schema='core'
              AND c.table_name='return_case_line'
              AND c.column_name=required.column_name
     );

    IF v_missing <> 0 THEN
        RAISE EXCEPTION 'FAIL: % required RETURN_CASE_LINE columns missing', v_missing;
    END IF;

    RAISE NOTICE 'PASS: Admin return/claim runtime contract complete for role %', v_app_role;
END
$$;
