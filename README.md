# Generic WMS / Fulfilment Platform

Reusable PostgreSQL-based warehouse, order, fulfilment and shipping platform.

## Principles

- Generic backend: no fish/aquatics-specific core logic.
- PostgreSQL first.
- One SQL file per table/object.
- UPPERCASE_UNDERSCORE naming conventions preserved in database object/column design where practical.
- CLIENT_ID retained to support multiple businesses/clients.
- Core business logic is data/configuration-driven.
- Database changes are made through source-controlled migrations.
- Website and Ops Console consume the backend through documented interfaces/APIs.

## Main database areas

- `core`   - operational master/transaction data
- `iface`  - inbound/outbound interface and staging objects
- `config` - carrier, merge, delivery and processing configuration
- `audit`  - processing history, audit and error information

## Build order

1. Schemas
2. Core tables
3. Interface tables
4. Configuration/rules tables
5. Indexes and constraints
6. Seed/test data
7. Processing functions/services
8. API
9. Ops Console
10. Customer-specific front ends
