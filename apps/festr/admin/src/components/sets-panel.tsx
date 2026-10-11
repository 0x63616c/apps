"use client";

import { PencilIcon, PlusIcon, Trash2Icon } from "lucide-react";
import { useActionState, useEffect, useState } from "react";
import { toast } from "sonner";
import { ConfirmButton } from "@/components/confirm-button";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Empty, EmptyHeader, EmptyTitle } from "@/components/ui/empty";
import { Field, FieldGroup, FieldLabel } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Spinner } from "@/components/ui/spinner";
import { Switch } from "@/components/ui/switch";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { dayLabel } from "@/lib/format";
import { deleteSet, saveSet } from "@/server/actions";

export interface SetRowView {
  id: string;
  artist: string;
  stageId: string;
  day: string;
  start: string;
  end: string | null;
  sourceUrl: string | null;
}

interface Props {
  festivalId: string;
  days: string[];
  stages: { id: string; name: string }[];
  sets: SetRowView[];
}

const crossesMidnight = (s: SetRowView) => s.end !== null && s.end < s.start;

export function SetsPanel({ festivalId, days, stages, sets }: Props) {
  const [editing, setEditing] = useState<SetRowView | "new" | null>(null);
  const stageName = new Map(stages.map((s) => [s.id, s.name]));
  const byDay = days
    .map((day) => ({ day, sets: sets.filter((s) => s.day === day) }))
    .filter((group) => group.sets.length > 0);

  return (
    <div className="flex flex-col gap-6">
      <div className="flex items-center justify-end">
        <Button onClick={() => setEditing("new")} disabled={stages.length === 0}>
          <PlusIcon data-icon="inline-start" />
          Add set
        </Button>
      </div>
      {byDay.length === 0 && (
        <Empty className="border">
          <EmptyHeader>
            <EmptyTitle>{stages.length === 0 ? "Add a stage first" : "No sets"}</EmptyTitle>
          </EmptyHeader>
        </Empty>
      )}
      {byDay.map(({ day, sets: daySets }) => (
        <section key={day} className="flex flex-col gap-3">
          <h2 className="flex items-center gap-2 text-sm font-medium">
            {dayLabel(day)}
            <span className="font-mono text-xs text-muted-foreground tabular-nums">{daySets.length}</span>
          </h2>
          <div className="overflow-hidden rounded-lg border">
            <Table className="table-fixed">
              <TableHeader>
                <TableRow className="bg-muted/50 hover:bg-muted/50">
                  <TableHead className="h-10 w-40 pl-4">Time</TableHead>
                  <TableHead>Artist</TableHead>
                  <TableHead className="w-72">Stage</TableHead>
                  <TableHead className="w-24 pr-4">
                    <span className="sr-only">Actions</span>
                  </TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {daySets.map((set) => (
                  <TableRow key={set.id} className="group h-12">
                    <TableCell className="pl-4 font-mono text-xs tabular-nums">
                      {set.start}
                      <span className="text-muted-foreground"> – {set.end ?? "close"}</span>
                      {crossesMidnight(set) && <span className="ml-1 text-muted-foreground">+1</span>}
                    </TableCell>
                    <TableCell className="truncate font-medium">{set.artist}</TableCell>
                    <TableCell className="text-muted-foreground">
                      {stageName.get(set.stageId) ?? set.stageId}
                    </TableCell>
                    <TableCell className="pr-4">
                      <div className="flex items-center justify-end gap-1 opacity-60 transition-opacity group-hover:opacity-100 focus-within:opacity-100">
                        <Button
                          variant="ghost"
                          size="icon-sm"
                          aria-label={`Edit ${set.artist}`}
                          onClick={() => setEditing(set)}
                        >
                          <PencilIcon data-icon="inline-start" />
                        </Button>
                        <ConfirmButton
                          title="Delete set?"
                          description={set.artist}
                          onConfirm={() => deleteSet(festivalId, set.id)}
                        >
                          <Button variant="ghost" size="icon-sm" aria-label={`Delete ${set.artist}`}>
                            <Trash2Icon data-icon="inline-start" />
                          </Button>
                        </ConfirmButton>
                      </div>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </div>
        </section>
      ))}
      <SetDialog
        key={editing === null ? "closed" : editing === "new" ? "new" : editing.id}
        open={editing !== null}
        onOpenChange={(open) => !open && setEditing(null)}
        festivalId={festivalId}
        days={days}
        stages={stages}
        set={editing === "new" ? null : editing}
      />
    </div>
  );
}

function SetDialog({
  open,
  onOpenChange,
  festivalId,
  days,
  stages,
  set,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  festivalId: string;
  days: string[];
  stages: { id: string; name: string }[];
  set: SetRowView | null;
}) {
  const [state, action, pending] = useActionState(saveSet, null);
  const [openEnd, setOpenEnd] = useState(set ? set.end === null : false);
  useEffect(() => {
    if (state?.ok) {
      toast.success(state.message);
      onOpenChange(false);
    }
    if (state?.ok === false) toast.error(state.error);
  }, [state, onOpenChange]);

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>{set ? "Edit set" : "Add set"}</DialogTitle>
          <DialogDescription className="sr-only">Local festival time</DialogDescription>
        </DialogHeader>
        <form action={action} id="set-form">
          <input type="hidden" name="festivalId" value={festivalId} />
          <input type="hidden" name="setId" value={set?.id ?? ""} />
          <FieldGroup className="gap-5">
            <Field>
              <FieldLabel htmlFor="artist">Artist</FieldLabel>
              <Input id="artist" name="artist" defaultValue={set?.artist} required autoFocus />
            </Field>
            <div className="grid grid-cols-2 gap-4">
              <Field>
                <FieldLabel htmlFor="stageId">Stage</FieldLabel>
                <Select name="stageId" defaultValue={set?.stageId ?? stages[0]?.id}>
                  <SelectTrigger id="stageId" className="w-full">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    {stages.map((s) => (
                      <SelectItem key={s.id} value={s.id}>
                        {s.name}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </Field>
              <Field>
                <FieldLabel htmlFor="day">Day</FieldLabel>
                <Select name="day" defaultValue={set?.day ?? days[0]}>
                  <SelectTrigger id="day" className="w-full">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    {days.map((d) => (
                      <SelectItem key={d} value={d}>
                        {dayLabel(d)}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </Field>
            </div>
            <div className="grid grid-cols-2 gap-4">
              <Field>
                <FieldLabel htmlFor="start">Start</FieldLabel>
                <Input id="start" name="start" type="time" defaultValue={set?.start} required />
              </Field>
              <Field data-disabled={openEnd || undefined}>
                <FieldLabel htmlFor="end">End</FieldLabel>
                <Input
                  id="end"
                  name="end"
                  type="time"
                  defaultValue={set?.end ?? ""}
                  disabled={openEnd}
                  required={!openEnd}
                />
              </Field>
            </div>
            <Field orientation="horizontal">
              <Switch id="openEnd" name="openEnd" checked={openEnd} onCheckedChange={setOpenEnd} />
              <FieldLabel htmlFor="openEnd">Open end</FieldLabel>
            </Field>
            <Field>
              <FieldLabel htmlFor="sourceUrl">Source</FieldLabel>
              <Input id="sourceUrl" name="sourceUrl" type="url" defaultValue={set?.sourceUrl ?? ""} />
            </Field>
          </FieldGroup>
        </form>
        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)}>
            Cancel
          </Button>
          <Button type="submit" form="set-form" disabled={pending}>
            {pending && <Spinner data-icon="inline-start" />}
            Save
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
