import {
  AppDashedIcon,
  AppMinusIcon,
  AppleIcon,
  BatteryIcon,
  BoltIcon,
  BoxIcon,
  BubbleIcon,
  ChartIcon,
  ClipboardIcon,
  CupIcon,
  DocIcon,
  DriveIcon,
  EyedropperIcon,
  GaugeIcon,
  HammerIcon,
  KegIcon,
  KeyboardIcon,
  LockIcon,
  MicIcon,
  NetworkIcon,
  PhoneIcon,
  SearchIcon,
  ShieldIcon,
  SparklesIcon,
  TagIcon,
  TilingIcon,
  TrashIcon,
  WrenchIcon,
} from "./components/icons";
import { CopyCommand } from "./components/copy-command";
import { KeyboardStage } from "./components/keyboard-stage";
import {
  CalcMock,
  CleanerMock,
  ClipboardMock,
  CommandBarMock,
  DictationMock,
  FileSearchMock,
  MeetingMock,
  ShowcaseMock,
  VoiceHudMock,
} from "./components/mockups";
import { SiteFooter } from "./components/site-footer";
import { SiteNav } from "./components/site-nav";
import {
  Badge,
  ButtonPrimary,
  Card,
  Keycap,
  Section,
  SectionHeading,
} from "./components/ui";

const sections = [
  {
    icon: GaugeIcon,
    title: "System",
    body: "CPU split into user and system, memory and swap, core count, load average and uptime.",
  },
  {
    icon: DriveIcon,
    title: "Disk",
    body: "Free space and capacity, with a health colour that moves green to yellow to red as the drive fills.",
  },
  {
    icon: SparklesIcon,
    title: "Cleaner",
    body: "Six categories of reclaimable space, each with a size and a tick box. Nothing goes until you say so.",
  },
  {
    icon: NetworkIcon,
    title: "Network",
    body: "Up and down rates on one shared sparkline, what this session has moved, and which apps are moving it.",
  },
  {
    icon: BoltIcon,
    title: "Power",
    body: "Charge, time left, cycle count, capacity against new, battery temperature and adapter wattage.",
  },
  {
    icon: WrenchIcon,
    title: "Tools",
    body: "Keep Awake on a timer, a screen colour picker, and the command bar shortcut.",
  },
  {
    icon: ClipboardIcon,
    title: "Clipboard",
    body: "The last 150 things you copied, pinned items first. Off until you turn it on.",
  },
  {
    icon: ChartIcon,
    title: "Large folders",
    body: "The biggest directories in your home folder, sorted by size, so you can see where it went.",
  },
  {
    icon: BoxIcon,
    title: "Docker",
    body: "Images, containers, volumes and reclaimable space, with a prune that names its own command.",
  },
  {
    icon: KegIcon,
    title: "Homebrew",
    body: "What is installed, what has an update waiting, and what the package cache is costing you in disk space.",
  },
  {
    icon: MicIcon,
    title: "Voice",
    body: "Which key you hold to dictate, whether the grants are in place, and the last things you said.",
  },
  {
    icon: BubbleIcon,
    title: "Meetings",
    body: "Calls you recorded, each with a transcript per speaker and a summary written on this Mac.",
  },
  {
    icon: TilingIcon,
    title: "Tiling",
    body: "Which workspace you are on, what is waiting on the other eight, and the layout this one is using.",
  },
];

/// The shortcuts, grouped the way the settings pane groups them.
const tilingShortcuts = [
  {
    group: "Focus",
    rows: [
      { keys: ["mod", "H J K L"], label: "Focus left, down, up, right" },
      { keys: ["mod", "←↓↑→"], label: "The same, for hands not yet trained on hjkl" },
      { keys: ["mod", "`"], label: "Cycle through the windows in order" },
    ],
  },
  {
    group: "Move",
    rows: [
      { keys: ["mod", "⇧", "H J K L"], label: "Swap the window with its neighbour" },
      { keys: ["mod", "⇧", "↩"], label: "Promote it to the main pane" },
    ],
  },
  {
    group: "Workspaces",
    rows: [
      { keys: ["mod", "1…9"], label: "Switch to a workspace" },
      { keys: ["mod", "⇧", "1…9"], label: "Send the window there and stay put" },
      { keys: ["mod", "[  ]"], label: "Previous or next workspace" },
    ],
  },
  {
    group: "Layout",
    rows: [
      { keys: ["mod", "E"], label: "Cycle dwindle, tall, wide, monocle" },
      { keys: ["mod", "-  ="], label: "Shrink or grow the pane you are in" },
      { keys: ["mod", ",  ."], label: "Fewer or more windows in the main pane" },
      { keys: ["mod", "0"], label: "Balance every split" },
      { keys: ["mod", "R"], label: "Lay everything out again" },
    ],
  },
  {
    group: "Window",
    rows: [
      { keys: ["mod", "F"], label: "Fill the screen" },
      { keys: ["mod", "V"], label: "Float it, or put it back" },
      { keys: ["mod", "⇧", "Q"], label: "Close it" },
      { keys: ["mod", "⇧", "T"], label: "Turn tiling on or off" },
    ],
  },
];

