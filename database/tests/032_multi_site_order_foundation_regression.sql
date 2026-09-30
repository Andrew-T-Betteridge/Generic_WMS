
-- 032_multi_site_order_foundation_regression.sql
-- DYNETIC Generic WMS 0.3.18 structural architecture regression.

DO $$
DECLARE
    v_count integer;
    v_nullable text;
BEGIN
    IF EXISTS (
        SELECT 1
          FROM information_schema.columns
         WHERE table_schema='core'
           AND table_name='site'
           AND column_name='client_id'
    ) THEN
        RAISE EXCEPTION
          'FAIL: core.SITE must not contain CLIENT_ID';
    END IF;

    IF to_regclass('config.client_site') IS NULL THEN
        RAISE EXCEPTION
          'FAIL: config.CLIENT_SITE missing';
    END IF;

    IF to_regclass('config.uq_client_site_default_fulfilment') IS NULL THEN
        RAISE EXCEPTION
          'FAIL: default fulfilment site uniqueness missing';
    END IF;

    SELECT is_nullable
      INTO v_nullable
      FROM information_schema.columns
     WHERE table_schema='core'
       AND table_name='order_header'
       AND column_name='site_id';

    IF v_nullable IS DISTINCT FROM 'NO' THEN
        RAISE EXCEPTION
          'FAIL: core.ORDER_HEADER.SITE_ID must exist and be NOT NULL';
    END IF;

    SELECT is_nullable
      INTO v_nullable
      FROM information_schema.columns
     WHERE table_schema='interface'
       AND table_name='order_header_if'
       AND column_name='site_id';

    IF v_nullable IS DISTINCT FROM 'NO' THEN
        RAISE EXCEPTION
          'FAIL: interface.ORDER_HEADER_IF.SITE_ID must exist and be NOT NULL';
    END IF;

    SELECT is_nullable
      INTO v_nullable
      FROM information_schema.columns
     WHERE table_schema='core'
       AND table_name='inventory'
       AND column_name='site_id';

    IF v_nullable IS DISTINCT FROM 'NO' THEN
        RAISE EXCEPTION
          'FAIL: core.INVENTORY.SITE_ID must be NOT NULL';
    END IF;

    SELECT is_nullable
      INTO v_nullable
      FROM information_schema.columns
     WHERE table_schema='core'
       AND table_name='location'
       AND column_name='site_id';

    IF v_nullable IS DISTINCT FROM 'NO' THEN
        RAISE EXCEPTION
          'FAIL: core.LOCATION.SITE_ID must be NOT NULL';
    END IF;

    SELECT COUNT(*)
      INTO v_count
      FROM information_schema.table_constraints
     WHERE table_schema='core'
       AND table_name='client'
       AND constraint_name='client_order_prefix_unique'
       AND constraint_type='UNIQUE';

    IF v_count<>1 THEN
        RAISE EXCEPTION
          'FAIL: CLIENT.ORDER_PREFIX uniqueness missing';
    END IF;

    IF to_regclass('core.order_number_sequence') IS NULL THEN
        RAISE EXCEPTION
          'FAIL: core.ORDER_NUMBER_SEQUENCE missing';
    END IF;

    IF to_regprocedure('core.next_order_id(character varying)') IS NULL THEN
        RAISE EXCEPTION
          'FAIL: core.NEXT_ORDER_ID(varchar) missing';
    END IF;

    RAISE NOTICE
      'PASS: 0.3.18 multi-site order foundation structure validated';
END;
$$;
