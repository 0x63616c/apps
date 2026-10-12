"use client";

import { ImageIcon, Trash2Icon, UploadIcon } from "lucide-react";
import { useRouter } from "next/navigation";
import { useActionState, useEffect, useState, useTransition } from "react";
import { toast } from "sonner";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import { Field, FieldGroup, FieldLabel } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Spinner } from "@/components/ui/spinner";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Textarea } from "@/components/ui/textarea";
import { dayLabel } from "@/lib/format";
import { normalizeDraft, parseSetsText, type DraftSet } from "@/lib/import";
import { extractFromImage, importSets } from "@/server/actions";

interface Props {
  festivalId: string;
  days: string[];
  stages: string[];
  visionEnabled: boolean;
}

const EXAMPLE =
  "Peggy Gou b2b Four Tet, Main Stage, Sat, 19:20, 20:50\nCalvin Harris, Main Stage, Sat, 23:00,";

export function ImportWorkbench({ festivalId, days, stages, visionEnabled }: Props) {
  const [rows, setRows] = useState<DraftSet[]>([]);
  const [text, setText] = useState("");

  return (
    <div className="flex flex-col gap-8">
      <Tabs defaultValue="paste" className="gap-4">
        <TabsList>
          <TabsTrigger value="paste">Paste</TabsTrigger>
          <TabsTrigger value="image">Image</TabsTrigger>
        </TabsList>
        <TabsContent value="paste" className="flex max-w-3xl flex-col gap-3">
          <Textarea
            value={text}
            onChange={(e) => setText(e.target.value)}
            rows={8}
            placeholder={EXAMPLE}
            aria-label="Sets as CSV"
            className="font-mono text-xs"
          />
          <div className="flex items-center justify-between gap-4">
            <p className="font-mono text-xs text-muted-foreground">artist, stage, day, start, end</p>
            <Button
              variant="outline"
              disabled={!text.trim()}
              onClick={() => setRows(parseSetsText(text, days).rows)}
            >
              Preview
            </Button>
          </div>
        </TabsContent>
        <TabsContent value="image" className="max-w-3xl">
          <ImageExtractor festivalId={festivalId} enabled={visionEnabled} onRows={setRows} />
        </TabsContent>
      </Tabs>
      {rows.length > 0 && (
        <DraftEditor festivalId={festivalId} days={days} stages={stages} rows={rows} onChange={setRows} />
      )}
    </div>
  );
}

function ImageExtractor({
  festivalId,
  enabled,
  onRows,
}: {
  festivalId: string;
  enabled: boolean;
  onRows: (rows: DraftSet[]) => void;
}) {
  const [state, action, pending] = useActionState(extractFromImage, null);
  const [preview, setPreview] = useState<string | null>(null);
  useEffect(() => {
    if (state?.ok) {
      onRows(state.rows);
      toast.success(`Found ${state.rows.length} sets`);
    }
    if (state?.ok === false) toast.error(state.error);
  }, [state, onRows]);
  useEffect(() => () => void (preview && URL.revokeObjectURL(preview)), [preview]);

  return (
    <form action={action} className="flex flex-col gap-3">
      <input type="hidden" name="festivalId" value={festivalId} />
      {!enabled && (
        <Alert>
          <AlertDescription>Set AI_GATEWAY_API_KEY to enable.</AlertDescription>
        </Alert>
      )}
      <label
        htmlFor="image"
        className="flex min-h-56 cursor-pointer flex-col items-center justify-center gap-3 overflow-hidden rounded-lg border border-dashed bg-muted/30 p-4 text-sm text-muted-foreground transition-colors outline-none hover:bg-muted/50 has-focus-visible:border-ring has-focus-visible:ring-3 has-focus-visible:ring-ring/50"
      >
        {preview ? (
          // eslint-disable-next-line @next/next/no-img-element -- local object URL preview
          <img src={preview} alt="Selected poster" className="max-h-80 rounded-md object-contain" />
        ) : (
          <>
            <ImageIcon className="size-5" />
            Drop a set-times poster or click to choose
          </>
        )}
        <input
          id="image"
          name="image"
          type="file"
          accept="image/png,image/jpeg,image/webp"
          className="sr-only"
          disabled={!enabled}
          onChange={(e) => {
            const file = e.target.files?.[0];
            setPreview(file ? URL.createObjectURL(file) : null);
          }}
        />
      </label>
      <div className="flex justify-end">
        <Button type="submit" variant="outline" disabled={!enabled || !preview || pending}>
          {pending ? <Spinner data-icon="inline-start" /> : <UploadIcon data-icon="inline-start" />}
          Extract
        </Button>
      </div>
    </form>
  );
}

