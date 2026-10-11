import "server-only";
import { asc, count, eq } from "drizzle-orm";
import { getDb } from "@/db";
import { publishStatus } from "@/db/publish";
import { festivals, sets, stages } from "@/db/schema";

export async function listFestivals() {
  const db = getDb();
  const [rows, counts] = await Promise.all([
    db.select().from(festivals).orderBy(asc(festivals.startDate), asc(festivals.name)),
    db.select({ festivalId: sets.festivalId, sets: count() }).from(sets).groupBy(sets.festivalId),
  ]);
  const byId = new Map(counts.map((c) => [c.festivalId, c.sets]));
  return rows.map((f) => ({ ...f, setCount: byId.get(f.id) ?? 0 }));
}

export async function getFestival(id: string) {
  const db = getDb();
  const [festival] = await db.select().from(festivals).where(eq(festivals.id, id));
  if (!festival) return null;
  const [stageRows, setRows] = await Promise.all([
    db
      .select()
      .from(stages)
      .where(eq(stages.festivalId, id))
      .orderBy(asc(stages.sortOrder), asc(stages.name)),
    db.select().from(sets).where(eq(sets.festivalId, id)).orderBy(asc(sets.startAt), asc(sets.artist)),
  ]);
  return { festival, stages: stageRows, sets: setRows };
}

export async function getPublishStatus() {
  return publishStatus(getDb());
}
