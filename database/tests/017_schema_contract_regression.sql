\set ON_ERROR_STOP on
\pset pager off
BEGIN;
DO $$
DECLARE v_missing text;
BEGIN
 SELECT string_agg(x.object_name,', ' ORDER BY x.object_name) INTO v_missing
 FROM (VALUES
  ('core.CLIENT','r'),('core.SKU','r'),('core.INVENTORY','r'),('core.ORDER_HEADER','r'),('core.ORDER_LINE','r'),
  ('core.ALLOCATION','r'),('core.PICK_TASK','r'),('core.ORDER_CONTAINER','r'),('core.SHIPPING_MANIFEST','r'),
  ('core.PRODUCT','r'),('core.PRODUCT_VARIANT','r'),('core.CUSTOMER_ACCOUNT','r'),('core.PAYMENT_TRANSACTION','r'),
  ('interface.ORDER_HEADER_IF','r'),('interface.ORDER_LINE_IF','r'),('audit.PAYMENT_EVENT','r'),('config.SYSTEM_VERSION','r')
 ) x(object_name,kind)
 WHERE to_regclass(x.object_name) IS NULL;
 IF v_missing IS NOT NULL THEN RAISE EXCEPTION 'Missing required relations: %',v_missing; END IF;

 IF to_regprocedure('core.allocate_order(character varying,character varying)') IS NULL THEN RAISE EXCEPTION 'Missing core.ALLOCATE_ORDER'; END IF;
 IF to_regprocedure('core.deallocate_order(character varying,character varying)') IS NULL THEN RAISE EXCEPTION 'Missing core.DEALLOCATE_ORDER'; END IF;
 IF to_regprocedure('api.get_system_version()') IS NULL THEN RAISE EXCEPTION 'Missing api.GET_SYSTEM_VERSION'; END IF;
 IF to_regprocedure('api.process_payment_event(character varying,character varying,character varying,character varying,character varying,jsonb)') IS NULL THEN RAISE EXCEPTION 'Missing api.PROCESS_PAYMENT_EVENT'; END IF;

 IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='core' AND table_name='order_header' AND column_name='payment_due_dstamp') THEN RAISE EXCEPTION 'ORDER_HEADER.PAYMENT_DUE_DSTAMP missing'; END IF;
 IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='core' AND table_name='payment_transaction' AND column_name='captured_amount') THEN RAISE EXCEPTION 'PAYMENT_TRANSACTION.CAPTURED_AMOUNT missing'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='uq_payment_event') THEN RAISE EXCEPTION 'Payment event idempotency constraint missing'; END IF;
END $$;
ROLLBACK;
\echo 'Schema contract regression tests passed.'
