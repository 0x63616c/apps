import { ifNoneMatchHits } from "./feed";

export const FEED_CACHE_CONTROL = "public, max-age=60, s-maxage=300, stale-while-revalidate=86400";

export function feedResponse(request: Request, file: { body: string; etag: string } | null): Response {
  if (!file) {
    return Response.json(
      { error: "Not published" },
      { status: 404, headers: { "Cache-Control": "no-store" } },
    );
  }
  const headers = { ETag: file.etag, "Cache-Control": FEED_CACHE_CONTROL };
  if (ifNoneMatchHits(request.headers.get("if-none-match"), file.etag)) {
    return new Response(null, { status: 304, headers });
  }
  return new Response(file.body, {
    status: 200,
    headers: { ...headers, "Content-Type": "application/json; charset=utf-8" },
  });
}
