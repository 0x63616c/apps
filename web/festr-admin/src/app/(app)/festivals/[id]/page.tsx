import { ImportIcon } from "lucide-react";
import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { DeleteFestivalButton } from "@/components/delete-festival-button";
import { FestivalForm } from "@/components/festival-form";
import { PageHeader } from "@/components/page-header";
import { SetsPanel } from "@/components/sets-panel";
import { StagesPanel } from "@/components/stages-panel";
import { StatusBadge } from "@/components/status-badge";
import { Button } from "@/components/ui/button";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { dateRange } from "@/lib/format";
import { festivalDays, localTimes } from "@/lib/sets";
import { getFestival } from "@/server/queries";

export async function generateMetadata({ params }: PageProps<"/festivals/[id]">): Promise<Metadata> {
  const data = await getFestival((await params).id);
  return { title: data?.festival.name ?? "Festival" };
}

export default async function FestivalPage({ params }: PageProps<"/festivals/[id]">) {
  const data = await getFestival((await params).id);
  if (!data) notFound();
  const { festival, stages, sets } = data;
  const rows = sets.map((s) => ({
    id: s.id,
    artist: s.artist,
    stageId: s.stageId,
    day: s.day ?? festival.startDate,
    sourceUrl: s.sourceUrl,
    ...localTimes(s, festival.timeZone),
  }));

  return (
    <>
      <div className="mb-2 flex items-center gap-2 text-sm text-muted-foreground">
        <Link href="/" className="transition-colors hover:text-foreground">
          Festivals
        </Link>
        <span aria-hidden="true">/</span>
        <span className="font-mono text-xs">{festival.id}</span>
      </div>
      <PageHeader
        title={
          <>
            {festival.name}
            <StatusBadge published={festival.published} />
          </>
        }
      >
        <span className="mr-2 text-sm text-muted-foreground">
          {dateRange(festival.startDate, festival.endDate)} ·{" "}
          {[festival.city, festival.region].filter(Boolean).join(", ")}
        </span>
        <Button variant="outline" asChild>
          <Link href={`/festivals/${festival.id}/import`}>
            <ImportIcon data-icon="inline-start" />
            Import
          </Link>
        </Button>
        <DeleteFestivalButton festivalId={festival.id} name={festival.name} />
      </PageHeader>
      <Tabs defaultValue="sets" className="gap-6">
        <TabsList>
          <TabsTrigger value="sets">
            Sets <span className="font-mono text-xs text-muted-foreground tabular-nums">{sets.length}</span>
          </TabsTrigger>
          <TabsTrigger value="stages">
            Stages{" "}
            <span className="font-mono text-xs text-muted-foreground tabular-nums">{stages.length}</span>
          </TabsTrigger>
          <TabsTrigger value="details">Details</TabsTrigger>
        </TabsList>
        <TabsContent value="sets">
          <SetsPanel
            festivalId={festival.id}
            days={festivalDays(festival.startDate, festival.endDate)}
            stages={stages.map((s) => ({ id: s.id, name: s.name }))}
            sets={rows}
          />
        </TabsContent>
        <TabsContent value="stages">
          <StagesPanel
            festivalId={festival.id}
            stages={stages.map((s) => ({
              id: s.id,
              name: s.name,
              sets: sets.filter((set) => set.stageId === s.id).length,
            }))}
          />
        </TabsContent>
        <TabsContent value="details">
          <FestivalForm festival={festival} />
        </TabsContent>
      </Tabs>
    </>
  );
}
