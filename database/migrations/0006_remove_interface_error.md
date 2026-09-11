# Remove INTERFACE_ERROR

Errors remain directly on each interface record using:
- PROCESS_STATUS
- ERROR_CODE
- ERROR_TEXT

Design rule: do not create a separate table unless it has a real independent purpose.
