import { getDb } from "@/db";
import { readFeedFile } from "@/db/publish";
import { feedResponse } from "@/lib/feed-response";

export const dynamic = "force-dynamic";

export async function GET(request: Request, ctx: RouteContext<"/feed/festivals/[file]">): Promise<Response> {
  const { file } = await ctx.params;
  const id = file.endsWith(".json") ? file.slice(0, -5) : "";
  if (!/^[a-z0-9][a-z0-9-]*$/.test(id)) return feedResponse(request, null);
  return feedResponse(request, await readFeedFile(getDb(), `festivals/${id}.json`));
}
