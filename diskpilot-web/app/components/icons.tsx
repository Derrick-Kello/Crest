type IconProps = { className?: string };

/** SF-Symbol-shaped line icons, drawn to match the glyphs the app itself uses. */
function Svg({ className, children }: IconProps & { children: React.ReactNode }) {
  return (
    <svg
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.6"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      className={className ?? "size-4"}
    >
      {children}
    </svg>
  );
}

export function GaugeIcon(p: IconProps) {
  return (
    <Svg {...p}>
      <path d="M3.5 17a9 9 0 1 1 17 0" />
      <path d="M12 13.5 16 9" />
      <circle cx="12" cy="14" r="1.4" fill="currentColor" stroke="none" />
    </Svg>
  );
}

export function DriveIcon(p: IconProps) {
  return (
    <Svg {...p}>
      <rect x="2.5" y="6" width="19" height="12" rx="3" />
      <circle cx="17" cy="12" r="1.3" fill="currentColor" stroke="none" />
      <path d="M6 12h6" />
    </Svg>
  );
}

export function SparklesIcon(p: IconProps) {
  return (
    <Svg {...p}>
      <path d="M12 3.5 13.6 8.4 18.5 10 13.6 11.6 12 16.5 10.4 11.6 5.5 10 10.4 8.4Z" />
      <path d="M18 16.5l.7 2 2 .7-2 .7-.7 2-.7-2-2-.7 2-.7Z" />
    </Svg>
  );
}

export function BoltIcon(p: IconProps) {
  return (
    <Svg {...p}>
      <path d="M13 2.5 5 13.5h6l-2 8 8-11h-6Z" />
    </Svg>
  );
}

export function WrenchIcon(p: IconProps) {
  return (
    <Svg {...p}>
      <path d="M15.5 3a5 5 0 0 0-4.6 6.9L3 17.8V21h3.2l7.9-7.9A5 5 0 1 0 15.5 3Z" />
      <path d="M6 18.2h.01" />
    </Svg>
  );
}

export function ClipboardIcon(p: IconProps) {
  return (
    <Svg {...p}>
      <rect x="5" y="4.5" width="14" height="16" rx="2.6" />
      <path d="M9 4.5V3.8A1.3 1.3 0 0 1 10.3 2.5h3.4A1.3 1.3 0 0 1 15 3.8v.7" />
      <path d="M9 11h6M9 15h4" />
    </Svg>
  );
}

export function ChartIcon(p: IconProps) {
  return (
    <Svg {...p}>
      <path d="M4 20V10M10 20V4M16 20v-7M22 20H2" />
    </Svg>
  );
}

export function BoxIcon(p: IconProps) {
  return (
    <Svg {...p}>
      <path d="M12 2.8 20.5 7v10L12 21.2 3.5 17V7Z" />
      <path d="M3.5 7 12 11.4 20.5 7M12 11.4V21.2" />
    </Svg>
  );
}

export function SearchIcon(p: IconProps) {
  return (
    <Svg {...p}>
      <circle cx="11" cy="11" r="6.5" />
      <path d="m16 16 4.5 4.5" />
    </Svg>
  );
}

export function CupIcon(p: IconProps) {
  return (
    <Svg {...p}>
      <path d="M4 8h12v6a5 5 0 0 1-5 5H9a5 5 0 0 1-5-5Z" />
      <path d="M16 9.5h1.8a2.7 2.7 0 0 1 0 5.4H16" />
      <path d="M7 5.2V3.5M11 5.2V3.5" />
    </Svg>
  );
}

export function EyedropperIcon(p: IconProps) {
  return (
    <Svg {...p}>
      <path d="m14.5 6.5 3 3M16 3.6a2.3 2.3 0 0 1 3.2 0l1.2 1.2a2.3 2.3 0 0 1 0 3.2l-1.6 1.6-4.4-4.4Z" />
      <path d="m13.6 6.8-8 8V19h4.2l8-8" />
    </Svg>
  );
}

export function BatteryIcon(p: IconProps) {
  return (
    <Svg {...p}>
      <rect x="2.5" y="7" width="16" height="10" rx="3" />
      <path d="M21.5 11v2" />
      <rect x="5" y="9.5" width="7" height="5" rx="1.4" fill="currentColor" stroke="none" />
    </Svg>
  );
}

