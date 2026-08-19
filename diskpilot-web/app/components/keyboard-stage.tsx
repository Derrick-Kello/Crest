import type { ReactNode } from "react";
import { AppleIcon, BoltIcon, LockIcon, TrashIcon } from "./icons";

const rows: { keys: string[]; grow?: number[] }[] = [
  { keys: ["esc", "F1", "F2", "F3", "F4", "F5", "F6"], grow: [2, 1, 1, 1, 1, 1, 1] },
  { keys: ["§", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0"] },
  { keys: ["tab", "Q", "W", "E", "R", "T", "Y", "U", "I", "O"], grow: [2, 1, 1, 1, 1, 1, 1, 1, 1, 1] },
  { keys: ["caps", "A", "S", "D", "F", "G", "H", "J", "K", "L"], grow: [2, 1, 1, 1, 1, 1, 1, 1, 1, 1] },
  { keys: ["shift", "Z", "X", "C", "V", "B", "N", "M"], grow: [3, 1, 1, 1, 1, 1, 1, 1] },
];

const cards: { icon: ReactNode; title: string; body: string; delay: string }[] = [
  {
    icon: <BoltIcon className="size-[17px]" />,
    title: "Fast.",
    body: "The app index is built at launch, so the first search is as quick as the hundredth.",
    delay: "0ms",
  },
  {
    icon: <AppleIcon className="size-[16px]" />,
    title: "Native.",
    body: "Swift and SwiftUI. One menu bar process, no web view in sight.",
    delay: "700ms",
  },
  {
    icon: <LockIcon className="size-[17px]" />,
    title: "Quiet.",
    body: "No account, no telemetry, no network calls of any kind.",
    delay: "1400ms",
  },
  {
    icon: <TrashIcon className="size-[17px]" />,
    title: "Reversible.",
    body: "Anything the cleaner removes lands in the Trash, where you can put it back.",
    delay: "2100ms",
  },
];

function Key({
  label,
  grow = 1,
  lit = false,
}: {
  label: string;
  grow?: number;
  lit?: boolean;
}) {
  return (
    <span
      style={{ flexGrow: grow, flexBasis: 0 }}
      className={`flex h-12 items-center justify-center rounded-md border text-[13px] transition-colors duration-500 sm:h-[70px] ${
        lit
          ? "border-hairline-strong bg-card text-ink"
          : "border-white/[0.04] bg-white/[0.015] text-stone/50"
      }`}
    >
      {label}
    </span>
  );
}

/** A dim keyboard with ⌥ and Space lit, and the product's claims floating over it. */
export function KeyboardStage() {
  return (
    <div className="relative">
      <div
        className="reveal-soft flex flex-col gap-[6px] select-none"
        aria-hidden="true"
      >
        {rows.map((row, i) => (
          <div key={i} className="flex gap-[6px]">
            {row.keys.map((key, j) => (
              <Key key={key + j} label={key} grow={row.grow?.[j] ?? 1} />
            ))}
          </div>
        ))}
        <div className="flex gap-[6px]">
          <Key label="fn" grow={1} />
          <Key label="control" grow={1.4} />
          <Key label="⌥ option" grow={1.8} lit />
          <Key label="⌘" grow={1.4} />
          <Key label="space" grow={5} lit />
        </div>
      </div>

      <div className="pointer-events-none absolute inset-0 flex items-center px-4 sm:px-10">
        <div className="mx-auto grid w-full max-w-[580px] grid-cols-1 gap-3 sm:grid-cols-2">
          {cards.map((card) => (
            <div
              key={card.title}
              style={{ "--delay": card.delay } as React.CSSProperties}
              className="drift rounded-lg border border-hairline bg-surface/95 p-4 backdrop-blur-sm"
            >
              <span className="flex size-8 items-center justify-center rounded-md bg-card text-body">
                {card.icon}
              </span>
              <p className="mt-3 text-[15px] leading-[1.5] text-stone">
                <span className="font-medium text-ink">{card.title}</span> {card.body}
              </p>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
