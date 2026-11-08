import { ArrowRight, Download } from "lucide-react";
import { AppCard, focusRing } from "@/components/AppCard";
import { AppIcon } from "@/components/AppIcon";
import { GitHubMark } from "@/components/GitHubMark";
import { Mark } from "@/components/Mark";
import { PrintPanel } from "@/components/Print";
import { apps, brand, catalog, isBuilt, priorityGroups } from "@/lib/catalog";
import { nordic, specimenFor } from "@/lib/herbarium";

const groups = priorityGroups
  .map((group) => ({ ...group, apps: apps.filter((app) => app.priority === group.priority) }))
  .filter((group) => group.apps.length > 0);
const builtCount = apps.filter(isBuilt).length;
const launcher = catalog.apps.find((app) => (app as { hub?: boolean }).hub);

// The hero's herbarium drawer: six mounted specimens (apps that have a herbarium icon).
const mounted = ["clips", "snapper", "switchboard", "paper", "awake", "tidy"]
  .map((slug) => apps.find((app) => app.slug === slug))
  .filter((app) => app && specimenFor(app.slug))
  .slice(0, 6) as typeof apps;

const principles = [
  {
    title: "Free",
    body: "No trial, no subscription, no paid tier. Every app costs nothing, now and later.",
    plate: "snapper",
    tile: nordic.clay,
    position: "25% 45%",
  },
  {
    title: "Open source",
    body: `${brand.license}-licensed Swift, developed in one public repository. Read it, fork it, improve it.`,
    plate: "tidy",
    tile: nordic.fjord,
    position: "15% 65%",
  },
  {
    title: "Private",
    body: "No account, no analytics, no tracking. Your clipboard, files and screenshots stay on your Mac.",
    plate: "commit",
    tile: nordic.heather,
    position: "35% 75%",
  },
];

const craft = [
  { title: "Native Swift", body: "SwiftUI and AppKit, for macOS 14 and later. Small, fast, at home on the Mac." },
  { title: "One design system", body: "Every app follows the same rules, so the set feels like one piece of work." },
  { title: "Tested on every change", body: "Each app is built, tested and launched in CI before it ships." },
];

const container = "mx-auto max-w-6xl px-4 sm:px-6";
const button = `inline-flex items-center justify-center gap-2 rounded-full px-5 py-3 text-[0.9375rem] font-semibold transition-colors ${focusRing}`;
const buttonPrimary = `${button} bg-action text-on-action hover:bg-action-hover`;
const buttonQuiet = `${button} border border-line-strong text-heading hover:bg-card-2`;
const sectionTitle = "font-serif text-[2.25rem] font-medium leading-[1.1] tracking-[-0.01em] text-heading sm:text-[2.75rem]";

