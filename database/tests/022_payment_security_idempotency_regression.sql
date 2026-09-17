\set ON_ERROR_STOP on

-- DYNETIC_TEST_ENVIRONMENT_GUARD_BEGIN
DO $dynetic_test_guard$
DECLARE
    v_database text := current_database();
BEGIN
    IF v_database NOT IN ('fulfilment_dev', 'fulfilment_test') THEN
        RAISE EXCEPTION
            'SAFETY STOP: database test execution is forbidden against database "%". Only fulfilment_dev and fulfilment_test are allowed.',
            v_database;
    END IF;

    RAISE NOTICE 'SAFETY: test database verified as %', v_database;
END
$dynetic_test_guard$;
-- DYNETIC_TEST_ENVIRONMENT_GUARD_END
\pset pager off
BEGIN;
INSERT INTO core.CLIENT(CLIENT_ID,DESCRIPTION,ACTIVE) VALUES('REGSEC','Security Regression',true) ON CONFLICT DO NOTHING;
DO $$ DECLARE a1 jsonb; a2 jsonb; id1 uuid; id2 uuid; p1 jsonb; p2 jsonb; blocked boolean:=false; BEGIN
 a1:=api.UPSERT_ACCOUNT_IDENTITY('REGSEC','TEST','subject-a','a@example.invalid',true); id1:=(a1->>'accountId')::uuid;
 a2:=api.UPSERT_ACCOUNT_IDENTITY('REGSEC','TEST','subject-b','b@example.invalid',true); id2:=(a2->>'accountId')::uuid;
 INSERT INTO core.ORDER_HEADER(CLIENT_ID,ORDER_ID,ORDER_DATE,STATUS,FREE_DELIVERY,FULFILMENT_STATUS,PAYMENT_STATUS,ORDER_VALUE,INV_CURRENCY,ACCOUNT_ID)
 VALUES('REGSEC','REG-SEC-ORDER',now(),'PENDING_PAYMENT','N','RESERVED','PENDING',31.25,'GBP',id1);
 p1:=api.CREATE_PAYMENT_REQUEST('REGSEC',id1,'ORDER','REG-SEC-ORDER','STRIPE','REG-SEC-IDEM');
 p2:=api.CREATE_PAYMENT_REQUEST('REGSEC',id1,'ORDER','REG-SEC-ORDER','STRIPE','REG-SEC-IDEM');
 IF p1->>'paymentId'<>p2->>'paymentId' THEN RAISE EXCEPTION 'Payment idempotency created duplicate payment'; END IF;
 IF (SELECT COUNT(*) FROM core.PAYMENT_TRANSACTION WHERE CLIENT_ID='REGSEC' AND IDEMPOTENCY_KEY='REG-SEC-IDEM')<>1 THEN RAISE EXCEPTION 'Expected exactly one payment transaction'; END IF;
 BEGIN
   PERFORM api.CREATE_PAYMENT_REQUEST('REGSEC',id2,'ORDER','REG-SEC-ORDER','STRIPE','REG-SEC-WRONG-OWNER');
 EXCEPTION WHEN OTHERS THEN blocked:=position('ORDER_NOT_FOUND_OR_NOT_OWNED' in SQLERRM)>0; END;
 IF NOT blocked THEN RAISE EXCEPTION 'Cross-account payment request was not blocked'; END IF;
 IF (p1->>'amount')::numeric<>31.25 THEN RAISE EXCEPTION 'Payment amount was not sourced from order'; END IF;
END $$;
DO $$ DECLARE j jsonb; BEGIN
 j:=api.PROCESS_PAYMENT_EVENT('REGSEC','STRIPE','evt_unmatched_reg','payment_intent.succeeded','pi_missing_reg','{"amountReceived":99}'::jsonb);
 IF COALESCE((j->>'processed')::boolean,true) THEN RAISE EXCEPTION 'Unmatched payment event incorrectly processed: %',j; END IF;
 IF (SELECT COUNT(*) FROM audit.PAYMENT_EVENT WHERE CLIENT_ID='REGSEC' AND PROVIDER_EVENT_ID='evt_unmatched_reg' AND EVENT_STATUS='UNMATCHED')<>1 THEN RAISE EXCEPTION 'Unmatched event was not audited'; END IF;
END $$;
ROLLBACK;
\echo 'Payment ownership/idempotency regression tests passed.'
