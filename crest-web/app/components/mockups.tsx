import type { ReactNode } from "react";
import { Keycap } from "./ui";
import {
  AppleIcon,
  BatteryIcon,
  BoltIcon,
  BoxIcon,
  ChartIcon,
  ClipboardIcon,
  CpuIcon,
  CupIcon,
  DriveIcon,
  EyedropperIcon,
  GaugeIcon,
  LogoMark,
  SearchIcon,
  SparklesIcon,
  WrenchIcon,
} from "./icons";

/* ---------------------------------------------------------------- panel */

const tabs = [
  { icon: GaugeIcon, label: "System" },
  { icon: DriveIcon, label: "Disk" },
  { icon: SparklesIcon, label: "Cleaner" },
  { icon: BoltIcon, label: "Power" },
  { icon: WrenchIcon, label: "Tools" },
  { icon: ClipboardIcon, label: "Clipboard" },
  { icon: ChartIcon, label: "Large folders" },
  { icon: BoxIcon, label: "Docker" },
];

function PanelRow({
  icon,
  title,
  children,
}: {
  icon: ReactNode;
  title: string;
  children: ReactNode;
}) {
  return (
    <div className="flex items-center gap-2 py-[5px]">
      <span className="text-stone">{icon}</span>
      <span className="text-[12px] text-body">{title}</span>
      <span className="ml-auto text-[12px] font-medium text-ink">{children}</span>
    </div>
  );
}

function Meter({ fill, color }: { fill: number; color: string }) {
  return (
    <div className="h-[6px] w-full overflow-hidden rounded-full bg-canvas">
      <div
        className="meter-fill h-full rounded-full"
        style={{ "--fill": `${fill}%`, background: color } as React.CSSProperties}
      />
    </div>
  );
}

/** The menu bar panel: header, icon tab bar, one section, footer. */
export function PanelMock({ className = "" }: { className?: string }) {
  return (
    <div
      className={`w-full max-w-[336px] shrink-0 overflow-hidden rounded-lg border border-hairline bg-surface ${className}`}
    >
      <div className="flex items-center gap-2 px-3 py-[10px]">
        <LogoMark className="size-[18px]" />
        <span className="text-[12px] font-medium text-ink">Crest</span>
        <span className="ml-auto flex items-center gap-1 text-[11px] text-mute">
          <span className="size-[6px] rounded-full bg-accent-green" />
          Healthy
        </span>
      </div>

      <div className="mx-[10px] mb-[10px] flex items-center gap-[2px] rounded-md bg-elevated p-[3px]">
        {tabs.map(({ icon: Icon, label }, i) => (
          <span
            key={label}
            title={label}
            className={`flex h-[26px] flex-1 items-center justify-center rounded-sm ${
              i === 1 ? "bg-card text-ink" : "text-stone"
            }`}
          >
            <Icon className="size-[13px]" />
          </span>
        ))}
      </div>

      <div className="space-y-[10px] px-[10px] pb-[10px]">
        <div className="rounded-md border border-hairline bg-elevated p-3">
          <div className="mb-2 flex items-center gap-2">
            <DriveIcon className="size-[13px] text-mute" />
            <span className="text-[12px] font-medium text-ink">Macintosh HD</span>
            <span className="ml-auto text-[11px] text-mute">312 GB free</span>
          </div>
          <Meter fill={69} color="#59d499" />
          <div className="mt-2 flex items-center justify-between text-[11px] text-ash">
            <span>682 GB used</span>
            <span>994 GB total</span>
          </div>
        </div>

        <div className="rounded-md border border-hairline bg-elevated px-3 py-1">
          <PanelRow icon={<CpuIcon className="size-[13px]" />} title="CPU">
            <span className="text-accent-green">12%</span>
          </PanelRow>
          <div className="h-px bg-hairline" />
          <PanelRow icon={<BoxIcon className="size-[13px]" />} title="Memory">
            9.4 / 16 GB
          </PanelRow>
          <div className="h-px bg-hairline" />
          <PanelRow icon={<BatteryIcon className="size-[13px]" />} title="Battery">
            <span className="text-accent-yellow">64%</span>
          </PanelRow>
          <div className="h-px bg-hairline" />
          <PanelRow icon={<CupIcon className="size-[13px]" />} title="Keep Awake">
            <span className="text-mute">Off</span>
          </PanelRow>
        </div>
      </div>

      <div className="flex items-center gap-2 border-t border-hairline px-3 py-2">
        <span className="text-[11px] text-mute">Quick scan</span>
        <span className="ml-auto flex items-center gap-1">
          <Keycap className="h-[18px] text-[11px]">⌥</Keycap>
          <Keycap className="h-[18px] text-[11px]">Space</Keycap>
        </span>
      </div>
    </div>
  );
}

/* ----------------------------------------------------------- command bar */

