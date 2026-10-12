import { describe, expect, it } from "vitest";
import {
  addDays,
  formatInZone,
  isValidTimeZone,
  localSetTimesToUtc,
  toIsoUtc,
  zonedWallTimeToUtc,
} from "./time";

const LA = "America/Los_Angeles";
const iso = (d: Date | null) => (d ? toIsoUtc(d) : null);

describe("zonedWallTimeToUtc", () => {
  it("converts PDT wall time", () => {
    expect(iso(zonedWallTimeToUtc("2026-10-10", "23:00", LA))).toBe("2026-10-11T06:00:00Z");
  });

  it("converts PST wall time", () => {
    expect(iso(zonedWallTimeToUtc("2026-12-01", "20:00", LA))).toBe("2026-12-02T04:00:00Z");
  });

  it("handles DST fall-back day (ambiguous 01:30 -> earlier, PDT)", () => {
    expect(iso(zonedWallTimeToUtc("2026-11-01", "01:30", LA))).toBe("2026-11-01T08:30:00Z");
    expect(iso(zonedWallTimeToUtc("2026-11-01", "03:00", LA))).toBe("2026-11-01T11:00:00Z");
  });

  it("handles DST spring-forward gap (02:30 does not exist -> 03:30 PDT)", () => {
    expect(iso(zonedWallTimeToUtc("2026-03-08", "02:30", LA))).toBe("2026-03-08T10:30:00Z");
    expect(iso(zonedWallTimeToUtc("2026-03-08", "01:30", LA))).toBe("2026-03-08T09:30:00Z");
    expect(iso(zonedWallTimeToUtc("2026-03-08", "03:30", LA))).toBe("2026-03-08T10:30:00Z");
  });

  it("works for zones east of UTC and UTC itself", () => {
    expect(iso(zonedWallTimeToUtc("2026-07-01", "12:00", "Europe/Amsterdam"))).toBe("2026-07-01T10:00:00Z");
    expect(iso(zonedWallTimeToUtc("2026-07-01", "00:15", "Asia/Kolkata"))).toBe("2026-06-30T18:45:00Z");
    expect(iso(zonedWallTimeToUtc("2026-07-01", "12:00", "UTC"))).toBe("2026-07-01T12:00:00Z");
  });

  it("rejects bad input", () => {
    expect(() => zonedWallTimeToUtc("2026-02-30", "12:00", LA)).toThrow();
    expect(() => zonedWallTimeToUtc("2026-02-01", "25:00", LA)).toThrow();
    expect(() => zonedWallTimeToUtc("2026-02-01", "12:00", "Mars/Olympus")).toThrow();
    expect(isValidTimeZone("Mars/Olympus")).toBe(false);
    expect(isValidTimeZone(LA)).toBe(true);
  });
});

describe("localSetTimesToUtc", () => {
  it("converts a same-day set", () => {
    const r = localSetTimesToUtc({ date: "2026-10-10", startTime: "16:30", endTime: "19:00", timeZone: LA });
    expect(iso(r.startAt)).toBe("2026-10-10T23:30:00Z");
    expect(iso(r.endAt)).toBe("2026-10-11T02:00:00Z");
  });

  it("rolls end past midnight to the next day", () => {
    const r = localSetTimesToUtc({ date: "2026-10-10", startTime: "15:00", endTime: "00:30", timeZone: LA });
    expect(iso(r.startAt)).toBe("2026-10-10T22:00:00Z");
    expect(iso(r.endAt)).toBe("2026-10-11T07:30:00Z");
  });

  it("handles past-midnight end across the DST fall-back night", () => {
    const r = localSetTimesToUtc({ date: "2026-10-31", startTime: "22:00", endTime: "02:00", timeZone: LA });
    expect(iso(r.startAt)).toBe("2026-11-01T05:00:00Z");
    expect(iso(r.endAt)).toBe("2026-11-01T10:00:00Z");
  });

  it("supports open-ended sets", () => {
    for (const endTime of [undefined, null, "", "  "]) {
      const r = localSetTimesToUtc({ date: "2026-10-10", startTime: "23:00", endTime, timeZone: LA });
      expect(iso(r.startAt)).toBe("2026-10-11T06:00:00Z");
      expect(r.endAt).toBeNull();
    }
  });

  it("rejects end equal to start", () => {
    expect(() =>
      localSetTimesToUtc({ date: "2026-10-10", startTime: "20:00", endTime: "20:00", timeZone: LA }),
    ).toThrow();
  });
});

describe("formatting helpers", () => {
  it("formats back to local wall time", () => {
    expect(formatInZone(new Date("2026-10-11T06:00:00Z"), LA)).toEqual({ date: "2026-10-10", time: "23:00" });
    expect(formatInZone(new Date("2026-11-01T10:00:00Z"), LA)).toEqual({ date: "2026-11-01", time: "02:00" });
  });

  it("round-trips local -> utc -> local", () => {
    const d = zonedWallTimeToUtc("2026-10-11", "22:30", LA);
    expect(formatInZone(d, LA)).toEqual({ date: "2026-10-11", time: "22:30" });
  });

  it("strips fractional seconds", () => {
    expect(toIsoUtc(new Date("2026-10-11T06:00:00.123Z"))).toBe("2026-10-11T06:00:00Z");
  });

  it("adds days across month boundaries", () => {
    expect(addDays("2026-10-31", 1)).toBe("2026-11-01");
    expect(addDays("2026-12-31", 1)).toBe("2027-01-01");
  });
});
