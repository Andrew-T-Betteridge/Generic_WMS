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

/*
  DYNETIC checkout matrix regression
  SAFE: runs inside BEGIN/ROLLBACK and uses current DEV/TEST catalogue data.
  STANDARD, LIVESTOCK and MIXED cases activate automatically when sellable stock exists.
*/

BEGIN;

INSERT INTO config.PROMOTION(
    CLIENT_ID,PROMOTION_ID,PROMO_CODE,DESCRIPTION,
    PROMOTION_TYPE,PROMOTION_VALUE,MIN_ORDER_VALUE
)
VALUES
    ('FINATICS','MATRIX10','MATRIX10','Checkout matrix 10 percent','PERCENT',10,0),
    ('FINATICS','MATRIXFREE','MATRIXFREE','Checkout matrix free delivery','FREE_DELIVERY',0,0)
ON CONFLICT DO NOTHING;

DO $$
DECLARE
    v_standard_sku VARCHAR;
    v_livestock_sku VARCHAR;
    v_standard_available NUMERIC;
    v_livestock_available NUMERIC;
    v_standard_price NUMERIC;
    v_livestock_price NUMERIC;
    v JSONB;
    v2 JSONB;
    v_order_id TEXT;
    v_local_zone TEXT;
    v_local_prefix TEXT;
    v_local_price NUMERIC;
    v_local_postcode TEXT;
    v_livestock_carrier_enabled BOOLEAN := TRUE;
