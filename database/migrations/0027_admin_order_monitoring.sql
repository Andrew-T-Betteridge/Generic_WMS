BEGIN;

CREATE TABLE IF NOT EXISTS audit.ADMIN_NOTIFICATION_EVENT (
    EVENT_ID            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    CLIENT_ID           varchar(10) NOT NULL,
    ORDER_ID            varchar(20),
    EVENT_TYPE          varchar(40) NOT NULL,
    SEVERITY            varchar(20) NOT NULL DEFAULT 'INFO',
    TITLE               varchar(120) NOT NULL,
    MESSAGE             text,
    PAYLOAD             jsonb NOT NULL DEFAULT '{}'::jsonb,
    CREATED_DSTAMP      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS IX_ADMIN_NOTIFICATION_EVENT_CLIENT_TIME
    ON audit.ADMIN_NOTIFICATION_EVENT (CLIENT_ID,CREATED_DSTAMP DESC);

CREATE INDEX IF NOT EXISTS IX_ADMIN_NOTIFICATION_EVENT_ORDER
    ON audit.ADMIN_NOTIFICATION_EVENT (CLIENT_ID,ORDER_ID,CREATED_DSTAMP);

CREATE TABLE IF NOT EXISTS config.ADMIN_NOTIFICATION_READ (
    CLIENT_ID           varchar(10) NOT NULL,
    ADMIN_USER_ID       uuid NOT NULL,
    EVENT_ID            uuid NOT NULL,
    READ_DSTAMP         timestamptz NOT NULL DEFAULT now(),
    ACKNOWLEDGED        boolean NOT NULL DEFAULT true,
    PRIMARY KEY (CLIENT_ID,ADMIN_USER_ID,EVENT_ID),
    FOREIGN KEY (ADMIN_USER_ID)
        REFERENCES config.ADMIN_USER (ADMIN_USER_ID)
        ON DELETE CASCADE,
    FOREIGN KEY (EVENT_ID)
        REFERENCES audit.ADMIN_NOTIFICATION_EVENT (EVENT_ID)
        ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS interface.NOTIFICATION_OUTBOX (
    OUTBOX_ID               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    EVENT_ID                 uuid NOT NULL,
    CLIENT_ID                varchar(10) NOT NULL,
    CHANNEL                  varchar(20) NOT NULL,
    STATUS                   varchar(20) NOT NULL DEFAULT 'PENDING',
    RECIPIENT                varchar(320),
    ATTEMPT_COUNT            integer NOT NULL DEFAULT 0,
    NEXT_ATTEMPT_DSTAMP      timestamptz NOT NULL DEFAULT now(),
    LAST_ERROR               text,
    CREATED_DSTAMP           timestamptz NOT NULL DEFAULT now(),
    SENT_DSTAMP              timestamptz,
    UNIQUE (EVENT_ID,CHANNEL),
    FOREIGN KEY (EVENT_ID)
        REFERENCES audit.ADMIN_NOTIFICATION_EVENT (EVENT_ID)
        ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS IX_NOTIFICATION_OUTBOX_PENDING
    ON interface.NOTIFICATION_OUTBOX
       (STATUS,NEXT_ATTEMPT_DSTAMP,CREATED_DSTAMP);

CREATE OR REPLACE FUNCTION audit.CAPTURE_ORDER_ADMIN_EVENT()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_event_id uuid;
BEGIN
    IF TG_OP='INSERT' THEN
        INSERT INTO audit.ADMIN_NOTIFICATION_EVENT (
            CLIENT_ID,ORDER_ID,EVENT_TYPE,SEVERITY,TITLE,MESSAGE,PAYLOAD
        ) VALUES (
            NEW.CLIENT_ID,
            NEW.ORDER_ID,
            'ORDER_CREATED',
            'INFO',
            format('Order %s created',NEW.ORDER_ID),
            format(
                'New order created%s.',
                CASE
                    WHEN NEW.CONTACT_EMAIL IS NOT NULL
                    THEN format(' for %s',NEW.CONTACT_EMAIL)
                    ELSE ''
                END
            ),
            jsonb_build_object(
                'orderId',NEW.ORDER_ID,
                'orderValue',NEW.ORDER_VALUE,
                'currency',NEW.INV_CURRENCY,
                'paymentStatus',NEW.PAYMENT_STATUS,
                'fulfilmentStatus',NEW.FULFILMENT_STATUS,
                'customerEmail',NEW.CONTACT_EMAIL,
                'deliveryPostcode',NEW.POSTCODE
            )
        )
        RETURNING EVENT_ID INTO v_event_id;

        RETURN NEW;
    END IF;

    IF NEW.PAYMENT_STATUS IS DISTINCT FROM OLD.PAYMENT_STATUS
       AND UPPER(COALESCE(NEW.PAYMENT_STATUS,'')) IN ('PAID','AUTHORISED') THEN

        INSERT INTO audit.ADMIN_NOTIFICATION_EVENT (
            CLIENT_ID,ORDER_ID,EVENT_TYPE,SEVERITY,TITLE,MESSAGE,PAYLOAD
        ) VALUES (
            NEW.CLIENT_ID,
            NEW.ORDER_ID,
            'PAYMENT_CONFIRMED',
            'SUCCESS',
            format('Paid order %s',NEW.ORDER_ID),
            format(
                'Payment confirmed for order %s%s.',
                NEW.ORDER_ID,
                CASE
                    WHEN NEW.ORDER_VALUE IS NOT NULL
                    THEN format(' - £%s',NEW.ORDER_VALUE)
                    ELSE ''
                END
            ),
            jsonb_build_object(
                'orderId',NEW.ORDER_ID,
                'orderValue',NEW.ORDER_VALUE,
                'currency',NEW.INV_CURRENCY,
                'paymentStatus',NEW.PAYMENT_STATUS,
                'fulfilmentStatus',NEW.FULFILMENT_STATUS,
                'customerEmail',NEW.CONTACT_EMAIL,
                'deliveryPostcode',NEW.POSTCODE
            )
        )
        RETURNING EVENT_ID INTO v_event_id;

        INSERT INTO interface.NOTIFICATION_OUTBOX (
            EVENT_ID,CLIENT_ID,CHANNEL
        ) VALUES (
            v_event_id,NEW.CLIENT_ID,'EMAIL'
        )
        ON CONFLICT (EVENT_ID,CHANNEL) DO NOTHING;
    END IF;

    IF NEW.PAYMENT_STATUS IS DISTINCT FROM OLD.PAYMENT_STATUS
       AND UPPER(COALESCE(NEW.PAYMENT_STATUS,''))='FAILED' THEN

        INSERT INTO audit.ADMIN_NOTIFICATION_EVENT (
            CLIENT_ID,ORDER_ID,EVENT_TYPE,SEVERITY,TITLE,MESSAGE,PAYLOAD
        ) VALUES (
            NEW.CLIENT_ID,
            NEW.ORDER_ID,
            'PAYMENT_FAILED',
            'ERROR',
            format('Payment failed - %s',NEW.ORDER_ID),
            'Customer payment failed and may need attention.',
            jsonb_build_object(
                'orderId',NEW.ORDER_ID,
                'paymentStatus',NEW.PAYMENT_STATUS,
                'customerEmail',NEW.CONTACT_EMAIL
            )
        );
    END IF;

    IF NEW.STATUS IS DISTINCT FROM OLD.STATUS
       OR NEW.FULFILMENT_STATUS IS DISTINCT FROM OLD.FULFILMENT_STATUS THEN

        IF UPPER(COALESCE(NEW.STATUS,''))='CANCELLED'
           OR UPPER(COALESCE(NEW.FULFILMENT_STATUS,''))='CANCELLED' THEN

            INSERT INTO audit.ADMIN_NOTIFICATION_EVENT (
                CLIENT_ID,ORDER_ID,EVENT_TYPE,SEVERITY,TITLE,MESSAGE,PAYLOAD
            ) VALUES (
                NEW.CLIENT_ID,
                NEW.ORDER_ID,
                'ORDER_CANCELLED',
                'WARN',
                format('Order %s cancelled',NEW.ORDER_ID),
                'Order was cancelled.',
                jsonb_build_object(
                    'orderId',NEW.ORDER_ID,
                    'status',NEW.STATUS,
                    'fulfilmentStatus',NEW.FULFILMENT_STATUS
                )
            );
        END IF;
    END IF;

    IF NEW.PAYMENT_STATUS IS DISTINCT FROM OLD.PAYMENT_STATUS
       AND UPPER(COALESCE(NEW.PAYMENT_STATUS,'')) IN ('REFUNDED','PART_REFUNDED') THEN

        INSERT INTO audit.ADMIN_NOTIFICATION_EVENT (
            CLIENT_ID,ORDER_ID,EVENT_TYPE,SEVERITY,TITLE,MESSAGE,PAYLOAD
        ) VALUES (
            NEW.CLIENT_ID,
            NEW.ORDER_ID,
            'ORDER_REFUNDED',
            'INFO',
            format('Refund recorded - %s',NEW.ORDER_ID),
            format('Payment status is now %s.',NEW.PAYMENT_STATUS),
            jsonb_build_object(
                'orderId',NEW.ORDER_ID,
                'paymentStatus',NEW.PAYMENT_STATUS
            )
        );
    END IF;

    IF NEW.SHIPPED_DATE IS NOT NULL
       AND OLD.SHIPPED_DATE IS NULL THEN

        INSERT INTO audit.ADMIN_NOTIFICATION_EVENT (
            CLIENT_ID,ORDER_ID,EVENT_TYPE,SEVERITY,TITLE,MESSAGE,PAYLOAD
        ) VALUES (
            NEW.CLIENT_ID,
            NEW.ORDER_ID,
            'ORDER_DISPATCHED',
            'SUCCESS',
            format('Order %s dispatched',NEW.ORDER_ID),
            'Order has been dispatched.',
            jsonb_build_object(
                'orderId',NEW.ORDER_ID,
                'carrierId',NEW.CARRIER_ID,
                'serviceLevel',NEW.SERVICE_LEVEL,
                'shippedDate',NEW.SHIPPED_DATE
            )
        );
    END IF;

    IF NEW.DELIVERED_DSTAMP IS NOT NULL
       AND OLD.DELIVERED_DSTAMP IS NULL THEN

        INSERT INTO audit.ADMIN_NOTIFICATION_EVENT (
            CLIENT_ID,ORDER_ID,EVENT_TYPE,SEVERITY,TITLE,MESSAGE,PAYLOAD
        ) VALUES (
            NEW.CLIENT_ID,
            NEW.ORDER_ID,
            'ORDER_DELIVERED',
            'SUCCESS',
            format('Order %s delivered',NEW.ORDER_ID),
            'Order has been marked delivered.',
            jsonb_build_object(
                'orderId',NEW.ORDER_ID,
                'deliveredDstamp',NEW.DELIVERED_DSTAMP
            )
        );
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS TRG_ORDER_ADMIN_EVENT
    ON core.ORDER_HEADER;

CREATE TRIGGER TRG_ORDER_ADMIN_EVENT
AFTER INSERT OR UPDATE
ON core.ORDER_HEADER
FOR EACH ROW
EXECUTE FUNCTION audit.CAPTURE_ORDER_ADMIN_EVENT();

DO $$
DECLARE
    v_app_role name;
BEGIN
    SELECT pg_get_userbyid(nspowner)
      INTO v_app_role
      FROM pg_namespace
     WHERE nspname='core';

    IF v_app_role IS NULL THEN
        RAISE EXCEPTION 'CORE_SCHEMA_OWNER_NOT_FOUND';
    END IF;

    EXECUTE format(
        'GRANT USAGE ON SCHEMA audit,config,interface TO %I',
        v_app_role
    );

    EXECUTE format(
        'GRANT SELECT,INSERT ON audit.admin_notification_event TO %I',
        v_app_role
    );

    EXECUTE format(
        'GRANT SELECT,INSERT,UPDATE,DELETE ON config.admin_notification_read TO %I',
        v_app_role
    );

    EXECUTE format(
        'GRANT SELECT,INSERT,UPDATE ON interface.notification_outbox TO %I',
        v_app_role
    );
END
$$;

COMMIT;
