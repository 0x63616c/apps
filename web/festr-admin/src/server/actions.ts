"use server";

import { and, eq, max } from "drizzle-orm";
import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { getDb } from "@/db";
import { publishFeed } from "@/db/publish";
import { touchFestival } from "@/db/queries";
import { festivals, sets, stages } from "@/db/schema";
import { clearFailures, lockedFor, recordFailure } from "@/lib/auth/rate-limit";
import { normalizeDraft, type DraftIssue, type DraftSet } from "@/lib/import";
import { festivalDays, setInstants } from "@/lib/sets";
import { slugify } from "@/lib/slug";
import { isValidDate, isValidTimeZone } from "@/lib/time";
import {
  clientIp,
  dbAttemptStore,
  endSession,
  passwordMatches,
  requireAdmin,
  startSession,
} from "@/server/auth";
import { extractSetsFromImage, visionEnabled } from "@/server/vision";

export type ActionResult = { ok: true; message?: string } | { ok: false; error: string } | null;

const ID_RE = /^[a-z0-9][a-z0-9-]*$/;

class ValidationError extends Error {}

const str = (form: FormData, key: string) => {
  const v = form.get(key);
  return typeof v === "string" ? v.trim() : "";
};

function required(form: FormData, key: string, label: string): string {
  const v = str(form, key);
  if (!v) throw new ValidationError(`${label} is required`);
  return v;
}

function url(form: FormData, key: string): string | null {
  const v = str(form, key);
  if (!v) return null;
  try {
    const parsed = new URL(v);
    if (parsed.protocol !== "https:" && parsed.protocol !== "http:") throw new Error();
    return v;
  } catch {
    throw new ValidationError(`Invalid URL: ${v}`);
  }
}

function failure(err: unknown): ActionResult {
  if (err instanceof ValidationError) return { ok: false, error: err.message };
  const e = err as { code?: string; cause?: { code?: string } };
  const code = e.code ?? e.cause?.code;
  if (code === "23505") return { ok: false, error: "Already exists" };
  console.error(err);
  return { ok: false, error: "Something went wrong" };
}

async function run(fn: () => Promise<string | void>): Promise<ActionResult> {
  await requireAdmin();
  try {
    const message = await fn();
    revalidatePath("/", "layout");
    return { ok: true, message: message || undefined };
  } catch (err) {
    return failure(err);
  }
}

async function festivalTimeZone(festivalId: string) {
  const [festival] = await getDb()
    .select({ timeZone: festivals.timeZone, startDate: festivals.startDate, endDate: festivals.endDate })
    .from(festivals)
    .where(eq(festivals.id, festivalId));
  if (!festival) throw new ValidationError("Festival not found");
  return festival;
}

// Auth

export async function login(_: ActionResult, form: FormData): Promise<ActionResult> {
  const email = str(form, "email").toLowerCase();
  const password = typeof form.get("password") === "string" ? (form.get("password") as string) : "";
  const keys = [`ip:${await clientIp()}`, `email:${email}`];
  const wait = await lockedFor(dbAttemptStore, keys);
  if (wait > 0) return { ok: false, error: `Too many attempts. Try again in ${Math.ceil(wait / 60)} min.` };
  if (!(await passwordMatches(email, password))) {
    await recordFailure(dbAttemptStore, keys);
    return { ok: false, error: "Invalid email or password" };
  }
  await clearFailures(dbAttemptStore, keys);
  await startSession(email);
  const next = str(form, "next");
  redirect(next.startsWith("/") && !next.startsWith("//") ? next : "/");
}

export async function logout(): Promise<void> {
  await endSession();
  redirect("/login");
}

// Festivals

