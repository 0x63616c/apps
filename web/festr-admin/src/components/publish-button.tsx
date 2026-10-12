"use client";

import { useTransition } from "react";
import { toast } from "sonner";
import type { PublishStatus } from "@/db/publish";
import { Button } from "@/components/ui/button";
import { Spinner } from "@/components/ui/spinner";
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip";
import { cn } from "@/lib/utils";
import { publish } from "@/server/actions";

export function PublishButton({ status }: { status: PublishStatus }) {
  const [pending, startTransition] = useTransition();
  const label = status.version ? `v${status.version}` : "Never published";
  return (
    <div className="flex items-center gap-3">
      <Tooltip>
        <TooltipTrigger asChild>
          <span className="flex items-center gap-2 font-mono text-xs text-muted-foreground">
            <span
              className={cn("size-1.5 rounded-full", status.pending ? "bg-amber-500" : "bg-success")}
              aria-hidden="true"
            />
            {label}
          </span>
        </TooltipTrigger>
        <TooltipContent>{status.pending ? "Unpublished changes" : "Up to date"}</TooltipContent>
      </Tooltip>
      <Button
        size="sm"
        disabled={pending || !status.pending}
        onClick={() =>
          startTransition(async () => {
            const result = await publish();
            if (result?.ok) toast.success(result.message);
            else if (result) toast.error(result.error);
          })
        }
      >
        {pending && <Spinner data-icon="inline-start" />}
        Publish
      </Button>
    </div>
  );
}