export function CpuIcon(p: IconProps) {
  return (
    <Svg {...p}>
      <rect x="6" y="6" width="12" height="12" rx="2.4" />
      <path d="M10 2.6v3M14 2.6v3M10 18.4v3M14 18.4v3M2.6 10h3M2.6 14h3M18.4 10h3M18.4 14h3" />
    </Svg>
  );
}

export function LockIcon(p: IconProps) {
  return (
    <Svg {...p}>
      <rect x="4.5" y="10" width="15" height="10.5" rx="2.6" />
      <path d="M8 10V7.5a4 4 0 0 1 8 0V10" />
    </Svg>
  );
}

export function TrashIcon(p: IconProps) {
  return (
    <Svg {...p}>
      <path d="M4 6.5h16M9.5 6.5V4.8A1.3 1.3 0 0 1 10.8 3.5h2.4a1.3 1.3 0 0 1 1.3 1.3v1.7" />
      <path d="M6.5 6.5 7.4 20a1.4 1.4 0 0 0 1.4 1.3h6.4a1.4 1.4 0 0 0 1.4-1.3l.9-13.5" />
    </Svg>
  );
}

export function HammerIcon(p: IconProps) {
  return (
    <Svg {...p}>
      <path d="m13.4 8.2-8.9 8.9a1.9 1.9 0 0 0 2.7 2.7l8.9-8.9" />
      <path d="M11.6 6.4 14.4 3.6l6 6-2.8 2.8Z" />
    </Svg>
  );
}

export function DocIcon(p: IconProps) {
  return (
    <Svg {...p}>
      <path d="M6 3.5h7l5 5v12H6Z" />
      <path d="M13 3.5v5h5M9 13h6M9 16.5h4" />
    </Svg>
  );
}

export function PhoneIcon(p: IconProps) {
  return (
    <Svg {...p}>
      <rect x="6.5" y="2.5" width="11" height="19" rx="2.8" />
      <path d="M10.8 18.6h2.4" />
    </Svg>
  );
}

export function AppDashedIcon(p: IconProps) {
  return (
    <Svg {...p}>
      <rect x="3.5" y="3.5" width="17" height="17" rx="4.5" strokeDasharray="3 2.6" />
    </Svg>
  );
}

export function CheckIcon(p: IconProps) {
  return (
    <Svg {...p}>
      <path d="m4.5 12.5 5 5 10-11" />
    </Svg>
  );
}

export function ArrowRightIcon(p: IconProps) {
  return (
    <Svg {...p}>
      <path d="M4.5 12h15M13.5 6l6 6-6 6" />
    </Svg>
  );
}

export function PlusIcon(p: IconProps) {
  return (
    <Svg {...p}>
      <path d="M12 5v14M5 12h14" />
    </Svg>
  );
}

export function AppleIcon(p: IconProps) {
  return (
    <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true" className={p.className ?? "size-4"}>
      <path d="M16.4 12.6c0-2.4 2-3.6 2.1-3.6-1.1-1.7-2.9-1.9-3.5-1.9-1.5-.2-2.9.9-3.7.9s-1.9-.9-3.2-.8c-1.6 0-3.1 1-4 2.4-1.7 3-.4 7.4 1.2 9.8.8 1.2 1.8 2.5 3.1 2.4 1.2 0 1.7-.8 3.2-.8s1.9.8 3.2.8 2.2-1.2 3-2.4c.9-1.3 1.3-2.6 1.3-2.7s-2.5-1-2.7-3.8zM14.2 5.6c.7-.8 1.1-2 1-3.1-1 0-2.2.7-2.9 1.5-.6.7-1.2 1.9-1 3 1.1.1 2.2-.6 2.9-1.4z" />
    </svg>
  );
}

export function LogoMark({ className }: IconProps) {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true" className={className ?? "size-6"}>
      <rect x="1" y="1" width="22" height="22" rx="6" fill="#121212" stroke="#242728" />
      <circle cx="12" cy="12" r="6.4" stroke="#434345" strokeWidth="1.4" fill="none" />
      <path
        d="M12 5.6A6.4 6.4 0 0 1 17.6 15"
        stroke="#59d499"
        strokeWidth="1.8"
        strokeLinecap="round"
        fill="none"
      />
      <circle cx="12" cy="12" r="1.7" fill="#f4f4f6" />
    </svg>
  );
}
