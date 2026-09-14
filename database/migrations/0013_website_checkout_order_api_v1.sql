BEGIN;

ALTER TABLE interface.ORDER_HEADER_IF
    ADD COLUMN IF NOT EXISTS FULFILMENT_PREFERENCE VARCHAR(30)
        NOT NULL DEFAULT 'CONSOLIDATE';

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname='ck_order_header_if_fulfilment_preference'
    ) THEN
        ALTER TABLE interface.ORDER_HEADER_IF
            ADD CONSTRAINT CK_ORDER_HEADER_IF_FULFILMENT_PREFERENCE
            CHECK (FULFILMENT_PREFERENCE IN (
                'CONSOLIDATE',
                'SPLIT_WHEN_REQUIRED'
            ));
    END IF;
END
$$;

COMMIT;
