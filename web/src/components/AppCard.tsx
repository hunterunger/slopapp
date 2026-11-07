import { Download } from "lucide-react";
import { AppIcon } from "@/components/AppIcon";
import { isBuilt, type CatalogApp } from "@/lib/catalog";
import { specimenFor } from "@/lib/herbarium";

const list = new Intl.ListFormat("en", { type: "conjunction" });

const statusLabel: Record<CatalogApp["status"], string | null> = {
  planned: "Coming soon",
  alpha: "Alpha",
  beta: "Beta",
  stable: null,
};

export const focusRing = "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus";

/** One app as a specimen sheet: icon, name, one line, and its herbarium tag. */
export function AppCard({ app }: { app: CatalogApp }) {
  const built = isBuilt(app);
  const label = statusLabel[app.status];
  const specimen = specimenFor(app.slug);

  return (
    <li className="flex flex-col rounded-[1.25rem] border border-line bg-card p-5 transition-[border-color,box-shadow] hover:border-line-strong hover:shadow-[0_12px_32px_-20px_rgb(47_45_42/0.35)]">
      <div className="flex items-start gap-4">
        <AppIcon slug={app.slug} name={app.icon} size={64} />
        <div className="min-w-0 flex-1 pt-0.5">
          <div className="flex flex-wrap items-center gap-x-2 gap-y-1">
            <h3 className="font-serif text-[1.375rem] font-medium leading-tight text-heading">{app.name}</h3>
            {label && (
              <span
                className={
                  built
                    ? "rounded-full border border-line-strong px-2 py-px text-xs font-medium text-text"
                    : "rounded-full bg-card-2 px-2 py-px text-xs font-medium text-muted"
                }
              >
                {label}
              </span>
            )}
          </div>
          <p className="mt-1 text-[0.9375rem] leading-relaxed text-text">{app.tagline}</p>
        </div>
      </div>

      <div className="mt-auto pt-5">
        <div className="border-t border-line pt-3.5">
          {specimen ? (
            <p className="truncate text-muted" title={`${specimen.plant}, ${specimen.common}`}>
              <span className="font-serif text-[0.9375rem] italic text-text">{specimen.plant}</span>
              {specimen.plate && <span className="label ml-2 align-[1px] whitespace-nowrap">Pl. {specimen.plate}</span>}
            </p>
          ) : (
            <p className="label py-[3px] text-muted">{app.category}</p>
          )}
          <div className="mt-2 flex min-h-8 items-center justify-between gap-3">
            <p className="min-w-0 text-xs leading-relaxed text-muted">
              {app.replaces.length > 0 && <>An alternative to {list.format(app.replaces)}</>}
            </p>
            {built && (
              <a
                href={app.downloadUrl}
                className={`inline-flex shrink-0 items-center gap-1.5 whitespace-nowrap rounded-full bg-action px-3.5 py-1.5 text-sm font-semibold text-on-action transition-colors hover:bg-action-hover ${focusRing}`}
              >
                <Download size={15} aria-hidden />
                Download{app.version ? ` ${app.version}` : ""}
                <span className="sr-only"> {app.name}</span>
              </a>
            )}
          </div>
        </div>
      </div>
    </li>
  );
}