BEGIN
    SELECT pv.SKU_ID, a.AVAILABLE_QTY, pv.WEB_PRICE
      INTO v_standard_sku, v_standard_available, v_standard_price
      FROM core.PRODUCT_VARIANT pv
      JOIN core.PRODUCT p
        ON p.CLIENT_ID=pv.CLIENT_ID AND p.PRODUCT_ID=pv.PRODUCT_ID AND p.ACTIVE=TRUE
      JOIN api.CATALOG_VARIANT_AVAILABILITY a
        ON a.CLIENT_ID=pv.CLIENT_ID AND a.PRODUCT_ID=pv.PRODUCT_ID AND a.SKU_ID=pv.SKU_ID
     WHERE pv.CLIENT_ID='FINATICS'
       AND pv.ACTIVE=TRUE
       AND pv.AVAILABILITY_STATE='AVAILABLE'
       AND UPPER(COALESCE(p.DELIVERY_CLASS,'STANDARD'))='STANDARD'
       AND COALESCE(a.AVAILABLE_QTY,0)>0
     ORDER BY CASE WHEN COALESCE(a.AVAILABLE_QTY,0)>=3 THEN 0 ELSE 1 END,
              a.AVAILABLE_QTY DESC,pv.SKU_ID
     LIMIT 1;

    SELECT pv.SKU_ID, a.AVAILABLE_QTY, pv.WEB_PRICE
      INTO v_livestock_sku, v_livestock_available, v_livestock_price
      FROM core.PRODUCT_VARIANT pv
      JOIN core.PRODUCT p
        ON p.CLIENT_ID=pv.CLIENT_ID AND p.PRODUCT_ID=pv.PRODUCT_ID AND p.ACTIVE=TRUE
      JOIN api.CATALOG_VARIANT_AVAILABILITY a
        ON a.CLIENT_ID=pv.CLIENT_ID AND a.PRODUCT_ID=pv.PRODUCT_ID AND a.SKU_ID=pv.SKU_ID
     WHERE pv.CLIENT_ID='FINATICS'
       AND pv.ACTIVE=TRUE
       AND pv.AVAILABILITY_STATE='AVAILABLE'
       AND UPPER(COALESCE(p.DELIVERY_CLASS,''))='LIVESTOCK'
       AND COALESCE(a.AVAILABLE_QTY,0)>0
     ORDER BY CASE WHEN COALESCE(a.AVAILABLE_QTY,0)>=3 THEN 0 ELSE 1 END,
              a.AVAILABLE_QTY DESC,pv.SKU_ID
     LIMIT 1;

    RAISE NOTICE 'STANDARD representative: % (available %, price %)',
        COALESCE(v_standard_sku,'<none>'),COALESCE(v_standard_available,0),COALESCE(v_standard_price,0);
    RAISE NOTICE 'LIVESTOCK representative: % (available %, price %)',
        COALESCE(v_livestock_sku,'<none>'),COALESCE(v_livestock_available,0),COALESCE(v_livestock_price,0);

    SELECT api.VALIDATE_BASKET('FINATICS','[]'::jsonb) INTO v;
    IF COALESCE((v->>'valid')::BOOLEAN,FALSE) THEN
        RAISE EXCEPTION '01 EMPTY_BASKET unexpectedly valid: %',v;
    END IF;
    RAISE NOTICE 'PASS 01: empty basket rejected';

    IF v_standard_sku IS NULL THEN
        RAISE NOTICE 'SKIP STANDARD cases: no available STANDARD SKU';
    ELSE
        SELECT api.VALIDATE_BASKET(
            'FINATICS',jsonb_build_array(jsonb_build_object('sku_id',v_standard_sku,'qty',1))
        ) INTO v;
        IF NOT COALESCE((v->>'valid')::BOOLEAN,FALSE)
           OR NOT COALESCE((v->>'hasStandard')::BOOLEAN,FALSE)
           OR COALESCE((v->>'hasLivestock')::BOOLEAN,FALSE) THEN
            RAISE EXCEPTION '02 STANDARD classification failed: %',v;
        END IF;
        RAISE NOTICE 'PASS 02: STANDARD classification';

        SELECT api.VALIDATE_BASKET(
            'FINATICS',jsonb_build_array(jsonb_build_object('sku_id',v_standard_sku,'qty',v_standard_available+1))
        ) INTO v;
        IF COALESCE((v->>'valid')::BOOLEAN,FALSE)
           OR NOT EXISTS (
               SELECT 1 FROM jsonb_array_elements(COALESCE(v->'errors','[]'::jsonb)) e
               WHERE e->>'code'='INSUFFICIENT_STOCK'
           ) THEN
            RAISE EXCEPTION '03 insufficient stock not rejected: %',v;
        END IF;
        RAISE NOTICE 'PASS 03: STANDARD insufficient stock';

        SELECT api.GET_DELIVERY_OPTIONS(
            'FINATICS',jsonb_build_object(
                'items',jsonb_build_array(jsonb_build_object('sku_id',v_standard_sku,'qty',1)),
                'deliveryAddress',jsonb_build_object('postcode','CV13 0AA','country','GB')
            )
        ) INTO v;
        IF NOT COALESCE((v->>'valid')::BOOLEAN,FALSE)
           OR NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v->'fulfilmentOptions') e WHERE e->>'code'='COLLECTION')
           OR NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v->'fulfilmentOptions') e WHERE e->>'code'='STANDARD_CARRIER') THEN
            RAISE EXCEPTION '04 STANDARD delivery options incorrect: %',v;
        END IF;
        RAISE NOTICE 'PASS 04: STANDARD delivery options';

        SELECT api.QUOTE_CHECKOUT(
            'FINATICS',jsonb_build_object(
                'items',jsonb_build_array(jsonb_build_object('sku_id',v_standard_sku,'qty',1)),
                'deliveryAddress',jsonb_build_object('postcode','CV13 0AA','country','GB'),
                'fulfilmentOptionCode','COLLECTION'
            )
        ) INTO v;
        IF NOT COALESCE((v->>'valid')::BOOLEAN,FALSE)
           OR NOT COALESCE((v->>'paymentReady')::BOOLEAN,FALSE)
           OR COALESCE((v->>'freightCost')::NUMERIC,-1)<>0
           OR (v->>'total')::NUMERIC<>(v->>'totalBeforeDelivery')::NUMERIC THEN
            RAISE EXCEPTION '05 STANDARD collection quote incorrect: %',v;
        END IF;
        RAISE NOTICE 'PASS 05: STANDARD collection quote';

        SELECT api.QUOTE_CHECKOUT(
            'FINATICS',jsonb_build_object(
                'items',jsonb_build_array(jsonb_build_object('sku_id',v_standard_sku,'qty',1)),
                'deliveryAddress',jsonb_build_object('postcode','CV13 0AA','country','GB'),
                'fulfilmentOptionCode','STANDARD_CARRIER'
            )
        ) INTO v;
        IF NOT COALESCE((v->>'valid')::BOOLEAN,FALSE)
           OR COALESCE((v->>'paymentReady')::BOOLEAN,FALSE)
           OR v->'total' IS DISTINCT FROM 'null'::jsonb THEN
            RAISE EXCEPTION '06 STANDARD carrier should be pending price: %',v;
        END IF;
        RAISE NOTICE 'PASS 06: unpriced STANDARD carrier blocked';

        SELECT api.QUOTE_CHECKOUT(
            'FINATICS',jsonb_build_object(
                'items',jsonb_build_array(jsonb_build_object('sku_id',v_standard_sku,'qty',1)),
                'deliveryAddress',jsonb_build_object('postcode','CV13 0AA','country','GB'),
                'promoCode','MATRIX10','fulfilmentOptionCode','COLLECTION'
            )
        ) INTO v;
        IF NOT COALESCE((v->>'valid')::BOOLEAN,FALSE)
           OR COALESCE((v->>'discountAmount')::NUMERIC,0)<=0
           OR (v->>'total')::NUMERIC<>(v->>'totalBeforeDelivery')::NUMERIC THEN
            RAISE EXCEPTION '07 promotion quote incorrect: %',v;
        END IF;
        RAISE NOTICE 'PASS 07: percentage promotion';

        SELECT api.CREATE_PENDING_WEB_ORDER(
            'FINATICS',jsonb_build_object(
                'idempotencyKey','MATRIX-STANDARD-ORDER',
                'items',jsonb_build_array(jsonb_build_object('sku_id',v_standard_sku,'qty',1)),
                'customer',jsonb_build_object('name','Matrix Standard','email','matrix-standard@example.invalid'),
                'deliveryAddress',jsonb_build_object('name','Matrix Standard','address1','1 Test Street','town','Hinckley','postcode','CV13 0AA','country','GB'),
                'fulfilmentOptionCode','COLLECTION','fulfilmentPreference','CONSOLIDATE'
            ),NULL,30
        ) INTO v;
        IF v->>'status'<>'PENDING_PAYMENT' OR NOT COALESCE((v->>'stockReserved')::BOOLEAN,FALSE) THEN
            RAISE EXCEPTION '08 STANDARD pending order failed: %',v;
        END IF;
        v_order_id:=v->>'orderId';

        SELECT api.CREATE_PENDING_WEB_ORDER(
            'FINATICS',jsonb_build_object(
                'idempotencyKey','MATRIX-STANDARD-ORDER',
                'items',jsonb_build_array(jsonb_build_object('sku_id',v_standard_sku,'qty',1)),
                'customer',jsonb_build_object('name','Matrix Standard','email','matrix-standard@example.invalid'),
                'deliveryAddress',jsonb_build_object('name','Matrix Standard','address1','1 Test Street','town','Hinckley','postcode','CV13 0AA','country','GB'),
                'fulfilmentOptionCode','COLLECTION','fulfilmentPreference','CONSOLIDATE'
            ),NULL,30
        ) INTO v2;
        IF v2->>'orderId'<>v_order_id OR NOT COALESCE((v2->>'idempotentReplay')::BOOLEAN,FALSE) THEN
            RAISE EXCEPTION '08 idempotent replay failed. first %, second %',v,v2;
        END IF;
        PERFORM core.DEALLOCATE_ORDER('FINATICS',v_order_id);
        RAISE NOTICE 'PASS 08: order reservation + idempotent replay';

        SELECT dz.ZONE_ID,dz.POSTCODE_PREFIX,dz.DELIVERY_PRICE
          INTO v_local_zone,v_local_prefix,v_local_price
          FROM config.DELIVERY_ZONE dz
         WHERE dz.CLIENT_ID='FINATICS' AND dz.ACTIVE=TRUE
           AND UPPER(dz.COUNTRY)='GB' AND dz.DELIVERY_PRICE IS NOT NULL
           AND UPPER(dz.FULFILMENT_METHOD)='LOCAL_DELIVERY'
           AND (dz.MIN_ORDER_VALUE IS NULL OR v_standard_price>=dz.MIN_ORDER_VALUE)
         ORDER BY dz.PRIORITY,dz.ZONE_ID LIMIT 1;

        IF v_local_zone IS NULL THEN
            RAISE NOTICE 'SKIP 09/10: no priced LOCAL_DELIVERY zone eligible for one STANDARD unit';
        ELSE
            v_local_postcode:=CASE
                WHEN NULLIF(TRIM(v_local_prefix),'') IS NULL THEN 'CV13 0AA'
                ELSE regexp_replace(UPPER(v_local_prefix),'[[:space:]]','','g')||' 0AA'
            END;

            SELECT api.QUOTE_CHECKOUT(
                'FINATICS',jsonb_build_object(
                    'items',jsonb_build_array(jsonb_build_object('sku_id',v_standard_sku,'qty',1)),
                    'deliveryAddress',jsonb_build_object('postcode',v_local_postcode,'country','GB'),
                    'fulfilmentOptionCode',v_local_zone
                )
            ) INTO v;
            IF NOT COALESCE((v->>'valid')::BOOLEAN,FALSE)
               OR NOT COALESCE((v->>'paymentReady')::BOOLEAN,FALSE)
               OR COALESCE((v->>'freightCost')::NUMERIC,-1)<>v_local_price
               OR (v->>'total')::NUMERIC<>((v->>'totalBeforeDelivery')::NUMERIC+v_local_price) THEN
                RAISE EXCEPTION '09 local delivery quote incorrect: %',v;
            END IF;
            RAISE NOTICE 'PASS 09: priced local delivery % = %',v_local_zone,v_local_price;

            SELECT api.QUOTE_CHECKOUT(
                'FINATICS',jsonb_build_object(
                    'items',jsonb_build_array(jsonb_build_object('sku_id',v_standard_sku,'qty',1)),
                    'deliveryAddress',jsonb_build_object('postcode',v_local_postcode,'country','GB'),
                    'promoCode','MATRIXFREE','fulfilmentOptionCode',v_local_zone
                )
            ) INTO v;
            IF NOT COALESCE((v->>'valid')::BOOLEAN,FALSE)
               OR NOT COALESCE((v->>'paymentReady')::BOOLEAN,FALSE)
               OR NOT COALESCE((v->>'freeDelivery')::BOOLEAN,FALSE)
               OR COALESCE((v->>'freightCost')::NUMERIC,-1)<>0
               OR (v->>'total')::NUMERIC<>(v->>'totalBeforeDelivery')::NUMERIC THEN
                RAISE EXCEPTION '10 free delivery promotion incorrect: %',v;
            END IF;
            RAISE NOTICE 'PASS 10: free-delivery promotion';
        END IF;
    END IF;

    IF v_livestock_sku IS NULL THEN
        RAISE NOTICE 'SKIP 11-15: no available LIVESTOCK SKU. Add real fish stock to DEV and rerun.';
    ELSE
        SELECT CARRIER_DESPATCH_ENABLED INTO v_livestock_carrier_enabled
          FROM config.DELIVERY_CLASS_CONTROL
         WHERE CLIENT_ID='FINATICS' AND UPPER(DELIVERY_CLASS)='LIVESTOCK';
        IF NOT FOUND THEN v_livestock_carrier_enabled:=TRUE; END IF;

        SELECT api.VALIDATE_BASKET(
            'FINATICS',jsonb_build_array(jsonb_build_object('sku_id',v_livestock_sku,'qty',1))
        ) INTO v;
        IF NOT COALESCE((v->>'valid')::BOOLEAN,FALSE)
           OR COALESCE((v->>'hasStandard')::BOOLEAN,FALSE)
           OR NOT COALESCE((v->>'hasLivestock')::BOOLEAN,FALSE) THEN
            RAISE EXCEPTION '11 LIVESTOCK classification failed: %',v;
        END IF;
        RAISE NOTICE 'PASS 11: LIVESTOCK classification';

        SELECT api.GET_DELIVERY_OPTIONS(
            'FINATICS',jsonb_build_object(
                'items',jsonb_build_array(jsonb_build_object('sku_id',v_livestock_sku,'qty',1)),
                'deliveryAddress',jsonb_build_object('postcode','CV13 0AA','country','GB')
            )
        ) INTO v;
        IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v->'fulfilmentOptions') e WHERE e->>'code'='COLLECTION')
           OR NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v->'fulfilmentOptions') e WHERE e->>'code'='MEET_POINT')
           OR (v_livestock_carrier_enabled AND NOT EXISTS (
                SELECT 1 FROM jsonb_array_elements(v->'fulfilmentOptions') e WHERE e->>'code'='LIVESTOCK_CARRIER'
           )) THEN
            RAISE EXCEPTION '12 LIVESTOCK delivery options incorrect: %',v;
        END IF;
        RAISE NOTICE 'PASS 12: LIVESTOCK delivery options';

        SELECT api.QUOTE_CHECKOUT(
            'FINATICS',jsonb_build_object(
                'items',jsonb_build_array(jsonb_build_object('sku_id',v_livestock_sku,'qty',1)),
                'deliveryAddress',jsonb_build_object('postcode','CV13 0AA','country','GB'),
                'fulfilmentOptionCode','COLLECTION'
            )
        ) INTO v;
        IF NOT COALESCE((v->>'paymentReady')::BOOLEAN,FALSE)
           OR COALESCE((v->>'freightCost')::NUMERIC,-1)<>0 THEN
            RAISE EXCEPTION '13 LIVESTOCK collection quote incorrect: %',v;
        END IF;
        RAISE NOTICE 'PASS 13: LIVESTOCK collection quote';

        IF v_livestock_carrier_enabled THEN
            SELECT api.QUOTE_CHECKOUT(
                'FINATICS',jsonb_build_object(
                    'items',jsonb_build_array(jsonb_build_object('sku_id',v_livestock_sku,'qty',1)),
                    'deliveryAddress',jsonb_build_object('postcode','CV13 0AA','country','GB'),
                    'fulfilmentOptionCode','LIVESTOCK_CARRIER'
                )
            ) INTO v;
            IF COALESCE((v->>'paymentReady')::BOOLEAN,FALSE) THEN
                RAISE EXCEPTION '14 LIVESTOCK carrier unexpectedly payment ready: %',v;
            END IF;
        END IF;

        SELECT api.QUOTE_CHECKOUT(
            'FINATICS',jsonb_build_object(
                'items',jsonb_build_array(jsonb_build_object('sku_id',v_livestock_sku,'qty',1)),
                'deliveryAddress',jsonb_build_object('postcode','CV13 0AA','country','GB'),
                'fulfilmentOptionCode','MEET_POINT'
            )
        ) INTO v;
        IF COALESCE((v->>'paymentReady')::BOOLEAN,FALSE) THEN
            RAISE EXCEPTION '14 MEET_POINT unexpectedly payment ready: %',v;
        END IF;
        RAISE NOTICE 'PASS 14: unpriced LIVESTOCK/manual options blocked';

        SELECT api.CREATE_PENDING_WEB_ORDER(
            'FINATICS',jsonb_build_object(
                'idempotencyKey','MATRIX-LIVESTOCK-ORDER',
                'items',jsonb_build_array(jsonb_build_object('sku_id',v_livestock_sku,'qty',1)),
                'customer',jsonb_build_object('name','Matrix Livestock','email','matrix-livestock@example.invalid'),
                'deliveryAddress',jsonb_build_object('name','Matrix Livestock','address1','1 Test Street','town','Hinckley','postcode','CV13 0AA','country','GB'),
                'fulfilmentOptionCode','COLLECTION','fulfilmentPreference','CONSOLIDATE'
            ),NULL,30
        ) INTO v;
        IF v->>'status'<>'PENDING_PAYMENT' OR v->>'fulfilmentMethod'<>'COLLECTION'
           OR NOT COALESCE((v->>'stockReserved')::BOOLEAN,FALSE) THEN
            RAISE EXCEPTION '15 LIVESTOCK collection order failed: %',v;
        END IF;
        PERFORM core.DEALLOCATE_ORDER('FINATICS',v->>'orderId');
        RAISE NOTICE 'PASS 15: LIVESTOCK order reserves stock';
    END IF;

    IF v_standard_sku IS NULL OR v_livestock_sku IS NULL THEN
        RAISE NOTICE 'SKIP 16-18: need both available STANDARD and LIVESTOCK SKUs';
    ELSE
        SELECT api.VALIDATE_BASKET(
            'FINATICS',jsonb_build_array(
                jsonb_build_object('sku_id',v_standard_sku,'qty',1),
                jsonb_build_object('sku_id',v_livestock_sku,'qty',1)
            )
        ) INTO v;
        IF NOT COALESCE((v->>'valid')::BOOLEAN,FALSE)
           OR NOT COALESCE((v->>'hasStandard')::BOOLEAN,FALSE)
           OR NOT COALESCE((v->>'hasLivestock')::BOOLEAN,FALSE) THEN
            RAISE EXCEPTION '16 MIXED classification failed: %',v;
        END IF;
        RAISE NOTICE 'PASS 16: MIXED classification';

        SELECT api.QUOTE_CHECKOUT(
            'FINATICS',jsonb_build_object(
                'items',jsonb_build_array(
                    jsonb_build_object('sku_id',v_standard_sku,'qty',1),
                    jsonb_build_object('sku_id',v_livestock_sku,'qty',1)
                ),
                'deliveryAddress',jsonb_build_object('postcode','CV13 0AA','country','GB'),
                'fulfilmentOptionCode','COLLECTION'
            )
        ) INTO v;
        IF NOT COALESCE((v->>'valid')::BOOLEAN,FALSE)
           OR NOT COALESCE((v->>'paymentReady')::BOOLEAN,FALSE)
           OR COALESCE((v->>'freightCost')::NUMERIC,-1)<>0 THEN
            RAISE EXCEPTION '17 MIXED collection quote failed: %',v;
        END IF;
        RAISE NOTICE 'PASS 17: MIXED collection quote';

        SELECT api.CREATE_PENDING_WEB_ORDER(
            'FINATICS',jsonb_build_object(
                'idempotencyKey','MATRIX-MIXED-ORDER',
                'items',jsonb_build_array(
                    jsonb_build_object('sku_id',v_standard_sku,'qty',1),
                    jsonb_build_object('sku_id',v_livestock_sku,'qty',1)
                ),
                'customer',jsonb_build_object('name','Matrix Mixed','email','matrix-mixed@example.invalid'),
                'deliveryAddress',jsonb_build_object('name','Matrix Mixed','address1','1 Test Street','town','Hinckley','postcode','CV13 0AA','country','GB'),
                'fulfilmentOptionCode','COLLECTION','fulfilmentPreference','SPLIT_WHEN_REQUIRED'
            ),NULL,30
        ) INTO v;
        IF v->>'status'<>'PENDING_PAYMENT' OR NOT COALESCE((v->>'stockReserved')::BOOLEAN,FALSE) THEN
            RAISE EXCEPTION '18 MIXED order failed: %',v;
        END IF;
        v_order_id:=v->>'orderId';
        IF NOT EXISTS (
            SELECT 1 FROM core.ORDER_HEADER
            WHERE CLIENT_ID='FINATICS' AND ORDER_ID=v_order_id
              AND FULFILMENT_PREFERENCE='SPLIT_WHEN_REQUIRED'
        ) THEN
            RAISE EXCEPTION '18 SPLIT_WHEN_REQUIRED not persisted for %',v_order_id;
        END IF;
        IF (
            SELECT COUNT(*) FROM core.ORDER_LINE
            WHERE CLIENT_ID='FINATICS' AND ORDER_ID=v_order_id
              AND SKU_ID IN (v_standard_sku,v_livestock_sku)
        )<>2 THEN
            RAISE EXCEPTION '18 expected two mixed order lines for %',v_order_id;
        END IF;
        PERFORM core.DEALLOCATE_ORDER('FINATICS',v_order_id);
        RAISE NOTICE 'PASS 18: MIXED order + SPLIT_WHEN_REQUIRED';
    END IF;

    RAISE NOTICE '============================================================';
    RAISE NOTICE 'CHECKOUT MATRIX COMPLETE';
    RAISE NOTICE 'SKIP means the current catalogue lacks that live test fixture.';
    RAISE NOTICE '============================================================';
END
$$;

ROLLBACK;
