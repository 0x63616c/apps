"use server";

import { and, eq, max } from "drizzle-orm";
import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { getDb } from "../db";
import { touchFestival } from "../db/queries";
import { festivals, sets, stages } from "../db/schema";
import { slugify } from "../lib/slug";
import { isValidDate, isValidTimeZone, localSetTimesToUtc } from "../lib/time";

const ID_RE = /^[a-z0-9][a-z0-9-]*$/;

class ValidationError extends Error {}

function str(form: FormData, key: string): string {
  const v = form.get(key);
  return typeof v === "string" ? v.trim() : "";
}

function required(form: FormData, key: string, label = key): string {
  const v = str(form, key);
  if (!v) throw new ValidationError(`${label} is required`);
  return v;
}

function optional(form: FormData, key: string): string | null {
  return str(form, key) || null;
}

function checkId(id: string, label: string): string {
  if (!ID_RE.test(id)) throw new ValidationError(`${label} must be lowercase letters, digits and dashes`);
  return id;
}

function checkUrl(url: string | null): string | null {
  if (url === null) return null;
  try {
    new URL(url);
    return url;
  } catch {
    throw new ValidationError(`Invalid URL: ${url}`);
  }
}

function errorMessage(err: unknown): string {
  if (err instanceof ValidationError) return err.message;
  const e = err as { code?: string; detail?: string; message?: string; cause?: { code?: string; detail?: string } };
  const code = e.code ?? e.cause?.code;
  if (code === "23505") return `Already exists: ${e.detail ?? e.cause?.detail ?? "duplicate id"}`;
  if (code === "23503") return `Invalid reference: ${e.detail ?? e.cause?.detail ?? "missing parent row"}`;
  return e.message ?? String(err);
}

/** Runs a mutation, then redirects to its result path, or back to `backTo` with ?error= on failure. */
async function mutate(backTo: string, fn: () => Promise<string | void>): Promise<never> {
  let target = backTo;
  try {
    target = (await fn()) ?? backTo;
  } catch (err) {
    if (!(err instanceof ValidationError)) console.error(err);
    target = `${backTo}?error=${encodeURIComponent(errorMessage(err))}`;
  }
  revalidatePath("/", "layout");
  redirect(target);
}

const festivalPath = (id: string) => `/festivals/${encodeURIComponent(id)}`;

export async function saveFestival(form: FormData): Promise<void> {
  const isNew = str(form, "isNew") === "1";
  const originalId = str(form, "originalId");
  await mutate(isNew ? "/festivals/new" : festivalPath(originalId), async () => {
    const id = checkId(isNew ? required(form, "id", "ID") : originalId, "ID");
    const timeZone = required(form, "timeZone", "Time zone");
    if (!isValidTimeZone(timeZone)) throw new ValidationError(`Unknown IANA time zone: ${timeZone}`);
    const startDate = required(form, "startDate", "Start date");
    const endDate = required(form, "endDate", "End date");
    if (!isValidDate(startDate) || !isValidDate(endDate)) throw new ValidationError("Dates must be YYYY-MM-DD");
    if (endDate < startDate) throw new ValidationError("End date is before start date");

    const values = {
      name: required(form, "name", "Name"),
      venue: required(form, "venue", "Venue"),
      city: required(form, "city", "City"),
      region: required(form, "region", "Region"),
      country: (str(form, "country") || "US").toUpperCase(),
      timeZone,
      startDate,
      endDate,
      sourceUrl: checkUrl(optional(form, "sourceUrl")),
      lineup: str(form, "lineup")
        .split("\n")
        .map((l) => l.trim())
        .filter(Boolean),
      published: form.get("published") === "on",
      updatedAt: new Date(),
    };
    const db = getDb();
    if (isNew) {
      await db.insert(festivals).values({ id, ...values });
    } else {
      const res = await db.update(festivals).set(values).where(eq(festivals.id, id)).returning({ id: festivals.id });
      if (res.length === 0) throw new ValidationError(`Festival ${id} not found`);
    }
    return festivalPath(id);
  });
}

export async function deleteFestival(form: FormData): Promise<void> {
  const id = str(form, "festivalId");
  await mutate(festivalPath(id), async () => {
    await getDb().delete(festivals).where(eq(festivals.id, id));
    return "/";
  });
}

