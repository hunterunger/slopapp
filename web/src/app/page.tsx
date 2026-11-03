import { Check, Code, Gift, Lock, Minus, Package, ShieldCheck, Wrench } from "lucide-react";
import { AppCard } from "@/components/AppCard";
import { AppIcon } from "@/components/AppIcon";
import { GitHubMark } from "@/components/GitHubMark";
import { Logo } from "@/components/Logo";
import { Mark } from "@/components/Mark";
import { apps, brand, isBuilt, priorityGroups } from "@/lib/catalog";

const groups = priorityGroups
  .map((group) => ({ ...group, apps: apps.filter((app) => app.priority === group.priority) }))
  .filter((group) => group.apps.length > 0);
const heroApps = apps.filter((app) => app.priority < 3).slice(0, 8);
const builtCount = apps.filter(isBuilt).length;
// First sentence of the brand description; the promise strip covers the rest.
const oneLiner = brand.description.split(". ")[0].replace(/\.?$/, ".");

const promises = [
  {
    icon: Gift,
    title: "Free forever",
    body: "No trial, no subscription, no paid tier. Every app costs $0.",
  },
  {
    icon: Code,
    title: "Open source",
    body: `${brand.license}-licensed Swift code. Read it, fork it, fix it.`,
  },
  {
    icon: Lock,
    title: "Private",
    body: "No account, no analytics, no tracking. Your data stays on your Mac.",
  },
];

const buildNotes = [
  { icon: Package, title: "Native Swift", body: "SwiftUI and AppKit. Small, fast, and at home on macOS." },
  { icon: Wrench, title: "One design system", body: "Every app follows the same rules, so they feel like a set." },
  { icon: ShieldCheck, title: "Tested in CI", body: "Every app is built and tested on every change." },
];

const comparison = [
  { label: "Price", setapp: "Monthly subscription (from $9.99)", slopapp: "$0" },
  { label: "Account", setapp: "Required", slopapp: "None" },
  { label: "Source code", setapp: "Closed", slopapp: `Open, ${brand.license} licensed` },
  { label: "Apps", setapp: "270+ curated apps", slopapp: "A growing set of everyday utilities" },
];

const buttonBase =
  "inline-flex items-center justify-center gap-2 rounded-full px-5 py-3 text-sm font-semibold transition focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-leaf";

