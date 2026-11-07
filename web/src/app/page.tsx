import Image from "next/image";
import { Check, Code, Gift, Lock, Minus, Package, ShieldCheck, Wrench, type LucideIcon } from "lucide-react";
import launcherIcon from "@/assets/slopapp-icon.webp";
import { AppCard } from "@/components/AppCard";
import { AppIcon } from "@/components/AppIcon";
import { GitHubMark } from "@/components/GitHubMark";
import { Logo } from "@/components/Logo";
import { Mark } from "@/components/Mark";
import { apps, brand, isBuilt, priorityGroups, type Flavour } from "@/lib/catalog";

const groups = priorityGroups
  .map((group) => ({ ...group, apps: apps.filter((app) => app.priority === group.priority) }))
  .filter((group) => group.apps.length > 0);
// The launcher is the big icon; the dock under it shows the first apps it installs.
const dockApps = apps.filter((app) => app.priority === 1 || app.priority === 2).slice(0, 6);
const builtCount = apps.filter(isBuilt).length;
// First sentence of the brand description; the promise strip covers the rest.
const oneLiner = brand.description.split(". ")[0].replace(/\.?$/, ".");
// "The name is a joke." / "The apps aren't."
const [taglineLead, ...taglineRest] = brand.tagline.split(/(?<=\.)\s+/);

type Note = { icon: LucideIcon; title: string; body: string; flavour: Flavour };

const promises: Note[] = [
  {
    icon: Gift,
    title: "Free forever",
    body: "No trial, no subscription, no paid tier. Every app costs $0.",
    flavour: "strawberry",
  },
  {
    icon: Code,
    title: "Open source",
    body: `${brand.license}-licensed Swift code. Read it, fork it, fix it.`,
    flavour: "blueberry",
  },
  {
    icon: Lock,
    title: "Private",
    body: "No account, no analytics, no tracking. Your data stays on your Mac.",
    flavour: "lime",
  },
];

const buildNotes: Note[] = [
  {
    icon: Package,
    title: "Native Swift",
    body: "SwiftUI and AppKit. Small, fast, and at home on macOS.",
    flavour: "tangerine",
  },
  {
    icon: Wrench,
    title: "One design system",
    body: "Every app follows the same rules, so they feel like a set.",
    flavour: "grape",
  },
  {
    icon: ShieldCheck,
    title: "Tested in CI",
    body: "Every app is built and tested on every change.",
    flavour: "lagoon",
  },
];

const comparison = [
  { label: "Price", setapp: "Monthly subscription (from $9.99)", slopapp: "$0" },
  { label: "Account", setapp: "Required", slopapp: "None" },
  { label: "Source code", setapp: "Closed", slopapp: `Open, ${brand.license} licensed` },
  { label: "Apps", setapp: "270+ curated apps", slopapp: "A growing set of everyday utilities" },
];

// Tinted badge per flavour: translucent fill, ink glyph (each ink clears 4.5:1 on its tint).
const badge: Record<Flavour, string> = {
  strawberry: "bg-strawberry/14 text-strawberry-ink ring-strawberry/20",
  tangerine: "bg-tangerine/16 text-tangerine-ink ring-tangerine/25",
  lime: "bg-lime/18 text-lime-ink ring-lime/25",
  lagoon: "bg-lagoon/14 text-lagoon-ink ring-lagoon/20",
  blueberry: "bg-blueberry/14 text-blueberry-ink ring-blueberry/20",
  grape: "bg-grape/14 text-grape-ink ring-grape/20",
};

const focusRing = "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-blueberry";
const buttonBase = `inline-flex items-center justify-center gap-2 rounded-full px-5 py-3 text-[0.9375rem] font-semibold ${focusRing}`;
const buttonQuiet = `${buttonBase} glass text-heading transition hover:bg-surface`;
const container = "mx-auto max-w-6xl px-4 sm:px-6";

function NoteCard({ note, className = "" }: { note: Note; className?: string }) {
  const { icon: Icon, title, body, flavour } = note;
  return (
    <li className={`glass rounded-3xl p-5 ${className}`}>
      <span className={`flex size-10 items-center justify-center rounded-xl ring-1 ring-inset ${badge[flavour]}`}>
        <Icon size={20} aria-hidden />
      </span>
      <h3 className="mt-4 font-display text-lg font-semibold text-heading">{title}</h3>
      <p className="mt-1 text-sm leading-relaxed text-muted">{body}</p>
    </li>
  );
}

