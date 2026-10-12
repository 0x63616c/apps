"use client";

import { CheckIcon, PlusIcon, Trash2Icon } from "lucide-react";
import { useActionState, useEffect, useRef } from "react";
import { toast } from "sonner";
import { ConfirmButton } from "@/components/confirm-button";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { deleteStage, saveStage, type ActionResult } from "@/server/actions";

interface StageView {
  id: string;
  name: string;
  sets: number;
}

function useToast(state: ActionResult, onSuccess?: () => void) {
  useEffect(() => {
    if (state?.ok) {
      if (state.message) toast.success(state.message);
      onSuccess?.();
    }
    if (state?.ok === false) toast.error(state.error);
  }, [state, onSuccess]);
}

export function StagesPanel({ festivalId, stages }: { festivalId: string; stages: StageView[] }) {
  const [state, action, pending] = useActionState(saveStage, null);
  const form = useRef<HTMLFormElement>(null);
  useToast(state, () => form.current?.reset());

  return (
    <div className="flex max-w-2xl flex-col gap-4">
      <form ref={form} action={action} className="flex items-center gap-2">
        <input type="hidden" name="festivalId" value={festivalId} />
        <Input name="name" placeholder="Stage name" aria-label="Stage name" required className="max-w-xs" />
        <Button type="submit" variant="outline" disabled={pending}>
          <PlusIcon data-icon="inline-start" />
          Add stage
        </Button>
      </form>
      {stages.length > 0 && (
        <div className="overflow-hidden rounded-lg border">
          <Table>
            <TableHeader>
              <TableRow className="bg-muted/50 hover:bg-muted/50">
                <TableHead className="h-10 pl-4">Name</TableHead>
                <TableHead className="w-20 text-right">Sets</TableHead>
                <TableHead className="w-16 pr-4">
                  <span className="sr-only">Actions</span>
                </TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {stages.map((stage) => (
                <StageRow key={stage.id} festivalId={festivalId} stage={stage} />
              ))}
            </TableBody>
          </Table>
        </div>
      )}
    </div>
  );
}

function StageRow({ festivalId, stage }: { festivalId: string; stage: StageView }) {
  const [state, action, pending] = useActionState(saveStage, null);
  useToast(state);
  return (
    <TableRow className="h-12">
      <TableCell className="pl-4">
        <form action={action} className="flex items-center gap-2">
          <input type="hidden" name="festivalId" value={festivalId} />
          <input type="hidden" name="stageId" value={stage.id} />
          <Input
            name="name"
            defaultValue={stage.name}
            aria-label={`${stage.name} name`}
            className="h-8 max-w-xs border-transparent bg-transparent shadow-none hover:border-input focus-visible:border-ring dark:bg-transparent"
          />
          <Button type="submit" variant="ghost" size="icon-sm" aria-label="Save name" disabled={pending}>
            <CheckIcon data-icon="inline-start" />
          </Button>
        </form>
      </TableCell>
      <TableCell className="text-right font-mono text-xs tabular-nums">{stage.sets}</TableCell>
      <TableCell className="pr-4">
        <div className="flex justify-end">
          <ConfirmButton
            title="Delete stage?"
            description={stage.sets ? `${stage.name} and its ${stage.sets} sets` : stage.name}
            onConfirm={() => deleteStage(festivalId, stage.id)}
          >
            <Button variant="ghost" size="icon-sm" aria-label={`Delete ${stage.name}`}>
              <Trash2Icon data-icon="inline-start" />
            </Button>
          </ConfirmButton>
        </div>
      </TableCell>
    </TableRow>
  );
}
