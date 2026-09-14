# Website Domain V2 API coverage matrix

| Requirement | HTTP/API | Server-side source of truth | Automated DB test 014 |
|---|---|---|---|
| Dynamic categories | `GET /api/catalog/categories` | `core.PRODUCT_CATEGORY` | Yes |
| Catalogue | `GET /api/catalog/products` | PRODUCT/VARIANT + WMS inventory | Existing 012 + 014 |
| Search / aliases | `GET /api/catalog/search` | PRODUCT + PRODUCT_SEARCH_ALIAS | Yes |
| Product detail | `GET /api/catalog/products/:slug` | PRODUCT/VARIANT | Yes |
| Images / video roles | `GET .../:slug/media` | PRODUCT_MEDIA | Yes |
| Livestock sale/availability states | product/search/validate APIs | PRODUCT_VARIANT | Yes |
| Real availability | product/validate APIs | INVENTORY.QTY_ON_HAND - QTY_ALLOCATED | Yes |
| Waitlist | `POST /api/interests` | CUSTOMER_INTEREST | Yes |
| Growing/coming-soon interest | `POST /api/interests` | CUSTOMER_INTEREST | Same model/test |
| Internal waiting-customer list | DB API `GET_INTEREST_CONTACTS` | CUSTOMER_INTEREST | Summary tested |
| FINatics-controlled notify action | DB API `MARK_INTEREST_NOTIFIED` | CUSTOMER_INTEREST | Function installed; admin UI later |
| Temporary stock hold | `POST /api/reservations` | STOCK_RESERVATION + INVENTORY allocation | Yes |
| Cancel/release hold | `DELETE /api/reservations/:id` | Reservation allocation mapping | Yes |
| Expire holds | DB API `EXPIRE_STOCK_RESERVATIONS` | Reservation allocation mapping | Function installed |
| Convert hold to order | `POST /api/reservations/:id/convert` | Interface order + ALLOCATE_ORDER | Yes |
| Configurable delivery zones | `POST /api/delivery/options` | config.DELIVERY_ZONE + carrier hold | Yes |
| Checkout quote | `POST /api/checkout/quote` | server repricing + delivery + promo | Yes |
| Promo codes | `POST /api/promotions/validate` | config.PROMOTION | Yes |
| Gift-card validation/balance | `POST /api/gift-cards/balance` | core.GIFT_CARD | Yes |
| Reviews | GET/POST product reviews | PRODUCT_REVIEW | Yes |
| Review moderation | DB API `MODERATE_PRODUCT_REVIEW` | PRODUCT_REVIEW | Admin UI later |
| Affiliate catalogue links | product detail / affiliate-links | PRODUCT_AFFILIATE_LINK | Click test yes |
| Affiliate click analytics | `POST /api/affiliate/click` | audit.AFFILIATE_CLICK | Yes |
| Affiliate demand report | DB API `GET_AFFILIATE_DEMAND` | click audit | Admin UI later |
| Marketing / stock-alert consent | `POST /api/preferences` | CONTACT_PREFERENCE | Yes |
| Stripe/PayPal neutral payment record | `POST /api/payments/prepare` | PAYMENT_TRANSACTION | Yes |
| Real Stripe/PayPal provider call | **Next integration** | provider adapter/webhook | Not faked |
| Web order | `POST /api/orders` | interface -> core order | Existing 013 |
| Reserved web order | reservation convert endpoint | reservation -> interface -> allocation | Yes |
| Order status | `GET /api/orders/:orderId` | core order/manifest | Existing 013 |
| Customer account identity | server-side CUSTOMER_ACCOUNT contract | external auth provider | Auth integration next |
| SMS/WhatsApp sending | consent model ready | provider integration later | Not faked |
| Weather automation | carrier hold already supports manual gate | forecast integration later | Existing hold tests |

## Test layers
1. Existing WMS regression tests remain unchanged.
2. Catalogue test 012 validates the original website catalogue.
3. Checkout/order test 013 validates web order ingestion.
4. New transactional test 014 validates the new website-domain state transitions and rolls back its data.
5. `test-website-domain-v2-http.ps1` smoke-tests the Fastify routing against a running API.
6. `npm run typecheck` validates TypeScript once dependencies are installed.

The matrix intentionally distinguishes **implemented contracts** from external integrations. Stripe, PayPal, SMS, WhatsApp and an auth provider require credentials/provider adapters and must not be simulated as complete.
