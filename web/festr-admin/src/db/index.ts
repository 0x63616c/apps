import { drizzle, type PostgresJsDatabase } from "drizzle-orm/postgres-js";
import postgres from "postgres";
import * as schema from "./schema";

export type Db = PostgresJsDatabase<typeof schema>;

const globalForDb = globalThis as unknown as { __festrDb?: { db: Db; client: postgres.Sql } };

/** Lazily connects on first use so `next build` never needs a database. */
export function getDb(): Db {
  if (!globalForDb.__festrDb) {
    const url = process.env.DATABASE_URL;
    if (!url) throw new Error("DATABASE_URL is not set");
    // prepare: false keeps this compatible with transaction-mode poolers (Neon, Supabase, pgbouncer).
    const client = postgres(url, { prepare: false, max: process.env.VERCEL ? 1 : 10 });
    globalForDb.__festrDb = { db: drizzle(client, { schema }), client };
  }
  return globalForDb.__festrDb.db;
}

export async function closeDb(): Promise<void> {
  if (globalForDb.__festrDb) {
    await globalForDb.__festrDb.client.end();
    globalForDb.__festrDb = undefined;
  }
}

export { schema };
