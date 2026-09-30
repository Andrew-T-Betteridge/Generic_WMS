-- WMS 0.3.18 - return/refund idempotency contract

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
          FROM information_schema.columns
         WHERE table_schema = 'core'
           AND table_name = 'return_case'
           AND column_name = 'operation_id'
    ) THEN
        RAISE EXCEPTION 'RETURN_CASE.OPERATION_ID missing';
    END IF;

    IF NOT EXISTS (
        SELECT 1
          FROM pg_indexes
         WHERE schemaname = 'core'
           AND tablename = 'return_case'
           AND indexname = 'uq_return_case_operation'
    ) THEN
        RAISE EXCEPTION 'Return operation unique index missing';
    END IF;

    IF NOT EXISTS (
        SELECT 1
          FROM pg_indexes
         WHERE schemaname = 'core'
           AND tablename = 'payment_refund'
           AND indexdef ILIKE '%idempotency_key%'
           AND indexdef ILIKE '%unique%'
    ) THEN
        RAISE EXCEPTION 'PAYMENT_REFUND idempotency uniqueness missing';
    END IF;
END
$$;
