import { cn } from "@/lib/utils";

export function Logo({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true" className={cn("size-5", className)}>
      <rect x="3" y="5" width="18" height="3.5" rx="1.75" fill="currentColor" />
      <rect x="3" y="10.25" width="13" height="3.5" rx="1.75" fill="currentColor" opacity="0.7" />
      <rect x="3" y="15.5" width="8" height="3.5" rx="1.75" fill="currentColor" opacity="0.45" />
    </svg>
  );
}
