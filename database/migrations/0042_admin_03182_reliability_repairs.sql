-- DYNETIC WMS 0.3.18.2 reliability repairs.
-- Reinstall the payment expiry function so expired orders also terminalise
-- their internal CREATED/PENDING payment transactions.

CREATE OR REPLACE FUNCTION api.EXPIRE_PENDING_PAYMENT_ORDERS(
    p_client_id VARCHAR,
    p_limit INTEGER DEFAULT 100
)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
    r RECORD;
    v_dealloc RECORD;
    v_expired INTEGER := 0;
BEGIN
    FOR r IN
        SELECT ORDER_ID
          FROM core.ORDER_HEADER
         WHERE CLIENT_ID=p_client_id
           AND STATUS='PENDING_PAYMENT'
           AND PAYMENT_STATUS NOT IN ('PAID','AUTHORISED')
           AND PAYMENT_DUE_DSTAMP IS NOT NULL
           AND PAYMENT_DUE_DSTAMP<=now()
         ORDER BY PAYMENT_DUE_DSTAMP
         LIMIT GREATEST(COALESCE(p_limit,100),1)
         FOR UPDATE SKIP LOCKED
    LOOP
        SELECT * INTO v_dealloc FROM core.DEALLOCATE_ORDER(p_client_id,r.ORDER_ID);

        -- The order timeout is an authoritative WMS cancellation. Keep the
        -- internal payment ledger aligned. A later provider webhook can still
        -- move the transaction to the provider-reported state.
        UPDATE core.PAYMENT_TRANSACTION
           SET STATUS='CANCELLED',
               LAST_EVENT_TYPE=COALESCE(LAST_EVENT_TYPE,'wms.payment_expired'),
               LAST_EVENT_DSTAMP=now(),
               LAST_UPDATE_DSTAMP=now()
         WHERE CLIENT_ID=p_client_id
           AND REFERENCE_TYPE='ORDER'
           AND REFERENCE_ID=r.ORDER_ID
           AND STATUS IN ('CREATED','PENDING');

        UPDATE core.ORDER_HEADER
           SET STATUS='CANCELLED',
               PAYMENT_STATUS='CANCELLED',
               FULFILMENT_STATUS='CANCELLED',
               LAST_UPDATED_BY='PAYMENT_EXPIRY',
               LAST_UPDATE_DATE=now()
         WHERE CLIENT_ID=p_client_id AND ORDER_ID=r.ORDER_ID;

        v_expired := v_expired + 1;
    END LOOP;

    RETURN jsonb_build_object('expiredOrders',v_expired);
END;
$$;

-- ---------------------------------------------------------------------------
-- CLIENT order-prefix default
--
-- DYNETIC 0.3.18.2 HISTORICAL PAYMENT EXPIRY RECONCILIATION
--
-- Before 0.3.18.2, EXPIRE_PENDING_PAYMENT_ORDERS terminalised the
-- order but could leave its internal payment transaction CREATED/PENDING.
-- Reconcile only rows whose order was explicitly terminalised by the
-- WMS PAYMENT_EXPIRY path and where no money was captured or refunded.
--
-- PROVIDER_STATUS is deliberately preserved. This is the WMS internal
-- ledger state only; a later provider webhook remains authoritative.
UPDATE core.PAYMENT_TRANSACTION pt
   SET STATUS='CANCELLED',
       LAST_EVENT_TYPE=COALESCE(pt.LAST_EVENT_TYPE,'wms.payment_expired'),
       LAST_EVENT_DSTAMP=COALESCE(pt.LAST_EVENT_DSTAMP,oh.LAST_UPDATE_DATE,now()),
       LAST_UPDATE_DSTAMP=now()
  FROM core.ORDER_HEADER oh
 WHERE oh.CLIENT_ID=pt.CLIENT_ID
   AND oh.ORDER_ID=pt.REFERENCE_ID
   AND pt.REFERENCE_TYPE='ORDER'
   AND pt.STATUS IN ('CREATED','PENDING')
   AND COALESCE(pt.CAPTURED_AMOUNT,0)=0
   AND COALESCE(pt.REFUNDED_AMOUNT,0)=0
   AND oh.STATUS='CANCELLED'
   AND oh.PAYMENT_STATUS='CANCELLED'
   AND oh.FULFILMENT_STATUS='CANCELLED'
   AND oh.LAST_UPDATED_BY='PAYMENT_EXPIRY';

-- 0.3.18 introduced ORDER_PREFIX as a required, unique client attribute.
-- Existing clients were backfilled, but clients created after the migration
-- had no database-level implementation of the documented default.
-- Preserve explicit prefixes; derive a missing prefix from CLIENT_ID.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION core.SET_CLIENT_ORDER_PREFIX_DEFAULT()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.ORDER_PREFIX IS NULL
       OR BTRIM(NEW.ORDER_PREFIX) = '' THEN
        NEW.ORDER_PREFIX := LEFT(
            REGEXP_REPLACE(
                UPPER(NEW.CLIENT_ID),
                '[^A-Z0-9]',
                '',
                'g'
            ),
            4
        );
    ELSE
        NEW.ORDER_PREFIX := UPPER(BTRIM(NEW.ORDER_PREFIX));
    END IF;

    IF NEW.ORDER_PREFIX IS NULL
       OR NEW.ORDER_PREFIX !~ '^[A-Z0-9]{1,4}$' THEN
        RAISE EXCEPTION
          'INVALID_ORDER_PREFIX: client % requires a 1-4 character alphanumeric order prefix',
          NEW.CLIENT_ID;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_client_order_prefix_default
    ON core.CLIENT;

CREATE TRIGGER trg_client_order_prefix_default
BEFORE INSERT OR UPDATE OF CLIENT_ID, ORDER_PREFIX
ON core.CLIENT
FOR EACH ROW
EXECUTE FUNCTION core.SET_CLIENT_ORDER_PREFIX_DEFAULT();

COMMENT ON FUNCTION core.SET_CLIENT_ORDER_PREFIX_DEFAULT() IS
'Derives a missing client order prefix from CLIENT_ID while preserving explicit independently configurable prefixes.';
