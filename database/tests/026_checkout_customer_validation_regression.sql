\set ON_ERROR_STOP on
\pset pager off

-- DYNETIC_TEST_ENVIRONMENT_GUARD_BEGIN
DO $dynetic_environment_guard$
DECLARE
    v_database text := current_database();
BEGIN
    IF v_database NOT IN ('fulfilment_dev', 'fulfilment_test') THEN
        RAISE EXCEPTION
            'SAFETY STOP: SQL tests are allowed only against fulfilment_dev or fulfilment_test. Current database: %',
            v_database;
    END IF;

    RAISE NOTICE
        'SAFETY: non-production database verified as %',
        v_database;
END
$dynetic_environment_guard$;
-- DYNETIC_TEST_ENVIRONMENT_GUARD_END

-- This particular regression uses FINATICS TEST fixtures and is intentionally
-- stricter than the universal non-production guard above.
DO $dynetic_test_only_guard$
DECLARE
    v_database text := current_database();
BEGIN
    IF v_database <> 'fulfilment_test' THEN
        RAISE EXCEPTION
            'SAFETY STOP: customer checkout validation regression is allowed only against fulfilment_test. Current database: %',
            v_database;
    END IF;

    RAISE NOTICE
        'SAFETY: customer checkout validation TEST database verified as %',
        v_database;
END
$dynetic_test_only_guard$;

BEGIN;

DO $$
DECLARE
    v_result JSONB;
    v_before INTEGER;
    v_after INTEGER;
