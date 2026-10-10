#!/usr/bin/env python3
"""Builds Festr/Resources/seed-feed.json (feed schema v1) from data/festivals.source.json.

The source file uses local wall-clock times in each festival's IANA time zone. An end earlier
than the start means the set runs past midnight; a null end is an open-ended closer.
"""
import json
import pathlib
import re
import sys
from datetime import date, datetime, time, timedelta, timezone
from zoneinfo import ZoneInfo

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE = ROOT / "data" / "festivals.source.json"
OUTPUT = ROOT / "Festr" / "Resources" / "seed-feed.json"


def slug(text: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")


def instant(day: date, hhmm: str, tz: ZoneInfo, after: datetime | None = None) -> datetime:
    hour, minute = map(int, hhmm.split(":"))
    local = datetime.combine(day, time(hour, minute), tzinfo=tz)
    if after is not None and local <= after:
        local = datetime.combine(day + timedelta(days=1), time(hour, minute), tzinfo=tz)
    return local.astimezone(timezone.utc)


def iso(moment: datetime) -> str:
    return moment.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def build(source: dict) -> dict:
    festivals = []
    for item in source["festivals"]:
        tz = ZoneInfo(item["timeZone"])
        stages = [{"id": stage["id"], "name": stage["name"], "sortOrder": index} for index, stage in enumerate(item.get("stages", []))]
        stage_ids = {stage["id"] for stage in stages}
        sets = []
        used_ids: set[str] = set()
        for entry in item.get("sets", []):
            assert entry["stage"] in stage_ids, f"{item['id']}: unknown stage {entry['stage']}"
            day = date.fromisoformat(entry["localDate"])
            start_local = datetime.combine(day, time(*map(int, entry["localStart"].split(":"))), tzinfo=tz)
            # Sets starting in the small hours belong to the previous festival day.
            if start_local.hour < 6:
                start_local += timedelta(days=1)
            start = start_local.astimezone(timezone.utc)
            end = instant(start_local.date(), entry["localEnd"], tz, after=start_local) if entry.get("localEnd") else None
            base_id = f"{item['id']}-{entry['localDate']}-{slug(entry['artist'])}"
            set_id, n = base_id, 2
            while set_id in used_ids:
                set_id, n = f"{base_id}-{n}", n + 1
            used_ids.add(set_id)
            sets.append({
                "id": set_id,
                "artist": entry["artist"],
                "stageId": entry["stage"],
                "day": entry["localDate"],
                "start": iso(start),
                "end": iso(end) if end else None,
                "sourceURL": entry.get("sourceURL", item.get("sourceURL")),
                "updatedAt": item["updatedAt"],
            })
        lineup = list(dict.fromkeys(item.get("lineup", []) + [entry["artist"] for entry in item.get("sets", [])]))
        festivals.append({
            "id": item["id"],
            "name": item["name"],
            "venue": item["venue"],
            "city": item["city"],
            "region": item["region"],
            "country": item.get("country", "US"),
            "timeZone": item["timeZone"],
            "startDate": item["startDate"],
            "endDate": item["endDate"],
            "sourceURL": item.get("sourceURL"),
            "links": {"website": item.get("links", {}).get("website"), "tickets": item.get("links", {}).get("tickets")},
            "updatedAt": item["updatedAt"],
            "lineup": lineup,
            "stages": stages,
            "sets": sets,
        })
    festivals.sort(key=lambda festival: festival["startDate"])
    return {"schemaVersion": 1, "generatedAt": source["generatedAt"], "festivals": festivals}


if __name__ == "__main__":
    feed = build(json.loads(SOURCE.read_text()))
    text = json.dumps(feed, indent=2, ensure_ascii=False) + "\n"
    if "--check" in sys.argv:
        if OUTPUT.read_text() != text:
            sys.exit("seed-feed.json is out of date; run scripts/make-seed-feed.py")
        print("seed-feed.json is up to date")
    else:
        OUTPUT.parent.mkdir(parents=True, exist_ok=True)
        OUTPUT.write_text(text)
        print(f"Wrote {OUTPUT.relative_to(ROOT)} ({len(feed['festivals'])} festivals)")
