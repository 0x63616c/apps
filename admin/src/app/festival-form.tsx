import type { FestivalRow } from "../db/schema";
import { saveFestival } from "./actions";

const TIME_ZONES = Intl.supportedValuesOf("timeZone");

export function FestivalForm({ festival }: { festival?: FestivalRow }) {
  const isNew = !festival;
  return (
    <form action={saveFestival} className="grid">
      <input type="hidden" name="isNew" value={isNew ? "1" : "0"} />
      <input type="hidden" name="originalId" value={festival?.id ?? ""} />
      <label>
        ID (slug)
        <input
          name="id"
          defaultValue={festival?.id}
          required={isNew}
          disabled={!isNew}
          pattern="[a-z0-9][a-z0-9\-]*"
          placeholder="head-trip-2026"
        />
      </label>
      <label>
        Name
        <input name="name" defaultValue={festival?.name} required />
      </label>
      <label>
        Venue
        <input name="venue" defaultValue={festival?.venue} required />
      </label>
      <label>
        City
        <input name="city" defaultValue={festival?.city} required />
      </label>
      <label>
        Region
        <input name="region" defaultValue={festival?.region} required placeholder="CA" />
      </label>
      <label>
        Country
        <input name="country" defaultValue={festival?.country ?? "US"} maxLength={2} />
      </label>
      <label>
        Time zone (IANA)
        <input
          name="timeZone"
          list="tz-list"
          defaultValue={festival?.timeZone ?? "America/Los_Angeles"}
          required
        />
        <datalist id="tz-list">
          {TIME_ZONES.map((tz) => (
            <option key={tz} value={tz} />
          ))}
        </datalist>
      </label>
      <label>
        Start date
        <input type="date" name="startDate" defaultValue={festival?.startDate} required />
      </label>
      <label>
        End date
        <input type="date" name="endDate" defaultValue={festival?.endDate} required />
      </label>
      <label className="wide">
        Source URL
        <input type="url" name="sourceUrl" defaultValue={festival?.sourceUrl ?? ""} />
      </label>
      <label className="wide">
        Lineup (one artist per line)
        <textarea name="lineup" defaultValue={festival?.lineup.join("\n")} />
      </label>
      <label className="check">
        <input type="checkbox" name="published" defaultChecked={festival?.published ?? true} />
        Published (included in /api/feed)
      </label>
      <div className="wide">
        <button type="submit">{isNew ? "Create festival" : "Save festival"}</button>
      </div>
    </form>
  );
}
