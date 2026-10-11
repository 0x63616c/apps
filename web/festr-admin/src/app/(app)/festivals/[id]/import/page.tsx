import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { ImportWorkbench } from "@/components/import-workbench";
import { PageHeader } from "@/components/page-header";
import { festivalDays } from "@/lib/sets";
import { getFestival } from "@/server/queries";
import { visionEnabled } from "@/server/vision";

export const metadata: Metadata = { title: "Import sets" };

export default async function ImportPage({ params }: PageProps<"/festivals/[id]/import">) {
  const data = await getFestival((await params).id);
  if (!data) notFound();
  const { festival, stages } = data;
  return (
    <>
      <div className="mb-2 flex items-center gap-2 text-sm text-muted-foreground">
        <Link href="/" className="transition-colors hover:text-foreground">
          Festivals
        </Link>
        <span aria-hidden="true">/</span>
        <Link href={`/festivals/${festival.id}`} className="transition-colors hover:text-foreground">
          {festival.name}
        </Link>
      </div>
      <PageHeader title="Import sets" />
      <ImportWorkbench
        festivalId={festival.id}
        days={festivalDays(festival.startDate, festival.endDate)}
        stages={stages.map((s) => s.name)}
        visionEnabled={visionEnabled()}
      />
    </>
  );
}
