import { Download } from "lucide-react";
import { AppIcon } from "@/components/AppIcon";
import { flavourFor, isBuilt, type CatalogApp, type Flavour } from "@/lib/catalog";

const list = new Intl.ListFormat("en", { type: "conjunction" });

const statusLabel: Record<CatalogApp["status"], string | null> = {
  planned: "Coming soon",
  alpha: "Alpha",
  beta: "Beta",
  stable: null,
};

// The one flavour accent a card gets: the dot beside its category.
const dot: Record<Flavour, string> = {
  strawberry: "bg-strawberry",
  tangerine: "bg-tangerine",
  lime: "bg-lime",
  lagoon: "bg-lagoon",
  blueberry: "bg-blueberry",
  grape: "bg-grape",
};

export function AppCard({ app }: { app: CatalogApp }) {
  const built = isBuilt(app);
  const label = statusLabel[app.status];

  return (
    <li className="flex flex-col gap-4 rounded-2xl border border-line bg-surface p-5 transition-[border-color,box-shadow] hover:border-line-strong hover:shadow-[0_8px_24px_-12px_rgb(28_31_36/0.18)]">
      <div className="flex items-start gap-4">
        <AppIcon name={app.icon} size={52} />
        <div className="min-w-0 flex-1">
          <div className="flex flex-wrap items-center gap-x-2 gap-y-1">
            <h3 className="font-display text-lg font-semibold text-heading">{app.name}</h3>
            {label && (
              <span
                className={
                  built
                    ? "rounded-full border border-line-strong px-2 py-px text-xs font-medium text-heading"
                    : "rounded-full bg-surface-2 px-2 py-px text-xs font-medium text-muted"
                }
              >
                {label}
              </span>
            )}
          </div>
          <p className="mt-1 text-sm leading-relaxed text-text">{app.tagline}</p>
        </div>
      </div>

      <div className="mt-auto flex items-end justify-between gap-3 text-xs text-muted">
        <div className="flex min-w-0 flex-col gap-1">
          <span className="inline-flex items-center gap-1.5 font-medium text-text">
            <span aria-hidden className={`size-2 shrink-0 rounded-full ${dot[flavourFor(app.category)]}`} />
            {app.category}
          </span>
          {app.replaces.length > 0 && <span>An alternative to {list.format(app.replaces)}</span>}
        </div>
        {built && (
          <a
            href={app.downloadUrl}
            className="inline-flex shrink-0 items-center gap-1.5 whitespace-nowrap rounded-full bg-surface-2 px-3 py-1.5 text-sm font-semibold text-heading transition-colors hover:bg-line-strong focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-blueberry"
          >
            <Download size={15} aria-hidden />
            Download{app.version ? ` ${app.version}` : ""}
          </a>
        )}
      </div>
    </li>
  );
}
