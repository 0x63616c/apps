import { Badge } from "@/components/ui/badge";

export function StatusBadge({ published }: { published: boolean }) {
  return published ? (
    <Badge variant="outline" className="gap-1.5">
      <span className="size-1.5 rounded-full bg-success" aria-hidden="true" />
      Live
    </Badge>
  ) : (
    <Badge variant="outline" className="gap-1.5 text-muted-foreground">
      <span className="size-1.5 rounded-full bg-muted-foreground" aria-hidden="true" />
      Hidden
    </Badge>
  );
}
