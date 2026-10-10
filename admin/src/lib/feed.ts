import { createHash } from "node:crypto";
import type { FestivalRow, SetRow, StageRow } from "../db/schema";
import { toIsoUtc } from "./time";

export const FEED_SCHEMA_VERSION = 1 as const;

export interface FeedStage {
  id: string;
  name: string;
  sortOrder: number;
}

export interface FeedSet {
  id: string;
  artist: string;
  stageId: string;
  day: string | null;
  start: string;
  end: string | null;
  sourceURL: string | null;
  updatedAt: string;
}

export interface FeedFestival {
  id: string;
  name: string;
  venue: string;
  city: string;
  region: string;
  country: string;
  timeZone: string;
  startDate: string;
  endDate: string;
  sourceURL: string | null;
  updatedAt: string;
  lineup: string[];
  stages: FeedStage[];
  sets: FeedSet[];
}

export interface Feed {
  schemaVersion: typeof FEED_SCHEMA_VERSION;
  generatedAt: string;
  festivals: FeedFestival[];
}

export interface FeedRows {
  festivals: FestivalRow[];
  stages: StageRow[];
  sets: SetRow[];
}

const byString = (a: string, b: string) => (a < b ? -1 : a > b ? 1 : 0);

/**
 * Pure rows -> feed transform. Unpublished festivals are dropped.
 * `generatedAt` defaults to the newest content timestamp (not "now") so identical
 * content always yields an identical body and therefore a stable ETag.
 */
export function buildFeed(rows: FeedRows, opts: { generatedAt?: Date } = {}): Feed {
  const published = rows.festivals
    .filter((f) => f.published)
    .sort((a, b) => byString(a.startDate, b.startDate) || byString(a.id, b.id));

  let newest = 0;
  const festivals = published.map((f): FeedFestival => {
    const stages = rows.stages
      .filter((s) => s.festivalId === f.id)
      .sort((a, b) => a.sortOrder - b.sortOrder || byString(a.id, b.id))
      .map((s) => ({ id: s.id, name: s.name, sortOrder: s.sortOrder }));

    const festivalSets = rows.sets
      .filter((s) => s.festivalId === f.id)
      .sort(
        (a, b) =>
          a.startAt.getTime() - b.startAt.getTime() || byString(a.stageId, b.stageId) || byString(a.id, b.id),
      );

    let updatedMs = f.updatedAt.getTime();
    for (const s of festivalSets) updatedMs = Math.max(updatedMs, s.updatedAt.getTime());
    newest = Math.max(newest, updatedMs);

    return {
      id: f.id,
      name: f.name,
      venue: f.venue,
      city: f.city,
      region: f.region,
      country: f.country,
      timeZone: f.timeZone,
      startDate: f.startDate,
      endDate: f.endDate,
      sourceURL: f.sourceUrl ?? null,
      updatedAt: toIsoUtc(new Date(updatedMs)),
      lineup: [...f.lineup],
      stages,
      sets: festivalSets.map((s) => ({
        id: s.id,
        artist: s.artist,
        stageId: s.stageId,
        day: s.day ?? null,
        start: toIsoUtc(s.startAt),
        end: s.endAt ? toIsoUtc(s.endAt) : null,
        sourceURL: s.sourceUrl ?? null,
        updatedAt: toIsoUtc(s.updatedAt),
      })),
    };
  });

  return {
    schemaVersion: FEED_SCHEMA_VERSION,
    generatedAt: toIsoUtc(opts.generatedAt ?? new Date(newest)),
    festivals,
  };
}

export function serializeFeed(feed: Feed, pretty = false): string {
  return pretty ? JSON.stringify(feed, null, 2) : JSON.stringify(feed);
}

/** Strong ETag: quoted SHA-256 (base64url) of the exact response body. */
export function etagFor(body: string): string {
  return `"${createHash("sha256").update(body).digest("base64url")}"`;
}

/** True if an If-None-Match header value matches `etag` (handles lists, `*`, and W/ prefixes). */
export function ifNoneMatchHits(header: string | null, etag: string): boolean {
  if (!header) return false;
  return header
    .split(",")
    .map((t) => t.trim())
    .some((t) => t === "*" || t.replace(/^W\//, "") === etag);
}

/** Inverse of buildFeed, used by the seed script to import a bundled feed. */
export function feedToRows(feed: Feed): FeedRows {
  if (feed?.schemaVersion !== FEED_SCHEMA_VERSION || !Array.isArray(feed.festivals)) {
    throw new Error(`Unsupported feed (schemaVersion ${String(feed?.schemaVersion)})`);
  }
  const rows: FeedRows = { festivals: [], stages: [], sets: [] };
  for (const f of feed.festivals) {
    rows.festivals.push({
      id: f.id,
      name: f.name,
      venue: f.venue,
      city: f.city,
      region: f.region,
      country: f.country ?? "US",
      timeZone: f.timeZone,
      startDate: f.startDate,
      endDate: f.endDate,
      sourceUrl: f.sourceURL ?? null,
      lineup: f.lineup ?? [],
      published: true,
      updatedAt: new Date(f.updatedAt),
    });
    for (const s of f.stages ?? []) {
      rows.stages.push({ id: s.id, festivalId: f.id, name: s.name, sortOrder: s.sortOrder ?? 0 });
    }
    for (const s of f.sets ?? []) {
      rows.sets.push({
        id: s.id,
        festivalId: f.id,
        stageId: s.stageId,
        artist: s.artist,
        day: s.day ?? null,
        startAt: new Date(s.start),
        endAt: s.end ? new Date(s.end) : null,
        sourceUrl: s.sourceURL ?? null,
        updatedAt: new Date(s.updatedAt ?? f.updatedAt),
      });
    }
  }
  return rows;
}
