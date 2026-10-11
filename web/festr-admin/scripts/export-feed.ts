import "./env";
import { writeFileSync } from "node:fs";
import { closeDb, getDb } from "../src/db";
import { currentFeed } from "../src/db/publish";
import { serializeFeed } from "../src/lib/feed";

// Usage: bun run feed:export [output-path]   (current data, published or not; stdout when no path is given)
async function main() {
  const out = process.argv[2];
  const json = serializeFeed(await currentFeed(getDb()), true) + "\n";
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
