# Interface schema

Staging and integration contract tables only.

Statuses used by order import:
NEW -> VALIDATING -> PROCESSED
                    -> ERROR

Retry is safe because the source-system/source-order key is unique and the
processor checks whether the operational order already exists.
