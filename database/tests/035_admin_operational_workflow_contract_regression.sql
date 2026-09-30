-- DYNETIC WMS 0.3.18
-- Admin operational workflow contract regression.
-- Generic platform contract only.

\set ON_ERROR_STOP on

DO $$
DECLARE
    v_count integer;
BEGIN
    IF EXISTS (
        SELECT 1
          FROM information_schema.columns
         WHERE table_schema='core'
           AND table_name='site'
           AND column_name='client_id'
    ) THEN
        RAISE EXCEPTION
          'FAIL: core.SITE must be independent from CLIENT';
    END IF;

    SELECT COUNT(*)
      INTO v_count
      FROM information_schema.columns
     WHERE table_schema='core'
       AND table_name='inventory'
       AND column_name IN ('client_id','site_id');

    IF v_count<>2 THEN
        RAISE EXCEPTION
          'FAIL: INVENTORY requires CLIENT_ID and SITE_ID';
    END IF;

    IF NOT EXISTS (
        SELECT 1
          FROM information_schema.columns
         WHERE table_schema='core'
           AND table_name='order_header'
           AND column_name='site_id'
    ) THEN
        RAISE EXCEPTION
          'FAIL: ORDER_HEADER.SITE_ID missing';
    END IF;

    IF NOT EXISTS (
        SELECT 1
          FROM information_schema.columns
         WHERE table_schema='core'
           AND table_name='client'
           AND column_name='order_prefix'
    ) THEN
        RAISE EXCEPTION
          'FAIL: CLIENT.ORDER_PREFIX missing';
    END IF;

    IF to_regclass('config.client_site') IS NULL THEN
        RAISE EXCEPTION
          'FAIL: CLIENT_SITE applicability table missing';
    END IF;

    IF to_regprocedure('core.next_order_id(character varying)') IS NULL
       AND to_regprocedure('core.next_order_id(text)') IS NULL THEN
        RAISE EXCEPTION
          'FAIL: core.NEXT_ORDER_ID missing';
    END IF;

    RAISE NOTICE
      'PASS 035 admin operational workflow contract';
END;
$$;

-- 0.3.18 BATCH 3 OPERATIONAL SAFETY CONTRACT
-- Refund requests must be replay-safe and reserve in-flight amounts.
-- Return creation must use a stable operation identity and a real order.

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint c
        JOIN pg_class t ON t.oid = c.conrelid
        JOIN pg_namespace n ON n.oid = t.relnamespace
        WHERE n.nspname = 'core'
          AND t.relname = 'payment_refund'
          AND c.contype = 'u'
          AND pg_get_constraintdef(c.oid) ILIKE '%client_id%idempotency_key%'
    ) THEN
        RAISE EXCEPTION 'PAYMENT_REFUND_IDEMPOTENCY_CONSTRAINT_MISSING';
    END IF;
END $$;
