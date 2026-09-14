CREATE OR REPLACE FUNCTION api.CREATE_STOCK_RESERVATION(p_client_id VARCHAR,p_payload JSONB)
RETURNS JSONB LANGUAGE plpgsql AS $$
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
