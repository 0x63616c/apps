const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
const WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

function parts(day: string) {
  const [y, m, d] = day.split("-").map(Number);
  return { y, m, d, weekday: new Date(Date.UTC(y, m - 1, d)).getUTCDay() };
}

/** "Oct 10–11, 2026", "Dec 31, 2026 – Jan 1, 2027". */
export function dateRange(start: string, end: string): string {
  const a = parts(start);
  const b = parts(end);
  if (start === end) return `${MONTHS[a.m - 1]} ${a.d}, ${a.y}`;
  if (a.y !== b.y) return `${MONTHS[a.m - 1]} ${a.d}, ${a.y} – ${MONTHS[b.m - 1]} ${b.d}, ${b.y}`;
  if (a.m !== b.m) return `${MONTHS[a.m - 1]} ${a.d} – ${MONTHS[b.m - 1]} ${b.d}, ${a.y}`;
  return `${MONTHS[a.m - 1]} ${a.d}–${b.d}, ${a.y}`;
}

/** "Sat, Oct 10". */
export function dayLabel(day: string): string {
  const p = parts(day);
  return `${WEEKDAYS[p.weekday]}, ${MONTHS[p.m - 1]} ${p.d}`;
}

export function relativeTime(date: Date, now = Date.now()): string {
  const seconds = Math.round((now - date.getTime()) / 1000);
  if (seconds < 60) return "just now";
  const units: [number, string][] = [
    [60, "m"],
    [60, "h"],
    [24, "d"],
    [30, "mo"],
    [12, "y"],
  ];
  let value = seconds;
  let label = "s";
  for (const [size, unit] of units) {
    if (value < size) break;
    value = Math.floor(value / size);
    label = unit;
  }
  return `${value}${label} ago`;
}
