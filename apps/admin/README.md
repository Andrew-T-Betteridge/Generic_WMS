# DYNETIC Generic WMS Admin

The Lovable implementation is the frontend design authority. The external Generic WMS API and Auth0 remain authoritative for data, permissions, security, and business actions.

## Run locally

1. Copy `.env.example` to `.env.local` and supply the deployment's Auth0 and WMS API settings.
2. Install dependencies with `bun install` (or `npm install`).
3. Start with `bun run dev` (or `npm run dev`).

Production and TEST configuration safety checks remain enforced by `src/admin/admin-config.ts`.

## Checks

- `bun test`
- `bun run typecheck`
- `bun run build`

The hidden `?visual-qa=1` test harness only operates in local development and exists for screenshot comparison. Published builds always use Auth0.
