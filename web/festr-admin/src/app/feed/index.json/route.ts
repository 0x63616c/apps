import { getDb } from "@/db";
import { readFeedFile } from "@/db/publish";
import { feedResponse } from "@/lib/feed-response";

export const dynamic = "force-dynamic";

export async function GET(request: Request): Promise<Response> {
  return feedResponse(request, await readFeedFile(getDb(), "index.json"));
}
