CREATE OR REPLACE FUNCTION api.QUOTE_CHECKOUT(p_client_id VARCHAR,p_payload JSONB)
RETURNS JSONB LANGUAGE plpgsql STABLE AS $$
DECLARE v_delivery JSONB; v_basket JSONB; v_promo JSONB; v_discount NUMERIC:=0; v_total NUMERIC;
BEGIN
 v_delivery:=api.GET_DELIVERY_OPTIONS(p_client_id,p_payload); v_basket:=v_delivery->'basket';
 IF NOT COALESCE((v_delivery->>'valid')::boolean,FALSE) THEN RETURN v_delivery; END IF;
 IF NULLIF(TRIM(p_payload->>'promoCode'),'') IS NOT NULL THEN
   v_promo:=api.VALIDATE_PROMOTION(p_client_id,p_payload->>'promoCode',(v_basket->>'subtotal')::numeric,NULL);
   IF COALESCE((v_promo->>'valid')::boolean,FALSE) THEN v_discount:=COALESCE((v_promo->>'discountAmount')::numeric,0); END IF;
 END IF;
 v_total:=GREATEST((v_basket->>'subtotal')::numeric-v_discount,0);
 RETURN jsonb_build_object('valid',TRUE,'basket',v_basket,'promotion',v_promo,'discountAmount',v_discount,'totalBeforeDelivery',v_total,'fulfilmentOptions',v_delivery->'fulfilmentOptions');
END; $$;