export default function Home() {
  return (
    <>
      <a href="#main" className={`sr-only focus:not-sr-only focus:fixed focus:left-4 focus:top-4 focus:z-50 focus:rounded-full focus:bg-card focus:px-4 focus:py-2 ${focusRing}`}>
        Skip to content
      </a>

      <header className="sticky top-0 z-40 border-b border-line bg-paper/90 backdrop-blur-md">
        <div className={`${container} flex h-16 items-center justify-between`}>
          <a href="#top" className={`flex items-center gap-2.5 rounded-lg text-heading ${focusRing}`} aria-label={`${brand.name} home`}>
            <Mark className="size-7" />
            <span className="font-serif text-[1.375rem] font-medium tracking-[-0.01em]">{brand.name}</span>
          </a>
          <nav aria-label="Main" className="flex items-center gap-1 text-sm font-medium">
            <a href="#apps" className={`hidden rounded-full px-3 py-2 text-muted transition-colors hover:text-heading sm:inline ${focusRing}`}>
              Apps
            </a>
            <a href="#principles" className={`hidden rounded-full px-3 py-2 text-muted transition-colors hover:text-heading sm:inline ${focusRing}`}>
              Principles
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

      <main id="main">
        {/* Hero: the promise on paper, the collection as a herbarium drawer */}
        <section id="top" className={`${container} grid items-center gap-12 pb-20 pt-12 md:grid-cols-[1.1fr_1fr] md:gap-14 md:pb-28 md:pt-20`}>
          <div>
            <p className="label text-muted">Free and open source · For macOS 14 and later</p>
            <h1 className="mt-5 text-balance font-serif text-[2.875rem] font-medium leading-[1.02] tracking-[-0.02em] text-heading sm:text-6xl lg:text-[4.25rem]">
              {brand.tagline}
            </h1>
            <p className="mt-6 max-w-xl text-lg leading-relaxed text-text">
              {brand.name} is a growing collection of small, native utilities for the things you do every day:
              clipboard history, screenshots, opening links in the right browser, shrinking images.
            </p>
            <p className="mt-3 max-w-xl leading-relaxed text-muted">
              Every app is free and open source. No subscription, no account, no tracking.
            </p>
            <div className="mt-8 flex flex-wrap gap-3">
              <a href="#apps" className={buttonPrimary}>
                Browse the apps
                <ArrowRight size={17} aria-hidden />
              </a>
              <a href={brand.repoUrl} className={buttonQuiet}>
                <GitHubMark className="size-4" />
                View the source
              </a>
            </div>
          </div>

          <PrintPanel plate="switchboard" tile={nordic.sage} className="rounded-[2rem] p-4 sm:p-5">
            <ul className="grid grid-cols-2 gap-3 sm:gap-4 lg:grid-cols-3" aria-label="Some of the apps">
              {mounted.map((app) => {
                const specimen = specimenFor(app.slug)!;
                return (
                  <li key={app.slug} className="flex flex-col items-center rounded-2xl bg-card px-3 pb-3.5 pt-4 text-center shadow-[0_1px_2px_rgb(47_45_42/0.08)]">
                    <AppIcon slug={app.slug} name={app.icon} size={72} eager />
                    <span className="mt-2.5 text-sm font-semibold text-heading">{app.name}</span>
                    <span className="font-serif text-[0.8125rem] italic leading-snug text-muted">{specimen.plant}</span>
                  </li>
                );
              })}
            </ul>
          </PrintPanel>
        </section>

        {/* Principles */}
        <section id="principles" aria-labelledby="principles-title" className="scroll-mt-16 border-t border-line">
          <div className={`${container} py-20`}>
            <h2 id="principles-title" className="sr-only">
              Principles
            </h2>
            <ul className="grid gap-10 sm:grid-cols-3 sm:gap-8">
              {principles.map((p) => (
                <li key={p.title}>
                  <PrintPanel plate={p.plate} tile={p.tile} className="size-16 rounded-full" zoom={2.6} position={p.position} />
                  <h3 className="mt-5 font-serif text-[1.625rem] font-medium text-heading">{p.title}</h3>
                  <p className="mt-2 max-w-sm leading-relaxed text-muted">{p.body}</p>
                </li>
              ))}
            </ul>
          </div>
        </section>

        {/* The launcher */}
        {launcher && (
          <section aria-labelledby="launcher-title" className={`${container} pb-20`}>
            <PrintPanel plate="clips" tile={nordic.ochre} className="rounded-[2rem] p-3 sm:p-4" position="30% 80%">
              <div className="grid gap-6 rounded-[1.5rem] bg-card p-6 sm:grid-cols-[auto_1fr_auto] sm:items-center sm:p-8">
                <span className="flex size-16 items-center justify-center rounded-[1.1rem] bg-heading text-paper" aria-hidden>
                  <Mark className="size-10" />
                </span>
                <div>
                  <p className="label text-muted">Start here</p>
                  <h2 id="launcher-title" className="mt-1 font-serif text-[1.75rem] font-medium leading-tight text-heading">
                    The {brand.name} launcher
                  </h2>
                  <p className="mt-1.5 max-w-xl leading-relaxed text-text">
                    One small app that installs, updates and removes every app in the collection.
                  </p>
                  {isBuilt(launcher) && (
                    <p className="mt-3 max-w-xl text-sm leading-relaxed text-muted">
                      Open the disk image and drag {brand.name} to Applications. It isn&apos;t notarized yet, so the
                      first time you open it, macOS stops it: open System Settings &gt; Privacy &amp; Security,
                      scroll down and click Open Anyway. You only need to do this once.
                    </p>
                  )}
                </div>
                {isBuilt(launcher) && (
                  <div className="flex flex-col items-start gap-2.5 sm:items-center">
                    <a href={launcher.dmgUrl ?? launcher.downloadUrl} className={buttonPrimary}>
                      <Download size={17} aria-hidden />
                      Download{launcher.version ? ` ${launcher.version}` : ""}
                    </a>
                    {launcher.dmgUrl && (
                      <a
                        href={launcher.downloadUrl}
                        className={`rounded-sm text-sm text-muted underline decoration-line-strong underline-offset-4 hover:text-heading ${focusRing}`}
                      >
                        or as a .zip
                      </a>
                    )}
                  </div>
                )}
              </div>
            </PrintPanel>
          </section>
        )}

        {/* The collection */}
        <section id="apps" aria-labelledby="apps-title" className="scroll-mt-16 border-t border-line bg-card-2/50">
          <div className={`${container} py-20`}>
            <div className="flex flex-wrap items-end justify-between gap-4">
              <h2 id="apps-title" className={sectionTitle}>
                The collection
              </h2>
              <p className="text-sm text-muted">
                {builtCount > 0
                  ? `${builtCount} ready to download, ${apps.length - builtCount} on the way.`
                  : `${apps.length} apps on the way.`}
              </p>
            </div>

            {groups.map((group) => (
              <div key={group.priority} className="mt-14">
                <div className="flex flex-wrap items-baseline gap-x-3 gap-y-1 border-b border-line pb-3">
                  <h3 className="label text-heading">{group.title}</h3>
                  <p className="text-sm text-muted">{group.note}</p>
                </div>
                <ul className="mt-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
                  {group.apps.map((app) => (
                    <AppCard key={app.slug} app={app} />
                  ))}
                </ul>
              </div>
            ))}
          </div>
        </section>

        {/* Built in the open */}
        <section aria-labelledby="built" className="border-t border-line">
          <div className={`${container} grid gap-10 py-20 lg:grid-cols-[0.9fr_1.4fr] lg:gap-14`}>
            <div>
              <h2 id="built" className={sectionTitle}>
                Built in the open
              </h2>
              <p className="mt-4 max-w-md leading-relaxed text-muted">
                We study how the best Mac utilities work, then build our own, natively, in one public repository.
                Found a bug, or want an app that isn&apos;t here yet? Open an issue or send a pull request.
              </p>
              <a href={brand.repoUrl} className={`${buttonQuiet} mt-7`}>
                <GitHubMark className="size-4" />
                Contribute on GitHub
              </a>
            </div>
            <ol className="divide-y divide-line border-y border-line">
              {craft.map((item, i) => (
                <li key={item.title} className="grid grid-cols-[3rem_1fr] gap-x-4 py-6">
                  <span className="font-serif text-2xl text-muted tabular-nums">{String(i + 1).padStart(2, "0")}</span>
                  <div>
                    <h3 className="font-serif text-[1.375rem] font-medium text-heading">{item.title}</h3>
                    <p className="mt-1 leading-relaxed text-muted">{item.body}</p>
                  </div>
                </li>
              ))}
            </ol>
          </div>
        </section>

        {/* Colophon: where the prints come from */}
        <section aria-label="About the botanical plates" className={`${container} pb-20`}>
          <PrintPanel plate="awake" tile={nordic.rosewood} className="rounded-[2rem] p-3 sm:p-4" position="50% 35%">
            <div className="ml-auto max-w-md rounded-[1.5rem] bg-card p-6 sm:p-7">
              <p className="label text-muted">The plates</p>
              <p className="mt-2 font-serif text-[1.375rem] leading-snug text-heading">
                Every icon carries a plant from <i>Köhler&apos;s Medizinal-Pflanzen</i>, 1887–1898.
              </p>
              <p className="mt-2 text-sm leading-relaxed text-muted">
                Public-domain scans from the{" "}
                <a href="https://www.biodiversitylibrary.org/" className={`rounded text-link underline underline-offset-2 hover:text-heading ${focusRing}`}>
                  Biodiversity Heritage Library
                </a>
                , printed in a single tone.
              </p>
            </div>
          </PrintPanel>
        </section>
      </main>

      <footer className="border-t border-line">
        <div className={`${container} flex flex-col gap-4 py-8 text-sm text-muted sm:flex-row sm:items-center sm:justify-between`}>
          <div className="flex items-center gap-2 text-heading">
            <Mark className="size-5" />
            <span className="font-serif text-lg font-medium">{brand.name}</span>
            <span className="text-muted">· {brand.license} licensed</span>
          </div>
          <a href={brand.repoUrl} className={`rounded hover:text-heading ${focusRing}`}>
            Source on GitHub
          </a>
        </div>
      </footer>
    </>
  );
}
