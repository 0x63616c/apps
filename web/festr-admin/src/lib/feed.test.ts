import { describe, expect, it } from "vitest";
import type { FestivalRow, SetRow, StageRow } from "../db/schema";
import { buildFeed, etagFor, feedFiles, feedToRows, ifNoneMatchHits, serializeFeed } from "./feed";

const festival = (over: Partial<FestivalRow> = {}): FestivalRow => ({
  id: "head-trip-2026",
  name: "Head Trip",
  venue: "Empire Polo Club",
  city: "Indio",
  region: "CA",
  country: "US",
  timeZone: "America/Los_Angeles",
  startDate: "2026-10-10",
  endDate: "2026-10-11",
  sourceUrl: "https://lineupscout.com/head-trip",
  websiteUrl: null,
  ticketsUrl: null,
  lineup: ["Calvin Harris", "Skrillex"],
  published: true,
  updatedAt: new Date("2026-09-01T12:00:00.500Z"),
  ...over,
});

const stages: StageRow[] = [
  { id: "sunflower", festivalId: "head-trip-2026", name: "Sunflower Sound System", sortOrder: 1 },
  { id: "main", festivalId: "head-trip-2026", name: "Main Stage", sortOrder: 0 },
];

const sets: SetRow[] = [
  {
    id: "ht26-sat-calvin-harris",
    festivalId: "head-trip-2026",
    stageId: "main",
    artist: "Calvin Harris",
    day: "2026-10-10",
    startAt: new Date("2026-10-11T06:00:00Z"),
    endAt: null,
    sourceUrl: null,
    updatedAt: new Date("2026-09-05T08:00:00.999Z"),
  },
  {
    id: "ht26-sat-seth-troxler",
    festivalId: "head-trip-2026",
    stageId: "main",
    artist: "Seth Troxler b2b Ben Sterling",
    day: "2026-10-10",
    startAt: new Date("2026-10-10T23:30:00Z"),
    endAt: new Date("2026-10-11T02:00:00Z"),
    sourceUrl: "https://lineupscout.com/head-trip",
    updatedAt: new Date("2026-09-02T00:00:00Z"),
  },
];

describe("buildFeed", () => {
  const feed = buildFeed({ festivals: [festival()], stages, sets });

  it("produces the v1 schema with exact keys and order", () => {
    expect(feed.schemaVersion).toBe(1);
    const f = feed.festivals[0];
    expect(Object.keys(f)).toEqual([
      "id",
      "name",
      "venue",
      "city",
      "region",
      "country",
      "timeZone",
      "startDate",
      "endDate",
      "sourceURL",
      "links",
      "updatedAt",
      "lineup",
      "stages",
      "sets",
    ]);
    expect(Object.keys(f.sets[0])).toEqual([
      "id",
      "artist",
      "stageId",
      "day",
      "start",
      "end",
      "sourceURL",
      "updatedAt",
    ]);
    expect(f.stages).toEqual([
      { id: "main", name: "Main Stage", sortOrder: 0 },
      { id: "sunflower", name: "Sunflower Sound System", sortOrder: 1 },
    ]);
  });

  it("sorts sets by start and serializes UTC instants without fractions", () => {
    const [first, second] = feed.festivals[0].sets;
    expect(first.id).toBe("ht26-sat-seth-troxler");
    expect(first.start).toBe("2026-10-10T23:30:00Z");
    expect(first.end).toBe("2026-10-11T02:00:00Z");
    expect(second).toEqual({
      id: "ht26-sat-calvin-harris",
      artist: "Calvin Harris",
      stageId: "main",
      day: "2026-10-10",
      start: "2026-10-11T06:00:00Z",
      end: null,
      sourceURL: null,
      updatedAt: "2026-09-05T08:00:00Z",
    });
  });

  it("uses max(festival, sets) updatedAt for the festival and generatedAt", () => {
    expect(feed.festivals[0].updatedAt).toBe("2026-09-05T08:00:00Z");
    expect(feed.generatedAt).toBe("2026-09-05T08:00:00Z");
    const newer = buildFeed({
      festivals: [festival({ updatedAt: new Date("2026-09-10T00:00:00Z") })],
      stages,
      sets,
    });
    expect(newer.festivals[0].updatedAt).toBe("2026-09-10T00:00:00Z");
  });

  it("excludes unpublished festivals and their children", () => {
    const f2 = buildFeed({
      festivals: [festival({ published: false }), festival({ id: "other", startDate: "2026-01-01" })],
      stages,
      sets,
    });
    expect(f2.festivals.map((f) => f.id)).toEqual(["other"]);
    expect(f2.festivals[0].sets).toEqual([]);
  });

  it("honors an explicit generatedAt and handles an empty feed", () => {
    const empty = buildFeed(
      { festivals: [], stages: [], sets: [] },
      { generatedAt: new Date("2026-10-10T00:00:00.123Z") },
    );
    expect(empty).toEqual({ schemaVersion: 1, generatedAt: "2026-10-10T00:00:00Z", festivals: [] });
  });

  it("round-trips through feedToRows", () => {
    const again = buildFeed(feedToRows(feed));
    expect(again).toEqual(feed);
  });
});

describe("etag helpers", () => {
  it("is stable for identical content and changes with content", () => {
    const a = serializeFeed(buildFeed({ festivals: [festival()], stages, sets }));
    const b = serializeFeed(buildFeed({ festivals: [festival()], stages, sets }));
    const c = serializeFeed(buildFeed({ festivals: [festival({ name: "Head Trip!" })], stages, sets }));
    expect(etagFor(a)).toBe(etagFor(b));
    expect(etagFor(a)).not.toBe(etagFor(c));
    expect(etagFor(a)).toMatch(/^"[A-Za-z0-9_-]+"$/);
  });

  it("matches If-None-Match lists, weak prefixes and *", () => {
    const tag = '"abc"';
    expect(ifNoneMatchHits(null, tag)).toBe(false);
    expect(ifNoneMatchHits('"abc"', tag)).toBe(true);
    expect(ifNoneMatchHits('"x", W/"abc"', tag)).toBe(true);
    expect(ifNoneMatchHits("*", tag)).toBe(true);
    expect(ifNoneMatchHits('"abd"', tag)).toBe(false);
  });
});

describe("feedFiles", () => {
  it("writes index.json plus one file per festival, each with its own ETag", () => {
    const feed = buildFeed({ festivals: [festival()], stages, sets });
    const files = feedFiles(feed);
    expect(files.map((f) => f.path)).toEqual(["index.json", "festivals/head-trip-2026.json"]);
    expect(JSON.parse(files[0].body)).toEqual(feed);
    const single = JSON.parse(files[1].body);
    expect(single.schemaVersion).toBe(1);
    expect(single.festival).toEqual(feed.festivals[0]);
    expect(files[1].etag).toBe(etagFor(files[1].body));
    expect(feed.festivals[0].links).toEqual({ website: null, tickets: null });
  });
});
