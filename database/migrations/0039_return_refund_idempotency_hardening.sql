-- WMS 0.3.18 - return/refund idempotency hardening
-- Persist return operation IDs rather than relying on audit JSON.
-- Existing return cases remain valid with OPERATION_ID null.

ALTER TABLE core.RETURN_CASE
    ADD COLUMN IF NOT EXISTS OPERATION_ID varchar(100);

CREATE UNIQUE INDEX IF NOT EXISTS UQ_RETURN_CASE_OPERATION
    ON core.RETURN_CASE (CLIENT_ID, OPERATION_ID)
    WHERE OPERATION_ID IS NOT NULL;

COMMENT ON COLUMN core.RETURN_CASE.OPERATION_ID IS
'Stable caller operation identifier used to make return/claim creation idempotent and concurrency-safe.';
