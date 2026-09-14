\set ON_ERROR_STOP on
\pset pager off
BEGIN;

DO $$
DECLARE
    v_account JSONB;
    v_account_id UUID;
    v_product_id VARCHAR(50);
    v_slug VARCHAR(250);
    v_address JSONB;
    v_fav JSONB;
    v_order_id VARCHAR(20);
    v_payment JSONB;
    v_payment_id UUID;
    v_event JSONB;
    v_status JSONB;
    v_count INTEGER;
BEGIN
    v_account := api.UPSERT_ACCOUNT_IDENTITY('FINATICS','TEST_IDP','subject-001','v3-test@example.invalid',TRUE);
    v_account_id := (v_account->>'accountId')::UUID;
    IF v_account_id IS NULL OR NOT COALESCE((v_account->>'emailVerified')::BOOLEAN,FALSE) THEN
        RAISE EXCEPTION 'Account identity test failed: %',v_account;
    END IF;

    v_address := api.SAVE_ACCOUNT_ADDRESS('FINATICS',v_account_id,jsonb_build_object(
        'label','Home','name','V3 Test','address1','1 Test Road','town','Hinckley',
        'postcode','LE10 0AA','country','GB','defaultDelivery',TRUE
    ));
    IF NOT COALESCE((v_address->>'saved')::BOOLEAN,FALSE) THEN
        RAISE EXCEPTION 'Saved address test failed: %',v_address;
    END IF;

    SELECT PRODUCT_ID,SLUG INTO v_product_id,v_slug
      FROM core.PRODUCT WHERE CLIENT_ID='FINATICS' AND ACTIVE=TRUE
      ORDER BY PRODUCT_ID LIMIT 1;
    IF v_product_id IS NULL THEN RAISE EXCEPTION 'No seeded product available for V3 test'; END IF;

    PERFORM api.SET_PRODUCT_FAVOURITE('FINATICS',v_account_id,v_slug,TRUE);
    v_fav := api.GET_PRODUCT_FAVOURITES('FINATICS',v_account_id);
    IF jsonb_array_length(v_fav)<1 THEN RAISE EXCEPTION 'Favourite test failed'; END IF;

    -- Create a minimal owned order directly to isolate security/payment V3 from catalogue fixtures.
    v_order_id := 'V3PAYTEST';
    INSERT INTO core.ORDER_HEADER(
        CLIENT_ID,ORDER_ID,ORDER_DATE,STATUS,PRIORITY,CUSTOMER_ID,
        INV_CURRENCY,CREATED_BY,LAST_UPDATED_BY,
        PAYMENT_STATUS,FULFILMENT_STATUS,FREE_DELIVERY,
        ACCOUNT_ID,ORDER_VALUE
    )
    VALUES(
        'FINATICS',v_order_id,now(),'NEW',1000,'V3TEST',
        'GBP','V3_TEST','V3_TEST',
        'PENDING','NEW','N',
        v_account_id,19.99
    );

    v_payment := api.CREATE_PAYMENT_REQUEST(
        'FINATICS',v_account_id,'ORDER',v_order_id,'STRIPE','v3-payment-idem-001'
    );
    v_payment_id := (v_payment->>'paymentId')::UUID;
    IF (v_payment->>'amount')::NUMERIC<>19.99 THEN
        RAISE EXCEPTION 'Server-side payment amount incorrect: %',v_payment;
    END IF;

    PERFORM api.SET_PAYMENT_PROVIDER_REFERENCE(
        'FINATICS',v_payment_id,'pi_dynetic_test_001','requires_payment_method'
    );

    v_event := api.PROCESS_PAYMENT_EVENT(
        'FINATICS','STRIPE','evt_dynetic_001','payment_intent.succeeded',
        'pi_dynetic_test_001',
        '{"providerStatus":"succeeded","amountReceived":19.99}'::jsonb
    );
    IF v_event->>'status'<>'PAID' THEN RAISE EXCEPTION 'Payment success event failed: %',v_event; END IF;

    -- Exact webhook replay must not duplicate processing.
    v_event := api.PROCESS_PAYMENT_EVENT(
        'FINATICS','STRIPE','evt_dynetic_001','payment_intent.succeeded',
        'pi_dynetic_test_001',
        '{"providerStatus":"succeeded","amountReceived":19.99}'::jsonb
    );
    IF NOT COALESCE((v_event->>'idempotentReplay')::BOOLEAN,FALSE) THEN
        RAISE EXCEPTION 'Webhook idempotency failed: %',v_event;
    END IF;

    SELECT COUNT(*) INTO v_count FROM audit.PAYMENT_EVENT
     WHERE CLIENT_ID='FINATICS' AND PROVIDER_EVENT_ID='evt_dynetic_001';
    IF v_count<>1 THEN RAISE EXCEPTION 'Expected exactly one payment event; got %',v_count; END IF;
END $$;

DO $$
DECLARE
    v_payment_status VARCHAR(30);
    v_payment_id UUID;
    v_result JSONB;
BEGIN
    SELECT PAYMENT_STATUS INTO v_payment_status
      FROM core.ORDER_HEADER WHERE CLIENT_ID='FINATICS' AND ORDER_ID='V3PAYTEST';
    IF v_payment_status<>'PAID' THEN
        RAISE EXCEPTION 'Order payment status was not updated: %',v_payment_status;
    END IF;

    SELECT PAYMENT_ID INTO v_payment_id
      FROM core.PAYMENT_TRANSACTION
     WHERE CLIENT_ID='FINATICS' AND REFERENCE_ID='V3PAYTEST'
     ORDER BY CREATED_DSTAMP DESC LIMIT 1;

    v_result := api.PROCESS_PAYMENT_EVENT(
        'FINATICS','STRIPE','evt_dynetic_refund_001','charge.refunded',
        'pi_dynetic_test_001',
        '{"providerStatus":"succeeded","amountRefunded":5.00}'::jsonb
    );
    IF v_result->>'status'<>'PART_REFUNDED' THEN
        RAISE EXCEPTION 'Partial refund state failed: %',v_result;
    END IF;
END $$;

ROLLBACK;