export async function saveFestival(_: ActionResult, form: FormData): Promise<ActionResult> {
  const originalId = str(form, "originalId");
  let createdId: string | null = null;
  const result = await run(async () => {
    const id =
      originalId || slugify(str(form, "id") || `${str(form, "name")} ${str(form, "startDate").slice(0, 4)}`);
    if (!ID_RE.test(id)) throw new ValidationError("ID must be lowercase letters, digits and dashes");
    const timeZone = required(form, "timeZone", "Time zone");
    if (!isValidTimeZone(timeZone)) throw new ValidationError("Unknown time zone");
    const startDate = required(form, "startDate", "Start date");
    const endDate = required(form, "endDate", "End date");
    if (!isValidDate(startDate) || !isValidDate(endDate)) throw new ValidationError("Invalid dates");
    if (endDate < startDate) throw new ValidationError("End date is before start date");
    const values = {
      name: required(form, "name", "Name"),
      venue: str(form, "venue"),
      city: required(form, "city", "City"),
      region: str(form, "region").toUpperCase(),
      timeZone,
      startDate,
      endDate,
      websiteUrl: url(form, "websiteUrl"),
      ticketsUrl: url(form, "ticketsUrl"),
      sourceUrl: url(form, "sourceUrl"),
      lineup: str(form, "lineup")
        .split("\n")
        .map((line) => line.trim())
        .filter(Boolean),
      published: form.get("published") === "on",
      updatedAt: new Date(),
    };
    const db = getDb();
    if (originalId) {
      await db.update(festivals).set(values).where(eq(festivals.id, originalId));
      return "Saved";
    }
    await db.insert(festivals).values({ id, ...values });
    createdId = id;
  });
  if (createdId) redirect(`/festivals/${createdId}`);
  return result;
}

export async function deleteFestival(festivalId: string): Promise<ActionResult> {
  const result = await run(async () => {
    await getDb().delete(festivals).where(eq(festivals.id, festivalId));
  });
  if (result?.ok) redirect("/");
  return result;
}

// Stages

export async function saveStage(_: ActionResult, form: FormData): Promise<ActionResult> {
  return run(async () => {
    const festivalId = required(form, "festivalId", "Festival");
    const name = required(form, "name", "Name");
    const db = getDb();
    const stageId = str(form, "stageId");
    if (stageId) {
      await db
        .update(stages)
        .set({ name })
        .where(and(eq(stages.festivalId, festivalId), eq(stages.id, stageId)));
    } else {
      const [row] = await db
        .select({ m: max(stages.sortOrder) })
        .from(stages)
        .where(eq(stages.festivalId, festivalId));
      const id = slugify(name);
      if (!id) throw new ValidationError("Name needs letters or digits");
      await db.insert(stages).values({ id, festivalId, name, sortOrder: row?.m == null ? 0 : row.m + 1 });
    }
    await touchFestival(db, festivalId);
    return stageId ? "Stage renamed" : "Stage added";
  });
}

export async function deleteStage(festivalId: string, stageId: string): Promise<ActionResult> {
  return run(async () => {
    const db = getDb();
    await db.delete(stages).where(and(eq(stages.festivalId, festivalId), eq(stages.id, stageId)));
    await touchFestival(db, festivalId);
    return "Stage deleted";
  });
}

// Sets

async function uniqueSetId(base: string): Promise<string> {
  const db = getDb();
  for (let n = 1; ; n++) {
    const id = n === 1 ? base : `${base}-${n}`;
    const [hit] = await db.select({ id: sets.id }).from(sets).where(eq(sets.id, id));
    if (!hit) return id;
  }
}

export async function saveSet(_: ActionResult, form: FormData): Promise<ActionResult> {
  return run(async () => {
    const festivalId = required(form, "festivalId", "Festival");
    const festival = await festivalTimeZone(festivalId);
    const artist = required(form, "artist", "Artist");
    const day = required(form, "day", "Day");
    const openEnd = form.get("openEnd") === "on";
    let times: { startAt: Date; endAt: Date | null };
    try {
      times = setInstants({
        day,
        start: required(form, "start", "Start"),
        end: openEnd ? null : str(form, "end") || null,
        timeZone: festival.timeZone,
      });
    } catch (err) {
      throw new ValidationError((err as Error).message);
    }
    const values = {
      festivalId,
      stageId: required(form, "stageId", "Stage"),
      artist,
      day,
      ...times,
      sourceUrl: url(form, "sourceUrl"),
      updatedAt: new Date(),
    };
    const db = getDb();
    const setId = str(form, "setId");
    if (setId) {
      await db
        .update(sets)
        .set(values)
        .where(and(eq(sets.id, setId), eq(sets.festivalId, festivalId)));
    } else {
      await db
        .insert(sets)
        .values({ id: await uniqueSetId(slugify(`${festivalId}-${day}-${artist}`)), ...values });
    }
    await touchFestival(db, festivalId);
    return setId ? "Set saved" : "Set added";
  });
}

