CREATE OR REPLACE FUNCTION api.GET_STOCK_RESERVATION(p_client_id VARCHAR,p_reservation_id UUID)
RETURNS JSONB LANGUAGE sql STABLE AS $$
SELECT jsonb_build_object(
 'reservationId',r.RESERVATION_ID,'status',r.STATUS,'expiresAt',r.EXPIRES_DSTAMP,
 'fulfilmentMethod',r.FULFILMENT_METHOD,'email',r.EMAIL,
 'items',COALESCE((SELECT jsonb_agg(jsonb_build_object('skuId',l.SKU_ID,'qty',l.QTY_RESERVED,'unitPrice',l.UNIT_PRICE) ORDER BY l.RESERVATION_LINE_ID)
                   FROM core.STOCK_RESERVATION_LINE l WHERE l.RESERVATION_ID=r.RESERVATION_ID),'[]'::jsonb)
) FROM core.STOCK_RESERVATION r WHERE r.CLIENT_ID=p_client_id AND r.RESERVATION_ID=p_reservation_id;
$$;
