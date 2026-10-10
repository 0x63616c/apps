import type { Metadata } from "next";
import { FestivalForm } from "@/components/festival-form";
import { PageHeader } from "@/components/page-header";

export const metadata: Metadata = { title: "New festival" };

export default function NewFestivalPage() {
  return (
    <>
      <PageHeader title="New festival" />
      <FestivalForm />
    </>
  );
}
