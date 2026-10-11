import { SiteHeader } from "@/components/site-header";
import { requireAdmin } from "@/server/auth";
import { getPublishStatus } from "@/server/queries";

export default async function AppLayout({ children }: { children: React.ReactNode }) {
  const session = await requireAdmin();
  const status = await getPublishStatus();
  return (
    <div className="flex min-h-svh flex-col">
      <SiteHeader email={session.sub} status={status} />
      <main className="mx-auto w-full max-w-6xl flex-1 px-6 py-8">{children}</main>
    </div>
  );
}