export async function addStage(form: FormData): Promise<void> {
  const festivalId = str(form, "festivalId");
  await mutate(festivalPath(festivalId), async () => {
    const name = required(form, "name", "Stage name");
    const id = checkId(str(form, "id") || slugify(name), "Stage ID");
    const db = getDb();
    let sortOrder = Number.parseInt(str(form, "sortOrder"), 10);
    if (Number.isNaN(sortOrder)) {
      const [row] = await db
        .select({ m: max(stages.sortOrder) })
        .from(stages)
        .where(eq(stages.festivalId, festivalId));
      sortOrder = row?.m == null ? 0 : row.m + 1;
    }
    await db.insert(stages).values({ id, festivalId, name, sortOrder });
    await touchFestival(db, festivalId);
  });
}

export async function updateStage(form: FormData): Promise<void> {
  const festivalId = str(form, "festivalId");
  await mutate(festivalPath(festivalId), async () => {
    const id = required(form, "stageId");
    const sortOrder = Number.parseInt(str(form, "sortOrder"), 10);
    if (Number.isNaN(sortOrder)) throw new ValidationError("Sort order must be an integer");
    const db = getDb();
    await db
      .update(stages)
      .set({ name: required(form, "name", "Stage name"), sortOrder })
      .where(and(eq(stages.festivalId, festivalId), eq(stages.id, id)));
    await touchFestival(db, festivalId);
  });
}

export async function deleteStage(form: FormData): Promise<void> {
  const festivalId = str(form, "festivalId");
  await mutate(festivalPath(festivalId), async () => {
    const db = getDb();
    await db
      .delete(stages)
      .where(and(eq(stages.festivalId, festivalId), eq(stages.id, required(form, "stageId"))));
    await touchFestival(db, festivalId);
  });
}

export async function saveSet(form: FormData): Promise<void> {
  const festivalId = str(form, "festivalId");
  const existingId = str(form, "setId");
  await mutate(festivalPath(festivalId), async () => {
    const db = getDb();
    const [festival] = await db
      .select({ timeZone: festivals.timeZone })
      .from(festivals)
      .where(eq(festivals.id, festivalId));
    if (!festival) throw new ValidationError(`Festival ${festivalId} not found`);

    const artist = required(form, "artist", "Artist");
    const date = required(form, "date", "Date");
    let startAt: Date;
    let endAt: Date | null;
    try {
      ({ startAt, endAt } = localSetTimesToUtc({
        date,
        startTime: required(form, "startTime", "Start time"),
        endTime: optional(form, "endTime"),
        timeZone: festival.timeZone,
      }));
    } catch (err) {
      throw new ValidationError((err as Error).message);
    }
    const day = optional(form, "day") ?? date;
    if (!isValidDate(day)) throw new ValidationError("Day must be YYYY-MM-DD");

    const values = {
      festivalId,
      stageId: required(form, "stageId", "Stage"),
      artist,
      day,
      startAt,
      endAt,
      sourceUrl: checkUrl(optional(form, "sourceUrl")),
      updatedAt: new Date(),
    };

    if (existingId) {
      await db
        .update(sets)
        .set(values)
        .where(and(eq(sets.id, existingId), eq(sets.festivalId, festivalId)));
    } else {
      const base = checkId(str(form, "id") || slugify(`${festivalId}-${day}-${artist}`), "Set ID");
      let id = base;
      for (let n = 2; ; n++) {
        const [hit] = await db.select({ id: sets.id }).from(sets).where(eq(sets.id, id));
        if (!hit) break;
        if (str(form, "id")) throw new ValidationError(`Set ID ${id} already exists`);
        id = `${base}-${n}`;
      }
      await db.insert(sets).values({ id, ...values });
    }
    await touchFestival(db, festivalId);
  });
}

export async function deleteSet(form: FormData): Promise<void> {
  const festivalId = str(form, "festivalId");
  await mutate(festivalPath(festivalId), async () => {
    const db = getDb();
    await db
      .delete(sets)
      .where(and(eq(sets.id, required(form, "setId")), eq(sets.festivalId, festivalId)));
    await touchFestival(db, festivalId);
  });
}