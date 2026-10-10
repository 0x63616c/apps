import "./env";
import { existsSync, readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { closeDb, getDb } from "../src/db";
import { upsertRows } from "../src/db/queries";
import type { FeedRows } from "../src/lib/feed";
import { feedToRows } from "../src/lib/feed";
import { slugify } from "../src/lib/slug";
import { localSetTimesToUtc } from "../src/lib/time";

const here = dirname(fileURLToPath(import.meta.url));
const BUNDLED_FEED = process.env.SEED_FEED_PATH ?? resolve(here, "../../Festr/Resources/seed-feed.json");

const TZ = "America/Los_Angeles";
const FESTIVAL_ID = "head-trip-2026";
const SOURCE = "https://lineupscout.com/head-trip";
const SAT = "2026-10-10";
const SUN = "2026-10-11";

type InlineSet = [day: string, stageId: string, artist: string, start: string, end: string | null];

const INLINE_SETS: InlineSet[] = [
  [SAT, "main", "Seth Troxler b2b Ben Sterling", "16:30", "19:00"],
  [SAT, "main", "Peggy Gou b2b Four Tet", "19:20", "20:50"],
  [SAT, "main", "Under Construction (FISHER + Chris Lake)", "21:10", "22:40"],
  [SAT, "main", "Calvin Harris", "23:00", null],
  [SUN, "main", "DJ Harvey", "15:30", "17:00"],
  [SUN, "main", "The Blessed Madonna", "17:00", "18:30"],
  [SUN, "main", "Dom Dolla b2b KETTAMA", "18:50", "20:20"],
  [SUN, "main", "Skrillex", "20:40", "22:10"],
  [SUN, "main", "Swedish House Mafia", "22:30", null],
  [SAT, "sunflower", "Floating Points Sunflower Sound System", "15:00", "00:30"],
  [SUN, "sunflower", "Floating Points Sunflower Sound System", "15:00", "23:30"],
];

function headTrip2026(now = new Date()): FeedRows {
  const sets = INLINE_SETS.map(([day, stageId, artist, start, end]) => {
    const { startAt, endAt } = localSetTimesToUtc({ date: day, startTime: start, endTime: end, timeZone: TZ });
    return {
      // Same id scheme as the iOS bundled feed and the admin's auto-generated set ids.
      id: slugify(`${FESTIVAL_ID}-${day}-${artist}`),
      festivalId: FESTIVAL_ID,
      stageId,
      artist,
      day,
      startAt,
      endAt,
      sourceUrl: SOURCE,
      updatedAt: now,
    };
  });
  return {
    festivals: [
      {
        id: FESTIVAL_ID,
        name: "Head Trip",
        venue: "Empire Polo Club",
        city: "Indio",
        region: "CA",
        country: "US",
        timeZone: TZ,
        startDate: SAT,
        endDate: SUN,
        sourceUrl: SOURCE,
        lineup: [...new Set(INLINE_SETS.map((s) => s[2]))],
        published: true,
        updatedAt: now,
      },
    ],
    stages: [
      { id: "main", festivalId: FESTIVAL_ID, name: "Main Stage", sortOrder: 0 },
      { id: "sunflower", festivalId: FESTIVAL_ID, name: "Sunflower Sound System", sortOrder: 1 },
    ],
    sets,
  };
}

async function main() {
  let rows: FeedRows;
  if (existsSync(BUNDLED_FEED)) {
    console.log(`Seeding from ${BUNDLED_FEED}`);
    rows = feedToRows(JSON.parse(readFileSync(BUNDLED_FEED, "utf8")));
  } else {
    console.log("Bundled seed-feed.json not found; seeding Head Trip 2026 inline");
    rows = headTrip2026();
  }
  await upsertRows(getDb(), rows);
  console.log(
    `Upserted ${rows.festivals.length} festival(s), ${rows.stages.length} stage(s), ${rows.sets.length} set(s)`,
  );
}

main()
  .catch((err) => {
    console.error(err);
    process.exitCode = 1;
  })
  .finally(() => closeDb());
