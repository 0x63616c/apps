import Link from "next/link";
import type { PublishStatus } from "@/db/publish";
import { Logo } from "@/components/logo";
import { PublishButton } from "@/components/publish-button";
import { ThemeToggle } from "@/components/theme-toggle";
import { UserMenu } from "@/components/user-menu";

export function SiteHeader({ email, status }: { email: string; status: PublishStatus }) {
  return (
    <header className="sticky top-0 z-40 border-b bg-background/80 backdrop-blur">
      <div className="mx-auto flex h-14 w-full max-w-6xl items-center gap-6 px-6">
        <Link href="/" className="flex items-center gap-2 text-sm font-semibold">
          <Logo />
          Festr
        </Link>
        <nav className="flex items-center gap-4 text-sm">
          <Link href="/" className="text-muted-foreground transition-colors hover:text-foreground">
            Festivals
          </Link>
          <a
            href="/feed/index.json"
            target="_blank"
            rel="noreferrer"
            className="text-muted-foreground transition-colors hover:text-foreground"
          >
            Feed
          </a>
        </nav>
        <div className="ml-auto flex items-center gap-2">
          <PublishButton status={status} />
          <ThemeToggle />
          <UserMenu email={email} />
        </div>
      </div>
    </header>
  );
}