function Tile({ children, tint }: { children: ReactNode; tint: string }) {
  return (
    <span
      className="flex size-[26px] items-center justify-center rounded-md bg-card"
      style={{ color: tint }}
    >
      {children}
    </span>
  );
}

const rows = [
  {
    tile: <Tile tint="#57c1ff"><SearchIcon className="size-[14px]" /></Tile>,
    title: "Calendar",
    subtitle: "Application",
    hint: "↩",
    active: true,
  },
  {
    tile: <Tile tint="#59d499"><SparklesIcon className="size-[14px]" /></Tile>,
    title: "Clean developer junk",
    subtitle: "Crest action · 41.2 GB found",
  },
  {
    tile: <Tile tint="#ffc533"><ClipboardIcon className="size-[14px]" /></Tile>,
    title: "calc-service.ts",
    subtitle: "Clipboard · copied 4 minutes ago",
  },
  {
    tile: <Tile tint="#ff6161"><EyedropperIcon className="size-[14px]" /></Tile>,
    title: "#ff6161",
    subtitle: "Picked colour · copied as hex",
  },
];

/** The ⌥Space bar: query field, result rows, keycap footer. */
export function CommandBarMock({ className = "" }: { className?: string }) {
  return (
    <div
      className={`w-full max-w-[420px] overflow-hidden rounded-xl border border-hairline bg-surface ${className}`}
    >
      <div className="flex items-center gap-[10px] border-b border-hairline px-4 py-[14px]">
        <SearchIcon className="size-4 text-mute" />
        <span className="type text-[16px] text-ink">cal</span>
        <span className="caret -ml-[3px] inline-block h-[17px] w-px bg-white/70" />
        <span className="ml-auto whitespace-nowrap text-[13px] text-stone">8 results</span>
      </div>

      <div className="space-y-[2px] p-[6px]">
        <div className="px-[10px] pt-1 pb-[6px] text-[12px] tracking-[0.4px] text-stone">
          Calculator
        </div>
        <div className="flex items-center gap-[10px] rounded-sm px-[10px] py-[6px]">
          <Tile tint="#9c9c9d">
            <span className="text-[13px] font-medium">=</span>
          </Tile>
          <div className="min-w-0">
            <p className="truncate text-[14px] text-ink">128 × 44 = 5,632</p>
            <p className="truncate text-[12px] text-mute">Copy answer</p>
          </div>
        </div>

        <div className="px-[10px] pt-3 pb-[6px] text-[12px] tracking-[0.4px] text-stone">
          Results
        </div>
        {rows.map((row) => (
          <div
            key={row.title}
            className={`flex items-center gap-[10px] rounded-sm px-[10px] py-[6px] ${
              row.active ? "bg-card" : ""
            }`}
          >
            {row.tile}
            <div className="min-w-0">
              <p className="truncate text-[14px] text-ink">{row.title}</p>
              <p className="truncate text-[12px] text-mute">{row.subtitle}</p>
            </div>
            {row.hint ? (
              <span className="ml-auto">
                <Keycap>{row.hint}</Keycap>
              </span>
            ) : null}
          </div>
        ))}
      </div>

      <div className="flex items-center gap-2 border-t border-hairline px-4 py-[10px]">
        <LogoMark className="size-[15px]" />
        <span className="text-[12px] text-mute">Crest</span>
        <span className="ml-auto flex items-center gap-[6px] text-[12px] text-mute">
          Open <Keycap>↩</Keycap> Actions <Keycap>⌘K</Keycap>
        </span>
      </div>
    </div>
  );
}

/* ------------------------------------------------------------- menu bar */

/** The macOS menu bar strip, with Crest's own item lit up. */
export function MenuBarStrip() {
  return (
    <div className="flex h-[26px] w-full items-center gap-4 rounded-t-xl border-b border-hairline-soft bg-[#0b0c0e] px-4 text-[12px] text-mute">
      <AppleIcon className="size-[13px] text-body" />
      <span className="font-medium text-body">Finder</span>
      <span className="hidden sm:inline">File</span>
      <span className="hidden sm:inline">Edit</span>
      <span className="hidden sm:inline">View</span>
      <span className="ml-auto flex items-center gap-3">
        <span className="flex items-center gap-[5px] rounded-xs bg-white/10 px-[6px] py-[2px] text-ink">
          <span className="size-[6px] rounded-full bg-accent-green" />
          312 GB
        </span>
        <BatteryIcon className="size-[15px]" />
        <span className="hidden sm:inline">9:41</span>
      </span>
    </div>
  );
}

/* ------------------------------------------------------------- showcase */