export default function Home() {
  return (
    <>
      <header className="glass-bar sticky top-0 z-40">
        <div className={`${container} flex h-16 items-center justify-between`}>
          <a href="#top" className={`flex items-center gap-2.5 rounded-lg ${focusRing}`} aria-label={`${brand.name} home`}>
            <Logo className="size-8 drop-shadow-[0_2px_6px_rgb(240_64_122/0.35)]" />
            <span className="font-display text-xl font-semibold text-heading">{brand.name}</span>
          </a>
          <nav className="flex items-center gap-1 text-sm font-medium">
            <a
              href="#apps"
              className={`hidden rounded-full px-3 py-2 text-muted transition-colors hover:text-heading sm:inline ${focusRing}`}
            >
              Apps
            </a>
            <a
              href={brand.repoUrl}
              className={`inline-flex items-center gap-2 rounded-full px-3 py-2 text-muted transition-colors hover:text-heading ${focusRing}`}
            >
              <GitHubMark className="size-5" />
              <span className="hidden sm:inline">GitHub</span>
              <span className="sr-only sm:hidden">GitHub</span>
            </a>
          </nav>
        </div>
      </header>

      <main id="top">
        {/* Frame: hero and promise, on the candy wash */}
        <div className="relative isolate overflow-hidden">
          <div aria-hidden className="candy-wash absolute inset-0 -z-10" />

          <section className={`${container} grid items-center gap-12 pb-16 pt-12 md:grid-cols-[1.25fr_1fr] md:pb-24 md:pt-20`}>
            <div>
              <h1 className="text-balance font-display text-[2.75rem] font-bold leading-[1.02] tracking-tight text-heading sm:text-6xl lg:text-[4rem]">
                <span className="block">{taglineLead}</span>
                {taglineRest.length > 0 && <span className="candy-text block pb-1">{taglineRest.join(" ")}</span>}
              </h1>
              <p className="mt-6 max-w-xl text-lg leading-relaxed text-muted">
                {oneLiner} Like Setapp, minus the subscription.
              </p>
              <div className="mt-8 flex flex-wrap gap-3">
                <a href="#apps" className={`${buttonBase} btn-candy`}>
                  Browse the apps
                </a>
                <a href={brand.repoUrl} className={buttonQuiet}>
                  <GitHubMark className="size-4" />
                  View on GitHub
                </a>
              </div>
            </div>

            {/* The launcher icon over a frosted dock of the apps it installs */}
            <div className="relative mx-auto flex w-full max-w-md flex-col items-center" aria-hidden>
              <div className="absolute left-1/2 top-[38%] -z-10 size-72 -translate-x-1/2 -translate-y-1/2 rounded-full bg-[radial-gradient(closest-side,rgb(240_64_122/0.45),rgb(242_138_12/0.18)_60%,transparent)] blur-2xl" />
              <Image
                src={launcherIcon}
                alt=""
                priority
                sizes="(min-width: 640px) 320px, 240px"
                className="relative w-60 animate-float drop-shadow-[0_28px_36px_rgb(150_30_70/0.35)] sm:w-80"
              />
              <div className="glass mt-2 flex gap-2.5 rounded-[1.75rem] p-3 sm:mt-1 sm:gap-3 sm:p-3.5">
                {dockApps.map((app, i) => (
                  <span key={app.slug} className={i === 5 ? "hidden sm:flex" : "flex"}>
                    <AppIcon name={app.icon} size={48} />
                  </span>
                ))}
              </div>
            </div>
          </section>

          <section aria-label="Our promise" className={`${container} pb-20`}>
            <ul className="grid gap-4 sm:grid-cols-3">
              {promises.map((note) => (
                <NoteCard key={note.title} note={note} />
              ))}
            </ul>
          </section>
        </div>

        {/* Collection: calm and quiet, for reading */}
        <section id="apps" className="scroll-mt-16 border-t border-line bg-page">
          <div className={`${container} py-20`}>
            <div className="flex flex-wrap items-end justify-between gap-4">
              <h2 className="font-display text-4xl font-bold tracking-tight text-heading">The collection</h2>
              <p className="text-sm text-muted">
                {builtCount > 0
                  ? `${builtCount} ready to download, ${apps.length - builtCount} on the way.`
                  : `${apps.length} apps on the way.`}
              </p>
            </div>

            {groups.map((group) => (
              <div key={group.priority} className="mt-12">
                <div className="flex flex-wrap items-baseline gap-x-3 gap-y-1 border-b border-line pb-3">
                  <h3 className="text-sm font-semibold uppercase tracking-wider text-heading">{group.title}</h3>
                  <p className="text-sm text-muted">{group.note}</p>
                </div>
                <ul className="mt-5 grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
                  {group.apps.map((app) => (
                    <AppCard key={app.slug} app={app} />
                  ))}
                </ul>
              </div>
            ))}
          </div>
        </section>

        {/* Comparison: candy glass shell around a frosted panel */}
        <section aria-labelledby="compare" className="relative isolate overflow-hidden">
          <div aria-hidden className="candy-wash-cool absolute inset-0 -z-10" />
          <div className={`${container} py-20`}>
            <div className="candy-shell rounded-[2rem] p-2 sm:p-3">
              <h2
                id="compare"
                className="px-4 pb-5 pt-6 font-display text-3xl font-bold tracking-tight text-white sm:px-6 sm:pt-8 sm:text-4xl"
              >
                Same idea. No bill.
              </h2>
              <div className="glass rounded-[1.5rem] px-4 [--glass-bg:var(--glass-thick)] sm:rounded-[1.25rem] sm:px-6">
                {/* Phones: one block per row, both answers side by side */}
                <div className="text-sm sm:hidden">
                  <div className="grid grid-cols-2 gap-3 border-b border-line py-3 text-xs font-semibold" aria-hidden>
                    <span className="text-muted">Setapp</span>
                    <span className="inline-flex items-center gap-1.5 text-heading">
                      <Logo className="size-4" />
                      {brand.name}
                    </span>
                  </div>
                  <dl className="divide-y divide-line">
                    {comparison.map((row) => (
                      <div key={row.label} className="py-3.5">
                        <dt className="text-xs font-semibold uppercase tracking-wider text-muted">{row.label}</dt>
                        <dd className="mt-1.5 grid grid-cols-2 gap-3">
                          <span className="text-muted">
                            <span className="sr-only">Setapp: </span>
                            {row.setapp}
                          </span>
                          <span className="flex gap-1.5 font-medium text-heading">
                            <Check size={16} aria-hidden className="mt-0.5 shrink-0 text-strawberry-ink" />
                            <span>
                              <span className="sr-only">{brand.name}: </span>
                              {row.slopapp}
                            </span>
                          </span>
                        </dd>
                      </div>
                    ))}
                  </dl>
                </div>
                <table className="hidden w-full text-left text-sm sm:table">
                  <thead>
                    <tr className="border-b border-line">
                      <th scope="col" className="py-4 pr-4 font-normal">
                        <span className="sr-only">Feature</span>
                      </th>
                      <th scope="col" className="py-4 pr-4 font-semibold text-muted">
                        Setapp
                      </th>
                      <th scope="col" className="py-4 font-display text-base font-semibold">
                        <span className="inline-flex items-center gap-2 text-heading">
                          <Logo className="size-5" />
                          {brand.name}
                        </span>
                      </th>
                    </tr>
                  </thead>
                  <tbody>
                    {comparison.map((row) => (
                      <tr key={row.label} className="border-b border-line last:border-0">
                        <th scope="row" className="py-4 pr-4 font-medium text-muted">
                          {row.label}
                        </th>
                        <td className="py-4 pr-4 text-muted">
                          <span className="inline-flex items-center gap-2">
                            <Minus size={16} aria-hidden className="shrink-0 opacity-60" />
                            {row.setapp}
                          </span>
                        </td>
                        <td className="py-4 font-medium text-heading">
                          <span className="inline-flex items-center gap-2">
                            <Check size={16} aria-hidden className="shrink-0 text-strawberry-ink" />
                            {row.slopapp}
                          </span>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </div>
          </div>
        </section>

        {/* How it's built */}
        <section aria-labelledby="built" className={`${container} pb-24 pt-4`}>
          <div className="grid gap-10 lg:grid-cols-[0.9fr_1.6fr] lg:gap-12">
            <div>
              <h2 id="built" className="font-display text-[2rem] font-bold leading-tight sm:text-4xl tracking-tight text-heading">
                Careful, despite the name
              </h2>
              <p className="mt-4 leading-relaxed text-muted">
                We study how the best Mac utilities work, then build our own, natively, in one public
                repo. Spot a bug or want an app that isn&apos;t here yet? Open an issue or send a pull
                request.
              </p>
              <a href={brand.repoUrl} className={`${buttonBase} btn-candy mt-6`}>
                <GitHubMark className="size-4" />
                Contribute on GitHub
              </a>
            </div>
            <ul className="grid gap-4 sm:grid-cols-3">
              {buildNotes.map((note) => (
                <NoteCard key={note.title} note={note} />
              ))}
            </ul>
          </div>
        </section>
      </main>

      <footer className="border-t border-line">
        <div className={`${container} flex flex-col gap-4 py-8 text-sm text-muted sm:flex-row sm:items-center sm:justify-between`}>
          <div className="flex items-center gap-2 text-heading">
            <Mark className="size-5" />
            <span className="font-display font-semibold">{brand.name}</span>
            <span className="text-muted">· {brand.license} licensed</span>
          </div>
          <div className="flex flex-col gap-1 sm:items-end">
            <a href={brand.repoUrl} className={`rounded hover:text-heading ${focusRing}`}>
              Source on GitHub
            </a>
            <span className="text-xs">Not affiliated with Setapp or MacPaw.</span>
          </div>
        </div>
      </footer>
    </>
  );
}
