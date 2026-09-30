# FINatics Admin 0.3.15.1 — PROD deploy V4

V3 failed safely during the immutable admin build, before backup or static
bundle activation.

The exact failure was shell parsing:

`VITE_ADMIN_TITLE=FINatics Control`

The V3 script sourced `.env.production` as a shell script. Dotenv syntax allows
that value to be represented differently from shell syntax, so Bash treated
`Control` as a command.

V4 removes that mistake completely:

- `.env.production` is written for Vite with `VITE_ADMIN_TITLE="FINatics Control"`;
- the deployment script never sources `.env.production`;
- each required Vite setting is exported explicitly into the build process;
- the immutable release commit/tag are unchanged;
- the existing Auth0 domain/client-id are reused without being printed;
- the run is still deploy-only and does not touch the database or API;
- current live `dist` is untouched until after the production bundle builds and
  validates;
- then a rollback backup is created before atomic activation;
- public HTML/assets and PROD API health are verified after cutover.

## Project context

Before making architectural, database, Admin, API, release or production-deployment changes, read PROJECT_CONTEXT.md.
It records the current architecture, safety constraints, release conventions and active development direction and must be maintained with material project changes.
