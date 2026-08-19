import Link from "next/link";
import { ButtonPrimary } from "./ui";
import { LogoMark } from "./icons";

const links = [
  { href: "#panel", label: "Panel" },
  { href: "#command-bar", label: "Command bar" },
  { href: "#cleaner", label: "Cleaner" },
  { href: "#privacy", label: "Privacy" },
  { href: "#faq", label: "FAQ" },
  { href: "#install", label: "Install" },
];

export function SiteNav() {
  return (
    <header className="sticky top-0 z-50 px-4 pt-4 sm:px-6">
      <div className="mx-auto flex h-14 w-full max-w-[1120px] items-center gap-4 rounded-xl border border-hairline bg-surface/80 px-4 backdrop-blur-xl sm:px-5">
        <Link href="/" className="flex items-center gap-2">
          <LogoMark className="size-[22px]" />
          <span className="text-[14px] font-medium tracking-[0.2px] text-ink">DiskPilot</span>
        </Link>

        <nav className="mx-auto hidden items-center gap-6 md:flex">
          {links.map((link) => (
            <Link
              key={link.href}
              href={link.href}
              className="text-[14px] font-medium tracking-[0.2px] text-body transition-colors hover:text-ink"
            >
              {link.label}
            </Link>
          ))}
        </nav>

        <div className="ml-auto flex items-center gap-2 md:ml-0">
          <ButtonPrimary href="/download">Download</ButtonPrimary>

          {/* Mobile drawer — a details element keeps the whole nav server-rendered. */}
          <details className="group relative md:hidden">
            <summary className="flex size-9 cursor-pointer list-none items-center justify-center rounded-md bg-elevated text-ink [&::-webkit-details-marker]:hidden">
              <svg viewBox="0 0 24 24" className="size-4" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round">
                <path d="M4 7h16M4 12h16M4 17h16" />
              </svg>
              <span className="sr-only">Menu</span>
            </summary>
            <div className="absolute right-0 mt-2 w-56 rounded-md border border-hairline bg-surface p-2">
              {links.map((link) => (
                <Link
                  key={link.href}
                  href={link.href}
                  className="block rounded-sm px-3 py-2 text-[14px] text-body hover:bg-elevated hover:text-ink"
                >
                  {link.label}
                </Link>
              ))}
            </div>
          </details>
        </div>
      </div>
    </header>
  );
}
