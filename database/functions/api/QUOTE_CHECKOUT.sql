CREATE OR REPLACE FUNCTION api.QUOTE_CHECKOUT(
    p_client_id VARCHAR,
    p_payload JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
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
