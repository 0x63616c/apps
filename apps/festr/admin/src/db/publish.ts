import { desc, eq } from "drizzle-orm";
import type { Db } from "./index";
import { loadFeedRows } from "./queries";
import { feedFiles, publishes } from "./schema";
import { buildFeed, feedFiles as buildFeedFiles, type Feed } from "../lib/feed";

export async function currentFeed(db: Db): Promise<Feed> {
  return buildFeed(await loadFeedRows(db));
}

function contentHash(feed: Feed): string {
  return buildFeedFiles(feed)[0].etag;
}

export interface PublishStatus {
  version: number | null;
  publishedAt: Date | null;
  pending: boolean;
}

export async function publishStatus(db: Db): Promise<PublishStatus> {
  const [latest] = await db.select().from(publishes).orderBy(desc(publishes.version)).limit(1);
  const hash = contentHash(await currentFeed(db));
  return {
    version: latest?.version ?? null,
    publishedAt: latest?.createdAt ?? null,
    pending: latest?.contentHash !== hash,
  };
}

/** Snapshots the current data into the files served under /feed/. Edits stay private until this runs. */
export async function publishFeed(db: Db): Promise<{ version: number; files: number }> {
  const feed = await currentFeed(db);
  const files = buildFeedFiles(feed);
  return db.transaction(async (tx) => {
    const [row] = await tx
      .insert(publishes)
      .values({
        contentHash: files[0].etag,
        festivalCount: feed.festivals.length,
        setCount: feed.festivals.reduce((total, f) => total + f.sets.length, 0),
      })
      .returning({ version: publishes.version });
    await tx.delete(feedFiles);
    await tx.insert(feedFiles).values(files.map((f) => ({ ...f, version: row.version })));
    return { version: row.version, files: files.length };
  });
}

export async function readFeedFile(db: Db, path: string) {
  const [file] = await db.select().from(feedFiles).where(eq(feedFiles.path, path));
  return file ?? null;
}
