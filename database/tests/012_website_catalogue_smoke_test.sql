\set ON_ERROR_STOP on
\pset pager off
BEGIN;

\ir ../seeds/001_finatics_fry_tray.sql

DO $$
DECLARE
    v_variant_count INTEGER;
    v_product JSONB;
    v_catalog JSONB;
BEGIN
    SELECT COUNT(*)
    INTO v_variant_count
    FROM core.PRODUCT_VARIANT
    WHERE CLIENT_ID='FINATICS'
      AND PRODUCT_ID='FRYTRAY001'
      AND ACTIVE=TRUE;

    IF v_variant_count<>22 THEN
        RAISE EXCEPTION
            'Expected 22 active fry-tray variants, got %.',
            v_variant_count;
    END IF;

    SELECT api.GET_CATALOG('FINATICS',NULL)
    INTO v_catalog;

    IF jsonb_array_length(v_catalog)<>1 THEN
        RAISE EXCEPTION
            'Expected one FINatics catalogue product, got %.',
            jsonb_array_length(v_catalog);
    END IF;

    SELECT api.GET_PRODUCT(
        'FINATICS',
        'finatics-aquatics-air-driven-fry-tray'
    )
    INTO v_product;

    IF v_product IS NULL THEN
        RAISE EXCEPTION 'GET_PRODUCT returned null.';
    END IF;

    IF jsonb_array_length(v_product->'variants')<>22 THEN
        RAISE EXCEPTION
            'GET_PRODUCT did not return all 22 variants.';
    END IF;

    IF v_product->'specification'->>'largeStatus' <> 'NOT_YET_RELEASED' THEN
        RAISE EXCEPTION
            'Large size must not be released in Website Catalogue V1.';
    END IF;
END
$$;

ROLLBACK;
