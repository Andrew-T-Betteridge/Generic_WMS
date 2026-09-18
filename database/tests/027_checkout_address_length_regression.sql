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

-- This regression uses the FINATICS TEST checkout fixture and is deliberately
-- stricter than the universal non-production guard above.
DO $dynetic_test_only_guard$
DECLARE
    v_database text := current_database();
BEGIN
    IF v_database <> 'fulfilment_test' THEN
        RAISE EXCEPTION
            'SAFETY STOP: checkout address-length regression is allowed only against fulfilment_test. Current database: %',
            v_database;
    END IF;

    RAISE NOTICE
        'SAFETY: checkout address-length TEST database verified as %',
        v_database;
END
$dynetic_test_only_guard$;

BEGIN;

DO $$
DECLARE
    v_result JSONB;
    v_created INTEGER;
BEGIN
    --------------------------------------------------------------------------
    -- EXACTLY 60 CHARACTERS MUST NOT TRIGGER A STORAGE-LENGTH ERROR
    --------------------------------------------------------------------------
    v_result := api.SUBMIT_WEB_ORDER(
        'FINATICS',
        jsonb_build_object(
            'idempotencyKey','ADDR-LEN-60-ALL',
            'fulfilmentOptionCode','COLLECTION',
            'items',jsonb_build_array(
                jsonb_build_object('sku_id','__ADDRESS_LENGTH_TEST_INVALID_SKU__','qty',1)
            ),
            'customer',jsonb_build_object(
                'name','Address Length Test',
                'email','address.length@example.com',
                'phone','07123456789'
            ),
            'deliveryAddress',jsonb_build_object(
                'address1',repeat('A',60),
                'address2',repeat('B',60),
                'town',repeat('C',60),
                'county',repeat('D',60),
                'postcode','CV13 0XX',
                'country','GB'
            )
        )
    );

    IF COALESCE(v_result->>'code','') IN (
        'DELIVERY_ADDRESS1_TOO_LONG',
        'DELIVERY_ADDRESS2_TOO_LONG',
        'DELIVERY_TOWN_TOO_LONG',
        'DELIVERY_COUNTY_TOO_LONG'
    ) THEN
        RAISE EXCEPTION 'FAIL 01: exactly 60 characters was rejected: %', v_result;
    END IF;
    RAISE NOTICE 'PASS 01: exactly 60 characters does not trigger address-length rejection';

    --------------------------------------------------------------------------
    -- 61 CHARACTERS MUST RETURN THE FIELD-SPECIFIC STRUCTURED CODE
    --------------------------------------------------------------------------
    v_result := api.SUBMIT_WEB_ORDER(
        'FINATICS',
        jsonb_build_object(
            'idempotencyKey','ADDR-LEN-61-ADDRESS1',
            'fulfilmentOptionCode','COLLECTION',
            'items',jsonb_build_array(
                jsonb_build_object('sku_id','__ADDRESS_LENGTH_TEST_INVALID_SKU__','qty',1)
            ),
            'customer',jsonb_build_object(
                'name','Address Length Test',
                'email','address.length@example.com',
                'phone','07123456789'
            ),
            'deliveryAddress',jsonb_build_object(
                'address1',repeat('A',61),
                'town','Nuneaton',
                'postcode','CV13 0XX',
                'country','GB'
            )
        )
    );

    IF v_result->>'code' <> 'DELIVERY_ADDRESS1_TOO_LONG' THEN
        RAISE EXCEPTION 'FAIL 02: expected DELIVERY_ADDRESS1_TOO_LONG, got %', v_result;
    END IF;
    RAISE NOTICE 'PASS 02: 61-character address1 rejected';

    v_result := api.SUBMIT_WEB_ORDER(
        'FINATICS',
        jsonb_build_object(
            'idempotencyKey','ADDR-LEN-61-ADDRESS2',
            'fulfilmentOptionCode','COLLECTION',
            'items',jsonb_build_array(
                jsonb_build_object('sku_id','__ADDRESS_LENGTH_TEST_INVALID_SKU__','qty',1)
            ),
            'customer',jsonb_build_object(
                'name','Address Length Test',
                'email','address.length@example.com',
                'phone','07123456789'
            ),
            'deliveryAddress',jsonb_build_object(
                'address1','1 Test Road',
                'address2',repeat('B',61),
                'town','Nuneaton',
                'postcode','CV13 0XX',
                'country','GB'
            )
        )
    );

    IF v_result->>'code' <> 'DELIVERY_ADDRESS2_TOO_LONG' THEN
        RAISE EXCEPTION 'FAIL 03: expected DELIVERY_ADDRESS2_TOO_LONG, got %', v_result;
    END IF;
    RAISE NOTICE 'PASS 03: 61-character address2 rejected';

    v_result := api.SUBMIT_WEB_ORDER(
        'FINATICS',
        jsonb_build_object(
            'idempotencyKey','ADDR-LEN-61-TOWN',
            'fulfilmentOptionCode','COLLECTION',
            'items',jsonb_build_array(
                jsonb_build_object('sku_id','__ADDRESS_LENGTH_TEST_INVALID_SKU__','qty',1)
            ),
            'customer',jsonb_build_object(
                'name','Address Length Test',
                'email','address.length@example.com',
                'phone','07123456789'
            ),
            'deliveryAddress',jsonb_build_object(
                'address1','1 Test Road',
                'town',repeat('C',61),
                'postcode','CV13 0XX',
                'country','GB'
            )
        )
    );

    IF v_result->>'code' <> 'DELIVERY_TOWN_TOO_LONG' THEN
        RAISE EXCEPTION 'FAIL 04: expected DELIVERY_TOWN_TOO_LONG, got %', v_result;
    END IF;
    RAISE NOTICE 'PASS 04: 61-character town rejected';

    v_result := api.SUBMIT_WEB_ORDER(
        'FINATICS',
        jsonb_build_object(
            'idempotencyKey','ADDR-LEN-61-COUNTY',
            'fulfilmentOptionCode','COLLECTION',
            'items',jsonb_build_array(
                jsonb_build_object('sku_id','__ADDRESS_LENGTH_TEST_INVALID_SKU__','qty',1)
            ),
            'customer',jsonb_build_object(
                'name','Address Length Test',
                'email','address.length@example.com',
                'phone','07123456789'
            ),
            'deliveryAddress',jsonb_build_object(
                'address1','1 Test Road',
                'town','Nuneaton',
                'county',repeat('D',61),
                'postcode','CV13 0XX',
                'country','GB'
            )
        )
    );

    IF v_result->>'code' <> 'DELIVERY_COUNTY_TOO_LONG' THEN
        RAISE EXCEPTION 'FAIL 05: expected DELIVERY_COUNTY_TOO_LONG, got %', v_result;
    END IF;
    RAISE NOTICE 'PASS 05: 61-character county rejected';

    --------------------------------------------------------------------------
    -- NO REJECTED OVER-LENGTH ATTEMPT MAY CREATE AN INTERFACE ORDER
    --------------------------------------------------------------------------
    SELECT COUNT(*)
      INTO v_created
      FROM interface.ORDER_HEADER_IF
     WHERE CLIENT_ID='FINATICS'
       AND SOURCE_SYSTEM='WEBSITE'
       AND SOURCE_ORDER_ID LIKE 'ADDR-LEN-61-%';

    IF v_created <> 0 THEN
        RAISE EXCEPTION 'FAIL 06: over-length address validation created % interface order(s)', v_created;
    END IF;

    RAISE NOTICE 'PASS 06: over-length address rejection creates no order/interface row';
END
$$;

ROLLBACK;
