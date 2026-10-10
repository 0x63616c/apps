import { getDb } from "../../../db";
import { loadFeedRows } from "../../../db/queries";
import { buildFeed, etagFor, ifNoneMatchHits, serializeFeed } from "../../../lib/feed";

export const dynamic = "force-dynamic";

const CACHE_CONTROL = "public, max-age=60, s-maxage=300, stale-while-revalidate=86400";

export async function GET(request: Request): Promise<Response> {
  const body = serializeFeed(buildFeed(await loadFeedRows(getDb())));
  const etag = etagFor(body);
  const headers = { ETag: etag, "Cache-Control": CACHE_CONTROL };

  if (ifNoneMatchHits(request.headers.get("if-none-match"), etag)) {
    return new Response(null, { status: 304, headers });
  }
  return new Response(body, {
    status: 200,
    headers: { ...headers, "Content-Type": "application/json; charset=utf-8" },
  });
}
