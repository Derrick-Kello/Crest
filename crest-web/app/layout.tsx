import type { Metadata } from "next";
import { Inter } from "next/font/google";
import "./globals.css";

const inter = Inter({
  variable: "--font-inter",
  subsets: ["latin"],
  weight: ["400", "500", "600"],
});

export const metadata: Metadata = {
  metadataBase: new URL("https://crest.app"),
  title: "Crest · Your whole Mac, one click from the menu bar",
  description:
    "Disk space, system load, battery health, a cleaner that shows its work, Docker, clipboard history and an ⌥Space command bar. One panel, no main window, nothing leaves your Mac.",
  openGraph: {
    title: "Crest · Your whole Mac, one click from the menu bar",
    description:
      "One menu bar panel for storage, system load, battery health, cleanup, Docker and clipboard, plus an ⌥Space command bar.",
    type: "website",
    siteName: "Crest",
  },
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html lang="en" className={`${inter.variable} h-full antialiased`}>
      <body className="bg-canvas text-body min-h-full flex flex-col font-sans">
        {children}
      </body>
    </html>
  );
}
