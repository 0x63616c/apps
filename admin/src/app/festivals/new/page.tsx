import Link from "next/link";
import { FestivalForm } from "../../festival-form";

export default async function NewFestivalPage({ searchParams }: { searchParams: Promise<{ error?: string }> }) {
  const { error } = await searchParams;
  return (
    <>
      <p>
        <Link href="/">← Festivals</Link>
      </p>
      <h1>New festival</h1>
      {error && <p className="error">{error}</p>}
      <FestivalForm />
    </>
  );
}
