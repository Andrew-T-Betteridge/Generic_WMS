--
-- PostgreSQL database dump
--

\restrict JvWesxIm4WB3PdmkoNO63XofJTJyr2LdccOR50dyEVYXm1Cuwg6f1tvFABf7lJn

-- Dumped from database version 18.6
-- Dumped by pg_dump version 18.6

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: api; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA api;


--
-- Name: audit; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA audit;


--
-- Name: config; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA config;


--
-- Name: core; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA core;


--
-- Name: interface; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA interface;


--
-- Name: claim_order_account(character varying, character varying, uuid, character varying); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.claim_order_account(p_client_id character varying, p_order_id character varying, p_account_id uuid, p_email character varying) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE v_rows INTEGER;
BEGIN
    UPDATE core.ORDER_HEADER
       SET ACCOUNT_ID=p_account_id,
           LAST_UPDATED_BY='WEB_API',
           LAST_UPDATE_DATE=now()
     WHERE CLIENT_ID=p_client_id
       AND ORDER_ID=p_order_id
       AND ACCOUNT_ID IS NULL
       AND LOWER(COALESCE(EMAIL,''))=LOWER(COALESCE(p_email,''));

    GET DIAGNOSTICS v_rows = ROW_COUNT;

    IF v_rows=0 AND EXISTS(
        SELECT 1 FROM core.ORDER_HEADER
        WHERE CLIENT_ID=p_client_id AND ORDER_ID=p_order_id AND ACCOUNT_ID=p_account_id
    ) THEN
        RETURN TRUE;
    END IF;

    RETURN v_rows=1;
END;
$$;


--
-- Name: create_customer_interest(character varying, jsonb); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.create_customer_interest(p_client_id character varying, p_payload jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
DECLARE v_id UUID; v_product_id VARCHAR; v_sku_id VARCHAR; v_type VARCHAR; v_email TEXT;
BEGIN
 v_type:=UPPER(COALESCE(NULLIF(TRIM(p_payload->>'interestType'),''),'WAITLIST'));
 v_product_id:=NULLIF(TRIM(p_payload->>'productId'),'');
 v_sku_id:=NULLIF(TRIM(p_payload->>'skuId'),'');
 v_email:=LOWER(NULLIF(TRIM(p_payload->>'email'),''));
 IF v_type NOT IN ('WAITLIST','GROWING_STOCK') THEN RAISE EXCEPTION 'INVALID_INTEREST_TYPE'; END IF;
 IF v_product_id IS NULL OR v_email IS NULL OR position('@' in v_email)<2 THEN RAISE EXCEPTION 'PRODUCT_AND_VALID_EMAIL_REQUIRED'; END IF;
 IF NOT EXISTS(SELECT 1 FROM core.PRODUCT WHERE CLIENT_ID=p_client_id AND PRODUCT_ID=v_product_id AND ACTIVE=TRUE) THEN RAISE EXCEPTION 'PRODUCT_NOT_FOUND'; END IF;
 INSERT INTO core.CUSTOMER_INTEREST(CLIENT_ID,INTEREST_TYPE,PRODUCT_ID,SKU_ID,REQUESTED_QTY,CONTACT_NAME,EMAIL,PHONE,PREFERRED_CHANNEL,CONSENT_TO_NOTIFY)
 VALUES(p_client_id,v_type,v_product_id,v_sku_id,NULLIF(p_payload->>'requestedQty','')::numeric,NULLIF(TRIM(p_payload->>'name'),''),v_email,
        NULLIF(TRIM(p_payload->>'phone'),''),UPPER(COALESCE(NULLIF(TRIM(p_payload->>'preferredChannel'),''),'EMAIL')),
        COALESCE((p_payload->>'consentToNotify')::boolean,TRUE)) RETURNING INTEREST_ID INTO v_id;
 RETURN jsonb_build_object('interestId',v_id,'status','ACTIVE','interestType',v_type);
END; $$;


--
-- Name: create_payment_request(character varying, uuid, character varying, character varying, character varying, character varying); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.create_payment_request(p_client_id character varying, p_account_id uuid, p_reference_type character varying, p_reference_id character varying, p_provider character varying, p_idempotency_key character varying) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_type VARCHAR(30) := UPPER(TRIM(p_reference_type));
    v_provider VARCHAR(30) := UPPER(COALESCE(NULLIF(TRIM(p_provider),''),'STRIPE'));
    v_amount NUMERIC(12,2);
    v_currency VARCHAR(3);
    v_payment core.PAYMENT_TRANSACTION%ROWTYPE;
BEGIN
    IF v_provider NOT IN ('STRIPE','PAYPAL') THEN
        RAISE EXCEPTION 'UNSUPPORTED_PAYMENT_PROVIDER';
    END IF;

    IF NULLIF(TRIM(p_idempotency_key),'') IS NULL THEN
        RAISE EXCEPTION 'IDEMPOTENCY_KEY_REQUIRED';
    END IF;

    IF v_type='ORDER' THEN
        SELECT ORDER_VALUE::NUMERIC(12,2),COALESCE(INV_CURRENCY,'GBP')
          INTO v_amount,v_currency
          FROM core.ORDER_HEADER
         WHERE CLIENT_ID=p_client_id
           AND ORDER_ID=p_reference_id
           AND (p_account_id IS NULL OR ACCOUNT_ID=p_account_id);

        IF NOT FOUND THEN RAISE EXCEPTION 'ORDER_NOT_FOUND_OR_NOT_OWNED'; END IF;
    ELSIF v_type='RESERVATION' THEN
        SELECT COALESCE(SUM(l.QTY_RESERVED*l.UNIT_PRICE),0)::NUMERIC(12,2),'GBP'
          INTO v_amount,v_currency
          FROM core.STOCK_RESERVATION r
          JOIN core.STOCK_RESERVATION_LINE l ON l.RESERVATION_ID=r.RESERVATION_ID
         WHERE r.CLIENT_ID=p_client_id
           AND r.RESERVATION_ID=p_reference_id::UUID
           AND r.STATUS='ACTIVE'
           AND (p_account_id IS NULL OR r.ACCOUNT_ID=p_account_id)
         GROUP BY r.RESERVATION_ID;

        IF NOT FOUND THEN RAISE EXCEPTION 'RESERVATION_NOT_FOUND_OR_NOT_OWNED'; END IF;
    ELSE
        RAISE EXCEPTION 'UNSUPPORTED_PAYMENT_REFERENCE';
    END IF;

    IF COALESCE(v_amount,0)<=0 THEN RAISE EXCEPTION 'PAYMENT_AMOUNT_NOT_POSITIVE'; END IF;

    SELECT * INTO v_payment
      FROM core.PAYMENT_TRANSACTION
     WHERE CLIENT_ID=p_client_id
       AND PROVIDER=v_provider
       AND IDEMPOTENCY_KEY=p_idempotency_key;

    IF NOT FOUND THEN
        INSERT INTO core.PAYMENT_TRANSACTION(
            CLIENT_ID,ACCOUNT_ID,PROVIDER,REFERENCE_TYPE,REFERENCE_ID,
            AMOUNT,CURRENCY,STATUS,IDEMPOTENCY_KEY
        )
        VALUES(
            p_client_id,p_account_id,v_provider,v_type,p_reference_id,
            v_amount,v_currency,'CREATED',p_idempotency_key
        )
        RETURNING * INTO v_payment;
    END IF;

    RETURN jsonb_build_object(
        'paymentId',v_payment.PAYMENT_ID,
        'provider',v_payment.PROVIDER,
        'referenceType',v_payment.REFERENCE_TYPE,
        'referenceId',v_payment.REFERENCE_ID,
        'amount',v_payment.AMOUNT,
        'currency',v_payment.CURRENCY,
        'status',v_payment.STATUS,
        'providerReference',v_payment.PROVIDER_REFERENCE,
        'idempotentReplay',v_payment.CREATED_DSTAMP<>v_payment.LAST_UPDATE_DSTAMP
    );
END;
$$;


--
-- Name: create_pending_web_order(character varying, jsonb, uuid, integer); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.create_pending_web_order(p_client_id character varying, p_payload jsonb, p_account_id uuid DEFAULT NULL::uuid, p_payment_timeout_minutes integer DEFAULT 30) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_result JSONB;
    v_alloc RECORD;
    v_order_id VARCHAR(20);
    v_email VARCHAR(254);
BEGIN
    v_result := api.SUBMIT_WEB_ORDER(p_client_id,p_payload);

    IF v_result->>'status'<>'ACCEPTED' THEN
        RETURN v_result;
    END IF;

    v_order_id := v_result->>'orderId';
    v_email := LOWER(NULLIF(TRIM(p_payload#>>'{customer,email}'),''));

    IF p_account_id IS NOT NULL THEN
        IF NOT api.CLAIM_ORDER_ACCOUNT(p_client_id,v_order_id,p_account_id,v_email) THEN
            RAISE EXCEPTION 'ORDER_ACCOUNT_CLAIM_FAILED';
        END IF;
    END IF;

    SELECT * INTO v_alloc FROM core.ALLOCATE_ORDER(p_client_id,v_order_id);

    IF v_alloc.RESULT_STATUS NOT IN ('ALLOCATED','ALREADY_ALLOCATED') THEN
        RAISE EXCEPTION 'ORDER_STOCK_RESERVATION_FAILED: %',v_alloc.RESULT_MESSAGE;
    END IF;

    UPDATE core.ORDER_HEADER
       SET STATUS='PENDING_PAYMENT',
           PAYMENT_STATUS='PENDING',
           FULFILMENT_STATUS='RESERVED',
           PAYMENT_DUE_DSTAMP=now() + make_interval(mins=>GREATEST(COALESCE(p_payment_timeout_minutes,30),5)),
           LAST_UPDATED_BY='WEB_API',
           LAST_UPDATE_DATE=now()
     WHERE CLIENT_ID=p_client_id AND ORDER_ID=v_order_id;

    RETURN v_result || jsonb_build_object(
        'status','PENDING_PAYMENT',
        'paymentStatus','PENDING',
        'fulfilmentStatus','RESERVED',
        'stockReserved',TRUE,
        'paymentDueAt',(
            SELECT PAYMENT_DUE_DSTAMP FROM core.ORDER_HEADER
            WHERE CLIENT_ID=p_client_id AND ORDER_ID=v_order_id
        )
    );
END;
$$;


--
-- Name: create_stock_reservation(character varying, jsonb); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.create_stock_reservation(p_client_id character varying, p_payload jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
DECLARE
 v_validation JSONB;
 v_res UUID; v_line BIGINT; v_item RECORD; v_inv RECORD; v_remaining NUMERIC; v_take NUMERIC;
 v_minutes INTEGER:=COALESCE(NULLIF(p_payload->>'holdMinutes','')::integer,2880); v_email TEXT; v_source TEXT;
BEGIN
 IF jsonb_typeof(COALESCE(p_payload->'items','[]'::jsonb))<>'array' OR jsonb_array_length(COALESCE(p_payload->'items','[]'::jsonb))=0 THEN RAISE EXCEPTION 'EMPTY_RESERVATION'; END IF;
 v_validation:=api.VALIDATE_BASKET(p_client_id,p_payload->'items');
 IF NOT COALESCE((v_validation->>'valid')::boolean,FALSE) THEN RAISE EXCEPTION 'RESERVATION_BASKET_INVALID: %',v_validation; END IF;
 v_email:=LOWER(NULLIF(TRIM(p_payload#>>'{customer,email}'),''));
 IF v_email IS NULL OR position('@' in v_email)<2 THEN RAISE EXCEPTION 'VALID_EMAIL_REQUIRED'; END IF;
 IF v_minutes<1 OR v_minutes>10080 THEN RAISE EXCEPTION 'INVALID_HOLD_MINUTES'; END IF;
 v_source:=NULLIF(TRIM(p_payload->>'idempotencyKey'),'');
 IF v_source IS NOT NULL THEN
   SELECT RESERVATION_ID INTO v_res FROM core.STOCK_RESERVATION WHERE CLIENT_ID=p_client_id AND SOURCE_SYSTEM='WEBSITE' AND SOURCE_REFERENCE=v_source;
   IF FOUND THEN RETURN api.GET_STOCK_RESERVATION(p_client_id,v_res); END IF;
 END IF;
 INSERT INTO core.STOCK_RESERVATION(CLIENT_ID,SOURCE_SYSTEM,SOURCE_REFERENCE,CONTACT_NAME,EMAIL,PHONE,FULFILMENT_METHOD,NOTES,EXPIRES_DSTAMP)
 VALUES(p_client_id,'WEBSITE',v_source,NULLIF(TRIM(p_payload#>>'{customer,name}'),''),v_email,NULLIF(TRIM(p_payload#>>'{customer,phone}'),''),
        NULLIF(UPPER(TRIM(p_payload->>'fulfilmentMethod')),''),NULLIF(TRIM(p_payload->>'notes'),''),now()+make_interval(mins=>v_minutes))
 RETURNING RESERVATION_ID INTO v_res;
 FOR v_item IN
   SELECT x.sku_id,x.qty,pv.WEB_PRICE,pv.MIN_ORDER_QTY,pv.MAX_ORDER_QTY,pv.QTY_INCREMENT
   FROM jsonb_to_recordset(p_payload->'items') x(sku_id VARCHAR,qty NUMERIC)
   JOIN core.PRODUCT_VARIANT pv ON pv.CLIENT_ID=p_client_id AND pv.SKU_ID=x.sku_id AND pv.ACTIVE=TRUE AND pv.AVAILABILITY_STATE='AVAILABLE'
 LOOP
   IF v_item.qty IS NULL OR v_item.qty<=0 OR v_item.qty<v_item.MIN_ORDER_QTY OR (v_item.MAX_ORDER_QTY IS NOT NULL AND v_item.qty>v_item.MAX_ORDER_QTY) THEN RAISE EXCEPTION 'INVALID_RESERVATION_QTY_FOR_%',v_item.sku_id; END IF;
   INSERT INTO core.STOCK_RESERVATION_LINE(RESERVATION_ID,CLIENT_ID,SKU_ID,QTY_RESERVED,UNIT_PRICE)
   VALUES(v_res,p_client_id,v_item.sku_id,v_item.qty,v_item.WEB_PRICE) RETURNING RESERVATION_LINE_ID INTO v_line;
   v_remaining:=v_item.qty;
   FOR v_inv IN
     SELECT i.KEY,GREATEST(COALESCE(i.QTY_ON_HAND,0)-COALESCE(i.QTY_ALLOCATED,0),0) available_qty
     FROM core.INVENTORY i JOIN core.LOCATION l ON l.LOCATION_ID=i.LOCATION_ID
     WHERE i.CLIENT_ID=p_client_id AND i.SKU_ID=v_item.sku_id
       AND COALESCE(i.DISALLOW_ALLOC,'N')<>'Y' AND COALESCE(l.DISALLOW_ALLOC,'N')<>'Y' AND COALESCE(l.ACTIVE,'Y')='Y'
       AND GREATEST(COALESCE(i.QTY_ON_HAND,0)-COALESCE(i.QTY_ALLOCATED,0),0)>0
     ORDER BY i.RECEIPT_DSTAMP NULLS LAST,i.KEY FOR UPDATE OF i SKIP LOCKED
   LOOP
     EXIT WHEN v_remaining<=0;
     v_take:=LEAST(v_remaining,v_inv.available_qty);
     UPDATE core.INVENTORY SET QTY_ALLOCATED=COALESCE(QTY_ALLOCATED,0)+v_take WHERE KEY=v_inv.KEY;
     INSERT INTO core.STOCK_RESERVATION_INVENTORY(RESERVATION_LINE_ID,INVENTORY_KEY,QTY_RESERVED) VALUES(v_line,v_inv.KEY,v_take);
     v_remaining:=v_remaining-v_take;
   END LOOP;
   IF v_remaining>0 THEN RAISE EXCEPTION 'INSUFFICIENT_STOCK_FOR_%',v_item.sku_id; END IF;
 END LOOP;
 IF NOT EXISTS(SELECT 1 FROM core.STOCK_RESERVATION_LINE WHERE RESERVATION_ID=v_res) THEN RAISE EXCEPTION 'NO_VALID_RESERVATION_ITEMS'; END IF;
 RETURN api.GET_STOCK_RESERVATION(p_client_id,v_res);
END; $$;


--
-- Name: expire_pending_payment_orders(character varying, integer); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.expire_pending_payment_orders(p_client_id character varying, p_limit integer DEFAULT 100) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
DECLARE
    r RECORD;
    v_dealloc RECORD;
    v_expired INTEGER := 0;
BEGIN
    FOR r IN
        SELECT ORDER_ID
          FROM core.ORDER_HEADER
         WHERE CLIENT_ID=p_client_id
           AND STATUS='PENDING_PAYMENT'
           AND PAYMENT_STATUS NOT IN ('PAID','AUTHORISED')
           AND PAYMENT_DUE_DSTAMP IS NOT NULL
           AND PAYMENT_DUE_DSTAMP<=now()
         ORDER BY PAYMENT_DUE_DSTAMP
         LIMIT GREATEST(COALESCE(p_limit,100),1)
         FOR UPDATE SKIP LOCKED
    LOOP
        SELECT * INTO v_dealloc FROM core.DEALLOCATE_ORDER(p_client_id,r.ORDER_ID);

        UPDATE core.ORDER_HEADER
           SET STATUS='CANCELLED',
               PAYMENT_STATUS='CANCELLED',
               FULFILMENT_STATUS='CANCELLED',
               LAST_UPDATED_BY='PAYMENT_EXPIRY',
               LAST_UPDATE_DATE=now()
         WHERE CLIENT_ID=p_client_id AND ORDER_ID=r.ORDER_ID;

        v_expired := v_expired + 1;
    END LOOP;

    RETURN jsonb_build_object('expiredOrders',v_expired);
END;
$$;


--
-- Name: expire_stock_reservations(character varying); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.expire_stock_reservations(p_client_id character varying) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE v RECORD; n INTEGER:=0;
BEGIN
 FOR v IN SELECT RESERVATION_ID FROM core.STOCK_RESERVATION WHERE CLIENT_ID=p_client_id AND STATUS='ACTIVE' AND EXPIRES_DSTAMP<=now() FOR UPDATE SKIP LOCKED LOOP
   PERFORM api.RELEASE_STOCK_RESERVATION(p_client_id,v.RESERVATION_ID,'EXPIRED'); n:=n+1;
 END LOOP;
 RETURN n;
END; $$;


--
-- Name: get_account(character varying, uuid); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.get_account(p_client_id character varying, p_account_id uuid) RETURNS jsonb
    LANGUAGE sql STABLE
    AS $$
SELECT jsonb_build_object(
    'accountId',a.ACCOUNT_ID,
    'customerId',a.CUSTOMER_ID,
    'email',a.EMAIL,
    'emailVerified',a.EMAIL_VERIFIED,
    'active',a.ACTIVE,
    'createdAt',a.CREATED_DSTAMP,
    'lastLoginAt',a.LAST_LOGIN_DSTAMP
)
FROM core.CUSTOMER_ACCOUNT a
WHERE a.CLIENT_ID=p_client_id
  AND a.ACCOUNT_ID=p_account_id
  AND a.ACTIVE=TRUE;
$$;


--
-- Name: get_account_addresses(character varying, uuid); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.get_account_addresses(p_client_id character varying, p_account_id uuid) RETURNS jsonb
    LANGUAGE sql STABLE
    AS $$
SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'addressId',m.ADDRESS_ID,
    'label',m.ADDRESS_LABEL,
    'defaultDelivery',m.DEFAULT_DELIVERY,
    'defaultBilling',m.DEFAULT_BILLING,
    'name',a.NAME,
    'contact',a.CONTACT,
    'phone',COALESCE(a.CONTACT_MOBILE,a.CONTACT_PHONE),
    'email',a.CONTACT_EMAIL,
    'address1',a.ADDRESS1,
    'address2',a.ADDRESS2,
    'town',a.TOWN,
    'county',a.COUNTY,
    'postcode',a.POSTCODE,
    'country',a.COUNTRY
) ORDER BY m.DEFAULT_DELIVERY DESC,m.DEFAULT_BILLING DESC,m.CREATED_DSTAMP DESC),'[]'::jsonb)
FROM core.CUSTOMER_ACCOUNT_ADDRESS m
JOIN core.ADDRESS a
  ON a.CLIENT_ID=m.CLIENT_ID AND a.ADDRESS_ID=m.ADDRESS_ID
WHERE m.CLIENT_ID=p_client_id
  AND m.ACCOUNT_ID=p_account_id
  AND m.ACTIVE=TRUE;
$$;


--
-- Name: get_account_interests(character varying, uuid); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.get_account_interests(p_client_id character varying, p_account_id uuid) RETURNS jsonb
    LANGUAGE sql STABLE
    AS $$
SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'interestId',i.INTEREST_ID,
    'interestType',i.INTEREST_TYPE,
    'productId',i.PRODUCT_ID,
    'skuId',i.SKU_ID,
    'requestedQty',i.REQUESTED_QTY,
    'status',i.STATUS,
    'createdAt',i.CREATED_DSTAMP,
    'notifiedAt',i.NOTIFIED_DSTAMP
) ORDER BY i.CREATED_DSTAMP DESC),'[]'::jsonb)
FROM core.CUSTOMER_INTEREST i
WHERE i.CLIENT_ID=p_client_id AND i.ACCOUNT_ID=p_account_id;
$$;


--
-- Name: get_account_orders(character varying, uuid); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.get_account_orders(p_client_id character varying, p_account_id uuid) RETURNS jsonb
    LANGUAGE sql STABLE
    AS $$
SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'orderId',h.ORDER_ID,
    'orderDate',h.ORDER_DATE,
    'status',h.STATUS,
    'paymentStatus',h.PAYMENT_STATUS,
    'fulfilmentStatus',h.FULFILMENT_STATUS,
    'dispatchMethod',h.DISPATCH_METHOD,
    'orderValue',h.ORDER_VALUE,
    'currency',h.INV_CURRENCY
) ORDER BY h.ORDER_DATE DESC),'[]'::jsonb)
FROM core.ORDER_HEADER h
WHERE h.CLIENT_ID=p_client_id AND h.ACCOUNT_ID=p_account_id;
$$;


--
-- Name: get_account_reservations(character varying, uuid); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.get_account_reservations(p_client_id character varying, p_account_id uuid) RETURNS jsonb
    LANGUAGE sql STABLE
    AS $$
SELECT COALESCE(jsonb_agg(api.GET_STOCK_RESERVATION(r.CLIENT_ID,r.RESERVATION_ID)
    ORDER BY r.CREATED_DSTAMP DESC),'[]'::jsonb)
FROM core.STOCK_RESERVATION r
WHERE r.CLIENT_ID=p_client_id AND r.ACCOUNT_ID=p_account_id;
$$;


--
-- Name: get_affiliate_demand(character varying, timestamp with time zone, timestamp with time zone); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.get_affiliate_demand(p_client_id character varying, p_from timestamp with time zone DEFAULT NULL::timestamp with time zone, p_to timestamp with time zone DEFAULT NULL::timestamp with time zone) RETURNS jsonb
    LANGUAGE sql STABLE
    AS $$
SELECT COALESCE(jsonb_agg(jsonb_build_object('productId',x.PRODUCT_ID,'productName',x.PRODUCT_NAME,'merchant',x.MERCHANT_NAME,'clicks',x.CLICKS) ORDER BY x.CLICKS DESC),'[]'::jsonb)
FROM (SELECT l.PRODUCT_ID,p.PRODUCT_NAME,l.MERCHANT_NAME,COUNT(*) CLICKS FROM audit.AFFILIATE_CLICK c JOIN core.PRODUCT_AFFILIATE_LINK l ON l.LINK_ID=c.LINK_ID JOIN core.PRODUCT p ON p.CLIENT_ID=l.CLIENT_ID AND p.PRODUCT_ID=l.PRODUCT_ID WHERE c.CLIENT_ID=p_client_id AND (p_from IS NULL OR c.CREATED_DSTAMP>=p_from) AND (p_to IS NULL OR c.CREATED_DSTAMP<p_to) GROUP BY l.PRODUCT_ID,p.PRODUCT_NAME,l.MERCHANT_NAME) x;
$$;


--
-- Name: get_affiliate_links(character varying, character varying); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.get_affiliate_links(p_client_id character varying, p_slug character varying) RETURNS jsonb
    LANGUAGE sql STABLE
    AS $$
SELECT COALESCE(jsonb_agg(jsonb_build_object('linkId',a.LINK_ID,'skuId',a.SKU_ID,'merchant',a.MERCHANT_NAME,'campaignCode',a.CAMPAIGN_CODE) ORDER BY a.SORT_SEQUENCE),'[]'::jsonb)
FROM core.PRODUCT_AFFILIATE_LINK a JOIN core.PRODUCT p ON p.CLIENT_ID=a.CLIENT_ID AND p.PRODUCT_ID=a.PRODUCT_ID
WHERE p.CLIENT_ID=p_client_id AND p.SLUG=p_slug AND p.ACTIVE=TRUE AND a.ACTIVE=TRUE;
$$;


--
-- Name: get_catalog(character varying, character varying); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.get_catalog(p_client_id character varying, p_category_slug character varying DEFAULT NULL::character varying) RETURNS jsonb
    LANGUAGE sql STABLE
    AS $$
SELECT COALESCE(jsonb_agg(jsonb_build_object(
 'productId',x.PRODUCT_ID,'name',x.PRODUCT_NAME,'slug',x.SLUG,'brand',x.BRAND_NAME,
 'productType',x.PRODUCT_TYPE,'category',jsonb_build_object('code',x.CATEGORY_CODE,'name',x.CATEGORY_NAME,'slug',x.CATEGORY_SLUG),
 'shortDescription',x.SHORT_DESCRIPTION,'deliveryClass',x.DELIVERY_CLASS,'currency',x.CURRENCY,
 'fromPrice',x.FROM_PRICE,'toPrice',x.TO_PRICE,'availableQty',x.AVAILABLE_QTY,
 'availabilityStates',x.AVAILABILITY_STATES,'saleTypes',x.SALE_TYPES,'featured',x.FEATURED,
 'media',api.GET_PRODUCT_MEDIA(x.CLIENT_ID,x.PRODUCT_ID)
) ORDER BY x.SORT_SEQUENCE,x.PRODUCT_NAME),'[]'::jsonb)
FROM api.CATALOG_PRODUCT_LIST x
WHERE x.CLIENT_ID=p_client_id AND (p_category_slug IS NULL OR x.CATEGORY_SLUG=p_category_slug);
$$;


--
-- Name: get_categories(character varying); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.get_categories(p_client_id character varying) RETURNS jsonb
    LANGUAGE sql STABLE
    AS $$
SELECT COALESCE(jsonb_agg(jsonb_build_object(
 'code',c.CATEGORY_CODE,'parentCode',c.PARENT_CATEGORY_CODE,'name',c.CATEGORY_NAME,
 'slug',c.SLUG,'description',c.DESCRIPTION,'sortSequence',c.SORT_SEQUENCE
) ORDER BY c.SORT_SEQUENCE,c.CATEGORY_NAME),'[]'::jsonb)
FROM core.PRODUCT_CATEGORY c WHERE c.CLIENT_ID=p_client_id AND c.ACTIVE=TRUE;
$$;


--
-- Name: get_delivery_options(character varying, jsonb); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.get_delivery_options(p_client_id character varying, p_payload jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE v_basket JSONB; v_options JSONB:='[]'::jsonb; v_postcode TEXT; v_country TEXT; v_subtotal NUMERIC; v_has_livestock BOOLEAN; v_carrier_enabled BOOLEAN:=TRUE; z RECORD;
BEGIN
 v_basket:=api.VALIDATE_BASKET(p_client_id,COALESCE(p_payload->'items','[]'::jsonb));
 IF NOT COALESCE((v_basket->>'valid')::boolean,FALSE) THEN RETURN jsonb_build_object('valid',FALSE,'basket',v_basket,'fulfilmentOptions','[]'::jsonb); END IF;
 v_postcode:=regexp_replace(UPPER(COALESCE(p_payload#>>'{deliveryAddress,postcode}','')),'[[:space:]]','','g');
 v_country:=UPPER(COALESCE(NULLIF(TRIM(p_payload#>>'{deliveryAddress,country}'),''),'GB'));
 v_subtotal:=COALESCE((v_basket->>'subtotal')::numeric,0); v_has_livestock:=COALESCE((v_basket->>'hasLivestock')::boolean,FALSE);
 v_options:=v_options||jsonb_build_array(jsonb_build_object('code','COLLECTION','label','Collection by arrangement','fulfilmentMethod','COLLECTION','price',0,'currency',v_basket->>'currency','requiresManualConfirmation',TRUE));
 FOR z IN SELECT * FROM config.DELIVERY_ZONE dz WHERE dz.CLIENT_ID=p_client_id AND dz.ACTIVE=TRUE AND UPPER(dz.COUNTRY)=v_country AND (dz.POSTCODE_PREFIX IS NULL OR v_postcode LIKE regexp_replace(UPPER(dz.POSTCODE_PREFIX),'[[:space:]]','','g')||'%') AND (dz.MIN_ORDER_VALUE IS NULL OR v_subtotal>=dz.MIN_ORDER_VALUE) ORDER BY dz.PRIORITY LOOP
   v_options:=v_options||jsonb_build_array(jsonb_build_object('code',z.ZONE_ID,'label',z.ZONE_NAME,'fulfilmentMethod',z.FULFILMENT_METHOD,'price',z.DELIVERY_PRICE,'currency',z.CURRENCY,'requiresManualConfirmation',z.REQUIRES_MANUAL_CONFIRMATION));
 END LOOP;
 IF v_has_livestock THEN
   SELECT CARRIER_DESPATCH_ENABLED INTO v_carrier_enabled FROM config.DELIVERY_CLASS_CONTROL WHERE CLIENT_ID=p_client_id AND UPPER(DELIVERY_CLASS)='LIVESTOCK';
   IF NOT FOUND THEN v_carrier_enabled:=TRUE; END IF;
   IF v_carrier_enabled THEN v_options:=v_options||jsonb_build_array(jsonb_build_object('code','LIVESTOCK_CARRIER','label','Livestock courier','fulfilmentMethod','CARRIER','price',NULL,'currency',v_basket->>'currency','requiresManualConfirmation',TRUE)); END IF;
   v_options:=v_options||jsonb_build_array(jsonb_build_object('code','MEET_POINT','label','Meet halfway / arranged handover','fulfilmentMethod','MEET_POINT','price',NULL,'currency',v_basket->>'currency','requiresManualConfirmation',TRUE));
 ELSE
   v_options:=v_options||jsonb_build_array(jsonb_build_object('code','STANDARD_CARRIER','label','Delivery','fulfilmentMethod','CARRIER','price',NULL,'currency',v_basket->>'currency','requiresManualConfirmation',TRUE));
 END IF;
 RETURN jsonb_build_object('valid',TRUE,'basket',v_basket,'fulfilmentOptions',v_options);
END; $$;


--
-- Name: get_gift_card_balance(character varying, character varying); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.get_gift_card_balance(p_client_id character varying, p_code character varying) RETURNS jsonb
    LANGUAGE sql STABLE
    AS $$
SELECT jsonb_build_object('valid',STATUS='ACTIVE' AND (EXPIRES_DSTAMP IS NULL OR EXPIRES_DSTAMP>now()),'currency',CURRENCY,'balance',BALANCE,'status',STATUS,'expiresAt',EXPIRES_DSTAMP)
FROM core.GIFT_CARD WHERE CLIENT_ID=p_client_id AND UPPER(GIFT_CODE)=UPPER(TRIM(p_code));
$$;


--
-- Name: get_interest_contacts(character varying, character varying); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.get_interest_contacts(p_client_id character varying, p_sku_id character varying) RETURNS jsonb
    LANGUAGE sql STABLE
    AS $$
SELECT COALESCE(jsonb_agg(jsonb_build_object('interestId',INTEREST_ID,'type',INTEREST_TYPE,'requestedQty',REQUESTED_QTY,'name',CONTACT_NAME,'email',EMAIL,'phone',PHONE,'preferredChannel',PREFERRED_CHANNEL,'createdAt',CREATED_DSTAMP) ORDER BY CREATED_DSTAMP),'[]'::jsonb)
FROM core.CUSTOMER_INTEREST WHERE CLIENT_ID=p_client_id AND SKU_ID=p_sku_id AND STATUS='ACTIVE' AND CONSENT_TO_NOTIFY=TRUE;
$$;


--
-- Name: get_interest_summary(character varying, character varying); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.get_interest_summary(p_client_id character varying, p_sku_id character varying) RETURNS jsonb
    LANGUAGE sql STABLE
    AS $$
SELECT jsonb_build_object(
 'skuId',p_sku_id,
 'activeCount',COUNT(*) FILTER(WHERE STATUS='ACTIVE'),
 'requestedQty',COALESCE(SUM(REQUESTED_QTY) FILTER(WHERE STATUS='ACTIVE'),0),
 'byType',jsonb_build_object(
   'waitlist',COUNT(*) FILTER(WHERE STATUS='ACTIVE' AND INTEREST_TYPE='WAITLIST'),
   'growingStock',COUNT(*) FILTER(WHERE STATUS='ACTIVE' AND INTEREST_TYPE='GROWING_STOCK')
 ))
FROM core.CUSTOMER_INTEREST WHERE CLIENT_ID=p_client_id AND SKU_ID=p_sku_id;
$$;


--
-- Name: get_order_status(character varying, character varying); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.get_order_status(p_client_id character varying, p_order_id character varying) RETURNS jsonb
    LANGUAGE sql STABLE
    AS $$
SELECT jsonb_build_object(
    'orderId',h.ORDER_ID,
    'orderDate',h.ORDER_DATE,
    'status',h.STATUS,
    'paymentStatus',h.PAYMENT_STATUS,
    'fulfilmentStatus',h.FULFILMENT_STATUS,
    'fulfilmentPreference',h.FULFILMENT_PREFERENCE,
    'dispatchMethod',h.DISPATCH_METHOD,
    'serviceLevel',h.SERVICE_LEVEL,
    'orderValue',h.ORDER_VALUE,
    'currency',h.INV_CURRENCY,
    'deliveryAddress',jsonb_build_object(
        'name',h.NAME,
        'address1',h.ADDRESS1,
        'address2',h.ADDRESS2,
        'town',h.TOWN,
        'county',h.COUNTY,
        'postcode',h.POSTCODE,
        'country',h.COUNTRY
    ),
    'lines',COALESCE((
        SELECT jsonb_agg(
            jsonb_build_object(
                'lineId',l.LINE_ID,
                'skuId',l.SKU_ID,
                'qtyOrdered',l.QTY_ORDERED,
                'qtyAllocated',l.QTY_SOFT_ALLOCATED,
                'qtyPicked',l.QTY_PICKED,
                'qtyShipped',l.QTY_SHIPPED,
                'unitPrice',l.PRODUCT_PRICE,
                'lineValue',COALESCE(l.EXTENDED_PRICE,l.PRODUCT_PRICE*l.QTY_ORDERED)
            )
            ORDER BY l.LINE_ID
        )
        FROM core.ORDER_LINE l
        WHERE l.CLIENT_ID=h.CLIENT_ID
          AND l.ORDER_ID=h.ORDER_ID
    ),'[]'::jsonb),
    'shipments',COALESCE((
        SELECT jsonb_agg(s.shipment ORDER BY s.container_id)
        FROM (
            SELECT
                sm.CONTAINER_ID AS container_id,
                jsonb_build_object(
                    'containerId',sm.CONTAINER_ID,
                    'status',MAX(sm.STATUS),
                    'carrierId',MAX(sm.CARRIER_ID),
                    'serviceLevel',MAX(sm.SERVICE_LEVEL),
                    'trackingNumber',MAX(sm.TRACKING_NUMBER),
                    'trackingUrl',MAX(sm.TRACKING_URL),
                    'trackingStatus',MAX(sm.TRACKING_STATUS),
                    'qtyShipped',SUM(COALESCE(sm.QTY_SHIPPED,0))
                ) AS shipment
            FROM core.SHIPPING_MANIFEST sm
            WHERE sm.CLIENT_ID=h.CLIENT_ID
              AND sm.ORDER_ID=h.ORDER_ID
            GROUP BY sm.CONTAINER_ID
        ) s
    ),'[]'::jsonb)
)
FROM core.ORDER_HEADER h
WHERE h.CLIENT_ID=p_client_id
  AND h.ORDER_ID=p_order_id;
$$;


--
-- Name: get_payment_status(character varying, uuid, uuid); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.get_payment_status(p_client_id character varying, p_payment_id uuid, p_account_id uuid DEFAULT NULL::uuid) RETURNS jsonb
    LANGUAGE sql STABLE
    AS $$
SELECT jsonb_build_object(
    'paymentId',p.PAYMENT_ID,
    'provider',p.PROVIDER,
    'referenceType',p.REFERENCE_TYPE,
    'referenceId',p.REFERENCE_ID,
    'amount',p.AMOUNT,
    'currency',p.CURRENCY,
    'status',p.STATUS,
    'capturedAmount',p.CAPTURED_AMOUNT,
    'refundedAmount',p.REFUNDED_AMOUNT,
    'failureCode',p.FAILURE_CODE,
    'failureText',p.FAILURE_TEXT,
    'createdAt',p.CREATED_DSTAMP,
    'updatedAt',p.LAST_UPDATE_DSTAMP
)
FROM core.PAYMENT_TRANSACTION p
WHERE p.CLIENT_ID=p_client_id
  AND p.PAYMENT_ID=p_payment_id
  AND (p_account_id IS NULL OR p.ACCOUNT_ID=p_account_id);
$$;


--
-- Name: get_product(character varying, character varying); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.get_product(p_client_id character varying, p_slug character varying) RETURNS jsonb
    LANGUAGE sql STABLE
    AS $$
SELECT jsonb_build_object(
 'productId',p.PRODUCT_ID,'name',p.PRODUCT_NAME,'slug',p.SLUG,'brand',p.BRAND_NAME,'productType',p.PRODUCT_TYPE,
 'category',jsonb_build_object('code',p.CATEGORY_CODE,'name',c.CATEGORY_NAME,'slug',c.SLUG),
 'shortDescription',p.SHORT_DESCRIPTION,'description',p.DESCRIPTION,'deliveryClass',p.DELIVERY_CLASS,
 'currency',p.CURRENCY,'media',api.GET_PRODUCT_MEDIA(p.CLIENT_ID,p.PRODUCT_ID),
 'specification',p.SPECIFICATION,'searchMetadata',p.SEARCH_METADATA,
 'variants',COALESCE((SELECT jsonb_agg(jsonb_build_object(
   'skuId',v.SKU_ID,'name',v.VARIANT_NAME,'options',v.OPTION_VALUES,'price',v.WEB_PRICE,
   'compareAtPrice',v.COMPARE_AT_PRICE,'availableQty',v.AVAILABLE_QTY,'available',v.AVAILABLE_QTY>0,
   'saleType',v.SALE_TYPE,'availabilityState',v.AVAILABILITY_STATE,
   'expectedAvailableFrom',v.EXPECTED_AVAILABLE_FROM,'expectedAvailableTo',v.EXPECTED_AVAILABLE_TO,
   'metadata',v.WEB_METADATA,'minOrderQty',v.MIN_ORDER_QTY,'maxOrderQty',v.MAX_ORDER_QTY,'qtyIncrement',v.QTY_INCREMENT
 ) ORDER BY v.SKU_ID) FROM api.CATALOG_VARIANT_AVAILABILITY v WHERE v.CLIENT_ID=p.CLIENT_ID AND v.PRODUCT_ID=p.PRODUCT_ID AND v.ACTIVE=TRUE),'[]'::jsonb),
 'affiliateLinks',COALESCE((SELECT jsonb_agg(jsonb_build_object('linkId',a.LINK_ID,'skuId',a.SKU_ID,'merchant',a.MERCHANT_NAME,'campaignCode',a.CAMPAIGN_CODE) ORDER BY a.SORT_SEQUENCE) FROM core.PRODUCT_AFFILIATE_LINK a WHERE a.CLIENT_ID=p.CLIENT_ID AND a.PRODUCT_ID=p.PRODUCT_ID AND a.ACTIVE=TRUE),'[]'::jsonb)
)
FROM core.PRODUCT p LEFT JOIN core.PRODUCT_CATEGORY c ON c.CLIENT_ID=p.CLIENT_ID AND c.CATEGORY_CODE=p.CATEGORY_CODE
WHERE p.CLIENT_ID=p_client_id AND p.SLUG=p_slug AND p.ACTIVE=TRUE;
$$;


--
-- Name: get_product_favourites(character varying, uuid); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.get_product_favourites(p_client_id character varying, p_account_id uuid) RETURNS jsonb
    LANGUAGE sql STABLE
    AS $$
SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'productId',p.PRODUCT_ID,
    'slug',p.SLUG,
    'productName',p.PRODUCT_NAME,
    'brandName',p.BRAND_NAME,
    'categoryCode',p.CATEGORY_CODE,
    'deliveryClass',p.DELIVERY_CLASS,
    'createdAt',f.CREATED_DSTAMP
) ORDER BY f.CREATED_DSTAMP DESC),'[]'::jsonb)
FROM core.PRODUCT_FAVOURITE f
JOIN core.PRODUCT p
  ON p.CLIENT_ID=f.CLIENT_ID AND p.PRODUCT_ID=f.PRODUCT_ID
WHERE f.CLIENT_ID=p_client_id AND f.ACCOUNT_ID=p_account_id;
$$;


--
-- Name: get_product_media(character varying, character varying); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.get_product_media(p_client_id character varying, p_product_id character varying) RETURNS jsonb
    LANGUAGE sql STABLE
    AS $$
SELECT COALESCE(jsonb_agg(jsonb_build_object(
  'mediaId',m.MEDIA_ID,'skuId',m.SKU_ID,'type',m.MEDIA_TYPE,'role',m.MEDIA_ROLE,
  'url',m.MEDIA_URL,'thumbnailUrl',m.THUMBNAIL_URL,'altText',m.ALT_TEXT,
  'caption',m.CAPTION,'sortSequence',m.SORT_SEQUENCE
) ORDER BY m.SORT_SEQUENCE,m.CREATED_DSTAMP),'[]'::jsonb)
FROM core.PRODUCT_MEDIA m
WHERE m.CLIENT_ID=p_client_id AND m.PRODUCT_ID=p_product_id AND m.ACTIVE=TRUE;
$$;


--
-- Name: get_product_reviews(character varying, character varying); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.get_product_reviews(p_client_id character varying, p_slug character varying) RETURNS jsonb
    LANGUAGE sql STABLE
    AS $$
WITH p AS (SELECT PRODUCT_ID FROM core.PRODUCT WHERE CLIENT_ID=p_client_id AND SLUG=p_slug AND ACTIVE=TRUE), r AS (
 SELECT pr.* FROM core.PRODUCT_REVIEW pr JOIN p ON p.PRODUCT_ID=pr.PRODUCT_ID WHERE pr.CLIENT_ID=p_client_id AND pr.STATUS='APPROVED'
)
SELECT jsonb_build_object('averageRating',ROUND(AVG(RATING)::numeric,2),'reviewCount',COUNT(*),'reviews',COALESCE(jsonb_agg(jsonb_build_object('reviewId',REVIEW_ID,'displayName',DISPLAY_NAME,'rating',RATING,'title',REVIEW_TITLE,'text',REVIEW_TEXT,'verifiedPurchase',VERIFIED_PURCHASE,'publishedAt',PUBLISHED_DSTAMP) ORDER BY PUBLISHED_DSTAMP DESC) FILTER(WHERE REVIEW_ID IS NOT NULL),'[]'::jsonb)) FROM r;
$$;


--
-- Name: get_stock_reservation(character varying, uuid); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.get_stock_reservation(p_client_id character varying, p_reservation_id uuid) RETURNS jsonb
    LANGUAGE sql STABLE
    AS $$
SELECT jsonb_build_object(
 'reservationId',r.RESERVATION_ID,'status',r.STATUS,'expiresAt',r.EXPIRES_DSTAMP,
 'fulfilmentMethod',r.FULFILMENT_METHOD,'email',r.EMAIL,
 'items',COALESCE((SELECT jsonb_agg(jsonb_build_object('skuId',l.SKU_ID,'qty',l.QTY_RESERVED,'unitPrice',l.UNIT_PRICE) ORDER BY l.RESERVATION_LINE_ID)
                   FROM core.STOCK_RESERVATION_LINE l WHERE l.RESERVATION_ID=r.RESERVATION_ID),'[]'::jsonb)
) FROM core.STOCK_RESERVATION r WHERE r.CLIENT_ID=p_client_id AND r.RESERVATION_ID=p_reservation_id;
$$;


--
-- Name: get_system_version(); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.get_system_version() RETURNS jsonb
    LANGUAGE sql STABLE
    AS $$
    SELECT jsonb_build_object(
        'productCode', sv.PRODUCT_CODE,
        'productName', sv.PRODUCT_NAME,
        'version', sv.VERSION_NUMBER,
        'major', sv.VERSION_MAJOR,
        'minor', sv.VERSION_MINOR,
        'patch', sv.VERSION_PATCH,
        'build', sv.BUILD_NUMBER,
        'releaseChannel', sv.RELEASE_CHANNEL,
        'releaseDate', sv.RELEASE_DATE,
        'description', sv.DESCRIPTION,
        'installedAt', sv.INSTALLED_DSTAMP
    )
    FROM config.SYSTEM_VERSION sv
    WHERE sv.PRODUCT_CODE='DYNETIC_WMS'
      AND sv.IS_CURRENT=TRUE
    ORDER BY sv.VERSION_KEY DESC
    LIMIT 1;
$$;


--
-- Name: mark_interest_notified(character varying, jsonb); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.mark_interest_notified(p_client_id character varying, p_interest_ids jsonb) RETURNS integer
    LANGUAGE plpgsql
    AS $$ DECLARE n INTEGER; BEGIN
 UPDATE core.CUSTOMER_INTEREST SET STATUS='NOTIFIED',NOTIFIED_DSTAMP=now(),LAST_UPDATE_DSTAMP=now()
 WHERE CLIENT_ID=p_client_id AND STATUS='ACTIVE' AND INTEREST_ID IN (SELECT value::uuid FROM jsonb_array_elements_text(COALESCE(p_interest_ids,'[]'::jsonb))); GET DIAGNOSTICS n=ROW_COUNT; RETURN n; END; $$;


--
-- Name: moderate_product_review(character varying, uuid, character varying); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.moderate_product_review(p_client_id character varying, p_review_id uuid, p_decision character varying) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$ DECLARE d VARCHAR:=UPPER(p_decision); BEGIN
 IF d NOT IN ('APPROVED','REJECTED') THEN RAISE EXCEPTION 'INVALID_REVIEW_DECISION'; END IF;
 UPDATE core.PRODUCT_REVIEW SET STATUS=d,PUBLISHED_DSTAMP=CASE WHEN d='APPROVED' THEN now() ELSE NULL END WHERE CLIENT_ID=p_client_id AND REVIEW_ID=p_review_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'REVIEW_NOT_FOUND'; END IF; RETURN jsonb_build_object('reviewId',p_review_id,'status',d); END; $$;


--
-- Name: normalize_gb_phone(text); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.normalize_gb_phone(p_value text) RETURNS text
    LANGUAGE plpgsql IMMUTABLE
    AS $_$
DECLARE
    v_phone TEXT;
BEGIN
    IF p_value IS NULL OR BTRIM(p_value) = '' THEN
        RETURN NULL;
    END IF;

    v_phone := regexp_replace(BTRIM(p_value), '[[:space:]().-]', '', 'g');

    IF v_phone LIKE '0044%' THEN
        v_phone := '+44' || SUBSTRING(v_phone FROM 5);
    ELSIF v_phone LIKE '+44%' THEN
        NULL;
    ELSIF v_phone LIKE '0%' AND v_phone NOT LIKE '00%' THEN
        v_phone := '+44' || SUBSTRING(v_phone FROM 2);
    ELSE
        RETURN NULL;
    END IF;

    IF v_phone !~ '^\+44[1-9][0-9]{9}$' THEN
        RETURN NULL;
    END IF;

    RETURN v_phone;
END;
$_$;


--
-- Name: normalize_gb_postcode(text); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.normalize_gb_postcode(p_value text) RETURNS text
    LANGUAGE plpgsql IMMUTABLE
    AS $_$
DECLARE
    v_postcode TEXT;
BEGIN
    IF p_value IS NULL OR BTRIM(p_value) = '' THEN
        RETURN NULL;
    END IF;

    v_postcode := UPPER(regexp_replace(BTRIM(p_value), '[[:space:]]', '', 'g'));

    IF v_postcode !~ '^(GIR0AA|[A-Z]{1,2}[0-9][0-9A-Z]?[0-9][A-Z]{2})$' THEN
        RETURN NULL;
    END IF;

    RETURN LEFT(v_postcode, LENGTH(v_postcode) - 3) || ' ' || RIGHT(v_postcode, 3);
END;
$_$;


--
-- Name: prepare_payment(character varying, jsonb); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.prepare_payment(p_client_id character varying, p_payload jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
DECLARE v_id UUID; v_provider VARCHAR; v_key TEXT;
BEGIN
 v_provider:=UPPER(COALESCE(NULLIF(TRIM(p_payload->>'provider'),''),'STRIPE')); v_key:=NULLIF(TRIM(p_payload->>'idempotencyKey'),'');
 IF v_provider NOT IN ('STRIPE','PAYPAL') THEN RAISE EXCEPTION 'UNSUPPORTED_PAYMENT_PROVIDER'; END IF;
 IF COALESCE(NULLIF(p_payload->>'amount','')::numeric,0)<=0 OR NULLIF(TRIM(p_payload->>'referenceId'),'') IS NULL THEN RAISE EXCEPTION 'INVALID_PAYMENT_REQUEST'; END IF;
 IF v_key IS NOT NULL THEN SELECT PAYMENT_ID INTO v_id FROM core.PAYMENT_TRANSACTION WHERE CLIENT_ID=p_client_id AND PROVIDER=v_provider AND IDEMPOTENCY_KEY=v_key; END IF;
 IF v_id IS NULL THEN
   INSERT INTO core.PAYMENT_TRANSACTION(CLIENT_ID,PROVIDER,REFERENCE_TYPE,REFERENCE_ID,AMOUNT,CURRENCY,IDEMPOTENCY_KEY)
   VALUES(p_client_id,v_provider,UPPER(COALESCE(NULLIF(TRIM(p_payload->>'referenceType'),''),'ORDER')),TRIM(p_payload->>'referenceId'),(p_payload->>'amount')::numeric,UPPER(COALESCE(NULLIF(TRIM(p_payload->>'currency'),''),'GBP')),v_key)
   RETURNING PAYMENT_ID INTO v_id;
 END IF;
 RETURN jsonb_build_object('paymentId',v_id,'provider',v_provider,'status','CREATED','providerIntegrated',FALSE,'requiresProviderAction',TRUE);
END; $$;


--
-- Name: process_payment_event(character varying, character varying, character varying, character varying, character varying, jsonb); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.process_payment_event(p_client_id character varying, p_provider character varying, p_provider_event_id character varying, p_event_type character varying, p_provider_reference character varying, p_payload jsonb) RETURNS jsonb
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


--
-- Name: quote_checkout(character varying, jsonb); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.quote_checkout(p_client_id character varying, p_payload jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    v_delivery JSONB;
    v_basket JSONB;
    v_promo JSONB;
    v_discount NUMERIC := 0;
    v_total_before_delivery NUMERIC := 0;
    v_selected_code TEXT;
    v_selected JSONB;
    v_freight_cost NUMERIC;
    v_total NUMERIC;
    v_free_delivery BOOLEAN := FALSE;
    v_payment_ready BOOLEAN := FALSE;
BEGIN
    v_delivery := api.GET_DELIVERY_OPTIONS(p_client_id,p_payload);
    v_basket := v_delivery->'basket';

    IF NOT COALESCE((v_delivery->>'valid')::BOOLEAN,FALSE) THEN
        RETURN v_delivery;
    END IF;

    IF NULLIF(TRIM(p_payload->>'promoCode'),'') IS NOT NULL THEN
        v_promo := api.VALIDATE_PROMOTION(
            p_client_id,
            p_payload->>'promoCode',
            (v_basket->>'subtotal')::NUMERIC,
            NULL
        );

        IF NOT COALESCE((v_promo->>'valid')::BOOLEAN,FALSE) THEN
            RETURN jsonb_build_object(
                'valid',FALSE,
                'code','PROMOTION_INVALID',
                'basket',v_basket,
                'promotion',v_promo,
                'discountAmount',0,
                'totalBeforeDelivery',(v_basket->>'subtotal')::NUMERIC,
                'fulfilmentOptions',v_delivery->'fulfilmentOptions'
            );
        END IF;

        v_discount := COALESCE((v_promo->>'discountAmount')::NUMERIC,0);
        v_free_delivery := COALESCE((v_promo->>'freeDelivery')::BOOLEAN,FALSE);
    END IF;

    v_total_before_delivery :=
        GREATEST((v_basket->>'subtotal')::NUMERIC - v_discount,0);

    v_selected_code := NULLIF(TRIM(p_payload->>'fulfilmentOptionCode'),'');

    IF v_selected_code IS NOT NULL THEN
        SELECT e.value
          INTO v_selected
          FROM jsonb_array_elements(
              COALESCE(v_delivery->'fulfilmentOptions','[]'::jsonb)
          ) AS e(value)
         WHERE UPPER(e.value->>'code') = UPPER(v_selected_code)
         LIMIT 1;

        IF v_selected IS NULL THEN
            RETURN jsonb_build_object(
                'valid',FALSE,
                'code','FULFILMENT_OPTION_NOT_AVAILABLE',
                'basket',v_basket,
                'promotion',v_promo,
                'discountAmount',v_discount,
                'totalBeforeDelivery',v_total_before_delivery,
                'fulfilmentOptions',v_delivery->'fulfilmentOptions'
            );
        END IF;

        IF UPPER(COALESCE(v_selected->>'currency',v_basket->>'currency')) <>
           UPPER(COALESCE(v_basket->>'currency','GBP')) THEN
            RETURN jsonb_build_object(
                'valid',FALSE,
                'code','FULFILMENT_CURRENCY_MISMATCH',
                'basket',v_basket,
                'promotion',v_promo,
                'selectedFulfilmentOption',v_selected,
                'fulfilmentOptions',v_delivery->'fulfilmentOptions'
            );
        END IF;

        IF jsonb_typeof(v_selected->'price') = 'number' THEN
            v_payment_ready := TRUE;
            v_freight_cost :=
                CASE
                    WHEN v_free_delivery THEN 0
                    ELSE (v_selected->>'price')::NUMERIC
                END;
            v_total := v_total_before_delivery + v_freight_cost;
        END IF;
    END IF;

    RETURN jsonb_build_object(
        'valid',TRUE,
        'basket',v_basket,
        'promotion',v_promo,
        'discountAmount',v_discount,
        'totalBeforeDelivery',v_total_before_delivery,
        'fulfilmentOptions',v_delivery->'fulfilmentOptions',
        'selectedFulfilmentOption',v_selected,
        'freightCost',v_freight_cost,
        'freeDelivery',v_free_delivery,
        'paymentReady',v_payment_ready,
        'total',v_total
    );
END;
$$;


--
-- Name: record_affiliate_click(character varying, uuid, jsonb); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.record_affiliate_click(p_client_id character varying, p_link_id uuid, p_payload jsonb DEFAULT '{}'::jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
DECLARE v_url TEXT; v_click UUID;
BEGIN
 SELECT DESTINATION_URL INTO v_url FROM core.PRODUCT_AFFILIATE_LINK WHERE CLIENT_ID=p_client_id AND LINK_ID=p_link_id AND ACTIVE=TRUE;
 IF NOT FOUND THEN RAISE EXCEPTION 'AFFILIATE_LINK_NOT_FOUND'; END IF;
 INSERT INTO audit.AFFILIATE_CLICK(CLIENT_ID,LINK_ID,SESSION_ID,SOURCE,REFERRER,USER_AGENT)
 VALUES(p_client_id,p_link_id,NULLIF(TRIM(p_payload->>'sessionId'),''),NULLIF(TRIM(p_payload->>'source'),''),NULLIF(TRIM(p_payload->>'referrer'),''),NULLIF(TRIM(p_payload->>'userAgent'),''))
 RETURNING CLICK_ID INTO v_click;
 RETURN jsonb_build_object('clickId',v_click,'destinationUrl',v_url);
END; $$;


--
-- Name: release_stock_reservation(character varying, uuid, character varying); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.release_stock_reservation(p_client_id character varying, p_reservation_id uuid, p_status character varying DEFAULT 'RELEASED'::character varying) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
DECLARE v_status VARCHAR:=UPPER(COALESCE(p_status,'RELEASED'));
BEGIN
 IF v_status NOT IN ('RELEASED','EXPIRED','CANCELLED') THEN RAISE EXCEPTION 'INVALID_RELEASE_STATUS'; END IF;
 IF NOT EXISTS(SELECT 1 FROM core.STOCK_RESERVATION WHERE CLIENT_ID=p_client_id AND RESERVATION_ID=p_reservation_id AND STATUS='ACTIVE' FOR UPDATE) THEN
   RETURN api.GET_STOCK_RESERVATION(p_client_id,p_reservation_id);
 END IF;
 UPDATE core.INVENTORY i SET QTY_ALLOCATED=GREATEST(COALESCE(i.QTY_ALLOCATED,0)-x.qty,0)
 FROM (SELECT ri.INVENTORY_KEY,SUM(ri.QTY_RESERVED) qty FROM core.STOCK_RESERVATION_INVENTORY ri JOIN core.STOCK_RESERVATION_LINE rl ON rl.RESERVATION_LINE_ID=ri.RESERVATION_LINE_ID WHERE rl.RESERVATION_ID=p_reservation_id GROUP BY ri.INVENTORY_KEY) x
 WHERE i.KEY=x.INVENTORY_KEY;
 UPDATE core.STOCK_RESERVATION SET STATUS=v_status,LAST_UPDATE_DSTAMP=now() WHERE CLIENT_ID=p_client_id AND RESERVATION_ID=p_reservation_id;
 RETURN api.GET_STOCK_RESERVATION(p_client_id,p_reservation_id);
END; $$;


--
-- Name: save_account_address(character varying, uuid, jsonb); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.save_account_address(p_client_id character varying, p_account_id uuid, p_payload jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_address_id VARCHAR(15);
    v_default_delivery BOOLEAN := COALESCE((p_payload->>'defaultDelivery')::BOOLEAN,FALSE);
    v_default_billing BOOLEAN := COALESCE((p_payload->>'defaultBilling')::BOOLEAN,FALSE);
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM core.CUSTOMER_ACCOUNT
        WHERE CLIENT_ID=p_client_id AND ACCOUNT_ID=p_account_id AND ACTIVE=TRUE
    ) THEN
        RAISE EXCEPTION 'ACCOUNT_NOT_FOUND';
    END IF;

    IF NULLIF(TRIM(p_payload->>'address1'),'') IS NULL
       OR NULLIF(TRIM(p_payload->>'town'),'') IS NULL
       OR NULLIF(TRIM(p_payload->>'postcode'),'') IS NULL THEN
        RAISE EXCEPTION 'ADDRESS_REQUIRED_FIELDS_MISSING';
    END IF;

    v_address_id := 'A' || UPPER(SUBSTRING(REPLACE(gen_random_uuid()::TEXT,'-','') FROM 1 FOR 14));

    INSERT INTO core.ADDRESS(
        CLIENT_ID,ADDRESS_ID,ADDRESS_TYPE,
        CONTACT,CONTACT_PHONE,CONTACT_MOBILE,CONTACT_EMAIL,
        NAME,ADDRESS1,ADDRESS2,TOWN,COUNTY,POSTCODE,COUNTRY,
        ACTIVE,DEFAULT_BILLING,DEFAULT_DELIVERY
    )
    SELECT
        p_client_id,v_address_id,'ACCOUNT',
        LEFT(NULLIF(TRIM(p_payload->>'contact'),''),25),
        LEFT(NULLIF(TRIM(p_payload->>'phone'),''),25),
        LEFT(NULLIF(TRIM(p_payload->>'mobile'),''),25),
        a.EMAIL,
        LEFT(NULLIF(TRIM(p_payload->>'name'),''),50),
        LEFT(TRIM(p_payload->>'address1'),60),
        LEFT(NULLIF(TRIM(p_payload->>'address2'),''),60),
        LEFT(TRIM(p_payload->>'town'),60),
        LEFT(NULLIF(TRIM(p_payload->>'county'),''),60),
        LEFT(UPPER(TRIM(p_payload->>'postcode')),20),
        LEFT(COALESCE(NULLIF(UPPER(TRIM(p_payload->>'country')),''),'GB'),25),
        'Y',
        CASE WHEN v_default_billing THEN 'Y' ELSE 'N' END,
        CASE WHEN v_default_delivery THEN 'Y' ELSE 'N' END
    FROM core.CUSTOMER_ACCOUNT a
    WHERE a.CLIENT_ID=p_client_id AND a.ACCOUNT_ID=p_account_id;

    IF v_default_delivery THEN
        UPDATE core.CUSTOMER_ACCOUNT_ADDRESS
           SET DEFAULT_DELIVERY=FALSE,LAST_UPDATE_DSTAMP=now()
         WHERE ACCOUNT_ID=p_account_id;
    END IF;

    IF v_default_billing THEN
        UPDATE core.CUSTOMER_ACCOUNT_ADDRESS
           SET DEFAULT_BILLING=FALSE,LAST_UPDATE_DSTAMP=now()
         WHERE ACCOUNT_ID=p_account_id;
    END IF;

    INSERT INTO core.CUSTOMER_ACCOUNT_ADDRESS(
        ACCOUNT_ID,CLIENT_ID,ADDRESS_ID,ADDRESS_LABEL,DEFAULT_DELIVERY,DEFAULT_BILLING
    )
    VALUES(
        p_account_id,p_client_id,v_address_id,
        LEFT(NULLIF(TRIM(p_payload->>'label'),''),50),
        v_default_delivery,v_default_billing
    );

    RETURN jsonb_build_object('addressId',v_address_id,'saved',TRUE);
END;
$$;


--
-- Name: search_catalog(character varying, character varying, character varying, character varying, character varying); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.search_catalog(p_client_id character varying, p_query character varying DEFAULT NULL::character varying, p_category_slug character varying DEFAULT NULL::character varying, p_availability_state character varying DEFAULT NULL::character varying, p_sale_type character varying DEFAULT NULL::character varying) RETURNS jsonb
    LANGUAGE sql STABLE
    AS $$
WITH matched AS (
 SELECT p.CLIENT_ID,p.PRODUCT_ID,p.PRODUCT_NAME,p.SLUG,p.BRAND_NAME,p.PRODUCT_TYPE,
        p.CATEGORY_CODE,c.CATEGORY_NAME,c.SLUG CATEGORY_SLUG,p.SHORT_DESCRIPTION,p.DELIVERY_CLASS,p.CURRENCY,
        p.FEATURED,p.SORT_SEQUENCE,
        MIN(v.WEB_PRICE) FILTER(WHERE v.ACTIVE) FROM_PRICE,
        MAX(v.WEB_PRICE) FILTER(WHERE v.ACTIVE) TO_PRICE,
        COALESCE(SUM(v.AVAILABLE_QTY) FILTER(WHERE v.ACTIVE),0) AVAILABLE_QTY
 FROM core.PRODUCT p
 LEFT JOIN core.PRODUCT_CATEGORY c ON c.CLIENT_ID=p.CLIENT_ID AND c.CATEGORY_CODE=p.CATEGORY_CODE
 LEFT JOIN api.CATALOG_VARIANT_AVAILABILITY v ON v.CLIENT_ID=p.CLIENT_ID AND v.PRODUCT_ID=p.PRODUCT_ID
 WHERE p.CLIENT_ID=p_client_id AND p.ACTIVE=TRUE
   AND (p_category_slug IS NULL OR c.SLUG=p_category_slug)
   AND (p_availability_state IS NULL OR EXISTS(SELECT 1 FROM api.CATALOG_VARIANT_AVAILABILITY vx WHERE vx.CLIENT_ID=p.CLIENT_ID AND vx.PRODUCT_ID=p.PRODUCT_ID AND vx.ACTIVE=TRUE AND vx.AVAILABILITY_STATE=UPPER(p_availability_state)))
   AND (p_sale_type IS NULL OR EXISTS(SELECT 1 FROM api.CATALOG_VARIANT_AVAILABILITY vx WHERE vx.CLIENT_ID=p.CLIENT_ID AND vx.PRODUCT_ID=p.PRODUCT_ID AND vx.ACTIVE=TRUE AND vx.SALE_TYPE=UPPER(p_sale_type)))
   AND (NULLIF(TRIM(p_query),'') IS NULL OR p.PRODUCT_NAME ILIKE '%'||p_query||'%' OR COALESCE(p.BRAND_NAME,'') ILIKE '%'||p_query||'%' OR COALESCE(p.SHORT_DESCRIPTION,'') ILIKE '%'||p_query||'%' OR p.SPECIFICATION::text ILIKE '%'||p_query||'%' OR p.SEARCH_METADATA::text ILIKE '%'||p_query||'%' OR EXISTS(SELECT 1 FROM core.PRODUCT_SEARCH_ALIAS a WHERE a.CLIENT_ID=p.CLIENT_ID AND a.PRODUCT_ID=p.PRODUCT_ID AND a.ACTIVE=TRUE AND a.ALIAS_TEXT ILIKE '%'||p_query||'%'))
 GROUP BY p.CLIENT_ID,p.PRODUCT_ID,p.PRODUCT_NAME,p.SLUG,p.BRAND_NAME,p.PRODUCT_TYPE,p.CATEGORY_CODE,c.CATEGORY_NAME,c.SLUG,p.SHORT_DESCRIPTION,p.DELIVERY_CLASS,p.CURRENCY,p.FEATURED,p.SORT_SEQUENCE
)
SELECT COALESCE(jsonb_agg(jsonb_build_object(
 'productId',PRODUCT_ID,'name',PRODUCT_NAME,'slug',SLUG,'brand',BRAND_NAME,'productType',PRODUCT_TYPE,
 'category',jsonb_build_object('code',CATEGORY_CODE,'name',CATEGORY_NAME,'slug',CATEGORY_SLUG),
 'shortDescription',SHORT_DESCRIPTION,'deliveryClass',DELIVERY_CLASS,'currency',CURRENCY,
 'fromPrice',FROM_PRICE,'toPrice',TO_PRICE,'availableQty',AVAILABLE_QTY,'featured',FEATURED
) ORDER BY SORT_SEQUENCE,PRODUCT_NAME),'[]'::jsonb) FROM matched;
$$;


--
-- Name: set_contact_preference(character varying, jsonb); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.set_contact_preference(p_client_id character varying, p_payload jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
DECLARE v_id UUID; v_type VARCHAR; v_value TEXT; v_channel VARCHAR; v_purpose VARCHAR;
BEGIN
 v_type:=UPPER(COALESCE(NULLIF(TRIM(p_payload->>'contactType'),''),'EMAIL')); v_value:=LOWER(NULLIF(TRIM(p_payload->>'contactValue'),'')); v_channel:=UPPER(NULLIF(TRIM(p_payload->>'channel'),'')); v_purpose:=UPPER(NULLIF(TRIM(p_payload->>'purpose'),''));
 IF v_value IS NULL OR v_channel NOT IN ('EMAIL','SMS','WHATSAPP') OR v_purpose NOT IN ('MARKETING','STOCK_ALERT','TRANSACTIONAL') THEN RAISE EXCEPTION 'INVALID_CONTACT_PREFERENCE'; END IF;
 INSERT INTO core.CONTACT_PREFERENCE(CLIENT_ID,CUSTOMER_ID,CONTACT_TYPE,CONTACT_VALUE,CHANNEL,PURPOSE,OPTED_IN)
 VALUES(p_client_id,NULLIF(TRIM(p_payload->>'customerId'),''),v_type,v_value,v_channel,v_purpose,COALESCE((p_payload->>'optedIn')::boolean,FALSE))
 ON CONFLICT (CLIENT_ID,CONTACT_TYPE,CONTACT_VALUE,CHANNEL,PURPOSE) DO UPDATE SET OPTED_IN=EXCLUDED.OPTED_IN,CUSTOMER_ID=COALESCE(EXCLUDED.CUSTOMER_ID,core.CONTACT_PREFERENCE.CUSTOMER_ID),CONSENT_DSTAMP=now(),LAST_UPDATE_DSTAMP=now()
 RETURNING CONTACT_PREFERENCE_ID INTO v_id;
 RETURN jsonb_build_object('preferenceId',v_id,'saved',TRUE);
END; $$;


--
-- Name: set_payment_provider_reference(character varying, uuid, character varying, character varying); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.set_payment_provider_reference(p_client_id character varying, p_payment_id uuid, p_provider_reference character varying, p_provider_status character varying) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
DECLARE v_payment core.PAYMENT_TRANSACTION%ROWTYPE;
BEGIN
    UPDATE core.PAYMENT_TRANSACTION
       SET PROVIDER_REFERENCE=p_provider_reference,
           PROVIDER_STATUS=p_provider_status,
           STATUS=CASE WHEN STATUS='CREATED' THEN 'PENDING' ELSE STATUS END,
           LAST_UPDATE_DSTAMP=now()
     WHERE CLIENT_ID=p_client_id AND PAYMENT_ID=p_payment_id
     RETURNING * INTO v_payment;

    IF NOT FOUND THEN RAISE EXCEPTION 'PAYMENT_NOT_FOUND'; END IF;

    RETURN jsonb_build_object(
        'paymentId',v_payment.PAYMENT_ID,
        'providerReference',v_payment.PROVIDER_REFERENCE,
        'status',v_payment.STATUS
    );
END;
$$;


--
-- Name: set_product_favourite(character varying, uuid, character varying, boolean); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.set_product_favourite(p_client_id character varying, p_account_id uuid, p_product_slug character varying, p_favourite boolean) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
DECLARE v_product_id VARCHAR(50);
BEGIN
    SELECT PRODUCT_ID INTO v_product_id
      FROM core.PRODUCT
     WHERE CLIENT_ID=p_client_id AND SLUG=p_product_slug AND ACTIVE=TRUE;

    IF v_product_id IS NULL THEN RAISE EXCEPTION 'PRODUCT_NOT_FOUND'; END IF;

    IF p_favourite THEN
        INSERT INTO core.PRODUCT_FAVOURITE(ACCOUNT_ID,CLIENT_ID,PRODUCT_ID)
        VALUES(p_account_id,p_client_id,v_product_id)
        ON CONFLICT DO NOTHING;
    ELSE
        DELETE FROM core.PRODUCT_FAVOURITE
         WHERE ACCOUNT_ID=p_account_id AND CLIENT_ID=p_client_id AND PRODUCT_ID=v_product_id;
    END IF;

    RETURN jsonb_build_object('productId',v_product_id,'favourite',p_favourite);
END;
$$;


--
-- Name: submit_product_review(character varying, character varying, jsonb); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.submit_product_review(p_client_id character varying, p_slug character varying, p_payload jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
DECLARE v_product VARCHAR; v_id UUID; v_rating INTEGER; v_email TEXT;
BEGIN
 SELECT PRODUCT_ID INTO v_product FROM core.PRODUCT WHERE CLIENT_ID=p_client_id AND SLUG=p_slug AND ACTIVE=TRUE; IF NOT FOUND THEN RAISE EXCEPTION 'PRODUCT_NOT_FOUND'; END IF;
 v_rating:=(p_payload->>'rating')::integer; v_email:=LOWER(NULLIF(TRIM(p_payload->>'email'),''));
 IF v_rating NOT BETWEEN 1 AND 5 OR v_email IS NULL OR position('@' in v_email)<2 OR NULLIF(TRIM(p_payload->>'displayName'),'') IS NULL THEN RAISE EXCEPTION 'INVALID_REVIEW'; END IF;
 INSERT INTO core.PRODUCT_REVIEW(CLIENT_ID,PRODUCT_ID,SKU_ID,EMAIL,DISPLAY_NAME,RATING,REVIEW_TITLE,REVIEW_TEXT)
 VALUES(p_client_id,v_product,NULLIF(TRIM(p_payload->>'skuId'),''),v_email,LEFT(TRIM(p_payload->>'displayName'),100),v_rating,LEFT(NULLIF(TRIM(p_payload->>'title'),''),200),NULLIF(TRIM(p_payload->>'text'),'')) RETURNING REVIEW_ID INTO v_id;
 RETURN jsonb_build_object('reviewId',v_id,'status','PENDING');
END; $$;


--
-- Name: submit_reserved_web_order(character varying, uuid, jsonb); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.submit_reserved_web_order(p_client_id character varying, p_reservation_id uuid, p_payload jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
DECLARE r core.STOCK_RESERVATION%ROWTYPE; v_payload JSONB; v_items JSONB; result JSONB; alloc RECORD;
BEGIN
 SELECT * INTO r FROM core.STOCK_RESERVATION WHERE CLIENT_ID=p_client_id AND RESERVATION_ID=p_reservation_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'RESERVATION_NOT_FOUND'; END IF;
 IF r.STATUS<>'ACTIVE' THEN RAISE EXCEPTION 'RESERVATION_NOT_ACTIVE'; END IF;
 IF r.EXPIRES_DSTAMP<=now() THEN PERFORM api.RELEASE_STOCK_RESERVATION(p_client_id,p_reservation_id,'EXPIRED'); RAISE EXCEPTION 'RESERVATION_EXPIRED'; END IF;
 IF LOWER(COALESCE(p_payload#>>'{customer,email}',''))<>LOWER(r.EMAIL) THEN RAISE EXCEPTION 'RESERVATION_EMAIL_MISMATCH'; END IF;
 SELECT jsonb_agg(jsonb_build_object('sku_id',SKU_ID,'qty',QTY_RESERVED) ORDER BY RESERVATION_LINE_ID) INTO v_items FROM core.STOCK_RESERVATION_LINE WHERE RESERVATION_ID=p_reservation_id;
 v_payload:=jsonb_set(p_payload,'{items}',COALESCE(v_items,'[]'::jsonb),TRUE);
 PERFORM api.RELEASE_STOCK_RESERVATION(p_client_id,p_reservation_id,'RELEASED');
 result:=api.SUBMIT_WEB_ORDER(p_client_id,v_payload);
 IF result->>'status'<>'ACCEPTED' THEN RAISE EXCEPTION 'RESERVED_ORDER_SUBMISSION_FAILED: %',result; END IF;
 SELECT * INTO alloc FROM core.ALLOCATE_ORDER(p_client_id,result->>'orderId');
 IF alloc.RESULT_STATUS NOT IN ('ALLOCATED','ALREADY_ALLOCATED') THEN RAISE EXCEPTION 'RESERVED_ORDER_ALLOCATION_FAILED: %',alloc.RESULT_MESSAGE; END IF;
 UPDATE core.STOCK_RESERVATION SET STATUS='CONVERTED',CONVERTED_ORDER_ID=result->>'orderId',LAST_UPDATE_DSTAMP=now() WHERE RESERVATION_ID=p_reservation_id;
 RETURN result||jsonb_build_object('reservationId',p_reservation_id,'reservationConverted',TRUE,'allocationStatus',alloc.RESULT_STATUS);
END; $$;


--
-- Name: submit_web_order(character varying, jsonb); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.submit_web_order(p_client_id character varying, p_payload jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    AS $_$
DECLARE
    v_quote JSONB;
    v_basket JSONB;
    v_selected JSONB;
    v_interface_id UUID;
    v_source_order_id VARCHAR(100);
    v_order_id VARCHAR(20);
    v_address_id VARCHAR(15);
    v_customer_id VARCHAR(15);
    v_currency VARCHAR(3);
    v_order_value NUMERIC(12,3);
    v_freight_cost NUMERIC(12,3);
    v_total_before_delivery NUMERIC(12,3);
    v_fulfilment_preference VARCHAR(30);
    v_fulfilment_method VARCHAR(30);
    v_fulfilment_option_code VARCHAR(100);
    v_result RECORD;
    v_existing interface.ORDER_HEADER_IF%ROWTYPE;
    v_existing_order core.ORDER_HEADER%ROWTYPE;
    v_item RECORD;
    v_line_id INTEGER := 0;
    v_discount NUMERIC(12,3) := 0;
    v_promo_code VARCHAR(50);
    v_free_delivery BOOLEAN := FALSE;
    v_idempotent_replay BOOLEAN := FALSE;

    v_customer_name TEXT;
    v_email TEXT;
    v_phone_raw TEXT;
    v_mobile_raw TEXT;
    v_phone TEXT;
    v_mobile TEXT;
    v_address1 TEXT;
    v_address2 TEXT;
    v_town TEXT;
    v_county TEXT;
    v_postcode_raw TEXT;
    v_postcode TEXT;
    v_country_raw TEXT;
    v_country TEXT;
    v_requires_delivery_address BOOLEAN := FALSE;
BEGIN
    v_source_order_id := NULLIF(TRIM(p_payload->>'idempotencyKey'),'');
    IF v_source_order_id IS NULL THEN
        RAISE EXCEPTION 'IDEMPOTENCY_KEY_REQUIRED';
    END IF;

    v_fulfilment_option_code :=
        NULLIF(TRIM(p_payload->>'fulfilmentOptionCode'),'');
    IF v_fulfilment_option_code IS NULL THEN
        RETURN jsonb_build_object(
            'status','REJECTED',
            'code','FULFILMENT_OPTION_REQUIRED'
        );
    END IF;

    SELECT *
      INTO v_existing
      FROM interface.ORDER_HEADER_IF
     WHERE CLIENT_ID=p_client_id
       AND SOURCE_SYSTEM='WEBSITE'
       AND SOURCE_ORDER_ID=v_source_order_id;

    IF FOUND AND v_existing.PROCESS_STATUS='PROCESSED' THEN
        v_idempotent_replay := TRUE;

        SELECT *
          INTO v_existing_order
          FROM core.ORDER_HEADER
         WHERE CLIENT_ID=p_client_id
           AND ORDER_ID=v_existing.ORDER_ID;

        RETURN jsonb_build_object(
            'status','ACCEPTED',
            'interfaceId',v_existing.INTERFACE_ID,
            'orderId',v_existing.ORDER_ID,
            'paymentStatus',v_existing_order.PAYMENT_STATUS,
            'fulfilmentStatus',v_existing_order.FULFILMENT_STATUS,
            'fulfilmentOptionCode',v_existing_order.SERVICE_LEVEL,
            'fulfilmentMethod',v_existing_order.DISPATCH_METHOD,
            'promoCode',v_existing_order.PROMO_CODE,
            'freightCost',v_existing_order.FREIGHT_COST,
            'freeDelivery',COALESCE(v_existing_order.FREE_DELIVERY,'N')='Y',
            'orderValue',v_existing_order.ORDER_VALUE,
            'idempotentReplay',TRUE
        );
    END IF;

    --------------------------------------------------------------------------
    -- AUTHORITATIVE CUSTOMER VALIDATION
    --------------------------------------------------------------------------
    v_customer_name := NULLIF(
        regexp_replace(
            TRIM(COALESCE(p_payload#>>'{customer,name}','')),
            '[[:space:]]+',
            ' ',
            'g'
        ),
        ''
    );

    IF v_customer_name IS NULL THEN
        RETURN jsonb_build_object(
            'status','REJECTED',
            'code','CUSTOMER_NAME_REQUIRED'
        );
    END IF;

    IF LENGTH(v_customer_name) > 50 THEN
        RETURN jsonb_build_object(
            'status','REJECTED',
            'code','CUSTOMER_NAME_INVALID'
        );
    END IF;

    v_email := LOWER(NULLIF(TRIM(p_payload#>>'{customer,email}'),''));

    IF v_email IS NULL
       OR LENGTH(v_email) > 254
       OR v_email !~* '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
    THEN
        RETURN jsonb_build_object(
            'status','REJECTED',
            'code','CUSTOMER_EMAIL_INVALID'
        );
    END IF;

    v_phone_raw := NULLIF(TRIM(p_payload#>>'{customer,phone}'),'');
    v_mobile_raw := NULLIF(TRIM(p_payload#>>'{customer,mobile}'),'');

    IF v_phone_raw IS NULL AND v_mobile_raw IS NULL THEN
        RETURN jsonb_build_object(
            'status','REJECTED',
            'code','CUSTOMER_PHONE_INVALID'
        );
    END IF;

    IF v_phone_raw IS NOT NULL THEN
        v_phone := api.NORMALIZE_GB_PHONE(v_phone_raw);

        IF v_phone IS NULL THEN
            RETURN jsonb_build_object(
                'status','REJECTED',
                'code','CUSTOMER_PHONE_INVALID'
            );
        END IF;
    END IF;

    IF v_mobile_raw IS NOT NULL THEN
        v_mobile := api.NORMALIZE_GB_PHONE(v_mobile_raw);

        IF v_mobile IS NULL THEN
            RETURN jsonb_build_object(
                'status','REJECTED',
                'code','CUSTOMER_PHONE_INVALID'
            );
        END IF;
    END IF;

    IF v_phone IS NOT NULL
       AND v_mobile IS NOT NULL
       AND v_phone <> v_mobile
    THEN
        RETURN jsonb_build_object(
            'status','REJECTED',
            'code','CUSTOMER_PHONE_CONFLICT'
        );
    END IF;

    -- New storefront contract: customer.phone is canonical.
    -- customer.mobile remains accepted for backwards compatibility.
    v_phone := COALESCE(v_phone,v_mobile);

    --------------------------------------------------------------------------
    -- CANONICAL DELIVERY ADDRESS VALUES
    --------------------------------------------------------------------------
    v_address1 := NULLIF(
        regexp_replace(
            TRIM(COALESCE(p_payload#>>'{deliveryAddress,address1}','')),
            '[[:space:]]+',
            ' ',
            'g'
        ),
        ''
    );

    v_address2 := NULLIF(
        regexp_replace(
            TRIM(COALESCE(p_payload#>>'{deliveryAddress,address2}','')),
            '[[:space:]]+',
            ' ',
            'g'
        ),
        ''
    );

    v_town := NULLIF(
        regexp_replace(
            TRIM(COALESCE(p_payload#>>'{deliveryAddress,town}','')),
            '[[:space:]]+',
            ' ',
            'g'
        ),
        ''
    );

    v_county := NULLIF(
        regexp_replace(
            TRIM(COALESCE(p_payload#>>'{deliveryAddress,county}','')),
            '[[:space:]]+',
            ' ',
            'g'
        ),
        ''
    );

    v_postcode_raw := NULLIF(
        TRIM(p_payload#>>'{deliveryAddress,postcode}'),
        ''
    );

    v_country_raw := NULLIF(
        UPPER(TRIM(p_payload#>>'{deliveryAddress,country}')),
        ''
    );

    v_country := CASE
        WHEN v_country_raw IS NULL THEN 'GB'
        WHEN v_country_raw IN ('GB','GBR','UK','UNITED KINGDOM') THEN 'GB'
        ELSE v_country_raw
    END;

    IF v_country <> 'GB' THEN
        RETURN jsonb_build_object(
            'status','REJECTED',
            'code','DELIVERY_COUNTRY_UNSUPPORTED'
        );
    END IF;

    IF v_postcode_raw IS NOT NULL THEN
        v_postcode := api.NORMALIZE_GB_POSTCODE(v_postcode_raw);

        IF v_postcode IS NULL THEN
            RETURN jsonb_build_object(
                'status','REJECTED',
                'code','DELIVERY_POSTCODE_INVALID'
            );
        END IF;
    END IF;

    --------------------------------------------------------------------------
    -- AUTHORITATIVE ADDRESS STORAGE-LENGTH VALIDATION
    --------------------------------------------------------------------------
    -- Validate normalised values before quoting/order creation. Never silently
    -- truncate customer delivery data to fit core.ADDRESS.
    IF v_address1 IS NOT NULL AND LENGTH(v_address1) > 60 THEN
        RETURN jsonb_build_object(
            'status','REJECTED',
            'code','DELIVERY_ADDRESS1_TOO_LONG'
        );
    END IF;

    IF v_address2 IS NOT NULL AND LENGTH(v_address2) > 60 THEN
        RETURN jsonb_build_object(
            'status','REJECTED',
            'code','DELIVERY_ADDRESS2_TOO_LONG'
        );
    END IF;

    IF v_town IS NOT NULL AND LENGTH(v_town) > 60 THEN
        RETURN jsonb_build_object(
            'status','REJECTED',
            'code','DELIVERY_TOWN_TOO_LONG'
        );
    END IF;

    IF v_county IS NOT NULL AND LENGTH(v_county) > 60 THEN
        RETURN jsonb_build_object(
            'status','REJECTED',
            'code','DELIVERY_COUNTY_TOO_LONG'
        );
    END IF;
    /*
     * Quote against canonical customer/address values. Browser formatting is
     * never authoritative.
     */
    p_payload := jsonb_set(
        p_payload,
        '{customer,name}',
        to_jsonb(v_customer_name),
        TRUE
    );

    p_payload := jsonb_set(
        p_payload,
        '{customer,email}',
        to_jsonb(v_email),
        TRUE
    );

    p_payload := jsonb_set(
        p_payload,
        '{customer,phone}',
        to_jsonb(v_phone),
        TRUE
    );

    IF v_mobile_raw IS NOT NULL THEN
        p_payload := jsonb_set(
            p_payload,
            '{customer,mobile}',
            to_jsonb(COALESCE(v_mobile,v_phone)),
            TRUE
        );
    END IF;

    IF NOT (p_payload ? 'deliveryAddress') THEN
        p_payload := jsonb_set(
            p_payload,
            '{deliveryAddress}',
            '{}'::jsonb,
            TRUE
        );
    END IF;

    p_payload := jsonb_set(
        p_payload,
        '{deliveryAddress,country}',
        to_jsonb(v_country),
        TRUE
    );

    IF v_postcode IS NOT NULL THEN
        p_payload := jsonb_set(
            p_payload,
            '{deliveryAddress,postcode}',
            to_jsonb(v_postcode),
            TRUE
        );
    END IF;

    IF v_address1 IS NOT NULL THEN
        p_payload := jsonb_set(
            p_payload,
            '{deliveryAddress,address1}',
            to_jsonb(v_address1),
            TRUE
        );
    END IF;

    IF v_address2 IS NOT NULL THEN
        p_payload := jsonb_set(
            p_payload,
            '{deliveryAddress,address2}',
            to_jsonb(v_address2),
            TRUE
        );
    END IF;

    IF v_town IS NOT NULL THEN
        p_payload := jsonb_set(
            p_payload,
            '{deliveryAddress,town}',
            to_jsonb(v_town),
            TRUE
        );
    END IF;

    IF v_county IS NOT NULL THEN
        p_payload := jsonb_set(
            p_payload,
            '{deliveryAddress,county}',
            to_jsonb(v_county),
            TRUE
        );
    END IF;

    --------------------------------------------------------------------------
    -- FINAL FULFILMENT / PRICE REVALIDATION
    --------------------------------------------------------------------------
    v_quote := api.QUOTE_CHECKOUT(p_client_id,p_payload);
    v_basket := v_quote->'basket';

    IF NOT COALESCE((v_quote->>'valid')::BOOLEAN,FALSE) THEN
        IF COALESCE(v_quote->>'code','') = 'FULFILMENT_OPTION_NOT_AVAILABLE' THEN
            RETURN jsonb_build_object(
                'status','REJECTED',
                'code','FULFILMENT_ADDRESS_CHANGED',
                'quote',v_quote
            );
        END IF;

        RETURN jsonb_build_object(
            'status','REJECTED',
            'code',
                CASE
                    WHEN NOT COALESCE((v_basket->>'valid')::BOOLEAN,FALSE)
                        THEN 'BASKET_INVALID'
                    ELSE COALESCE(v_quote->>'code','CHECKOUT_INVALID')
                END,
            'quote',v_quote
        );
    END IF;

    v_selected := v_quote->'selectedFulfilmentOption';

    IF v_selected IS NULL THEN
        RETURN jsonb_build_object(
            'status','REJECTED',
            'code','FULFILMENT_OPTION_NOT_AVAILABLE',
            'quote',v_quote
        );
    END IF;

    IF NOT COALESCE((v_quote->>'paymentReady')::BOOLEAN,FALSE) THEN
        RETURN jsonb_build_object(
            'status','REJECTED',
            'code','FULFILMENT_PRICE_PENDING',
            'selectedFulfilmentOption',v_selected,
            'quote',v_quote
        );
    END IF;

    v_currency := COALESCE(v_basket->>'currency','GBP');
    v_discount := COALESCE((v_quote->>'discountAmount')::NUMERIC,0);
    v_total_before_delivery :=
        COALESCE((v_quote->>'totalBeforeDelivery')::NUMERIC,0);
    v_freight_cost := COALESCE((v_quote->>'freightCost')::NUMERIC,0);
    v_order_value := COALESCE((v_quote->>'total')::NUMERIC,0);
    v_promo_code := NULLIF(UPPER(TRIM(p_payload->>'promoCode')),'');
    v_free_delivery := COALESCE((v_quote->>'freeDelivery')::BOOLEAN,FALSE);

    v_fulfilment_method :=
        UPPER(NULLIF(TRIM(v_selected->>'fulfilmentMethod'),''));

    v_fulfilment_option_code :=
        NULLIF(TRIM(v_selected->>'code'),'');

    v_requires_delivery_address :=
        v_fulfilment_method IN (
            'CARRIER',
            'LOCAL_DELIVERY',
            'ROUTE_DELIVERY'
        );

    IF v_requires_delivery_address THEN
        IF v_address1 IS NULL THEN
            RETURN jsonb_build_object(
                'status','REJECTED',
                'code','DELIVERY_ADDRESS1_REQUIRED'
            );
        END IF;

        IF v_town IS NULL THEN
            RETURN jsonb_build_object(
                'status','REJECTED',
                'code','DELIVERY_TOWN_REQUIRED'
            );
        END IF;

        IF v_postcode IS NULL THEN
            RETURN jsonb_build_object(
                'status','REJECTED',
                'code','DELIVERY_POSTCODE_INVALID'
            );
        END IF;
    END IF;

    v_fulfilment_preference := COALESCE(
        NULLIF(UPPER(TRIM(p_payload->>'fulfilmentPreference')),''),
        'CONSOLIDATE'
    );

    IF v_fulfilment_preference NOT IN (
        'CONSOLIDATE',
        'SPLIT_WHEN_REQUIRED'
    ) THEN
        RAISE EXCEPTION 'INVALID_FULFILMENT_PREFERENCE';
    END IF;

    IF v_fulfilment_method NOT IN (
        'CARRIER',
        'LOCAL_DELIVERY',
        'COLLECTION',
        'ROUTE_DELIVERY',
        'MEET_POINT'
    ) THEN
        RAISE EXCEPTION 'INVALID_FULFILMENT_METHOD';
    END IF;

    --------------------------------------------------------------------------
    -- EXISTING ORDER CREATION PATH
    --------------------------------------------------------------------------
    IF v_existing.INTERFACE_ID IS NOT NULL THEN
        v_idempotent_replay := TRUE;

        SELECT *
          INTO v_result
          FROM interface.PROCESS_ORDER_INTERFACE(v_existing.INTERFACE_ID);

        IF v_result.RESULT_STATUS<>'PROCESSED' THEN
            RETURN jsonb_build_object(
                'status','ERROR',
                'interfaceId',v_existing.INTERFACE_ID,
                'orderId',v_result.RESULT_ORDER_ID,
                'message',v_result.RESULT_MESSAGE,
                'idempotentReplay',TRUE
            );
        END IF;

        v_order_id := v_result.RESULT_ORDER_ID;
        v_interface_id := v_existing.INTERFACE_ID;
    ELSE
        v_customer_id := LEFT(
            COALESCE(
                NULLIF(TRIM(p_payload#>>'{customer,customerId}'),''),
                'WEB-' || UPPER(
                    SUBSTRING(
                        REPLACE(gen_random_uuid()::TEXT,'-','')
                        FROM 1 FOR 11
                    )
                )
            ),
            15
        );

        v_address_id :=
            'W' || UPPER(
                SUBSTRING(
                    REPLACE(gen_random_uuid()::TEXT,'-','')
                    FROM 1 FOR 14
                )
            );

        INSERT INTO core.ADDRESS (
            CLIENT_ID,
            ADDRESS_ID,
            ADDRESS_TYPE,
            CONTACT,
            CONTACT_PHONE,
            CONTACT_MOBILE,
            CONTACT_EMAIL,
            NAME,
            ADDRESS1,
            ADDRESS2,
            TOWN,
            COUNTY,
            POSTCODE,
            COUNTRY,
            ACTIVE,
            DEFAULT_BILLING,
            DEFAULT_DELIVERY
        )
        VALUES (
            p_client_id,
            v_address_id,
            'DELIVERY',
            LEFT(v_customer_name,25),
            LEFT(v_phone,25),
            LEFT(
                CASE
                    WHEN v_mobile_raw IS NOT NULL
                        THEN COALESCE(v_mobile,v_phone)
                END,
                25
            ),
            v_email,
            LEFT(
                COALESCE(
                    NULLIF(TRIM(p_payload#>>'{deliveryAddress,name}'),''),
                    v_customer_name
                ),
                50
            ),
            v_address1,
            v_address2,
            v_town,
            v_county,
            LEFT(v_postcode,20),
            LEFT(v_country,25),
            'Y',
            'N',
            'Y'
        );

        INSERT INTO interface.ORDER_HEADER_IF (
            CLIENT_ID,
            SOURCE_SYSTEM,
            SOURCE_ORDER_ID,
            CUSTOMER_ID,
            ORDER_DATE,
            DISPATCH_METHOD,
            SERVICE_LEVEL,
            ADDRESS_ID,
            ORDER_VALUE,
            CURRENCY,
            FULFILMENT_PREFERENCE,
            PROCESS_STATUS
        )
        VALUES (
            p_client_id,
            'WEBSITE',
            v_source_order_id,
            v_customer_id,
            now(),
            v_fulfilment_method,
            v_fulfilment_option_code,
            v_address_id,
            v_order_value,
            v_currency,
            v_fulfilment_preference,
            'NEW'
        )
        RETURNING INTERFACE_ID INTO v_interface_id;

        FOR v_item IN
            SELECT
                x.sku_id,
                x.qty,
                pv.WEB_PRICE,
                pv.VARIANT_NAME
            FROM jsonb_to_recordset(p_payload->'items')
                 AS x(sku_id VARCHAR, qty NUMERIC)
            JOIN core.PRODUCT_VARIANT pv
              ON pv.CLIENT_ID=p_client_id
             AND pv.SKU_ID=x.sku_id
             AND pv.ACTIVE=TRUE
            ORDER BY x.sku_id
        LOOP
            v_line_id := v_line_id + 1;

            INSERT INTO interface.ORDER_LINE_IF (
                INTERFACE_ID,
                LINE_ID,
                SOURCE_LINE_ID,
                SKU_ID,
                QTY_ORDERED,
                PRODUCT_PRICE,
                EXTENDED_PRICE,
                NOTES,
                PROCESS_STATUS
            )
            VALUES (
                v_interface_id,
                v_line_id,
                v_line_id::TEXT,
                v_item.sku_id,
                v_item.qty,
                v_item.WEB_PRICE,
                v_item.WEB_PRICE*v_item.qty,
                LEFT(v_item.VARIANT_NAME,80),
                'NEW'
            );
        END LOOP;

        SELECT *
          INTO v_result
          FROM interface.PROCESS_ORDER_INTERFACE(v_interface_id);

        IF v_result.RESULT_STATUS<>'PROCESSED' THEN
            RETURN jsonb_build_object(
                'status','ERROR',
                'interfaceId',v_interface_id,
                'orderId',v_result.RESULT_ORDER_ID,
                'message',v_result.RESULT_MESSAGE
            );
        END IF;

        v_order_id := v_result.RESULT_ORDER_ID;
    END IF;

    UPDATE core.ORDER_HEADER
       SET DISPATCH_METHOD=v_fulfilment_method,
           SERVICE_LEVEL=v_fulfilment_option_code,
           FULFILMENT_PREFERENCE=v_fulfilment_preference,
           FREIGHT_COST=v_freight_cost,
           FREE_DELIVERY=CASE WHEN v_free_delivery THEN 'Y' ELSE 'N' END,
           ORDER_VALUE=v_order_value,
           PROMO_CODE=v_promo_code,
           LAST_UPDATED_BY='WEB_API',
           LAST_UPDATE_DATE=now()
     WHERE CLIENT_ID=p_client_id
       AND ORDER_ID=v_order_id;

    RETURN jsonb_build_object(
        'status','ACCEPTED',
        'interfaceId',v_interface_id,
        'orderId',v_order_id,
        'paymentStatus','PENDING',
        'fulfilmentStatus','NEW',
        'fulfilmentOptionCode',v_fulfilment_option_code,
        'fulfilmentMethod',v_fulfilment_method,
        'promoCode',v_promo_code,
        'discountAmount',v_discount,
        'totalBeforeDelivery',v_total_before_delivery,
        'freightCost',v_freight_cost,
        'freeDelivery',v_free_delivery,
        'orderValue',v_order_value,
        'idempotentReplay',v_idempotent_replay
    );
END;
$_$;


--
-- Name: upsert_account_identity(character varying, character varying, character varying, character varying, boolean); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.upsert_account_identity(p_client_id character varying, p_auth_provider character varying, p_auth_subject character varying, p_email character varying, p_email_verified boolean DEFAULT false) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_account core.CUSTOMER_ACCOUNT%ROWTYPE;
BEGIN
    IF NULLIF(TRIM(p_auth_provider),'') IS NULL
       OR NULLIF(TRIM(p_auth_subject),'') IS NULL
       OR NULLIF(LOWER(TRIM(p_email)),'') IS NULL THEN
        RAISE EXCEPTION 'INVALID_AUTH_IDENTITY';
    END IF;

    INSERT INTO core.CUSTOMER_ACCOUNT(
        CLIENT_ID,AUTH_PROVIDER,AUTH_SUBJECT,EMAIL,EMAIL_VERIFIED,ACTIVE,LAST_LOGIN_DSTAMP
    )
    VALUES(
        p_client_id,
        UPPER(TRIM(p_auth_provider)),
        TRIM(p_auth_subject),
        LOWER(TRIM(p_email)),
        COALESCE(p_email_verified,FALSE),
        TRUE,
        now()
    )
    ON CONFLICT (CLIENT_ID,AUTH_PROVIDER,AUTH_SUBJECT)
    DO UPDATE SET
        EMAIL=EXCLUDED.EMAIL,
        EMAIL_VERIFIED=core.CUSTOMER_ACCOUNT.EMAIL_VERIFIED OR EXCLUDED.EMAIL_VERIFIED,
        ACTIVE=TRUE,
        LAST_LOGIN_DSTAMP=now()
    RETURNING * INTO v_account;

    RETURN jsonb_build_object(
        'accountId',v_account.ACCOUNT_ID,
        'clientId',v_account.CLIENT_ID,
        'customerId',v_account.CUSTOMER_ID,
        'authProvider',v_account.AUTH_PROVIDER,
        'authSubject',v_account.AUTH_SUBJECT,
        'email',v_account.EMAIL,
        'emailVerified',v_account.EMAIL_VERIFIED,
        'active',v_account.ACTIVE
    );
END;
$$;


--
-- Name: validate_basket(character varying, jsonb); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.validate_basket(p_client_id character varying, p_items jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE v_result JSONB;
BEGIN
 IF p_items IS NULL OR jsonb_typeof(p_items)<>'array' OR jsonb_array_length(p_items)=0 THEN
   RETURN jsonb_build_object('valid',FALSE,'errors',jsonb_build_array(jsonb_build_object('code','EMPTY_BASKET','message','Basket is empty.')),'items','[]'::jsonb);
 END IF;
 WITH requested AS (SELECT x.sku_id,x.qty FROM jsonb_to_recordset(p_items) x(sku_id VARCHAR,qty NUMERIC)),
 resolved AS (
   SELECT r.sku_id,r.qty,pv.PRODUCT_ID,p.PRODUCT_NAME,p.SLUG,p.DELIVERY_CLASS,p.CURRENCY,pv.VARIANT_NAME,pv.OPTION_VALUES,pv.WEB_PRICE,
          pv.SALE_TYPE,pv.AVAILABILITY_STATE,pv.EXPECTED_AVAILABLE_FROM,pv.EXPECTED_AVAILABLE_TO,pv.MIN_ORDER_QTY,pv.MAX_ORDER_QTY,pv.QTY_INCREMENT,
          COALESCE(a.AVAILABLE_QTY,0) AVAILABLE_QTY,
          CASE WHEN pv.SKU_ID IS NULL THEN 'SKU_NOT_FOR_SALE'
               WHEN pv.AVAILABILITY_STATE<>'AVAILABLE' THEN 'NOT_YET_AVAILABLE'
               WHEN r.qty IS NULL OR r.qty<=0 THEN 'INVALID_QTY'
               WHEN r.qty<pv.MIN_ORDER_QTY THEN 'BELOW_MIN_QTY'
               WHEN pv.MAX_ORDER_QTY IS NOT NULL AND r.qty>pv.MAX_ORDER_QTY THEN 'ABOVE_MAX_QTY'
               WHEN pv.QTY_INCREMENT>0 AND mod(r.qty-pv.MIN_ORDER_QTY,pv.QTY_INCREMENT)<>0 THEN 'INVALID_QTY_INCREMENT'
               WHEN COALESCE(a.AVAILABLE_QTY,0)<r.qty THEN 'INSUFFICIENT_STOCK' ELSE NULL END ERROR_CODE
   FROM requested r LEFT JOIN core.PRODUCT_VARIANT pv ON pv.CLIENT_ID=p_client_id AND pv.SKU_ID=r.sku_id AND pv.ACTIVE=TRUE
   LEFT JOIN core.PRODUCT p ON p.CLIENT_ID=pv.CLIENT_ID AND p.PRODUCT_ID=pv.PRODUCT_ID AND p.ACTIVE=TRUE
   LEFT JOIN api.CATALOG_VARIANT_AVAILABILITY a ON a.CLIENT_ID=pv.CLIENT_ID AND a.PRODUCT_ID=pv.PRODUCT_ID AND a.SKU_ID=pv.SKU_ID
 )
 SELECT jsonb_build_object(
   'valid',COUNT(*) FILTER(WHERE ERROR_CODE IS NOT NULL)=0,'currency',COALESCE(MAX(CURRENCY),'GBP'),
   'subtotal',COALESCE(SUM(CASE WHEN ERROR_CODE IS NULL THEN WEB_PRICE*qty ELSE 0 END),0),
   'hasStandard',COALESCE(BOOL_OR(UPPER(COALESCE(DELIVERY_CLASS,'STANDARD'))='STANDARD' AND ERROR_CODE IS NULL),FALSE),
   'hasLivestock',COALESCE(BOOL_OR(UPPER(COALESCE(DELIVERY_CLASS,''))='LIVESTOCK' AND ERROR_CODE IS NULL),FALSE),
   'deliveryClasses',COALESCE(jsonb_agg(DISTINCT DELIVERY_CLASS) FILTER(WHERE ERROR_CODE IS NULL),'[]'::jsonb),
   'items',COALESCE(jsonb_agg(jsonb_build_object('skuId',sku_id,'qty',qty,'productId',PRODUCT_ID,'productName',PRODUCT_NAME,'slug',SLUG,'variantName',VARIANT_NAME,'options',OPTION_VALUES,'deliveryClass',DELIVERY_CLASS,'saleType',SALE_TYPE,'availabilityState',AVAILABILITY_STATE,'expectedAvailableFrom',EXPECTED_AVAILABLE_FROM,'expectedAvailableTo',EXPECTED_AVAILABLE_TO,'unitPrice',WEB_PRICE,'lineTotal',CASE WHEN WEB_PRICE IS NULL THEN NULL ELSE WEB_PRICE*qty END,'availableQty',AVAILABLE_QTY,'minOrderQty',MIN_ORDER_QTY,'maxOrderQty',MAX_ORDER_QTY,'qtyIncrement',QTY_INCREMENT,'valid',ERROR_CODE IS NULL,'errorCode',ERROR_CODE) ORDER BY sku_id),'[]'::jsonb),
   'errors',COALESCE(jsonb_agg(jsonb_build_object('skuId',sku_id,'code',ERROR_CODE,'message',CASE ERROR_CODE WHEN 'SKU_NOT_FOR_SALE' THEN 'This item is not currently available for sale.' WHEN 'NOT_YET_AVAILABLE' THEN 'This item is not ready for normal checkout.' WHEN 'INVALID_QTY' THEN 'Quantity must be greater than zero.' WHEN 'BELOW_MIN_QTY' THEN 'Quantity is below the minimum for this offer.' WHEN 'ABOVE_MAX_QTY' THEN 'Quantity is above the maximum for this offer.' WHEN 'INVALID_QTY_INCREMENT' THEN 'Quantity does not match this offer''s required increment.' WHEN 'INSUFFICIENT_STOCK' THEN 'Requested quantity is not currently available.' ELSE 'Basket validation failed.' END)) FILTER(WHERE ERROR_CODE IS NOT NULL),'[]'::jsonb)
 ) INTO v_result FROM resolved;
 RETURN v_result;
END; $$;


--
-- Name: validate_promotion(character varying, character varying, numeric, character varying); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.validate_promotion(p_client_id character varying, p_code character varying, p_order_value numeric, p_delivery_class character varying DEFAULT NULL::character varying) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE p RECORD; d NUMERIC:=0;
BEGIN
 SELECT * INTO p FROM config.PROMOTION WHERE CLIENT_ID=p_client_id AND UPPER(PROMO_CODE)=UPPER(TRIM(p_code)) AND ACTIVE=TRUE AND (STARTS_DSTAMP IS NULL OR STARTS_DSTAMP<=now()) AND (ENDS_DSTAMP IS NULL OR ENDS_DSTAMP>=now());
 IF NOT FOUND THEN RETURN jsonb_build_object('valid',FALSE,'code','PROMO_NOT_FOUND'); END IF;
 IF p.MIN_ORDER_VALUE IS NOT NULL AND COALESCE(p_order_value,0)<p.MIN_ORDER_VALUE THEN RETURN jsonb_build_object('valid',FALSE,'code','MIN_ORDER_NOT_MET','minimum',p.MIN_ORDER_VALUE); END IF;
 IF p.DELIVERY_CLASS IS NOT NULL AND UPPER(COALESCE(p_delivery_class,''))<>UPPER(p.DELIVERY_CLASS) THEN RETURN jsonb_build_object('valid',FALSE,'code','DELIVERY_CLASS_NOT_ELIGIBLE'); END IF;
 IF p.PROMOTION_TYPE='PERCENT' THEN d:=ROUND(COALESCE(p_order_value,0)*(p.PROMOTION_VALUE/100.0),2); ELSIF p.PROMOTION_TYPE='FIXED' THEN d:=LEAST(COALESCE(p.PROMOTION_VALUE,0),COALESCE(p_order_value,0)); END IF;
 RETURN jsonb_build_object('valid',TRUE,'promotionId',p.PROMOTION_ID,'promoCode',p.PROMO_CODE,'type',p.PROMOTION_TYPE,'value',p.PROMOTION_VALUE,'discountAmount',d,'freeDelivery',p.PROMOTION_TYPE='FREE_DELIVERY');
END; $$;


--
-- Name: carrier_condition_match(bigint, numeric, numeric, numeric, character varying, character varying, character varying, character varying, character varying, character varying); Type: FUNCTION; Schema: config; Owner: -
--

CREATE FUNCTION config.carrier_condition_match(p_rule_id bigint, p_weight_kg numeric, p_volume_cm3 numeric, p_order_value numeric, p_delivery_class character varying, p_dispatch_method character varying, p_requested_service character varying, p_country character varying, p_postcode character varying, p_free_delivery character varying) RETURNS boolean
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    r RECORD;
    v_text TEXT;
    v_num NUMERIC;
    v_bool BOOLEAN;
    v_match BOOLEAN;
    v_group INTEGER;
    v_group_match BOOLEAN;
BEGIN
    -- No child conditions means the rule relies only on the direct
    -- columns on config.CARRIER_SELECTION_RULE.
    IF NOT EXISTS (
        SELECT 1
        FROM config.CARRIER_SELECTION_CONDITION
        WHERE RULE_ID = p_rule_id
    ) THEN
        RETURN TRUE;
    END IF;

    -- Conditions within the same CONDITION_GROUP are ANDed together.
    -- Different groups are ORed together.
    FOR v_group IN
        SELECT DISTINCT CONDITION_GROUP
        FROM config.CARRIER_SELECTION_CONDITION
        WHERE RULE_ID = p_rule_id
        ORDER BY CONDITION_GROUP
    LOOP
        v_group_match := TRUE;

        FOR r IN
            SELECT *
            FROM config.CARRIER_SELECTION_CONDITION
            WHERE RULE_ID = p_rule_id
              AND CONDITION_GROUP = v_group
            ORDER BY SEQUENCE, CONDITION_ID
        LOOP
            v_text := NULL;
            v_num := NULL;
            v_bool := NULL;
            v_match := FALSE;

            -- Resolve only known/safe fields.
            CASE UPPER(r.FIELD_NAME)
                WHEN 'WEIGHT_KG' THEN
                    v_num := p_weight_kg;
                WHEN 'VOLUME_CM3' THEN
                    v_num := p_volume_cm3;
                WHEN 'ORDER_VALUE' THEN
                    v_num := p_order_value;
                WHEN 'DELIVERY_CLASS' THEN
                    v_text := p_delivery_class;
                WHEN 'DISPATCH_METHOD' THEN
                    v_text := p_dispatch_method;
                WHEN 'SERVICE_LEVEL' THEN
                    v_text := p_requested_service;
                WHEN 'COUNTRY' THEN
                    v_text := p_country;
                WHEN 'POSTCODE' THEN
                    v_text := p_postcode;
                WHEN 'POSTCODE_PREFIX' THEN
                    v_text := p_postcode;
                WHEN 'FREE_DELIVERY' THEN
                    v_bool := UPPER(COALESCE(p_free_delivery,'N'))
                              IN ('Y','YES','TRUE','1');
                ELSE
                    RAISE EXCEPTION
                        'Unsupported carrier condition FIELD_NAME: %',
                        r.FIELD_NAME;
            END CASE;

            -- Operators are handled as PL/pgSQL statements rather than
            -- trying to place RAISE EXCEPTION inside a SQL CASE expression.
            IF UPPER(r.OPERATOR) = 'EQ' THEN
                IF v_num IS NOT NULL THEN
                    v_match := v_num = r.VALUE_NUMERIC;
                ELSIF v_bool IS NOT NULL THEN
                    v_match := v_bool = r.VALUE_BOOLEAN;
                ELSE
                    v_match := UPPER(COALESCE(v_text,'')) =
                               UPPER(COALESCE(r.VALUE_TEXT,''));
                END IF;

            ELSIF UPPER(r.OPERATOR) = 'NE' THEN
                IF v_num IS NOT NULL THEN
                    v_match := v_num <> r.VALUE_NUMERIC;
                ELSIF v_bool IS NOT NULL THEN
                    v_match := v_bool <> r.VALUE_BOOLEAN;
                ELSE
                    v_match := UPPER(COALESCE(v_text,'')) <>
                               UPPER(COALESCE(r.VALUE_TEXT,''));
                END IF;

            ELSIF UPPER(r.OPERATOR) = 'GT' THEN
                v_match := v_num > r.VALUE_NUMERIC;

            ELSIF UPPER(r.OPERATOR) = 'GTE' THEN
                v_match := v_num >= r.VALUE_NUMERIC;

            ELSIF UPPER(r.OPERATOR) = 'LT' THEN
                v_match := v_num < r.VALUE_NUMERIC;

            ELSIF UPPER(r.OPERATOR) = 'LTE' THEN
                v_match := v_num <= r.VALUE_NUMERIC;

            ELSIF UPPER(r.OPERATOR) = 'BETWEEN' THEN
                v_match := v_num BETWEEN r.VALUE_FROM AND r.VALUE_TO;

            ELSIF UPPER(r.OPERATOR) = 'IN' THEN
                v_match := UPPER(COALESCE(v_text,'')) = ANY(
                    string_to_array(
                        UPPER(REPLACE(COALESCE(r.VALUE_TEXT,''),' ','')),
                        ','
                    )
                );

            ELSIF UPPER(r.OPERATOR) = 'STARTS_WITH' THEN
                v_match := UPPER(COALESCE(v_text,'')) LIKE
                           UPPER(COALESCE(r.VALUE_TEXT,'')) || '%';

            ELSIF UPPER(r.OPERATOR) = 'IS_TRUE' THEN
                v_match := COALESCE(v_bool,FALSE) = TRUE;

            ELSIF UPPER(r.OPERATOR) = 'IS_FALSE' THEN
                v_match := COALESCE(v_bool,FALSE) = FALSE;

            ELSE
                RAISE EXCEPTION
                    'Unsupported carrier condition OPERATOR: %',
                    r.OPERATOR;
            END IF;

            IF COALESCE(r.NEGATE,FALSE) THEN
                v_match := NOT COALESCE(v_match,FALSE);
            END IF;

            IF NOT COALESCE(v_match,FALSE) THEN
                v_group_match := FALSE;
                EXIT;
            END IF;
        END LOOP;

        -- OR between groups: one fully-matched group is enough.
        IF v_group_match THEN
            RETURN TRUE;
        END IF;
    END LOOP;

    RETURN FALSE;
END;
$$;


--
-- Name: merge_condition_match(bigint, boolean, boolean, boolean, boolean, boolean, character varying, character varying, boolean, character varying, numeric, numeric, boolean, boolean, character varying); Type: FUNCTION; Schema: config; Owner: -
--

CREATE FUNCTION config.merge_condition_match(p_rule_id bigint, p_same_order boolean, p_same_customer boolean, p_same_postcode boolean, p_same_country boolean, p_same_delivery_class boolean, p_left_delivery_class character varying, p_right_delivery_class character varying, p_same_fulfilment_method boolean, p_fulfilment_method character varying, p_combined_weight_kg numeric, p_combined_volume_cm3 numeric, p_any_held boolean, p_both_held boolean, p_fulfilment_preference character varying) RETURNS boolean
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    r RECORD;
    v_group INTEGER;
    v_group_match BOOLEAN;
    v_match BOOLEAN;
    v_text TEXT;
    v_num NUMERIC;
    v_bool BOOLEAN;
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM config.MERGE_RULE_CONDITION
        WHERE RULE_ID=p_rule_id
    ) THEN
        RETURN TRUE;
    END IF;

    FOR v_group IN
        SELECT DISTINCT CONDITION_GROUP
        FROM config.MERGE_RULE_CONDITION
        WHERE RULE_ID=p_rule_id
        ORDER BY CONDITION_GROUP
    LOOP
        v_group_match := TRUE;

        FOR r IN
            SELECT *
            FROM config.MERGE_RULE_CONDITION
            WHERE RULE_ID=p_rule_id
              AND CONDITION_GROUP=v_group
            ORDER BY SEQUENCE,CONDITION_ID
        LOOP
            v_text := NULL;
            v_num := NULL;
            v_bool := NULL;
            v_match := FALSE;

            CASE UPPER(r.FIELD_NAME)
                WHEN 'SAME_ORDER' THEN v_bool := p_same_order;
                WHEN 'SAME_CUSTOMER' THEN v_bool := p_same_customer;
                WHEN 'SAME_POSTCODE' THEN v_bool := p_same_postcode;
                WHEN 'SAME_COUNTRY' THEN v_bool := p_same_country;
                WHEN 'SAME_DELIVERY_CLASS' THEN v_bool := p_same_delivery_class;
                WHEN 'LEFT_DELIVERY_CLASS' THEN v_text := p_left_delivery_class;
                WHEN 'RIGHT_DELIVERY_CLASS' THEN v_text := p_right_delivery_class;
                WHEN 'SAME_FULFILMENT_METHOD' THEN v_bool := p_same_fulfilment_method;
                WHEN 'FULFILMENT_METHOD' THEN v_text := p_fulfilment_method;
                WHEN 'COMBINED_WEIGHT_KG' THEN v_num := p_combined_weight_kg;
                WHEN 'COMBINED_VOLUME_CM3' THEN v_num := p_combined_volume_cm3;
                WHEN 'ANY_HELD' THEN v_bool := p_any_held;
                WHEN 'BOTH_HELD' THEN v_bool := p_both_held;
                WHEN 'FULFILMENT_PREFERENCE' THEN v_text := p_fulfilment_preference;
                ELSE
                    RAISE EXCEPTION
                        'Unsupported merge condition FIELD_NAME: %',
                        r.FIELD_NAME;
            END CASE;

            IF UPPER(r.OPERATOR)='EQ' THEN
                IF v_num IS NOT NULL THEN
                    v_match := v_num=r.VALUE_NUMERIC;
                ELSIF v_bool IS NOT NULL THEN
                    v_match := v_bool=r.VALUE_BOOLEAN;
                ELSE
                    v_match := UPPER(COALESCE(v_text,''))=
                               UPPER(COALESCE(r.VALUE_TEXT,''));
                END IF;

            ELSIF UPPER(r.OPERATOR)='NE' THEN
                IF v_num IS NOT NULL THEN
                    v_match := v_num<>r.VALUE_NUMERIC;
                ELSIF v_bool IS NOT NULL THEN
                    v_match := v_bool<>r.VALUE_BOOLEAN;
                ELSE
                    v_match := UPPER(COALESCE(v_text,''))<>
                               UPPER(COALESCE(r.VALUE_TEXT,''));
                END IF;

            ELSIF UPPER(r.OPERATOR)='GT' THEN
                v_match := v_num>r.VALUE_NUMERIC;

            ELSIF UPPER(r.OPERATOR)='GTE' THEN
                v_match := v_num>=r.VALUE_NUMERIC;

            ELSIF UPPER(r.OPERATOR)='LT' THEN
                v_match := v_num<r.VALUE_NUMERIC;

            ELSIF UPPER(r.OPERATOR)='LTE' THEN
                v_match := v_num<=r.VALUE_NUMERIC;

            ELSIF UPPER(r.OPERATOR)='BETWEEN' THEN
                v_match := v_num BETWEEN r.VALUE_FROM AND r.VALUE_TO;

            ELSIF UPPER(r.OPERATOR)='IN' THEN
                v_match := UPPER(COALESCE(v_text,'')) = ANY(
                    string_to_array(
                        UPPER(REPLACE(COALESCE(r.VALUE_TEXT,''),' ','')),
                        ','
                    )
                );

            ELSIF UPPER(r.OPERATOR)='IS_TRUE' THEN
                v_match := COALESCE(v_bool,FALSE)=TRUE;

            ELSIF UPPER(r.OPERATOR)='IS_FALSE' THEN
                v_match := COALESCE(v_bool,FALSE)=FALSE;

            ELSE
                RAISE EXCEPTION
                    'Unsupported merge condition OPERATOR: %',
                    r.OPERATOR;
            END IF;

            IF COALESCE(r.NEGATE,FALSE) THEN
                v_match := NOT COALESCE(v_match,FALSE);
            END IF;

            IF NOT COALESCE(v_match,FALSE) THEN
                v_group_match := FALSE;
                EXIT;
            END IF;
        END LOOP;

        IF v_group_match THEN
            RETURN TRUE;
        END IF;
    END LOOP;

    RETURN FALSE;
END;
$$;


--
-- Name: allocate_order(character varying, character varying); Type: FUNCTION; Schema: core; Owner: -
--

CREATE FUNCTION core.allocate_order(p_client_id character varying, p_order_id character varying) RETURNS TABLE(result_status character varying, result_order_id character varying, result_lines integer, result_full_lines integer, result_part_lines integer, result_no_stock_lines integer, result_qty_allocated numeric, result_message text)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_line RECORD;
    v_inv RECORD;
    v_required NUMERIC(15,6);
    v_take NUMERIC(15,6);
    v_line_allocated NUMERIC(15,6);
    v_total_allocated NUMERIC(15,6) := 0;
    v_lines INTEGER := 0;
    v_full_lines INTEGER := 0;
    v_part_lines INTEGER := 0;
    v_no_stock_lines INTEGER := 0;
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM core.ORDER_HEADER
        WHERE CLIENT_ID = p_client_id AND ORDER_ID = p_order_id
    ) THEN
        RETURN QUERY SELECT 'ERROR'::VARCHAR, p_order_id::VARCHAR, 0,0,0,0,0::NUMERIC,
            'Order does not exist.'::TEXT;
        RETURN;
    END IF;

    FOR v_line IN
        SELECT ol.CLIENT_ID, ol.ORDER_ID, ol.LINE_ID, ol.SKU_ID,
               ol.BATCH_ID, ol.CONDITION_ID, ol.OWNER_ID,
               ol.QTY_ORDERED,
               COALESCE(ol.QTY_PICKED,0) AS QTY_PICKED,
               COALESCE(ol.QTY_SOFT_ALLOCATED,0) AS QTY_SOFT_ALLOCATED
        FROM core.ORDER_LINE ol
        WHERE ol.CLIENT_ID = p_client_id
          AND ol.ORDER_ID = p_order_id
          AND UPPER(COALESCE(ol.ALLOCATE,'Y')) <> 'N'
          AND COALESCE(ol.QTY_PICKED,0) + COALESCE(ol.QTY_SOFT_ALLOCATED,0) < ol.QTY_ORDERED
        ORDER BY ol.LINE_ID
        FOR UPDATE
    LOOP
        v_lines := v_lines + 1;
        v_required := v_line.QTY_ORDERED - v_line.QTY_PICKED - v_line.QTY_SOFT_ALLOCATED;
        v_line_allocated := 0;

        FOR v_inv IN
            SELECT i.KEY, (i.QTY_ON_HAND - i.QTY_ALLOCATED) AS AVAILABLE_QTY
            FROM core.INVENTORY i
            JOIN core.LOCATION l ON l.LOCATION_ID = i.LOCATION_ID
            WHERE i.CLIENT_ID = v_line.CLIENT_ID
              AND i.SKU_ID = v_line.SKU_ID
              AND (i.QTY_ON_HAND - i.QTY_ALLOCATED) > 0
              AND UPPER(COALESCE(i.DISALLOW_ALLOC,'N')) <> 'Y'
              AND UPPER(COALESCE(i.LOCK_STATUS,'')) NOT IN ('LOCKED','HOLD','QUARANTINE')
              AND UPPER(COALESCE(l.DISALLOW_ALLOC,'N')) <> 'Y'
              AND UPPER(COALESCE(l.LOCK_STATUS,'')) NOT IN ('LOCKED','HOLD','QUARANTINE')
              AND UPPER(COALESCE(l.ACTIVE,'Y')) = 'Y'
              AND (v_line.BATCH_ID IS NULL OR i.BATCH_ID = v_line.BATCH_ID)
              AND (v_line.CONDITION_ID IS NULL OR i.CONDITION_ID = v_line.CONDITION_ID)
              AND (v_line.OWNER_ID IS NULL OR i.OWNER_ID = v_line.OWNER_ID)
            ORDER BY i.RECEIPT_DSTAMP, i.KEY
            FOR UPDATE OF i SKIP LOCKED
        LOOP
            EXIT WHEN v_required <= 0;
            v_take := LEAST(v_required, v_inv.AVAILABLE_QTY);

            UPDATE core.INVENTORY
            SET QTY_ALLOCATED = QTY_ALLOCATED + v_take
            WHERE KEY = v_inv.KEY;

            INSERT INTO core.ALLOCATION (
                CLIENT_ID, ORDER_ID, LINE_ID, INVENTORY_KEY,
                QTY_ALLOCATED, QTY_PICKED, QTY_RELEASED, STATUS,
                CREATED_BY, LAST_UPDATED_BY
            ) VALUES (
                v_line.CLIENT_ID, v_line.ORDER_ID, v_line.LINE_ID, v_inv.KEY,
                v_take, 0, 0, 'ALLOCATED',
                'ALLOCATE_ORDER', 'ALLOCATE_ORDER'
            );

            v_required := v_required - v_take;
            v_line_allocated := v_line_allocated + v_take;
            v_total_allocated := v_total_allocated + v_take;
        END LOOP;

        UPDATE core.ORDER_LINE
        SET QTY_SOFT_ALLOCATED = COALESCE(QTY_SOFT_ALLOCATED,0) + v_line_allocated,
            BACK_ORDERED = CASE
                WHEN COALESCE(QTY_PICKED,0) + COALESCE(QTY_SOFT_ALLOCATED,0) + v_line_allocated >= QTY_ORDERED
                    THEN 'N' ELSE 'Y' END,
            LAST_UPDATED_BY = 'ALLOCATE_ORDER', LAST_UPDATE_DATE = now()
        WHERE CLIENT_ID = v_line.CLIENT_ID AND ORDER_ID = v_line.ORDER_ID AND LINE_ID = v_line.LINE_ID;

        IF v_line_allocated = 0 THEN v_no_stock_lines := v_no_stock_lines + 1;
        ELSIF v_required > 0 THEN v_part_lines := v_part_lines + 1;
        ELSE v_full_lines := v_full_lines + 1;
        END IF;
    END LOOP;

    UPDATE core.ORDER_HEADER oh
    SET FULFILMENT_STATUS = CASE
            WHEN NOT EXISTS (
                SELECT 1 FROM core.ORDER_LINE ol
                WHERE ol.CLIENT_ID = p_client_id AND ol.ORDER_ID = p_order_id
                  AND COALESCE(ol.QTY_PICKED,0) + COALESCE(ol.QTY_SOFT_ALLOCATED,0) < ol.QTY_ORDERED
            ) THEN 'ALLOCATED'
            WHEN EXISTS (
                SELECT 1 FROM core.ORDER_LINE ol
                WHERE ol.CLIENT_ID = p_client_id AND ol.ORDER_ID = p_order_id
                  AND COALESCE(ol.QTY_SOFT_ALLOCATED,0) > 0
            ) THEN 'PART_ALLOCATED'
            ELSE COALESCE(oh.FULFILMENT_STATUS,'UNALLOCATED')
        END,
        LAST_UPDATED_BY = 'ALLOCATE_ORDER', LAST_UPDATE_DATE = now()
    WHERE oh.CLIENT_ID = p_client_id AND oh.ORDER_ID = p_order_id;

    IF v_lines = 0 THEN
        RETURN QUERY SELECT 'ALREADY_ALLOCATED'::VARCHAR, p_order_id::VARCHAR, 0,0,0,0,0::NUMERIC,
            'No order lines required additional allocation.'::TEXT;
        RETURN;
    END IF;

    RETURN QUERY SELECT
        CASE WHEN v_part_lines = 0 AND v_no_stock_lines = 0 THEN 'ALLOCATED'
             WHEN v_full_lines = 0 AND v_part_lines = 0 AND v_no_stock_lines > 0 THEN 'NO_STOCK'
             ELSE 'PART_ALLOCATED' END::VARCHAR,
        p_order_id::VARCHAR, v_lines, v_full_lines, v_part_lines, v_no_stock_lines,
        v_total_allocated::NUMERIC,
        format('Processed %s line(s): %s full, %s part, %s no stock. Reserved %s unit(s).',
               v_lines, v_full_lines, v_part_lines, v_no_stock_lines, v_total_allocated)::TEXT;
END;
$$;


--
-- Name: confirm_pick(bigint, numeric, character varying, character varying, boolean, character varying); Type: FUNCTION; Schema: core; Owner: -
--

CREATE FUNCTION core.confirm_pick(p_pick_task_id bigint, p_qty_picked numeric, p_user_id character varying DEFAULT 'SYSTEM'::character varying, p_station_id character varying DEFAULT 'WMS'::character varying, p_short_close boolean DEFAULT false, p_short_reason character varying DEFAULT NULL::character varying) RETURNS TABLE(result_status character varying, result_pick_task_id bigint, result_qty_picked numeric, result_qty_short numeric, result_message text)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_task RECORD;
    v_alloc RECORD;
    v_inv RECORD;
    v_task_remaining NUMERIC(15,6);
    v_alloc_remaining NUMERIC(15,6);
    v_short NUMERIC(15,6) := 0;
    v_user VARCHAR(20) := LEFT(COALESCE(NULLIF(p_user_id,''),'SYSTEM'),20);
    v_station VARCHAR(256) := LEFT(COALESCE(NULLIF(p_station_id,''),'WMS'),256);
BEGIN
    SELECT * INTO v_task FROM core.PICK_TASK WHERE PICK_TASK_ID=p_pick_task_id FOR UPDATE;
    IF NOT FOUND THEN
        RETURN QUERY SELECT 'ERROR'::VARCHAR,p_pick_task_id,0::NUMERIC,0::NUMERIC,'Pick task does not exist.'::TEXT;
        RETURN;
    END IF;

    IF v_task.STATUS NOT IN ('OPEN','PART_PICKED') THEN
        RETURN QUERY SELECT 'ERROR'::VARCHAR,p_pick_task_id,0::NUMERIC,0::NUMERIC,
            format('Pick task is already %s.',v_task.STATUS)::TEXT;
        RETURN;
    END IF;

    IF p_qty_picked < 0 OR (p_qty_picked = 0 AND NOT p_short_close) THEN
        RETURN QUERY SELECT 'ERROR'::VARCHAR,p_pick_task_id,0::NUMERIC,0::NUMERIC,
            'Pick quantity must be positive, unless zero is being short-closed.'::TEXT;
        RETURN;
    END IF;

    v_task_remaining := v_task.QTY_REQUIRED-v_task.QTY_PICKED-v_task.SHORT_QTY;
    IF p_qty_picked > v_task_remaining THEN
        RETURN QUERY SELECT 'ERROR'::VARCHAR,p_pick_task_id,0::NUMERIC,0::NUMERIC,
            format('Cannot pick %s; task only has %s remaining.',p_qty_picked,v_task_remaining)::TEXT;
        RETURN;
    END IF;

    SELECT * INTO v_alloc FROM core.ALLOCATION WHERE ALLOCATION_ID=v_task.ALLOCATION_ID FOR UPDATE;
    v_alloc_remaining := v_alloc.QTY_ALLOCATED-v_alloc.QTY_PICKED-v_alloc.QTY_RELEASED;
    IF p_qty_picked > v_alloc_remaining THEN
        RETURN QUERY SELECT 'ERROR'::VARCHAR,p_pick_task_id,0::NUMERIC,0::NUMERIC,
            'Pick exceeds the open allocation quantity.'::TEXT;
        RETURN;
    END IF;

    SELECT * INTO v_inv FROM core.INVENTORY WHERE KEY=v_task.INVENTORY_KEY FOR UPDATE;
    IF p_qty_picked > v_inv.QTY_ON_HAND THEN
        RETURN QUERY SELECT 'ERROR'::VARCHAR,p_pick_task_id,0::NUMERIC,0::NUMERIC,'Pick exceeds physical stock on hand.'::TEXT;
        RETURN;
    END IF;
    IF p_qty_picked > v_inv.QTY_ALLOCATED THEN
        RETURN QUERY SELECT 'ERROR'::VARCHAR,p_pick_task_id,0::NUMERIC,0::NUMERIC,'Pick exceeds inventory reserved quantity.'::TEXT;
        RETURN;
    END IF;

    IF p_qty_picked > 0 THEN
        UPDATE core.INVENTORY
        SET QTY_ON_HAND=QTY_ON_HAND-p_qty_picked,
            QTY_ALLOCATED=QTY_ALLOCATED-p_qty_picked,
            MOVE_DSTAMP=now()
        WHERE KEY=v_task.INVENTORY_KEY;

        UPDATE core.ALLOCATION
        SET QTY_PICKED=QTY_PICKED+p_qty_picked,
            STATUS='PART_PICKED',LAST_UPDATE_DSTAMP=now(),LAST_UPDATED_BY=v_user
        WHERE ALLOCATION_ID=v_task.ALLOCATION_ID;

        UPDATE core.ORDER_LINE
        SET QTY_PICKED=COALESCE(QTY_PICKED,0)+p_qty_picked,
            QTY_SOFT_ALLOCATED=GREATEST(0,COALESCE(QTY_SOFT_ALLOCATED,0)-p_qty_picked),
            LAST_UPDATED_BY=v_user,LAST_UPDATE_DATE=now()
        WHERE CLIENT_ID=v_task.CLIENT_ID AND ORDER_ID=v_task.ORDER_ID AND LINE_ID=v_task.LINE_ID;

        INSERT INTO core.INVENTORY_TRANSACTION (
            CODE,SITE_ID,FROM_SITE_ID,FROM_LOC_ID,FINAL_LOC_ID,OWNER_ID,CLIENT_ID,SKU_ID,TAG_ID,
            CONTAINER_ID,BATCH_ID,QC_STATUS,EXPIRY_DSTAMP,MANUF_DSTAMP,ORIGIN_ID,CONDITION_ID,LOCK_STATUS,
            DSTAMP,SUPPLIER_ID,REFERENCE_ID,LINE_ID,STATION_ID,USER_ID,UPDATE_QTY,ORIGINAL_QTY,
            COMPLETE_DSTAMP,NOTES,LOCK_CODE,SOURCE,REFERENCE_TYPE
        ) VALUES (
            'PICK',v_inv.SITE_ID,v_inv.SITE_ID,v_inv.LOCATION_ID,v_inv.LOCATION_ID,v_inv.OWNER_ID,
            v_inv.CLIENT_ID,v_inv.SKU_ID,v_inv.TAG_ID,v_inv.CONTAINER_ID,v_inv.BATCH_ID,v_inv.QC_STATUS,
            v_inv.EXPIRY_DSTAMP,v_inv.MANUF_DSTAMP,v_inv.ORIGIN_ID,v_inv.CONDITION_ID,v_inv.LOCK_STATUS,
            now(),v_inv.SUPPLIER_ID,v_task.ORDER_ID,v_task.LINE_ID,v_station,v_user,-p_qty_picked,
            v_inv.QTY_ON_HAND,now(),format('Pick task %s',p_pick_task_id),v_inv.LOCK_CODE,
            'WAREHOUSE_EXECUTION','ORDER'
        );
    END IF;

    IF p_short_close THEN
        v_short := v_task_remaining-p_qty_picked;
        IF v_short > 0 THEN
            UPDATE core.INVENTORY SET QTY_ALLOCATED=GREATEST(0,QTY_ALLOCATED-v_short)
            WHERE KEY=v_task.INVENTORY_KEY;
            UPDATE core.ALLOCATION
            SET QTY_RELEASED=QTY_RELEASED+v_short,
                LAST_UPDATE_DSTAMP=now(),LAST_UPDATED_BY=v_user
            WHERE ALLOCATION_ID=v_task.ALLOCATION_ID;
            UPDATE core.ORDER_LINE
            SET QTY_SOFT_ALLOCATED=GREATEST(0,COALESCE(QTY_SOFT_ALLOCATED,0)-v_short),
                LAST_UPDATED_BY=v_user,LAST_UPDATE_DATE=now()
            WHERE CLIENT_ID=v_task.CLIENT_ID AND ORDER_ID=v_task.ORDER_ID AND LINE_ID=v_task.LINE_ID;
        END IF;
    END IF;

    UPDATE core.PICK_TASK
    SET QTY_PICKED=QTY_PICKED+p_qty_picked,
        SHORT_QTY=SHORT_QTY+v_short,
        STATUS=CASE
            WHEN p_short_close AND v_short>0 THEN 'SHORT'
            WHEN QTY_PICKED+p_qty_picked >= QTY_REQUIRED THEN 'PICKED'
            ELSE 'PART_PICKED' END,
        SHORT_REASON=CASE WHEN p_short_close AND v_short>0 THEN COALESCE(p_short_reason,'Short pick') ELSE SHORT_REASON END,
        STARTED_DSTAMP=COALESCE(STARTED_DSTAMP,now()),
        COMPLETED_DSTAMP=CASE WHEN (p_short_close AND v_short>0) OR QTY_PICKED+p_qty_picked>=QTY_REQUIRED THEN now() ELSE COMPLETED_DSTAMP END,
        LAST_UPDATE_DSTAMP=now(),LAST_UPDATED_BY=v_user
    WHERE PICK_TASK_ID=p_pick_task_id;

    UPDATE core.ALLOCATION
    SET STATUS=CASE
            WHEN QTY_PICKED+QTY_RELEASED >= QTY_ALLOCATED AND QTY_RELEASED>0 AND QTY_PICKED>0 THEN 'SHORT'
            WHEN QTY_PICKED >= QTY_ALLOCATED THEN 'PICKED'
            WHEN QTY_PICKED+QTY_RELEASED >= QTY_ALLOCATED THEN 'RELEASED'
            ELSE 'PART_PICKED' END,
        LAST_UPDATE_DSTAMP=now(),LAST_UPDATED_BY=v_user
    WHERE ALLOCATION_ID=v_task.ALLOCATION_ID;

    UPDATE core.ORDER_LINE ol
    SET QTY_TASKED=COALESCE(ol.QTY_PICKED,0)+COALESCE((
            SELECT SUM(GREATEST(0,pt.QTY_REQUIRED-pt.QTY_PICKED-pt.SHORT_QTY))
            FROM core.PICK_TASK pt
            WHERE pt.CLIENT_ID=ol.CLIENT_ID AND pt.ORDER_ID=ol.ORDER_ID AND pt.LINE_ID=ol.LINE_ID
              AND pt.STATUS IN ('OPEN','PART_PICKED')
        ),0),
        BACK_ORDERED=CASE WHEN COALESCE(ol.QTY_PICKED,0)+COALESCE(ol.QTY_SOFT_ALLOCATED,0)>=ol.QTY_ORDERED THEN 'N' ELSE 'Y' END,
        LAST_UPDATED_BY=v_user,LAST_UPDATE_DATE=now()
    WHERE ol.CLIENT_ID=v_task.CLIENT_ID AND ol.ORDER_ID=v_task.ORDER_ID AND ol.LINE_ID=v_task.LINE_ID;

    UPDATE core.ORDER_HEADER oh
    SET FULFILMENT_STATUS=CASE
            WHEN NOT EXISTS (SELECT 1 FROM core.ORDER_LINE ol WHERE ol.CLIENT_ID=v_task.CLIENT_ID AND ol.ORDER_ID=v_task.ORDER_ID AND COALESCE(ol.QTY_PICKED,0)<ol.QTY_ORDERED)
                THEN 'READY_TO_PACK'
            WHEN EXISTS (SELECT 1 FROM core.ORDER_LINE ol WHERE ol.CLIENT_ID=v_task.CLIENT_ID AND ol.ORDER_ID=v_task.ORDER_ID AND COALESCE(ol.QTY_PICKED,0)>0)
                THEN 'PART_PICKED'
            ELSE 'PICKING' END,
        LAST_UPDATED_BY=v_user,LAST_UPDATE_DATE=now()
    WHERE oh.CLIENT_ID=v_task.CLIENT_ID AND oh.ORDER_ID=v_task.ORDER_ID;

    RETURN QUERY SELECT
        CASE WHEN p_short_close AND v_short>0 THEN 'SHORT' WHEN p_qty_picked=v_task_remaining THEN 'PICKED' ELSE 'PART_PICKED' END::VARCHAR,
        p_pick_task_id,p_qty_picked::NUMERIC,v_short::NUMERIC,
        format('Confirmed %s unit(s) on pick task %s%s.',p_qty_picked,p_pick_task_id,
               CASE WHEN v_short>0 THEN format('; released %s short unit(s)',v_short) ELSE '' END)::TEXT;
END;
$$;


--
-- Name: create_pick_tasks(character varying, character varying, character varying); Type: FUNCTION; Schema: core; Owner: -
--

CREATE FUNCTION core.create_pick_tasks(p_client_id character varying, p_order_id character varying, p_created_by character varying DEFAULT 'SYSTEM'::character varying) RETURNS TABLE(result_status character varying, result_order_id character varying, result_tasks_created integer, result_qty_tasked numeric, result_message text)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_created INTEGER := 0;
    v_qty NUMERIC(15,6) := 0;
    v_row RECORD;
    v_open NUMERIC(15,6);
BEGIN
    IF NOT EXISTS (SELECT 1 FROM core.ORDER_HEADER WHERE CLIENT_ID=p_client_id AND ORDER_ID=p_order_id) THEN
        RETURN QUERY SELECT 'ERROR'::VARCHAR,p_order_id::VARCHAR,0,0::NUMERIC,'Order does not exist.'::TEXT;
        RETURN;
    END IF;

    FOR v_row IN
        SELECT a.ALLOCATION_ID,a.CLIENT_ID,a.ORDER_ID,a.LINE_ID,a.INVENTORY_KEY,
               a.QTY_ALLOCATED,a.QTY_PICKED,a.QTY_RELEASED,
               ol.SKU_ID,i.LOCATION_ID,i.BATCH_ID
        FROM core.ALLOCATION a
        JOIN core.ORDER_LINE ol ON ol.CLIENT_ID=a.CLIENT_ID AND ol.ORDER_ID=a.ORDER_ID AND ol.LINE_ID=a.LINE_ID
        JOIN core.INVENTORY i ON i.KEY=a.INVENTORY_KEY
        WHERE a.CLIENT_ID=p_client_id AND a.ORDER_ID=p_order_id
          AND (a.QTY_ALLOCATED-a.QTY_PICKED-a.QTY_RELEASED)>0
          AND NOT EXISTS (SELECT 1 FROM core.PICK_TASK pt WHERE pt.ALLOCATION_ID=a.ALLOCATION_ID)
        ORDER BY a.LINE_ID,a.ALLOCATION_ID
        FOR UPDATE OF a
    LOOP
        v_open := v_row.QTY_ALLOCATED-v_row.QTY_PICKED-v_row.QTY_RELEASED;
        INSERT INTO core.PICK_TASK (
            CLIENT_ID,ORDER_ID,LINE_ID,ALLOCATION_ID,INVENTORY_KEY,SKU_ID,LOCATION_ID,BATCH_ID,
            QTY_REQUIRED,CREATED_BY,LAST_UPDATED_BY
        ) VALUES (
            v_row.CLIENT_ID,v_row.ORDER_ID,v_row.LINE_ID,v_row.ALLOCATION_ID,v_row.INVENTORY_KEY,
            v_row.SKU_ID,v_row.LOCATION_ID,v_row.BATCH_ID,v_open,
            COALESCE(NULLIF(p_created_by,''),'SYSTEM'),COALESCE(NULLIF(p_created_by,''),'SYSTEM')
        );
        v_created := v_created+1;
        v_qty := v_qty+v_open;
    END LOOP;

    UPDATE core.ORDER_LINE ol
    SET QTY_TASKED = COALESCE(ol.QTY_PICKED,0) + COALESCE((
            SELECT SUM(GREATEST(0,pt.QTY_REQUIRED-pt.QTY_PICKED-pt.SHORT_QTY))
            FROM core.PICK_TASK pt
            WHERE pt.CLIENT_ID=ol.CLIENT_ID AND pt.ORDER_ID=ol.ORDER_ID AND pt.LINE_ID=ol.LINE_ID
              AND pt.STATUS IN ('OPEN','PART_PICKED')
        ),0),
        LAST_UPDATED_BY='CREATE_PICK_TASKS',LAST_UPDATE_DATE=now()
    WHERE ol.CLIENT_ID=p_client_id AND ol.ORDER_ID=p_order_id;

    IF v_created>0 THEN
        UPDATE core.ORDER_HEADER SET FULFILMENT_STATUS='PICKING',LAST_UPDATED_BY='CREATE_PICK_TASKS',LAST_UPDATE_DATE=now()
        WHERE CLIENT_ID=p_client_id AND ORDER_ID=p_order_id;
    END IF;

    RETURN QUERY SELECT
        CASE WHEN v_created=0 THEN 'NO_NEW_TASKS' ELSE 'TASKS_CREATED' END::VARCHAR,
        p_order_id::VARCHAR,v_created,v_qty::NUMERIC,
        CASE WHEN v_created=0 THEN 'No untasked open allocations were found.'
             ELSE format('Created %s pick task(s) for %s unit(s).',v_created,v_qty) END::TEXT;
END;
$$;


--
-- Name: deallocate_order(character varying, character varying); Type: FUNCTION; Schema: core; Owner: -
--

CREATE FUNCTION core.deallocate_order(p_client_id character varying, p_order_id character varying) RETURNS TABLE(result_status character varying, result_order_id character varying, result_allocations integer, result_qty_released numeric, result_message text)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_alloc RECORD;
    v_open_qty NUMERIC(15,6);
    v_count INTEGER := 0;
    v_qty_released NUMERIC(15,6) := 0;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM core.ORDER_HEADER WHERE CLIENT_ID=p_client_id AND ORDER_ID=p_order_id) THEN
        RETURN QUERY SELECT 'ERROR'::VARCHAR, p_order_id::VARCHAR, 0, 0::NUMERIC, 'Order does not exist.'::TEXT;
        RETURN;
    END IF;

    FOR v_alloc IN
        SELECT a.*
        FROM core.ALLOCATION a
        WHERE a.CLIENT_ID=p_client_id AND a.ORDER_ID=p_order_id
          AND (a.QTY_ALLOCATED - a.QTY_PICKED - a.QTY_RELEASED) > 0
        ORDER BY a.ALLOCATION_ID
        FOR UPDATE
    LOOP
        v_open_qty := v_alloc.QTY_ALLOCATED - v_alloc.QTY_PICKED - v_alloc.QTY_RELEASED;

        UPDATE core.INVENTORY
        SET QTY_ALLOCATED = GREATEST(0, QTY_ALLOCATED - v_open_qty)
        WHERE KEY = v_alloc.INVENTORY_KEY;

        UPDATE core.ALLOCATION
        SET QTY_RELEASED = QTY_RELEASED + v_open_qty,
            STATUS = CASE WHEN QTY_PICKED > 0 THEN 'PART_PICKED_RELEASED' ELSE 'RELEASED' END,
            LAST_UPDATE_DSTAMP = now(), LAST_UPDATED_BY = 'DEALLOCATE_ORDER'
        WHERE ALLOCATION_ID = v_alloc.ALLOCATION_ID;

        UPDATE core.PICK_TASK
        SET SHORT_QTY = LEAST(QTY_REQUIRED - QTY_PICKED, SHORT_QTY + v_open_qty),
            STATUS = CASE WHEN QTY_PICKED > 0 THEN 'SHORT' ELSE 'CANCELLED' END,
            SHORT_REASON = COALESCE(SHORT_REASON, 'Allocation released'),
            COMPLETED_DSTAMP = now(), LAST_UPDATE_DSTAMP = now(), LAST_UPDATED_BY='DEALLOCATE_ORDER'
        WHERE ALLOCATION_ID = v_alloc.ALLOCATION_ID
          AND STATUS IN ('OPEN','PART_PICKED');

        v_count := v_count + 1;
        v_qty_released := v_qty_released + v_open_qty;
    END LOOP;

    UPDATE core.ORDER_LINE ol
    SET QTY_SOFT_ALLOCATED = COALESCE((
            SELECT SUM(GREATEST(0, a.QTY_ALLOCATED-a.QTY_PICKED-a.QTY_RELEASED))
            FROM core.ALLOCATION a
            WHERE a.CLIENT_ID=ol.CLIENT_ID AND a.ORDER_ID=ol.ORDER_ID AND a.LINE_ID=ol.LINE_ID
        ),0),
        BACK_ORDERED = CASE WHEN COALESCE(ol.QTY_PICKED,0) >= ol.QTY_ORDERED THEN 'N' ELSE 'Y' END,
        LAST_UPDATED_BY='DEALLOCATE_ORDER', LAST_UPDATE_DATE=now()
    WHERE ol.CLIENT_ID=p_client_id AND ol.ORDER_ID=p_order_id;

    UPDATE core.ORDER_HEADER
    SET FULFILMENT_STATUS = CASE
            WHEN EXISTS (SELECT 1 FROM core.ORDER_LINE WHERE CLIENT_ID=p_client_id AND ORDER_ID=p_order_id AND COALESCE(QTY_PICKED,0)>0)
                THEN 'PART_PICKED'
            ELSE 'UNALLOCATED' END,
        LAST_UPDATED_BY='DEALLOCATE_ORDER', LAST_UPDATE_DATE=now()
    WHERE CLIENT_ID=p_client_id AND ORDER_ID=p_order_id;

    RETURN QUERY SELECT
        CASE WHEN v_count=0 THEN 'NOT_ALLOCATED' ELSE 'DEALLOCATED' END::VARCHAR,
        p_order_id::VARCHAR, v_count, v_qty_released::NUMERIC,
        CASE WHEN v_count=0 THEN 'Order had no open reservations to release.'
             ELSE format('Released %s open allocation(s), totalling %s unit(s). Allocation history retained.',v_count,v_qty_released)
        END::TEXT;
END;
$$;


--
-- Name: evaluate_container_merge(character varying, character varying, character varying); Type: FUNCTION; Schema: core; Owner: -
--

CREATE FUNCTION core.evaluate_container_merge(p_client_id character varying, p_left_container_id character varying, p_right_container_id character varying) RETURNS TABLE(result_status character varying, result_allowed boolean, result_rule_id bigint, result_rule_name character varying, result_reason text)
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    l RECORD;
    r RECORD;
    mr RECORD;
    v_same_order BOOLEAN;
    v_same_customer BOOLEAN;
    v_same_postcode BOOLEAN;
    v_same_country BOOLEAN;
    v_same_class BOOLEAN;
    v_same_method BOOLEAN;
    v_any_held BOOLEAN;
    v_both_held BOOLEAN;
    v_combined_weight NUMERIC;
    v_combined_volume NUMERIC;
BEGIN
    IF p_left_container_id=p_right_container_id THEN
        RETURN QUERY
        SELECT 'REJECTED'::VARCHAR,FALSE,NULL::BIGINT,NULL::VARCHAR,
               'A container cannot be merged into itself.'::TEXT;
        RETURN;
    END IF;

    SELECT
        oc.*,
        hdr.CUSTOMER_ID,
        hdr.POSTCODE,
        hdr.COUNTRY,
        hdr.FULFILMENT_PREFERENCE
    INTO l
    FROM core.ORDER_CONTAINER oc
    JOIN core.ORDER_HEADER hdr
      ON hdr.CLIENT_ID=oc.CLIENT_ID
     AND hdr.ORDER_ID=oc.ORDER_ID
    WHERE oc.CLIENT_ID=p_client_id
      AND oc.CONTAINER_ID=p_left_container_id;

    IF NOT FOUND THEN
        RETURN QUERY
        SELECT 'ERROR'::VARCHAR,FALSE,NULL::BIGINT,NULL::VARCHAR,
               'Left container does not exist.'::TEXT;
        RETURN;
    END IF;

    SELECT
        oc.*,
        hdr.CUSTOMER_ID,
        hdr.POSTCODE,
        hdr.COUNTRY,
        hdr.FULFILMENT_PREFERENCE
    INTO r
    FROM core.ORDER_CONTAINER oc
    JOIN core.ORDER_HEADER hdr
      ON hdr.CLIENT_ID=oc.CLIENT_ID
     AND hdr.ORDER_ID=oc.ORDER_ID
    WHERE oc.CLIENT_ID=p_client_id
      AND oc.CONTAINER_ID=p_right_container_id;

    IF NOT FOUND THEN
        RETURN QUERY
        SELECT 'ERROR'::VARCHAR,FALSE,NULL::BIGINT,NULL::VARCHAR,
               'Right container does not exist.'::TEXT;
        RETURN;
    END IF;

    -- V1 deliberately supports same-order consolidation only.
    IF l.ORDER_ID<>r.ORDER_ID THEN
        RETURN QUERY
        SELECT 'REJECTED'::VARCHAR,FALSE,NULL::BIGINT,NULL::VARCHAR,
               'Merge V1 only consolidates containers belonging to the same order.'::TEXT;
        RETURN;
    END IF;

    IF UPPER(COALESCE(l.STATUS,'')) IN ('SHIPPED','MERGED','CANCELLED')
       OR UPPER(COALESCE(r.STATUS,'')) IN ('SHIPPED','MERGED','CANCELLED')
    THEN
        RETURN QUERY
        SELECT 'REJECTED'::VARCHAR,FALSE,NULL::BIGINT,NULL::VARCHAR,
               'Shipped, merged or cancelled containers cannot be merged.'::TEXT;
        RETURN;
    END IF;

    IF EXISTS (
        SELECT 1
        FROM core.SHIPPING_MANIFEST sm
        WHERE sm.CLIENT_ID=p_client_id
          AND sm.CONTAINER_ID IN (p_left_container_id,p_right_container_id)
          AND COALESCE(sm.QTY_SHIPPED,0)>0
    ) THEN
        RETURN QUERY
        SELECT 'REJECTED'::VARCHAR,FALSE,NULL::BIGINT,NULL::VARCHAR,
               'A container with shipped quantity cannot be merged.'::TEXT;
        RETURN;
    END IF;

    v_same_order := l.ORDER_ID=r.ORDER_ID;
    v_same_customer := COALESCE(l.CUSTOMER_ID,'')=COALESCE(r.CUSTOMER_ID,'');
    v_same_postcode := COALESCE(UPPER(l.POSTCODE),'')=COALESCE(UPPER(r.POSTCODE),'');
    v_same_country := COALESCE(UPPER(l.COUNTRY),'')=COALESCE(UPPER(r.COUNTRY),'');
    v_same_class := UPPER(COALESCE(l.DELIVERY_CLASS,'STANDARD'))=
                    UPPER(COALESCE(r.DELIVERY_CLASS,'STANDARD'));
    v_same_method := UPPER(COALESCE(l.FULFILMENT_METHOD,'CARRIER'))=
                     UPPER(COALESCE(r.FULFILMENT_METHOD,'CARRIER'));
    v_any_held := COALESCE(l.HOLD_STATUS,'NONE')<>'NONE'
                  OR COALESCE(r.HOLD_STATUS,'NONE')<>'NONE';
    v_both_held := COALESCE(l.HOLD_STATUS,'NONE')<>'NONE'
                   AND COALESCE(r.HOLD_STATUS,'NONE')<>'NONE';
    v_combined_weight := COALESCE(l.WEIGHT,0)+COALESCE(r.WEIGHT,0);
    v_combined_volume := COALESCE(l.VOLUME,0)+COALESCE(r.VOLUME,0);

    IF NOT v_same_method THEN
        RETURN QUERY
        SELECT 'REJECTED'::VARCHAR,FALSE,NULL::BIGINT,NULL::VARCHAR,
               'Containers use different fulfilment methods.'::TEXT;
        RETURN;
    END IF;

    IF COALESCE(l.HOLD_STATUS,'NONE')<>COALESCE(r.HOLD_STATUS,'NONE') THEN
        RETURN QUERY
        SELECT 'REJECTED'::VARCHAR,FALSE,NULL::BIGINT,NULL::VARCHAR,
               'Held and releasable containers are not merged automatically.'::TEXT;
        RETURN;
    END IF;

    IF COALESCE(l.CARRIER_ID,'')<>'' AND COALESCE(r.CARRIER_ID,'')<>''
       AND l.CARRIER_ID<>r.CARRIER_ID
    THEN
        RETURN QUERY
        SELECT 'REJECTED'::VARCHAR,FALSE,NULL::BIGINT,NULL::VARCHAR,
               'Containers already have different carriers selected.'::TEXT;
        RETURN;
    END IF;

    IF COALESCE(l.SERVICE_LEVEL,'')<>'' AND COALESCE(r.SERVICE_LEVEL,'')<>''
       AND l.SERVICE_LEVEL<>r.SERVICE_LEVEL
    THEN
        RETURN QUERY
        SELECT 'REJECTED'::VARCHAR,FALSE,NULL::BIGINT,NULL::VARCHAR,
               'Containers already have different carrier service levels.'::TEXT;
        RETURN;
    END IF;

    FOR mr IN
        SELECT m.*
        FROM config.MERGE_RULE m
        WHERE m.CLIENT_ID=p_client_id
          AND m.ACTIVE=TRUE
        ORDER BY m.PRIORITY,m.RULE_ID
    LOOP
        IF config.MERGE_CONDITION_MATCH(
            mr.RULE_ID,
            v_same_order,
            v_same_customer,
            v_same_postcode,
            v_same_country,
            v_same_class,
            UPPER(COALESCE(l.DELIVERY_CLASS,'STANDARD')),
            UPPER(COALESCE(r.DELIVERY_CLASS,'STANDARD')),
            v_same_method,
            UPPER(COALESCE(l.FULFILMENT_METHOD,'CARRIER')),
            v_combined_weight,
            v_combined_volume,
            v_any_held,
            v_both_held,
            l.FULFILMENT_PREFERENCE
        ) THEN
            RETURN QUERY
            SELECT
                CASE WHEN mr.DECISION='ALLOW'
                     THEN 'ALLOWED' ELSE 'REJECTED' END::VARCHAR,
                (mr.DECISION='ALLOW'),
                mr.RULE_ID,
                mr.RULE_NAME,
                format('Matched merge rule %s (%s).',
                       mr.RULE_NAME,mr.DECISION)::TEXT;
            RETURN;
        END IF;
    END LOOP;

    IF v_same_class THEN
        RETURN QUERY
        SELECT 'ALLOWED'::VARCHAR,TRUE,NULL::BIGINT,NULL::VARCHAR,
               'Compatible same-order containers with the same delivery class.'::TEXT;
    ELSE
        RETURN QUERY
        SELECT 'REJECTED'::VARCHAR,FALSE,NULL::BIGINT,NULL::VARCHAR,
               'Different delivery classes require an explicit ALLOW merge rule.'::TEXT;
    END IF;
END;
$$;


--
-- Name: evaluate_delivery_hold(character varying, character varying, character varying); Type: FUNCTION; Schema: core; Owner: -
--

CREATE FUNCTION core.evaluate_delivery_hold(p_client_id character varying, p_container_id character varying, p_user_id character varying DEFAULT 'SYSTEM'::character varying) RETURNS TABLE(result_status character varying, result_hold_status character varying, result_message text)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_container RECORD;
    v_enabled BOOLEAN := TRUE;
    v_config_reason VARCHAR(250);
    v_delivery_class VARCHAR(30);
    v_user VARCHAR(20) := LEFT(COALESCE(NULLIF(p_user_id,''),'SYSTEM'),20);
BEGIN
    SELECT *
    INTO v_container
    FROM core.ORDER_CONTAINER
    WHERE CLIENT_ID = p_client_id
      AND CONTAINER_ID = p_container_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN QUERY
        SELECT 'ERROR'::VARCHAR, NULL::VARCHAR,
               'Container does not exist.'::TEXT;
        RETURN;
    END IF;

    v_delivery_class := UPPER(COALESCE(v_container.DELIVERY_CLASS,'STANDARD'));

    -- Only carrier fulfilment is controlled here.
    -- Local delivery / collection / route delivery can still proceed.
    IF UPPER(COALESCE(v_container.FULFILMENT_METHOD,'CARRIER')) <> 'CARRIER' THEN
        UPDATE core.ORDER_CONTAINER
        SET HOLD_STATUS='NONE',
            HOLD_REASON=NULL,
            HOLD_DSTAMP=NULL,
            HOLD_SOURCE=NULL
        WHERE CLIENT_ID=p_client_id
          AND CONTAINER_ID=p_container_id
          AND HOLD_SOURCE='DELIVERY_CLASS_CONTROL';

        RETURN QUERY
        SELECT 'ALLOWED'::VARCHAR, 'NONE'::VARCHAR,
               'Container is not using carrier fulfilment.'::TEXT;
        RETURN;
    END IF;

    SELECT
        d.CARRIER_DESPATCH_ENABLED,
        d.HOLD_REASON
    INTO
        v_enabled,
        v_config_reason
    FROM config.DELIVERY_CLASS_CONTROL d
    WHERE d.CLIENT_ID = p_client_id
      AND UPPER(d.DELIVERY_CLASS) = v_delivery_class;

    -- No row means no restriction for that class.
    IF NOT FOUND THEN
        v_enabled := TRUE;
        v_config_reason := NULL;
    END IF;

    IF NOT COALESCE(v_enabled,TRUE) THEN
        UPDATE core.ORDER_CONTAINER
        SET HOLD_STATUS='DELIVERY_HOLD',
            HOLD_REASON=COALESCE(
                NULLIF(v_config_reason,''),
                v_delivery_class || ' carrier despatch is currently disabled.'
            ),
            HOLD_DSTAMP=now(),
            HOLD_SOURCE='DELIVERY_CLASS_CONTROL',
            RELEASE_DSTAMP=NULL,
            RELEASED_BY=NULL
        WHERE CLIENT_ID=p_client_id
          AND CONTAINER_ID=p_container_id;

        INSERT INTO audit.RULE_DECISION_LOG (
            CLIENT_ID,
            ENGINE_NAME,
            ENTITY_TYPE,
            ENTITY_ID,
            MATCHED,
            DECISION,
            REASON,
            DETAIL
        )
        VALUES (
            p_client_id,
            'DELIVERY_HOLD',
            'ORDER_CONTAINER',
            p_container_id,
            TRUE,
            'HELD',
            COALESCE(
                NULLIF(v_config_reason,''),
                v_delivery_class || ' carrier despatch is currently disabled.'
            ),
            jsonb_build_object(
                'delivery_class', v_delivery_class,
                'fulfilment_method', 'CARRIER',
                'control_source', 'DELIVERY_CLASS_CONTROL',
                'user_id', v_user
            )
        );

        RETURN QUERY
        SELECT
            'HELD'::VARCHAR,
            'DELIVERY_HOLD'::VARCHAR,
            COALESCE(
                NULLIF(v_config_reason,''),
                v_delivery_class || ' carrier despatch is currently disabled.'
            )::TEXT;
        RETURN;
    END IF;

    -- Never remove a manual/weather/other hold here.
    IF v_container.HOLD_STATUS <> 'NONE'
       AND COALESCE(v_container.HOLD_SOURCE,'') <> 'DELIVERY_CLASS_CONTROL'
    THEN
        RETURN QUERY
        SELECT
            'HELD'::VARCHAR,
            v_container.HOLD_STATUS::VARCHAR,
            COALESCE(v_container.HOLD_REASON,'Container is held.')::TEXT;
        RETURN;
    END IF;

    UPDATE core.ORDER_CONTAINER
    SET HOLD_STATUS='NONE',
        HOLD_REASON=NULL,
        HOLD_DSTAMP=NULL,
        HOLD_SOURCE=NULL
    WHERE CLIENT_ID=p_client_id
      AND CONTAINER_ID=p_container_id
      AND (
          HOLD_SOURCE='DELIVERY_CLASS_CONTROL'
          OR HOLD_STATUS='NONE'
      );

    RETURN QUERY
    SELECT
        'ALLOWED'::VARCHAR,
        'NONE'::VARCHAR,
        'Carrier despatch is enabled for this delivery class.'::TEXT;
END;
$$;


--
-- Name: merge_containers(character varying, character varying, character varying, character varying); Type: FUNCTION; Schema: core; Owner: -
--

CREATE FUNCTION core.merge_containers(p_client_id character varying, p_target_container_id character varying, p_source_container_id character varying, p_user_id character varying DEFAULT 'SYSTEM'::character varying) RETURNS TABLE(result_status character varying, result_target_container_id character varying, result_source_container_id character varying, result_message text)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_eval RECORD;
    v_target RECORD;
    v_source RECORD;
    v_user VARCHAR(20) := LEFT(COALESCE(NULLIF(p_user_id,''),'SYSTEM'),20);
BEGIN
    -- Lock in deterministic order to reduce deadlock risk.
    PERFORM 1
    FROM core.ORDER_CONTAINER
    WHERE CLIENT_ID=p_client_id
      AND CONTAINER_ID IN (p_target_container_id,p_source_container_id)
    ORDER BY CONTAINER_ID
    FOR UPDATE;

    SELECT *
    INTO v_eval
    FROM core.EVALUATE_CONTAINER_MERGE(
        p_client_id,p_target_container_id,p_source_container_id
    );

    IF NOT COALESCE(v_eval.RESULT_ALLOWED,FALSE) THEN
        INSERT INTO audit.RULE_DECISION_LOG (
            CLIENT_ID,ENGINE_NAME,ENTITY_TYPE,ENTITY_ID,
            RULE_ID,RULE_NAME,MATCHED,DECISION,REASON,DETAIL
        )
        VALUES (
            p_client_id,
            'CONTAINER_MERGE',
            'ORDER_CONTAINER',
            p_source_container_id,
            v_eval.RESULT_RULE_ID,
            v_eval.RESULT_RULE_NAME,
            v_eval.RESULT_RULE_ID IS NOT NULL,
            'REJECTED',
            v_eval.RESULT_REASON,
            jsonb_build_object(
                'target_container_id',p_target_container_id,
                'source_container_id',p_source_container_id,
                'user_id',v_user
            )
        );

        RETURN QUERY
        SELECT
            'REJECTED'::VARCHAR,
            p_target_container_id::VARCHAR,
            p_source_container_id::VARCHAR,
            v_eval.RESULT_REASON::TEXT;
        RETURN;
    END IF;

    SELECT *
    INTO v_target
    FROM core.ORDER_CONTAINER
    WHERE CLIENT_ID=p_client_id
      AND CONTAINER_ID=p_target_container_id;

    SELECT *
    INTO v_source
    FROM core.ORDER_CONTAINER
    WHERE CLIENT_ID=p_client_id
      AND CONTAINER_ID=p_source_container_id;

    -- Move packed contents to the surviving physical/logical container.
    UPDATE core.SHIPPING_MANIFEST
    SET CONTAINER_ID=p_target_container_id,
        CARRIER_ID=NULL,
        SERVICE_LEVEL=NULL,
        CARRIER_SELECTION_RULE_ID=NULL
    WHERE CLIENT_ID=p_client_id
      AND CONTAINER_ID=p_source_container_id
      AND COALESCE(QTY_SHIPPED,0)=0;

    -- Weight/volume are additive. Physical dimensions are deliberately not
    -- mathematically combined because the surviving package determines them.
    UPDATE core.ORDER_CONTAINER
    SET WEIGHT=COALESCE(v_target.WEIGHT,0)+COALESCE(v_source.WEIGHT,0),
        VOLUME=COALESCE(v_target.VOLUME,0)+COALESCE(v_source.VOLUME,0),
        CARRIER_ID=NULL,
        SERVICE_LEVEL=NULL,
        CARRIER_COST=NULL,
        CARRIER_SELECTION_SOURCE=NULL,
        CARRIER_SELECTION_RULE_ID=NULL,
        CARRIER_SELECTED_DSTAMP=NULL,
        CARRIER_OVERRIDE_REASON=NULL,
        MERGE_RULE_ID=v_eval.RESULT_RULE_ID
    WHERE CLIENT_ID=p_client_id
      AND CONTAINER_ID=p_target_container_id;

    UPDATE core.ORDER_CONTAINER
    SET STATUS='MERGED',
        MERGED_INTO_CONTAINER_ID=p_target_container_id,
        MERGED_DSTAMP=now(),
        MERGED_BY=v_user,
        MERGE_RULE_ID=v_eval.RESULT_RULE_ID
    WHERE CLIENT_ID=p_client_id
      AND CONTAINER_ID=p_source_container_id;

    INSERT INTO audit.RULE_DECISION_LOG (
        CLIENT_ID,ENGINE_NAME,ENTITY_TYPE,ENTITY_ID,
        RULE_ID,RULE_NAME,MATCHED,DECISION,REASON,DETAIL
    )
    VALUES (
        p_client_id,
        'CONTAINER_MERGE',
        'ORDER_CONTAINER',
        p_source_container_id,
        v_eval.RESULT_RULE_ID,
        v_eval.RESULT_RULE_NAME,
        v_eval.RESULT_RULE_ID IS NOT NULL,
        'MERGED',
        v_eval.RESULT_REASON,
        jsonb_build_object(
            'target_container_id',p_target_container_id,
            'source_container_id',p_source_container_id,
            'combined_weight',COALESCE(v_target.WEIGHT,0)+COALESCE(v_source.WEIGHT,0),
            'combined_volume',COALESCE(v_target.VOLUME,0)+COALESCE(v_source.VOLUME,0),
            'carrier_selection_reset',TRUE,
            'user_id',v_user
        )
    );

    RETURN QUERY
    SELECT
        'MERGED'::VARCHAR,
        p_target_container_id::VARCHAR,
        p_source_container_id::VARCHAR,
        'Containers merged. Carrier selection must be run again for the surviving container.'::TEXT;
END;
$$;


--
-- Name: override_carrier(character varying, character varying, character varying, character varying, character varying, character varying); Type: FUNCTION; Schema: core; Owner: -
--

CREATE FUNCTION core.override_carrier(p_client_id character varying, p_container_id character varying, p_carrier_id character varying, p_service_level character varying, p_reason character varying, p_user_id character varying DEFAULT 'SYSTEM'::character varying) RETURNS TABLE(result_status character varying, result_carrier_id character varying, result_service_level character varying, result_message text)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_container RECORD;
    v_user VARCHAR(20) := LEFT(COALESCE(NULLIF(p_user_id,''),'SYSTEM'),20);
BEGIN
    IF p_reason IS NULL OR btrim(p_reason)='' THEN
        RETURN QUERY SELECT 'ERROR'::VARCHAR,NULL::VARCHAR,NULL::VARCHAR,
            'A manual carrier override requires a reason.'::TEXT;
        RETURN;
    END IF;

    SELECT * INTO v_container
    FROM core.ORDER_CONTAINER
    WHERE CLIENT_ID=p_client_id AND CONTAINER_ID=p_container_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN QUERY SELECT 'ERROR'::VARCHAR,NULL::VARCHAR,NULL::VARCHAR,'Container does not exist.'::TEXT;
        RETURN;
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM config.CARRIER_SERVICE cs
        JOIN config.CARRIER c ON c.CLIENT_ID=cs.CLIENT_ID AND c.CARRIER_ID=cs.CARRIER_ID
        WHERE cs.CLIENT_ID=p_client_id
          AND cs.CARRIER_ID=p_carrier_id
          AND cs.SERVICE_LEVEL=p_service_level
          AND cs.ACTIVE=TRUE
          AND c.ACTIVE=TRUE
    ) THEN
        RETURN QUERY SELECT 'ERROR'::VARCHAR,NULL::VARCHAR,NULL::VARCHAR,
            'Requested carrier/service is not active.'::TEXT;
        RETURN;
    END IF;

    UPDATE core.ORDER_CONTAINER
    SET CARRIER_ID=p_carrier_id,
        SERVICE_LEVEL=p_service_level,
        CARRIER_SELECTION_SOURCE='MANUAL_OVERRIDE',
        CARRIER_SELECTION_RULE_ID=NULL,
        CARRIER_SELECTED_DSTAMP=now(),
        CARRIER_OVERRIDE_REASON=LEFT(p_reason,250)
    WHERE CLIENT_ID=p_client_id AND CONTAINER_ID=p_container_id;

    UPDATE core.SHIPPING_MANIFEST
    SET CARRIER_ID=p_carrier_id,
        SERVICE_LEVEL=p_service_level,
        CARRIER_SELECTION_RULE_ID=NULL
    WHERE CLIENT_ID=p_client_id AND CONTAINER_ID=p_container_id
      AND COALESCE(SHIPPED,'N')='N';

    INSERT INTO audit.RULE_DECISION_LOG
        (CLIENT_ID,ENGINE_NAME,ENTITY_TYPE,ENTITY_ID,MATCHED,DECISION,REASON,DETAIL)
    VALUES
        (p_client_id,'CARRIER_SELECTION','ORDER_CONTAINER',p_container_id,TRUE,'OVERRIDDEN',
         p_reason,
         jsonb_build_object('carrier_id',p_carrier_id,'service_level',p_service_level,'user_id',v_user));

    RETURN QUERY SELECT 'OVERRIDDEN'::VARCHAR,p_carrier_id::VARCHAR,p_service_level::VARCHAR,
        format('Container %s manually assigned to %s / %s.',p_container_id,p_carrier_id,p_service_level)::TEXT;
END;
$$;


--
-- Name: pack_order(character varying, character varying, character varying, character varying, character varying); Type: FUNCTION; Schema: core; Owner: -
--

CREATE FUNCTION core.pack_order(p_client_id character varying, p_order_id character varying, p_container_id character varying, p_user_id character varying DEFAULT 'SYSTEM'::character varying, p_station_id character varying DEFAULT 'WMS'::character varying) RETURNS TABLE(result_status character varying, result_container_id character varying, result_rows_packed integer, result_qty_packed numeric, result_message text)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_task RECORD;
    v_qty NUMERIC(15,6);
    v_rows INTEGER := 0;
    v_total NUMERIC(15,6) := 0;
    v_user VARCHAR(20) := LEFT(COALESCE(NULLIF(p_user_id,''),'SYSTEM'),20);
    v_station VARCHAR(256) := LEFT(COALESCE(NULLIF(p_station_id,''),'WMS'),256);
BEGIN
    IF p_container_id IS NULL OR btrim(p_container_id)='' THEN
        RETURN QUERY SELECT 'ERROR'::VARCHAR,p_container_id::VARCHAR,0,0::NUMERIC,'Container ID is required.'::TEXT;
        RETURN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM core.ORDER_HEADER WHERE CLIENT_ID=p_client_id AND ORDER_ID=p_order_id) THEN
        RETURN QUERY SELECT 'ERROR'::VARCHAR,p_container_id::VARCHAR,0,0::NUMERIC,'Order does not exist.'::TEXT;
        RETURN;
    END IF;
    IF EXISTS (SELECT 1 FROM core.ORDER_CONTAINER WHERE CLIENT_ID=p_client_id AND CONTAINER_ID=p_container_id AND ORDER_ID<>p_order_id) THEN
        RETURN QUERY SELECT 'ERROR'::VARCHAR,p_container_id::VARCHAR,0,0::NUMERIC,'Container belongs to another order.'::TEXT;
        RETURN;
    END IF;

    INSERT INTO core.ORDER_CONTAINER (CLIENT_ID,ORDER_ID,CONTAINER_ID,STATUS)
    VALUES (p_client_id,p_order_id,p_container_id,'OPEN')
    ON CONFLICT (CLIENT_ID,CONTAINER_ID) DO NOTHING;

    FOR v_task IN
        SELECT pt.*, i.SITE_ID,i.OWNER_ID,i.TAG_ID,i.CONTAINER_ID AS INVENTORY_CONTAINER_ID,
               i.CONDITION_ID,i.LOCK_STATUS,i.LOCK_CODE,i.ORIGIN_ID,i.SUPPLIER_ID,
               COALESCE((SELECT SUM(sm.QTY_PICKED) FROM core.SHIPPING_MANIFEST sm WHERE sm.PICK_TASK_ID=pt.PICK_TASK_ID),0) AS ALREADY_PACKED
        FROM core.PICK_TASK pt
        JOIN core.INVENTORY i ON i.KEY=pt.INVENTORY_KEY
        WHERE pt.CLIENT_ID=p_client_id AND pt.ORDER_ID=p_order_id AND pt.QTY_PICKED>0
        ORDER BY pt.LINE_ID,pt.PICK_TASK_ID
        FOR UPDATE OF pt
    LOOP
        v_qty := v_task.QTY_PICKED-v_task.ALREADY_PACKED;
        CONTINUE WHEN v_qty<=0;

        INSERT INTO core.SHIPPING_MANIFEST (
            CLIENT_ID,ORDER_ID,LINE_ID,SKU_ID,BATCH_ID,CONTAINER_ID,SITE_ID,LOCATION_ID,OWNER_ID,
            QTY_PICKED,PICKED_DSTAMP,QTY_SHIPPED,SHIPPED,STATION_ID,USER_ID,SUPPLIER_ID,ORIGIN_ID,
            CONDITION_ID,LOCK_STATUS,LOCK_CODE,STATUS,PICK_TASK_ID
        ) VALUES (
            p_client_id,p_order_id,v_task.LINE_ID,v_task.SKU_ID,v_task.BATCH_ID,p_container_id,
            v_task.SITE_ID,v_task.LOCATION_ID,v_task.OWNER_ID,v_qty,now(),0,'N',v_station,v_user,
            v_task.SUPPLIER_ID,v_task.ORIGIN_ID,v_task.CONDITION_ID,v_task.LOCK_STATUS,v_task.LOCK_CODE,
            'PACKED',v_task.PICK_TASK_ID
        );
        v_rows:=v_rows+1; v_total:=v_total+v_qty;
    END LOOP;

    IF v_rows=0 THEN
        RETURN QUERY SELECT 'NOTHING_TO_PACK'::VARCHAR,p_container_id::VARCHAR,0,0::NUMERIC,'No picked quantity remains unpacked.'::TEXT;
        RETURN;
    END IF;

    UPDATE core.ORDER_CONTAINER SET STATUS='PACKED',CLOSED_DSTAMP=now()
    WHERE CLIENT_ID=p_client_id AND CONTAINER_ID=p_container_id;

    UPDATE core.ORDER_HEADER oh
    SET FULFILMENT_STATUS=CASE
            WHEN NOT EXISTS (
                SELECT 1 FROM core.ORDER_LINE ol
                WHERE ol.CLIENT_ID=p_client_id AND ol.ORDER_ID=p_order_id
                  AND COALESCE((SELECT SUM(sm.QTY_PICKED) FROM core.SHIPPING_MANIFEST sm
                                WHERE sm.CLIENT_ID=ol.CLIENT_ID AND sm.ORDER_ID=ol.ORDER_ID AND sm.LINE_ID=ol.LINE_ID),0) < ol.QTY_ORDERED
            ) THEN 'READY_TO_SHIP'
            ELSE 'PART_PACKED' END,
        LAST_UPDATED_BY=v_user,LAST_UPDATE_DATE=now()
    WHERE oh.CLIENT_ID=p_client_id AND oh.ORDER_ID=p_order_id;

    RETURN QUERY SELECT 'PACKED'::VARCHAR,p_container_id::VARCHAR,v_rows,v_total::NUMERIC,
        format('Packed %s manifest row(s), totalling %s unit(s), into container %s.',v_rows,v_total,p_container_id)::TEXT;
END;
$$;


--
-- Name: release_delivery_hold(character varying, character varying, character varying, character varying); Type: FUNCTION; Schema: core; Owner: -
--

CREATE FUNCTION core.release_delivery_hold(p_client_id character varying, p_container_id character varying, p_reason character varying, p_user_id character varying DEFAULT 'SYSTEM'::character varying) RETURNS TABLE(result_status character varying, result_message text)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_user VARCHAR(20) := LEFT(COALESCE(NULLIF(p_user_id,''),'SYSTEM'),20);
BEGIN
    IF p_reason IS NULL OR btrim(p_reason)='' THEN
        RETURN QUERY SELECT 'ERROR'::VARCHAR,'A release/override requires a reason.'::TEXT;
        RETURN;
    END IF;

    UPDATE core.ORDER_CONTAINER
    SET HOLD_STATUS='NONE',
        HOLD_REASON=NULL,
        HOLD_DSTAMP=NULL,
        HOLD_SOURCE='MANUAL_OVERRIDE',
        RELEASE_DSTAMP=now(),
        RELEASED_BY=v_user
    WHERE CLIENT_ID=p_client_id AND CONTAINER_ID=p_container_id;

    IF NOT FOUND THEN
        RETURN QUERY SELECT 'ERROR'::VARCHAR,'Container does not exist.'::TEXT;
        RETURN;
    END IF;

    INSERT INTO audit.RULE_DECISION_LOG
        (CLIENT_ID,ENGINE_NAME,ENTITY_TYPE,ENTITY_ID,MATCHED,DECISION,REASON,DETAIL)
    VALUES
        (p_client_id,'DELIVERY_HOLD','ORDER_CONTAINER',p_container_id,TRUE,'RELEASED',
         p_reason,jsonb_build_object('user_id',v_user));

    RETURN QUERY SELECT 'RELEASED'::VARCHAR,'Delivery hold released.'::TEXT;
END;
$$;


--
-- Name: select_carrier(character varying, character varying, character varying, character varying, character varying); Type: FUNCTION; Schema: core; Owner: -
--

CREATE FUNCTION core.select_carrier(p_client_id character varying, p_container_id character varying, p_delivery_class character varying DEFAULT NULL::character varying, p_strategy character varying DEFAULT 'CHEAPEST'::character varying, p_user_id character varying DEFAULT 'SYSTEM'::character varying) RETURNS TABLE(result_status character varying, result_carrier_id character varying, result_service_level character varying, result_cost numeric, result_rule_id bigint, result_message text)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_container RECORD;
    v_order RECORD;
    v_weight NUMERIC(14,3);
    v_volume NUMERIC(18,3);
    v_height NUMERIC(14,3);
    v_width NUMERIC(14,3);
    v_depth NUMERIC(14,3);
    v_delivery_class VARCHAR(30);
    v_strategy VARCHAR(20);
    v_active_rule_count INTEGER;
    v_candidate RECORD;
    v_rule RECORD;
    v_rule_matched BOOLEAN;
    v_best_carrier VARCHAR(30);
    v_best_service VARCHAR(50);
    v_best_cost NUMERIC(12,2);
    v_best_rule BIGINT;
    v_best_priority INTEGER;
    v_cost NUMERIC(12,2);
    v_rate RECORD;
    v_candidate_priority INTEGER;
    v_candidate_rule BIGINT;
    v_user VARCHAR(20) := LEFT(COALESCE(NULLIF(p_user_id,''),'SYSTEM'),20);
BEGIN
    v_strategy := UPPER(COALESCE(NULLIF(p_strategy,''),'CHEAPEST'));

    IF v_strategy NOT IN ('CHEAPEST','PRIORITY') THEN
        RETURN QUERY SELECT 'ERROR'::VARCHAR,NULL::VARCHAR,NULL::VARCHAR,NULL::NUMERIC,NULL::BIGINT,
            'Unsupported strategy. Use CHEAPEST or PRIORITY.'::TEXT;
        RETURN;
    END IF;

    SELECT * INTO v_container
    FROM core.ORDER_CONTAINER
    WHERE CLIENT_ID=p_client_id AND CONTAINER_ID=p_container_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN QUERY SELECT 'ERROR'::VARCHAR,NULL::VARCHAR,NULL::VARCHAR,NULL::NUMERIC,NULL::BIGINT,
            'Container does not exist.'::TEXT;
        RETURN;
    END IF;

    SELECT * INTO v_order
    FROM core.ORDER_HEADER
    WHERE CLIENT_ID=p_client_id AND ORDER_ID=v_container.ORDER_ID;

    IF NOT FOUND THEN
        RETURN QUERY SELECT 'ERROR'::VARCHAR,NULL::VARCHAR,NULL::VARCHAR,NULL::NUMERIC,NULL::BIGINT,
            'Order does not exist.'::TEXT;
        RETURN;
    END IF;

    IF v_container.STATUS NOT IN ('PACKED','READY_TO_SHIP','OPEN') THEN
        RETURN QUERY SELECT 'ERROR'::VARCHAR,NULL::VARCHAR,NULL::VARCHAR,NULL::NUMERIC,NULL::BIGINT,
            format('Container status %s is not eligible for carrier selection.',v_container.STATUS)::TEXT;
        RETURN;
    END IF;

    -- Prefer actual container measurements. If weight/volume are not captured yet,
    -- derive practical estimates from packed SKU quantities.
    SELECT
        COALESCE(v_container.WEIGHT,
            SUM(COALESCE(s.EACH_WEIGHT,0) * COALESCE(sm.QTY_PICKED,0))),
        COALESCE(v_container.VOLUME,
            SUM(COALESCE(s.EACH_VOLUME,0) * COALESCE(sm.QTY_PICKED,0)))
    INTO v_weight, v_volume
    FROM core.SHIPPING_MANIFEST sm
    JOIN core.SKU s
      ON s.CLIENT_ID=sm.CLIENT_ID AND s.SKU_ID=sm.SKU_ID
    WHERE sm.CLIENT_ID=p_client_id
      AND sm.CONTAINER_ID=p_container_id;

    v_weight := COALESCE(v_weight,0);
    v_volume := COALESCE(v_volume,0);
    v_height := v_container.HEIGHT;
    v_width := v_container.WIDTH;
    v_depth := v_container.DEPTH;

    v_delivery_class := UPPER(COALESCE(
        NULLIF(p_delivery_class,''),
        NULLIF(v_container.DELIVERY_CLASS,''),
        'STANDARD'
    ));

    SELECT COUNT(*) INTO v_active_rule_count
    FROM config.CARRIER_SELECTION_RULE
    WHERE CLIENT_ID=p_client_id AND ACTIVE=TRUE;

    -- Clear the decision trail for a fresh run on this container.
    DELETE FROM audit.RULE_DECISION_LOG
    WHERE CLIENT_ID=p_client_id
      AND ENGINE_NAME='CARRIER_SELECTION'
      AND ENTITY_TYPE='ORDER_CONTAINER'
      AND ENTITY_ID=p_container_id;

    FOR v_candidate IN
        SELECT
            cs.CLIENT_ID,
            cs.CARRIER_ID,
            cs.SERVICE_LEVEL,
            cs.DESCRIPTION,
            cs.DISPATCH_METHOD,
            cs.MAX_WEIGHT_KG,
            cs.MAX_LENGTH_CM,
            cs.MAX_WIDTH_CM,
            cs.MAX_HEIGHT_CM,
            cs.MAX_VOLUME_CM3,
            cs.BASE_COST,
            cs.COST_PER_KG,
            cs.REQUIRES_MANUAL_APPROVAL,
            cs.LIVE_GOODS_ALLOWED,
            cs.SORT_SEQUENCE
        FROM config.CARRIER_SERVICE cs
        JOIN config.CARRIER c
          ON c.CLIENT_ID=cs.CLIENT_ID AND c.CARRIER_ID=cs.CARRIER_ID
        WHERE cs.CLIENT_ID=p_client_id
          AND cs.ACTIVE=TRUE
          AND c.ACTIVE=TRUE
        ORDER BY cs.SORT_SEQUENCE, cs.CARRIER_ID, cs.SERVICE_LEVEL
    LOOP
        -- Hard service constraints first.
        IF v_candidate.MAX_WEIGHT_KG IS NOT NULL AND v_weight > v_candidate.MAX_WEIGHT_KG THEN
            INSERT INTO audit.RULE_DECISION_LOG
                (CLIENT_ID,ENGINE_NAME,ENTITY_TYPE,ENTITY_ID,MATCHED,DECISION,REASON,DETAIL)
            VALUES
                (p_client_id,'CARRIER_SELECTION','ORDER_CONTAINER',p_container_id,FALSE,'REJECTED',
                 'Container exceeds service maximum weight.',
                 jsonb_build_object('carrier_id',v_candidate.CARRIER_ID,'service_level',v_candidate.SERVICE_LEVEL,
                                    'weight_kg',v_weight,'max_weight_kg',v_candidate.MAX_WEIGHT_KG));
            CONTINUE;
        END IF;

        IF v_candidate.MAX_VOLUME_CM3 IS NOT NULL AND v_volume > v_candidate.MAX_VOLUME_CM3 THEN
            CONTINUE;
        END IF;

        IF v_height IS NOT NULL AND v_candidate.MAX_HEIGHT_CM IS NOT NULL AND v_height > v_candidate.MAX_HEIGHT_CM THEN
            CONTINUE;
        END IF;
        IF v_width IS NOT NULL AND v_candidate.MAX_WIDTH_CM IS NOT NULL AND v_width > v_candidate.MAX_WIDTH_CM THEN
            CONTINUE;
        END IF;
        IF v_depth IS NOT NULL AND v_candidate.MAX_LENGTH_CM IS NOT NULL AND v_depth > v_candidate.MAX_LENGTH_CM THEN
            CONTINUE;
        END IF;

        IF v_delivery_class='LIVESTOCK' AND NOT v_candidate.LIVE_GOODS_ALLOWED THEN
            INSERT INTO audit.RULE_DECISION_LOG
                (CLIENT_ID,ENGINE_NAME,ENTITY_TYPE,ENTITY_ID,MATCHED,DECISION,REASON,DETAIL)
            VALUES
                (p_client_id,'CARRIER_SELECTION','ORDER_CONTAINER',p_container_id,FALSE,'REJECTED',
                 'Livestock requires a service explicitly approved for live goods.',
                 jsonb_build_object('carrier_id',v_candidate.CARRIER_ID,'service_level',v_candidate.SERVICE_LEVEL));
            CONTINUE;
        END IF;

        -- When rules exist for a client, a service must match at least one rule
        -- that targets it (or is intentionally generic).
        v_candidate_priority := 1000000;
        v_candidate_rule := NULL;
        v_rule_matched := FALSE;

        FOR v_rule IN
            SELECT *
            FROM config.CARRIER_SELECTION_RULE r
            WHERE r.CLIENT_ID=p_client_id
              AND r.ACTIVE=TRUE
              AND (r.CARRIER_ID IS NULL OR r.CARRIER_ID=v_candidate.CARRIER_ID)
              AND (r.SERVICE_LEVEL IS NULL OR r.SERVICE_LEVEL=v_candidate.SERVICE_LEVEL)
            ORDER BY r.PRIORITY,r.RULE_ID
        LOOP
            IF v_rule.MIN_WEIGHT_KG IS NOT NULL AND v_weight < v_rule.MIN_WEIGHT_KG THEN CONTINUE; END IF;
            IF v_rule.MAX_WEIGHT_KG IS NOT NULL AND v_weight > v_rule.MAX_WEIGHT_KG THEN CONTINUE; END IF;
            IF v_rule.MIN_VOLUME_CM3 IS NOT NULL AND v_volume < v_rule.MIN_VOLUME_CM3 THEN CONTINUE; END IF;
            IF v_rule.MAX_VOLUME_CM3 IS NOT NULL AND v_volume > v_rule.MAX_VOLUME_CM3 THEN CONTINUE; END IF;
            IF v_rule.MAX_ORDER_VALUE IS NOT NULL AND COALESCE(v_order.ORDER_VALUE,0) > v_rule.MAX_ORDER_VALUE THEN CONTINUE; END IF;
            IF v_rule.MIN_ORDER_VALUE IS NOT NULL AND COALESCE(v_order.ORDER_VALUE,0) < v_rule.MIN_ORDER_VALUE THEN CONTINUE; END IF;
            IF v_rule.DISPATCH_METHOD IS NOT NULL AND UPPER(COALESCE(v_order.DISPATCH_METHOD,'')) <> UPPER(v_rule.DISPATCH_METHOD) THEN CONTINUE; END IF;
            IF v_rule.DELIVERY_CLASS IS NOT NULL AND v_delivery_class <> UPPER(v_rule.DELIVERY_CLASS) THEN CONTINUE; END IF;
            IF v_rule.COUNTRY_CODE IS NOT NULL AND UPPER(LEFT(COALESCE(v_order.COUNTRY,''),3)) <> UPPER(v_rule.COUNTRY_CODE) THEN CONTINUE; END IF;

            IF NOT config.CARRIER_CONDITION_MATCH(
                v_rule.RULE_ID,
                v_weight,
                v_volume,
                v_order.ORDER_VALUE,
                v_delivery_class,
                v_order.DISPATCH_METHOD,
                v_order.SERVICE_LEVEL,
                v_order.COUNTRY,
                v_order.POSTCODE,
                v_order.FREE_DELIVERY
            ) THEN
                CONTINUE;
            END IF;

            v_rule_matched := TRUE;
            v_candidate_priority := LEAST(v_candidate_priority,v_rule.PRIORITY);
            IF v_candidate_rule IS NULL OR v_rule.PRIORITY=v_candidate_priority THEN
                v_candidate_rule := v_rule.RULE_ID;
            END IF;

            INSERT INTO audit.RULE_DECISION_LOG
                (CLIENT_ID,ENGINE_NAME,ENTITY_TYPE,ENTITY_ID,RULE_ID,RULE_NAME,MATCHED,DECISION,REASON,DETAIL)
            VALUES
                (p_client_id,'CARRIER_SELECTION','ORDER_CONTAINER',p_container_id,
                 v_rule.RULE_ID,v_rule.RULE_NAME,TRUE,'MATCHED','Carrier selection rule matched.',
                 jsonb_build_object('carrier_id',v_candidate.CARRIER_ID,'service_level',v_candidate.SERVICE_LEVEL,
                                    'priority',v_rule.PRIORITY));

            EXIT WHEN v_rule.STOP_ON_MATCH;
        END LOOP;

        IF v_active_rule_count>0 AND NOT v_rule_matched THEN
            CONTINUE;
        END IF;

        -- Best matching commercial rate band. Most specific postcode/country
        -- beats generic, then lower PRIORITY number.
        SELECT *
        INTO v_rate
        FROM config.CARRIER_SERVICE_RATE csr
        WHERE csr.CLIENT_ID=p_client_id
          AND csr.CARRIER_ID=v_candidate.CARRIER_ID
          AND csr.SERVICE_LEVEL=v_candidate.SERVICE_LEVEL
          AND csr.ACTIVE=TRUE
          AND v_weight >= csr.MIN_WEIGHT_KG
          AND (csr.MAX_WEIGHT_KG IS NULL OR v_weight <= csr.MAX_WEIGHT_KG)
          AND (csr.EFFECTIVE_FROM IS NULL OR csr.EFFECTIVE_FROM <= CURRENT_DATE)
          AND (csr.EFFECTIVE_TO IS NULL OR csr.EFFECTIVE_TO >= CURRENT_DATE)
          AND (csr.COUNTRY_CODE IS NULL OR UPPER(LEFT(COALESCE(v_order.COUNTRY,''),3))=UPPER(csr.COUNTRY_CODE))
          AND (csr.POSTCODE_PREFIX IS NULL OR UPPER(COALESCE(v_order.POSTCODE,'')) LIKE UPPER(csr.POSTCODE_PREFIX)||'%')
        ORDER BY
            CASE WHEN csr.POSTCODE_PREFIX IS NOT NULL THEN 0 ELSE 1 END,
            CASE WHEN csr.COUNTRY_CODE IS NOT NULL THEN 0 ELSE 1 END,
            csr.PRIORITY,
            csr.MIN_WEIGHT_KG DESC,
            csr.RATE_ID
        LIMIT 1;

        IF FOUND THEN
            v_cost := ROUND((v_rate.BASE_COST + (v_rate.COST_PER_KG * v_weight) + v_rate.SURCHARGE)::NUMERIC,2);
        ELSE
            v_cost := ROUND((COALESCE(v_candidate.BASE_COST,0) + (COALESCE(v_candidate.COST_PER_KG,0) * v_weight))::NUMERIC,2);
        END IF;

        INSERT INTO audit.RULE_DECISION_LOG
            (CLIENT_ID,ENGINE_NAME,ENTITY_TYPE,ENTITY_ID,RULE_ID,MATCHED,DECISION,REASON,DETAIL)
        VALUES
            (p_client_id,'CARRIER_SELECTION','ORDER_CONTAINER',p_container_id,
             v_candidate_rule,TRUE,'ELIGIBLE','Carrier service is eligible.',
             jsonb_build_object('carrier_id',v_candidate.CARRIER_ID,'service_level',v_candidate.SERVICE_LEVEL,
                                'cost',v_cost,'weight_kg',v_weight,'delivery_class',v_delivery_class,
                                'priority',v_candidate_priority));

        IF v_best_carrier IS NULL
           OR (v_strategy='CHEAPEST' AND
               (v_cost < v_best_cost OR
                (v_cost=v_best_cost AND v_candidate_priority < v_best_priority) OR
                (v_cost=v_best_cost AND v_candidate_priority=v_best_priority AND
                 (v_candidate.CARRIER_ID,v_candidate.SERVICE_LEVEL) < (v_best_carrier,v_best_service))))
           OR (v_strategy='PRIORITY' AND
               (v_candidate_priority < v_best_priority OR
                (v_candidate_priority=v_best_priority AND v_cost < v_best_cost) OR
                (v_candidate_priority=v_best_priority AND v_cost=v_best_cost AND
                 (v_candidate.CARRIER_ID,v_candidate.SERVICE_LEVEL) < (v_best_carrier,v_best_service))))
        THEN
            v_best_carrier := v_candidate.CARRIER_ID;
            v_best_service := v_candidate.SERVICE_LEVEL;
            v_best_cost := v_cost;
            v_best_rule := v_candidate_rule;
            v_best_priority := v_candidate_priority;
        END IF;
    END LOOP;

    IF v_best_carrier IS NULL THEN
        UPDATE core.ORDER_CONTAINER
        SET CARRIER_ID=NULL,
            SERVICE_LEVEL=NULL,
            CARRIER_COST=NULL,
            CARRIER_SELECTION_SOURCE='NO_MATCH',
            CARRIER_SELECTION_RULE_ID=NULL,
            CARRIER_SELECTED_DSTAMP=now(),
            DELIVERY_CLASS=v_delivery_class
        WHERE CLIENT_ID=p_client_id AND CONTAINER_ID=p_container_id;

        RETURN QUERY SELECT 'NO_ELIGIBLE_SERVICE'::VARCHAR,NULL::VARCHAR,NULL::VARCHAR,NULL::NUMERIC,NULL::BIGINT,
            'No active carrier service satisfied the container constraints and selection rules.'::TEXT;
        RETURN;
    END IF;

    UPDATE core.ORDER_CONTAINER
    SET CARRIER_ID=v_best_carrier,
        SERVICE_LEVEL=v_best_service,
        CARRIER_COST=v_best_cost,
        CARRIER_SELECTION_SOURCE=v_strategy,
        CARRIER_SELECTION_RULE_ID=v_best_rule,
        CARRIER_SELECTED_DSTAMP=now(),
        CARRIER_OVERRIDE_REASON=NULL,
        DELIVERY_CLASS=v_delivery_class
    WHERE CLIENT_ID=p_client_id AND CONTAINER_ID=p_container_id;

    UPDATE core.SHIPPING_MANIFEST
    SET CARRIER_ID=v_best_carrier,
        SERVICE_LEVEL=v_best_service,
        DISPATCH_COST=v_best_cost,
        CARRIER_SELECTION_RULE_ID=v_best_rule
    WHERE CLIENT_ID=p_client_id AND CONTAINER_ID=p_container_id
      AND COALESCE(SHIPPED,'N')='N';

    INSERT INTO audit.RULE_DECISION_LOG
        (CLIENT_ID,ENGINE_NAME,ENTITY_TYPE,ENTITY_ID,RULE_ID,MATCHED,DECISION,REASON,DETAIL)
    VALUES
        (p_client_id,'CARRIER_SELECTION','ORDER_CONTAINER',p_container_id,
         v_best_rule,TRUE,'SELECTED','Carrier service selected.',
         jsonb_build_object('carrier_id',v_best_carrier,'service_level',v_best_service,
                            'cost',v_best_cost,'strategy',v_strategy,'selected_by',v_user));

    RETURN QUERY SELECT 'SELECTED'::VARCHAR,v_best_carrier::VARCHAR,v_best_service::VARCHAR,
        v_best_cost::NUMERIC,v_best_rule,
        format('Selected %s / %s at estimated cost %s using %s strategy.',
               v_best_carrier,v_best_service,v_best_cost,v_strategy)::TEXT;
END;
$$;


--
-- Name: set_container_fulfilment(character varying, character varying, character varying, character varying); Type: FUNCTION; Schema: core; Owner: -
--

CREATE FUNCTION core.set_container_fulfilment(p_client_id character varying, p_container_id character varying, p_fulfilment_method character varying, p_user_id character varying DEFAULT 'SYSTEM'::character varying) RETURNS TABLE(result_status character varying, result_method character varying, result_message text)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_method VARCHAR(30) := UPPER(COALESCE(p_fulfilment_method,''));
BEGIN
    IF v_method NOT IN ('CARRIER','LOCAL_DELIVERY','COLLECTION','ROUTE_DELIVERY','MEET_POINT') THEN
        RETURN QUERY SELECT 'ERROR'::VARCHAR,NULL::VARCHAR,'Unsupported fulfilment method.'::TEXT;
        RETURN;
    END IF;

    UPDATE core.ORDER_CONTAINER
    SET FULFILMENT_METHOD=v_method
    WHERE CLIENT_ID=p_client_id AND CONTAINER_ID=p_container_id;

    IF NOT FOUND THEN
        RETURN QUERY SELECT 'ERROR'::VARCHAR,NULL::VARCHAR,'Container does not exist.'::TEXT;
        RETURN;
    END IF;

    -- Re-evaluate because moving livestock from CARRIER to LOCAL_DELIVERY
    -- should remove only the master carrier gate hold.
    PERFORM core.EVALUATE_DELIVERY_HOLD(p_client_id,p_container_id,p_user_id);

    RETURN QUERY SELECT 'UPDATED'::VARCHAR,v_method,
        format('Container fulfilment method set to %s.',v_method)::TEXT;
END;
$$;


--
-- Name: set_delivery_hold(character varying, character varying, character varying, character varying, character varying, character varying); Type: FUNCTION; Schema: core; Owner: -
--

CREATE FUNCTION core.set_delivery_hold(p_client_id character varying, p_container_id character varying, p_hold_status character varying, p_reason character varying, p_source character varying DEFAULT 'MANUAL'::character varying, p_user_id character varying DEFAULT 'SYSTEM'::character varying) RETURNS TABLE(result_status character varying, result_message text)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_user VARCHAR(20) := LEFT(COALESCE(NULLIF(p_user_id,''),'SYSTEM'),20);
BEGIN
    IF p_reason IS NULL OR btrim(p_reason)='' THEN
        RETURN QUERY SELECT 'ERROR'::VARCHAR,'A hold requires a reason.'::TEXT;
        RETURN;
    END IF;

    UPDATE core.ORDER_CONTAINER
    SET HOLD_STATUS=UPPER(COALESCE(NULLIF(p_hold_status,''),'DELIVERY_HOLD')),
        HOLD_REASON=LEFT(p_reason,250),
        HOLD_DSTAMP=now(),
        HOLD_SOURCE=UPPER(COALESCE(NULLIF(p_source,''),'MANUAL')),
        RELEASE_DSTAMP=NULL,
        RELEASED_BY=NULL
    WHERE CLIENT_ID=p_client_id AND CONTAINER_ID=p_container_id;

    IF NOT FOUND THEN
        RETURN QUERY SELECT 'ERROR'::VARCHAR,'Container does not exist.'::TEXT;
        RETURN;
    END IF;

    INSERT INTO audit.RULE_DECISION_LOG
        (CLIENT_ID,ENGINE_NAME,ENTITY_TYPE,ENTITY_ID,MATCHED,DECISION,REASON,DETAIL)
    VALUES
        (p_client_id,'DELIVERY_HOLD','ORDER_CONTAINER',p_container_id,TRUE,'HELD',
         p_reason,jsonb_build_object('source',p_source,'user_id',v_user));

    RETURN QUERY SELECT 'HELD'::VARCHAR,'Delivery hold applied.'::TEXT;
END;
$$;


--
-- Name: set_fulfilment_preference(character varying, character varying, character varying, character varying); Type: FUNCTION; Schema: core; Owner: -
--

CREATE FUNCTION core.set_fulfilment_preference(p_client_id character varying, p_order_id character varying, p_preference character varying, p_user_id character varying DEFAULT 'SYSTEM'::character varying) RETURNS TABLE(result_status character varying, result_preference character varying, result_message text)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_pref VARCHAR(30) := UPPER(COALESCE(p_preference,''));
    v_user VARCHAR(20) := LEFT(COALESCE(NULLIF(p_user_id,''),'SYSTEM'),20);
BEGIN
    IF v_pref NOT IN ('CONSOLIDATE','SPLIT_WHEN_REQUIRED') THEN
        RETURN QUERY SELECT 'ERROR'::VARCHAR,NULL::VARCHAR,
            'Preference must be CONSOLIDATE or SPLIT_WHEN_REQUIRED.'::TEXT;
        RETURN;
    END IF;

    UPDATE core.ORDER_HEADER
    SET FULFILMENT_PREFERENCE=v_pref,
        LAST_UPDATED_BY=v_user,
        LAST_UPDATE_DATE=now()
    WHERE CLIENT_ID=p_client_id AND ORDER_ID=p_order_id;

    IF NOT FOUND THEN
        RETURN QUERY SELECT 'ERROR'::VARCHAR,NULL::VARCHAR,'Order does not exist.'::TEXT;
        RETURN;
    END IF;

    RETURN QUERY SELECT 'UPDATED'::VARCHAR,v_pref,
        format('Order fulfilment preference set to %s.',v_pref)::TEXT;
END;
$$;


--
-- Name: ship_container(character varying, character varying, character varying, character varying); Type: FUNCTION; Schema: core; Owner: -
--

CREATE FUNCTION core.ship_container(p_client_id character varying, p_container_id character varying, p_user_id character varying DEFAULT 'SYSTEM'::character varying, p_station_id character varying DEFAULT 'WMS'::character varying) RETURNS TABLE(result_status character varying, result_container_id character varying, result_order_id character varying, result_qty_shipped numeric, result_message text)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_container RECORD;
    v_line RECORD;
    v_total NUMERIC(15,6):=0;
    v_user VARCHAR(20):=LEFT(COALESCE(NULLIF(p_user_id,''),'SYSTEM'),20);
BEGIN
    SELECT * INTO v_container FROM core.ORDER_CONTAINER
    WHERE CLIENT_ID=p_client_id AND CONTAINER_ID=p_container_id FOR UPDATE;
    IF NOT FOUND THEN
        RETURN QUERY SELECT 'ERROR'::VARCHAR,p_container_id::VARCHAR,NULL::VARCHAR,0::NUMERIC,'Container does not exist.'::TEXT;
        RETURN;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM core.SHIPPING_MANIFEST WHERE CLIENT_ID=p_client_id AND CONTAINER_ID=p_container_id AND SHIPPED='N') THEN
        RETURN QUERY SELECT 'ALREADY_SHIPPED'::VARCHAR,p_container_id::VARCHAR,v_container.ORDER_ID::VARCHAR,0::NUMERIC,
            'Container has no unshipped packed quantity.'::TEXT;
        RETURN;
    END IF;

    FOR v_line IN
        SELECT LINE_ID,SUM(COALESCE(QTY_PICKED,0)-COALESCE(QTY_SHIPPED,0)) AS QTY
        FROM core.SHIPPING_MANIFEST
        WHERE CLIENT_ID=p_client_id AND CONTAINER_ID=p_container_id AND SHIPPED='N'
        GROUP BY LINE_ID
        ORDER BY LINE_ID
    LOOP
        IF v_line.QTY>0 THEN
            UPDATE core.ORDER_LINE
            SET QTY_SHIPPED=COALESCE(QTY_SHIPPED,0)+v_line.QTY,
                LAST_UPDATED_BY=v_user,LAST_UPDATE_DATE=now()
            WHERE CLIENT_ID=p_client_id AND ORDER_ID=v_container.ORDER_ID AND LINE_ID=v_line.LINE_ID;
            v_total:=v_total+v_line.QTY;
        END IF;
    END LOOP;

    UPDATE core.SHIPPING_MANIFEST
    SET QTY_SHIPPED=QTY_PICKED,SHIPPED='Y',SHIPPED_DSTAMP=now(),STATUS='SHIPPED',USER_ID=v_user
    WHERE CLIENT_ID=p_client_id AND CONTAINER_ID=p_container_id AND SHIPPED='N';

    UPDATE core.ORDER_CONTAINER SET STATUS='SHIPPED' WHERE CLIENT_ID=p_client_id AND CONTAINER_ID=p_container_id;

    UPDATE core.ORDER_HEADER oh
    SET SHIPPED_DATE=CASE WHEN NOT EXISTS (
                SELECT 1 FROM core.ORDER_LINE ol WHERE ol.CLIENT_ID=p_client_id AND ol.ORDER_ID=v_container.ORDER_ID
                  AND COALESCE(ol.QTY_SHIPPED,0)<ol.QTY_ORDERED
            ) THEN now() ELSE oh.SHIPPED_DATE END,
        FULFILMENT_STATUS=CASE WHEN NOT EXISTS (
                SELECT 1 FROM core.ORDER_LINE ol WHERE ol.CLIENT_ID=p_client_id AND ol.ORDER_ID=v_container.ORDER_ID
                  AND COALESCE(ol.QTY_SHIPPED,0)<ol.QTY_ORDERED
            ) THEN 'SHIPPED' ELSE 'PART_SHIPPED' END,
        LAST_UPDATED_BY=v_user,LAST_UPDATE_DATE=now()
    WHERE oh.CLIENT_ID=p_client_id AND oh.ORDER_ID=v_container.ORDER_ID;

    RETURN QUERY SELECT 'SHIPPED'::VARCHAR,p_container_id::VARCHAR,v_container.ORDER_ID::VARCHAR,v_total::NUMERIC,
        format('Shipped container %s with %s unit(s).',p_container_id,v_total)::TEXT;
END;
$$;


--
-- Name: process_order_interface(uuid); Type: FUNCTION; Schema: interface; Owner: -
--

CREATE FUNCTION interface.process_order_interface(p_interface_id uuid) RETURNS TABLE(result_status character varying, result_order_id character varying, result_message text)
    LANGUAGE plpgsql
    AS $$
DECLARE
    V_HEADER interface.ORDER_HEADER_IF%ROWTYPE;
    V_ADDRESS core.ADDRESS%ROWTYPE;
    V_ORDER_ID varchar(20);
    V_NUM_LINES integer;
    V_BAD_SKUS text;
BEGIN
    SELECT * INTO V_HEADER
      FROM interface.ORDER_HEADER_IF
     WHERE INTERFACE_ID = P_INTERFACE_ID
     FOR UPDATE;

    IF NOT FOUND THEN
        RETURN QUERY SELECT 'ERROR'::varchar, NULL::varchar, 'Interface order not found.'::text;
        RETURN;
    END IF;

    IF V_HEADER.PROCESS_STATUS = 'PROCESSED' THEN
        RETURN QUERY SELECT 'PROCESSED'::varchar, V_HEADER.ORDER_ID::varchar,
               'Order has already been processed; no duplicate created.'::text;
        RETURN;
    END IF;

    UPDATE interface.ORDER_HEADER_IF
       SET PROCESS_STATUS='VALIDATING', ERROR_CODE=NULL, ERROR_TEXT=NULL
     WHERE INTERFACE_ID=P_INTERFACE_ID;

    UPDATE interface.ORDER_LINE_IF
       SET PROCESS_STATUS='VALIDATING', ERROR_CODE=NULL, ERROR_TEXT=NULL
     WHERE INTERFACE_ID=P_INTERFACE_ID;

    IF NOT EXISTS (
        SELECT 1 FROM core.CLIENT
         WHERE CLIENT_ID=V_HEADER.CLIENT_ID AND ACTIVE=true
    ) THEN
        RAISE EXCEPTION 'CLIENT_NOT_FOUND: %', V_HEADER.CLIENT_ID;
    END IF;

    SELECT COUNT(*) INTO V_NUM_LINES
      FROM interface.ORDER_LINE_IF
     WHERE INTERFACE_ID=P_INTERFACE_ID;

    IF V_NUM_LINES=0 THEN
        RAISE EXCEPTION 'NO_ORDER_LINES';
    END IF;

    IF EXISTS (
        SELECT 1 FROM interface.ORDER_LINE_IF
         WHERE INTERFACE_ID=P_INTERFACE_ID AND QTY_ORDERED<=0
    ) THEN
        RAISE EXCEPTION 'INVALID_QTY';
    END IF;

    SELECT string_agg(DISTINCT L.SKU_ID, ', ' ORDER BY L.SKU_ID)
      INTO V_BAD_SKUS
      FROM interface.ORDER_LINE_IF L
      LEFT JOIN core.SKU S
        ON S.CLIENT_ID=V_HEADER.CLIENT_ID
       AND S.SKU_ID=L.SKU_ID
     WHERE L.INTERFACE_ID=P_INTERFACE_ID
       AND S.SKU_ID IS NULL;

    IF V_BAD_SKUS IS NOT NULL THEN
        RAISE EXCEPTION 'SKU_NOT_FOUND: %', V_BAD_SKUS;
    END IF;

    IF V_HEADER.ADDRESS_ID IS NOT NULL THEN
        SELECT *
          INTO V_ADDRESS
          FROM core.ADDRESS
         WHERE CLIENT_ID=V_HEADER.CLIENT_ID
           AND ADDRESS_ID=V_HEADER.ADDRESS_ID;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'ADDRESS_NOT_FOUND: %', V_HEADER.ADDRESS_ID;
        END IF;
    END IF;

    V_ORDER_ID := COALESCE(
    NULLIF(V_HEADER.ORDER_ID,''),
    'WEB-' || UPPER(
        SUBSTRING(
            REPLACE(gen_random_uuid()::TEXT,'-','')
            FROM 1 FOR 16
        )
    )
);

    IF V_ORDER_ID IS NULL OR V_ORDER_ID='' THEN
        RAISE EXCEPTION 'ORDER_ID_REQUIRED';
    END IF;

    IF EXISTS (
        SELECT 1 FROM core.ORDER_HEADER
         WHERE CLIENT_ID=V_HEADER.CLIENT_ID AND ORDER_ID=V_ORDER_ID
    ) THEN
        UPDATE interface.ORDER_HEADER_IF
           SET PROCESS_STATUS='PROCESSED',
               ORDER_ID=V_ORDER_ID,
               PROCESSED_DSTAMP=COALESCE(PROCESSED_DSTAMP,now())
         WHERE INTERFACE_ID=P_INTERFACE_ID;

        UPDATE interface.ORDER_LINE_IF
           SET PROCESS_STATUS='PROCESSED'
         WHERE INTERFACE_ID=P_INTERFACE_ID;

        RETURN QUERY SELECT 'PROCESSED'::varchar, V_ORDER_ID::varchar,
               'Operational order already exists; interface marked processed.'::text;
        RETURN;
    END IF;

    INSERT INTO core.ORDER_HEADER (
        CLIENT_ID, ORDER_ID, STATUS, CUSTOMER_ID, ORDER_DATE,
        SHIP_BY_DATE, DELIVER_BY_DATE, DISPATCH_METHOD, SERVICE_LEVEL,
        CONTACT, CONTACT_PHONE, CONTACT_MOBILE, CONTACT_EMAIL,
        NAME, ADDRESS1, ADDRESS2, TOWN, COUNTY, POSTCODE, COUNTRY,
        ORDER_VALUE, INV_CURRENCY, NUM_LINES, ORDER_SOURCE,
        CREATED_BY, CREATION_DATE, LAST_UPDATED_BY, LAST_UPDATE_DATE,
        PAYMENT_STATUS, FULFILMENT_STATUS, FREE_DELIVERY,
        FULFILMENT_PREFERENCE
    )
    VALUES (
        V_HEADER.CLIENT_ID, V_ORDER_ID, 'NEW', V_HEADER.CUSTOMER_ID, V_HEADER.ORDER_DATE,
        V_HEADER.SHIP_BY_DATE, V_HEADER.DELIVER_BY_DATE, V_HEADER.DISPATCH_METHOD,
        V_HEADER.SERVICE_LEVEL,
        CASE WHEN V_HEADER.ADDRESS_ID IS NULL THEN NULL ELSE V_ADDRESS.CONTACT END,
        CASE WHEN V_HEADER.ADDRESS_ID IS NULL THEN NULL ELSE V_ADDRESS.CONTACT_PHONE END,
        CASE WHEN V_HEADER.ADDRESS_ID IS NULL THEN NULL ELSE V_ADDRESS.CONTACT_MOBILE END,
        CASE WHEN V_HEADER.ADDRESS_ID IS NULL THEN NULL ELSE V_ADDRESS.CONTACT_EMAIL END,
        CASE WHEN V_HEADER.ADDRESS_ID IS NULL THEN NULL ELSE V_ADDRESS.NAME END,
        CASE WHEN V_HEADER.ADDRESS_ID IS NULL THEN NULL ELSE V_ADDRESS.ADDRESS1 END,
        CASE WHEN V_HEADER.ADDRESS_ID IS NULL THEN NULL ELSE V_ADDRESS.ADDRESS2 END,
        CASE WHEN V_HEADER.ADDRESS_ID IS NULL THEN NULL ELSE V_ADDRESS.TOWN END,
        CASE WHEN V_HEADER.ADDRESS_ID IS NULL THEN NULL ELSE V_ADDRESS.COUNTY END,
        CASE WHEN V_HEADER.ADDRESS_ID IS NULL THEN NULL ELSE V_ADDRESS.POSTCODE END,
        CASE WHEN V_HEADER.ADDRESS_ID IS NULL THEN NULL ELSE V_ADDRESS.COUNTRY END,
        V_HEADER.ORDER_VALUE, V_HEADER.CURRENCY, V_NUM_LINES,
        CASE WHEN UPPER(COALESCE(V_HEADER.SOURCE_SYSTEM,''))='WEBSITE' THEN 'W' ELSE 'I' END,
        'INTERFACE', now(), 'INTERFACE', now(),
        'PENDING', 'NEW', 'N', V_HEADER.FULFILMENT_PREFERENCE
    );

    INSERT INTO core.ORDER_LINE (
        CLIENT_ID, ORDER_ID, LINE_ID, SKU_ID, QTY_ORDERED,
        PRODUCT_PRICE, EXTENDED_PRICE, PRODUCT_CURRENCY, NOTES,
        ALLOCATE, CREATED_BY, CREATION_DATE, LAST_UPDATED_BY, LAST_UPDATE_DATE
    )
    SELECT
        V_HEADER.CLIENT_ID, V_ORDER_ID, L.LINE_ID, L.SKU_ID, L.QTY_ORDERED,
        L.PRODUCT_PRICE, COALESCE(L.EXTENDED_PRICE,L.PRODUCT_PRICE*L.QTY_ORDERED),
        V_HEADER.CURRENCY, L.NOTES, 'Y',
        'INTERFACE', now(), 'INTERFACE', now()
      FROM interface.ORDER_LINE_IF L
     WHERE L.INTERFACE_ID=P_INTERFACE_ID;

    UPDATE interface.ORDER_LINE_IF
       SET PROCESS_STATUS='PROCESSED', ERROR_CODE=NULL, ERROR_TEXT=NULL
     WHERE INTERFACE_ID=P_INTERFACE_ID;

    UPDATE interface.ORDER_HEADER_IF
       SET ORDER_ID=V_ORDER_ID, PROCESS_STATUS='PROCESSED',
           ERROR_CODE=NULL, ERROR_TEXT=NULL, PROCESSED_DSTAMP=now()
     WHERE INTERFACE_ID=P_INTERFACE_ID;

    RETURN QUERY SELECT 'PROCESSED'::varchar, V_ORDER_ID::varchar,
           ('Imported '||V_NUM_LINES||' order line(s).')::text;

EXCEPTION
    WHEN OTHERS THEN
        UPDATE interface.ORDER_HEADER_IF
           SET PROCESS_STATUS='ERROR',
               ERROR_CODE=LEFT(SQLSTATE,50),
               ERROR_TEXT=SQLERRM
         WHERE INTERFACE_ID=P_INTERFACE_ID;

        UPDATE interface.ORDER_LINE_IF
           SET PROCESS_STATUS='ERROR',
               ERROR_CODE=LEFT(SQLSTATE,50),
               ERROR_TEXT=SQLERRM
         WHERE INTERFACE_ID=P_INTERFACE_ID
           AND PROCESS_STATUS<>'PROCESSED';

        RETURN QUERY SELECT 'ERROR'::varchar,
               COALESCE(V_ORDER_ID,V_HEADER.ORDER_ID)::varchar,
               SQLERRM::text;
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: inventory; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.inventory (
    key bigint NOT NULL,
    tag_id character varying(50),
    container_id character varying(50),
    client_id character varying(10) NOT NULL,
    sku_id character varying(50) NOT NULL,
    site_id character varying(10),
    location_id character varying(20) NOT NULL,
    owner_id character varying(10),
    qty_on_hand numeric(15,6) NOT NULL,
    qty_allocated numeric(15,6) NOT NULL,
    origin_id character varying(10),
    condition_id character varying(10),
    lock_status character varying(20) NOT NULL,
    lock_code character varying(10),
    receipt_dstamp timestamp with time zone NOT NULL,
    move_dstamp timestamp with time zone NOT NULL,
    receipt_type character varying(1),
    receipt_id character varying(20),
    line_id numeric(6,0),
    qc_status character varying(20),
    batch_id character varying(50),
    expiry_dstamp timestamp with time zone,
    manuf_dstamp timestamp with time zone,
    count_dstamp timestamp with time zone,
    count_needed character varying(1),
    supplier_id character varying(15),
    description character varying(80),
    notes character varying(80),
    disallow_alloc character varying(1),
    unit_cost numeric(12,2)
);


--
-- Name: location; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.location (
    site_id character varying(10),
    location_id character varying(20) NOT NULL,
    zone_1 character varying(10),
    subzone_1 character varying(10),
    subzone_2 character varying(10),
    storage_class character varying(10),
    loc_type character varying(15) NOT NULL,
    lock_status character varying(20) NOT NULL,
    volume numeric(13,6) NOT NULL,
    height numeric(15,6),
    depth numeric(7,3),
    width numeric(7,3),
    weight numeric(13,6),
    disallow_alloc character varying(1),
    count_dstamp timestamp with time zone,
    pick_face character varying(1),
    count_needed character varying(1) NOT NULL,
    aisle character varying(20),
    bay character varying(20),
    levels character varying(20),
    "position" character varying(20),
    locality character varying(10),
    max_units_on_loc numeric(10,0),
    id numeric NOT NULL,
    description character varying(120),
    active character(1) NOT NULL,
    livestock_allowed character(1) NOT NULL
);


--
-- Name: COLUMN location.site_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.location.site_id IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN location.location_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.location.location_id IS 'KEEP: Inventory/location identifier';


--
-- Name: COLUMN location.zone_1; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.location.zone_1 IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN location.subzone_1; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.location.subzone_1 IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN location.subzone_2; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.location.subzone_2 IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN location.storage_class; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.location.storage_class IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN location.loc_type; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.location.loc_type IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN location.lock_status; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.location.lock_status IS 'KEEP: Inventory/location hold state';


--
-- Name: COLUMN location.volume; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.location.volume IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN location.height; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.location.height IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN location.depth; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.location.depth IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN location.width; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.location.width IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN location.weight; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.location.weight IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN location.disallow_alloc; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.location.disallow_alloc IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN location.count_dstamp; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.location.count_dstamp IS 'KEEP: Audit/operational timestamp';


--
-- Name: COLUMN location.pick_face; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.location.pick_face IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN location.count_needed; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.location.count_needed IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN location.aisle; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.location.aisle IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN location.bay; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.location.bay IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN location.levels; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.location.levels IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN location."position"; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.location."position" IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN location.locality; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.location.locality IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN location.max_units_on_loc; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.location.max_units_on_loc IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN location.id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.location.id IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN location.description; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.location.description IS 'ADD: Friendly location/tank description';


--
-- Name: COLUMN location.active; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.location.active IS 'ADD: Whether location is operational';


--
-- Name: COLUMN location.livestock_allowed; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.location.livestock_allowed IS 'ADD: Whether livestock can be held here';


--
-- Name: product_variant; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.product_variant (
    client_id character varying(30) NOT NULL,
    product_id character varying(50) NOT NULL,
    sku_id character varying(50) NOT NULL,
    variant_name character varying(200) NOT NULL,
    option_values jsonb DEFAULT '{}'::jsonb NOT NULL,
    web_price numeric(12,2) NOT NULL,
    compare_at_price numeric(12,2),
    active boolean DEFAULT true NOT NULL,
    sort_sequence integer DEFAULT 100 NOT NULL,
    created_dstamp timestamp with time zone DEFAULT now() NOT NULL,
    last_update_dstamp timestamp with time zone DEFAULT now() NOT NULL,
    sale_type character varying(30) DEFAULT 'STANDARD'::character varying NOT NULL,
    availability_state character varying(30) DEFAULT 'AVAILABLE'::character varying NOT NULL,
    expected_available_from date,
    expected_available_to date,
    web_metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    min_order_qty numeric(15,6) DEFAULT 1 NOT NULL,
    max_order_qty numeric(15,6),
    qty_increment numeric(15,6) DEFAULT 1 NOT NULL
);


--
-- Name: TABLE product_variant; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.product_variant IS 'Maps customer-selectable product options to the real warehouse SKU.';


--
-- Name: catalog_variant_availability; Type: VIEW; Schema: api; Owner: -
--

CREATE VIEW api.catalog_variant_availability AS
 SELECT pv.client_id,
    pv.product_id,
    pv.sku_id,
    pv.variant_name,
    pv.option_values,
    pv.web_price,
    pv.compare_at_price,
    pv.active,
        CASE
            WHEN ((pv.availability_state)::text = 'AVAILABLE'::text) THEN COALESCE(sum(
            CASE
                WHEN (((COALESCE(i.disallow_alloc, 'N'::character varying))::text <> 'Y'::text) AND (upper((COALESCE(i.lock_status, ''::character varying))::text) <> ALL (ARRAY['LOCKED'::text, 'HOLD'::text, 'QUARANTINE'::text])) AND ((COALESCE(l.disallow_alloc, 'N'::character varying))::text <> 'Y'::text) AND (upper((COALESCE(l.lock_status, ''::character varying))::text) <> ALL (ARRAY['LOCKED'::text, 'HOLD'::text, 'QUARANTINE'::text])) AND (COALESCE(l.active, 'Y'::bpchar) = 'Y'::bpchar)) THEN GREATEST((COALESCE(i.qty_on_hand, (0)::numeric) - COALESCE(i.qty_allocated, (0)::numeric)), (0)::numeric)
                ELSE (0)::numeric
            END), (0)::numeric)
            ELSE (0)::numeric
        END AS available_qty,
    pv.sale_type,
    pv.availability_state,
    pv.expected_available_from,
    pv.expected_available_to,
    pv.web_metadata,
    pv.min_order_qty,
    pv.max_order_qty,
    pv.qty_increment
   FROM ((core.product_variant pv
     LEFT JOIN core.inventory i ON ((((i.client_id)::text = (pv.client_id)::text) AND ((i.sku_id)::text = (pv.sku_id)::text))))
     LEFT JOIN core.location l ON (((l.location_id)::text = (i.location_id)::text)))
  GROUP BY pv.client_id, pv.product_id, pv.sku_id, pv.variant_name, pv.option_values, pv.web_price, pv.compare_at_price, pv.active, pv.sale_type, pv.availability_state, pv.expected_available_from, pv.expected_available_to, pv.web_metadata, pv.min_order_qty, pv.max_order_qty, pv.qty_increment;


--
-- Name: product; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.product (
    client_id character varying(30) NOT NULL,
    product_id character varying(50) NOT NULL,
    product_name character varying(200) NOT NULL,
    slug character varying(220) NOT NULL,
    brand_name character varying(100),
    category_code character varying(50),
    short_description character varying(500),
    description text,
    delivery_class character varying(30) DEFAULT 'STANDARD'::character varying NOT NULL,
    currency character varying(3) DEFAULT 'GBP'::character varying NOT NULL,
    media jsonb DEFAULT '[]'::jsonb NOT NULL,
    specification jsonb DEFAULT '{}'::jsonb NOT NULL,
    active boolean DEFAULT true NOT NULL,
    featured boolean DEFAULT false NOT NULL,
    sort_sequence integer DEFAULT 100 NOT NULL,
    created_dstamp timestamp with time zone DEFAULT now() NOT NULL,
    last_update_dstamp timestamp with time zone DEFAULT now() NOT NULL,
    product_type character varying(30) DEFAULT 'GOODS'::character varying NOT NULL,
    search_metadata jsonb DEFAULT '{}'::jsonb NOT NULL
);


--
-- Name: TABLE product; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.product IS 'Customer-facing product master. One PRODUCT may expose multiple stock-controlled SKU variants.';


--
-- Name: product_category; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.product_category (
    client_id character varying(30) NOT NULL,
    category_code character varying(50) NOT NULL,
    parent_category_code character varying(50),
    category_name character varying(100) NOT NULL,
    slug character varying(120) NOT NULL,
    description character varying(500),
    sort_sequence integer DEFAULT 100 NOT NULL,
    active boolean DEFAULT true NOT NULL,
    created_dstamp timestamp with time zone DEFAULT now() NOT NULL,
    last_update_dstamp timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: TABLE product_category; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.product_category IS 'Website catalogue category tree. Separate from warehouse SKU grouping.';


--
-- Name: catalog_product_list; Type: VIEW; Schema: api; Owner: -
--

CREATE VIEW api.catalog_product_list AS
 SELECT p.client_id,
    p.product_id,
    p.product_name,
    p.slug,
    p.brand_name,
    p.category_code,
    c.category_name,
    c.slug AS category_slug,
    p.short_description,
    p.delivery_class,
    p.currency,
    p.media,
    p.featured,
    p.sort_sequence,
    min(v.web_price) FILTER (WHERE v.active) AS from_price,
    max(v.web_price) FILTER (WHERE v.active) AS to_price,
    COALESCE(sum(v.available_qty) FILTER (WHERE v.active), (0)::numeric) AS available_qty,
    p.product_type,
    COALESCE(jsonb_agg(DISTINCT v.availability_state) FILTER (WHERE (v.active AND (v.availability_state IS NOT NULL))), '[]'::jsonb) AS availability_states,
    COALESCE(jsonb_agg(DISTINCT v.sale_type) FILTER (WHERE (v.active AND (v.sale_type IS NOT NULL))), '[]'::jsonb) AS sale_types
   FROM ((core.product p
     LEFT JOIN core.product_category c ON ((((c.client_id)::text = (p.client_id)::text) AND ((c.category_code)::text = (p.category_code)::text))))
     LEFT JOIN api.catalog_variant_availability v ON ((((v.client_id)::text = (p.client_id)::text) AND ((v.product_id)::text = (p.product_id)::text))))
  WHERE (p.active = true)
  GROUP BY p.client_id, p.product_id, p.product_name, p.slug, p.brand_name, p.category_code, c.category_name, c.slug, p.short_description, p.delivery_class, p.currency, p.media, p.featured, p.sort_sequence, p.product_type;


--
-- Name: affiliate_click; Type: TABLE; Schema: audit; Owner: -
--

CREATE TABLE audit.affiliate_click (
    click_id uuid DEFAULT gen_random_uuid() NOT NULL,
    client_id character varying(30) NOT NULL,
    link_id uuid NOT NULL,
    session_id character varying(100),
    source character varying(100),
    referrer text,
    user_agent text,
    created_dstamp timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: api_security_event; Type: TABLE; Schema: audit; Owner: -
--

CREATE TABLE audit.api_security_event (
    security_event_key bigint NOT NULL,
    client_id character varying(30),
    event_type character varying(50) NOT NULL,
    auth_provider character varying(50),
    auth_subject character varying(200),
    route character varying(250),
    resource_type character varying(50),
    resource_id character varying(200),
    result character varying(30) NOT NULL,
    detail character varying(500),
    created_dstamp timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: api_security_event_security_event_key_seq; Type: SEQUENCE; Schema: audit; Owner: -
--

ALTER TABLE audit.api_security_event ALTER COLUMN security_event_key ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME audit.api_security_event_security_event_key_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: audit_event; Type: TABLE; Schema: audit; Owner: -
--

CREATE TABLE audit.audit_event (
    audit_id bigint NOT NULL,
    client_id character varying(30),
    entity_type character varying(50) NOT NULL,
    entity_id character varying(120) NOT NULL,
    action character varying(40) NOT NULL,
    changed_by character varying(120),
    reason text,
    before_data jsonb,
    after_data jsonb,
    created_dstamp timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: audit_event_audit_id_seq; Type: SEQUENCE; Schema: audit; Owner: -
--

ALTER TABLE audit.audit_event ALTER COLUMN audit_id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME audit.audit_event_audit_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: payment_event; Type: TABLE; Schema: audit; Owner: -
--

CREATE TABLE audit.payment_event (
    payment_event_key bigint NOT NULL,
    client_id character varying(30) NOT NULL,
    provider character varying(30) NOT NULL,
    provider_event_id character varying(200) NOT NULL,
    event_type character varying(100) NOT NULL,
    provider_reference character varying(200),
    payment_id uuid,
    event_status character varying(30) DEFAULT 'RECEIVED'::character varying NOT NULL,
    event_payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    error_text character varying(500),
    created_dstamp timestamp with time zone DEFAULT now() NOT NULL,
    processed_dstamp timestamp with time zone
);


--
-- Name: payment_event_payment_event_key_seq; Type: SEQUENCE; Schema: audit; Owner: -
--

ALTER TABLE audit.payment_event ALTER COLUMN payment_event_key ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME audit.payment_event_payment_event_key_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: processing_log; Type: TABLE; Schema: audit; Owner: -
--

CREATE TABLE audit.processing_log (
    log_id bigint NOT NULL,
    client_id character varying(30),
    process_name character varying(80) NOT NULL,
    process_run_id uuid,
    entity_type character varying(50),
    entity_id character varying(100),
    status character varying(30),
    message text,
    detail jsonb,
    created_dstamp timestamp with time zone DEFAULT now() NOT NULL,
    created_by character varying(100)
);


--
-- Name: processing_log_log_id_seq; Type: SEQUENCE; Schema: audit; Owner: -
--

ALTER TABLE audit.processing_log ALTER COLUMN log_id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME audit.processing_log_log_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: rule_decision_log; Type: TABLE; Schema: audit; Owner: -
--

CREATE TABLE audit.rule_decision_log (
    decision_id bigint NOT NULL,
    client_id character varying(30),
    engine_name character varying(50) NOT NULL,
    entity_type character varying(50),
    entity_id character varying(120),
    rule_id bigint,
    rule_name character varying(120),
    matched boolean,
    decision character varying(80),
    reason text,
    detail jsonb,
    created_dstamp timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: rule_decision_log_decision_id_seq; Type: SEQUENCE; Schema: audit; Owner: -
--

ALTER TABLE audit.rule_decision_log ALTER COLUMN decision_id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME audit.rule_decision_log_decision_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: allocation_rule; Type: TABLE; Schema: config; Owner: -
--

CREATE TABLE config.allocation_rule (
    rule_id bigint NOT NULL,
    client_id character varying(30) NOT NULL,
    rule_name character varying(120) NOT NULL,
    priority integer DEFAULT 100 NOT NULL,
    strategy character varying(40) DEFAULT 'FIFO'::character varying NOT NULL,
    active boolean DEFAULT true NOT NULL,
    stop_on_match boolean DEFAULT true NOT NULL,
    created_dstamp timestamp with time zone DEFAULT now() NOT NULL,
    last_updated_dstamp timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: allocation_rule_condition; Type: TABLE; Schema: config; Owner: -
--

CREATE TABLE config.allocation_rule_condition (
    condition_id bigint NOT NULL,
    rule_id bigint NOT NULL,
    field_name character varying(80) NOT NULL,
    operator character varying(20) NOT NULL,
    value_text text,
    value_numeric numeric(18,6),
    value_boolean boolean,
    condition_group integer DEFAULT 1 NOT NULL,
    sequence integer DEFAULT 100 NOT NULL,
    negate boolean DEFAULT false NOT NULL
);


--
-- Name: allocation_rule_condition_condition_id_seq; Type: SEQUENCE; Schema: config; Owner: -
--

ALTER TABLE config.allocation_rule_condition ALTER COLUMN condition_id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME config.allocation_rule_condition_condition_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: allocation_rule_rule_id_seq; Type: SEQUENCE; Schema: config; Owner: -
--

ALTER TABLE config.allocation_rule ALTER COLUMN rule_id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME config.allocation_rule_rule_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: carrier; Type: TABLE; Schema: config; Owner: -
--

CREATE TABLE config.carrier (
    client_id character varying(30) NOT NULL,
    carrier_id character varying(30) NOT NULL,
    description character varying(100) NOT NULL,
    active boolean DEFAULT true NOT NULL,
    api_enabled boolean DEFAULT false NOT NULL,
    account_reference character varying(100),
    tracking_url_pattern text,
    created_dstamp timestamp with time zone DEFAULT now() NOT NULL,
    last_updated_dstamp timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: carrier_selection_condition; Type: TABLE; Schema: config; Owner: -
--

CREATE TABLE config.carrier_selection_condition (
    condition_id bigint NOT NULL,
    rule_id bigint NOT NULL,
    field_name character varying(80) NOT NULL,
    operator character varying(20) NOT NULL,
    value_text text,
    value_numeric numeric(18,6),
    value_boolean boolean,
    value_from numeric(18,6),
    value_to numeric(18,6),
    condition_group integer DEFAULT 1 NOT NULL,
    sequence integer DEFAULT 100 NOT NULL,
    negate boolean DEFAULT false NOT NULL
);


--
-- Name: carrier_selection_condition_condition_id_seq; Type: SEQUENCE; Schema: config; Owner: -
--

ALTER TABLE config.carrier_selection_condition ALTER COLUMN condition_id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME config.carrier_selection_condition_condition_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: carrier_selection_rule; Type: TABLE; Schema: config; Owner: -
--

CREATE TABLE config.carrier_selection_rule (
    rule_id bigint NOT NULL,
    client_id character varying(30) NOT NULL,
    rule_name character varying(100) NOT NULL,
    priority integer DEFAULT 100 NOT NULL,
    active boolean DEFAULT true NOT NULL,
    carrier_id character varying(30),
    service_level character varying(50),
    min_weight_kg numeric(12,3),
    max_weight_kg numeric(12,3),
    min_volume_cm3 numeric(18,3),
    max_volume_cm3 numeric(18,3),
    max_item_length_cm numeric(12,3),
    max_order_value numeric(14,2),
    min_order_value numeric(14,2),
    dispatch_method character varying(30),
    delivery_class character varying(30),
    country_code character varying(3),
    rule_expression jsonb,
    stop_on_match boolean DEFAULT true NOT NULL,
    created_dstamp timestamp with time zone DEFAULT now() NOT NULL,
    last_updated_dstamp timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: carrier_selection_rule_rule_id_seq; Type: SEQUENCE; Schema: config; Owner: -
--

ALTER TABLE config.carrier_selection_rule ALTER COLUMN rule_id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME config.carrier_selection_rule_rule_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: carrier_service; Type: TABLE; Schema: config; Owner: -
--

CREATE TABLE config.carrier_service (
    client_id character varying(30) NOT NULL,
    carrier_id character varying(30) NOT NULL,
    service_level character varying(50) NOT NULL,
    description character varying(120),
    dispatch_method character varying(30),
    active boolean DEFAULT true NOT NULL,
    max_weight_kg numeric(12,3),
    max_length_cm numeric(12,3),
    max_width_cm numeric(12,3),
    max_height_cm numeric(12,3),
    max_volume_cm3 numeric(18,3),
    volumetric_divisor numeric(12,3),
    max_parcels integer,
    base_cost numeric(12,2),
    cost_per_kg numeric(12,4),
    requires_manual_approval boolean DEFAULT false NOT NULL,
    live_goods_allowed boolean DEFAULT false NOT NULL,
    sort_sequence integer DEFAULT 100 NOT NULL,
    created_dstamp timestamp with time zone DEFAULT now() NOT NULL,
    last_updated_dstamp timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: carrier_service_rate; Type: TABLE; Schema: config; Owner: -
--

CREATE TABLE config.carrier_service_rate (
    rate_id bigint NOT NULL,
    client_id character varying(30) NOT NULL,
    carrier_id character varying(30) NOT NULL,
    service_level character varying(50) NOT NULL,
    min_weight_kg numeric(12,3) DEFAULT 0 NOT NULL,
    max_weight_kg numeric(12,3),
    postcode_prefix character varying(20),
    country_code character varying(3),
    base_cost numeric(12,2) DEFAULT 0 NOT NULL,
    cost_per_kg numeric(12,4) DEFAULT 0 NOT NULL,
    surcharge numeric(12,2) DEFAULT 0 NOT NULL,
    active boolean DEFAULT true NOT NULL,
    priority integer DEFAULT 100 NOT NULL,
    effective_from date,
    effective_to date,
    created_dstamp timestamp with time zone DEFAULT now() NOT NULL,
    last_updated_dstamp timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: TABLE carrier_service_rate; Type: COMMENT; Schema: config; Owner: -
--

COMMENT ON TABLE config.carrier_service_rate IS 'Optional weight/postcode/country rate bands used by Carrier Selection V1. A separate table is justified because one carrier service can have many commercial rate bands.';


--
-- Name: carrier_service_rate_rate_id_seq; Type: SEQUENCE; Schema: config; Owner: -
--

ALTER TABLE config.carrier_service_rate ALTER COLUMN rate_id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME config.carrier_service_rate_rate_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: delivery_class_control; Type: TABLE; Schema: config; Owner: -
--

CREATE TABLE config.delivery_class_control (
    client_id character varying(30) NOT NULL,
    delivery_class character varying(30) NOT NULL,
    carrier_despatch_enabled boolean DEFAULT true NOT NULL,
    hold_reason character varying(250),
    created_dstamp timestamp with time zone DEFAULT now() NOT NULL,
    last_update_dstamp timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: delivery_zone; Type: TABLE; Schema: config; Owner: -
--

CREATE TABLE config.delivery_zone (
    client_id character varying(30) NOT NULL,
    zone_id character varying(50) NOT NULL,
    zone_name character varying(100) NOT NULL,
    fulfilment_method character varying(30) NOT NULL,
    country character varying(25) DEFAULT 'GB'::character varying NOT NULL,
    postcode_prefix character varying(20),
    min_distance_miles numeric(8,2),
    max_distance_miles numeric(8,2),
    min_order_value numeric(12,2),
    delivery_price numeric(12,2),
    currency character varying(3) DEFAULT 'GBP'::character varying NOT NULL,
    requires_manual_confirmation boolean DEFAULT false NOT NULL,
    priority integer DEFAULT 100 NOT NULL,
    active boolean DEFAULT true NOT NULL,
    created_dstamp timestamp with time zone DEFAULT now() NOT NULL,
    last_update_dstamp timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: feature_flag; Type: TABLE; Schema: config; Owner: -
--

CREATE TABLE config.feature_flag (
    client_id character varying(30) NOT NULL,
    feature_key character varying(100) NOT NULL,
    enabled boolean DEFAULT false NOT NULL,
    description character varying(250),
    last_updated_dstamp timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: merge_rule; Type: TABLE; Schema: config; Owner: -
--

CREATE TABLE config.merge_rule (
    rule_id bigint NOT NULL,
    client_id character varying(30) NOT NULL,
    rule_name character varying(100) NOT NULL,
    priority integer DEFAULT 100 NOT NULL,
    active boolean DEFAULT true NOT NULL,
    decision character varying(10) DEFAULT 'ALLOW'::character varying NOT NULL,
    stop_on_match boolean DEFAULT true NOT NULL,
    created_dstamp timestamp with time zone DEFAULT now() NOT NULL,
    last_update_dstamp timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT ck_merge_rule_decision CHECK (((decision)::text = ANY ((ARRAY['ALLOW'::character varying, 'DENY'::character varying])::text[])))
);


--
-- Name: TABLE merge_rule; Type: COMMENT; Schema: config; Owner: -
--

COMMENT ON TABLE config.merge_rule IS 'Ordered, client-specific rules controlling whether two compatible containers may be consolidated.';


--
-- Name: merge_rule_condition; Type: TABLE; Schema: config; Owner: -
--

CREATE TABLE config.merge_rule_condition (
    condition_id bigint NOT NULL,
    rule_id bigint NOT NULL,
    field_name character varying(50) NOT NULL,
    operator character varying(20) NOT NULL,
    value_text character varying(250),
    value_numeric numeric(18,4),
    value_boolean boolean,
    value_from numeric(18,4),
    value_to numeric(18,4),
    condition_group integer DEFAULT 1 NOT NULL,
    sequence integer DEFAULT 10 NOT NULL,
    negate boolean DEFAULT false NOT NULL,
    created_dstamp timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: TABLE merge_rule_condition; Type: COMMENT; Schema: config; Owner: -
--

COMMENT ON TABLE config.merge_rule_condition IS 'Safe, structured conditions for MERGE_RULE. Conditions inside a group are ANDed; groups are ORed.';


--
-- Name: merge_rule_condition_condition_id_seq; Type: SEQUENCE; Schema: config; Owner: -
--

ALTER TABLE config.merge_rule_condition ALTER COLUMN condition_id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME config.merge_rule_condition_condition_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: merge_rule_rule_id_seq; Type: SEQUENCE; Schema: config; Owner: -
--

ALTER TABLE config.merge_rule ALTER COLUMN rule_id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME config.merge_rule_rule_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: promotion; Type: TABLE; Schema: config; Owner: -
--

CREATE TABLE config.promotion (
    client_id character varying(30) NOT NULL,
    promotion_id character varying(50) NOT NULL,
    promo_code character varying(50) NOT NULL,
    description character varying(250),
    promotion_type character varying(30) NOT NULL,
    promotion_value numeric(12,2),
    min_order_value numeric(12,2),
    delivery_class character varying(30),
    starts_dstamp timestamp with time zone,
    ends_dstamp timestamp with time zone,
    active boolean DEFAULT true NOT NULL,
    created_dstamp timestamp with time zone DEFAULT now() NOT NULL,
    last_update_dstamp timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT ck_promotion_type CHECK (((promotion_type)::text = ANY ((ARRAY['PERCENT'::character varying, 'FIXED'::character varying, 'FREE_DELIVERY'::character varying])::text[])))
);


--
-- Name: system_setting; Type: TABLE; Schema: config; Owner: -
--

CREATE TABLE config.system_setting (
    setting_id bigint NOT NULL,
    client_id character varying(30),
    site_id character varying(30),
    setting_key character varying(100) NOT NULL,
    value_text text,
    value_numeric numeric(18,6),
    value_boolean boolean,
    description character varying(250),
    active boolean DEFAULT true NOT NULL,
    created_dstamp timestamp with time zone DEFAULT now() NOT NULL,
    last_updated_dstamp timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: system_setting_setting_id_seq; Type: SEQUENCE; Schema: config; Owner: -
--

ALTER TABLE config.system_setting ALTER COLUMN setting_id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME config.system_setting_setting_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: system_version; Type: TABLE; Schema: config; Owner: -
--

CREATE TABLE config.system_version (
    version_key bigint NOT NULL,
    product_code character varying(30) NOT NULL,
    product_name character varying(100) NOT NULL,
    version_number character varying(30) NOT NULL,
    version_major integer NOT NULL,
    version_minor integer NOT NULL,
    version_patch integer NOT NULL,
    build_number integer DEFAULT 0 NOT NULL,
    release_channel character varying(20) DEFAULT 'DEVELOPMENT'::character varying NOT NULL,
    release_date date DEFAULT CURRENT_DATE NOT NULL,
    description character varying(500),
    is_current boolean DEFAULT false NOT NULL,
    installed_dstamp timestamp with time zone DEFAULT now() NOT NULL,
    installed_by character varying(100) DEFAULT CURRENT_USER NOT NULL
);


--
-- Name: system_version_version_key_seq; Type: SEQUENCE; Schema: config; Owner: -
--

ALTER TABLE config.system_version ALTER COLUMN version_key ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME config.system_version_version_key_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: address; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.address (
    client_id character varying(10) NOT NULL,
    address_id character varying(15) NOT NULL,
    address_type character varying(10),
    contact character varying(25),
    contact_phone character varying(25),
    contact_mobile character varying(25),
    contact_email character varying(256),
    name character varying(50),
    address1 character varying(60),
    address2 character varying(60),
    town character varying(60),
    county character varying(60),
    postcode character varying(20),
    country character varying(25),
    directions character varying(180),
    url character varying(250),
    vat_number character varying(20),
    delivery_open_time timestamp with time zone,
    delivery_close_time timestamp with time zone,
    delivery_open_mon character varying(1),
    delivery_open_tue character varying(1),
    delivery_open_wed character varying(1),
    delivery_open_thur character varying(1),
    delivery_open_fri character varying(1),
    delivery_open_sat character varying(1),
    delivery_open_sun character varying(1),
    fastest_carrier character varying(1),
    cheapest_carrier character varying(1),
    freight_charges character varying(10),
    customer_type character varying(1),
    credit_status character varying(1),
    credit_days numeric(4,0),
    retailer_id character varying(15),
    latitude numeric(10,7),
    longitude numeric(10,7),
    active character(1) NOT NULL,
    default_billing character(1) NOT NULL,
    default_delivery character(1) NOT NULL
);


--
-- Name: COLUMN address.client_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.address.client_id IS 'KEEP: Client/business identifier';


--
-- Name: COLUMN address.address_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.address.address_id IS 'KEEP: Customer/billing/delivery address snapshot';


--
-- Name: COLUMN address.address_type; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.address.address_type IS 'KEEP: Customer/billing/delivery address snapshot';


--
-- Name: COLUMN address.contact; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.address.contact IS 'KEEP: Customer/billing/delivery address snapshot';


--
-- Name: COLUMN address.contact_phone; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.address.contact_phone IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN address.contact_mobile; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.address.contact_mobile IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN address.contact_email; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.address.contact_email IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN address.name; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.address.name IS 'KEEP: Customer/billing/delivery address snapshot';


--
-- Name: COLUMN address.address1; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.address.address1 IS 'KEEP: Customer/billing/delivery address snapshot';


--
-- Name: COLUMN address.address2; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.address.address2 IS 'KEEP: Customer/billing/delivery address snapshot';


--
-- Name: COLUMN address.town; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.address.town IS 'KEEP: Customer/billing/delivery address snapshot';


--
-- Name: COLUMN address.county; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.address.county IS 'KEEP: Customer/billing/delivery address snapshot';


--
-- Name: COLUMN address.postcode; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.address.postcode IS 'KEEP: Customer/billing/delivery address snapshot';


--
-- Name: COLUMN address.country; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.address.country IS 'KEEP: Customer/billing/delivery address snapshot';


--
-- Name: COLUMN address.directions; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.address.directions IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN address.url; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.address.url IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN address.vat_number; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.address.vat_number IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN address.delivery_open_time; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.address.delivery_open_time IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN address.delivery_close_time; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.address.delivery_close_time IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN address.delivery_open_mon; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.address.delivery_open_mon IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN address.delivery_open_tue; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.address.delivery_open_tue IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN address.delivery_open_wed; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.address.delivery_open_wed IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN address.delivery_open_thur; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.address.delivery_open_thur IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN address.delivery_open_fri; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.address.delivery_open_fri IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN address.delivery_open_sat; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.address.delivery_open_sat IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN address.delivery_open_sun; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.address.delivery_open_sun IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN address.fastest_carrier; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.address.fastest_carrier IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN address.cheapest_carrier; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.address.cheapest_carrier IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN address.freight_charges; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.address.freight_charges IS 'KEEP: Delivery/freight charge/cost';


--
-- Name: COLUMN address.customer_type; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.address.customer_type IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN address.credit_status; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.address.credit_status IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN address.credit_days; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.address.credit_days IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN address.retailer_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.address.retailer_id IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN address.latitude; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.address.latitude IS 'ADD: Cached latitude for distance-based delivery';


--
-- Name: COLUMN address.longitude; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.address.longitude IS 'ADD: Cached longitude for distance-based delivery';


--
-- Name: COLUMN address.active; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.address.active IS 'ADD: Whether address record is active';


--
-- Name: COLUMN address.default_billing; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.address.default_billing IS 'ADD: Default billing address flag';


--
-- Name: COLUMN address.default_delivery; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.address.default_delivery IS 'ADD: Default delivery address flag';


--
-- Name: allocation; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.allocation (
    allocation_id bigint NOT NULL,
    client_id character varying(10) NOT NULL,
    order_id character varying(20) NOT NULL,
    line_id numeric(6,0) NOT NULL,
    inventory_key bigint NOT NULL,
    qty_allocated numeric(15,6) NOT NULL,
    allocation_dstamp timestamp with time zone DEFAULT now() NOT NULL,
    created_by character varying(20) DEFAULT 'SYSTEM'::character varying NOT NULL,
    qty_picked numeric(15,6) DEFAULT 0 NOT NULL,
    qty_released numeric(15,6) DEFAULT 0 NOT NULL,
    status character varying(30) DEFAULT 'ALLOCATED'::character varying NOT NULL,
    last_update_dstamp timestamp with time zone DEFAULT now() NOT NULL,
    last_updated_by character varying(20) DEFAULT 'SYSTEM'::character varying NOT NULL,
    CONSTRAINT ck_allocation_qty_consumed CHECK (((qty_picked >= (0)::numeric) AND (qty_released >= (0)::numeric) AND ((qty_picked + qty_released) <= qty_allocated))),
    CONSTRAINT ck_allocation_qty_positive CHECK ((qty_allocated > (0)::numeric))
);


--
-- Name: TABLE allocation; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.allocation IS 'Links order-line demand to the exact inventory records reserved to fulfil it.';


--
-- Name: COLUMN allocation.allocation_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.allocation.allocation_id IS 'Unique allocation/reservation identifier.';


--
-- Name: COLUMN allocation.client_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.allocation.client_id IS 'Client/business identifier.';


--
-- Name: COLUMN allocation.order_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.allocation.order_id IS 'Order identifier.';


--
-- Name: COLUMN allocation.line_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.allocation.line_id IS 'Order line identifier.';


--
-- Name: COLUMN allocation.inventory_key; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.allocation.inventory_key IS 'Inventory record supplying the reservation.';


--
-- Name: COLUMN allocation.qty_allocated; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.allocation.qty_allocated IS 'Quantity reserved from the inventory record for the order line.';


--
-- Name: COLUMN allocation.allocation_dstamp; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.allocation.allocation_dstamp IS 'Timestamp when the reservation was created.';


--
-- Name: COLUMN allocation.created_by; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.allocation.created_by IS 'Process or user that created the reservation.';


--
-- Name: allocation_allocation_id_seq; Type: SEQUENCE; Schema: core; Owner: -
--

ALTER TABLE core.allocation ALTER COLUMN allocation_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME core.allocation_allocation_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: carrier_decision_explanation; Type: VIEW; Schema: core; Owner: -
--

CREATE VIEW core.carrier_decision_explanation AS
 SELECT decision_id,
    client_id,
    entity_id AS container_id,
    rule_id,
    rule_name,
    matched,
    decision,
    reason,
    detail,
    created_dstamp
   FROM audit.rule_decision_log
  WHERE (((engine_name)::text = 'CARRIER_SELECTION'::text) AND ((entity_type)::text = 'ORDER_CONTAINER'::text));


--
-- Name: order_container; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.order_container (
    container_key bigint NOT NULL,
    client_id character varying(30) NOT NULL,
    order_id character varying(50) NOT NULL,
    container_id character varying(80) NOT NULL,
    container_type character varying(40),
    status character varying(30) DEFAULT 'OPEN'::character varying NOT NULL,
    weight numeric(14,3),
    height numeric(14,3),
    width numeric(14,3),
    depth numeric(14,3),
    volume numeric(18,3),
    carrier_id character varying(30),
    service_level character varying(50),
    tracking_number character varying(100),
    created_dstamp timestamp with time zone DEFAULT now() NOT NULL,
    closed_dstamp timestamp with time zone,
    delivery_class character varying(30),
    carrier_cost numeric(12,2),
    carrier_selection_source character varying(30),
    carrier_selection_rule_id bigint,
    carrier_selected_dstamp timestamp with time zone,
    carrier_override_reason character varying(250),
    fulfilment_method character varying(30),
    hold_status character varying(30) DEFAULT 'NONE'::character varying NOT NULL,
    hold_reason character varying(250),
    hold_dstamp timestamp with time zone,
    hold_source character varying(30),
    release_dstamp timestamp with time zone,
    released_by character varying(20),
    merged_into_container_id character varying(80),
    merged_dstamp timestamp with time zone,
    merged_by character varying(20),
    merge_rule_id bigint
);


--
-- Name: order_header; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.order_header (
    client_id character varying(10) NOT NULL,
    order_id character varying(20) NOT NULL,
    order_type character varying(10),
    status character varying(15),
    priority numeric(4,0),
    consignment character varying(20),
    delivery_point character varying(15),
    from_site_id character varying(10),
    to_site_id character varying(10),
    owner_id character varying(10),
    customer_id character varying(15),
    order_date timestamp with time zone NOT NULL,
    ship_by_date timestamp with time zone,
    deliver_by_date timestamp with time zone,
    shipped_date timestamp with time zone,
    delivered_dstamp timestamp with time zone,
    signatory character varying(25),
    purchase_order character varying(25),
    carrier_id character varying(25),
    dispatch_method character varying(40),
    service_level character varying(40),
    inv_address_id character varying(15),
    inv_contact character varying(25),
    inv_contact_phone character varying(25),
    inv_contact_mobile character varying(25),
    inv_contact_email character varying(256),
    inv_name character varying(50),
    inv_address1 character varying(60),
    inv_address2 character varying(60),
    inv_town character varying(60),
    inv_county character varying(60),
    inv_postcode character varying(20),
    inv_country character varying(25),
    instructions character varying(180),
    order_volume numeric(15,6),
    order_weight numeric(15,6),
    contact character varying(25),
    contact_phone character varying(25),
    contact_mobile character varying(25),
    contact_email character varying(256),
    name character varying(50),
    address1 character varying(60),
    address2 character varying(60),
    town character varying(60),
    county character varying(60),
    postcode character varying(20),
    country character varying(25),
    no_shipment_email character varying(1),
    order_source character varying(1),
    num_lines numeric(6,0),
    created_by character varying(20),
    creation_date timestamp with time zone,
    last_updated_by character varying(20),
    last_update_date timestamp with time zone,
    status_reason_code character varying(10),
    archived character varying(1),
    closure_date timestamp with time zone,
    order_closed character varying(1),
    order_value numeric(12,3),
    expected_volume numeric(15,6),
    expected_weight numeric(15,6),
    expected_value numeric(12,3),
    language character varying(8),
    vat_number character varying(20),
    inv_vat_number character varying(20),
    inv_reference character varying(35),
    inv_dstamp timestamp with time zone,
    inv_currency character varying(3),
    payment_terms character varying(35),
    subtotal_1 numeric(12,3),
    freight_cost numeric(12,3),
    discount numeric(12,3),
    tax_rate_1 numeric(12,3),
    tax_amount_1 numeric(12,3),
    order_reference character varying(35),
    packing_notes character varying(200),
    payment_status character varying(20),
    payment_method character varying(30),
    payment_reference character varying(120),
    payment_dstamp timestamp with time zone,
    fulfilment_status character varying(30),
    promo_code character varying(50),
    free_delivery character(1) NOT NULL,
    delivery_distance_miles numeric(8,2),
    fulfilment_preference character varying(30) DEFAULT 'CONSOLIDATE'::character varying NOT NULL,
    account_id uuid,
    payment_due_dstamp timestamp with time zone
);


--
-- Name: COLUMN order_header.client_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_header.client_id IS 'KEEP: Client/business identifier';


--
-- Name: COLUMN order_header.order_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_header.order_id IS 'KEEP: Order identifier';


--
-- Name: COLUMN order_header.order_type; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_header.order_type IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN order_header.status; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_header.status IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN order_header.priority; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_header.priority IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN order_header.consignment; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_header.consignment IS 'KEEP: Internal consignment reference';


--
-- Name: COLUMN order_header.delivery_point; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_header.delivery_point IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN order_header.from_site_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_header.from_site_id IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN order_header.to_site_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_header.to_site_id IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN order_header.owner_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_header.owner_id IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN order_header.customer_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_header.customer_id IS 'KEEP: Customer identifier';


--
-- Name: COLUMN order_header.order_date; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_header.order_date IS 'KEEP: Audit/operational timestamp';


--
-- Name: COLUMN order_header.ship_by_date; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_header.ship_by_date IS 'KEEP: Audit/operational timestamp';


--
-- Name: COLUMN order_header.deliver_by_date; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_header.deliver_by_date IS 'KEEP: Audit/operational timestamp';


--
-- Name: COLUMN order_header.shipped_date; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_header.shipped_date IS 'KEEP: Audit/operational timestamp';


--
-- Name: COLUMN order_header.delivered_dstamp; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_header.delivered_dstamp IS 'KEEP: Audit/operational timestamp';


--
-- Name: COLUMN order_header.signatory; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_header.signatory IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN order_header.purchase_order; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_header.purchase_order IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN order_header.carrier_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_header.carrier_id IS 'KEEP: Carrier identifier';


--
-- Name: COLUMN order_header.dispatch_method; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_header.dispatch_method IS 'KEEP: Dispatch method';


--
-- Name: COLUMN order_header.service_level; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_header.service_level IS 'KEEP: Carrier/service level';


--
-- Name: COLUMN order_header.inv_address_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_header.inv_address_id IS 'KEEP: Customer/billing/delivery address snapshot';


--
-- Name: COLUMN order_header.inv_contact; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_header.inv_contact IS 'KEEP: Invoice/billing information';


--
-- Name: COLUMN order_header.inv_contact_phone; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_header.inv_contact_phone IS 'KEEP: Invoice/billing information';


--
-- Name: COLUMN order_header.inv_contact_mobile; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_header.inv_contact_mobile IS 'KEEP: Invoice/billing information';


--
-- Name: COLUMN order_header.inv_contact_email; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_header.inv_contact_email IS 'KEEP: Invoice/billing information';


--
-- Name: COLUMN order_header.inv_name; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_header.inv_name IS 'KEEP: Invoice/billing information';


--
-- Name: COLUMN order_header.inv_address1; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_header.inv_address1 IS 'KEEP: Customer/billing/delivery address snapshot';


--
-- Name: COLUMN order_header.inv_address2; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_header.inv_address2 IS 'KEEP: Customer/billing/delivery address snapshot';


--
-- Name: COLUMN order_header.inv_town; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_header.inv_town IS 'KEEP: Invoice/billing information';


--
-- Name: COLUMN order_header.inv_county; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_header.inv_county IS 'KEEP: Invoice/billing information';


--
-- Name: COLUMN order_header.inv_postcode; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_header.inv_postcode IS 'KEEP: Invoice/billing information';


--
-- Name: COLUMN order_header.inv_country; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_header.inv_country IS 'KEEP: Invoice/billing information';


--
-- Name: COLUMN order_header.instructions; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_header.instructions IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN order_header.order_volume; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_header.order_volume IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN order_header.order_weight; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_header.order_weight IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN order_header.contact; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_header.contact IS 'KEEP: Customer/billing/delivery address snapshot';


--
-- Name: COLUMN order_header.contact_phone; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_header.contact_phone IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN order_header.contact_mobile; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_header.contact_mobile IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN order_header.contact_email; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_header.contact_email IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN order_header.name; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_header.name IS 'KEEP: Customer/billing/delivery address snapshot';


--
-- Name: COLUMN order_header.address1; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_header.address1 IS 'KEEP: Customer/billing/delivery address snapshot';


--
-- Name: COLUMN order_header.address2; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_header.address2 IS 'KEEP: Customer/billing/delivery address snapshot';


--
-- Name: COLUMN order_header.town; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_header.town IS 'KEEP: Customer/billing/delivery address snapshot';


--
-- Name: COLUMN order_header.county; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_header.county IS 'KEEP: Customer/billing/delivery address snapshot';


--
-- Name: COLUMN order_header.postcode; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_header.postcode IS 'KEEP: Customer/billing/delivery address snapshot';


--
-- Name: COLUMN order_header.country; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_header.country IS 'KEEP: Customer/billing/delivery address snapshot';


--
-- Name: COLUMN order_header.no_shipment_email; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_header.no_shipment_email IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN order_header.order_source; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_header.order_source IS 'KEEP: Order source e.g. WEB/FACEBOOK/MANUAL';


--
-- Name: COLUMN order_header.num_lines; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_header.num_lines IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN order_header.created_by; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_header.created_by IS 'KEEP: Audit field';


--
-- Name: COLUMN order_header.creation_date; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_header.creation_date IS 'KEEP: Audit/operational timestamp';


--
-- Name: COLUMN order_header.last_updated_by; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_header.last_updated_by IS 'KEEP: Audit field';


--
-- Name: COLUMN order_header.last_update_date; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_header.last_update_date IS 'KEEP: Audit/operational timestamp';


--
-- Name: COLUMN order_header.status_reason_code; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_header.status_reason_code IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN order_header.archived; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_header.archived IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN order_header.closure_date; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_header.closure_date IS 'KEEP: Audit/operational timestamp';


--
-- Name: COLUMN order_header.order_closed; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_header.order_closed IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN order_header.order_value; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_header.order_value IS 'KEEP: Commercial value captured for order';


--
-- Name: COLUMN order_header.expected_volume; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_header.expected_volume IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN order_header.expected_weight; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_header.expected_weight IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN order_header.expected_value; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_header.expected_value IS 'KEEP: Commercial value captured for order';


--
-- Name: COLUMN order_header.language; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_header.language IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN order_header.vat_number; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_header.vat_number IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN order_header.inv_vat_number; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_header.inv_vat_number IS 'KEEP: Invoice/billing information';


--
-- Name: COLUMN order_header.inv_reference; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_header.inv_reference IS 'KEEP: Invoice/billing information';


--
-- Name: COLUMN order_header.inv_dstamp; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_header.inv_dstamp IS 'KEEP: Audit/operational timestamp';


--
-- Name: COLUMN order_header.inv_currency; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_header.inv_currency IS 'KEEP: Invoice/billing information';


--
-- Name: COLUMN order_header.payment_terms; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_header.payment_terms IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN order_header.subtotal_1; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_header.subtotal_1 IS 'KEEP: Commercial value captured for order';


--
-- Name: COLUMN order_header.freight_cost; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_header.freight_cost IS 'KEEP: Delivery/freight charge/cost';


--
-- Name: COLUMN order_header.discount; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_header.discount IS 'KEEP: Commercial value captured for order';


--
-- Name: COLUMN order_header.tax_rate_1; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_header.tax_rate_1 IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN order_header.tax_amount_1; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_header.tax_amount_1 IS 'KEEP: Commercial value captured for order';


--
-- Name: COLUMN order_header.order_reference; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_header.order_reference IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN order_header.packing_notes; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_header.packing_notes IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN order_header.payment_status; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_header.payment_status IS 'ADD: Payment state';


--
-- Name: COLUMN order_header.payment_method; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_header.payment_method IS 'ADD: Payment method';


--
-- Name: COLUMN order_header.payment_reference; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_header.payment_reference IS 'ADD: Stripe/provider payment reference';


--
-- Name: COLUMN order_header.payment_dstamp; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_header.payment_dstamp IS 'ADD: When payment completed';


--
-- Name: COLUMN order_header.fulfilment_status; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_header.fulfilment_status IS 'ADD: Overall fulfilment state';


--
-- Name: COLUMN order_header.promo_code; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_header.promo_code IS 'ADD: Promotion code used';


--
-- Name: COLUMN order_header.free_delivery; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_header.free_delivery IS 'ADD: Whether delivery charge was waived';


--
-- Name: COLUMN order_header.delivery_distance_miles; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_header.delivery_distance_miles IS 'ADD: Calculated distance used for local delivery pricing';


--
-- Name: carrier_selection_workbench; Type: VIEW; Schema: core; Owner: -
--

CREATE VIEW core.carrier_selection_workbench AS
 SELECT oc.client_id,
    oc.order_id,
    oc.container_id,
    oc.status AS container_status,
    oc.delivery_class,
    oc.weight,
    oc.volume,
    oh.order_value,
    oh.dispatch_method,
    oh.service_level AS requested_service_level,
    oh.postcode,
    oh.country,
    oc.carrier_id,
    oc.service_level AS selected_service_level,
    oc.carrier_cost,
    oc.carrier_selection_source,
    oc.carrier_selection_rule_id,
    oc.carrier_selected_dstamp,
    oc.carrier_override_reason,
        CASE
            WHEN (oc.carrier_id IS NULL) THEN 'NEEDS_SELECTION'::text
            WHEN ((oc.carrier_selection_source)::text = 'MANUAL_OVERRIDE'::text) THEN 'OVERRIDDEN'::text
            ELSE 'SELECTED'::text
        END AS selection_status
   FROM (core.order_container oc
     JOIN core.order_header oh ON ((((oh.client_id)::text = (oc.client_id)::text) AND ((oh.order_id)::text = (oc.order_id)::text))))
  WHERE ((oc.status)::text <> 'SHIPPED'::text);


--
-- Name: client; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.client (
    client_id character varying(30) NOT NULL,
    description character varying(100) NOT NULL,
    active boolean DEFAULT true NOT NULL,
    created_dstamp timestamp with time zone DEFAULT now() NOT NULL,
    last_updated_dstamp timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: contact_preference; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.contact_preference (
    contact_preference_id uuid DEFAULT gen_random_uuid() NOT NULL,
    client_id character varying(30) NOT NULL,
    customer_id character varying(15),
    contact_type character varying(20) NOT NULL,
    contact_value character varying(254) NOT NULL,
    channel character varying(20) NOT NULL,
    purpose character varying(30) NOT NULL,
    opted_in boolean NOT NULL,
    consent_dstamp timestamp with time zone DEFAULT now() NOT NULL,
    last_update_dstamp timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT ck_contact_preference_channel CHECK (((channel)::text = ANY ((ARRAY['EMAIL'::character varying, 'SMS'::character varying, 'WHATSAPP'::character varying])::text[]))),
    CONSTRAINT ck_contact_preference_purpose CHECK (((purpose)::text = ANY ((ARRAY['MARKETING'::character varying, 'STOCK_ALERT'::character varying, 'TRANSACTIONAL'::character varying])::text[])))
);


--
-- Name: container_merge_candidate_workbench; Type: VIEW; Schema: core; Owner: -
--

CREATE VIEW core.container_merge_candidate_workbench AS
 SELECT a.client_id,
    a.order_id,
    a.container_id AS left_container_id,
    b.container_id AS right_container_id,
    a.delivery_class AS left_delivery_class,
    b.delivery_class AS right_delivery_class,
    a.fulfilment_method AS left_fulfilment_method,
    b.fulfilment_method AS right_fulfilment_method,
    a.hold_status AS left_hold_status,
    b.hold_status AS right_hold_status,
    (COALESCE(a.weight, (0)::numeric) + COALESCE(b.weight, (0)::numeric)) AS combined_weight,
    (COALESCE(a.volume, (0)::numeric) + COALESCE(b.volume, (0)::numeric)) AS combined_volume,
    oh.fulfilment_preference,
    e.result_allowed AS merge_allowed,
    e.result_rule_id AS merge_rule_id,
    e.result_rule_name AS merge_rule_name,
    e.result_reason AS merge_reason
   FROM (((core.order_container a
     JOIN core.order_container b ON ((((b.client_id)::text = (a.client_id)::text) AND ((b.order_id)::text = (a.order_id)::text) AND ((b.container_id)::text > (a.container_id)::text))))
     JOIN core.order_header oh ON ((((oh.client_id)::text = (a.client_id)::text) AND ((oh.order_id)::text = (a.order_id)::text))))
     CROSS JOIN LATERAL core.evaluate_container_merge(a.client_id, a.container_id, b.container_id) e(result_status, result_allowed, result_rule_id, result_rule_name, result_reason))
  WHERE ((upper((COALESCE(a.status, ''::character varying))::text) <> ALL (ARRAY['SHIPPED'::text, 'MERGED'::text, 'CANCELLED'::text])) AND (upper((COALESCE(b.status, ''::character varying))::text) <> ALL (ARRAY['SHIPPED'::text, 'MERGED'::text, 'CANCELLED'::text])));


--
-- Name: customer_account; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.customer_account (
    account_id uuid DEFAULT gen_random_uuid() NOT NULL,
    client_id character varying(30) NOT NULL,
    customer_id character varying(15),
    auth_provider character varying(50) NOT NULL,
    auth_subject character varying(200) NOT NULL,
    email character varying(254) NOT NULL,
    email_verified boolean DEFAULT false NOT NULL,
    active boolean DEFAULT true NOT NULL,
    created_dstamp timestamp with time zone DEFAULT now() NOT NULL,
    last_login_dstamp timestamp with time zone
);


--
-- Name: customer_account_address; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.customer_account_address (
    account_id uuid NOT NULL,
    client_id character varying(30) NOT NULL,
    address_id character varying(15) NOT NULL,
    address_label character varying(50),
    default_delivery boolean DEFAULT false NOT NULL,
    default_billing boolean DEFAULT false NOT NULL,
    active boolean DEFAULT true NOT NULL,
    created_dstamp timestamp with time zone DEFAULT now() NOT NULL,
    last_update_dstamp timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: customer_interest; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.customer_interest (
    interest_id uuid DEFAULT gen_random_uuid() NOT NULL,
    client_id character varying(30) NOT NULL,
    interest_type character varying(30) NOT NULL,
    product_id character varying(50) NOT NULL,
    sku_id character varying(50),
    requested_qty numeric(15,6),
    contact_name character varying(100),
    email character varying(254) NOT NULL,
    phone character varying(40),
    preferred_channel character varying(20) DEFAULT 'EMAIL'::character varying NOT NULL,
    consent_to_notify boolean DEFAULT true NOT NULL,
    status character varying(30) DEFAULT 'ACTIVE'::character varying NOT NULL,
    notified_dstamp timestamp with time zone,
    converted_order_id character varying(20),
    created_dstamp timestamp with time zone DEFAULT now() NOT NULL,
    last_update_dstamp timestamp with time zone DEFAULT now() NOT NULL,
    account_id uuid,
    CONSTRAINT ck_customer_interest_channel CHECK (((preferred_channel)::text = ANY ((ARRAY['EMAIL'::character varying, 'SMS'::character varying, 'WHATSAPP'::character varying])::text[]))),
    CONSTRAINT ck_customer_interest_status CHECK (((status)::text = ANY ((ARRAY['ACTIVE'::character varying, 'NOTIFIED'::character varying, 'CONVERTED'::character varying, 'CLOSED'::character varying])::text[]))),
    CONSTRAINT ck_customer_interest_type CHECK (((interest_type)::text = ANY ((ARRAY['WAITLIST'::character varying, 'GROWING_STOCK'::character varying])::text[])))
);


--
-- Name: delivery_hold_workbench; Type: VIEW; Schema: core; Owner: -
--

CREATE VIEW core.delivery_hold_workbench AS
 SELECT oc.client_id,
    oc.order_id,
    oc.container_id,
    oc.delivery_class,
    oc.fulfilment_method,
    oc.status AS container_status,
    oc.hold_status,
    oc.hold_reason,
    oc.hold_source,
    oc.hold_dstamp,
    oc.release_dstamp,
    oc.released_by,
    oh.fulfilment_preference,
    oh.customer_id,
    oh.postcode,
    oh.country
   FROM (core.order_container oc
     JOIN core.order_header oh ON ((((oh.client_id)::text = (oc.client_id)::text) AND ((oh.order_id)::text = (oc.order_id)::text))))
  WHERE (((oc.hold_status)::text <> 'NONE'::text) OR (upper((COALESCE(oc.delivery_class, 'STANDARD'::character varying))::text) = 'LIVESTOCK'::text));


--
-- Name: gift_card; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.gift_card (
    gift_card_id uuid DEFAULT gen_random_uuid() NOT NULL,
    client_id character varying(30) NOT NULL,
    gift_code character varying(100) NOT NULL,
    currency character varying(3) DEFAULT 'GBP'::character varying NOT NULL,
    original_value numeric(12,2) NOT NULL,
    balance numeric(12,2) NOT NULL,
    status character varying(30) DEFAULT 'ACTIVE'::character varying NOT NULL,
    expires_dstamp timestamp with time zone,
    created_dstamp timestamp with time zone DEFAULT now() NOT NULL,
    last_update_dstamp timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT ck_gift_card_balance CHECK ((balance >= (0)::numeric)),
    CONSTRAINT ck_gift_card_status CHECK (((status)::text = ANY ((ARRAY['ACTIVE'::character varying, 'SPENT'::character varying, 'CANCELLED'::character varying, 'EXPIRED'::character varying])::text[])))
);


--
-- Name: inventory_availability; Type: VIEW; Schema: core; Owner: -
--

CREATE VIEW core.inventory_availability AS
 SELECT i.key AS inventory_key,
    i.client_id,
    i.sku_id,
    i.site_id,
    i.location_id,
    i.owner_id,
    i.batch_id,
    i.condition_id,
    i.lock_status,
    i.disallow_alloc,
    i.qty_on_hand,
    i.qty_allocated,
    (i.qty_on_hand - i.qty_allocated) AS qty_available,
    i.receipt_dstamp,
    i.expiry_dstamp,
    l.active AS location_active,
    l.lock_status AS location_lock_status,
    l.disallow_alloc AS location_disallow_alloc,
        CASE
            WHEN (upper((COALESCE(i.disallow_alloc, 'N'::character varying))::text) = 'Y'::text) THEN 'N'::text
            WHEN (upper((COALESCE(i.lock_status, ''::character varying))::text) = ANY (ARRAY['LOCKED'::text, 'HOLD'::text, 'QUARANTINE'::text])) THEN 'N'::text
            WHEN (upper((COALESCE(l.disallow_alloc, 'N'::character varying))::text) = 'Y'::text) THEN 'N'::text
            WHEN (upper((COALESCE(l.lock_status, ''::character varying))::text) = ANY (ARRAY['LOCKED'::text, 'HOLD'::text, 'QUARANTINE'::text])) THEN 'N'::text
            WHEN (upper((COALESCE(l.active, 'Y'::bpchar))::text) <> 'Y'::text) THEN 'N'::text
            WHEN ((i.qty_on_hand - i.qty_allocated) <= (0)::numeric) THEN 'N'::text
            ELSE 'Y'::text
        END AS allocatable
   FROM (core.inventory i
     JOIN core.location l ON (((l.location_id)::text = (i.location_id)::text)));


--
-- Name: VIEW inventory_availability; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON VIEW core.inventory_availability IS 'Operational availability view: QTY_ON_HAND minus QTY_ALLOCATED plus allocatable status.';


--
-- Name: inventory_key_seq; Type: SEQUENCE; Schema: core; Owner: -
--

ALTER TABLE core.inventory ALTER COLUMN key ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME core.inventory_key_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: inventory_reservation_reconciliation; Type: VIEW; Schema: core; Owner: -
--

CREATE VIEW core.inventory_reservation_reconciliation AS
 SELECT i.key AS inventory_key,
    i.client_id,
    i.sku_id,
    i.location_id,
    i.qty_on_hand,
    i.qty_allocated,
    COALESCE(sum(GREATEST((0)::numeric, ((a.qty_allocated - a.qty_picked) - a.qty_released))), (0)::numeric) AS expected_qty_allocated,
    (i.qty_allocated - COALESCE(sum(GREATEST((0)::numeric, ((a.qty_allocated - a.qty_picked) - a.qty_released))), (0)::numeric)) AS reservation_difference,
        CASE
            WHEN (i.qty_allocated = COALESCE(sum(GREATEST((0)::numeric, ((a.qty_allocated - a.qty_picked) - a.qty_released))), (0)::numeric)) THEN 'OK'::text
            ELSE 'MISMATCH'::text
        END AS reconciliation_status
   FROM (core.inventory i
     LEFT JOIN core.allocation a ON ((a.inventory_key = i.key)))
  GROUP BY i.key, i.client_id, i.sku_id, i.location_id, i.qty_on_hand, i.qty_allocated;


--
-- Name: inventory_transaction; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.inventory_transaction (
    key bigint NOT NULL,
    code character varying(40) NOT NULL,
    site_id character varying(10),
    from_site_id character varying(10),
    to_site_id character varying(10),
    from_loc_id character varying(20),
    to_loc_id character varying(20),
    final_loc_id character varying(20),
    owner_id character varying(10),
    client_id character varying(10),
    sku_id character varying(50),
    tag_id character varying(50),
    container_id character varying(50),
    batch_id character varying(50),
    qc_status character varying(20),
    expiry_dstamp timestamp with time zone,
    manuf_dstamp timestamp with time zone,
    origin_id character varying(10),
    condition_id character varying(10),
    lock_status character varying(20),
    dstamp timestamp with time zone NOT NULL,
    consignment character varying(20),
    supplier_id character varying(15),
    reference_id character varying(20),
    line_id numeric(6,0),
    reason_id character varying(10),
    station_id character varying(256) NOT NULL,
    user_id character varying(20) NOT NULL,
    update_qty numeric(15,6) NOT NULL,
    original_qty numeric(15,6),
    complete_dstamp timestamp with time zone,
    notes character varying(400),
    lock_code character varying(10),
    customer_id character varying(15),
    shipment_number numeric(10,0),
    from_status character varying(15),
    to_status character varying(15),
    source character varying(30),
    reference_type character varying(30)
);


--
-- Name: inventory_transaction_key_seq; Type: SEQUENCE; Schema: core; Owner: -
--

ALTER TABLE core.inventory_transaction ALTER COLUMN key ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME core.inventory_transaction_key_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: kit_header; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.kit_header (
    client_id character varying(30) NOT NULL,
    kit_id character varying(50) NOT NULL,
    kit_sku_id character varying(50) NOT NULL,
    kit_type character varying(30) DEFAULT 'MANUFACTURE'::character varying NOT NULL,
    description character varying(150),
    active boolean DEFAULT true NOT NULL,
    created_dstamp timestamp with time zone DEFAULT now() NOT NULL,
    last_updated_dstamp timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: kit_line; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.kit_line (
    client_id character varying(30) NOT NULL,
    kit_id character varying(50) NOT NULL,
    line_id integer NOT NULL,
    component_sku_id character varying(50) NOT NULL,
    qty numeric(18,6) NOT NULL,
    sequence integer DEFAULT 100 NOT NULL,
    optional_component boolean DEFAULT false NOT NULL,
    show_as_replacement boolean DEFAULT false NOT NULL,
    active boolean DEFAULT true NOT NULL,
    created_dstamp timestamp with time zone DEFAULT now() NOT NULL,
    last_updated_dstamp timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: location_zone; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.location_zone (
    client_id character varying(30) NOT NULL,
    site_id character varying(30) NOT NULL,
    zone_id character varying(50) NOT NULL,
    description character varying(120) NOT NULL,
    zone_type character varying(30),
    pick_sequence integer,
    putaway_sequence integer,
    active boolean DEFAULT true NOT NULL,
    created_dstamp timestamp with time zone DEFAULT now() NOT NULL,
    last_updated_dstamp timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: merge_decision_explanation; Type: VIEW; Schema: core; Owner: -
--

CREATE VIEW core.merge_decision_explanation AS
 SELECT decision_id,
    client_id,
    entity_id AS source_container_id,
    rule_id,
    rule_name,
    decision,
    reason,
    detail,
    created_dstamp
   FROM audit.rule_decision_log
  WHERE ((engine_name)::text = 'CONTAINER_MERGE'::text);


--
-- Name: mixed_order_fulfilment_workbench; Type: VIEW; Schema: core; Owner: -
--

CREATE VIEW core.mixed_order_fulfilment_workbench AS
 WITH x AS (
         SELECT oh.client_id,
            oh.order_id,
            oh.fulfilment_preference,
            count(*) AS container_count,
            count(*) FILTER (WHERE (upper((COALESCE(oc.delivery_class, 'STANDARD'::character varying))::text) = 'LIVESTOCK'::text)) AS livestock_containers,
            count(*) FILTER (WHERE (upper((COALESCE(oc.delivery_class, 'STANDARD'::character varying))::text) <> 'LIVESTOCK'::text)) AS non_live_containers,
            count(*) FILTER (WHERE ((oc.hold_status)::text <> 'NONE'::text)) AS held_containers,
            count(*) FILTER (WHERE ((upper((COALESCE(oc.delivery_class, 'STANDARD'::character varying))::text) <> 'LIVESTOCK'::text) AND ((oc.hold_status)::text = 'NONE'::text) AND ((oc.status)::text = ANY ((ARRAY['PACKED'::character varying, 'READY_TO_SHIP'::character varying, 'OPEN'::character varying])::text[])))) AS non_live_ready
           FROM (core.order_header oh
             JOIN core.order_container oc ON ((((oc.client_id)::text = (oh.client_id)::text) AND ((oc.order_id)::text = (oh.order_id)::text))))
          GROUP BY oh.client_id, oh.order_id, oh.fulfilment_preference
        )
 SELECT client_id,
    order_id,
    fulfilment_preference,
    container_count,
    livestock_containers,
    non_live_containers,
    held_containers,
    non_live_ready,
        CASE
            WHEN ((livestock_containers > 0) AND (non_live_containers > 0) AND ((fulfilment_preference)::text = 'SPLIT_WHEN_REQUIRED'::text) AND (non_live_ready > 0)) THEN 'RELEASE_NON_LIVE'::text
            WHEN ((livestock_containers > 0) AND (non_live_containers > 0) AND ((fulfilment_preference)::text = 'CONSOLIDATE'::text)) THEN 'HOLD_FOR_COMBINED_DELIVERY'::text
            WHEN (held_containers > 0) THEN 'REVIEW_HOLD'::text
            ELSE 'NORMAL_FULFILMENT'::text
        END AS recommended_action
   FROM x;


--
-- Name: order_container_container_key_seq; Type: SEQUENCE; Schema: core; Owner: -
--

ALTER TABLE core.order_container ALTER COLUMN container_key ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME core.order_container_container_key_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: order_line; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.order_line (
    client_id character varying(10) NOT NULL,
    order_id character varying(20) NOT NULL,
    line_id numeric(6,0) NOT NULL,
    sku_id character varying(50) NOT NULL,
    batch_id character varying(50),
    condition_id character varying(10),
    qty_ordered numeric(15,6) NOT NULL,
    qty_tasked numeric(15,6),
    qty_picked numeric(15,6),
    qty_shipped numeric(15,6),
    qty_delivered numeric(15,6),
    qty_returned numeric(15,6),
    qty_soft_allocated numeric(15,6),
    allocate character varying(1),
    back_ordered character varying(1),
    created_by character varying(20),
    creation_date timestamp with time zone,
    last_updated_by character varying(20),
    last_update_date timestamp with time zone,
    line_value numeric(12,3),
    notes character varying(80),
    min_qty_ordered numeric(15,6),
    max_qty_ordered numeric(15,6),
    expected_volume numeric(15,6),
    expected_weight numeric(15,6),
    expected_value numeric(12,3),
    product_price numeric(12,3),
    product_currency character varying(3),
    extended_price numeric(12,3),
    tax_1 numeric(12,3),
    tax_2 numeric(12,3),
    owner_id character varying(10),
    location_id character varying(20),
    fulfilment_type character varying(20),
    supplier_id character varying(30),
    unit_cost numeric(12,2),
    discount_value numeric(12,2),
    vat_rate numeric(5,2),
    external_fulfilment_ref character varying(120)
);


--
-- Name: COLUMN order_line.client_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_line.client_id IS 'KEEP: Client/business identifier';


--
-- Name: COLUMN order_line.order_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_line.order_id IS 'KEEP: Order identifier';


--
-- Name: COLUMN order_line.line_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_line.line_id IS 'KEEP: Order line number';


--
-- Name: COLUMN order_line.sku_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_line.sku_id IS 'KEEP: Single FINatics SKU/product identifier';


--
-- Name: COLUMN order_line.batch_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_line.batch_id IS 'KEEP: Batch/spawn/lot identifier';


--
-- Name: COLUMN order_line.condition_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_line.condition_id IS 'KEEP: Inventory condition, useful for AVAILABLE/QUARANTINE etc.';


--
-- Name: COLUMN order_line.qty_ordered; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_line.qty_ordered IS 'KEEP: Quantity/status measure retained from WMS';


--
-- Name: COLUMN order_line.qty_tasked; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_line.qty_tasked IS 'KEEP: Quantity/status measure retained from WMS';


--
-- Name: COLUMN order_line.qty_picked; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_line.qty_picked IS 'KEEP: Quantity/status measure retained from WMS';


--
-- Name: COLUMN order_line.qty_shipped; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_line.qty_shipped IS 'KEEP: Quantity/status measure retained from WMS';


--
-- Name: COLUMN order_line.qty_delivered; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_line.qty_delivered IS 'KEEP: Quantity/status measure retained from WMS';


--
-- Name: COLUMN order_line.qty_returned; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_line.qty_returned IS 'KEEP: Quantity/status measure retained from WMS';


--
-- Name: COLUMN order_line.qty_soft_allocated; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_line.qty_soft_allocated IS 'KEEP: Quantity/status measure retained from WMS';


--
-- Name: COLUMN order_line.allocate; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_line.allocate IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN order_line.back_ordered; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_line.back_ordered IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN order_line.created_by; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_line.created_by IS 'KEEP: Audit field';


--
-- Name: COLUMN order_line.creation_date; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_line.creation_date IS 'KEEP: Audit/operational timestamp';


--
-- Name: COLUMN order_line.last_updated_by; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_line.last_updated_by IS 'KEEP: Audit field';


--
-- Name: COLUMN order_line.last_update_date; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_line.last_update_date IS 'KEEP: Audit/operational timestamp';


--
-- Name: COLUMN order_line.line_value; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_line.line_value IS 'KEEP: Commercial value captured for order';


--
-- Name: COLUMN order_line.notes; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_line.notes IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN order_line.min_qty_ordered; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_line.min_qty_ordered IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN order_line.max_qty_ordered; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_line.max_qty_ordered IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN order_line.expected_volume; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_line.expected_volume IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN order_line.expected_weight; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_line.expected_weight IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN order_line.expected_value; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_line.expected_value IS 'KEEP: Commercial value captured for order';


--
-- Name: COLUMN order_line.product_price; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_line.product_price IS 'KEEP: Unit sell price captured on the order line';


--
-- Name: COLUMN order_line.product_currency; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_line.product_currency IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN order_line.extended_price; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_line.extended_price IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN order_line.tax_1; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_line.tax_1 IS 'KEEP: Commercial value captured for order';


--
-- Name: COLUMN order_line.tax_2; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_line.tax_2 IS 'KEEP: Commercial value captured for order';


--
-- Name: COLUMN order_line.owner_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_line.owner_id IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN order_line.location_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_line.location_id IS 'KEEP: Inventory/location identifier';


--
-- Name: COLUMN order_line.fulfilment_type; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_line.fulfilment_type IS 'ADD: Actual fulfilment route for this line';


--
-- Name: COLUMN order_line.supplier_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_line.supplier_id IS 'ADD: Supplier used for direct fulfilment';


--
-- Name: COLUMN order_line.unit_cost; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_line.unit_cost IS 'ADD: Cost snapshot at order time';


--
-- Name: COLUMN order_line.discount_value; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_line.discount_value IS 'ADD: Line discount amount';


--
-- Name: COLUMN order_line.vat_rate; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_line.vat_rate IS 'ADD: VAT rate snapshot';


--
-- Name: COLUMN order_line.external_fulfilment_ref; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.order_line.external_fulfilment_ref IS 'ADD: Supplier/external reference where applicable';


--
-- Name: order_fulfilment_workbench; Type: VIEW; Schema: core; Owner: -
--

CREATE VIEW core.order_fulfilment_workbench AS
 SELECT oh.client_id,
    oh.order_id,
    oh.customer_id,
    oh.priority,
    oh.order_date,
    oh.ship_by_date,
    oh.dispatch_method,
    oh.carrier_id,
    oh.service_level,
    oh.fulfilment_status,
    count(ol.line_id) AS line_count,
    sum(ol.qty_ordered) AS qty_ordered,
    sum(COALESCE(ol.qty_soft_allocated, (0)::numeric)) AS qty_reserved,
    sum(COALESCE(ol.qty_picked, (0)::numeric)) AS qty_picked,
    sum(COALESCE(ol.qty_shipped, (0)::numeric)) AS qty_shipped,
        CASE
            WHEN (sum(COALESCE(ol.qty_shipped, (0)::numeric)) >= sum(ol.qty_ordered)) THEN 'SHIPPED'::text
            WHEN (sum(COALESCE(ol.qty_picked, (0)::numeric)) >= sum(ol.qty_ordered)) THEN 'READY_TO_PACK'::text
            WHEN (sum(COALESCE(ol.qty_picked, (0)::numeric)) > (0)::numeric) THEN 'PART_PICKED'::text
            WHEN (sum(COALESCE(ol.qty_soft_allocated, (0)::numeric)) >= sum(ol.qty_ordered)) THEN 'ALLOCATED'::text
            WHEN (sum(COALESCE(ol.qty_soft_allocated, (0)::numeric)) > (0)::numeric) THEN 'PART_ALLOCATED'::text
            ELSE 'UNALLOCATED'::text
        END AS derived_status
   FROM (core.order_header oh
     JOIN core.order_line ol ON ((((ol.client_id)::text = (oh.client_id)::text) AND ((ol.order_id)::text = (oh.order_id)::text))))
  GROUP BY oh.client_id, oh.order_id, oh.customer_id, oh.priority, oh.order_date, oh.ship_by_date, oh.dispatch_method, oh.carrier_id, oh.service_level, oh.fulfilment_status;


--
-- Name: payment_transaction; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.payment_transaction (
    payment_id uuid DEFAULT gen_random_uuid() NOT NULL,
    client_id character varying(30) NOT NULL,
    provider character varying(30) NOT NULL,
    reference_type character varying(30) NOT NULL,
    reference_id character varying(100) NOT NULL,
    provider_reference character varying(200),
    amount numeric(12,2) NOT NULL,
    currency character varying(3) DEFAULT 'GBP'::character varying NOT NULL,
    status character varying(30) DEFAULT 'CREATED'::character varying NOT NULL,
    idempotency_key character varying(100),
    failure_code character varying(100),
    failure_text character varying(500),
    created_dstamp timestamp with time zone DEFAULT now() NOT NULL,
    last_update_dstamp timestamp with time zone DEFAULT now() NOT NULL,
    account_id uuid,
    captured_amount numeric(12,2) DEFAULT 0 NOT NULL,
    refunded_amount numeric(12,2) DEFAULT 0 NOT NULL,
    provider_status character varying(50),
    last_event_type character varying(100),
    last_event_dstamp timestamp with time zone,
    CONSTRAINT ck_payment_provider CHECK (((provider)::text = ANY ((ARRAY['STRIPE'::character varying, 'PAYPAL'::character varying])::text[]))),
    CONSTRAINT ck_payment_reference_type CHECK (((reference_type)::text = ANY ((ARRAY['ORDER'::character varying, 'RESERVATION'::character varying, 'GIFT_CARD'::character varying])::text[]))),
    CONSTRAINT ck_payment_status CHECK (((status)::text = ANY ((ARRAY['CREATED'::character varying, 'PENDING'::character varying, 'AUTHORISED'::character varying, 'PAID'::character varying, 'FAILED'::character varying, 'CANCELLED'::character varying, 'REFUNDED'::character varying, 'PART_REFUNDED'::character varying])::text[])))
);


--
-- Name: pick_task; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.pick_task (
    pick_task_id bigint NOT NULL,
    client_id character varying(10) NOT NULL,
    order_id character varying(20) NOT NULL,
    line_id numeric(6,0) NOT NULL,
    allocation_id bigint NOT NULL,
    inventory_key bigint NOT NULL,
    sku_id character varying(50) NOT NULL,
    location_id character varying(20) NOT NULL,
    batch_id character varying(50),
    qty_required numeric(15,6) NOT NULL,
    qty_picked numeric(15,6) DEFAULT 0 NOT NULL,
    short_qty numeric(15,6) DEFAULT 0 NOT NULL,
    status character varying(30) DEFAULT 'OPEN'::character varying NOT NULL,
    short_reason character varying(120),
    created_dstamp timestamp with time zone DEFAULT now() NOT NULL,
    started_dstamp timestamp with time zone,
    completed_dstamp timestamp with time zone,
    last_update_dstamp timestamp with time zone DEFAULT now() NOT NULL,
    created_by character varying(20) DEFAULT 'SYSTEM'::character varying NOT NULL,
    last_updated_by character varying(20) DEFAULT 'SYSTEM'::character varying NOT NULL,
    CONSTRAINT ck_pick_task_qty CHECK (((qty_required > (0)::numeric) AND (qty_picked >= (0)::numeric) AND (short_qty >= (0)::numeric) AND ((qty_picked + short_qty) <= qty_required)))
);


--
-- Name: TABLE pick_task; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.pick_task IS 'Minimal warehouse execution work: what order/line/SKU/inventory/location/quantity must be picked and its execution state.';


--
-- Name: pick_task_pick_task_id_seq; Type: SEQUENCE; Schema: core; Owner: -
--

ALTER TABLE core.pick_task ALTER COLUMN pick_task_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME core.pick_task_pick_task_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: pick_work_queue; Type: VIEW; Schema: core; Owner: -
--

CREATE VIEW core.pick_work_queue AS
 SELECT pt.pick_task_id,
    pt.client_id,
    pt.order_id,
    pt.line_id,
    pt.sku_id,
    pt.location_id,
    pt.batch_id,
    pt.qty_required,
    pt.qty_picked,
    pt.short_qty,
    GREATEST((0)::numeric, ((pt.qty_required - pt.qty_picked) - pt.short_qty)) AS qty_remaining,
    pt.status,
    pt.short_reason,
    pt.created_dstamp,
    pt.started_dstamp,
    pt.completed_dstamp,
    oh.priority,
    oh.ship_by_date,
    oh.deliver_by_date
   FROM (core.pick_task pt
     JOIN core.order_header oh ON ((((oh.client_id)::text = (pt.client_id)::text) AND ((oh.order_id)::text = (pt.order_id)::text))));


--
-- Name: pre_advice_header; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.pre_advice_header (
    client_id character varying(30) NOT NULL,
    pre_advice_id character varying(50) NOT NULL,
    site_id character varying(30) NOT NULL,
    supplier_id character varying(50),
    status character varying(30) DEFAULT 'EXPECTED'::character varying NOT NULL,
    supplier_reference character varying(100),
    carrier_reference character varying(100),
    due_dstamp timestamp with time zone,
    actual_dstamp timestamp with time zone,
    notes text,
    created_dstamp timestamp with time zone DEFAULT now() NOT NULL,
    last_updated_dstamp timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: pre_advice_line; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.pre_advice_line (
    client_id character varying(30) NOT NULL,
    pre_advice_id character varying(50) NOT NULL,
    line_id integer NOT NULL,
    sku_id character varying(50) NOT NULL,
    qty_due numeric(18,6) NOT NULL,
    qty_received numeric(18,6) DEFAULT 0 NOT NULL,
    batch_id character varying(80),
    expiry_dstamp timestamp with time zone,
    manuf_dstamp timestamp with time zone,
    condition_id character varying(30),
    notes text,
    created_dstamp timestamp with time zone DEFAULT now() NOT NULL,
    last_updated_dstamp timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: product_affiliate_link; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.product_affiliate_link (
    link_id uuid DEFAULT gen_random_uuid() NOT NULL,
    client_id character varying(30) NOT NULL,
    product_id character varying(50) NOT NULL,
    sku_id character varying(50),
    merchant_name character varying(100) NOT NULL,
    destination_url text NOT NULL,
    campaign_code character varying(100),
    active boolean DEFAULT true NOT NULL,
    sort_sequence integer DEFAULT 100 NOT NULL,
    created_dstamp timestamp with time zone DEFAULT now() NOT NULL,
    last_update_dstamp timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: product_favourite; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.product_favourite (
    account_id uuid NOT NULL,
    client_id character varying(30) NOT NULL,
    product_id character varying(50) NOT NULL,
    created_dstamp timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: product_group; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.product_group (
    product_group_id character varying(50) NOT NULL,
    client_id character varying(30) NOT NULL,
    parent_group_id character varying(50),
    description character varying(150) NOT NULL,
    display_sequence integer DEFAULT 100 NOT NULL,
    active boolean DEFAULT true NOT NULL,
    created_dstamp timestamp with time zone DEFAULT now() NOT NULL,
    last_updated_dstamp timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: product_media; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.product_media (
    media_id uuid DEFAULT gen_random_uuid() NOT NULL,
    client_id character varying(30) NOT NULL,
    product_id character varying(50) NOT NULL,
    sku_id character varying(50),
    media_type character varying(20) NOT NULL,
    media_role character varying(30) DEFAULT 'GALLERY'::character varying NOT NULL,
    media_url text NOT NULL,
    thumbnail_url text,
    alt_text character varying(300),
    caption character varying(500),
    sort_sequence integer DEFAULT 100 NOT NULL,
    active boolean DEFAULT true NOT NULL,
    created_dstamp timestamp with time zone DEFAULT now() NOT NULL,
    last_update_dstamp timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT ck_product_media_role CHECK (((media_role)::text = ANY ((ARRAY['HERO'::character varying, 'GALLERY'::character varying, 'REPRESENTATIVE'::character varying, 'CURRENT_STOCK'::character varying, 'HOVER'::character varying])::text[]))),
    CONSTRAINT ck_product_media_type CHECK (((media_type)::text = ANY ((ARRAY['IMAGE'::character varying, 'VIDEO'::character varying])::text[])))
);


--
-- Name: product_review; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.product_review (
    review_id uuid DEFAULT gen_random_uuid() NOT NULL,
    client_id character varying(30) NOT NULL,
    product_id character varying(50) NOT NULL,
    sku_id character varying(50),
    customer_id character varying(15),
    email character varying(254) NOT NULL,
    display_name character varying(100) NOT NULL,
    rating integer NOT NULL,
    review_title character varying(200),
    review_text text,
    verified_purchase boolean DEFAULT false NOT NULL,
    status character varying(30) DEFAULT 'PENDING'::character varying NOT NULL,
    created_dstamp timestamp with time zone DEFAULT now() NOT NULL,
    published_dstamp timestamp with time zone,
    CONSTRAINT ck_product_review_rating CHECK (((rating >= 1) AND (rating <= 5))),
    CONSTRAINT ck_product_review_status CHECK (((status)::text = ANY ((ARRAY['PENDING'::character varying, 'APPROVED'::character varying, 'REJECTED'::character varying])::text[])))
);


--
-- Name: product_search_alias; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.product_search_alias (
    search_alias_id bigint NOT NULL,
    client_id character varying(30) NOT NULL,
    product_id character varying(50) NOT NULL,
    alias_text character varying(250) NOT NULL,
    alias_type character varying(30) DEFAULT 'OTHER'::character varying NOT NULL,
    active boolean DEFAULT true NOT NULL,
    created_dstamp timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: product_search_alias_search_alias_id_seq; Type: SEQUENCE; Schema: core; Owner: -
--

ALTER TABLE core.product_search_alias ALTER COLUMN search_alias_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME core.product_search_alias_search_alias_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: shipping_manifest; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.shipping_manifest (
    key bigint NOT NULL,
    client_id character varying(10) NOT NULL,
    order_id character varying(20) NOT NULL,
    line_id numeric(6,0) NOT NULL,
    tag_id character varying(50),
    sku_id character varying(50) NOT NULL,
    batch_id character varying(50),
    expiry_dstamp timestamp with time zone,
    consignment character varying(20),
    container_id character varying(50),
    site_id character varying(10),
    location_id character varying(20) NOT NULL,
    owner_id character varying(10),
    qty_picked numeric(15,6),
    picked_dstamp timestamp with time zone NOT NULL,
    qty_shipped numeric(15,6),
    shipped_dstamp timestamp with time zone,
    shipped character varying(1) NOT NULL,
    qty_delivered numeric(15,6),
    delivered_dstamp timestamp with time zone,
    delivered character varying(1),
    pod_confirmed character varying(1),
    pod_exception_reason character varying(10),
    station_id character varying(256),
    user_id character varying(20),
    supplier_id character varying(15),
    origin_id character varying(10),
    condition_id character varying(10),
    lock_status character varying(20),
    lock_code character varying(10),
    notes character varying(80),
    customer_id character varying(15),
    shipment_number numeric(10,0),
    carrier_id character varying(25),
    service_level character varying(40),
    load_sequence numeric(10,0),
    carrier_container_id character varying(50),
    container_weight numeric(13,6),
    container_height numeric(13,6),
    container_width numeric(13,6),
    container_depth numeric(13,6),
    container_type character varying(15),
    container_n_of_n numeric(5,0),
    status character varying(15),
    customer_shipment_number numeric(10,0),
    shipment_group character varying(20),
    shipment_ref character varying(50),
    carrier_consignment_num numeric(3,0),
    carrier_consignment_id character varying(30),
    total_volume numeric(13,6),
    carrier_manifest_number character varying(20),
    transport_boxes numeric(4,0),
    dispatch_method character varying(30),
    tracking_number character varying(120),
    tracking_url text,
    tracking_status character varying(30),
    tracking_last_dstamp timestamp with time zone,
    dispatch_cost numeric(12,2),
    collected_dstamp timestamp with time zone,
    pod_name character varying(120),
    pod_image_url text,
    local_driver character varying(120),
    pick_task_id bigint,
    carrier_selection_rule_id bigint
);


--
-- Name: COLUMN shipping_manifest.key; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.shipping_manifest.key IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN shipping_manifest.client_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.shipping_manifest.client_id IS 'KEEP: Client/business identifier';


--
-- Name: COLUMN shipping_manifest.order_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.shipping_manifest.order_id IS 'KEEP: Order identifier';


--
-- Name: COLUMN shipping_manifest.line_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.shipping_manifest.line_id IS 'KEEP: Order line number';


--
-- Name: COLUMN shipping_manifest.tag_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.shipping_manifest.tag_id IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN shipping_manifest.sku_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.shipping_manifest.sku_id IS 'KEEP: Single FINatics SKU/product identifier';


--
-- Name: COLUMN shipping_manifest.batch_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.shipping_manifest.batch_id IS 'KEEP: Batch/spawn/lot identifier';


--
-- Name: COLUMN shipping_manifest.expiry_dstamp; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.shipping_manifest.expiry_dstamp IS 'KEEP: Audit/operational timestamp';


--
-- Name: COLUMN shipping_manifest.consignment; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.shipping_manifest.consignment IS 'KEEP: Internal consignment reference';


--
-- Name: COLUMN shipping_manifest.container_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.shipping_manifest.container_id IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN shipping_manifest.site_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.shipping_manifest.site_id IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN shipping_manifest.location_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.shipping_manifest.location_id IS 'KEEP: Inventory/location identifier';


--
-- Name: COLUMN shipping_manifest.owner_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.shipping_manifest.owner_id IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN shipping_manifest.qty_picked; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.shipping_manifest.qty_picked IS 'KEEP: Quantity/status measure retained from WMS';


--
-- Name: COLUMN shipping_manifest.picked_dstamp; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.shipping_manifest.picked_dstamp IS 'KEEP: Audit/operational timestamp';


--
-- Name: COLUMN shipping_manifest.qty_shipped; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.shipping_manifest.qty_shipped IS 'KEEP: Quantity/status measure retained from WMS';


--
-- Name: COLUMN shipping_manifest.shipped_dstamp; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.shipping_manifest.shipped_dstamp IS 'KEEP: Audit/operational timestamp';


--
-- Name: COLUMN shipping_manifest.shipped; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.shipping_manifest.shipped IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN shipping_manifest.qty_delivered; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.shipping_manifest.qty_delivered IS 'KEEP: Quantity/status measure retained from WMS';


--
-- Name: COLUMN shipping_manifest.delivered_dstamp; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.shipping_manifest.delivered_dstamp IS 'KEEP: Audit/operational timestamp';


--
-- Name: COLUMN shipping_manifest.delivered; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.shipping_manifest.delivered IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN shipping_manifest.pod_confirmed; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.shipping_manifest.pod_confirmed IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN shipping_manifest.pod_exception_reason; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.shipping_manifest.pod_exception_reason IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN shipping_manifest.station_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.shipping_manifest.station_id IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN shipping_manifest.user_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.shipping_manifest.user_id IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN shipping_manifest.supplier_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.shipping_manifest.supplier_id IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN shipping_manifest.origin_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.shipping_manifest.origin_id IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN shipping_manifest.condition_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.shipping_manifest.condition_id IS 'KEEP: Inventory condition, useful for AVAILABLE/QUARANTINE etc.';


--
-- Name: COLUMN shipping_manifest.lock_status; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.shipping_manifest.lock_status IS 'KEEP: Inventory/location hold state';


--
-- Name: COLUMN shipping_manifest.lock_code; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.shipping_manifest.lock_code IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN shipping_manifest.notes; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.shipping_manifest.notes IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN shipping_manifest.customer_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.shipping_manifest.customer_id IS 'KEEP: Customer identifier';


--
-- Name: COLUMN shipping_manifest.shipment_number; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.shipping_manifest.shipment_number IS 'KEEP: Shipment identifier';


--
-- Name: COLUMN shipping_manifest.carrier_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.shipping_manifest.carrier_id IS 'KEEP: Carrier identifier';


--
-- Name: COLUMN shipping_manifest.service_level; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.shipping_manifest.service_level IS 'KEEP: Carrier/service level';


--
-- Name: COLUMN shipping_manifest.load_sequence; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.shipping_manifest.load_sequence IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN shipping_manifest.carrier_container_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.shipping_manifest.carrier_container_id IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN shipping_manifest.container_weight; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.shipping_manifest.container_weight IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN shipping_manifest.container_height; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.shipping_manifest.container_height IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN shipping_manifest.container_width; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.shipping_manifest.container_width IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN shipping_manifest.container_depth; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.shipping_manifest.container_depth IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN shipping_manifest.container_type; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.shipping_manifest.container_type IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN shipping_manifest.container_n_of_n; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.shipping_manifest.container_n_of_n IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN shipping_manifest.status; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.shipping_manifest.status IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN shipping_manifest.customer_shipment_number; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.shipping_manifest.customer_shipment_number IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN shipping_manifest.shipment_group; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.shipping_manifest.shipment_group IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN shipping_manifest.shipment_ref; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.shipping_manifest.shipment_ref IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN shipping_manifest.carrier_consignment_num; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.shipping_manifest.carrier_consignment_num IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN shipping_manifest.carrier_consignment_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.shipping_manifest.carrier_consignment_id IS 'KEEP: Carrier consignment reference';


--
-- Name: COLUMN shipping_manifest.total_volume; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.shipping_manifest.total_volume IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN shipping_manifest.carrier_manifest_number; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.shipping_manifest.carrier_manifest_number IS 'KEEP: Carrier manifest reference';


--
-- Name: COLUMN shipping_manifest.transport_boxes; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.shipping_manifest.transport_boxes IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN shipping_manifest.dispatch_method; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.shipping_manifest.dispatch_method IS 'ADD: Dispatch route for this shipment/container';


--
-- Name: COLUMN shipping_manifest.tracking_number; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.shipping_manifest.tracking_number IS 'ADD: Carrier tracking number';


--
-- Name: COLUMN shipping_manifest.tracking_url; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.shipping_manifest.tracking_url IS 'ADD: Carrier/customer tracking link';


--
-- Name: COLUMN shipping_manifest.tracking_status; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.shipping_manifest.tracking_status IS 'ADD: Latest tracking state';


--
-- Name: COLUMN shipping_manifest.tracking_last_dstamp; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.shipping_manifest.tracking_last_dstamp IS 'ADD: When tracking state was last refreshed';


--
-- Name: COLUMN shipping_manifest.dispatch_cost; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.shipping_manifest.dispatch_cost IS 'ADD: Actual cost to FINatics to dispatch this shipment';


--
-- Name: COLUMN shipping_manifest.collected_dstamp; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.shipping_manifest.collected_dstamp IS 'ADD: Customer collection timestamp when method is collection';


--
-- Name: COLUMN shipping_manifest.pod_name; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.shipping_manifest.pod_name IS 'ADD: Name of recipient/collector';


--
-- Name: COLUMN shipping_manifest.pod_image_url; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.shipping_manifest.pod_image_url IS 'ADD: Optional proof-of-delivery image/reference';


--
-- Name: COLUMN shipping_manifest.local_driver; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.shipping_manifest.local_driver IS 'ADD: Driver/user for FINatics local deliveries';


--
-- Name: shipment_work_queue; Type: VIEW; Schema: core; Owner: -
--

CREATE VIEW core.shipment_work_queue AS
 SELECT oc.client_id,
    oc.order_id,
    oc.container_id,
    oc.status AS container_status,
    count(sm.key) AS manifest_rows,
    COALESCE(sum(sm.qty_picked), (0)::numeric) AS qty_packed,
    COALESCE(sum(sm.qty_shipped), (0)::numeric) AS qty_shipped,
    oc.carrier_id,
    oc.service_level,
    oc.tracking_number,
    oc.created_dstamp,
    oc.closed_dstamp
   FROM (core.order_container oc
     LEFT JOIN core.shipping_manifest sm ON ((((sm.client_id)::text = (oc.client_id)::text) AND ((sm.container_id)::text = (oc.container_id)::text))))
  GROUP BY oc.client_id, oc.order_id, oc.container_id, oc.status, oc.carrier_id, oc.service_level, oc.tracking_number, oc.created_dstamp, oc.closed_dstamp;


--
-- Name: shipping_manifest_key_seq; Type: SEQUENCE; Schema: core; Owner: -
--

ALTER TABLE core.shipping_manifest ALTER COLUMN key ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME core.shipping_manifest_key_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: site; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.site (
    site_id character varying(30) NOT NULL,
    client_id character varying(30) NOT NULL,
    description character varying(120) NOT NULL,
    site_type character varying(30) DEFAULT 'FULFILMENT'::character varying NOT NULL,
    address_id character varying(50),
    time_zone character varying(80),
    active boolean DEFAULT true NOT NULL,
    created_dstamp timestamp with time zone DEFAULT now() NOT NULL,
    last_updated_dstamp timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: sku; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.sku (
    client_id character varying(10) NOT NULL,
    sku_id character varying(50) NOT NULL,
    ean character varying(14),
    upc character varying(14),
    description character varying(80),
    product_group character varying(10),
    each_height numeric(15,6),
    each_weight numeric(13,6),
    each_volume numeric(13,6),
    each_value numeric(12,3),
    shelf_life numeric(5,0),
    expiry_reqd character varying(1),
    obsolete_product character varying(1),
    new_product character varying(1),
    colour character varying(20),
    sku_size character varying(10),
    each_width numeric(7,3),
    each_depth numeric(7,3),
    reorder_trigger_qty numeric(15,6),
    low_trigger_qty numeric(15,6),
    created_by character varying(20),
    creation_date timestamp with time zone,
    last_updated_by character varying(20),
    last_update_date timestamp with time zone,
    commodity_code character varying(22),
    family_group character varying(15),
    fragile character varying(1),
    ecommerce character varying(1),
    promotion character varying(1),
    style character varying(10),
    decatalogued character varying(1),
    hazmat character varying(1),
    sub_group character varying(30),
    category character varying(50),
    manufacturer_id character varying(30),
    manufacturer_sku character varying(80),
    brand_name character varying(80),
    preferred_supplier_id character varying(30),
    supplier_sku character varying(80),
    sell_price numeric(12,2),
    cost_price numeric(12,2),
    vat_rate numeric(5,2),
    web_title character varying(160),
    web_description text,
    web_slug character varying(180),
    web_active character(1) NOT NULL,
    web_featured character(1) NOT NULL,
    web_image_1 text,
    web_image_2 text,
    web_image_3 text,
    web_image_4 text,
    web_image_5 text,
    web_video_url text,
    fulfilment_type character varying(20),
    supplier_direct_enabled character(1) NOT NULL,
    affiliate_fallback character(1) NOT NULL,
    affiliate_url text,
    min_order_qty numeric(15,6),
    max_order_qty numeric(15,6),
    genus character varying(80),
    species character varying(120),
    lineage character varying(20),
    sex character varying(20),
    adult_size_cm numeric(6,2),
    care_notes text,
    coming_soon character(1) NOT NULL,
    available_dstamp timestamp with time zone
);


--
-- Name: COLUMN sku.client_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.sku.client_id IS 'KEEP: Client/business identifier';


--
-- Name: COLUMN sku.sku_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.sku.sku_id IS 'KEEP: Single FINatics SKU/product identifier';


--
-- Name: COLUMN sku.ean; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.sku.ean IS 'KEEP: Optional barcode/product identifier';


--
-- Name: COLUMN sku.upc; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.sku.upc IS 'KEEP: Optional barcode/product identifier';


--
-- Name: COLUMN sku.description; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.sku.description IS 'KEEP: Operational item description';


--
-- Name: COLUMN sku.product_group; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.sku.product_group IS 'KEEP: Top-level product hierarchy';


--
-- Name: COLUMN sku.each_height; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.sku.each_height IS 'KEEP: Physical product dimension/weight';


--
-- Name: COLUMN sku.each_weight; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.sku.each_weight IS 'KEEP: Physical product dimension/weight';


--
-- Name: COLUMN sku.each_volume; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.sku.each_volume IS 'KEEP: Physical product dimension/weight';


--
-- Name: COLUMN sku.each_value; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.sku.each_value IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN sku.shelf_life; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.sku.shelf_life IS 'KEEP: Useful for food/dated stock';


--
-- Name: COLUMN sku.expiry_reqd; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.sku.expiry_reqd IS 'KEEP: Useful for food/dated stock';


--
-- Name: COLUMN sku.obsolete_product; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.sku.obsolete_product IS 'KEEP: Product lifecycle control';


--
-- Name: COLUMN sku.new_product; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.sku.new_product IS 'KEEP: Product lifecycle control';


--
-- Name: COLUMN sku.colour; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.sku.colour IS 'KEEP: Colour/visual classification';


--
-- Name: COLUMN sku.sku_size; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.sku.sku_size IS 'KEEP: Size sold/handled';


--
-- Name: COLUMN sku.each_width; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.sku.each_width IS 'KEEP: Physical product dimension/weight';


--
-- Name: COLUMN sku.each_depth; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.sku.each_depth IS 'KEEP: Physical product dimension/weight';


--
-- Name: COLUMN sku.reorder_trigger_qty; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.sku.reorder_trigger_qty IS 'KEEP: Stock replenishment threshold';


--
-- Name: COLUMN sku.low_trigger_qty; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.sku.low_trigger_qty IS 'KEEP: Stock replenishment threshold';


--
-- Name: COLUMN sku.created_by; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.sku.created_by IS 'KEEP: Audit field';


--
-- Name: COLUMN sku.creation_date; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.sku.creation_date IS 'KEEP: Audit/operational timestamp';


--
-- Name: COLUMN sku.last_updated_by; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.sku.last_updated_by IS 'KEEP: Audit field';


--
-- Name: COLUMN sku.last_update_date; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.sku.last_update_date IS 'KEEP: Audit/operational timestamp';


--
-- Name: COLUMN sku.commodity_code; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.sku.commodity_code IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN sku.family_group; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.sku.family_group IS 'KEEP: Second-level product hierarchy';


--
-- Name: COLUMN sku.fragile; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.sku.fragile IS 'KEEP: Dispatch/handling property';


--
-- Name: COLUMN sku.ecommerce; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.sku.ecommerce IS 'KEEP: Existing ecommerce eligibility flag';


--
-- Name: COLUMN sku.promotion; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.sku.promotion IS 'KEEP: Existing WMS field retained for FINatics';


--
-- Name: COLUMN sku.style; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.sku.style IS 'KEEP: Existing style/variant classification field';


--
-- Name: COLUMN sku.decatalogued; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.sku.decatalogued IS 'KEEP: Product lifecycle control';


--
-- Name: COLUMN sku.hazmat; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.sku.hazmat IS 'KEEP: Dispatch/handling property';


--
-- Name: COLUMN sku.sub_group; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.sku.sub_group IS 'ADD: 3rd category level';


--
-- Name: COLUMN sku.category; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.sku.category IS 'ADD: 4th category/product family level';


--
-- Name: COLUMN sku.manufacturer_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.sku.manufacturer_id IS 'ADD: Manufacturer identifier';


--
-- Name: COLUMN sku.manufacturer_sku; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.sku.manufacturer_sku IS 'ADD: Manufacturer''s own product code';


--
-- Name: COLUMN sku.brand_name; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.sku.brand_name IS 'ADD: Customer-facing brand';


--
-- Name: COLUMN sku.preferred_supplier_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.sku.preferred_supplier_id IS 'ADD: Preferred source when purchasing stock';


--
-- Name: COLUMN sku.supplier_sku; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.sku.supplier_sku IS 'ADD: Supplier product reference';


--
-- Name: COLUMN sku.sell_price; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.sku.sell_price IS 'ADD: Current FINatics selling price';


--
-- Name: COLUMN sku.cost_price; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.sku.cost_price IS 'ADD: Current expected unit cost';


--
-- Name: COLUMN sku.vat_rate; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.sku.vat_rate IS 'ADD: VAT percentage used for web pricing';


--
-- Name: COLUMN sku.web_title; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.sku.web_title IS 'ADD: SEO/customer product title; DESCRIPTION remains operational description';


--
-- Name: COLUMN sku.web_description; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.sku.web_description IS 'ADD: Full customer-facing product description';


--
-- Name: COLUMN sku.web_slug; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.sku.web_slug IS 'ADD: Stable product page path';


--
-- Name: COLUMN sku.web_active; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.sku.web_active IS 'ADD: Whether the SKU appears on the website';


--
-- Name: COLUMN sku.web_featured; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.sku.web_featured IS 'ADD: Homepage/featured product flag';


--
-- Name: COLUMN sku.web_image_1; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.sku.web_image_1 IS 'ADD: Primary product image URL/path';


--
-- Name: COLUMN sku.web_image_2; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.sku.web_image_2 IS 'ADD: Additional image URL/path';


--
-- Name: COLUMN sku.web_image_3; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.sku.web_image_3 IS 'ADD: Additional image URL/path';


--
-- Name: COLUMN sku.web_image_4; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.sku.web_image_4 IS 'ADD: Additional image URL/path';


--
-- Name: COLUMN sku.web_image_5; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.sku.web_image_5 IS 'ADD: Additional image URL/path';


--
-- Name: COLUMN sku.web_video_url; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.sku.web_video_url IS 'ADD: Optional product/fish video';


--
-- Name: COLUMN sku.fulfilment_type; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.sku.fulfilment_type IS 'ADD: Default fulfilment route';


--
-- Name: COLUMN sku.supplier_direct_enabled; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.sku.supplier_direct_enabled IS 'ADD: Allow supplier-direct fallback';


--
-- Name: COLUMN sku.affiliate_fallback; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.sku.affiliate_fallback IS 'ADD: Allow affiliate route when own/supplier stock unavailable';


--
-- Name: COLUMN sku.affiliate_url; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.sku.affiliate_url IS 'ADD: External tracked affiliate URL';


--
-- Name: COLUMN sku.min_order_qty; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.sku.min_order_qty IS 'ADD: Minimum purchasable quantity';


--
-- Name: COLUMN sku.max_order_qty; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.sku.max_order_qty IS 'ADD: Maximum quantity per order if required';


--
-- Name: COLUMN sku.genus; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.sku.genus IS 'ADD: Fish only - genus';


--
-- Name: COLUMN sku.species; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.sku.species IS 'ADD: Fish only - species/strain name';


--
-- Name: COLUMN sku.lineage; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.sku.lineage IS 'ADD: Fish only - lineage';


--
-- Name: COLUMN sku.sex; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.sku.sex IS 'ADD: Fish only - sex where sold by sex';


--
-- Name: COLUMN sku.adult_size_cm; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.sku.adult_size_cm IS 'ADD: Fish only - expected adult size';


--
-- Name: COLUMN sku.care_notes; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.sku.care_notes IS 'ADD: Fish only - care / compatibility notes';


--
-- Name: COLUMN sku.coming_soon; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.sku.coming_soon IS 'ADD: Display product before stock is sellable';


--
-- Name: COLUMN sku.available_dstamp; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.sku.available_dstamp IS 'ADD: Expected availability date/time';


--
-- Name: sku_media; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.sku_media (
    media_id bigint NOT NULL,
    client_id character varying(30) NOT NULL,
    sku_id character varying(50) NOT NULL,
    media_type character varying(30) NOT NULL,
    media_role character varying(40),
    file_path text NOT NULL,
    thumbnail_path text,
    poster_path text,
    alt_text character varying(250),
    title character varying(250),
    sort_sequence integer DEFAULT 100 NOT NULL,
    primary_media boolean DEFAULT false NOT NULL,
    active boolean DEFAULT true NOT NULL,
    created_dstamp timestamp with time zone DEFAULT now() NOT NULL,
    last_updated_dstamp timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: sku_media_media_id_seq; Type: SEQUENCE; Schema: core; Owner: -
--

ALTER TABLE core.sku_media ALTER COLUMN media_id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME core.sku_media_media_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: stock_reservation; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.stock_reservation (
    reservation_id uuid DEFAULT gen_random_uuid() NOT NULL,
    client_id character varying(30) NOT NULL,
    source_system character varying(50) DEFAULT 'WEBSITE'::character varying NOT NULL,
    source_reference character varying(100),
    customer_id character varying(15),
    contact_name character varying(100),
    email character varying(254) NOT NULL,
    phone character varying(40),
    status character varying(30) DEFAULT 'ACTIVE'::character varying NOT NULL,
    fulfilment_method character varying(30),
    notes character varying(500),
    expires_dstamp timestamp with time zone NOT NULL,
    converted_order_id character varying(20),
    created_dstamp timestamp with time zone DEFAULT now() NOT NULL,
    last_update_dstamp timestamp with time zone DEFAULT now() NOT NULL,
    account_id uuid,
    CONSTRAINT ck_stock_reservation_status CHECK (((status)::text = ANY ((ARRAY['ACTIVE'::character varying, 'CONVERTED'::character varying, 'RELEASED'::character varying, 'EXPIRED'::character varying, 'CANCELLED'::character varying])::text[])))
);


--
-- Name: stock_reservation_inventory; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.stock_reservation_inventory (
    reservation_line_id bigint NOT NULL,
    inventory_key bigint NOT NULL,
    qty_reserved numeric(15,6) NOT NULL,
    created_dstamp timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT ck_reservation_inventory_qty CHECK ((qty_reserved > (0)::numeric))
);


--
-- Name: stock_reservation_line; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.stock_reservation_line (
    reservation_line_id bigint NOT NULL,
    reservation_id uuid NOT NULL,
    client_id character varying(30) NOT NULL,
    sku_id character varying(50) NOT NULL,
    qty_reserved numeric(15,6) NOT NULL,
    unit_price numeric(12,2),
    created_dstamp timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT ck_stock_reservation_line_qty CHECK ((qty_reserved > (0)::numeric))
);


--
-- Name: stock_reservation_line_reservation_line_id_seq; Type: SEQUENCE; Schema: core; Owner: -
--

ALTER TABLE core.stock_reservation_line ALTER COLUMN reservation_line_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME core.stock_reservation_line_reservation_line_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: supplier; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.supplier (
    supplier_id character varying(50) NOT NULL,
    client_id character varying(30) NOT NULL,
    name character varying(150) NOT NULL,
    address_id character varying(50),
    contact character varying(120),
    contact_email character varying(180),
    contact_phone character varying(50),
    active boolean DEFAULT true NOT NULL,
    notes text,
    created_dstamp timestamp with time zone DEFAULT now() NOT NULL,
    last_updated_dstamp timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: supplier_sku; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.supplier_sku (
    client_id character varying(30) NOT NULL,
    supplier_id character varying(50) NOT NULL,
    sku_id character varying(50) NOT NULL,
    supplier_sku_id character varying(80),
    cost_price numeric(14,4),
    currency character varying(3),
    lead_time_days integer,
    min_order_qty numeric(18,6),
    preferred boolean DEFAULT false NOT NULL,
    active boolean DEFAULT true NOT NULL,
    created_dstamp timestamp with time zone DEFAULT now() NOT NULL,
    last_updated_dstamp timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: inventory_adjust_if; Type: TABLE; Schema: interface; Owner: -
--

CREATE TABLE interface.inventory_adjust_if (
    interface_id uuid DEFAULT gen_random_uuid() NOT NULL,
    client_id character varying(10) NOT NULL,
    source_system character varying(50) NOT NULL,
    source_reference character varying(100) NOT NULL,
    sku_id character varying(50) NOT NULL,
    location_id character varying(20),
    tag_id character varying(50),
    adjustment_qty numeric(15,6) NOT NULL,
    reason_code character varying(50),
    notes text,
    process_status character varying(30) DEFAULT 'NEW'::character varying NOT NULL,
    error_code character varying(50),
    error_text text,
    created_dstamp timestamp with time zone DEFAULT now() NOT NULL,
    processed_dstamp timestamp with time zone
);


--
-- Name: order_header_if; Type: TABLE; Schema: interface; Owner: -
--

CREATE TABLE interface.order_header_if (
    interface_id uuid DEFAULT gen_random_uuid() NOT NULL,
    client_id character varying(10) NOT NULL,
    source_system character varying(50) NOT NULL,
    source_order_id character varying(100) NOT NULL,
    order_id character varying(20),
    customer_id character varying(15),
    order_date timestamp with time zone DEFAULT now() NOT NULL,
    ship_by_date timestamp with time zone,
    deliver_by_date timestamp with time zone,
    dispatch_method character varying(40),
    service_level character varying(40),
    address_id character varying(50),
    order_value numeric(12,3),
    currency character varying(3),
    process_status character varying(30) DEFAULT 'NEW'::character varying NOT NULL,
    error_code character varying(50),
    error_text text,
    created_dstamp timestamp with time zone DEFAULT now() NOT NULL,
    processed_dstamp timestamp with time zone,
    fulfilment_preference character varying(30) DEFAULT 'CONSOLIDATE'::character varying NOT NULL,
    CONSTRAINT ck_order_header_if_fulfilment_preference CHECK (((fulfilment_preference)::text = ANY ((ARRAY['CONSOLIDATE'::character varying, 'SPLIT_WHEN_REQUIRED'::character varying])::text[])))
);


--
-- Name: order_line_if; Type: TABLE; Schema: interface; Owner: -
--

CREATE TABLE interface.order_line_if (
    interface_id uuid NOT NULL,
    line_id numeric(6,0) NOT NULL,
    source_line_id character varying(100),
    sku_id character varying(50) NOT NULL,
    qty_ordered numeric(15,6) NOT NULL,
    product_price numeric(12,3),
    extended_price numeric(12,3),
    notes character varying(80),
    process_status character varying(30) DEFAULT 'NEW'::character varying NOT NULL,
    error_code character varying(50),
    error_text text,
    created_dstamp timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: pre_advice_header_if; Type: TABLE; Schema: interface; Owner: -
--

CREATE TABLE interface.pre_advice_header_if (
    interface_id uuid DEFAULT gen_random_uuid() NOT NULL,
    client_id character varying(10) NOT NULL,
    source_system character varying(50) NOT NULL,
    source_reference character varying(100) NOT NULL,
    pre_advice_id character varying(50),
    site_id character varying(30),
    supplier_id character varying(50),
    due_dstamp timestamp with time zone,
    process_status character varying(30) DEFAULT 'NEW'::character varying NOT NULL,
    error_code character varying(50),
    error_text text,
    created_dstamp timestamp with time zone DEFAULT now() NOT NULL,
    processed_dstamp timestamp with time zone
);


--
-- Name: pre_advice_line_if; Type: TABLE; Schema: interface; Owner: -
--

CREATE TABLE interface.pre_advice_line_if (
    interface_id uuid NOT NULL,
    line_id numeric(6,0) NOT NULL,
    sku_id character varying(50) NOT NULL,
    qty_due numeric(15,6) NOT NULL,
    batch_id character varying(50),
    expiry_dstamp timestamp with time zone,
    process_status character varying(30) DEFAULT 'NEW'::character varying NOT NULL,
    error_code character varying(50),
    error_text text,
    created_dstamp timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: affiliate_click affiliate_click_pkey; Type: CONSTRAINT; Schema: audit; Owner: -
--

ALTER TABLE ONLY audit.affiliate_click
    ADD CONSTRAINT affiliate_click_pkey PRIMARY KEY (click_id);


--
-- Name: api_security_event api_security_event_pkey; Type: CONSTRAINT; Schema: audit; Owner: -
--

ALTER TABLE ONLY audit.api_security_event
    ADD CONSTRAINT api_security_event_pkey PRIMARY KEY (security_event_key);


--
-- Name: audit_event audit_event_pkey; Type: CONSTRAINT; Schema: audit; Owner: -
--

ALTER TABLE ONLY audit.audit_event
    ADD CONSTRAINT audit_event_pkey PRIMARY KEY (audit_id);


--
-- Name: payment_event payment_event_pkey; Type: CONSTRAINT; Schema: audit; Owner: -
--

ALTER TABLE ONLY audit.payment_event
    ADD CONSTRAINT payment_event_pkey PRIMARY KEY (payment_event_key);


--
-- Name: processing_log processing_log_pkey; Type: CONSTRAINT; Schema: audit; Owner: -
--

ALTER TABLE ONLY audit.processing_log
    ADD CONSTRAINT processing_log_pkey PRIMARY KEY (log_id);


--
-- Name: rule_decision_log rule_decision_log_pkey; Type: CONSTRAINT; Schema: audit; Owner: -
--

ALTER TABLE ONLY audit.rule_decision_log
    ADD CONSTRAINT rule_decision_log_pkey PRIMARY KEY (decision_id);


--
-- Name: payment_event uq_payment_event; Type: CONSTRAINT; Schema: audit; Owner: -
--

ALTER TABLE ONLY audit.payment_event
    ADD CONSTRAINT uq_payment_event UNIQUE (client_id, provider, provider_event_id);


--
-- Name: allocation_rule_condition allocation_rule_condition_pkey; Type: CONSTRAINT; Schema: config; Owner: -
--

ALTER TABLE ONLY config.allocation_rule_condition
    ADD CONSTRAINT allocation_rule_condition_pkey PRIMARY KEY (condition_id);


--
-- Name: allocation_rule allocation_rule_pkey; Type: CONSTRAINT; Schema: config; Owner: -
--

ALTER TABLE ONLY config.allocation_rule
    ADD CONSTRAINT allocation_rule_pkey PRIMARY KEY (rule_id);


--
-- Name: carrier carrier_pkey; Type: CONSTRAINT; Schema: config; Owner: -
--

ALTER TABLE ONLY config.carrier
    ADD CONSTRAINT carrier_pkey PRIMARY KEY (client_id, carrier_id);


--
-- Name: carrier_selection_condition carrier_selection_condition_pkey; Type: CONSTRAINT; Schema: config; Owner: -
--

ALTER TABLE ONLY config.carrier_selection_condition
    ADD CONSTRAINT carrier_selection_condition_pkey PRIMARY KEY (condition_id);


--
-- Name: carrier_selection_rule carrier_selection_rule_pkey; Type: CONSTRAINT; Schema: config; Owner: -
--

ALTER TABLE ONLY config.carrier_selection_rule
    ADD CONSTRAINT carrier_selection_rule_pkey PRIMARY KEY (rule_id);


--
-- Name: carrier_service carrier_service_pkey; Type: CONSTRAINT; Schema: config; Owner: -
--

ALTER TABLE ONLY config.carrier_service
    ADD CONSTRAINT carrier_service_pkey PRIMARY KEY (client_id, carrier_id, service_level);


--
-- Name: carrier_service_rate carrier_service_rate_pkey; Type: CONSTRAINT; Schema: config; Owner: -
--

ALTER TABLE ONLY config.carrier_service_rate
    ADD CONSTRAINT carrier_service_rate_pkey PRIMARY KEY (rate_id);


--
-- Name: delivery_class_control delivery_class_control_pkey; Type: CONSTRAINT; Schema: config; Owner: -
--

ALTER TABLE ONLY config.delivery_class_control
    ADD CONSTRAINT delivery_class_control_pkey PRIMARY KEY (client_id, delivery_class);


--
-- Name: delivery_zone delivery_zone_pkey; Type: CONSTRAINT; Schema: config; Owner: -
--

ALTER TABLE ONLY config.delivery_zone
    ADD CONSTRAINT delivery_zone_pkey PRIMARY KEY (client_id, zone_id);


--
-- Name: feature_flag feature_flag_pkey; Type: CONSTRAINT; Schema: config; Owner: -
--

ALTER TABLE ONLY config.feature_flag
    ADD CONSTRAINT feature_flag_pkey PRIMARY KEY (client_id, feature_key);


--
-- Name: merge_rule_condition merge_rule_condition_pkey; Type: CONSTRAINT; Schema: config; Owner: -
--

ALTER TABLE ONLY config.merge_rule_condition
    ADD CONSTRAINT merge_rule_condition_pkey PRIMARY KEY (condition_id);


--
-- Name: merge_rule merge_rule_pkey; Type: CONSTRAINT; Schema: config; Owner: -
--

ALTER TABLE ONLY config.merge_rule
    ADD CONSTRAINT merge_rule_pkey PRIMARY KEY (rule_id);


--
-- Name: promotion promotion_pkey; Type: CONSTRAINT; Schema: config; Owner: -
--

ALTER TABLE ONLY config.promotion
    ADD CONSTRAINT promotion_pkey PRIMARY KEY (client_id, promotion_id);


--
-- Name: system_setting system_setting_client_id_site_id_setting_key_key; Type: CONSTRAINT; Schema: config; Owner: -
--

ALTER TABLE ONLY config.system_setting
    ADD CONSTRAINT system_setting_client_id_site_id_setting_key_key UNIQUE (client_id, site_id, setting_key);


--
-- Name: system_setting system_setting_pkey; Type: CONSTRAINT; Schema: config; Owner: -
--

ALTER TABLE ONLY config.system_setting
    ADD CONSTRAINT system_setting_pkey PRIMARY KEY (setting_id);


--
-- Name: system_version system_version_pkey; Type: CONSTRAINT; Schema: config; Owner: -
--

ALTER TABLE ONLY config.system_version
    ADD CONSTRAINT system_version_pkey PRIMARY KEY (version_key);


--
-- Name: merge_rule uq_merge_rule_name; Type: CONSTRAINT; Schema: config; Owner: -
--

ALTER TABLE ONLY config.merge_rule
    ADD CONSTRAINT uq_merge_rule_name UNIQUE (client_id, rule_name);


--
-- Name: promotion uq_promotion_code; Type: CONSTRAINT; Schema: config; Owner: -
--

ALTER TABLE ONLY config.promotion
    ADD CONSTRAINT uq_promotion_code UNIQUE (client_id, promo_code);


--
-- Name: system_version uq_system_version; Type: CONSTRAINT; Schema: config; Owner: -
--

ALTER TABLE ONLY config.system_version
    ADD CONSTRAINT uq_system_version UNIQUE (product_code, version_number);


--
-- Name: address address_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.address
    ADD CONSTRAINT address_pkey PRIMARY KEY (client_id, address_id);


--
-- Name: allocation allocation_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.allocation
    ADD CONSTRAINT allocation_pkey PRIMARY KEY (allocation_id);


--
-- Name: client client_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.client
    ADD CONSTRAINT client_pkey PRIMARY KEY (client_id);


--
-- Name: contact_preference contact_preference_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.contact_preference
    ADD CONSTRAINT contact_preference_pkey PRIMARY KEY (contact_preference_id);


--
-- Name: customer_account_address customer_account_address_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.customer_account_address
    ADD CONSTRAINT customer_account_address_pkey PRIMARY KEY (account_id, address_id);


--
-- Name: customer_account customer_account_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.customer_account
    ADD CONSTRAINT customer_account_pkey PRIMARY KEY (account_id);


--
-- Name: customer_interest customer_interest_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.customer_interest
    ADD CONSTRAINT customer_interest_pkey PRIMARY KEY (interest_id);


--
-- Name: gift_card gift_card_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.gift_card
    ADD CONSTRAINT gift_card_pkey PRIMARY KEY (gift_card_id);


--
-- Name: inventory inventory_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.inventory
    ADD CONSTRAINT inventory_pkey PRIMARY KEY (key);


--
-- Name: inventory_transaction inventory_transaction_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.inventory_transaction
    ADD CONSTRAINT inventory_transaction_pkey PRIMARY KEY (key);


--
-- Name: kit_header kit_header_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.kit_header
    ADD CONSTRAINT kit_header_pkey PRIMARY KEY (client_id, kit_id);


--
-- Name: kit_line kit_line_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.kit_line
    ADD CONSTRAINT kit_line_pkey PRIMARY KEY (client_id, kit_id, line_id);


--
-- Name: location location_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.location
    ADD CONSTRAINT location_pkey PRIMARY KEY (location_id);


--
-- Name: location_zone location_zone_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.location_zone
    ADD CONSTRAINT location_zone_pkey PRIMARY KEY (client_id, site_id, zone_id);


--
-- Name: order_container order_container_client_id_container_id_key; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.order_container
    ADD CONSTRAINT order_container_client_id_container_id_key UNIQUE (client_id, container_id);


--
-- Name: order_container order_container_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.order_container
    ADD CONSTRAINT order_container_pkey PRIMARY KEY (container_key);


--
-- Name: order_header order_header_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.order_header
    ADD CONSTRAINT order_header_pkey PRIMARY KEY (client_id, order_id);


--
-- Name: order_line order_line_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.order_line
    ADD CONSTRAINT order_line_pkey PRIMARY KEY (client_id, order_id, line_id);


--
-- Name: payment_transaction payment_transaction_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.payment_transaction
    ADD CONSTRAINT payment_transaction_pkey PRIMARY KEY (payment_id);


--
-- Name: pick_task pick_task_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.pick_task
    ADD CONSTRAINT pick_task_pkey PRIMARY KEY (pick_task_id);


--
-- Name: pre_advice_header pre_advice_header_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.pre_advice_header
    ADD CONSTRAINT pre_advice_header_pkey PRIMARY KEY (client_id, pre_advice_id);


--
-- Name: pre_advice_line pre_advice_line_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.pre_advice_line
    ADD CONSTRAINT pre_advice_line_pkey PRIMARY KEY (client_id, pre_advice_id, line_id);


--
-- Name: product_affiliate_link product_affiliate_link_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.product_affiliate_link
    ADD CONSTRAINT product_affiliate_link_pkey PRIMARY KEY (link_id);


--
-- Name: product_category product_category_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.product_category
    ADD CONSTRAINT product_category_pkey PRIMARY KEY (client_id, category_code);


--
-- Name: product_favourite product_favourite_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.product_favourite
    ADD CONSTRAINT product_favourite_pkey PRIMARY KEY (account_id, product_id);


--
-- Name: product_group product_group_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.product_group
    ADD CONSTRAINT product_group_pkey PRIMARY KEY (product_group_id);


--
-- Name: product_media product_media_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.product_media
    ADD CONSTRAINT product_media_pkey PRIMARY KEY (media_id);


--
-- Name: product product_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.product
    ADD CONSTRAINT product_pkey PRIMARY KEY (client_id, product_id);


--
-- Name: product_review product_review_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.product_review
    ADD CONSTRAINT product_review_pkey PRIMARY KEY (review_id);


--
-- Name: product_search_alias product_search_alias_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.product_search_alias
    ADD CONSTRAINT product_search_alias_pkey PRIMARY KEY (search_alias_id);


--
-- Name: product_variant product_variant_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.product_variant
    ADD CONSTRAINT product_variant_pkey PRIMARY KEY (client_id, product_id, sku_id);


--
-- Name: shipping_manifest shipping_manifest_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.shipping_manifest
    ADD CONSTRAINT shipping_manifest_pkey PRIMARY KEY (key);


--
-- Name: site site_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.site
    ADD CONSTRAINT site_pkey PRIMARY KEY (site_id);


--
-- Name: sku_media sku_media_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.sku_media
    ADD CONSTRAINT sku_media_pkey PRIMARY KEY (media_id);


--
-- Name: sku sku_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.sku
    ADD CONSTRAINT sku_pkey PRIMARY KEY (client_id, sku_id);


--
-- Name: stock_reservation_inventory stock_reservation_inventory_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.stock_reservation_inventory
    ADD CONSTRAINT stock_reservation_inventory_pkey PRIMARY KEY (reservation_line_id, inventory_key);


--
-- Name: stock_reservation_line stock_reservation_line_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.stock_reservation_line
    ADD CONSTRAINT stock_reservation_line_pkey PRIMARY KEY (reservation_line_id);


--
-- Name: stock_reservation stock_reservation_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.stock_reservation
    ADD CONSTRAINT stock_reservation_pkey PRIMARY KEY (reservation_id);


--
-- Name: supplier supplier_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.supplier
    ADD CONSTRAINT supplier_pkey PRIMARY KEY (supplier_id);


--
-- Name: supplier_sku supplier_sku_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.supplier_sku
    ADD CONSTRAINT supplier_sku_pkey PRIMARY KEY (client_id, supplier_id, sku_id);


--
-- Name: contact_preference uq_contact_preference; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.contact_preference
    ADD CONSTRAINT uq_contact_preference UNIQUE (client_id, contact_type, contact_value, channel, purpose);


--
-- Name: customer_account uq_customer_account_auth; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.customer_account
    ADD CONSTRAINT uq_customer_account_auth UNIQUE (client_id, auth_provider, auth_subject);


--
-- Name: gift_card uq_gift_card_code; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.gift_card
    ADD CONSTRAINT uq_gift_card_code UNIQUE (client_id, gift_code);


--
-- Name: payment_transaction uq_payment_idempotency; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.payment_transaction
    ADD CONSTRAINT uq_payment_idempotency UNIQUE (client_id, provider, idempotency_key);


--
-- Name: pick_task uq_pick_task_allocation; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.pick_task
    ADD CONSTRAINT uq_pick_task_allocation UNIQUE (allocation_id);


--
-- Name: product_category uq_product_category_slug; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.product_category
    ADD CONSTRAINT uq_product_category_slug UNIQUE (client_id, slug);


--
-- Name: product_search_alias uq_product_search_alias; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.product_search_alias
    ADD CONSTRAINT uq_product_search_alias UNIQUE (client_id, product_id, alias_text);


--
-- Name: product uq_product_slug; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.product
    ADD CONSTRAINT uq_product_slug UNIQUE (client_id, slug);


--
-- Name: stock_reservation uq_stock_reservation_source; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.stock_reservation
    ADD CONSTRAINT uq_stock_reservation_source UNIQUE (client_id, source_system, source_reference);


--
-- Name: inventory_adjust_if inventory_adjust_if_client_id_source_system_source_referenc_key; Type: CONSTRAINT; Schema: interface; Owner: -
--

ALTER TABLE ONLY interface.inventory_adjust_if
    ADD CONSTRAINT inventory_adjust_if_client_id_source_system_source_referenc_key UNIQUE (client_id, source_system, source_reference);


--
-- Name: inventory_adjust_if inventory_adjust_if_pkey; Type: CONSTRAINT; Schema: interface; Owner: -
--

ALTER TABLE ONLY interface.inventory_adjust_if
    ADD CONSTRAINT inventory_adjust_if_pkey PRIMARY KEY (interface_id);


--
-- Name: order_header_if order_header_if_client_id_source_system_source_order_id_key; Type: CONSTRAINT; Schema: interface; Owner: -
--

ALTER TABLE ONLY interface.order_header_if
    ADD CONSTRAINT order_header_if_client_id_source_system_source_order_id_key UNIQUE (client_id, source_system, source_order_id);


--
-- Name: order_header_if order_header_if_pkey; Type: CONSTRAINT; Schema: interface; Owner: -
--

ALTER TABLE ONLY interface.order_header_if
    ADD CONSTRAINT order_header_if_pkey PRIMARY KEY (interface_id);


--
-- Name: order_line_if order_line_if_pkey; Type: CONSTRAINT; Schema: interface; Owner: -
--

ALTER TABLE ONLY interface.order_line_if
    ADD CONSTRAINT order_line_if_pkey PRIMARY KEY (interface_id, line_id);


--
-- Name: pre_advice_header_if pre_advice_header_if_client_id_source_system_source_referen_key; Type: CONSTRAINT; Schema: interface; Owner: -
--

ALTER TABLE ONLY interface.pre_advice_header_if
    ADD CONSTRAINT pre_advice_header_if_client_id_source_system_source_referen_key UNIQUE (client_id, source_system, source_reference);


--
-- Name: pre_advice_header_if pre_advice_header_if_pkey; Type: CONSTRAINT; Schema: interface; Owner: -
--

ALTER TABLE ONLY interface.pre_advice_header_if
    ADD CONSTRAINT pre_advice_header_if_pkey PRIMARY KEY (interface_id);


--
-- Name: pre_advice_line_if pre_advice_line_if_pkey; Type: CONSTRAINT; Schema: interface; Owner: -
--

ALTER TABLE ONLY interface.pre_advice_line_if
    ADD CONSTRAINT pre_advice_line_if_pkey PRIMARY KEY (interface_id, line_id);


--
-- Name: ix_affiliate_click_link; Type: INDEX; Schema: audit; Owner: -
--

CREATE INDEX ix_affiliate_click_link ON audit.affiliate_click USING btree (client_id, link_id, created_dstamp);


--
-- Name: ix_api_security_event_created; Type: INDEX; Schema: audit; Owner: -
--

CREATE INDEX ix_api_security_event_created ON audit.api_security_event USING btree (created_dstamp DESC);


--
-- Name: ix_payment_event_provider_reference; Type: INDEX; Schema: audit; Owner: -
--

CREATE INDEX ix_payment_event_provider_reference ON audit.payment_event USING btree (client_id, provider, provider_reference, created_dstamp DESC);


--
-- Name: ix_processing_log_process; Type: INDEX; Schema: audit; Owner: -
--

CREATE INDEX ix_processing_log_process ON audit.processing_log USING btree (process_name, created_dstamp);


--
-- Name: ix_rule_decision_carrier_entity; Type: INDEX; Schema: audit; Owner: -
--

CREATE INDEX ix_rule_decision_carrier_entity ON audit.rule_decision_log USING btree (client_id, engine_name, entity_type, entity_id, created_dstamp);


--
-- Name: ix_rule_decision_log_entity; Type: INDEX; Schema: audit; Owner: -
--

CREATE INDEX ix_rule_decision_log_entity ON audit.rule_decision_log USING btree (engine_name, entity_type, entity_id, created_dstamp);


--
-- Name: ix_allocation_rule_client_priority; Type: INDEX; Schema: config; Owner: -
--

CREATE INDEX ix_allocation_rule_client_priority ON config.allocation_rule USING btree (client_id, active, priority);


--
-- Name: ix_carrier_condition_rule; Type: INDEX; Schema: config; Owner: -
--

CREATE INDEX ix_carrier_condition_rule ON config.carrier_selection_condition USING btree (rule_id, condition_group, sequence);


--
-- Name: ix_carrier_rate_lookup; Type: INDEX; Schema: config; Owner: -
--

CREATE INDEX ix_carrier_rate_lookup ON config.carrier_service_rate USING btree (client_id, carrier_id, service_level, active, min_weight_kg, max_weight_kg);


--
-- Name: ix_carrier_rule_active; Type: INDEX; Schema: config; Owner: -
--

CREATE INDEX ix_carrier_rule_active ON config.carrier_selection_rule USING btree (client_id, active, priority, carrier_id, service_level);


--
-- Name: ix_carrier_selection_condition_rule; Type: INDEX; Schema: config; Owner: -
--

CREATE INDEX ix_carrier_selection_condition_rule ON config.carrier_selection_condition USING btree (rule_id, condition_group, sequence);


--
-- Name: ix_carrier_selection_rule_priority; Type: INDEX; Schema: config; Owner: -
--

CREATE INDEX ix_carrier_selection_rule_priority ON config.carrier_selection_rule USING btree (client_id, active, priority);


--
-- Name: ix_carrier_service_active; Type: INDEX; Schema: config; Owner: -
--

CREATE INDEX ix_carrier_service_active ON config.carrier_service USING btree (client_id, active, sort_sequence, carrier_id, service_level);


--
-- Name: ix_delivery_class_control; Type: INDEX; Schema: config; Owner: -
--

CREATE INDEX ix_delivery_class_control ON config.delivery_class_control USING btree (client_id, delivery_class, carrier_despatch_enabled);


--
-- Name: ix_delivery_zone_match; Type: INDEX; Schema: config; Owner: -
--

CREATE INDEX ix_delivery_zone_match ON config.delivery_zone USING btree (client_id, active, country, priority);


--
-- Name: ix_merge_condition_rule; Type: INDEX; Schema: config; Owner: -
--

CREATE INDEX ix_merge_condition_rule ON config.merge_rule_condition USING btree (rule_id, condition_group, sequence, condition_id);


--
-- Name: ix_merge_rule_active; Type: INDEX; Schema: config; Owner: -
--

CREATE INDEX ix_merge_rule_active ON config.merge_rule USING btree (client_id, active, priority, rule_id);


--
-- Name: ix_merge_rule_condition_rule; Type: INDEX; Schema: config; Owner: -
--

CREATE INDEX ix_merge_rule_condition_rule ON config.merge_rule_condition USING btree (rule_id, condition_group, sequence);


--
-- Name: ix_merge_rule_priority; Type: INDEX; Schema: config; Owner: -
--

CREATE INDEX ix_merge_rule_priority ON config.merge_rule USING btree (client_id, active, priority);


--
-- Name: uq_system_version_current; Type: INDEX; Schema: config; Owner: -
--

CREATE UNIQUE INDEX uq_system_version_current ON config.system_version USING btree (product_code) WHERE (is_current = true);


--
-- Name: ix_affiliate_link_product; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_affiliate_link_product ON core.product_affiliate_link USING btree (client_id, product_id, active);


--
-- Name: ix_allocation_inventory; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_allocation_inventory ON core.allocation USING btree (inventory_key);


--
-- Name: ix_allocation_open; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_allocation_open ON core.allocation USING btree (client_id, order_id, line_id, status, allocation_id);


--
-- Name: ix_allocation_order_line; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_allocation_order_line ON core.allocation USING btree (client_id, order_id, line_id);


--
-- Name: ix_customer_interest_account; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_customer_interest_account ON core.customer_interest USING btree (client_id, account_id, status, created_dstamp DESC);


--
-- Name: ix_customer_interest_active; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_customer_interest_active ON core.customer_interest USING btree (client_id, sku_id, status, interest_type);


--
-- Name: ix_inventory_allocation_search; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_inventory_allocation_search ON core.inventory USING btree (client_id, sku_id, receipt_dstamp, key);


--
-- Name: ix_inventory_location; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_inventory_location ON core.inventory USING btree (location_id);


--
-- Name: ix_order_container_carrier_selection; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_order_container_carrier_selection ON core.order_container USING btree (client_id, status, carrier_id, service_level);


--
-- Name: ix_order_container_hold; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_order_container_hold ON core.order_container USING btree (client_id, hold_status, delivery_class, fulfilment_method, status);


--
-- Name: ix_order_container_merge_status; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_order_container_merge_status ON core.order_container USING btree (client_id, order_id, status, delivery_class, fulfilment_method, hold_status);


--
-- Name: ix_order_container_merged_into; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_order_container_merged_into ON core.order_container USING btree (client_id, merged_into_container_id);


--
-- Name: ix_order_container_order; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_order_container_order ON core.order_container USING btree (client_id, order_id, status);


--
-- Name: ix_order_header_account; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_order_header_account ON core.order_header USING btree (client_id, account_id, order_date DESC);


--
-- Name: ix_order_header_fulfilment_preference; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_order_header_fulfilment_preference ON core.order_header USING btree (client_id, fulfilment_preference, fulfilment_status);


--
-- Name: ix_order_header_web_status; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_order_header_web_status ON core.order_header USING btree (client_id, order_id, payment_status, fulfilment_status);


--
-- Name: ix_order_line_allocation_pending; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_order_line_allocation_pending ON core.order_line USING btree (client_id, order_id, sku_id);


--
-- Name: ix_payment_reference; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_payment_reference ON core.payment_transaction USING btree (client_id, reference_type, reference_id, status);


--
-- Name: ix_payment_transaction_account; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_payment_transaction_account ON core.payment_transaction USING btree (client_id, account_id, created_dstamp DESC);


--
-- Name: ix_payment_transaction_reference; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_payment_transaction_reference ON core.payment_transaction USING btree (client_id, reference_type, reference_id, created_dstamp DESC);


--
-- Name: ix_pick_task_order_line; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_pick_task_order_line ON core.pick_task USING btree (client_id, order_id, line_id);


--
-- Name: ix_pick_task_queue; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_pick_task_queue ON core.pick_task USING btree (status, client_id, order_id, location_id, pick_task_id);


--
-- Name: ix_pre_advice_line_sku; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_pre_advice_line_sku ON core.pre_advice_line USING btree (client_id, sku_id);


--
-- Name: ix_product_active; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_product_active ON core.product USING btree (client_id, active, featured, sort_sequence);


--
-- Name: ix_product_category_active; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_product_category_active ON core.product_category USING btree (client_id, active, sort_sequence);


--
-- Name: ix_product_category_lookup; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_product_category_lookup ON core.product USING btree (client_id, category_code, active);


--
-- Name: ix_product_media_lookup; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_product_media_lookup ON core.product_media USING btree (client_id, product_id, active, sort_sequence);


--
-- Name: ix_product_review_public; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_product_review_public ON core.product_review USING btree (client_id, product_id, status, published_dstamp);


--
-- Name: ix_product_search_alias_text; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_product_search_alias_text ON core.product_search_alias USING btree (client_id, lower((alias_text)::text)) WHERE (active = true);


--
-- Name: ix_product_variant_active; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_product_variant_active ON core.product_variant USING btree (client_id, product_id, active, sort_sequence);


--
-- Name: ix_shipping_manifest_container; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_shipping_manifest_container ON core.shipping_manifest USING btree (client_id, container_id, shipped, key);


--
-- Name: ix_shipping_manifest_pick_task; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_shipping_manifest_pick_task ON core.shipping_manifest USING btree (pick_task_id) WHERE (pick_task_id IS NOT NULL);


--
-- Name: ix_sku_media_sku; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_sku_media_sku ON core.sku_media USING btree (client_id, sku_id, active, sort_sequence);


--
-- Name: ix_stock_reservation_account; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_stock_reservation_account ON core.stock_reservation USING btree (client_id, account_id, status, created_dstamp DESC);


--
-- Name: ix_stock_reservation_expiry; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_stock_reservation_expiry ON core.stock_reservation USING btree (client_id, status, expires_dstamp);


--
-- Name: ix_supplier_sku_sku; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_supplier_sku_sku ON core.supplier_sku USING btree (client_id, sku_id, active);


--
-- Name: ix_order_header_if_status; Type: INDEX; Schema: interface; Owner: -
--

CREATE INDEX ix_order_header_if_status ON interface.order_header_if USING btree (process_status, created_dstamp);


--
-- Name: ix_order_header_if_website_source; Type: INDEX; Schema: interface; Owner: -
--

CREATE INDEX ix_order_header_if_website_source ON interface.order_header_if USING btree (client_id, source_system, source_order_id, process_status);


--
-- Name: affiliate_click fk_affiliate_click_link; Type: FK CONSTRAINT; Schema: audit; Owner: -
--

ALTER TABLE ONLY audit.affiliate_click
    ADD CONSTRAINT fk_affiliate_click_link FOREIGN KEY (link_id) REFERENCES core.product_affiliate_link(link_id);


--
-- Name: payment_event fk_payment_event_payment; Type: FK CONSTRAINT; Schema: audit; Owner: -
--

ALTER TABLE ONLY audit.payment_event
    ADD CONSTRAINT fk_payment_event_payment FOREIGN KEY (payment_id) REFERENCES core.payment_transaction(payment_id);


--
-- Name: processing_log processing_log_client_id_fkey; Type: FK CONSTRAINT; Schema: audit; Owner: -
--

ALTER TABLE ONLY audit.processing_log
    ADD CONSTRAINT processing_log_client_id_fkey FOREIGN KEY (client_id) REFERENCES core.client(client_id);


--
-- Name: allocation_rule allocation_rule_client_id_fkey; Type: FK CONSTRAINT; Schema: config; Owner: -
--

ALTER TABLE ONLY config.allocation_rule
    ADD CONSTRAINT allocation_rule_client_id_fkey FOREIGN KEY (client_id) REFERENCES core.client(client_id);


--
-- Name: allocation_rule_condition allocation_rule_condition_rule_id_fkey; Type: FK CONSTRAINT; Schema: config; Owner: -
--

ALTER TABLE ONLY config.allocation_rule_condition
    ADD CONSTRAINT allocation_rule_condition_rule_id_fkey FOREIGN KEY (rule_id) REFERENCES config.allocation_rule(rule_id) ON DELETE CASCADE;


--
-- Name: carrier carrier_client_id_fkey; Type: FK CONSTRAINT; Schema: config; Owner: -
--

ALTER TABLE ONLY config.carrier
    ADD CONSTRAINT carrier_client_id_fkey FOREIGN KEY (client_id) REFERENCES core.client(client_id);


--
-- Name: carrier_selection_condition carrier_selection_condition_rule_id_fkey; Type: FK CONSTRAINT; Schema: config; Owner: -
--

ALTER TABLE ONLY config.carrier_selection_condition
    ADD CONSTRAINT carrier_selection_condition_rule_id_fkey FOREIGN KEY (rule_id) REFERENCES config.carrier_selection_rule(rule_id) ON DELETE CASCADE;


--
-- Name: carrier_selection_rule carrier_selection_rule_client_id_carrier_id_service_level_fkey; Type: FK CONSTRAINT; Schema: config; Owner: -
--

ALTER TABLE ONLY config.carrier_selection_rule
    ADD CONSTRAINT carrier_selection_rule_client_id_carrier_id_service_level_fkey FOREIGN KEY (client_id, carrier_id, service_level) REFERENCES config.carrier_service(client_id, carrier_id, service_level);


--
-- Name: carrier_selection_rule carrier_selection_rule_client_id_fkey; Type: FK CONSTRAINT; Schema: config; Owner: -
--

ALTER TABLE ONLY config.carrier_selection_rule
    ADD CONSTRAINT carrier_selection_rule_client_id_fkey FOREIGN KEY (client_id) REFERENCES core.client(client_id);


--
-- Name: carrier_service carrier_service_client_id_carrier_id_fkey; Type: FK CONSTRAINT; Schema: config; Owner: -
--

ALTER TABLE ONLY config.carrier_service
    ADD CONSTRAINT carrier_service_client_id_carrier_id_fkey FOREIGN KEY (client_id, carrier_id) REFERENCES config.carrier(client_id, carrier_id);


--
-- Name: carrier_service_rate carrier_service_rate_client_id_carrier_id_service_level_fkey; Type: FK CONSTRAINT; Schema: config; Owner: -
--

ALTER TABLE ONLY config.carrier_service_rate
    ADD CONSTRAINT carrier_service_rate_client_id_carrier_id_service_level_fkey FOREIGN KEY (client_id, carrier_id, service_level) REFERENCES config.carrier_service(client_id, carrier_id, service_level);


--
-- Name: feature_flag feature_flag_client_id_fkey; Type: FK CONSTRAINT; Schema: config; Owner: -
--

ALTER TABLE ONLY config.feature_flag
    ADD CONSTRAINT feature_flag_client_id_fkey FOREIGN KEY (client_id) REFERENCES core.client(client_id);


--
-- Name: delivery_class_control fk_delivery_class_control_client; Type: FK CONSTRAINT; Schema: config; Owner: -
--

ALTER TABLE ONLY config.delivery_class_control
    ADD CONSTRAINT fk_delivery_class_control_client FOREIGN KEY (client_id) REFERENCES core.client(client_id);


--
-- Name: delivery_zone fk_delivery_zone_client; Type: FK CONSTRAINT; Schema: config; Owner: -
--

ALTER TABLE ONLY config.delivery_zone
    ADD CONSTRAINT fk_delivery_zone_client FOREIGN KEY (client_id) REFERENCES core.client(client_id);


--
-- Name: merge_rule_condition fk_merge_condition_rule; Type: FK CONSTRAINT; Schema: config; Owner: -
--

ALTER TABLE ONLY config.merge_rule_condition
    ADD CONSTRAINT fk_merge_condition_rule FOREIGN KEY (rule_id) REFERENCES config.merge_rule(rule_id) ON DELETE CASCADE;


--
-- Name: merge_rule fk_merge_rule_client; Type: FK CONSTRAINT; Schema: config; Owner: -
--

ALTER TABLE ONLY config.merge_rule
    ADD CONSTRAINT fk_merge_rule_client FOREIGN KEY (client_id) REFERENCES core.client(client_id);


--
-- Name: promotion fk_promotion_client; Type: FK CONSTRAINT; Schema: config; Owner: -
--

ALTER TABLE ONLY config.promotion
    ADD CONSTRAINT fk_promotion_client FOREIGN KEY (client_id) REFERENCES core.client(client_id);


--
-- Name: system_setting system_setting_client_id_fkey; Type: FK CONSTRAINT; Schema: config; Owner: -
--

ALTER TABLE ONLY config.system_setting
    ADD CONSTRAINT system_setting_client_id_fkey FOREIGN KEY (client_id) REFERENCES core.client(client_id);


--
-- Name: address address_client_id_fkey; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.address
    ADD CONSTRAINT address_client_id_fkey FOREIGN KEY (client_id) REFERENCES core.client(client_id);


--
-- Name: allocation allocation_client_id_order_id_line_id_fkey; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.allocation
    ADD CONSTRAINT allocation_client_id_order_id_line_id_fkey FOREIGN KEY (client_id, order_id, line_id) REFERENCES core.order_line(client_id, order_id, line_id);


--
-- Name: allocation allocation_inventory_key_fkey; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.allocation
    ADD CONSTRAINT allocation_inventory_key_fkey FOREIGN KEY (inventory_key) REFERENCES core.inventory(key);


--
-- Name: customer_account_address fk_account_address_account; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.customer_account_address
    ADD CONSTRAINT fk_account_address_account FOREIGN KEY (account_id) REFERENCES core.customer_account(account_id) ON DELETE CASCADE;


--
-- Name: customer_account_address fk_account_address_address; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.customer_account_address
    ADD CONSTRAINT fk_account_address_address FOREIGN KEY (client_id, address_id) REFERENCES core.address(client_id, address_id) ON DELETE CASCADE;


--
-- Name: contact_preference fk_contact_preference_client; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.contact_preference
    ADD CONSTRAINT fk_contact_preference_client FOREIGN KEY (client_id) REFERENCES core.client(client_id);


--
-- Name: customer_account fk_customer_account_client; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.customer_account
    ADD CONSTRAINT fk_customer_account_client FOREIGN KEY (client_id) REFERENCES core.client(client_id);


--
-- Name: customer_interest fk_customer_interest_account; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.customer_interest
    ADD CONSTRAINT fk_customer_interest_account FOREIGN KEY (account_id) REFERENCES core.customer_account(account_id);


--
-- Name: customer_interest fk_customer_interest_product; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.customer_interest
    ADD CONSTRAINT fk_customer_interest_product FOREIGN KEY (client_id, product_id) REFERENCES core.product(client_id, product_id);


--
-- Name: gift_card fk_gift_card_client; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.gift_card
    ADD CONSTRAINT fk_gift_card_client FOREIGN KEY (client_id) REFERENCES core.client(client_id);


--
-- Name: order_container fk_order_container_merge_rule; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.order_container
    ADD CONSTRAINT fk_order_container_merge_rule FOREIGN KEY (merge_rule_id) REFERENCES config.merge_rule(rule_id);


--
-- Name: order_header fk_order_header_account; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.order_header
    ADD CONSTRAINT fk_order_header_account FOREIGN KEY (account_id) REFERENCES core.customer_account(account_id);


--
-- Name: payment_transaction fk_payment_transaction_account; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.payment_transaction
    ADD CONSTRAINT fk_payment_transaction_account FOREIGN KEY (account_id) REFERENCES core.customer_account(account_id);


--
-- Name: payment_transaction fk_payment_transaction_client; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.payment_transaction
    ADD CONSTRAINT fk_payment_transaction_client FOREIGN KEY (client_id) REFERENCES core.client(client_id);


--
-- Name: pick_task fk_pick_task_allocation; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.pick_task
    ADD CONSTRAINT fk_pick_task_allocation FOREIGN KEY (allocation_id) REFERENCES core.allocation(allocation_id);


--
-- Name: pick_task fk_pick_task_inventory; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.pick_task
    ADD CONSTRAINT fk_pick_task_inventory FOREIGN KEY (inventory_key) REFERENCES core.inventory(key);


--
-- Name: pick_task fk_pick_task_location; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.pick_task
    ADD CONSTRAINT fk_pick_task_location FOREIGN KEY (location_id) REFERENCES core.location(location_id);


--
-- Name: pick_task fk_pick_task_order_line; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.pick_task
    ADD CONSTRAINT fk_pick_task_order_line FOREIGN KEY (client_id, order_id, line_id) REFERENCES core.order_line(client_id, order_id, line_id);


--
-- Name: pick_task fk_pick_task_sku; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.pick_task
    ADD CONSTRAINT fk_pick_task_sku FOREIGN KEY (client_id, sku_id) REFERENCES core.sku(client_id, sku_id);


--
-- Name: product_affiliate_link fk_product_affiliate_product; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.product_affiliate_link
    ADD CONSTRAINT fk_product_affiliate_product FOREIGN KEY (client_id, product_id) REFERENCES core.product(client_id, product_id) ON DELETE CASCADE;


--
-- Name: product fk_product_category; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.product
    ADD CONSTRAINT fk_product_category FOREIGN KEY (client_id, category_code) REFERENCES core.product_category(client_id, category_code);


--
-- Name: product_category fk_product_category_client; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.product_category
    ADD CONSTRAINT fk_product_category_client FOREIGN KEY (client_id) REFERENCES core.client(client_id);


--
-- Name: product fk_product_client; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.product
    ADD CONSTRAINT fk_product_client FOREIGN KEY (client_id) REFERENCES core.client(client_id);


--
-- Name: product_favourite fk_product_favourite_account; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.product_favourite
    ADD CONSTRAINT fk_product_favourite_account FOREIGN KEY (account_id) REFERENCES core.customer_account(account_id) ON DELETE CASCADE;


--
-- Name: product_favourite fk_product_favourite_product; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.product_favourite
    ADD CONSTRAINT fk_product_favourite_product FOREIGN KEY (client_id, product_id) REFERENCES core.product(client_id, product_id) ON DELETE CASCADE;


--
-- Name: product_media fk_product_media_product; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.product_media
    ADD CONSTRAINT fk_product_media_product FOREIGN KEY (client_id, product_id) REFERENCES core.product(client_id, product_id) ON DELETE CASCADE;


--
-- Name: product_review fk_product_review_product; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.product_review
    ADD CONSTRAINT fk_product_review_product FOREIGN KEY (client_id, product_id) REFERENCES core.product(client_id, product_id) ON DELETE CASCADE;


--
-- Name: product_search_alias fk_product_search_alias_product; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.product_search_alias
    ADD CONSTRAINT fk_product_search_alias_product FOREIGN KEY (client_id, product_id) REFERENCES core.product(client_id, product_id) ON DELETE CASCADE;


--
-- Name: product_variant fk_product_variant_product; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.product_variant
    ADD CONSTRAINT fk_product_variant_product FOREIGN KEY (client_id, product_id) REFERENCES core.product(client_id, product_id) ON DELETE CASCADE;


--
-- Name: product_variant fk_product_variant_sku; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.product_variant
    ADD CONSTRAINT fk_product_variant_sku FOREIGN KEY (client_id, sku_id) REFERENCES core.sku(client_id, sku_id);


--
-- Name: stock_reservation_inventory fk_reservation_inventory_line; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.stock_reservation_inventory
    ADD CONSTRAINT fk_reservation_inventory_line FOREIGN KEY (reservation_line_id) REFERENCES core.stock_reservation_line(reservation_line_id) ON DELETE CASCADE;


--
-- Name: stock_reservation_inventory fk_reservation_inventory_stock; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.stock_reservation_inventory
    ADD CONSTRAINT fk_reservation_inventory_stock FOREIGN KEY (inventory_key) REFERENCES core.inventory(key);


--
-- Name: shipping_manifest fk_shipping_manifest_pick_task; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.shipping_manifest
    ADD CONSTRAINT fk_shipping_manifest_pick_task FOREIGN KEY (pick_task_id) REFERENCES core.pick_task(pick_task_id);


--
-- Name: stock_reservation fk_stock_reservation_account; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.stock_reservation
    ADD CONSTRAINT fk_stock_reservation_account FOREIGN KEY (account_id) REFERENCES core.customer_account(account_id);


--
-- Name: stock_reservation fk_stock_reservation_client; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.stock_reservation
    ADD CONSTRAINT fk_stock_reservation_client FOREIGN KEY (client_id) REFERENCES core.client(client_id);


--
-- Name: stock_reservation_line fk_stock_reservation_line_header; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.stock_reservation_line
    ADD CONSTRAINT fk_stock_reservation_line_header FOREIGN KEY (reservation_id) REFERENCES core.stock_reservation(reservation_id) ON DELETE CASCADE;


--
-- Name: stock_reservation_line fk_stock_reservation_line_sku; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.stock_reservation_line
    ADD CONSTRAINT fk_stock_reservation_line_sku FOREIGN KEY (client_id, sku_id) REFERENCES core.sku(client_id, sku_id);


--
-- Name: inventory inventory_client_id_fkey; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.inventory
    ADD CONSTRAINT inventory_client_id_fkey FOREIGN KEY (client_id) REFERENCES core.client(client_id);


--
-- Name: inventory inventory_client_id_sku_id_fkey; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.inventory
    ADD CONSTRAINT inventory_client_id_sku_id_fkey FOREIGN KEY (client_id, sku_id) REFERENCES core.sku(client_id, sku_id);


--
-- Name: inventory inventory_location_id_fkey; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.inventory
    ADD CONSTRAINT inventory_location_id_fkey FOREIGN KEY (location_id) REFERENCES core.location(location_id);


--
-- Name: kit_header kit_header_client_id_fkey; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.kit_header
    ADD CONSTRAINT kit_header_client_id_fkey FOREIGN KEY (client_id) REFERENCES core.client(client_id);


--
-- Name: kit_header kit_header_client_id_kit_sku_id_fkey; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.kit_header
    ADD CONSTRAINT kit_header_client_id_kit_sku_id_fkey FOREIGN KEY (client_id, kit_sku_id) REFERENCES core.sku(client_id, sku_id);


--
-- Name: kit_line kit_line_client_id_component_sku_id_fkey; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.kit_line
    ADD CONSTRAINT kit_line_client_id_component_sku_id_fkey FOREIGN KEY (client_id, component_sku_id) REFERENCES core.sku(client_id, sku_id);


--
-- Name: kit_line kit_line_client_id_kit_id_fkey; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.kit_line
    ADD CONSTRAINT kit_line_client_id_kit_id_fkey FOREIGN KEY (client_id, kit_id) REFERENCES core.kit_header(client_id, kit_id);


--
-- Name: location_zone location_zone_client_id_fkey; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.location_zone
    ADD CONSTRAINT location_zone_client_id_fkey FOREIGN KEY (client_id) REFERENCES core.client(client_id);


--
-- Name: location_zone location_zone_site_id_fkey; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.location_zone
    ADD CONSTRAINT location_zone_site_id_fkey FOREIGN KEY (site_id) REFERENCES core.site(site_id);


--
-- Name: order_container order_container_client_id_fkey; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.order_container
    ADD CONSTRAINT order_container_client_id_fkey FOREIGN KEY (client_id) REFERENCES core.client(client_id);


--
-- Name: order_container order_container_client_id_order_id_fkey; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.order_container
    ADD CONSTRAINT order_container_client_id_order_id_fkey FOREIGN KEY (client_id, order_id) REFERENCES core.order_header(client_id, order_id);


--
-- Name: order_header order_header_client_id_fkey; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.order_header
    ADD CONSTRAINT order_header_client_id_fkey FOREIGN KEY (client_id) REFERENCES core.client(client_id);


--
-- Name: order_line order_line_client_id_order_id_fkey; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.order_line
    ADD CONSTRAINT order_line_client_id_order_id_fkey FOREIGN KEY (client_id, order_id) REFERENCES core.order_header(client_id, order_id);


--
-- Name: order_line order_line_client_id_sku_id_fkey; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.order_line
    ADD CONSTRAINT order_line_client_id_sku_id_fkey FOREIGN KEY (client_id, sku_id) REFERENCES core.sku(client_id, sku_id);


--
-- Name: pre_advice_header pre_advice_header_client_id_fkey; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.pre_advice_header
    ADD CONSTRAINT pre_advice_header_client_id_fkey FOREIGN KEY (client_id) REFERENCES core.client(client_id);


--
-- Name: pre_advice_header pre_advice_header_site_id_fkey; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.pre_advice_header
    ADD CONSTRAINT pre_advice_header_site_id_fkey FOREIGN KEY (site_id) REFERENCES core.site(site_id);


--
-- Name: pre_advice_header pre_advice_header_supplier_id_fkey; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.pre_advice_header
    ADD CONSTRAINT pre_advice_header_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES core.supplier(supplier_id);


--
-- Name: pre_advice_line pre_advice_line_client_id_pre_advice_id_fkey; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.pre_advice_line
    ADD CONSTRAINT pre_advice_line_client_id_pre_advice_id_fkey FOREIGN KEY (client_id, pre_advice_id) REFERENCES core.pre_advice_header(client_id, pre_advice_id);


--
-- Name: pre_advice_line pre_advice_line_client_id_sku_id_fkey; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.pre_advice_line
    ADD CONSTRAINT pre_advice_line_client_id_sku_id_fkey FOREIGN KEY (client_id, sku_id) REFERENCES core.sku(client_id, sku_id);


--
-- Name: product_group product_group_client_id_fkey; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.product_group
    ADD CONSTRAINT product_group_client_id_fkey FOREIGN KEY (client_id) REFERENCES core.client(client_id);


--
-- Name: product_group product_group_parent_group_id_fkey; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.product_group
    ADD CONSTRAINT product_group_parent_group_id_fkey FOREIGN KEY (parent_group_id) REFERENCES core.product_group(product_group_id);


--
-- Name: shipping_manifest shipping_manifest_client_id_order_id_line_id_fkey; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.shipping_manifest
    ADD CONSTRAINT shipping_manifest_client_id_order_id_line_id_fkey FOREIGN KEY (client_id, order_id, line_id) REFERENCES core.order_line(client_id, order_id, line_id);


--
-- Name: shipping_manifest shipping_manifest_client_id_sku_id_fkey; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.shipping_manifest
    ADD CONSTRAINT shipping_manifest_client_id_sku_id_fkey FOREIGN KEY (client_id, sku_id) REFERENCES core.sku(client_id, sku_id);


--
-- Name: shipping_manifest shipping_manifest_location_id_fkey; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.shipping_manifest
    ADD CONSTRAINT shipping_manifest_location_id_fkey FOREIGN KEY (location_id) REFERENCES core.location(location_id);


--
-- Name: site site_client_id_fkey; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.site
    ADD CONSTRAINT site_client_id_fkey FOREIGN KEY (client_id) REFERENCES core.client(client_id);


--
-- Name: sku sku_client_id_fkey; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.sku
    ADD CONSTRAINT sku_client_id_fkey FOREIGN KEY (client_id) REFERENCES core.client(client_id);


--
-- Name: sku_media sku_media_client_id_fkey; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.sku_media
    ADD CONSTRAINT sku_media_client_id_fkey FOREIGN KEY (client_id) REFERENCES core.client(client_id);


--
-- Name: sku_media sku_media_client_id_sku_id_fkey; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.sku_media
    ADD CONSTRAINT sku_media_client_id_sku_id_fkey FOREIGN KEY (client_id, sku_id) REFERENCES core.sku(client_id, sku_id);


--
-- Name: supplier supplier_client_id_fkey; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.supplier
    ADD CONSTRAINT supplier_client_id_fkey FOREIGN KEY (client_id) REFERENCES core.client(client_id);


--
-- Name: supplier_sku supplier_sku_client_id_fkey; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.supplier_sku
    ADD CONSTRAINT supplier_sku_client_id_fkey FOREIGN KEY (client_id) REFERENCES core.client(client_id);


--
-- Name: supplier_sku supplier_sku_client_id_sku_id_fkey; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.supplier_sku
    ADD CONSTRAINT supplier_sku_client_id_sku_id_fkey FOREIGN KEY (client_id, sku_id) REFERENCES core.sku(client_id, sku_id);


--
-- Name: supplier_sku supplier_sku_supplier_id_fkey; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.supplier_sku
    ADD CONSTRAINT supplier_sku_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES core.supplier(supplier_id);


--
-- Name: inventory_adjust_if inventory_adjust_if_client_id_fkey; Type: FK CONSTRAINT; Schema: interface; Owner: -
--

ALTER TABLE ONLY interface.inventory_adjust_if
    ADD CONSTRAINT inventory_adjust_if_client_id_fkey FOREIGN KEY (client_id) REFERENCES core.client(client_id);


--
-- Name: order_header_if order_header_if_client_id_fkey; Type: FK CONSTRAINT; Schema: interface; Owner: -
--

ALTER TABLE ONLY interface.order_header_if
    ADD CONSTRAINT order_header_if_client_id_fkey FOREIGN KEY (client_id) REFERENCES core.client(client_id);


--
-- Name: order_line_if order_line_if_interface_id_fkey; Type: FK CONSTRAINT; Schema: interface; Owner: -
--

ALTER TABLE ONLY interface.order_line_if
    ADD CONSTRAINT order_line_if_interface_id_fkey FOREIGN KEY (interface_id) REFERENCES interface.order_header_if(interface_id) ON DELETE CASCADE;


--
-- Name: pre_advice_header_if pre_advice_header_if_client_id_fkey; Type: FK CONSTRAINT; Schema: interface; Owner: -
--

ALTER TABLE ONLY interface.pre_advice_header_if
    ADD CONSTRAINT pre_advice_header_if_client_id_fkey FOREIGN KEY (client_id) REFERENCES core.client(client_id);


--
-- Name: pre_advice_line_if pre_advice_line_if_interface_id_fkey; Type: FK CONSTRAINT; Schema: interface; Owner: -
--

ALTER TABLE ONLY interface.pre_advice_line_if
    ADD CONSTRAINT pre_advice_line_if_interface_id_fkey FOREIGN KEY (interface_id) REFERENCES interface.pre_advice_header_if(interface_id) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

\unrestrict JvWesxIm4WB3PdmkoNO63XofJTJyr2LdccOR50dyEVYXm1Cuwg6f1tvFABf7lJn
