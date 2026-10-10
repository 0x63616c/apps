import type { Metadata } from "next";
import Link from "next/link";
import "./globals.css";

export const metadata: Metadata = {
  title: "Festr Admin",
  robots: { index: false, follow: false },
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>
        <header className="topbar">
          <Link href="/">Festr Admin</Link>
          <a href="/api/feed" target="_blank" rel="noreferrer">
            /api/feed
          </a>
        </header>
        <main>{children}</main>
      </body>
    </html>
  );
}
