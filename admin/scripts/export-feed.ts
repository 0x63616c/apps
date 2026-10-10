import "./env";
import { writeFileSync } from "node:fs";
import { closeDb, getDb } from "../src/db";
import { loadFeedRows } from "../src/db/queries";
import { buildFeed, serializeFeed } from "../src/lib/feed";

// Usage: pnpm feed:export [output-path]   (writes to stdout when no path is given)
async function main() {
  const out = process.argv[2];
  const json = serializeFeed(buildFeed(await loadFeedRows(getDb())), true) + "\n";
  if (out) {
    writeFileSync(out, json);
    console.error(`Wrote feed to ${out}`);
  } else {
    process.stdout.write(json);
  }
}

main()
  .catch((err) => {
    console.error(err);
    process.exitCode = 1;
  })
  .finally(() => closeDb());
