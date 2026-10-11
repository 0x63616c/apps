import { MockLanguageModelV4 } from "ai/test";
import { describe, expect, it } from "vitest";
import { extractSetsFromImage } from "./vision";

function modelReturning(json: unknown) {
  return new MockLanguageModelV4({
    doGenerate: async () => ({
      content: [{ type: "text", text: JSON.stringify(json) }],
      finishReason: { unified: "stop", raw: "stop" },
      usage: {
        inputTokens: { total: 0, noCache: 0, cacheRead: 0, cacheWrite: 0 },
        outputTokens: { total: 0, text: 0, reasoning: 0 },
      },
      warnings: [],
    }),
  });
}

describe("extractSetsFromImage", () => {
  it("sends the image and normalises the model's rows into reviewable drafts", async () => {
    const model = modelReturning({
      sets: [
        { artist: "Skrillex", stage: "Main Stage", day: "2026-10-11", start: "8:40 PM", end: "22:10" },
        { artist: "Swedish House Mafia", stage: "Main Stage", day: "Sunday", start: "22:30", end: "" },
        { artist: "Mystery", stage: "Tent", day: "Monday", start: "noon", end: "" },
      ],
    });
    const { rows, issues } = await extractSetsFromImage({
      image: new Uint8Array([137, 80, 78, 71]),
      mediaType: "image/png",
      days: ["2026-10-10", "2026-10-11"],
      stages: ["Main Stage"],
      model,
    });
    expect(rows.slice(0, 2)).toEqual([
      { artist: "Skrillex", stage: "Main Stage", day: "2026-10-11", start: "20:40", end: "22:10" },
      { artist: "Swedish House Mafia", stage: "Main Stage", day: "2026-10-11", start: "22:30", end: "" },
    ]);
    expect(issues).toEqual([
      { row: 3, message: 'Unknown day "Monday"' },
      { row: 3, message: 'Bad start "noon"' },
    ]);
    const prompt = model.doGenerateCalls[0].prompt.at(-1);
    expect(JSON.stringify(prompt)).toContain("Saturday 2026-10-10");
    expect(JSON.stringify(prompt)).toContain("image/png");
  });
});