function DraftEditor({
  festivalId,
  days,
  stages,
  rows,
  onChange,
}: {
  festivalId: string;
  days: string[];
  stages: string[];
  rows: DraftSet[];
  onChange: (rows: DraftSet[]) => void;
}) {
  const router = useRouter();
  const [source, setSource] = useState("");
  const [pending, startTransition] = useTransition();
  const problems = rows.map((row) => {
    const { problems: list } = normalizeDraft(row, days);
    return row.stage.trim() ? list : [...list, "Missing stage"];
  });
  const invalid = problems.filter((p) => p.length > 0).length;
  const update = (index: number, patch: Partial<DraftSet>) =>
    onChange(rows.map((row, i) => (i === index ? { ...row, ...patch } : row)));

  return (
    <section className="flex flex-col gap-4">
      <div className="flex items-center justify-between gap-4">
        <h2 className="flex items-center gap-2 text-sm font-medium">
          Preview
          <span className="font-mono text-xs text-muted-foreground tabular-nums">{rows.length}</span>
        </h2>
        {invalid > 0 && <span className="text-sm text-destructive">{invalid} rows need fixing</span>}
      </div>
      <datalist id="stage-names">
        {stages.map((s) => (
          <option key={s} value={s} />
        ))}
      </datalist>
      <div className="overflow-hidden rounded-lg border">
        <Table>
          <TableHeader>
            <TableRow className="bg-muted/50 hover:bg-muted/50">
              <TableHead className="h-10 pl-4">Artist</TableHead>
              <TableHead className="w-44">Stage</TableHead>
              <TableHead className="w-40">Day</TableHead>
              <TableHead className="w-28">Start</TableHead>
              <TableHead className="w-28">End</TableHead>
              <TableHead className="w-12 pr-4">
                <span className="sr-only">Remove</span>
              </TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {rows.map((row, index) => {
              const bad = (needle: string) => problems[index].some((p) => p.toLowerCase().includes(needle));
              return (
                <TableRow key={index} className="h-12">
                  <TableCell className="pl-4">
                    <Input
                      value={row.artist}
                      aria-label="Artist"
                      aria-invalid={bad("artist") || undefined}
                      onChange={(e) => update(index, { artist: e.target.value })}
                      className="h-8"
                    />
                  </TableCell>
                  <TableCell>
                    <Input
                      value={row.stage}
                      list="stage-names"
                      aria-label="Stage"
                      aria-invalid={bad("stage") || undefined}
                      onChange={(e) => update(index, { stage: e.target.value })}
                      className="h-8"
                    />
                  </TableCell>
                  <TableCell>
                    <Select
                      value={days.includes(row.day) ? row.day : undefined}
                      onValueChange={(day) => update(index, { day })}
                    >
                      <SelectTrigger
                        size="sm"
                        className="w-full"
                        aria-label="Day"
                        aria-invalid={bad("day") || undefined}
                      >
                        <SelectValue placeholder={row.day || "Day"} />
                      </SelectTrigger>
                      <SelectContent>
                        {days.map((d) => (
                          <SelectItem key={d} value={d}>
                            {dayLabel(d)}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  </TableCell>
                  <TableCell>
                    <Input
                      type="time"
                      value={row.start}
                      aria-label="Start"
                      aria-invalid={bad("start") || undefined}
                      onChange={(e) => update(index, { start: e.target.value })}
                      className="h-8 font-mono text-xs"
                    />
                  </TableCell>
                  <TableCell>
                    <Input
                      type="time"
                      value={row.end}
                      aria-label="End"
                      aria-invalid={bad("end") || undefined}
                      onChange={(e) => update(index, { end: e.target.value })}
                      className="h-8 font-mono text-xs"
                    />
                  </TableCell>
                  <TableCell className="pr-4">
                    <Button
                      variant="ghost"
                      size="icon-sm"
                      aria-label="Remove row"
                      onClick={() => onChange(rows.filter((_, i) => i !== index))}
                    >
                      <Trash2Icon data-icon="inline-start" />
                    </Button>
                  </TableCell>
                </TableRow>
              );
            })}
          </TableBody>
        </Table>
      </div>
      <FieldGroup className="flex-row items-end justify-between gap-4">
        <Field className="max-w-md">
          <FieldLabel htmlFor="import-source">Source</FieldLabel>
          <Input
            id="import-source"
            type="url"
            placeholder="https://"
            value={source}
            onChange={(e) => setSource(e.target.value)}
          />
        </Field>
        <Button
          disabled={invalid > 0 || pending}
          onClick={() =>
            startTransition(async () => {
              const result = await importSets(festivalId, rows, source);
              if (result?.ok) {
                toast.success(result.message);
                router.push(`/festivals/${festivalId}`);
              } else if (result) {
                toast.error(result.error);
              }
            })
          }
        >
          {pending && <Spinner data-icon="inline-start" />}
          Save {rows.length} sets
        </Button>
      </FieldGroup>
    </section>
  );
}
