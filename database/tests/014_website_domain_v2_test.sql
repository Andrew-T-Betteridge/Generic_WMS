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
\ir ../seeds/001_finatics_fry_tray.sql

INSERT INTO core.LOCATION(LOCATION_ID,LOC_TYPE,LOCK_STATUS,VOLUME,DISALLOW_ALLOC,COUNT_NEEDED,ID,DESCRIPTION,ACTIVE,LIVESTOCK_ALLOWED)
VALUES('WEB-V2-LOC','STORAGE','UNLOCKED',1000000,'N','N',991402,'Website Domain V2 Test','Y','Y') ON CONFLICT (LOCATION_ID) DO NOTHING;
INSERT INTO core.INVENTORY(CLIENT_ID,SKU_ID,SITE_ID,LOCATION_ID,QTY_ON_HAND,QTY_ALLOCATED,LOCK_STATUS,RECEIPT_DSTAMP,MOVE_DSTAMP,DISALLOW_ALLOC)
VALUES('FINATICS','FRYTRAY001-S-G-W-G','WEB','WEB-V2-LOC',10,0,'UNLOCKED',now(),now(),'N');

INSERT INTO core.PRODUCT_SEARCH_ALIAS(CLIENT_ID,PRODUCT_ID,ALIAS_TEXT,ALIAS_TYPE) VALUES('FINATICS','FRYTRAY001','fry breeder tray','COMMON_NAME') ON CONFLICT DO NOTHING;
INSERT INTO core.PRODUCT_MEDIA(CLIENT_ID,PRODUCT_ID,MEDIA_TYPE,MEDIA_ROLE,MEDIA_URL,ALT_TEXT,SORT_SEQUENCE) VALUES('FINATICS','FRYTRAY001','IMAGE','HERO','https://example.invalid/frytray.jpg','FINatics Fry Tray',10);

DO $$ DECLARE j JSONB; BEGIN
 SELECT api.GET_CATEGORIES('FINATICS') INTO j; IF jsonb_array_length(j)<1 THEN RAISE EXCEPTION 'Categories API failed: %',j; END IF;
 SELECT api.SEARCH_CATALOG('FINATICS','fry breeder',NULL,NULL,NULL) INTO j; IF jsonb_array_length(j)<>1 THEN RAISE EXCEPTION 'Search alias failed: %',j; END IF;
 SELECT api.GET_PRODUCT_MEDIA('FINATICS','FRYTRAY001') INTO j; IF jsonb_array_length(j)<>1 THEN RAISE EXCEPTION 'Media API failed: %',j; END IF;
 SELECT api.GET_PRODUCT('FINATICS','finatics-aquatics-air-driven-fry-tray') INTO j; IF j->>'productType' IS NULL OR jsonb_array_length(j->'variants')<>22 THEN RAISE EXCEPTION 'Enhanced product API failed: %',j; END IF;
END $$;

DO $$ DECLARE j JSONB; BEGIN
 SELECT api.CREATE_CUSTOMER_INTEREST('FINATICS','{"interestType":"WAITLIST","productId":"FRYTRAY001","skuId":"FRYTRAY001-S-G-W-G","requestedQty":2,"email":"wait@example.invalid","preferredChannel":"EMAIL"}'::jsonb) INTO j;
 IF j->>'status'<>'ACTIVE' THEN RAISE EXCEPTION 'Interest create failed: %',j; END IF;
 SELECT api.GET_INTEREST_SUMMARY('FINATICS','FRYTRAY001-S-G-W-G') INTO j; IF (j->>'activeCount')::int<>1 THEN RAISE EXCEPTION 'Interest summary failed: %',j; END IF;
END $$;

INSERT INTO config.DELIVERY_ZONE(CLIENT_ID,ZONE_ID,ZONE_NAME,FULFILMENT_METHOD,COUNTRY,POSTCODE_PREFIX,MIN_ORDER_VALUE,DELIVERY_PRICE,CURRENCY,REQUIRES_MANUAL_CONFIRMATION,PRIORITY)
VALUES('FINATICS','LOCAL-CV13','Local delivery','LOCAL_DELIVERY','GB','CV13',20,5,'GBP',FALSE,10);

