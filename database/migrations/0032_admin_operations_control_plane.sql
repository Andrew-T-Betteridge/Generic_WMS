BEGIN;

-- DYNETIC WMS 0.3.14
-- Admin & Operations control plane.
-- Backend-first: the frontend must call guarded commands rather than mutate
-- fulfilment status directly.

CREATE TABLE IF NOT EXISTS config.ADMIN_REASON_CODE (
    CLIENT_ID varchar(30) NOT NULL,
    REASON_DOMAIN varchar(40) NOT NULL,
    REASON_CODE varchar(40) NOT NULL,
    DESCRIPTION varchar(200) NOT NULL,
    ACTIVE boolean NOT NULL DEFAULT true,
    REQUIRES_NOTES boolean NOT NULL DEFAULT false,
    SORT_SEQUENCE integer NOT NULL DEFAULT 100,
    CREATED_DSTAMP timestamptz NOT NULL DEFAULT now(),
    LAST_UPDATE_DSTAMP timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (CLIENT_ID, REASON_DOMAIN, REASON_CODE)
);

CREATE TABLE IF NOT EXISTS config.ADMIN_OPERATIONAL_SLA (
    CLIENT_ID varchar(30) NOT NULL,
    SLA_CODE varchar(60) NOT NULL,
    DESCRIPTION varchar(200) NOT NULL,
    WARNING_MINUTES integer,
    CRITICAL_MINUTES integer,
    ACTIVE boolean NOT NULL DEFAULT true,
    CREATED_DSTAMP timestamptz NOT NULL DEFAULT now(),
    LAST_UPDATE_DSTAMP timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (CLIENT_ID, SLA_CODE),
    CHECK (WARNING_MINUTES IS NULL OR WARNING_MINUTES >= 0),
    CHECK (CRITICAL_MINUTES IS NULL OR CRITICAL_MINUTES >= 0)
);

