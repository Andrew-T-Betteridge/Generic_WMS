\set ON_ERROR_STOP on

-- Production-safe base configuration for a fresh FINatics database.
-- Delivery zones are deliberately NOT seeded here because TEST delivery
-- configuration must never be promoted to PROD by accident.
--
-- The FINATICS client is created by database/seeds/001_finatics_fry_tray.sql.

BEGIN;

INSERT INTO config.DELIVERY_CLASS_CONTROL (
    CLIENT_ID,
    DELIVERY_CLASS,
    CARRIER_DESPATCH_ENABLED,
    HOLD_REASON
)
VALUES (
    'FINATICS',
    'LIVESTOCK',
    TRUE,
    NULL
)
ON CONFLICT (CLIENT_ID, DELIVERY_CLASS)
DO UPDATE SET
    CARRIER_DESPATCH_ENABLED = EXCLUDED.CARRIER_DESPATCH_ENABLED,
    HOLD_REASON = EXCLUDED.HOLD_REASON,
    LAST_UPDATE_DSTAMP = now();

COMMIT;