/** The product shot: a menu bar with Crest open under it, command bar alongside. */
export function ShowcaseMock() {
  return (
    <div className="reveal-lift relative w-full overflow-hidden rounded-xl border border-hairline bg-canvas">
      <MenuBarStrip />

      <div className="stage-glow relative flex flex-col items-center gap-6 px-4 pt-6 pb-8 sm:px-8 lg:flex-row lg:items-start lg:justify-between lg:gap-10 lg:pt-12 lg:pb-14">
        <div className="drift w-full max-w-[440px] lg:ml-6" style={{ "--delay": "400ms" } as React.CSSProperties}>
          <CommandBarMock />
        </div>
        <PanelMock className="lg:mr-2" />
      </div>
    </div>
  );
}

/* -------------------------------------------------------------- cleaner */

const cleanerRows = [
  { name: "Developer junk", size: "41.2 GB", note: "1,204 items in 6 tools", on: true },
  { name: "Caches", size: "12.8 GB", note: "38 apps", on: true },
  { name: "App leftovers", size: "3.4 GB", note: "9 apps you removed", on: true },
  { name: "Logs", size: "864 MB", note: "412 files", on: true },
  { name: "Device backups", size: "28.0 GB", note: "2 backups, opt in", on: false },
  { name: "Trash", size: "6.1 GB", note: "Opt in, permanent", on: false },
];

/** The review step: everything found, everything itemised, nothing removed yet. */
export function CleanerMock() {
  return (
    <div className="overflow-hidden rounded-lg border border-hairline bg-surface">
      <div className="flex items-center gap-3 border-b border-hairline px-4 py-3">
        <SparklesIcon className="size-4 text-mute" />
        <span className="text-[14px] font-medium text-ink">Review before removing</span>
        <span className="ml-auto text-[13px] text-mute">58.3 GB selected</span>
      </div>
      <div>
        {cleanerRows.map((row) => (
          <div
            key={row.name}
            className="flex items-center gap-3 border-b border-hairline px-4 py-[11px] last:border-b-0"
          >
            <span
              className={`flex size-[15px] items-center justify-center rounded-xs border ${
                row.on ? "border-white bg-white" : "border-stone"
              }`}
            >
              {row.on ? (
                <svg viewBox="0 0 24 24" className="size-[10px]" fill="none" stroke="#000" strokeWidth="3.4" strokeLinecap="round" strokeLinejoin="round">
                  <path d="m4.5 12.5 5 5 10-11" />
                </svg>
              ) : null}
            </span>
            <div className="min-w-0">
              <p className="text-[14px] text-ink">{row.name}</p>
              <p className="truncate text-[13px] text-mute">{row.note}</p>
            </div>
            <span className="ml-auto text-[14px] font-medium text-ink">{row.size}</span>
          </div>
        ))}
      </div>
      <div className="flex items-center gap-3 border-t border-hairline bg-elevated px-4 py-3">
        <span className="text-[13px] text-mute">Everything goes to the Trash.</span>
        <span className="ml-auto inline-flex h-8 items-center rounded-md bg-white px-[14px] text-[13px] font-medium text-black">
          Remove 58.3 GB
        </span>
      </div>
    </div>
  );
}

/* ---------------------------------------------------------------- bento */

/** Arithmetic answering ahead of every fuzzy match. */
export function CalcMock() {
  return (
    <div className="overflow-hidden rounded-md border border-hairline bg-elevated">
      <div className="flex items-center gap-2 border-b border-hairline px-3 py-[10px]">
        <SearchIcon className="size-[14px] text-mute" />
        <span className="text-[14px] text-ink">1.2tb in gb</span>
        <span className="caret inline-block h-[15px] w-px bg-white/70" />
      </div>
      <div className="flex items-center gap-[10px] p-[10px]">
        <span className="flex size-[26px] items-center justify-center rounded-md bg-card text-[13px] font-medium text-mute">
          =
        </span>
        <div>
          <p className="text-[14px] text-ink">1,200 GB</p>
          <p className="text-[12px] text-mute">Press ↩ to copy</p>
        </div>
      </div>
    </div>
  );
}

/** The clipboard, pinned first then most recent. */
export function ClipboardMock() {
  const items = [
    { text: "sk_live_… (pinned)", meta: "Pinned", pinned: true },
    { text: "https://crest.app/download", meta: "2 minutes ago" },
    { text: "#59d499", meta: "11 minutes ago" },
  ];

  return (
    <div className="overflow-hidden rounded-md border border-hairline bg-elevated">
      {items.map((item) => (
        <div
          key={item.text}
          className="flex items-center gap-[10px] border-b border-hairline px-3 py-[9px] last:border-b-0"
        >
          <span className="flex size-[26px] items-center justify-center rounded-md bg-card text-mute">
            <ClipboardIcon className="size-[13px]" />
          </span>
          <div className="min-w-0">
            <p className="truncate text-[13px] text-ink">{item.text}</p>
            <p className="text-[12px] text-mute">{item.meta}</p>
          </div>
          {item.pinned ? (
            <span className="ml-auto rounded-xs bg-card px-[6px] py-[2px] text-[11px] text-mute">
              1
            </span>
          ) : null}
        </div>
      ))}
    </div>
  );
}
