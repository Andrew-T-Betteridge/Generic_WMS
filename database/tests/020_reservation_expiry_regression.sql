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
VALUES('REG-RES-LOC','STORAGE','UNLOCKED',1000000,'N','N',993020,'Reservation Regression','Y','Y') ON CONFLICT DO NOTHING;
INSERT INTO core.INVENTORY(CLIENT_ID,SKU_ID,LOCATION_ID,QTY_ON_HAND,QTY_ALLOCATED,LOCK_STATUS,RECEIPT_DSTAMP,MOVE_DSTAMP,DISALLOW_ALLOC)
VALUES('FINATICS','FRYTRAY001-S-G-W-G','REG-RES-LOC',5,0,'UNLOCKED',now(),now(),'N');
DO $$ DECLARE j jsonb; rid uuid; before_q numeric; after_q numeric; n integer; BEGIN
 SELECT QTY_ALLOCATED INTO before_q FROM core.INVENTORY WHERE CLIENT_ID='FINATICS' AND SKU_ID='FRYTRAY001-S-G-W-G' AND LOCATION_ID='REG-RES-LOC';
 j:=api.CREATE_STOCK_RESERVATION('FINATICS','{"idempotencyKey":"REG-RES-EXP","holdMinutes":60,"customer":{"name":"Regression","email":"reg-res@example.invalid"},"fulfilmentMethod":"COLLECTION","items":[{"sku_id":"FRYTRAY001-S-G-W-G","qty":2}]}'::jsonb);
 rid:=(j->>'reservationId')::uuid;
 UPDATE core.STOCK_RESERVATION SET EXPIRES_DSTAMP=now()-interval '1 minute' WHERE RESERVATION_ID=rid;
 n:=api.EXPIRE_STOCK_RESERVATIONS('FINATICS');
 IF n<1 THEN RAISE EXCEPTION 'Expected at least one expired reservation'; END IF;
 IF (SELECT STATUS FROM core.STOCK_RESERVATION WHERE RESERVATION_ID=rid)<>'EXPIRED' THEN RAISE EXCEPTION 'Reservation not EXPIRED'; END IF;
 SELECT QTY_ALLOCATED INTO after_q FROM core.INVENTORY WHERE CLIENT_ID='FINATICS' AND SKU_ID='FRYTRAY001-S-G-W-G' AND LOCATION_ID='REG-RES-LOC';
 IF after_q<>before_q THEN RAISE EXCEPTION 'Expired reservation did not release inventory: before %, after %',before_q,after_q; END IF;
END $$;
ROLLBACK;
\echo 'Reservation expiry regression tests passed.'
