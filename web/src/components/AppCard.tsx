import { Download } from "lucide-react";
import { AppIcon } from "@/components/AppIcon";
import { isBuilt, type CatalogApp } from "@/lib/catalog";

const list = new Intl.ListFormat("en", { type: "conjunction" });

const statusLabel: Record<CatalogApp["status"], string | null> = {
  planned: "Coming soon",
  alpha: "Alpha",
  beta: "Beta",
  stable: null,
};

export function AppCard({ app }: { app: CatalogApp }) {
  const built = isBuilt(app);
  const label = statusLabel[app.status];

  return (
    <li className="flex flex-col gap-4 rounded-2xl border border-line bg-card p-5 transition-shadow hover:shadow-md">
      <div className="flex items-start gap-4">
        <AppIcon name={app.icon} size={52} />
        <div className="min-w-0 flex-1">
          <div className="flex flex-wrap items-center gap-2">
            <h3 className="font-display text-lg font-semibold text-heading">{app.name}</h3>
            {label && (
              <span
                className={
                  built
                    ? "rounded-full bg-ember/15 px-2 py-0.5 text-xs font-medium text-ember"
                    : "rounded-full bg-mint px-2 py-0.5 text-xs font-medium text-forest"
                }
              >
                {label}
              </span>
            )}
          </div>
          <p className="mt-1 text-sm leading-relaxed text-text">{app.tagline}</p>
        </div>
      </div>

      <div className="mt-auto flex items-center justify-between gap-3 text-xs text-muted">
        {app.replaces.length > 0 && <span>An alternative to {list.format(app.replaces)}</span>}
        {built && (
          <a
            href={app.downloadUrl}
            className="ml-auto inline-flex shrink-0 items-center gap-1.5 whitespace-nowrap rounded-full bg-leaf px-3 py-1.5 text-sm font-medium text-forest hover:brightness-105 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-leaf"
          >
            <Download size={15} aria-hidden />
            Download{app.version ? ` ${app.version}` : ""}
          </a>
        )}
      </div>
    </li>
  );
}
