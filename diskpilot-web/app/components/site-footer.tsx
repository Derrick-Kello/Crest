import Link from "next/link";
import { LogoMark } from "./icons";

/* Replace the "#" entries once the changelog and support addresses are live. */
const columns = [
  {
    title: "Product",
    links: [
      { href: "/download", label: "Download" },
      { href: "#panel", label: "What's in the panel" },
      { href: "#command-bar", label: "Command bar" },
      { href: "#install", label: "Install" },
      { href: "#requirements", label: "Requirements" },
    ],
  },
  {
    title: "Features",
    links: [
      { href: "#cleaner", label: "Cleaner" },
      { href: "#panel", label: "Docker" },
      { href: "#panel", label: "Clipboard history" },
      { href: "#panel", label: "Battery health" },
    ],
  },
  {
    title: "Trust",
    links: [
      { href: "#privacy", label: "Privacy" },
      { href: "#privacy", label: "What it never touches" },
      { href: "#faq", label: "FAQ" },
      { href: "#", label: "Changelog" },
    ],
  },
  {
    title: "Elsewhere",
    links: [
      { href: "https://github.com/Derrick-Kello/DiskPilot", label: "Source" },
      { href: "#", label: "Support" },
      { href: "https://github.com/Derrick-Kello/DiskPilot/issues", label: "Report an issue" },
    ],
  },
];

export function SiteFooter() {
  return (
    <footer className="relative border-t border-hairline bg-canvas">
      {/* faint echo of the hero stripe motif */}
      <div className="pointer-events-none absolute inset-x-0 top-0 h-24 overflow-hidden opacity-40">
        <div className="hero-stripes absolute inset-x-0 -top-16 h-40" />
      </div>

      <div className="relative mx-auto w-full max-w-[1240px] px-6 py-16">
        <div className="grid grid-cols-2 gap-x-8 gap-y-10 md:grid-cols-4 lg:grid-cols-6">
          <div className="col-span-2">
            <Link href="/" className="flex items-center gap-2">
              <LogoMark className="size-[22px]" />
              <span className="text-[14px] font-medium tracking-[0.2px] text-ink">DiskPilot</span>
            </Link>
            <p className="mt-3 max-w-[260px] text-[14px] leading-[1.6] text-mute">
              A menu bar app for people who would rather not open an app to find out what their Mac
              is doing.
            </p>
          </div>

          {columns.map((column) => (
            <div key={column.title}>
              <p className="mb-3 text-[14px] font-medium tracking-[0.2px] text-ink">{column.title}</p>
              <ul className="space-y-[10px]">
                {column.links.map((link) => (
                  <li key={link.label}>
                    <Link
                      href={link.href}
                      className="text-[14px] leading-[1.6] text-mute transition-colors hover:text-body"
                    >
                      {link.label}
                    </Link>
                  </li>
                ))}
              </ul>
            </div>
          ))}
        </div>

        <div className="mt-14 flex flex-col gap-3 border-t border-hairline pt-6 text-[13px] text-stone sm:flex-row sm:items-center">
          <p>© {new Date().getFullYear()} DiskPilot. Built for macOS.</p>
          <p className="sm:ml-auto">Made in Swift and SwiftUI. No analytics on this page.</p>
        </div>
      </div>
    </footer>
  );
}
