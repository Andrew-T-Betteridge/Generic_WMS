BEGIN;

CREATE OR REPLACE FUNCTION api.CLAIM_ORDER_ACCOUNT(
    p_client_id varchar,
    p_order_id varchar,
    p_account_id uuid,
    p_email varchar
)
RETURNS boolean
LANGUAGE plpgsql
AS $function$
DECLARE v_rows INTEGER;
BEGIN
    UPDATE core.ORDER_HEADER
       SET ACCOUNT_ID=p_account_id,
           LAST_UPDATED_BY='WEB_API',
           LAST_UPDATE_DATE=now()
     WHERE CLIENT_ID=p_client_id
       AND ORDER_ID=p_order_id
       AND ACCOUNT_ID IS NULL
       AND LOWER(COALESCE(CONTACT_EMAIL,''))=LOWER(COALESCE(p_email,''));

    GET DIAGNOSTICS v_rows = ROW_COUNT;

    IF v_rows=0 AND EXISTS(
        SELECT 1
        FROM core.ORDER_HEADER
        WHERE CLIENT_ID=p_client_id
          AND ORDER_ID=p_order_id
          AND ACCOUNT_ID=p_account_id
    ) THEN
        RETURN TRUE;
    END IF;

    RETURN v_rows=1;
END;
$function$;

COMMIT;
