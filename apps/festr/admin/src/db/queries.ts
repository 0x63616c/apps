import { asc, sql } from "drizzle-orm";
import type { Db } from "./index";
import { festivals, sets, stages } from "./schema";
import type { FeedRows } from "../lib/feed";

export async function loadFeedRows(db: Db): Promise<FeedRows> {
  const [f, st, se] = await Promise.all([
    db.select().from(festivals).orderBy(asc(festivals.startDate)),
    db.select().from(stages),
    db.select().from(sets),
  ]);
  return { festivals: f, stages: st, sets: se };
}

function withoutId<T extends { id: string }>(row: T): Omit<T, "id"> {
  const copy: Partial<T> = { ...row };
  delete copy.id;
  return copy as Omit<T, "id">;
}

/** Upserts rows by primary key (non-destructive: rows missing from input are kept). */
export async function upsertRows(db: Db, rows: FeedRows): Promise<void> {
  await db.transaction(async (tx) => {
    for (const f of rows.festivals) {
      await tx
        .insert(festivals)
        .values(f)
        .onConflictDoUpdate({ target: festivals.id, set: withoutId(f) });
    }
    for (const s of rows.stages) {
      await tx
        .insert(stages)
        .values(s)
        .onConflictDoUpdate({
          target: [stages.festivalId, stages.id],
          set: { name: s.name, sortOrder: s.sortOrder },
        });
    }
    for (const s of rows.sets) {
      await tx
        .insert(sets)
        .values(s)
        .onConflictDoUpdate({ target: sets.id, set: withoutId(s) });
    }
  });
}

export async function touchFestival(db: Db, festivalId: string): Promise<void> {
  await db
    .update(festivals)
    .set({ updatedAt: sql`now()` })
    .where(sql`${festivals.id} = ${festivalId}`);
}
