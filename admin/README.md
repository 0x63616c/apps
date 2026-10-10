# Festr Admin

Small Next.js (App Router) admin for editing festivals, stages and sets, and serving the
versioned JSON feed (`GET /api/feed`, `schemaVersion: 1`) that the Festr iOS app consumes.

Stack: Next.js 16, Drizzle ORM + drizzle-kit, Postgres via `postgres` (postgres-js), pnpm, vitest.

## Local setup

```bash
cp .env.example .env          # DATABASE_URL, ADMIN_PASSWORD (empty = no auth in dev)
pnpm i
docker compose up -d          # postgres:16 on localhost:5432, db "festr"
pnpm db:migrate               # applies drizzle/*.sql
pnpm db:seed                  # imports ../Festr/Resources/seed-feed.json, or Head Trip 2026 inline
pnpm dev                      # http://localhost:3000
```

Other scripts:

| Script | What it does |
| --- | --- |
| `pnpm test` | vitest (time conversion + feed builder) |
| `pnpm typecheck` | `tsc --noEmit` |
| `pnpm build` | production build (no database needed at build time) |
| `pnpm db:generate` | generate a new SQL migration after editing `src/db/schema.ts` |
| `pnpm feed:export [path]` | write the feed JSON to `path`, or stdout (use `pnpm -s feed:export > x.json` to keep pnpm's banner out of the file) |

`pnpm db:seed` upserts by primary key and never deletes rows. Set `SEED_FEED_PATH` to import a different feed file.

## How it works

- `src/db/schema.ts` – tables `festivals`, `stages` (pk `festival_id, id`), `sets`. Deleting a festival or stage cascades to its sets.
- `src/lib/time.ts` – converts local wall-clock date + time in the festival's IANA zone to UTC (Intl-based, DST-aware).
  In the set form, an end time earlier than the start means the set ends after midnight; a blank end time means open-ended (closer).
- `src/lib/feed.ts` – pure `buildFeed(rows)`; only published festivals. Festival `updatedAt` = max of festival and set `updated_at`.
  `generatedAt` is the newest content timestamp (not request time) so identical content gives an identical body and ETag.
  Any stage/set edit bumps the festival's `updated_at`.
- `src/app/api/feed/route.ts` – strong ETag (SHA-256 of the body), `If-None-Match` → 304,
  `Cache-Control: public, max-age=60, s-maxage=300, stale-while-revalidate=86400`.
- `src/proxy.ts` – Next 16's replacement for `middleware.ts`. Basic auth on everything except `/api/feed`
  when `ADMIN_PASSWORD` is set (any username). If unset: open in dev, but **503 in production** so a deploy is never left unprotected.

## Deploying to Vercel

1. Import the repo in Vercel with **Root Directory = `admin`** (framework preset: Next.js, pnpm is detected from the lockfile).
2. Create a Postgres database (Neon / Vercel Postgres) and set env vars: `DATABASE_URL` (pooled connection string is fine;
   the client uses `prepare: false`) and `ADMIN_PASSWORD`.
3. Run migrations and seed once against that database from your machine:
   `DATABASE_URL=... pnpm db:migrate && DATABASE_URL=... pnpm db:seed`.
4. Point the iOS app at `FEED_URL = https://<deployment>/api/feed`.
