# Festr admin

Next.js (App Router) + Drizzle + Postgres admin for festivals, stages and sets. **Publish** snapshots the data into the versioned JSON feed the iOS app reads:

| Path                        | Body                                                                                       |
| --------------------------- | ------------------------------------------------------------------------------------------ |
| `/feed/index.json`          | Whole feed (schema v1): every published festival with stages and sets. The app reads this. |
| `/feed/festivals/{id}.json` | `{ schemaVersion, generatedAt, festival }` for one festival.                               |

Both send a strong `ETag` (SHA-256 of the body), answer `If-None-Match` with `304`, and cache for 60 s at the browser and 5 min at the edge. Edits stay private until you publish; the header shows the published version and whether there are unpublished changes.

## Local setup

```bash
bun install
docker compose up -d            # or any Postgres 16; set DATABASE_URL
cp .env.example .env.local      # then fill in the values below
bun hash-password              # prints ADMIN_PASSWORD_HASH (escaped form for .env files)
openssl rand -hex 32            # SESSION_SECRET
bun db:migrate
bun db:seed                    # upserts ../Festr/Resources/seed-feed.json, then publishes
bun dev
```

Sign in with `ADMIN_EMAIL` (default `calumpeterwebb@icloud.com`) and the password you hashed.

## Checks

```bash
bun lint          # ESLint: next/core-web-vitals, next/typescript, eslint-plugin-shadcn (radix-all)
bun format:check  # Prettier with prettier-plugin-tailwindcss
bun typecheck     # next typegen + tsc
bun test          # Vitest: time zones, feed, import parsing, vision extraction (mock model), sessions, rate limit
bun ui:check      # shadcn CLI: installed components match the registry
bun build
E2E_PASSWORD=… E2E_BASE_URL=http://localhost:3000 bun e2e   # Playwright, against a running server with FESTR_VISION_MOCK=1
```

`src/components/ui` holds unmodified shadcn/ui registry components (Prettier and the shadcn lint rules skip them; `ui:check` keeps them in sync). Add more with `bun dlx shadcn@latest add <name>`.

## Features

- **Festivals:** name, dates, venue, city/state, IANA time zone, website, tickets, times source, lineup, shown-in-app toggle.
- **Stages** and **sets:** set times are entered as local festival time. A start before 06:00 belongs to the previous festival day (same rule as the app), an end earlier than the start runs past midnight, and an empty end is an open-ended closer.
- **Import:** paste CSV/TSV (`artist, stage, day, start, end`; header optional; weekday names, dates or `Day N`; 12- or 24-hour times) or upload a set-times poster. Both land in an editable preview; nothing is saved until **Save**. Unknown stages are created by name.
- **Import from image** uses the Vercel AI SDK through AI Gateway (`AI_GATEWAY_API_KEY`, model `AI_VISION_MODEL`, default `google/gemini-2.5-flash`). Without a key the tab is disabled. `FESTR_VISION_MOCK=1` returns a fixed two-set result for local UI testing.

## Auth

A single admin: email + bcrypt hash from the environment, compared in constant work even for unknown emails. A successful login sets an `httpOnly`, `SameSite=Lax` cookie (`Secure` in production) holding an HMAC-SHA256-signed session that expires after 7 days. Failed logins are rate-limited per IP and per email in Postgres (5 per 15 minutes), so the limit holds across serverless instances. The proxy redirects signed-out requests to `/login`; every page and server action also verifies the session. `/feed/*` is public.

## Deploy to Vercel

1. Import the repository in Vercel and set **Root Directory** to `admin` (Next.js is detected; `vercel.json` sets the install and build commands).
2. **Storage → Marketplace → Neon → Connect** to the project. This adds `DATABASE_URL` and `DATABASE_URL_UNPOOLED`.
3. Add environment variables: `ADMIN_EMAIL`, `ADMIN_PASSWORD_HASH` (raw hash, no escaping), `SESSION_SECRET`, and optionally `AI_GATEWAY_API_KEY` (or enable AI Gateway on the project, which uses the deployment's OIDC token).
4. Deploy. The build runs `bun db:migrate` (Drizzle migrations from `drizzle/`, using the unpooled URL), then `next build`.
5. Seed once from your machine against the Neon database: `DATABASE_URL=<neon url> bun db:seed`.
6. Point the iOS app at the deployment: set `FEED_BASE_URL` in `project.yml` (for example `https://festr-admin.vercel.app`) and regenerate the Xcode project. The app reads `<FEED_BASE_URL>/feed/index.json`.

Schema changes: edit `src/db/schema.ts`, run `bun db:generate`, commit the new file in `drizzle/`.

In the monorepo, set the Vercel project Root Directory to `web/festr-admin`. The bundled seed feed is read from `../../apps/festr/Festr/Resources/seed-feed.json`; override `SEED_FEED_PATH` when seeding outside this checkout. Use bun for installation and scripts. Deployment and migrations are separate from a local production build.
