# DYNETIC WMS Website/API V3 coverage

| Requirement | Boundary | Test |
|---|---|---|
| Guest checkout | `POST /api/orders` | Existing 013/014 + HTTP contract |
| Optional customer account | OIDC/JWT -> `CUSTOMER_ACCOUNT` | 016 + HTTP |
| No local password storage | Provider + subject only | Schema review |
| Email verified claim retained | `UPSERT_ACCOUNT_IDENTITY` | 016 |
| Saved addresses | `/api/account/addresses` | 016 + HTTP |
| Favourites | `/api/account/favourites` | 016 + HTTP |
| Order history | `/api/account/orders` | ownership model + HTTP boundary |
| Waitlists/interests | V2 + `/api/account/interests` | 014/016 |
| Stock reservations | V2 + `/api/account/reservations` | 014/016 |
| Public order lookup secured | account ownership or signed guest token | HTTP boundary |
| Browser cannot choose payment amount | `CREATE_PAYMENT_REQUEST` loads WMS value | 016 |
| Stock protected during payment | `CREATE_PENDING_WEB_ORDER` allocates before payment | clean/HTTP journey |
| Abandoned payment stock released | `EXPIRE_PENDING_PAYMENT_ORDERS` | SQL/API |
| Payment failure/cancel releases allocation | webhook -> `DEALLOCATE_ORDER` | SQL event mapping |
| Guest reservation access secured | signed scoped reservation token | HTTP boundary |
| Guest payment access secured | order/reservation scoped token required | HTTP boundary |
| Stripe PaymentIntent | server-side Stripe adapter | external test-mode required |
| Card / Apple Pay / Google Pay | Stripe automatic payment methods | provider configuration |
| Payment success authoritative | signed Stripe webhook only | 016 DB event test |
| Webhook replay safe | unique provider event id | 016 |
| Failed/cancelled state | `PROCESS_PAYMENT_EVENT` | event mapping |
| Partial/full refund state | `charge.refunded` mapping | 016 |
| Admin-only analytics/moderation/expiry/refund | JWT role enforcement | HTTP |
| Provider-neutral auth | OIDC/JWKS adapter | configuration |
| Provider-neutral payment storage | generic PAYMENT_TRANSACTION | schema |
| Version | DYNETIC WMS `0.2.0 DEVELOPMENT` | clean build/version tests |

## External tests intentionally separate

A clean local build cannot genuinely prove:
- Stripe accepting a PaymentIntent;
- Stripe webhook delivery over the internet;
- Apple Pay / Google Pay domain eligibility;
- a chosen production identity provider.

Those are external integration tests after local V3 is green.
