"use client";

import { useEffect, useState } from "react";
import { CheckIcon } from "./icons";

/** A shell command the reader is meant to run, with one-click copy. */
export function CopyCommand({
  command,
  className = "",
}: {
  /** One line, or several that are meant to be pasted together. */
  command: string | string[];
  className?: string;
}) {
  const lines = Array.isArray(command) ? command : [command];
  const text = lines.join("\n");
  const [copied, setCopied] = useState(false);

  useEffect(() => {
    if (!copied) return;
    const timer = setTimeout(() => setCopied(false), 2000);
    return () => clearTimeout(timer);
  }, [copied]);

  /** Pre-async-clipboard path, still the only one that works in some contexts. */
  function copyViaSelection(text: string) {
    const field = document.createElement("textarea");
    field.value = text;
    field.setAttribute("readonly", "");
    field.style.position = "fixed";
    field.style.opacity = "0";
    document.body.appendChild(field);
    field.select();

    let ok = false;
    try {
      ok = document.execCommand("copy");
    } catch {
      ok = false;
    }
    document.body.removeChild(field);
    return ok;
  }

  async function copy() {
    try {
      await navigator.clipboard.writeText(text);
      setCopied(true);
    } catch {
      // Permission or focus can deny the async API. Fall back before giving up.
      if (copyViaSelection(text)) setCopied(true);
    }
  }

  return (
    <div
      className={`flex items-start gap-3 rounded-md border border-hairline bg-elevated py-[10px] pr-[10px] pl-4 ${className}`}
    >
      <code className="min-w-0 flex-1 space-y-1 overflow-x-auto py-[3px] text-[13px] leading-[1.5] text-body">
        {lines.map((line) => (
          <span key={line} className="block whitespace-nowrap">
            <span className="text-stone select-none">$ </span>
            {line}
          </span>
        ))}
      </code>
      <button
        type="button"
        onClick={copy}
        aria-label={copied ? "Copied" : "Copy command"}
        className="flex h-7 shrink-0 items-center gap-[6px] rounded-sm bg-card px-[10px] text-[12px] font-medium tracking-[0.2px] text-body transition-colors hover:text-ink"
      >
        {copied ? (
          <>
            <CheckIcon className="size-[13px] text-accent-green" />
            Copied
          </>
        ) : (
          <>
            <svg
              viewBox="0 0 24 24"
              className="size-[13px]"
              fill="none"
              stroke="currentColor"
              strokeWidth="1.7"
              strokeLinecap="round"
              strokeLinejoin="round"
              aria-hidden="true"
            >
              <rect x="9" y="9" width="11" height="11" rx="2.4" />
              <path d="M15 5.5A1.5 1.5 0 0 0 13.5 4h-8A1.5 1.5 0 0 0 4 5.5v8A1.5 1.5 0 0 0 5.5 15" />
            </svg>
            Copy
          </>
        )}
      </button>
    </div>
  );
}
