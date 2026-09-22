BEGIN;

CREATE TABLE IF NOT EXISTS core.gb_postcode_directory (
    postcode                       text PRIMARY KEY,
    postcode_compact               text NOT NULL UNIQUE,
    outward_code                   text NOT NULL,
    positional_quality_indicator   smallint,
    easting                        integer,
    northing                       integer,
    country_code                   text,
    nhs_regional_ha_code           text,
    nhs_ha_code                    text,
    admin_county_code              text,
    admin_district_code            text,
    admin_ward_code                text,
    source                         text NOT NULL DEFAULT 'OS_CODE_POINT_OPEN',
    source_updated_at              date,
    imported_at                    timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ix_gb_postcode_directory_outward
    ON core.gb_postcode_directory (outward_code);

CREATE INDEX IF NOT EXISTS ix_gb_postcode_directory_compact_prefix
    ON core.gb_postcode_directory (postcode_compact text_pattern_ops);

DO $$
DECLARE
    v_schema_owner name;
BEGIN
    SELECT pg_get_userbyid(nspowner)
      INTO v_schema_owner
      FROM pg_namespace
     WHERE nspname = 'core';

    IF v_schema_owner IS NOT NULL AND v_schema_owner <> current_user THEN
        EXECUTE format(
            'ALTER TABLE core.gb_postcode_directory OWNER TO %I',
            v_schema_owner
        );
    END IF;
END
$$;

COMMIT;
