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
    "Disk space, system load, battery health, network, a cleaner that shows its work, Docker, Homebrew, clipboard history, an ⌥Space command bar and on-device dictation and meeting notes. One panel, no main window, nothing leaves your Mac.",
  openGraph: {
    title: "Crest · Your whole Mac, one click from the menu bar",
    description:
      "One menu bar panel for storage, system load, battery, network, cleanup, Docker and Homebrew, plus an ⌥Space command bar and dictation that runs on your Mac.",
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
