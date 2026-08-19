import type { ReactNode } from "react";

/** White pill. The one primary action in the system — at most one per fold. */
export function ButtonPrimary({
  href,
  children,
  className = "",
}: {
  href: string;
  children: ReactNode;
  className?: string;
}) {
  return (
    <a
      href={href}
      className={`inline-flex h-9 items-center gap-2 rounded-md bg-white px-4 text-[14px] font-medium tracking-[0.2px] text-black transition-colors active:bg-[#e8e8e8] ${className}`}
    >
      {children}
    </a>
  );
}

/** Transparent, lower-emphasis. */
export function ButtonSecondary({
  href,
  children,
  className = "",
}: {
  href: string;
  children: ReactNode;
  className?: string;
}) {
  return (
    <a
      href={href}
      className={`inline-flex h-9 items-center gap-2 rounded-md px-4 text-[14px] font-medium tracking-[0.2px] text-white/90 transition-colors hover:text-white ${className}`}
    >
      {children}
    </a>
  );
}

/** Soft surface button, one notch up the ladder. */
export function ButtonTertiary({
  href,
  children,
  className = "",
}: {
  href: string;
  children: ReactNode;
  className?: string;
}) {
  return (
    <a
      href={href}
      className={`inline-flex h-9 items-center gap-2 rounded-md bg-elevated px-4 text-[14px] font-medium tracking-[0.2px] text-white transition-colors hover:bg-card ${className}`}
    >
      {children}
    </a>
  );
}

export function Keycap({ children, className = "" }: { children: ReactNode; className?: string }) {
  return (
    <kbd
      className={`keycap-face inline-flex h-5 min-w-5 items-center justify-center rounded-xs border border-hairline px-[6px] text-[13px] leading-none font-normal tracking-[0.1px] text-body ${className}`}
    >
      {children}
    </kbd>
  );
}

export function Badge({ children }: { children: ReactNode }) {
  return (
    <span className="inline-flex items-center rounded-xs bg-elevated px-[6px] py-[2px] text-[12px] tracking-[0.4px] text-on-dark-mute">
      {children}
    </span>
  );
}

export function BadgeInfo({ children }: { children: ReactNode }) {
  return (
    <span className="inline-flex items-center rounded-xs bg-accent-blue-soft px-2 py-[2px] text-[12px] tracking-[0.4px] text-accent-blue">
      {children}
    </span>
  );
}

export function Section({
  id,
  children,
  className = "",
}: {
  id?: string;
  children: ReactNode;
  className?: string;
}) {
  return (
    <section id={id} className={`px-6 py-12 md:py-16 lg:py-24 ${className}`}>
      <div className="mx-auto w-full max-w-[1240px]">{children}</div>
    </section>
  );
}

export function SectionHeading({
  eyebrow,
  title,
  subtitle,
  body,
  center = false,
  className = "",
}: {
  eyebrow?: string;
  title: string;
  /** Second line, rendered muted. The reference system's signature heading shape. */
  subtitle?: string;
  body?: string;
  center?: boolean;
  className?: string;
}) {
  return (
    <div
      className={`reveal ${center ? "mx-auto max-w-[760px] text-center" : "max-w-[640px]"} ${className}`}
    >
      {eyebrow ? (
        <p className="mb-3 text-[13px] tracking-[0.1px] text-mute">{eyebrow}</p>
      ) : null}
      <h2 className="display text-[30px] leading-[1.15] font-medium tracking-[0.2px] text-ink md:text-[40px]">
        {title}
        {subtitle ? (
          <>
            <br />
            <span className="text-stone">{subtitle}</span>
          </>
        ) : null}
      </h2>
      {body ? (
        <p
          className={`mt-4 text-[16px] leading-[1.6] text-body md:text-[18px] ${center ? "mx-auto max-w-[560px]" : ""}`}
        >
          {body}
        </p>
      ) : null}
    </div>
  );
}

export function Card({
  children,
  elevated = false,
  className = "",
}: {
  children: ReactNode;
  elevated?: boolean;
  className?: string;
}) {
  return (
    <div
      className={`rounded-lg border border-hairline p-6 transition-colors duration-300 hover:border-hairline-strong ${elevated ? "bg-elevated" : "bg-surface"} ${className}`}
    >
      {children}
    </div>
  );
}