export default function Home() {
  return (
    <>
      <header className="mx-auto flex max-w-6xl items-center justify-between px-6 py-5">
        <a href="#top" className="flex items-center gap-2.5 rounded-lg" aria-label={`${brand.name} home`}>
          <Logo className="size-8" />
          <span className="font-display text-xl font-semibold text-heading">{brand.name}</span>
        </a>
        <nav className="flex items-center gap-1 text-sm">
          <a href="#apps" className="hidden rounded-full px-3 py-2 text-muted hover:text-heading sm:inline">
            Apps
          </a>
          <a
            href={brand.repoUrl}
            className="inline-flex items-center gap-2 rounded-full px-3 py-2 text-muted hover:text-heading"
          >
            <GitHubMark className="size-5" />
            <span className="hidden sm:inline">GitHub</span>
            <span className="sr-only sm:hidden">GitHub</span>
          </a>
        </nav>
      </header>

      <main id="top">
        {/* Hero */}
        <section className="mx-auto grid max-w-6xl items-center gap-12 px-6 pb-20 pt-10 md:grid-cols-[1.15fr_1fr] md:pt-16">
          <div>
            <h1 className="font-display text-5xl font-bold leading-[1.02] tracking-tight text-heading sm:text-6xl">
              {brand.tagline}
            </h1>
            <p className="mt-6 max-w-xl text-lg leading-relaxed text-muted">
              {oneLiner} Like Setapp, minus the subscription.
            </p>
            <div className="mt-8 flex flex-wrap gap-3">
              <a href="#apps" className={`${buttonBase} bg-forest text-cream hover:bg-forest/90 dark:bg-leaf dark:text-forest dark:hover:bg-leaf/90`}>
                Browse the apps
              </a>
              <a
                href={brand.repoUrl}
                className={`${buttonBase} border border-line bg-card text-heading hover:border-forest/40`}
              >
                <GitHubMark className="size-4" />
                View on GitHub
              </a>
            </div>
          </div>

          <div className="relative mx-auto w-full max-w-sm" aria-hidden>
            <div className="absolute inset-6 -z-10 rounded-full bg-mint blur-3xl dark:bg-leaf/10" />
            <div className="grid grid-cols-4 gap-4">
              {heroApps.map((app, i) => (
                <div key={app.slug} className={i % 2 ? "translate-y-4" : ""}>
                  <AppIcon name={app.icon} size={72} />
                </div>
              ))}
            </div>
          </div>
        </section>

        {/* Promise */}
        <section aria-label="Our promise" className="border-y border-line bg-card/60">
          <ul className="mx-auto grid max-w-6xl gap-8 px-6 py-12 sm:grid-cols-3">
            {promises.map(({ icon: Icon, title, body }) => (
              <li key={title} className="flex gap-4">
                <span className="flex size-10 shrink-0 items-center justify-center rounded-xl bg-mint text-forest">
                  <Icon size={20} aria-hidden />
                </span>
                <div>
                  <h2 className="font-display text-lg font-semibold text-heading">{title}</h2>
                  <p className="mt-1 text-sm leading-relaxed text-muted">{body}</p>
                </div>
              </li>
            ))}
          </ul>
        </section>

        {/* Collection */}
        <section id="apps" className="mx-auto max-w-6xl scroll-mt-6 px-6 py-20">
          <div className="flex flex-wrap items-end justify-between gap-4">
            <h2 className="font-display text-4xl font-bold tracking-tight text-heading">The collection</h2>
            <p className="text-sm text-muted">
              {builtCount > 0
                ? `${builtCount} ready to download, ${apps.length - builtCount} on the way.`
                : `${apps.length} apps on the way.`}
            </p>
          </div>

          {groups.map((group) => (
            <div key={group.priority} className="mt-10">
              <div className="flex flex-wrap items-baseline gap-x-3 gap-y-1">
                <h3 className="text-sm font-semibold uppercase tracking-wider text-heading">{group.title}</h3>
                <p className="text-sm text-muted">{group.note}</p>
              </div>
              <ul className="mt-4 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
                {group.apps.map((app) => (
                  <AppCard key={app.slug} app={app} />
                ))}
              </ul>
            </div>
          ))}
        </section>

        {/* Comparison */}
        <section aria-labelledby="compare" className="bg-forest text-cream">
          <div className="mx-auto max-w-6xl px-6 py-20">
            <h2 id="compare" className="font-display text-4xl font-bold tracking-tight">
              Same idea. No bill.
            </h2>
            <div className="mt-10 overflow-x-auto">
              <table className="w-full min-w-[32rem] text-left text-sm">
                <thead>
                  <tr className="border-b border-cream/15">
                    <th scope="col" className="py-3 pr-4 font-normal text-cream/60">
                      <span className="sr-only">Feature</span>
                    </th>
                    <th scope="col" className="py-3 pr-4 font-semibold text-cream/70">
                      Setapp
                    </th>
                    <th scope="col" className="py-3 font-display text-base font-semibold text-leaf">
                      {brand.name}
                    </th>
                  </tr>
                </thead>
                <tbody>
                  {comparison.map((row) => (
                    <tr key={row.label} className="border-b border-cream/10 last:border-0">
                      <th scope="row" className="py-4 pr-4 font-medium text-cream/60">
                        {row.label}
                      </th>
                      <td className="py-4 pr-4 text-cream/80">
                        <span className="inline-flex items-center gap-2">
                          <Minus size={16} aria-hidden className="text-cream/40" />
                          {row.setapp}
                        </span>
                      </td>
                      <td className="py-4 font-medium">
                        <span className="inline-flex items-center gap-2">
                          <Check size={16} aria-hidden className="text-leaf" />
                          {row.slopapp}
                        </span>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        </section>

        {/* How it's built */}
        <section aria-labelledby="built" className="mx-auto max-w-6xl px-6 py-20">
          <div className="grid gap-12 md:grid-cols-[1fr_1.4fr]">
            <div>
              <h2 id="built" className="font-display text-4xl font-bold tracking-tight text-heading">
                Careful, despite the name
              </h2>
              <p className="mt-4 leading-relaxed text-muted">
                We study how the best Mac utilities work, then build our own, natively, in one public
                repo. Spot a bug or want an app that isn&apos;t here yet? Open an issue or send a pull
                request.
              </p>
              <a
                href={brand.repoUrl}
                className={`${buttonBase} mt-6 bg-forest text-cream hover:bg-forest/90 dark:bg-leaf dark:text-forest`}
              >
                <GitHubMark className="size-4" />
                Contribute on GitHub
              </a>
            </div>
            <ul className="grid gap-6 sm:grid-cols-3 md:grid-cols-1 lg:grid-cols-3">
              {buildNotes.map(({ icon: Icon, title, body }) => (
                <li key={title} className="rounded-2xl border border-line bg-card p-5">
                  <Icon size={22} aria-hidden className="text-leaf" />
                  <h3 className="mt-3 font-display text-lg font-semibold text-heading">{title}</h3>
                  <p className="mt-1 text-sm leading-relaxed text-muted">{body}</p>
                </li>
              ))}
            </ul>
          </div>
        </section>
      </main>

      <footer className="border-t border-line">
        <div className="mx-auto flex max-w-6xl flex-col gap-4 px-6 py-8 text-sm text-muted sm:flex-row sm:items-center sm:justify-between">
          <div className="flex items-center gap-2 text-heading">
            <Mark className="size-5" />
            <span className="font-display font-semibold">{brand.name}</span>
            <span className="text-muted">· {brand.license} licensed</span>
          </div>
          <div className="flex flex-col gap-1 sm:items-end">
            <a href={brand.repoUrl} className="hover:text-heading">
              Source on GitHub
            </a>
            <span className="text-xs">Not affiliated with Setapp or MacPaw.</span>
          </div>
        </div>
      </footer>
    </>
  );
}
