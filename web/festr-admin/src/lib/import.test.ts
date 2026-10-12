import { describe, expect, it } from "vitest";
import { parseSetsText } from "./import";
import { festivalDays, normalizeTime, resolveDay, setInstants, startDateFor } from "./sets";

const days = festivalDays("2026-10-10", "2026-10-11");

describe("normalizeTime", () => {
  it.each([
    ["21:10", "21:10"],
    ["9:10 PM", "21:10"],
    ["9pm", "21:00"],
    ["12:30am", "00:30"],
    ["12 PM", "12:00"],
    ["21.10", "21:10"],
    ["2110", "21:10"],
    ["0030", "00:30"],
  ])("%s -> %s", (raw, expected) => expect(normalizeTime(raw)).toBe(expected));

  it.each(["25:00", "13pm", "9:75", "soon", ""])("rejects %s", (raw) =>
    expect(normalizeTime(raw)).toBeNull(),
  );
});

describe("days", () => {
  it("resolves weekday names, day numbers and dates", () => {
    expect(days).toEqual(["2026-10-10", "2026-10-11"]);
    expect(resolveDay("Sat", days)).toBe("2026-10-10");
    expect(resolveDay("sunday", days)).toBe("2026-10-11");
    expect(resolveDay("Day 2", days)).toBe("2026-10-11");
    expect(resolveDay("2026-10-11", days)).toBe("2026-10-11");
    expect(resolveDay("Friday", days)).toBeNull();
  });

  it("puts sets starting before 06:00 on the next calendar date", () => {
    expect(startDateFor("2026-10-10", "00:30")).toBe("2026-10-11");
    expect(startDateFor("2026-10-10", "23:00")).toBe("2026-10-10");
    const { startAt, endAt } = setInstants({
      day: "2026-10-10",
      start: "01:00",
      end: "02:30",
      timeZone: "America/Los_Angeles",
    });
    expect(startAt.toISOString()).toBe("2026-10-11T08:00:00.000Z");
    expect(endAt?.toISOString()).toBe("2026-10-11T09:30:00.000Z");
  });

  it("keeps past-midnight ends and open ends", () => {
    const tz = "America/Los_Angeles";
    expect(
      setInstants({ day: "2026-10-10", start: "15:00", end: "00:30", timeZone: tz }).endAt?.toISOString(),
    ).toBe("2026-10-11T07:30:00.000Z");
    expect(setInstants({ day: "2026-10-10", start: "23:00", end: null, timeZone: tz }).endAt).toBeNull();
  });
});

describe("parseSetsText", () => {
  it("parses headerless CSV in the default column order", () => {
    const { rows, issues } = parseSetsText(
      "Peggy Gou b2b Four Tet, Main Stage, Sat, 7:20 PM, 8:50 PM\nCalvin Harris, Main Stage, Sat, 23:00, late",
      days,
    );
    expect(issues).toEqual([]);
    expect(rows).toEqual([
      {
        artist: "Peggy Gou b2b Four Tet",
        stage: "Main Stage",
        day: "2026-10-10",
        start: "19:20",
        end: "20:50",
      },
      { artist: "Calvin Harris", stage: "Main Stage", day: "2026-10-10", start: "23:00", end: "" },
    ]);
  });

  it("uses a header row for column order, tabs and quoted commas", () => {
    const tsv = "Start\tEnd\tArtist\tStage\tDay\n15:00\t00:30\tFloating Points\tSunflower\t2026-10-10";
    expect(parseSetsText(tsv, days).rows[0]).toEqual({
      artist: "Floating Points",
      stage: "Sunflower",
      day: "2026-10-10",
      start: "15:00",
      end: "00:30",
    });
    const csv = 'artist,stage,day,start,end\n"Under Construction (FISHER, Chris Lake)",Main,Sat,21:10,22:40';
    expect(parseSetsText(csv, days).rows[0].artist).toBe("Under Construction (FISHER, Chris Lake)");
  });

  it("reports problems per row", () => {
    const { issues } = parseSetsText(",Main,Fri,later,", days);
    expect(issues.map((i) => i.message)).toEqual([
      "Missing artist",
      'Unknown day "Fri"',
      'Bad start "later"',
    ]);
  });
});