DO $$ DECLARE j JSONB; BEGIN
 SELECT api.GET_DELIVERY_OPTIONS('FINATICS','{"items":[{"sku_id":"FRYTRAY001-S-G-W-G","qty":1}],"deliveryAddress":{"postcode":"CV13 0AA","country":"GB"}}'::jsonb) INTO j;
 IF NOT (j->>'valid')::boolean OR jsonb_array_length(j->'fulfilmentOptions')<2 THEN RAISE EXCEPTION 'Delivery options failed: %',j; END IF;
END $$;

INSERT INTO config.PROMOTION(CLIENT_ID,PROMOTION_ID,PROMO_CODE,DESCRIPTION,PROMOTION_TYPE,PROMOTION_VALUE,MIN_ORDER_VALUE)
VALUES('FINATICS','WELCOME10','WELCOME10','Test 10 percent','PERCENT',10,20);
INSERT INTO core.GIFT_CARD(CLIENT_ID,GIFT_CODE,ORIGINAL_VALUE,BALANCE) VALUES('FINATICS','TEST-GIFT-25',25,25);

DO $$ DECLARE j JSONB; BEGIN
 SELECT api.VALIDATE_PROMOTION('FINATICS','WELCOME10',26.99,NULL) INTO j; IF NOT (j->>'valid')::boolean OR (j->>'discountAmount')::numeric<>2.70 THEN RAISE EXCEPTION 'Promotion failed: %',j; END IF;
 SELECT api.GET_GIFT_CARD_BALANCE('FINATICS','TEST-GIFT-25') INTO j; IF NOT (j->>'valid')::boolean OR (j->>'balance')::numeric<>25 THEN RAISE EXCEPTION 'Gift card failed: %',j; END IF;
END $$;

DO $$ DECLARE j JSONB; rid UUID; before_q NUMERIC; during_q NUMERIC; after_q NUMERIC; BEGIN
 SELECT QTY_ALLOCATED INTO before_q FROM core.INVENTORY WHERE CLIENT_ID='FINATICS' AND SKU_ID='FRYTRAY001-S-G-W-G' ORDER BY KEY DESC LIMIT 1;
 SELECT api.CREATE_STOCK_RESERVATION('FINATICS','{"idempotencyKey":"V2-RES-001","holdMinutes":60,"customer":{"name":"Test","email":"reserve@example.invalid"},"fulfilmentMethod":"COLLECTION","items":[{"sku_id":"FRYTRAY001-S-G-W-G","qty":2}]}'::jsonb) INTO j;
 rid:=(j->>'reservationId')::uuid; IF rid IS NULL OR j->>'status'<>'ACTIVE' THEN RAISE EXCEPTION 'Reservation failed: %',j; END IF;
 SELECT QTY_ALLOCATED INTO during_q FROM core.INVENTORY WHERE CLIENT_ID='FINATICS' AND SKU_ID='FRYTRAY001-S-G-W-G' ORDER BY KEY DESC LIMIT 1;
 IF during_q-before_q<>2 THEN RAISE EXCEPTION 'Reservation did not allocate inventory. before %, during %',before_q,during_q; END IF;
 SELECT api.RELEASE_STOCK_RESERVATION('FINATICS',rid,'RELEASED') INTO j;
 SELECT QTY_ALLOCATED INTO after_q FROM core.INVENTORY WHERE CLIENT_ID='FINATICS' AND SKU_ID='FRYTRAY001-S-G-W-G' ORDER BY KEY DESC LIMIT 1;
 IF after_q<>before_q OR j->>'status'<>'RELEASED' THEN RAISE EXCEPTION 'Reservation release failed: %, before %, after %',j,before_q,after_q; END IF;
END $$;


