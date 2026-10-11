import "server-only";
import { generateText, Output, type LanguageModel } from "ai";
import { z } from "zod";
import { normalizeDraft, type DraftIssue, type DraftSet } from "@/lib/import";
import { weekdayOf } from "@/lib/sets";

const WEEKDAY_NAMES = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];

/** The vision model runs through Vercel AI Gateway; override with AI_VISION_MODEL. */
export const DEFAULT_VISION_MODEL = "google/gemini-2.5-flash";

export function visionEnabled(): boolean {
  return Boolean(
    process.env.AI_GATEWAY_API_KEY || process.env.VERCEL_OIDC_TOKEN || process.env.FESTR_VISION_MOCK,
  );
}

export const extractionSchema = z.object({
  sets: z.array(
    z.object({
      artist: z.string().describe("Artist or act exactly as printed"),
      stage: z.string().describe("Stage name as printed; empty if the poster has a single stage"),
      day: z.string().describe("Festival day as YYYY-MM-DD, chosen from the provided days"),
      start: z.string().describe("Start time, 24-hour HH:MM local time"),
      end: z.string().describe("End time, 24-hour HH:MM local time; empty string if not printed"),
    }),
  ),
});

export interface ExtractInput {
  image: Uint8Array;
  mediaType: string;
  days: string[];
  stages: string[];
  model?: LanguageModel;
}

async function mockModel(): Promise<LanguageModel> {
  const { MockLanguageModelV4 } = await import("ai/test");
  const sets = [
    { artist: "Peggy Gou b2b Four Tet", stage: "Main Stage", day: "Sat", start: "7:20 PM", end: "8:50 PM" },
    { artist: "Calvin Harris", stage: "Main Stage", day: "Sat", start: "11:00 PM", end: "" },
  ];
  return new MockLanguageModelV4({
    doGenerate: async () => ({
      content: [{ type: "text", text: JSON.stringify({ sets }) }],
      finishReason: { unified: "stop", raw: "stop" },
      usage: {
        inputTokens: { total: 0, noCache: 0, cacheRead: 0, cacheWrite: 0 },
        outputTokens: { total: 0, text: 0, reasoning: 0 },
      },
      warnings: [],
    }),
  });
}

/** Reads a set-times poster into draft rows for review. Nothing is saved here. */
export async function extractSetsFromImage(
  input: ExtractInput,
): Promise<{ rows: DraftSet[]; issues: DraftIssue[] }> {
  const dayList = input.days.map((d) => `${WEEKDAY_NAMES[weekdayOf(d)]} ${d}`).join(", ");
  const model =
    input.model ??
    (process.env.FESTR_VISION_MOCK ? await mockModel() : process.env.AI_VISION_MODEL || DEFAULT_VISION_MODEL);
  const { output } = await generateText({
    model,
    output: Output.object({ schema: extractionSchema }),
    temperature: 0,
    messages: [
      {
        role: "user",
        content: [
          {
            type: "text",
            text: [
              "Extract every performance from this festival set-times poster.",
              `Festival days: ${dayList}. Sets after midnight belong to the previous day.`,
              input.stages.length ? `Known stages: ${input.stages.join(", ")}.` : "",
              "Only include what is printed. Do not guess missing times.",
            ].join(" "),
          },
          { type: "file", data: input.image, mediaType: input.mediaType },
        ],
      },
    ],
  });
  const rows: DraftSet[] = [];
  const issues: DraftIssue[] = [];
  (output?.sets ?? []).forEach((raw, index) => {
    const { draft, problems } = normalizeDraft(raw, input.days);
    rows.push(draft);
    for (const message of problems) issues.push({ row: index + 1, message });
  });
  return { rows, issues };
}
