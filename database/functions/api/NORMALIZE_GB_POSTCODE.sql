\set ON_ERROR_STOP on

CREATE OR REPLACE FUNCTION api.NORMALIZE_GB_POSTCODE(p_value TEXT)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
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
$$;
