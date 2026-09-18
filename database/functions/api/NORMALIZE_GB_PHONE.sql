\set ON_ERROR_STOP on

CREATE OR REPLACE FUNCTION api.NORMALIZE_GB_PHONE(p_value TEXT)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
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
$$;
