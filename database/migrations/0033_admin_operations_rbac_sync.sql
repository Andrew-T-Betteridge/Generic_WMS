BEGIN;

-- DYNETIC WMS 0.3.14
-- Synchronise newly introduced permissions into the OWNER system role.
-- OWNER is intentionally complete; lower roles remain explicitly curated.

INSERT INTO config.ADMIN_ROLE_PERMISSION
    (CLIENT_ID, ROLE_CODE, PERMISSION_CODE)
SELECT
    r.CLIENT_ID,
    r.ROLE_CODE,
    p.PERMISSION_CODE
FROM config.ADMIN_ROLE r
CROSS JOIN config.ADMIN_PERMISSION p
WHERE r.ROLE_CODE = 'OWNER'
  AND r.ACTIVE = true
ON CONFLICT (CLIENT_ID, ROLE_CODE, PERMISSION_CODE) DO NOTHING;

DO $verify$
DECLARE
    v_missing integer;
BEGIN
    SELECT count(*)
      INTO v_missing
      FROM config.ADMIN_ROLE r
      CROSS JOIN config.ADMIN_PERMISSION p
      LEFT JOIN config.ADMIN_ROLE_PERMISSION rp
        ON rp.CLIENT_ID = r.CLIENT_ID
       AND rp.ROLE_CODE = r.ROLE_CODE
       AND rp.PERMISSION_CODE = p.PERMISSION_CODE
     WHERE r.ROLE_CODE = 'OWNER'
       AND r.ACTIVE = true
       AND rp.PERMISSION_CODE IS NULL;

    IF v_missing <> 0 THEN
        RAISE EXCEPTION 'OWNER_PERMISSION_SYNC_FAILED: % permission mapping(s) missing', v_missing;
    END IF;
END
$verify$;

COMMIT;
