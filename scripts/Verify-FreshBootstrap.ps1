param(
    [string]$Database = "fulfilment_bootstrap_verify",
    [string]$HostName = "localhost",
    [int]$Port = 5432,
    [string]$DbUser = "postgres",
    [string]$PsqlPath = "C:\Program Files\PostgreSQL\18\bin\psql.exe"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

if ($Database -ne "fulfilment_bootstrap_verify") {
    throw "SAFETY STOP: this verification script may only run against fulfilment_bootstrap_verify."
}

$sql = @"
DO `$verify`$
DECLARE
    v_version text;
    v_tables integer;
    v_views integer;
    v_functions integer;
    v_test_rows integer;
    v_variants integer;
    v_media integer;
BEGIN
    SELECT api.GET_SYSTEM_VERSION()->>'version' INTO v_version;
    IF v_version <> '0.3.6' THEN
        RAISE EXCEPTION 'Expected version 0.3.6, got %', v_version;
    END IF;

    SELECT count(*) INTO v_tables
    FROM information_schema.tables
    WHERE table_schema IN ('audit','config','core','interface')
      AND table_type='BASE TABLE';

    IF v_tables <> 65 THEN
        RAISE EXCEPTION 'Expected 65 application tables, got %', v_tables;
    END IF;

    SELECT count(*) INTO v_views
    FROM information_schema.views
    WHERE table_schema IN ('api','core');

    IF v_views <> 13 THEN
        RAISE EXCEPTION 'Expected 13 application views, got %', v_views;
    END IF;

    SELECT count(*) INTO v_functions
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname IN ('api','audit','config','core','interface');

    IF v_functions <> 66 THEN
        RAISE EXCEPTION 'Expected 66 application functions, got %', v_functions;
    END IF;

    SELECT
      (SELECT count(*) FROM core.SKU WHERE SKU_ID ILIKE 'TEST-%') +
      (SELECT count(*) FROM core.PRODUCT WHERE PRODUCT_ID ILIKE 'TEST-%')
    INTO v_test_rows;

    IF v_test_rows <> 0 THEN
        RAISE EXCEPTION 'TEST fixture rows detected: %', v_test_rows;
    END IF;

    SELECT count(*) INTO v_variants
    FROM core.PRODUCT_VARIANT
    WHERE CLIENT_ID='FINATICS' AND PRODUCT_ID='FRYTRAY001';

    IF v_variants <> 22 THEN
        RAISE EXCEPTION 'Expected 22 FRYTRAY001 variants, got %', v_variants;
    END IF;

    SELECT count(*) INTO v_media
    FROM core.PRODUCT_MEDIA
    WHERE CLIENT_ID='FINATICS' AND PRODUCT_ID='FRYTRAY001';

    IF v_media <> 116 THEN
        RAISE EXCEPTION 'Expected 116 FRYTRAY001 media rows, got %', v_media;
    END IF;

    IF NOT EXISTS (
      SELECT 1
      FROM config.DELIVERY_CLASS_CONTROL
      WHERE CLIENT_ID='FINATICS'
        AND DELIVERY_CLASS='LIVESTOCK'
    ) THEN
        RAISE EXCEPTION 'Missing FINATICS LIVESTOCK delivery-class control.';
    END IF;

    RAISE NOTICE 'PASS: DYNETIC 0.3.6 fresh bootstrap verified.';
    RAISE NOTICE 'Tables=%, Views=%, Functions=%, FRYTRAY variants=%, Media=%',
                 v_tables, v_views, v_functions, v_variants, v_media;
END
`$verify`$;
"@

& $PsqlPath -X -v ON_ERROR_STOP=1 -h $HostName -p $Port -U $DbUser -d $Database -c $sql
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