const tilingLayouts = [
  {
    title: "Dwindle",
    body: "Every new window halves the space of the one before it, alternating the cut. Two sit side by side, three make an L, four make a spiral.",
  },
  {
    title: "Tall",
    body: "One large pane on the left, everything else stacked down the right. For when one window is the work and the rest are reference.",
  },
  {
    title: "Wide",
    body: "Tall, rotated. The main pane spans the top, which suits a monitor wider than it is deep.",
  },
  {
    title: "Monocle",
    body: "One window at a time, filling the screen, the rest behind it.",
  },
];

const cleanerCategories = [
  {
    icon: HammerIcon,
    title: "Developer junk",
    body: "Build output and package caches. Your tools regenerate these on the next build.",
    tint: "#59d499",
  },
  {
    icon: BoxIcon,
    title: "Caches",
    body: "Rebuilt automatically. Apps may open slower once, and downloaded content re-downloads.",
    tint: "#57c1ff",
  },
  {
    icon: AppDashedIcon,
    title: "App leftovers",
    body: "Support files and preferences from apps that are no longer installed.",
    tint: "#57c1ff",
  },
  {
    icon: DocIcon,
    title: "Logs",
    body: "Diagnostic text written by apps. Nothing reads them once the app has moved on.",
    tint: "#9c9c9d",
  },
  {
    icon: PhoneIcon,
    title: "Device backups",
    body: "Old iPhone and iPad backups. Opt in only, because a backup is not something you can rebuild.",
    tint: "#ffc533",
  },
  {
    icon: TrashIcon,
    title: "Trash",
    body: "Items already in the Trash. Opt in only, because emptying it is permanent.",
    tint: "#ff6161",
  },
];

const faqs = [
  {
    q: "Is there a main window?",
    a: "No. The panel is the app. Settings opens in its own small window, and the command bar appears over whatever you are working in.",
  },
  {
    q: "How do I know it will not delete something I need?",
    a: "Crest only reads your home folder, never system files. Every scan lists what it found with a size and a description of what happens if it goes. Removal moves things to the Trash, so anything you disagree with is one drag back.",
  },
  {
    q: "Does it need Accessibility permission?",
    a: "Only for dictation. Every shortcut, including ⌥Space, is registered with the system hot key API, so macOS delivers that one combination to Crest instead of the app watching every keystroke. Push to talk cannot work that way: a bare modifier key has no release event to register, so it needs an event tap, and an event tap needs Accessibility. Leave dictation off and Crest never asks.",
  },
  {
    q: "Is anything I dictate or record sent anywhere?",
    a: "No. Transcription is the speech recogniser in macOS 26, and the cleanup and meeting summaries are Apple's on-device model. Both ship with the OS and both run here. Crest has no server to send audio to.",
  },
  {
    q: "What happens without the screen recording grant?",
    a: "A meeting still records, but only your side of it, and the recorder says so at the start rather than handing you half a conversation with no explanation. The grant is what lets macOS give Crest the audio coming out of your speakers, which is everyone else on the call.",
  },
  {
    q: "Can I change the shortcut?",
    a: "Yes. ⌥Space is the default because it sits next to Spotlight without colliding with it. Pick any combination in Settings, and Crest tells you straight away if another app has claimed it.",
  },
  {
    q: "What does it cost in battery?",
    a: "Depends what you put in the menu bar. Free space and battery percentage cost nothing extra. CPU and memory keep a one second sampler running even when the panel is closed.",
  },
  {
    q: "Is the app signed?",
    a: "Not yet. Signing and notarisation need a paid Apple Developer ID, which Crest does not have at launch. That is why the install needs an xattr line afterwards, and why the dmg needs an Open Anyway on first run. Both go away once it is notarised.",
  },
  {
    q: "Do I need Docker or Homebrew?",
    a: "No. If Docker is not running, or the brew CLI is not on your PATH, that section says so instead of showing an empty list. Hide either one in Settings and its tab goes with it.",
  },
];