export async function deleteSet(festivalId: string, setId: string): Promise<ActionResult> {
  return run(async () => {
    const db = getDb();
    await db.delete(sets).where(and(eq(sets.id, setId), eq(sets.festivalId, festivalId)));
    await touchFestival(db, festivalId);
    return "Set deleted";
  });
}

// Import

/** Saves reviewed draft rows, creating any stages that don't exist yet (matched by name). */
export async function importSets(
  festivalId: string,
  drafts: DraftSet[],
  sourceUrl: string,
): Promise<ActionResult> {
  return run(async () => {
    const festival = await festivalTimeZone(festivalId);
    const days = festivalDays(festival.startDate, festival.endDate);
    const db = getDb();
    const existing = await db.select().from(stages).where(eq(stages.festivalId, festivalId));
    const byName = new Map(existing.map((s) => [s.name.toLowerCase(), s.id]));
    let nextOrder = existing.reduce((m, s) => Math.max(m, s.sortOrder + 1), 0);
    const source = sourceUrl.trim() ? new URL(sourceUrl.trim()).toString() : null;
    const rows = drafts.map((raw, index) => {
      const { draft, problems } = normalizeDraft(raw, days);
      if (problems.length) throw new ValidationError(`Row ${index + 1}: ${problems[0]}`);
      if (!draft.stage) throw new ValidationError(`Row ${index + 1}: Missing stage`);
      return draft;
    });
    await db.transaction(async (tx) => {
      for (const draft of rows) {
        let stageId = byName.get(draft.stage.toLowerCase());
        if (!stageId) {
          stageId = slugify(draft.stage) || `stage-${nextOrder}`;
          await tx
            .insert(stages)
            .values({ id: stageId, festivalId, name: draft.stage, sortOrder: nextOrder++ });
          byName.set(draft.stage.toLowerCase(), stageId);
        }
        const times = setInstants({
          day: draft.day,
          start: draft.start,
          end: draft.end || null,
          timeZone: festival.timeZone,
        });
        const id = await uniqueSetId(slugify(`${festivalId}-${draft.day}-${draft.artist}`));
        await tx.insert(sets).values({
          id,
          festivalId,
          stageId,
          artist: draft.artist,
          day: draft.day,
          ...times,
          sourceUrl: source,
          updatedAt: new Date(),
        });
      }
    });
    await touchFestival(db, festivalId);
    return `Imported ${rows.length} sets`;
  });
}

export type ExtractResult =
  { ok: true; rows: DraftSet[]; issues: DraftIssue[] } | { ok: false; error: string } | null;

export async function extractFromImage(_: ExtractResult, form: FormData): Promise<ExtractResult> {
  await requireAdmin();
  if (!visionEnabled()) return { ok: false, error: "Set AI_GATEWAY_API_KEY to enable" };
  const file = form.get("image");
  if (!(file instanceof File) || file.size === 0) return { ok: false, error: "Choose an image" };
  if (!file.type.startsWith("image/")) return { ok: false, error: "Not an image" };
  if (file.size > 8 * 1024 * 1024) return { ok: false, error: "Image is over 8 MB" };
  try {
    const festival = await festivalTimeZone(str(form, "festivalId"));
    const existing = await getDb()
      .select({ name: stages.name })
      .from(stages)
      .where(eq(stages.festivalId, str(form, "festivalId")));
    return {
      ok: true,
      ...(await extractSetsFromImage({
        image: new Uint8Array(await file.arrayBuffer()),
        mediaType: file.type,
        days: festivalDays(festival.startDate, festival.endDate),
        stages: existing.map((s) => s.name),
      })),
    };
  } catch (err) {
    console.error(err);
    return { ok: false, error: "Couldn't read that image" };
  }
}

// Publish

export async function publish(): Promise<ActionResult> {
  return run(async () => {
    const { version } = await publishFeed(getDb());
    return `Published v${version}`;
  });
}