CREATE TABLE IF NOT EXISTS core.ORDER_NOTE (
    ORDER_NOTE_ID uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    CLIENT_ID varchar(30) NOT NULL,
    ORDER_ID varchar(20) NOT NULL,
    NOTE_TYPE varchar(30) NOT NULL DEFAULT 'INTERNAL',
    NOTE_TEXT text NOT NULL,
    IMPORTANT boolean NOT NULL DEFAULT false,
    CREATED_BY varchar(255) NOT NULL,
    CREATED_DSTAMP timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS IX_ORDER_NOTE_ORDER
ON core.ORDER_NOTE(CLIENT_ID, ORDER_ID, CREATED_DSTAMP DESC);

CREATE TABLE IF NOT EXISTS core.CUSTOMER_NOTE (
    CUSTOMER_NOTE_ID uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    CLIENT_ID varchar(30) NOT NULL,
    ACCOUNT_ID uuid,
    CUSTOMER_ID varchar(50),
    NOTE_TYPE varchar(30) NOT NULL DEFAULT 'INTERNAL',
    NOTE_TEXT text NOT NULL,
    IMPORTANT boolean NOT NULL DEFAULT false,
    CREATED_BY varchar(255) NOT NULL,
    CREATED_DSTAMP timestamptz NOT NULL DEFAULT now(),
    CHECK (ACCOUNT_ID IS NOT NULL OR CUSTOMER_ID IS NOT NULL)
);
CREATE INDEX IF NOT EXISTS IX_CUSTOMER_NOTE_ACCOUNT
ON core.CUSTOMER_NOTE(CLIENT_ID,ACCOUNT_ID,CREATED_DSTAMP DESC);
CREATE INDEX IF NOT EXISTS IX_CUSTOMER_NOTE_CUSTOMER
ON core.CUSTOMER_NOTE(CLIENT_ID,CUSTOMER_ID,CREATED_DSTAMP DESC);

CREATE TABLE IF NOT EXISTS core.RETURN_CASE (
    RETURN_CASE_ID uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    CLIENT_ID varchar(30) NOT NULL,
    CASE_NUMBER varchar(30) NOT NULL,
    ORDER_ID varchar(20) NOT NULL,
    ACCOUNT_ID uuid,
    CUSTOMER_ID varchar(50),
    CASE_TYPE varchar(30) NOT NULL,
    STATUS varchar(30) NOT NULL DEFAULT 'OPEN',
    REASON_CODE varchar(40),
    CUSTOMER_MESSAGE text,
    INTERNAL_NOTES text,
    RESOLUTION varchar(40),
    REFUND_REQUESTED numeric(14,2) NOT NULL DEFAULT 0,
    REFUND_APPROVED numeric(14,2) NOT NULL DEFAULT 0,
    REPLACEMENT_ORDER_ID varchar(20),
    CREATED_BY varchar(255) NOT NULL,
    ASSIGNED_TO varchar(255),
    CREATED_DSTAMP timestamptz NOT NULL DEFAULT now(),
    LAST_UPDATE_DSTAMP timestamptz NOT NULL DEFAULT now(),
    CLOSED_DSTAMP timestamptz,
    UNIQUE(CLIENT_ID,CASE_NUMBER),
    CHECK (STATUS IN ('OPEN','INVESTIGATING','AWAITING_CUSTOMER','APPROVED','REJECTED','RESOLVED','CLOSED')),
    CHECK (REFUND_REQUESTED >= 0),
    CHECK (REFUND_APPROVED >= 0)
);
CREATE INDEX IF NOT EXISTS IX_RETURN_CASE_ORDER
ON core.RETURN_CASE(CLIENT_ID,ORDER_ID,STATUS);
CREATE INDEX IF NOT EXISTS IX_RETURN_CASE_STATUS
ON core.RETURN_CASE(CLIENT_ID,STATUS,CREATED_DSTAMP DESC);

CREATE TABLE IF NOT EXISTS core.RETURN_CASE_LINE (
    RETURN_CASE_LINE_ID uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    RETURN_CASE_ID uuid NOT NULL REFERENCES core.RETURN_CASE(RETURN_CASE_ID) ON DELETE CASCADE,
    CLIENT_ID varchar(30) NOT NULL,
    ORDER_ID varchar(20) NOT NULL,
    LINE_ID numeric,
    SKU_ID varchar(50),
    QTY numeric NOT NULL DEFAULT 1,
    ISSUE_TYPE varchar(30) NOT NULL,
    CONDITION_CODE varchar(30),
    RESOLUTION varchar(40),
    REFUND_AMOUNT numeric(14,2) NOT NULL DEFAULT 0,
    NOTES text,
    CREATED_DSTAMP timestamptz NOT NULL DEFAULT now(),
    CHECK (QTY > 0),
    CHECK (REFUND_AMOUNT >= 0)
);
CREATE INDEX IF NOT EXISTS IX_RETURN_CASE_LINE_CASE
ON core.RETURN_CASE_LINE(RETURN_CASE_ID);

CREATE TABLE IF NOT EXISTS core.PAYMENT_REFUND (
    PAYMENT_REFUND_ID uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    CLIENT_ID varchar(30) NOT NULL,
    PAYMENT_ID uuid NOT NULL,
    ORDER_ID varchar(20),
    RETURN_CASE_ID uuid REFERENCES core.RETURN_CASE(RETURN_CASE_ID),
    PROVIDER varchar(30) NOT NULL,
    PROVIDER_REFERENCE varchar(255),
    PROVIDER_REFUND_ID varchar(255),
    IDEMPOTENCY_KEY varchar(255) NOT NULL,
    AMOUNT numeric(14,2) NOT NULL,
    CURRENCY varchar(3) NOT NULL DEFAULT 'GBP',
    STATUS varchar(30) NOT NULL DEFAULT 'REQUESTED',
    REASON_CODE varchar(40),
    NOTES text,
    REQUESTED_BY varchar(255) NOT NULL,
    REQUESTED_DSTAMP timestamptz NOT NULL DEFAULT now(),
    COMPLETED_DSTAMP timestamptz,
    FAILURE_CODE varchar(100),
    FAILURE_TEXT text,
    UNIQUE(CLIENT_ID,IDEMPOTENCY_KEY),
    CHECK (AMOUNT > 0),
    CHECK (STATUS IN ('REQUESTED','SUBMITTED','SUCCEEDED','FAILED','CANCELLED'))
);
CREATE INDEX IF NOT EXISTS IX_PAYMENT_REFUND_PAYMENT
ON core.PAYMENT_REFUND(CLIENT_ID,PAYMENT_ID,REQUESTED_DSTAMP DESC);

CREATE TABLE IF NOT EXISTS core.GIFT_CARD_TRANSACTION (
    GIFT_CARD_TRANSACTION_ID uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    CLIENT_ID varchar(30) NOT NULL,
    GIFT_CARD_ID uuid NOT NULL,
    TRANSACTION_TYPE varchar(30) NOT NULL,
    AMOUNT numeric(14,2) NOT NULL,
    BALANCE_BEFORE numeric(14,2) NOT NULL,
    BALANCE_AFTER numeric(14,2) NOT NULL,
    REFERENCE_TYPE varchar(30),
    REFERENCE_ID varchar(100),
    REASON_CODE varchar(40),
    NOTES text,
    CREATED_BY varchar(255) NOT NULL,
    CREATED_DSTAMP timestamptz NOT NULL DEFAULT now(),
    CHECK (TRANSACTION_TYPE IN ('ISSUE','REDEEM','REFUND','ADJUST','CANCEL','EXPIRE')),
    CHECK (BALANCE_AFTER >= 0)
);
CREATE INDEX IF NOT EXISTS IX_GIFT_CARD_TRANSACTION_CARD
ON core.GIFT_CARD_TRANSACTION(CLIENT_ID,GIFT_CARD_ID,CREATED_DSTAMP DESC);

CREATE TABLE IF NOT EXISTS core.INVENTORY_COUNT (
    INVENTORY_COUNT_ID uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    CLIENT_ID varchar(30) NOT NULL,
    COUNT_REFERENCE varchar(40) NOT NULL,
    SITE_ID varchar(50),
    LOCATION_ID varchar(50),
    SKU_ID varchar(50),
    STATUS varchar(30) NOT NULL DEFAULT 'OPEN',
    CREATED_BY varchar(255) NOT NULL,
    CREATED_DSTAMP timestamptz NOT NULL DEFAULT now(),
    COMPLETED_BY varchar(255),
    COMPLETED_DSTAMP timestamptz,
    UNIQUE(CLIENT_ID,COUNT_REFERENCE),
    CHECK (STATUS IN ('OPEN','COUNTING','REVIEW','COMPLETED','CANCELLED'))
);

CREATE TABLE IF NOT EXISTS core.INVENTORY_COUNT_LINE (
    INVENTORY_COUNT_LINE_ID uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    INVENTORY_COUNT_ID uuid NOT NULL REFERENCES core.INVENTORY_COUNT(INVENTORY_COUNT_ID) ON DELETE CASCADE,
    CLIENT_ID varchar(30) NOT NULL,
    INVENTORY_KEY bigint,
    SKU_ID varchar(50) NOT NULL,
    LOCATION_ID varchar(50) NOT NULL,
    SYSTEM_QTY numeric NOT NULL,
    COUNTED_QTY numeric,
    VARIANCE_QTY numeric,
    STATUS varchar(30) NOT NULL DEFAULT 'PENDING',
    COUNTED_BY varchar(255),
    COUNTED_DSTAMP timestamptz,
    ADJUSTMENT_APPLIED boolean NOT NULL DEFAULT false,
    ADJUSTMENT_REASON varchar(40),
    CHECK (STATUS IN ('PENDING','COUNTED','ACCEPTED','REJECTED','ADJUSTED'))
);
CREATE INDEX IF NOT EXISTS IX_INVENTORY_COUNT_LINE_COUNT
ON core.INVENTORY_COUNT_LINE(INVENTORY_COUNT_ID,STATUS);

CREATE TABLE IF NOT EXISTS audit.ADMIN_ACTION_ATTEMPT (
    ACTION_ATTEMPT_ID uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    CLIENT_ID varchar(30) NOT NULL,
    ADMIN_USER_ID uuid,
    ADMIN_EMAIL varchar(255),
    ACTION_CODE varchar(80) NOT NULL,
    ENTITY_TYPE varchar(50),
    ENTITY_ID varchar(100),
    PERMISSION_CODE varchar(80),
    RESULT varchar(30) NOT NULL,
    REASON text,
    DETAIL jsonb NOT NULL DEFAULT '{}'::jsonb,
    CREATED_DSTAMP timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS IX_ADMIN_ACTION_ATTEMPT_TIME
ON audit.ADMIN_ACTION_ATTEMPT(CLIENT_ID,CREATED_DSTAMP DESC);

INSERT INTO config.ADMIN_PERMISSION(PERMISSION_CODE,CATEGORY,DESCRIPTION,DANGEROUS)
VALUES
 ('exception.read','OPERATIONS','View operational exception centre',false),
 ('audit.read','AUDIT','View audit and operational history',false),
 ('system.read','SYSTEM','View system health',false),
 ('order.note','ORDER','Add internal order notes',false),
 ('order.amend','ORDER','Amend permitted pre-fulfilment order details',true),
 ('order.allocate','ORDER','Allocate order inventory',true),
 ('order.deallocate','ORDER','Release order allocations',true),
 ('order.pick.create','FULFILMENT','Create pick tasks',true),
 ('pick.read','FULFILMENT','View pick tasks and queues',false),
 ('pick.confirm','FULFILMENT','Confirm or short-close a pick task',true),
 ('container.read','FULFILMENT','View order containers',false),
 ('container.pack','FULFILMENT','Pack an order container',true),
 ('container.merge','FULFILMENT','Merge compatible containers',true),
 ('container.fulfilment','FULFILMENT','Change container fulfilment method',true),
 ('delivery.hold','DELIVERY','Set or release delivery holds',true),
 ('carrier.read','DELIVERY','View carrier configuration and diagnostics',false),
 ('carrier.override','DELIVERY','Override selected carrier/service',true),
 ('shipment.read','FULFILMENT','View shipments and manifests',false),
 ('shipment.ship','FULFILMENT','Confirm container shipment',true),
 ('payment.read','PAYMENT','View payments',false),
 ('payment.refund','PAYMENT','Issue full or partial refunds',true),
 ('return.read','CUSTOMER_SERVICE','View returns/DOA/claims',false),
 ('return.create','CUSTOMER_SERVICE','Create returns/DOA/claims',true),
 ('return.manage','CUSTOMER_SERVICE','Manage returns/DOA/claims',true),
 ('customer.note','CUSTOMER','Add internal customer notes',false),
 ('inventory.move','INVENTORY','Move unallocated stock between locations',true),
 ('inventory.count','INVENTORY','Create and complete stock counts',true),
 ('notification.read','COMMUNICATION','View notification outbox',false),
 ('notification.retry','COMMUNICATION','Retry failed notifications',true),
 ('interface.read','INTERFACE','View interface processing',false),
 ('interface.retry','INTERFACE','Retry supported interface records',true),
 ('config.read','CONFIGURATION','View operational configuration',false),
 ('config.update','CONFIGURATION','Change operational configuration',true),
 ('promotion.manage','COMMERCIAL','Manage promotions',true),
 ('giftcard.read','COMMERCIAL','View gift cards and ledger',false),
 ('giftcard.manage','COMMERCIAL','Manage gift cards',true),
 ('supplier.read','INBOUND','View suppliers and supplier SKUs',false),
 ('supplier.manage','INBOUND','Maintain suppliers and supplier SKUs',true),
 ('pre_advice.read','INBOUND','View inbound pre-advice',false),
 ('pre_advice.manage','INBOUND','Maintain inbound pre-advice',true)
ON CONFLICT(PERMISSION_CODE) DO UPDATE
SET CATEGORY=EXCLUDED.CATEGORY,
    DESCRIPTION=EXCLUDED.DESCRIPTION,
    DANGEROUS=EXCLUDED.DANGEROUS;

INSERT INTO config.ADMIN_REASON_CODE
(CLIENT_ID,REASON_DOMAIN,REASON_CODE,DESCRIPTION,ACTIVE,REQUIRES_NOTES,SORT_SEQUENCE)
VALUES
 ('FINATICS','ORDER_CANCEL','CUSTOMER_REQUEST','Customer requested cancellation',true,false,10),
 ('FINATICS','ORDER_CANCEL','DUPLICATE','Duplicate order',true,false,20),
 ('FINATICS','ORDER_CANCEL','PAYMENT_FAILURE','Payment could not be completed',true,false,30),
 ('FINATICS','ORDER_CANCEL','OUT_OF_STOCK','Unable to fulfil due to stock',true,true,40),
 ('FINATICS','REFUND','CUSTOMER_REQUEST','Customer requested refund',true,false,10),
 ('FINATICS','REFUND','DOA','Livestock DOA claim',true,true,20),
 ('FINATICS','REFUND','DAMAGED','Goods damaged',true,true,30),
 ('FINATICS','REFUND','WRONG_ITEM','Wrong item supplied',true,true,40),
 ('FINATICS','REFUND','GOODWILL','Goodwill refund',true,true,50),
 ('FINATICS','INVENTORY_ADJUST','COUNT_VARIANCE','Stock count variance',true,true,10),
 ('FINATICS','INVENTORY_ADJUST','DAMAGE','Damaged stock',true,true,20),
 ('FINATICS','INVENTORY_ADJUST','DOA','Livestock loss / DOA',true,true,30),
 ('FINATICS','INVENTORY_ADJUST','CORRECTION','Administrative correction',true,true,40),
 ('FINATICS','INVENTORY_MOVE','REPLENISHMENT','Operational replenishment/move',true,false,10),
 ('FINATICS','PICK_SHORT','NO_STOCK','No stock at pick location',true,false,10),
 ('FINATICS','PICK_SHORT','DAMAGED','Stock damaged at pick',true,true,20),
 ('FINATICS','PICK_SHORT','OTHER','Other pick shortage',true,true,90),
 ('FINATICS','RETURN','DOA','Livestock dead on arrival',true,true,10),
 ('FINATICS','RETURN','DAMAGED','Damaged item',true,true,20),
 ('FINATICS','RETURN','WRONG_ITEM','Wrong item supplied',true,true,30),
 ('FINATICS','RETURN','CUSTOMER_RETURN','Customer return',true,false,40),
 ('FINATICS','GIFTCARD','MANUAL_ADJUST','Manual gift-card correction',true,true,10)
ON CONFLICT(CLIENT_ID,REASON_DOMAIN,REASON_CODE) DO NOTHING;

INSERT INTO config.ADMIN_OPERATIONAL_SLA
(CLIENT_ID,SLA_CODE,DESCRIPTION,WARNING_MINUTES,CRITICAL_MINUTES)
VALUES
 ('FINATICS','PAID_NOT_ALLOCATED','Paid order awaiting allocation',10,30),
 ('FINATICS','OPEN_PICK','Open pick age',30,120),
 ('FINATICS','PACKED_NOT_SHIPPED','Packed container awaiting shipment',30,120),
 ('FINATICS','FAILED_NOTIFICATION','Failed notification waiting retry',15,60),
 ('FINATICS','FAILED_INTERFACE','Failed interface waiting retry',15,60),
 ('FINATICS','DELIVERY_HOLD','Delivery hold age',120,720)
ON CONFLICT(CLIENT_ID,SLA_CODE) DO NOTHING;

CREATE OR REPLACE VIEW core.ADMIN_ORDER_CONTROL_WORKBENCH AS
SELECT
    oh.CLIENT_ID,oh.ORDER_ID,oh.CUSTOMER_ID,oh.ACCOUNT_ID,oh.CONTACT_EMAIL,
    oh.ORDER_DATE,oh.PRIORITY,oh.STATUS,oh.PAYMENT_STATUS,oh.FULFILMENT_STATUS,
    oh.ORDER_VALUE,oh.DISPATCH_METHOD,oh.CARRIER_ID,oh.SERVICE_LEVEL,
    oh.SHIP_BY_DATE,oh.DELIVER_BY_DATE,oh.POSTCODE,oh.COUNTRY,
    COALESCE(ofw.LINE_COUNT,0) LINE_COUNT,
    COALESCE(ofw.QTY_ORDERED,0) QTY_ORDERED,
    COALESCE(ofw.QTY_RESERVED,0) QTY_RESERVED,
    COALESCE(ofw.QTY_PICKED,0) QTY_PICKED,
    COALESCE(ofw.QTY_SHIPPED,0) QTY_SHIPPED,
    ofw.DERIVED_STATUS,
    (SELECT count(*)::int FROM core.PICK_TASK pt
      WHERE pt.CLIENT_ID=oh.CLIENT_ID AND pt.ORDER_ID=oh.ORDER_ID
        AND pt.STATUS NOT IN ('COMPLETED','CANCELLED')) OPEN_PICK_TASKS,
    (SELECT count(*)::int FROM core.ORDER_CONTAINER oc
      WHERE oc.CLIENT_ID=oh.CLIENT_ID AND oc.ORDER_ID=oh.ORDER_ID
        AND oc.STATUS NOT IN ('SHIPPED','MERGED','CANCELLED')) OPEN_CONTAINERS,
    (SELECT count(*)::int FROM core.ORDER_NOTE n
      WHERE n.CLIENT_ID=oh.CLIENT_ID AND n.ORDER_ID=oh.ORDER_ID) NOTE_COUNT
FROM core.ORDER_HEADER oh
LEFT JOIN core.ORDER_FULFILMENT_WORKBENCH ofw
  ON ofw.CLIENT_ID=oh.CLIENT_ID AND ofw.ORDER_ID=oh.ORDER_ID;

CREATE OR REPLACE VIEW core.ADMIN_PAYMENT_WORKBENCH AS
SELECT
    p.CLIENT_ID,p.PAYMENT_ID,p.REFERENCE_TYPE,p.REFERENCE_ID,p.ACCOUNT_ID,
    p.PROVIDER,p.PROVIDER_REFERENCE,p.AMOUNT,p.CAPTURED_AMOUNT,p.REFUNDED_AMOUNT,
    (p.CAPTURED_AMOUNT-p.REFUNDED_AMOUNT) REFUNDABLE_AMOUNT,p.CURRENCY,p.STATUS,
    p.PROVIDER_STATUS,p.LAST_EVENT_TYPE,p.LAST_EVENT_DSTAMP,p.FAILURE_CODE,
    p.FAILURE_TEXT,p.CREATED_DSTAMP,p.LAST_UPDATE_DSTAMP
FROM core.PAYMENT_TRANSACTION p;

CREATE OR REPLACE VIEW core.ADMIN_EXCEPTION_WORKBENCH AS
SELECT
  'PAID_NOT_ALLOCATED'::text EXCEPTION_TYPE,
  oh.CLIENT_ID,'ORDER'::text ENTITY_TYPE,oh.ORDER_ID::text ENTITY_ID,
  oh.ORDER_DATE CREATED_DSTAMP,
  EXTRACT(EPOCH FROM(now()-oh.ORDER_DATE))/60.0 AGE_MINUTES,
  'Paid order is not progressing through allocation'::text MESSAGE,
  jsonb_build_object('paymentStatus',oh.PAYMENT_STATUS,'fulfilmentStatus',oh.FULFILMENT_STATUS,'orderValue',oh.ORDER_VALUE) DETAIL
FROM core.ORDER_HEADER oh
WHERE oh.PAYMENT_STATUS='PAID'
  AND COALESCE(oh.FULFILMENT_STATUS,'UNALLOCATED') IN ('UNALLOCATED','RESERVED')
UNION ALL
SELECT
  'OPEN_PICK',pt.CLIENT_ID,'PICK_TASK',pt.PICK_TASK_ID::text,pt.CREATED_DSTAMP,
  EXTRACT(EPOCH FROM(now()-pt.CREATED_DSTAMP))/60.0,
  'Pick task remains open',
  jsonb_build_object('orderId',pt.ORDER_ID,'skuId',pt.SKU_ID,'locationId',pt.LOCATION_ID,'status',pt.STATUS,'qtyRequired',pt.QTY_REQUIRED,'qtyPicked',pt.QTY_PICKED)
FROM core.PICK_TASK pt
WHERE pt.STATUS IN ('OPEN','STARTED')
UNION ALL
SELECT
  'FAILED_NOTIFICATION',n.CLIENT_ID,'NOTIFICATION',n.OUTBOX_ID::text,n.CREATED_DSTAMP,
  EXTRACT(EPOCH FROM(now()-n.CREATED_DSTAMP))/60.0,
  COALESCE(n.LAST_ERROR,'Notification delivery failed'),
  jsonb_build_object('channel',n.CHANNEL,'recipient',n.RECIPIENT,'attemptCount',n.ATTEMPT_COUNT,'status',n.STATUS)
FROM interface.NOTIFICATION_OUTBOX n
WHERE n.STATUS IN ('FAILED','ERROR')
UNION ALL
SELECT
  'FAILED_ORDER_INTERFACE',i.CLIENT_ID,'ORDER_INTERFACE',i.INTERFACE_ID::text,i.CREATED_DSTAMP,
  EXTRACT(EPOCH FROM(now()-i.CREATED_DSTAMP))/60.0,
  COALESCE(i.ERROR_TEXT,'Order interface failed'),
  jsonb_build_object('sourceSystem',i.SOURCE_SYSTEM,'sourceOrderId',i.SOURCE_ORDER_ID,'status',i.PROCESS_STATUS,'errorCode',i.ERROR_CODE)
FROM interface.ORDER_HEADER_IF i
WHERE i.PROCESS_STATUS IN ('FAILED','ERROR');

CREATE OR REPLACE FUNCTION core.ADD_ORDER_NOTE(
 p_client_id varchar,p_order_id varchar,p_note_type varchar,p_note_text text,
 p_important boolean,p_user_id varchar
) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_id uuid;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM core.ORDER_HEADER WHERE CLIENT_ID=p_client_id AND ORDER_ID=p_order_id)
 THEN RAISE EXCEPTION 'ORDER_NOT_FOUND'; END IF;
 IF length(trim(COALESCE(p_note_text,'')))<2 THEN RAISE EXCEPTION 'INVALID_NOTE_TEXT'; END IF;
 INSERT INTO core.ORDER_NOTE(CLIENT_ID,ORDER_ID,NOTE_TYPE,NOTE_TEXT,IMPORTANT,CREATED_BY)
 VALUES(p_client_id,p_order_id,upper(COALESCE(NULLIF(trim(p_note_type),''),'INTERNAL')),trim(p_note_text),COALESCE(p_important,false),p_user_id)
 RETURNING ORDER_NOTE_ID INTO v_id;
 INSERT INTO audit.AUDIT_EVENT(CLIENT_ID,ENTITY_TYPE,ENTITY_ID,ACTION,CHANGED_BY,AFTER_DATA)
 VALUES(p_client_id,'ORDER',p_order_id,'NOTE_ADDED',p_user_id,jsonb_build_object('orderNoteId',v_id));
 RETURN v_id;
END $$;

CREATE OR REPLACE FUNCTION core.AMEND_ORDER_HEADER(
 p_client_id varchar,p_order_id varchar,p_patch jsonb,p_reason text,p_user_id varchar
) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_before jsonb; v_after jsonb; v_status text; v_fulfilment text;
BEGIN
 SELECT to_jsonb(h),upper(COALESCE(h.STATUS,'')),upper(COALESCE(h.FULFILMENT_STATUS,''))
 INTO v_before,v_status,v_fulfilment
 FROM core.ORDER_HEADER h WHERE CLIENT_ID=p_client_id AND ORDER_ID=p_order_id FOR UPDATE;
 IF v_before IS NULL THEN RAISE EXCEPTION 'ORDER_NOT_FOUND'; END IF;
 IF v_status IN ('CANCELLED','CLOSED','SHIPPED') OR v_fulfilment IN ('SHIPPED','COMPLETE','CANCELLED')
 THEN RAISE EXCEPTION 'ORDER_AMEND_NOT_ALLOWED'; END IF;

 UPDATE core.ORDER_HEADER h SET
   PRIORITY=COALESCE((p_patch->>'priority')::numeric,PRIORITY),
   CONTACT=COALESCE(p_patch->>'contact',CONTACT),
   CONTACT_PHONE=COALESCE(p_patch->>'contactPhone',CONTACT_PHONE),
   CONTACT_MOBILE=COALESCE(p_patch->>'contactMobile',CONTACT_MOBILE),
   CONTACT_EMAIL=COALESCE(p_patch->>'contactEmail',CONTACT_EMAIL),
   NAME=COALESCE(p_patch->>'name',NAME),
   ADDRESS1=COALESCE(p_patch->>'address1',ADDRESS1),
   ADDRESS2=COALESCE(p_patch->>'address2',ADDRESS2),
   TOWN=COALESCE(p_patch->>'town',TOWN),
   COUNTY=COALESCE(p_patch->>'county',COUNTY),
   POSTCODE=COALESCE(p_patch->>'postcode',POSTCODE),
   COUNTRY=COALESCE(p_patch->>'country',COUNTRY),
   INSTRUCTIONS=COALESCE(p_patch->>'instructions',INSTRUCTIONS),
   PACKING_NOTES=COALESCE(p_patch->>'packingNotes',PACKING_NOTES),
   SHIP_BY_DATE=COALESCE((p_patch->>'shipByDate')::timestamptz,SHIP_BY_DATE),
   DELIVER_BY_DATE=COALESCE((p_patch->>'deliverByDate')::timestamptz,DELIVER_BY_DATE),
   LAST_UPDATED_BY=p_user_id,LAST_UPDATE_DATE=now()
 WHERE CLIENT_ID=p_client_id AND ORDER_ID=p_order_id
 RETURNING to_jsonb(h) INTO v_after;

 INSERT INTO audit.AUDIT_EVENT(CLIENT_ID,ENTITY_TYPE,ENTITY_ID,ACTION,CHANGED_BY,REASON,BEFORE_DATA,AFTER_DATA)
 VALUES(p_client_id,'ORDER',p_order_id,'AMEND',p_user_id,p_reason,v_before,v_after);
 RETURN v_after;
END $$;

CREATE OR REPLACE FUNCTION core.AMEND_ORDER_LINE_PRE_FULFILMENT(
 p_client_id varchar,p_order_id varchar,p_line_id numeric,p_patch jsonb,p_reason text,p_user_id varchar
) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_before jsonb; v_after jsonb; v_payment text; v_alloc numeric; v_picked numeric; v_shipped numeric;
BEGIN
 SELECT to_jsonb(ol),upper(COALESCE(oh.PAYMENT_STATUS,'')),
        COALESCE(ol.QTY_SOFT_ALLOCATED,0),COALESCE(ol.QTY_PICKED,0),COALESCE(ol.QTY_SHIPPED,0)
 INTO v_before,v_payment,v_alloc,v_picked,v_shipped
 FROM core.ORDER_LINE ol JOIN core.ORDER_HEADER oh
 ON oh.CLIENT_ID=ol.CLIENT_ID AND oh.ORDER_ID=ol.ORDER_ID
 WHERE ol.CLIENT_ID=p_client_id AND ol.ORDER_ID=p_order_id AND ol.LINE_ID=p_line_id
 FOR UPDATE OF ol;
 IF v_before IS NULL THEN RAISE EXCEPTION 'ORDER_LINE_NOT_FOUND'; END IF;
 IF v_payment IN ('PAID','AUTHORISED','PART_REFUNDED','REFUNDED') THEN RAISE EXCEPTION 'PAID_ORDER_LINE_AMEND_NOT_ALLOWED'; END IF;
 IF v_alloc>0 OR v_picked>0 OR v_shipped>0 THEN RAISE EXCEPTION 'FULFILMENT_STARTED_LINE_AMEND_NOT_ALLOWED'; END IF;

 UPDATE core.ORDER_LINE ol SET
   SKU_ID=COALESCE(p_patch->>'skuId',SKU_ID),
   QTY_ORDERED=COALESCE((p_patch->>'qtyOrdered')::numeric,QTY_ORDERED),
   NOTES=COALESCE(p_patch->>'notes',NOTES),
   LAST_UPDATED_BY=p_user_id,LAST_UPDATE_DATE=now()
 WHERE CLIENT_ID=p_client_id AND ORDER_ID=p_order_id AND LINE_ID=p_line_id
 RETURNING to_jsonb(ol) INTO v_after;

 INSERT INTO audit.AUDIT_EVENT(CLIENT_ID,ENTITY_TYPE,ENTITY_ID,ACTION,CHANGED_BY,REASON,BEFORE_DATA,AFTER_DATA)
 VALUES(p_client_id,'ORDER_LINE',p_order_id||':'||p_line_id,'AMEND',p_user_id,p_reason,v_before,v_after);
 RETURN v_after;
END $$;

CREATE OR REPLACE FUNCTION core.MOVE_INVENTORY(
 p_client_id varchar,p_inventory_key bigint,p_to_location_id varchar,
 p_reason_code varchar,p_notes text,p_user_id varchar,p_station_id varchar
) RETURNS TABLE(result_status varchar,result_inventory_key bigint,result_from_location varchar,result_to_location varchar,result_qty numeric,result_message text)
LANGUAGE plpgsql AS $$
DECLARE v_inv core.INVENTORY%ROWTYPE; v_original numeric;
BEGIN
 SELECT * INTO v_inv FROM core.INVENTORY
 WHERE CLIENT_ID=p_client_id AND KEY=p_inventory_key FOR UPDATE;
 IF NOT FOUND THEN RETURN QUERY SELECT 'NOT_FOUND'::varchar,p_inventory_key,NULL::varchar,NULL::varchar,0::numeric,'Inventory not found.'::text; RETURN; END IF;
 IF COALESCE(v_inv.QTY_ALLOCATED,0)<>0 THEN RAISE EXCEPTION 'ALLOCATED_INVENTORY_MOVE_NOT_ALLOWED'; END IF;
 IF v_inv.LOCATION_ID=p_to_location_id THEN RAISE EXCEPTION 'SAME_LOCATION_MOVE_NOT_ALLOWED'; END IF;
 IF NOT EXISTS(SELECT 1 FROM core.LOCATION WHERE LOCATION_ID=p_to_location_id) THEN RAISE EXCEPTION 'LOCATION_NOT_FOUND'; END IF;
 v_original:=v_inv.QTY_ON_HAND;

 UPDATE core.INVENTORY SET LOCATION_ID=p_to_location_id,MOVE_DSTAMP=now() WHERE KEY=p_inventory_key;

 INSERT INTO core.INVENTORY_TRANSACTION
 (CODE,SITE_ID,FROM_SITE_ID,TO_SITE_ID,FROM_LOC_ID,TO_LOC_ID,FINAL_LOC_ID,OWNER_ID,CLIENT_ID,SKU_ID,TAG_ID,CONTAINER_ID,BATCH_ID,QC_STATUS,EXPIRY_DSTAMP,MANUF_DSTAMP,ORIGIN_ID,CONDITION_ID,LOCK_STATUS,DSTAMP,REFERENCE_ID,REASON_ID,STATION_ID,USER_ID,UPDATE_QTY,ORIGINAL_QTY,COMPLETE_DSTAMP,NOTES,SOURCE,REFERENCE_TYPE)
 VALUES
 ('MOVE',v_inv.SITE_ID,v_inv.SITE_ID,v_inv.SITE_ID,v_inv.LOCATION_ID,p_to_location_id,p_to_location_id,
  v_inv.OWNER_ID,v_inv.CLIENT_ID,v_inv.SKU_ID,v_inv.TAG_ID,v_inv.CONTAINER_ID,v_inv.BATCH_ID,v_inv.QC_STATUS,
  v_inv.EXPIRY_DSTAMP,v_inv.MANUF_DSTAMP,v_inv.ORIGIN_ID,v_inv.CONDITION_ID,v_inv.LOCK_STATUS,now(),
  p_inventory_key::text,p_reason_code,p_station_id,p_user_id,0,v_original,now(),p_notes,'ADMIN','INVENTORY_MOVE');

 INSERT INTO audit.AUDIT_EVENT(CLIENT_ID,ENTITY_TYPE,ENTITY_ID,ACTION,CHANGED_BY,REASON,BEFORE_DATA,AFTER_DATA)
 VALUES(p_client_id,'INVENTORY',p_inventory_key::text,'MOVE',p_user_id,p_reason_code,
        jsonb_build_object('locationId',v_inv.LOCATION_ID),
        jsonb_build_object('locationId',p_to_location_id));

 RETURN QUERY SELECT 'MOVED'::varchar,p_inventory_key,v_inv.LOCATION_ID,p_to_location_id,v_original,'Inventory moved.'::text;
END $$;

CREATE OR REPLACE FUNCTION core.RETRY_NOTIFICATION(
 p_client_id varchar,p_outbox_id uuid,p_user_id varchar
) RETURNS TABLE(result_status varchar,result_message text)
LANGUAGE plpgsql AS $$
BEGIN
 UPDATE interface.NOTIFICATION_OUTBOX
 SET STATUS='PENDING',ATTEMPT_COUNT=0,NEXT_ATTEMPT_DSTAMP=now(),LAST_ERROR=NULL
 WHERE CLIENT_ID=p_client_id AND OUTBOX_ID=p_outbox_id AND STATUS IN('FAILED','ERROR');
 IF NOT FOUND THEN RETURN QUERY SELECT 'NOT_RETRYABLE'::varchar,'Notification not found or not retryable.'::text; RETURN; END IF;
 INSERT INTO audit.AUDIT_EVENT(CLIENT_ID,ENTITY_TYPE,ENTITY_ID,ACTION,CHANGED_BY)
 VALUES(p_client_id,'NOTIFICATION',p_outbox_id::text,'RETRY',p_user_id);
 RETURN QUERY SELECT 'REQUEUED'::varchar,'Notification queued for retry.'::text;
END $$;

CREATE OR REPLACE FUNCTION core.RETRY_ORDER_INTERFACE(
 p_client_id varchar,p_interface_id uuid,p_user_id varchar
) RETURNS TABLE(result_status varchar,result_order_id varchar,result_message text)
LANGUAGE plpgsql AS $$
DECLARE v_result record;
BEGIN
 IF NOT EXISTS(
   SELECT 1 FROM interface.ORDER_HEADER_IF
   WHERE CLIENT_ID=p_client_id AND INTERFACE_ID=p_interface_id AND PROCESS_STATUS IN('FAILED','ERROR')
 ) THEN
   RETURN QUERY SELECT 'NOT_RETRYABLE'::varchar,NULL::varchar,'Order interface not found or not retryable.'::text; RETURN;
 END IF;

 UPDATE interface.ORDER_HEADER_IF
 SET PROCESS_STATUS='NEW',ERROR_CODE=NULL,ERROR_TEXT=NULL,PROCESSED_DSTAMP=NULL
 WHERE CLIENT_ID=p_client_id AND INTERFACE_ID=p_interface_id;

 SELECT * INTO v_result FROM interface.PROCESS_ORDER_INTERFACE(p_interface_id);
 INSERT INTO audit.AUDIT_EVENT(CLIENT_ID,ENTITY_TYPE,ENTITY_ID,ACTION,CHANGED_BY,AFTER_DATA)
 VALUES(p_client_id,'ORDER_INTERFACE',p_interface_id::text,'RETRY',p_user_id,to_jsonb(v_result));
 RETURN QUERY SELECT v_result.result_status,v_result.result_order_id,v_result.result_message;
END $$;

CREATE OR REPLACE FUNCTION core.ADJUST_GIFT_CARD(
 p_client_id varchar,p_gift_code varchar,p_amount numeric,p_reason_code varchar,
 p_notes text,p_reference_type varchar,p_reference_id varchar,p_user_id varchar
) RETURNS TABLE(result_status varchar,result_balance numeric,result_message text)
LANGUAGE plpgsql AS $$
DECLARE v_card core.GIFT_CARD%ROWTYPE; v_before numeric; v_after numeric; v_type varchar;
BEGIN
 SELECT * INTO v_card FROM core.GIFT_CARD
 WHERE CLIENT_ID=p_client_id AND GIFT_CODE=p_gift_code FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'GIFT_CARD_NOT_FOUND'; END IF;
 IF p_amount=0 THEN RAISE EXCEPTION 'INVALID_GIFT_CARD_AMOUNT'; END IF;
 v_before:=v_card.BALANCE;
 v_after:=v_before+p_amount;
 IF v_after<0 THEN RAISE EXCEPTION 'INSUFFICIENT_GIFT_CARD_BALANCE'; END IF;
 v_type:=CASE WHEN p_amount>0 THEN 'ADJUST' ELSE 'REDEEM' END;

 UPDATE core.GIFT_CARD SET BALANCE=v_after,
   STATUS=CASE WHEN v_after=0 THEN 'SPENT' ELSE STATUS END,
   LAST_UPDATE_DSTAMP=now()
 WHERE GIFT_CARD_ID=v_card.GIFT_CARD_ID;

 INSERT INTO core.GIFT_CARD_TRANSACTION
 (CLIENT_ID,GIFT_CARD_ID,TRANSACTION_TYPE,AMOUNT,BALANCE_BEFORE,BALANCE_AFTER,REFERENCE_TYPE,REFERENCE_ID,REASON_CODE,NOTES,CREATED_BY)
 VALUES(p_client_id,v_card.GIFT_CARD_ID,v_type,p_amount,v_before,v_after,p_reference_type,p_reference_id,p_reason_code,p_notes,p_user_id);

 RETURN QUERY SELECT 'UPDATED'::varchar,v_after,'Gift-card balance updated.'::text;
END $$;

COMMIT;