export default function Home() {
  return (
    <>
      <SiteNav />

      <main className="flex-1">
        {/* Hero. Centred, minimal, and the only place the stripe band appears.
            Pulled up under the sticky nav — the nav takes 72px of flow (pt-4 +
            h-14), and without this the stripe band starts below it, leaving a
            bare strip of canvas across the top of the page. */}
        <section className="relative -mt-[72px] flex min-h-[calc(86svh+72px)] items-center overflow-hidden px-6 pt-[72px]">
          <div className="hero-stripes pointer-events-none absolute inset-x-0 -top-10 h-[460px]" />

          <div className="relative mx-auto w-full max-w-[940px] pt-10 pb-16 text-center">
          

            <h1
              className="rise display text-[36px] leading-[1.1] font-semibold text-ink sm:text-[48px] lg:text-[57px]"
              style={{ "--delay": "140ms" } as React.CSSProperties}
            >
              Your shortcut to everything
              <br />
              <span className="text-stone">your Mac is doing.</span>
            </h1>

            <p
              className="rise mx-auto mt-6 max-w-[560px] text-[17px] leading-[1.6] text-body"
              style={{ "--delay": "240ms" } as React.CSSProperties}
            >
              One menu bar panel for storage, system load, battery and cleanup. One shortcut for
              everything else, and one key you hold to talk instead of type.
            </p>

            <div
              className="rise mt-9 flex flex-col items-center gap-3"
              style={{ "--delay": "340ms" } as React.CSSProperties}
            >
              <ButtonPrimary href="/download" className="h-10 px-5">
                <AppleIcon className="size-[15px]" />
                Download for macOS
              </ButtonPrimary>
              <p className="text-[13px] text-mute">
                Free. macOS 26 Tahoe or later. Or{" "}
                <a href="#install" className="text-body underline-offset-4 hover:underline">
                  install with Homebrew
                </a>
                .
              </p>
            </div>
          </div>
        </section>

        {/* The product shot, sized to one screen. */}
        <section
          id="showcase"
          className="stage-glow relative flex min-h-[100svh] items-center border-y border-hairline px-4 py-14 sm:px-6"
        >
          <div className="mx-auto w-full max-w-[1160px]">
            <ShowcaseMock />
            <p className="reveal mt-6 text-center text-[14px] text-mute">
              Click the menu bar item for the panel. Press{" "}
              <span className="inline-flex translate-y-[2px] items-center gap-1">
                <Keycap>⌥</Keycap>
                <Keycap>Space</Keycap>
              </span>{" "}
              for the command bar.
            </p>
          </div>
        </section>

        {/* Eight sections */}
        <Section id="panel">
          <SectionHeading
            center
            title="Twelve sections."
            subtitle="Only the one you are looking at does any work."
            body="Hide the ones you have no use for, and drag the rest into the order you want them in. The tab bar is whatever is left."
          />

          <div className="mt-12 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
            {sections.map(({ icon: Icon, title, body }, i) => (
              <div
                key={title}
                className="reveal"
                style={{ "--stagger": `${(i % 4) * 3}%` } as React.CSSProperties}
              >
                <Card className="h-full">
                  <span className="flex size-9 items-center justify-center rounded-md bg-card text-body">
                    <Icon className="size-[17px]" />
                  </span>
                  <h3 className="mt-4 text-[18px] leading-[1.4] font-medium tracking-[0.2px] text-ink">
                    {title}
                  </h3>
                  <p className="mt-2 text-[14px] leading-[1.6] text-mute">{body}</p>
                </Card>
              </div>
            ))}
          </div>
        </Section>

        {/* Statement */}
        <Section>
          <div className="grid items-center gap-12 lg:grid-cols-[minmax(0,460px)_minmax(0,1fr)] lg:gap-14">
            <div className="reveal">
              <h2 className="display text-[28px] leading-[1.15] font-medium tracking-[0.2px] text-ink md:text-[34px]">
                It is not about the free space.
                <br />
                <span className="text-stone">It is about never wondering where it went.</span>
              </h2>
              <p className="mt-6 max-w-[420px] text-[16px] leading-[1.6] text-body">
                Crest answers the question in the menu bar, before you have to go looking for a
                tool that answers it.
              </p>
              <div className="mt-8">
                <ButtonPrimary href="/download" className="h-10 px-5">
                  <AppleIcon className="size-[15px]" />
                  Download
                </ButtonPrimary>
              </div>
            </div>

            <KeyboardStage />
          </div>
        </Section>

        {/* Command bar */}
        <Section id="command-bar">
          <SectionHeading
            center
            title="Press ⌥Space."
            subtitle="Then type what you were about to go looking for."
          />

          <div className="mt-12 grid gap-4">
            <div className="reveal grid overflow-hidden rounded-lg border border-hairline bg-surface lg:grid-cols-2">
              <div className="p-6 sm:p-10">
                <span className="flex size-9 items-center justify-center rounded-md bg-card text-body">
                  <SearchIcon className="size-[17px]" />
                </span>
                <h3 className="mt-5 text-[22px] leading-[1.15] font-medium text-ink">
                  Launch anything
                </h3>
                <p className="mt-3 max-w-[420px] text-[15px] leading-[1.6] text-mute">
                  Fuzzy matching across your apps, ranked by what you actually open. The index is
                  built in the background at launch, so the first search is as fast as the
                  hundredth. System Settings panes, sleep and restart, and Crest actions sit in
                  the same list: quick scan, clean developer junk, Docker prune, start dictation.
                </p>
                <p className="mt-3 max-w-[420px] text-[15px] leading-[1.6] text-mute">
                  Teach it your own names for things, so <span className="text-body">db</span>{" "}
                  opens the database client and <span className="text-body">t</span> opens the
                  terminal. An alias matches as a whole word, never fuzzily, so a two letter one
                  lands on exactly what you meant.
                </p>
                <div className="mt-6 flex items-center gap-[6px] text-[13px] text-mute">
                  Rebind it in Settings
                  <Keycap>⌥</Keycap>
                  <Keycap>Space</Keycap>
                </div>
              </div>

              <div className="relative min-h-[280px] overflow-hidden border-t border-hairline bg-elevated lg:border-t-0 lg:border-l">
                <div className="absolute top-8 left-8 w-[420px] max-w-[calc(100%-2rem)] lg:top-10">
                  <CommandBarMock className="max-w-none" />
                </div>
              </div>
            </div>

            <div className="grid gap-4 md:grid-cols-3">
              <div className="reveal">
                <Card className="h-full">
                  <CalcMock />
                  <h3 className="mt-6 text-[20px] leading-[1.2] font-medium text-ink">
                    Do the arithmetic
                  </h3>
                  <p className="mt-2 text-[15px] leading-[1.6] text-mute">
                    Type a sum or a unit conversion and the answer outranks every fuzzy match,
                    because only the calculator could have parsed it.
                  </p>
                </Card>
              </div>

              <div className="reveal" style={{ "--stagger": "3%" } as React.CSSProperties}>
                <Card className="h-full">
                  <ClipboardMock />
                  <h3 className="mt-6 text-[20px] leading-[1.2] font-medium text-ink">
                    Paste something back
                  </h3>
                  <p className="mt-2 text-[15px] leading-[1.6] text-mute">
                    Search the last 150 things you copied, pin the ones you keep reaching for, and
                    put any of them back on the clipboard.
                  </p>
                </Card>
              </div>

              <div className="reveal" style={{ "--stagger": "6%" } as React.CSSProperties}>
                <Card className="h-full">
                  <FileSearchMock />
                  <h3 className="mt-6 text-[20px] leading-[1.2] font-medium text-ink">
                    Open a file
                  </h3>
                  <p className="mt-2 text-[15px] leading-[1.6] text-mute">
                    Files come from the Spotlight index macOS already keeps, so there is no second
                    index to build. Six rows at most in a mixed search, the whole list when you
                    ask for files and nothing else.
                  </p>
                </Card>
              </div>
            </div>
          </div>
        </Section>

        {/* Voice and meetings */}
        <Section id="voice">
          <SectionHeading
            center
            title="Hold a key and talk."
            subtitle="The text lands where you were already typing."
          />

          <div className="mt-12 grid gap-4">
            <div className="reveal grid overflow-hidden rounded-lg border border-hairline bg-surface lg:grid-cols-2">
              <div className="p-6 sm:p-10">
                <span className="flex size-9 items-center justify-center rounded-md bg-card text-body">
                  <MicIcon className="size-[17px]" />
                </span>
                <h3 className="mt-5 text-[22px] leading-[1.15] font-medium text-ink">
                  Dictation, on this Mac
                </h3>
                <p className="mt-3 max-w-[420px] text-[15px] leading-[1.6] text-mute">
                  Hold the key you picked, say the sentence, let go. Crest tidies the filler and
                  the spoken punctuation out of it and inserts the result into whatever had focus.
                  Speech recognition and cleanup both ship with macOS, so nothing is uploaded and
                  nothing is transcribed by anyone else.
                </p>
                <p className="mt-3 max-w-[420px] text-[15px] leading-[1.6] text-mute">
                  Four styles decide how it reads. Prose writes full sentences, Chat drops the
                  full stop nobody types in Slack, Code stays lowercase and turns spoken symbols
                  into real ones, Verbatim changes nothing.
                </p>
                <div className="mt-6 flex flex-wrap items-center gap-2">
                  {["Prose", "Chat", "Code", "Verbatim"].map((style) => (
                    <span
                      key={style}
                      className="rounded-full bg-elevated px-[10px] py-1 text-[13px] text-body"
                    >
                      {style}
                    </span>
                  ))}
                </div>
              </div>

              <div className="relative flex min-h-[280px] flex-col justify-center gap-5 border-t border-hairline bg-elevated p-6 sm:p-10 lg:border-t-0 lg:border-l">
                <VoiceHudMock className="self-start" />
                <DictationMock />
              </div>
            </div>

            <div className="grid gap-4 md:grid-cols-2">
              <div className="reveal">
                <Card className="h-full">
                  <MeetingMock />
                  <h3 className="mt-6 text-[20px] leading-[1.2] font-medium text-ink">
                    Sit in on the call
                  </h3>
                  <p className="mt-2 text-[15px] leading-[1.6] text-mute">
                    Your microphone and the call audio are recorded and transcribed separately, so
                    the transcript knows who said what without guessing. The summary, its
                    decisions and its action items are written by the model built into macOS, and
                    the whole thing exports as Markdown.
                  </p>
                </Card>
              </div>

              <div className="reveal" style={{ "--stagger": "3%" } as React.CSSProperties}>
                <Card className="h-full">
                  <div className="space-y-3">
                    {[
                      {
                        icon: TagIcon,
                        t: "Your vocabulary",
                        d: "Names, product words and the spellings it keeps getting wrong, in a text file you edit.",
                      },
                      {
                        icon: WrenchIcon,
                        t: "Rewrite the selection",
                        d: "Select a paragraph anywhere, hold the command key and say what to do with it.",
                      },
                      {
                        icon: ShieldIcon,
                        t: "Guarded against helpfulness",
                        d: "Dictate a question and a model wants to answer it. Anything that introduces a word you never said is thrown away.",
                      },
                    ].map(({ icon: Icon, t, d }) => (
                      <div key={t} className="flex gap-3">
                        <span className="mt-[1px] flex size-7 shrink-0 items-center justify-center rounded-md bg-card text-body">
                          <Icon className="size-[15px]" />
                        </span>
                        <div>
                          <p className="text-[14px] font-medium tracking-[0.2px] text-ink">{t}</p>
                          <p className="mt-1 text-[14px] leading-[1.6] text-mute">{d}</p>
                        </div>
                      </div>
                    ))}
                  </div>

                  <div className="mt-5 border-t border-hairline pt-4">
                    <p className="text-[14px] leading-[1.6] text-mute">
                      Voice is the one part of Crest that needs permissions. Accessibility, so the
                      held key is seen at all. The microphone. Screen and system audio recording
                      for the other side of a call, and without it a meeting still records your
                      half and says so.
                    </p>
                  </div>
                </Card>
              </div>
            </div>
          </div>
        </Section>

        {/* Cleaner */}
        {/* Tiling */}
        <Section id="tiling">
          <SectionHeading
            center
            title="Your windows, arranged."
            subtitle="Nine workspaces, four layouts, and a key for each of them."
          />

          <div className="mt-12 grid items-start gap-10 lg:grid-cols-[minmax(0,1fr)_minmax(0,1.1fr)] lg:gap-14">
            <div className="space-y-3">
              {tilingLayouts.map(({ title, body }, i) => (
                <div
                  key={title}
                  className="reveal rounded-md border border-hairline bg-surface p-4 transition-colors duration-300 hover:border-hairline-strong"
                  style={{ "--stagger": `${i * 2}%` } as React.CSSProperties}
                >
                  <p className="text-[14px] font-medium tracking-[0.2px] text-ink">{title}</p>
                  <p className="mt-1 text-[14px] leading-[1.6] text-mute">{body}</p>
                </div>
              ))}

              <div className="reveal rounded-md border border-hairline bg-card p-4">
                <p className="text-[14px] leading-[1.6] text-mute">
                  macOS will not let anything replace its window server, so Crest moves windows
                  through the Accessibility API instead. Workspaces are Crest&rsquo;s own rather
                  than Spaces, which cannot be switched without turning off System Integrity
                  Protection. Turning tiling off puts every window back.
                </p>
              </div>
            </div>

            <div className="space-y-6">
              {tilingShortcuts.map(({ group, rows }) => (
                <div key={group} className="reveal">
                  <p className="text-[13px] font-medium uppercase tracking-[0.8px] text-mute">
                    {group}
                  </p>
                  <div className="mt-3 space-y-2">
                    {rows.map(({ keys, label }) => (
                      <div
                        key={label}
                        className="flex flex-wrap items-center gap-x-3 gap-y-2 rounded-md border border-hairline bg-surface px-4 py-2.5"
                      >
                        <span className="flex shrink-0 items-center gap-1">
                          {keys.map((key) => (
                            <Keycap key={key}>{key === "mod" ? "⌃⌘" : key}</Keycap>
                          ))}
                        </span>
                        <span className="text-[14px] leading-[1.6] text-mute">{label}</span>
                      </div>
                    ))}
                  </div>
                </div>
              ))}

              <p className="reveal text-[14px] leading-[1.6] text-mute">
                <Keycap>⌃⌘</Keycap> stands in for Omarchy&rsquo;s SUPER key, and every shortcut
                hangs off it. Pick a different one in Settings if it collides with something you
                already use, and the whole map moves with it.
              </p>
            </div>
          </div>
        </Section>

        <Section id="cleaner">
          <SectionHeading
            center
            title="It shows you the bill first."
            subtitle="Then it removes exactly what you ticked."
          />

          <div className="mt-12 grid items-start gap-10 lg:grid-cols-2 lg:gap-14">
            <div className="reveal order-2 lg:order-1 lg:sticky lg:top-28">
              <CleanerMock />
              <p className="mt-4 text-[14px] leading-[1.6] text-mute">
                Set a minimum age and a minimum size in Settings. Anything under the threshold is
                still counted, grouped into one row per category rather than listed individually.
              </p>
            </div>

            <div className="order-1 space-y-3 lg:order-2">
              {cleanerCategories.map(({ icon: Icon, title, body, tint }, i) => (
                <div
                  key={title}
                  className="reveal flex gap-3 rounded-md border border-hairline bg-surface p-4 transition-colors duration-300 hover:border-hairline-strong"
                  style={{ "--stagger": `${i * 2}%` } as React.CSSProperties}
                >
                  <span
                    className="mt-[1px] flex size-7 shrink-0 items-center justify-center rounded-md bg-card"
                    style={{ color: tint }}
                  >
                    <Icon className="size-[15px]" />
                  </span>
                  <div>
                    <p className="text-[14px] font-medium tracking-[0.2px] text-ink">{title}</p>
                    <p className="mt-1 text-[14px] leading-[1.6] text-mute">{body}</p>
                  </div>
                </div>
              ))}
            </div>
          </div>
        </Section>

        {/* Small tools */}
        <Section>
          <SectionHeading
            center
            title="The small stuff too."
            subtitle="So you can delete the three apps you kept for it."
          />

          <div className="mt-12 grid gap-4 md:grid-cols-3">
            {[
              {
                icon: CupIcon,
                t: "Keep Awake",
                d: "Hold sleep off for a set stretch, and choose whether the display may sleep anyway. Change the duration mid-session and it adopts the new deadline.",
              },
              {
                icon: EyedropperIcon,
                t: "Colour picker",
                d: "The system magnifier samples the pixel, so Crest never needs Screen Recording. The value lands on your clipboard in the format you chose.",
              },
              {
                icon: BatteryIcon,
                t: "Menu bar metric",
                d: "Show free space, CPU, memory or battery in the menu bar, or just the icon. The panel is one click away either way.",
              },
              {
                icon: AppMinusIcon,
                t: "Uninstaller",
                d: "Drag an app in, or pick it from the list, and Crest finds the support files, preferences, caches and login items it left behind. Every path is listed before anything moves.",
              },
              {
                icon: KeyboardIcon,
                t: "Shortcuts of your own",
                d: "Give an app or a Crest action its own combination. They go through the same system hot key API as ⌥Space, so none of them need Accessibility either.",
              },
              {
                icon: NetworkIcon,
                t: "Update check",
                d: "Crest asks GitHub whether a newer release exists and tells you. It never downloads or replaces itself, and the check turns off in Settings.",
              },
            ].map(({ icon: Icon, t, d }, i) => (
              <div
                key={t}
                className="reveal"
                style={{ "--stagger": `${(i % 3) * 3}%` } as React.CSSProperties}
              >
                <Card elevated className="h-full">
                  <span className="flex size-9 items-center justify-center rounded-md bg-card text-body">
                    <Icon className="size-[17px]" />
                  </span>
                  <h3 className="mt-4 text-[18px] leading-[1.4] font-medium tracking-[0.2px] text-ink">
                    {t}
                  </h3>
                  <p className="mt-2 text-[14px] leading-[1.6] text-mute">{d}</p>
                </Card>
              </div>
            ))}
          </div>
        </Section>

        {/* Privacy */}
        <Section id="privacy">
          <SectionHeading
            center
            title="A disk tool should ask for less."
            subtitle="Crest asks for almost nothing."
          />

          <div className="mt-12 grid gap-4 md:grid-cols-3">
            {[
              {
                icon: LockIcon,
                t: "Nothing leaves your Mac",
                d: "No sign in, no account, no telemetry. Speech is transcribed and summaries are written by the models built into macOS, so a dictated sentence and a recorded call never reach a server. The one call Crest makes is asking GitHub whether there is a newer version, and that switches off.",
              },
              {
                icon: ShieldIcon,
                t: "Permissions only where the feature needs one",
                d: "The panel, the cleaner and the command bar ask for nothing: the hot key goes through the system API rather than a keystroke monitor, and the colour picker uses the OS sampler. Dictation is the exception, and it says which grants it wants before you turn it on.",
              },
              {
                icon: TrashIcon,
                t: "Removal goes to the Trash",
                d: "Cleanup moves files where you can see them and put them back. Only Trash itself, which you opt into, is permanent.",
              },
            ].map(({ icon: Icon, t, d }, i) => (
              <div
                key={t}
                className="reveal"
                style={{ "--stagger": `${i * 3}%` } as React.CSSProperties}
              >
                <Card className="h-full">
                  <span className="flex size-9 items-center justify-center rounded-md bg-card text-body">
                    <Icon className="size-[17px]" />
                  </span>
                  <h3 className="mt-4 text-[18px] leading-[1.4] font-medium tracking-[0.2px] text-ink">
                    {t}
                  </h3>
                  <p className="mt-2 text-[14px] leading-[1.6] text-mute">{d}</p>
                </Card>
              </div>
            ))}
          </div>

          <div className="reveal mt-4 rounded-lg border border-hairline bg-surface p-6">
            <p className="text-[14px] font-medium tracking-[0.2px] text-ink">What it never touches</p>
            <div className="mt-3 flex flex-wrap gap-2">
              {["Documents", "Desktop", "Photos", "System files", "Anything outside your home folder"].map(
                (item) => (
                  <span
                    key={item}
                    className="rounded-full bg-elevated px-[10px] py-1 text-[14px] text-body"
                  >
                    {item}
                  </span>
                ),
              )}
            </div>
          </div>
        </Section>

        {/* FAQ */}
        <Section id="faq">
          <div className="grid gap-12 lg:grid-cols-[380px_1fr] lg:gap-16">
            <SectionHeading
              eyebrow="FAQ"
              title="The questions worth answering first."
              className="lg:sticky lg:top-28 lg:self-start"
            />

            <div className="border-t border-hairline">
              {faqs.map((faq, i) => (
                <div
                  key={faq.q}
                  className="reveal border-b border-hairline py-6"
                  style={{ "--stagger": `${i * 1.5}%` } as React.CSSProperties}
                >
                  <h3 className="text-[18px] leading-[1.4] font-medium tracking-[0.2px] text-ink">
                    {faq.q}
                  </h3>
                  <p className="mt-2 max-w-[640px] text-[15px] leading-[1.6] text-mute">{faq.a}</p>
                </div>
              ))}
            </div>
          </div>
        </Section>

        {/* Install */}
        <Section id="install" className="pb-24">
          <div className="reveal relative overflow-hidden rounded-xl border border-hairline bg-surface px-6 py-16 md:px-12">
            <div className="stage-glow pointer-events-none absolute inset-0" />

            <div className="relative">
              <h2 className="display mx-auto max-w-[720px] text-center text-[30px] leading-[1.15] font-medium tracking-[0.2px] text-ink md:text-[42px]">
                Put it in the menu bar.
                <br />
                <span className="text-stone">Then forget it is there.</span>
              </h2>

              <div className="mx-auto mt-12 grid max-w-[900px] gap-4">
                <div className="rounded-lg border border-hairline bg-canvas/60 p-6">
                  <div className="flex flex-wrap items-center gap-2">
                    <h3 className="text-[18px] leading-[1.4] font-medium tracking-[0.2px] text-ink">
                      Homebrew
                    </h3>
                    <Badge>Recommended</Badge>
                    <p className="w-full text-[14px] leading-[1.6] text-mute sm:ml-auto sm:w-auto">
                      <span className="text-body">brew upgrade</span> keeps it current afterwards.
                    </p>
                  </div>
                  <CopyCommand
                    className="mt-5"
                    command={[
                      "brew install --cask derrick-kello/tap/crest",
                      "xattr -dr com.apple.quarantine /Applications/Crest.app",
                    ]}
                  />
                </div>

                <div className="grid gap-4 md:grid-cols-2">
                  <div className="flex flex-col rounded-lg border border-hairline bg-canvas/60 p-6">
                    <h3 className="text-[18px] leading-[1.4] font-medium tracking-[0.2px] text-ink">
                      Direct download
                    </h3>
                    <p className="mt-2 text-[14px] leading-[1.6] text-mute">
                      A disk image with the app inside. Drag it to Applications, then read the note
                      beside this before the first launch.
                    </p>
                    <div className="mt-5">
                      <ButtonPrimary href="/download" className="h-10 px-5">
                        <AppleIcon className="size-[15px]" />
                        Download the dmg
                      </ButtonPrimary>
                    </div>
                  </div>

                  <div className="rounded-lg border border-hairline bg-canvas/60 p-6">
                    <h3 className="text-[18px] leading-[1.4] font-medium tracking-[0.2px] text-ink">
                      Why the second line
                    </h3>
                    <p className="mt-2 text-[14px] leading-[1.6] text-mute">
                      Crest is not notarised by Apple yet, so macOS marks it as quarantined and
                      refuses to open it. The <span className="text-body">xattr</span> line clears
                      that mark on the app you just installed, and nothing else. Skip it if you
                      prefer: open the app, let macOS block it, then go to System Settings, Privacy
                      and Security, and press Open Anyway.
                    </p>
                  </div>
                </div>
              </div>

              <div
                id="requirements"
                className="mx-auto mt-12 flex max-w-[900px] flex-wrap items-center justify-center gap-2 border-t border-hairline pt-8"
              >
                <Badge>macOS 26 Tahoe</Badge>
                <Badge>Apple silicon and Intel</Badge>
                <Badge>Universal build</Badge>
                <Badge>Launch at login</Badge>
                <Badge>Apple Intelligence for voice cleanup and summaries</Badge>
                <Badge>Version 1.0</Badge>
              </div>
            </div>
          </div>
        </Section>

      </main>

      <SiteFooter />
    </>
  );
}
