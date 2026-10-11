const DATE_RE = /^(\d{4})-(\d{2})-(\d{2})$/;
const TIME_RE = /^(\d{2}):(\d{2})(?::(\d{2}))?$/;

const formatters = new Map<string, Intl.DateTimeFormat>();

function formatterFor(timeZone: string): Intl.DateTimeFormat {
  let f = formatters.get(timeZone);
  if (!f) {
    f = new Intl.DateTimeFormat("en-US", {
      timeZone,
      hourCycle: "h23",
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit",
    });
    formatters.set(timeZone, f);
  }
  return f;
}

export function isValidTimeZone(timeZone: string): boolean {
  if (!timeZone) return false;
  try {
    formatterFor(timeZone);
    return true;
  } catch {
    return false;
  }
}

export function isValidDate(value: string): boolean {
  const m = DATE_RE.exec(value);
  if (!m) return false;
  const d = new Date(Date.UTC(+m[1], +m[2] - 1, +m[3]));
  return d.getUTCFullYear() === +m[1] && d.getUTCMonth() === +m[2] - 1 && d.getUTCDate() === +m[3];
}

function parseDate(value: string): [number, number, number] {
  if (!isValidDate(value)) throw new Error(`Invalid date "${value}" (expected YYYY-MM-DD)`);
  const m = DATE_RE.exec(value)!;
  return [+m[1], +m[2], +m[3]];
}

function parseTime(value: string): [number, number, number] {
  const m = TIME_RE.exec(value);
  if (!m || +m[1] > 23 || +m[2] > 59 || +(m[3] ?? 0) > 59) {
    throw new Error(`Invalid time "${value}" (expected HH:MM)`);
  }
  return [+m[1], +m[2], +(m[3] ?? 0)];
}

interface WallParts {
  year: number;
  month: number;
  day: number;
  hour: number;
  minute: number;
  second: number;
}

function wallParts(instantMs: number, timeZone: string): WallParts {
  const out: Record<string, number> = {};
  for (const p of formatterFor(timeZone).formatToParts(new Date(instantMs))) {
    if (p.type !== "literal") out[p.type] = Number(p.value);
  }
  return {
    year: out.year,
    month: out.month,
    day: out.day,
    hour: out.hour,
    minute: out.minute,
    second: out.second,
  };
}

/** Offset (local minus UTC) in ms for the given instant in the given zone. */
export function zoneOffsetMs(instantMs: number, timeZone: string): number {
  const w = wallParts(instantMs, timeZone);
  const asUtc = Date.UTC(w.year, w.month - 1, w.day, w.hour, w.minute, w.second);
  return asUtc - Math.floor(instantMs / 1000) * 1000;
}

/**
 * Converts a local wall-clock date + time in `timeZone` to a UTC instant.
 * Ambiguous times (DST fall-back) resolve to the earlier occurrence; nonexistent
 * times (DST spring-forward gap) are shifted forward by the gap length.
 */
export function zonedWallTimeToUtc(date: string, time: string, timeZone: string): Date {
  if (!isValidTimeZone(timeZone)) throw new Error(`Invalid time zone "${timeZone}"`);
  const [y, mo, d] = parseDate(date);
  const [h, mi, s] = parseTime(time);
  const wall = Date.UTC(y, mo - 1, d, h, mi, s);

  const o1 = zoneOffsetMs(wall, timeZone);
  const t1 = wall - o1;
  const o2 = zoneOffsetMs(t1, timeZone);
  if (o1 === o2) return new Date(t1);
  const t2 = wall - o2;
  if (zoneOffsetMs(t2, timeZone) === o2) return new Date(t2);
  return new Date(t1);
}

export function addDays(date: string, days: number): string {
  const [y, m, d] = parseDate(date);
  return new Date(Date.UTC(y, m - 1, d + days)).toISOString().slice(0, 10);
}

function minutesOf(time: string): number {
  const [h, m, s] = parseTime(time);
  return h * 3600 + m * 60 + s;
}

export interface LocalSetTimes {
  /** Local calendar date the set starts on (YYYY-MM-DD). */
  date: string;
  /** Local start time (HH:MM). */
  startTime: string;
  /** Local end time (HH:MM); empty/undefined means open-ended. Earlier than start means next day. */
  endTime?: string | null;
  timeZone: string;
}

export function localSetTimesToUtc(input: LocalSetTimes): { startAt: Date; endAt: Date | null } {
  const startAt = zonedWallTimeToUtc(input.date, input.startTime, input.timeZone);
  const endTime = input.endTime?.trim();
  if (!endTime) return { startAt, endAt: null };
  if (minutesOf(endTime) === minutesOf(input.startTime)) {
    throw new Error("End time must differ from start time");
  }
  const endDate = minutesOf(endTime) < minutesOf(input.startTime) ? addDays(input.date, 1) : input.date;
  const endAt = zonedWallTimeToUtc(endDate, endTime, input.timeZone);
  if (endAt.getTime() <= startAt.getTime()) throw new Error("End must be after start");
  return { startAt, endAt };
}

/** Formats an instant as local wall-clock date (YYYY-MM-DD) and time (HH:MM) in `timeZone`. */
export function formatInZone(instant: Date, timeZone: string): { date: string; time: string } {
  const w = wallParts(instant.getTime(), timeZone);
  const pad = (n: number) => String(n).padStart(2, "0");
  return {
    date: `${w.year}-${pad(w.month)}-${pad(w.day)}`,
    time: `${pad(w.hour)}:${pad(w.minute)}`,
  };
}

/** UTC ISO-8601 with 'Z' and no fractional seconds. */
export function toIsoUtc(instant: Date): string {
  return instant.toISOString().replace(/\.\d{3}Z$/, "Z");
}
