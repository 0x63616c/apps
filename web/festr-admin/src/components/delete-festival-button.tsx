"use client";

import { Trash2Icon } from "lucide-react";
import { ConfirmButton } from "@/components/confirm-button";
import { Button } from "@/components/ui/button";
import { deleteFestival } from "@/server/actions";

export function DeleteFestivalButton({ festivalId, name }: { festivalId: string; name: string }) {
  return (
    <ConfirmButton
      title="Delete festival?"
      description={`${name}, its stages and sets`}
      onConfirm={() => deleteFestival(festivalId)}
    >
      <Button variant="ghost" size="icon" aria-label="Delete festival">
        <Trash2Icon data-icon="inline-start" />
      </Button>
    </ConfirmButton>
  );
}
