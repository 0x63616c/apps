"use client";

import { useActionState, useEffect } from "react";
import { toast } from "sonner";
import type { FestivalRow } from "@/db/schema";
import { Button } from "@/components/ui/button";
import { Field, FieldGroup, FieldLabel, FieldSeparator } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Spinner } from "@/components/ui/spinner";
import { Switch } from "@/components/ui/switch";
import { Textarea } from "@/components/ui/textarea";
import { saveFestival } from "@/server/actions";

const US_TIME_ZONES = [
  ["America/New_York", "Eastern"],
  ["America/Chicago", "Central"],
  ["America/Denver", "Mountain"],
  ["America/Phoenix", "Arizona"],
  ["America/Los_Angeles", "Pacific"],
  ["America/Anchorage", "Alaska"],
  ["Pacific/Honolulu", "Hawaii"],
] as const;

export function FestivalForm({ festival }: { festival?: FestivalRow }) {
  const [state, action, pending] = useActionState(saveFestival, null);
  useEffect(() => {
    if (state?.ok && state.message) toast.success(state.message);
    if (state?.ok === false) toast.error(state.error);
  }, [state]);
  const zones = US_TIME_ZONES.some(([id]) => id === festival?.timeZone)
    ? US_TIME_ZONES
    : festival
      ? [...US_TIME_ZONES, [festival.timeZone, festival.timeZone] as const]
      : US_TIME_ZONES;

  return (
    <form action={action} className="max-w-2xl">
      <input type="hidden" name="originalId" value={festival?.id ?? ""} />
      <FieldGroup className="gap-6">
        <Field>
          <FieldLabel htmlFor="name">Name</FieldLabel>
          <Input id="name" name="name" defaultValue={festival?.name} required />
        </Field>
        <div className="grid gap-6 sm:grid-cols-2">
          <Field>
            <FieldLabel htmlFor="startDate">Start</FieldLabel>
            <Input id="startDate" name="startDate" type="date" defaultValue={festival?.startDate} required />
          </Field>
          <Field>
            <FieldLabel htmlFor="endDate">End</FieldLabel>
            <Input id="endDate" name="endDate" type="date" defaultValue={festival?.endDate} required />
          </Field>
        </div>
        <Field>
          <FieldLabel htmlFor="venue">Venue</FieldLabel>
          <Input id="venue" name="venue" defaultValue={festival?.venue} />
        </Field>
        <div className="grid gap-6 sm:grid-cols-[1fr_6rem_1fr]">
          <Field>
            <FieldLabel htmlFor="city">City</FieldLabel>
            <Input id="city" name="city" defaultValue={festival?.city} required />
          </Field>
          <Field>
            <FieldLabel htmlFor="region">State</FieldLabel>
            <Input
              id="region"
              name="region"
              defaultValue={festival?.region}
              maxLength={2}
              className="uppercase"
            />
          </Field>
          <Field>
            <FieldLabel htmlFor="timeZone">Time zone</FieldLabel>
            <Select name="timeZone" defaultValue={festival?.timeZone ?? "America/Los_Angeles"}>
              <SelectTrigger id="timeZone" className="w-full">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {zones.map(([id, label]) => (
                  <SelectItem key={id} value={id}>
                    {label}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </Field>
        </div>
        <FieldSeparator />
        <div className="grid gap-6 sm:grid-cols-2">
          <Field>
            <FieldLabel htmlFor="websiteUrl">Website</FieldLabel>
            <Input id="websiteUrl" name="websiteUrl" type="url" defaultValue={festival?.websiteUrl ?? ""} />
          </Field>
          <Field>
            <FieldLabel htmlFor="ticketsUrl">Tickets</FieldLabel>
            <Input id="ticketsUrl" name="ticketsUrl" type="url" defaultValue={festival?.ticketsUrl ?? ""} />
          </Field>
        </div>
        <Field>
          <FieldLabel htmlFor="sourceUrl">Times source</FieldLabel>
          <Input id="sourceUrl" name="sourceUrl" type="url" defaultValue={festival?.sourceUrl ?? ""} />
        </Field>
        <Field>
          <FieldLabel htmlFor="lineup">Lineup</FieldLabel>
          <Textarea
            id="lineup"
            name="lineup"
            rows={6}
            placeholder="One artist per line"
            defaultValue={festival?.lineup.join("\n")}
            className="font-mono text-xs"
          />
        </Field>
        <FieldSeparator />
        <Field orientation="horizontal">
          <Switch id="published" name="published" defaultChecked={festival?.published ?? true} />
          <FieldLabel htmlFor="published">Show in app</FieldLabel>
        </Field>
        <div>
          <Button type="submit" disabled={pending}>
            {pending && <Spinner data-icon="inline-start" />}
            {festival ? "Save" : "Create"}
          </Button>
        </div>
      </FieldGroup>
    </form>
  );
}
