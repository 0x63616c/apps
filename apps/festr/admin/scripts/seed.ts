import "./env";
import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { closeDb, getDb } from "../src/db";
import { publishFeed } from "../src/db/publish";
import { upsertRows } from "../src/db/queries";
import { feedToRows } from "../src/lib/feed";

const here = dirname(fileURLToPath(import.meta.url));
const BUNDLED_FEED = process.env.SEED_FEED_PATH ?? resolve(here, "../../Festr/Resources/seed-feed.json");

// Upserts the iOS app's bundled feed (non-destructive), then publishes. Usage: pnpm db:seed [--no-publish]
async function main() {
  const rows = feedToRows(JSON.parse(readFileSync(BUNDLED_FEED, "utf8")));
  const db = getDb();
  await upsertRows(db, rows);
  console.log(
    `Upserted ${rows.festivals.length} festivals, ${rows.stages.length} stages, ${rows.sets.length} sets`,
  );
  if (!process.argv.includes("--no-publish")) {
    const { version, files } = await publishFeed(db);
    console.log(`Published version ${version} (${files} files)`);
  }
}

main()
  .catch((err) => {
    console.error(err);
    process.exitCode = 1;
  })
  .finally(() => closeDb());