DO $$ DECLARE j JSONB; rid UUID; BEGIN
 SELECT api.CREATE_STOCK_RESERVATION('FINATICS','{"idempotencyKey":"V2-RES-CONVERT","holdMinutes":60,"customer":{"name":"Convert Test","email":"convert@example.invalid"},"fulfilmentMethod":"COLLECTION","items":[{"sku_id":"FRYTRAY001-S-G-W-G","qty":1}]}'::jsonb) INTO j;
 rid:=(j->>'reservationId')::uuid;
 SELECT api.SUBMIT_RESERVED_WEB_ORDER('FINATICS',rid,'{"idempotencyKey":"V2-ORDER-CONVERT","customer":{"name":"Convert Test","email":"convert@example.invalid"},"deliveryAddress":{"name":"Convert Test","address1":"1 Test Street","town":"Hinckley","postcode":"CV13 0AA","country":"GB"},"fulfilmentMethod":"COLLECTION","fulfilmentPreference":"CONSOLIDATE"}'::jsonb) INTO j;
 IF j->>'status'<>'ACCEPTED' OR NOT COALESCE((j->>'reservationConverted')::boolean,FALSE) OR j->>'allocationStatus'<>'ALLOCATED' THEN RAISE EXCEPTION 'Reservation conversion failed: %',j; END IF;
 IF NOT EXISTS(SELECT 1 FROM core.STOCK_RESERVATION WHERE RESERVATION_ID=rid AND STATUS='CONVERTED' AND CONVERTED_ORDER_ID=j->>'orderId') THEN RAISE EXCEPTION 'Reservation was not marked converted'; END IF;
END $$;

DO $$ DECLARE link UUID; j JSONB; BEGIN
 INSERT INTO core.PRODUCT_AFFILIATE_LINK(CLIENT_ID,PRODUCT_ID,MERCHANT_NAME,DESTINATION_URL,CAMPAIGN_CODE) VALUES('FINATICS','FRYTRAY001','TEST MERCHANT','https://example.invalid/product','TEST') RETURNING LINK_ID INTO link;
 SELECT api.RECORD_AFFILIATE_CLICK('FINATICS',link,'{"sessionId":"abc","source":"product-page"}'::jsonb) INTO j; IF j->>'destinationUrl'<>'https://example.invalid/product' THEN RAISE EXCEPTION 'Affiliate click failed: %',j; END IF;
END $$;

DO $$ DECLARE j JSONB; review UUID; BEGIN
 SELECT api.SUBMIT_PRODUCT_REVIEW('FINATICS','finatics-aquatics-air-driven-fry-tray','{"email":"review@example.invalid","displayName":"Tester","rating":5,"title":"Great","text":"Test review"}'::jsonb) INTO j; review:=(j->>'reviewId')::uuid;
 UPDATE core.PRODUCT_REVIEW SET STATUS='APPROVED',PUBLISHED_DSTAMP=now() WHERE REVIEW_ID=review;
 SELECT api.GET_PRODUCT_REVIEWS('FINATICS','finatics-aquatics-air-driven-fry-tray') INTO j; IF (j->>'reviewCount')::int<>1 OR (j->>'averageRating')::numeric<>5 THEN RAISE EXCEPTION 'Reviews failed: %',j; END IF;
END $$;

DO $$ DECLARE j JSONB; BEGIN
 SELECT api.SET_CONTACT_PREFERENCE('FINATICS','{"contactType":"EMAIL","contactValue":"customer@example.invalid","channel":"EMAIL","purpose":"MARKETING","optedIn":true}'::jsonb) INTO j; IF NOT (j->>'saved')::boolean THEN RAISE EXCEPTION 'Preference failed'; END IF;
 SELECT api.PREPARE_PAYMENT('FINATICS','{"provider":"STRIPE","referenceType":"RESERVATION","referenceId":"TEST-REFERENCE","amount":26.99,"currency":"GBP","idempotencyKey":"PAY-V2-001"}'::jsonb) INTO j; IF j->>'status'<>'CREATED' OR (j->>'providerIntegrated')::boolean THEN RAISE EXCEPTION 'Payment contract failed: %',j; END IF;
END $$;

DO $$ DECLARE j JSONB; BEGIN
 SELECT api.QUOTE_CHECKOUT('FINATICS','{"items":[{"sku_id":"FRYTRAY001-S-G-W-G","qty":1}],"deliveryAddress":{"postcode":"CV13 0AA","country":"GB"},"promoCode":"WELCOME10"}'::jsonb) INTO j;
 IF NOT (j->>'valid')::boolean OR (j->>'discountAmount')::numeric<>2.70 THEN RAISE EXCEPTION 'V2 quote failed: %',j; END IF;
END $$;

ROLLBACK;
