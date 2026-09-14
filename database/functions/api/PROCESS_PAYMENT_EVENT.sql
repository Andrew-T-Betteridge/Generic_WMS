CREATE OR REPLACE FUNCTION api.PROCESS_PAYMENT_EVENT(
    p_client_id VARCHAR,
    p_provider VARCHAR,
    p_provider_event_id VARCHAR,
    p_event_type VARCHAR,
    p_provider_reference VARCHAR,
    p_payload JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
    v_payment core.PAYMENT_TRANSACTION%ROWTYPE;
    v_existing audit.PAYMENT_EVENT%ROWTYPE;
    v_new_status VARCHAR(30);
    v_amount_received NUMERIC(12,2);
    v_amount_refunded NUMERIC(12,2);
    v_payment_found BOOLEAN;
BEGIN
    SELECT * INTO v_existing
      FROM audit.PAYMENT_EVENT
     WHERE CLIENT_ID=p_client_id
       AND PROVIDER=UPPER(p_provider)
       AND PROVIDER_EVENT_ID=p_provider_event_id;

    IF FOUND THEN
        RETURN jsonb_build_object(
            'processed',TRUE,'idempotentReplay',TRUE,
            'paymentId',v_existing.PAYMENT_ID,'eventType',v_existing.EVENT_TYPE
        );
    END IF;

    SELECT * INTO v_payment
      FROM core.PAYMENT_TRANSACTION
     WHERE CLIENT_ID=p_client_id
       AND PROVIDER=UPPER(p_provider)
       AND PROVIDER_REFERENCE=p_provider_reference
     ORDER BY CREATED_DSTAMP DESC
     LIMIT 1
     FOR UPDATE;

    v_payment_found := FOUND;

    INSERT INTO audit.PAYMENT_EVENT(
        CLIENT_ID,PROVIDER,PROVIDER_EVENT_ID,EVENT_TYPE,PROVIDER_REFERENCE,
        PAYMENT_ID,EVENT_STATUS,EVENT_PAYLOAD
    )
    VALUES(
        p_client_id,UPPER(p_provider),p_provider_event_id,p_event_type,p_provider_reference,
        CASE WHEN v_payment_found THEN v_payment.PAYMENT_ID ELSE NULL END,
        CASE WHEN v_payment_found THEN 'RECEIVED' ELSE 'UNMATCHED' END,
        COALESCE(p_payload,'{}'::jsonb)
    );

    IF NOT v_payment_found THEN
        RETURN jsonb_build_object('processed',FALSE,'reason','PAYMENT_NOT_FOUND');
    END IF;

    v_amount_received := COALESCE(NULLIF(p_payload->>'amountReceived','')::NUMERIC,0);
    v_amount_refunded := COALESCE(NULLIF(p_payload->>'amountRefunded','')::NUMERIC,0);

    v_new_status := CASE p_event_type
        WHEN 'payment_intent.succeeded' THEN 'PAID'
        WHEN 'payment_intent.processing' THEN 'PENDING'
        WHEN 'payment_intent.requires_capture' THEN 'AUTHORISED'
        WHEN 'payment_intent.payment_failed' THEN 'FAILED'
        WHEN 'payment_intent.canceled' THEN 'CANCELLED'
        WHEN 'charge.refunded' THEN CASE
            WHEN v_amount_refunded>=v_payment.AMOUNT THEN 'REFUNDED'
            ELSE 'PART_REFUNDED'
        END
        ELSE v_payment.STATUS
    END;

    UPDATE core.PAYMENT_TRANSACTION
       SET STATUS=v_new_status,
           PROVIDER_STATUS=COALESCE(p_payload->>'providerStatus',PROVIDER_STATUS),
           CAPTURED_AMOUNT=CASE
               WHEN p_event_type='payment_intent.succeeded'
               THEN GREATEST(CAPTURED_AMOUNT,COALESCE(NULLIF(v_amount_received,0),AMOUNT))
               ELSE CAPTURED_AMOUNT END,
           REFUNDED_AMOUNT=CASE
               WHEN p_event_type='charge.refunded'
               THEN GREATEST(REFUNDED_AMOUNT,v_amount_refunded)
               ELSE REFUNDED_AMOUNT END,
           FAILURE_CODE=CASE WHEN p_event_type='payment_intent.payment_failed'
                             THEN LEFT(p_payload->>'failureCode',100) ELSE FAILURE_CODE END,
           FAILURE_TEXT=CASE WHEN p_event_type='payment_intent.payment_failed'
                             THEN LEFT(p_payload->>'failureText',500) ELSE FAILURE_TEXT END,
           LAST_EVENT_TYPE=p_event_type,
           LAST_EVENT_DSTAMP=now(),
           LAST_UPDATE_DSTAMP=now()
     WHERE PAYMENT_ID=v_payment.PAYMENT_ID;

    IF v_payment.REFERENCE_TYPE='ORDER' THEN
        /*
         * DEALLOCATE_ORDER deliberately recalculates FULFILMENT_STATUS to
         * UNALLOCATED/PART_PICKED.  For failed/cancelled payments the terminal
         * payment state must win, so release inventory first and only then set
         * the final order/fulfilment status.
         */
        IF v_new_status IN ('FAILED','CANCELLED') THEN
            PERFORM core.DEALLOCATE_ORDER(p_client_id,v_payment.REFERENCE_ID);
        END IF;

        UPDATE core.ORDER_HEADER
           SET PAYMENT_STATUS=v_new_status,
               STATUS=CASE
                   WHEN v_new_status IN ('PAID','AUTHORISED') AND STATUS='PENDING_PAYMENT' THEN 'NEW'
                   WHEN v_new_status='FAILED' THEN 'PAYMENT_FAILED'
                   WHEN v_new_status='CANCELLED' THEN 'CANCELLED'
                   ELSE STATUS
               END,
               FULFILMENT_STATUS=CASE
                   WHEN v_new_status IN ('PAID','AUTHORISED') AND FULFILMENT_STATUS='RESERVED' THEN 'ALLOCATED'
                   WHEN v_new_status IN ('FAILED','CANCELLED') THEN 'CANCELLED'
                   ELSE FULFILMENT_STATUS
               END,
               LAST_UPDATED_BY='PAYMENT_WEBHOOK',
               LAST_UPDATE_DATE=now()
         WHERE CLIENT_ID=p_client_id
           AND ORDER_ID=v_payment.REFERENCE_ID;
    END IF;

    UPDATE audit.PAYMENT_EVENT
       SET EVENT_STATUS='PROCESSED',PROCESSED_DSTAMP=now()
     WHERE CLIENT_ID=p_client_id
       AND PROVIDER=UPPER(p_provider)
       AND PROVIDER_EVENT_ID=p_provider_event_id;

    RETURN jsonb_build_object(
        'processed',TRUE,
        'idempotentReplay',FALSE,
        'paymentId',v_payment.PAYMENT_ID,
        'status',v_new_status
    );
END;
$$;
