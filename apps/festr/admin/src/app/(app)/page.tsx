import { PlusIcon } from "lucide-react";
import type { Metadata } from "next";
import Link from "next/link";
import { PageHeader } from "@/components/page-header";
import { StatusBadge } from "@/components/status-badge";
import { Button } from "@/components/ui/button";
import { Empty, EmptyHeader, EmptyTitle } from "@/components/ui/empty";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { dateRange, relativeTime } from "@/lib/format";
import { listFestivals } from "@/server/queries";

export const metadata: Metadata = { title: "Festivals" };

export default async function FestivalsPage() {
  const festivals = await listFestivals();
  return (
    <>
      <PageHeader title="Festivals">
        <Button asChild>
          <Link href="/festivals/new">
            <PlusIcon data-icon="inline-start" />
            New festival
          </Link>
        </Button>
      </PageHeader>
      {festivals.length === 0 ? (
        <Empty className="border">
          <EmptyHeader>
            <EmptyTitle>No festivals</EmptyTitle>
          </EmptyHeader>
        </Empty>
      ) : (
        <div className="overflow-hidden rounded-lg border">
          <Table>
            <TableHeader>
              <TableRow className="bg-muted/50 hover:bg-muted/50">
                <TableHead className="h-10 pl-4">Name</TableHead>
                <TableHead>Dates</TableHead>
                <TableHead>Location</TableHead>
                <TableHead className="text-right">Sets</TableHead>
                <TableHead>Status</TableHead>
                <TableHead className="pr-4 text-right">Updated</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {festivals.map((f) => (
                <TableRow key={f.id} className="relative h-12">
                  <TableCell className="pl-4 font-medium">
                    <Link href={`/festivals/${f.id}`} className="after:absolute after:inset-0">
                      {f.name}
                    </Link>
                  </TableCell>
                  <TableCell className="text-muted-foreground">{dateRange(f.startDate, f.endDate)}</TableCell>
                  <TableCell className="text-muted-foreground">
                    {[f.city, f.region].filter(Boolean).join(", ")}
                  </TableCell>
                  <TableCell className="text-right font-mono text-xs tabular-nums">
                    {f.setCount || "–"}
                  </TableCell>
                  <TableCell>
                    <StatusBadge published={f.published} />
                  </TableCell>
                  <TableCell className="pr-4 text-right text-muted-foreground">
                    {relativeTime(f.updatedAt)}
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </div>
      )}
    </>
  );
}