BEGIN
    IF api.NORMALIZE_GB_PHONE('07123 456789') <> '+447123456789' THEN
        RAISE EXCEPTION 'FAIL 01: 07 mobile was not normalised to E.164';
    END IF;
    RAISE NOTICE 'PASS 01: 07 mobile normalises to +44 E.164';

    IF api.NORMALIZE_GB_PHONE('+44 7123 456789') <> '+447123456789' THEN
        RAISE EXCEPTION 'FAIL 02: +44 mobile was not accepted';
    END IF;
    RAISE NOTICE 'PASS 02: +44 mobile accepted';

    IF api.NORMALIZE_GB_PHONE('0044 7123 456789') <> '+447123456789' THEN
        RAISE EXCEPTION 'FAIL 03: 0044 mobile was not normalised';
    END IF;
    RAISE NOTICE 'PASS 03: 0044 mobile normalises';

    IF api.NORMALIZE_GB_PHONE('07123 45678') IS NOT NULL THEN
        RAISE EXCEPTION 'FAIL 04: short invalid UK-looking number was accepted';
    END IF;
    RAISE NOTICE 'PASS 04: short invalid phone rejected';

    IF api.NORMALIZE_GB_POSTCODE('cv130xx') <> 'CV13 0XX' THEN
        RAISE EXCEPTION 'FAIL 05: postcode did not canonicalise';
    END IF;
    RAISE NOTICE 'PASS 05: postcode canonicalises to CV13 0XX';

    IF api.NORMALIZE_GB_POSTCODE('NOT A POSTCODE') IS NOT NULL THEN
        RAISE EXCEPTION 'FAIL 06: malformed postcode accepted';
    END IF;
    RAISE NOTICE 'PASS 06: malformed postcode rejected';

    v_result := api.SUBMIT_WEB_ORDER(
        'FINATICS',
        jsonb_build_object(
            'idempotencyKey','CUST-VAL-BLANK-NAME',
            'fulfilmentOptionCode','LOCAL-CV13',
            'items',jsonb_build_array(
                jsonb_build_object('sku_id','FRYTRAY001-S-G-W-G','qty',1)
            ),
            'customer',jsonb_build_object(
                'name','   ',
                'email','test@example.com',
                'phone','07123456789'
            ),
            'deliveryAddress',jsonb_build_object(
                'address1','1 Test Road',
                'town','Nuneaton',
                'postcode','CV13 0XX',
                'country','GB'
            )
        )
    );

    IF v_result->>'code' <> 'CUSTOMER_NAME_REQUIRED' THEN
        RAISE EXCEPTION 'FAIL 07: expected CUSTOMER_NAME_REQUIRED, got %',v_result;
    END IF;
    RAISE NOTICE 'PASS 07: blank customer name rejected';

    v_result := api.SUBMIT_WEB_ORDER(
        'FINATICS',
        jsonb_build_object(
            'idempotencyKey','CUST-VAL-EMAIL',
            'fulfilmentOptionCode','LOCAL-CV13',
            'items',jsonb_build_array(
                jsonb_build_object('sku_id','FRYTRAY001-S-G-W-G','qty',1)
            ),
            'customer',jsonb_build_object(
                'name','Test Customer',
                'email','not-an-email',
                'phone','07123456789'
            ),
            'deliveryAddress',jsonb_build_object(
                'address1','1 Test Road',
                'town','Nuneaton',
                'postcode','CV13 0XX',
                'country','GB'
            )
        )
    );

    IF v_result->>'code' <> 'CUSTOMER_EMAIL_INVALID' THEN
        RAISE EXCEPTION 'FAIL 08: expected CUSTOMER_EMAIL_INVALID, got %',v_result;
    END IF;
    RAISE NOTICE 'PASS 08: malformed email rejected';

    v_result := api.SUBMIT_WEB_ORDER(
        'FINATICS',
        jsonb_build_object(
            'idempotencyKey','CUST-VAL-PHONE',
            'fulfilmentOptionCode','LOCAL-CV13',
            'items',jsonb_build_array(
                jsonb_build_object('sku_id','FRYTRAY001-S-G-W-G','qty',1)
            ),
            'customer',jsonb_build_object(
                'name','Test Customer',
                'email','test@example.com',
                'phone','07123'
            ),
            'deliveryAddress',jsonb_build_object(
                'address1','1 Test Road',
                'town','Nuneaton',
                'postcode','CV13 0XX',
                'country','GB'
            )
        )
    );

    IF v_result->>'code' <> 'CUSTOMER_PHONE_INVALID' THEN
        RAISE EXCEPTION 'FAIL 09: expected CUSTOMER_PHONE_INVALID, got %',v_result;
    END IF;
    RAISE NOTICE 'PASS 09: malformed phone rejected';

    v_result := api.SUBMIT_WEB_ORDER(
        'FINATICS',
        jsonb_build_object(
            'idempotencyKey','CUST-VAL-PC',
            'fulfilmentOptionCode','LOCAL-CV13',
            'items',jsonb_build_array(
                jsonb_build_object('sku_id','FRYTRAY001-S-G-W-G','qty',1)
            ),
            'customer',jsonb_build_object(
                'name','Test Customer',
                'email','test@example.com',
                'phone','07123456789'
            ),
            'deliveryAddress',jsonb_build_object(
                'address1','1 Test Road',
                'town','Nuneaton',
                'postcode','BAD',
                'country','GB'
            )
        )
    );

    IF v_result->>'code' <> 'DELIVERY_POSTCODE_INVALID' THEN
        RAISE EXCEPTION 'FAIL 10: expected DELIVERY_POSTCODE_INVALID, got %',v_result;
    END IF;
    RAISE NOTICE 'PASS 10: malformed postcode rejected';

    v_result := api.SUBMIT_WEB_ORDER(
        'FINATICS',
        jsonb_build_object(
            'idempotencyKey','CUST-VAL-COUNTRY',
            'fulfilmentOptionCode','LOCAL-CV13',
            'items',jsonb_build_array(
                jsonb_build_object('sku_id','FRYTRAY001-S-G-W-G','qty',1)
            ),
            'customer',jsonb_build_object(
                'name','Test Customer',
                'email','test@example.com',
                'phone','07123456789'
            ),
            'deliveryAddress',jsonb_build_object(
                'address1','1 Test Road',
                'town','Nuneaton',
                'postcode','CV13 0XX',
                'country','FR'
            )
        )
    );

    IF v_result->>'code' <> 'DELIVERY_COUNTRY_UNSUPPORTED' THEN
        RAISE EXCEPTION 'FAIL 11: expected DELIVERY_COUNTRY_UNSUPPORTED, got %',v_result;
    END IF;
    RAISE NOTICE 'PASS 11: non-GB delivery country rejected';

    SELECT COUNT(*)
      INTO v_before
      FROM interface.ORDER_HEADER_IF
     WHERE CLIENT_ID='FINATICS'
       AND SOURCE_SYSTEM='WEBSITE'
       AND SOURCE_ORDER_ID='CUST-VAL-STALE-LOCAL';

    v_result := api.SUBMIT_WEB_ORDER(
        'FINATICS',
        jsonb_build_object(
            'idempotencyKey','CUST-VAL-STALE-LOCAL',
            'fulfilmentOptionCode','LOCAL-CV13',
            'items',jsonb_build_array(
                jsonb_build_object('sku_id','FRYTRAY001-S-G-W-G','qty',1)
            ),
            'customer',jsonb_build_object(
                'name','Test Customer',
                'email','TEST@EXAMPLE.COM',
                'phone','07123 456789'
            ),
            'deliveryAddress',jsonb_build_object(
                'address1','1 Test Road',
                'town','London',
                'postcode','SW1A 1AA',
                'country','GB'
            )
        )
    );

    IF v_result->>'code' <> 'FULFILMENT_ADDRESS_CHANGED' THEN
        RAISE EXCEPTION 'FAIL 12: expected FULFILMENT_ADDRESS_CHANGED, got %',v_result;
    END IF;

    SELECT COUNT(*)
      INTO v_after
      FROM interface.ORDER_HEADER_IF
     WHERE CLIENT_ID='FINATICS'
       AND SOURCE_SYSTEM='WEBSITE'
       AND SOURCE_ORDER_ID='CUST-VAL-STALE-LOCAL';

    IF v_after <> v_before THEN
        RAISE EXCEPTION 'FAIL 13: stale address rejection created an order/interface row';
    END IF;

    RAISE NOTICE 'PASS 12: stale local-delivery selection rejected against final postcode';
    RAISE NOTICE 'PASS 13: stale address rejection creates no order/interface record';

    v_result := api.SUBMIT_WEB_ORDER(
        'FINATICS',
        jsonb_build_object(
            'idempotencyKey','CUST-VAL-PHONE-CONFLICT',
            'fulfilmentOptionCode','LOCAL-CV13',
            'items',jsonb_build_array(
                jsonb_build_object('sku_id','FRYTRAY001-S-G-W-G','qty',1)
            ),
            'customer',jsonb_build_object(
                'name','Test Customer',
                'email','test@example.com',
                'phone','07123456789',
                'mobile','07987654321'
            ),
            'deliveryAddress',jsonb_build_object(
                'address1','1 Test Road',
                'town','Nuneaton',
                'postcode','CV13 0XX',
                'country','GB'
            )
        )
    );

    IF v_result->>'code' <> 'CUSTOMER_PHONE_CONFLICT' THEN
        RAISE EXCEPTION 'FAIL 14: expected CUSTOMER_PHONE_CONFLICT, got %',v_result;
    END IF;

    RAISE NOTICE 'PASS 14: conflicting phone/mobile values rejected';
END
$$;

ROLLBACK;
