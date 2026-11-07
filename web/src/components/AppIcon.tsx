import {
  AppWindow,
  AudioLines,
  Braces,
  BrushCleaning,
  Calculator,
  Calendar,
  Camera,
  ChartColumn,
  ClipboardList,
  Coffee,
  Copy,
  FilePenLine,
  FolderTree,
  Gauge,
  GitBranch,
  Globe,
  Inbox,
  LayoutGrid,
  Package,
  PanelRight,
  PanelTopClose,
  Pipette,
  Pointer,
  RefreshCw,
  Route,
  Ruler,
  ScanText,
  Shapes,
  Search,
  Shrink,
  SquareX,
  TextCursorInput,
  Timer,
  ToggleRight,
  Type,
  type LucideIcon,
} from "lucide-react";
import { asset, specimenFor } from "@/lib/herbarium";

// Explicit map keeps the static export small and avoids client-side icon loading.
// Add an entry here when a new app uses a new Lucide icon.
const icons: Record<string, LucideIcon> = {
  "app-window": AppWindow,
  "audio-lines": AudioLines,
  braces: Braces,
  "brush-cleaning": BrushCleaning,
  calculator: Calculator,
  calendar: Calendar,
  camera: Camera,
  "chart-column": ChartColumn,
  "clipboard-list": ClipboardList,
  coffee: Coffee,
  copy: Copy,
  "file-pen-line": FilePenLine,
  "folder-tree": FolderTree,
  gauge: Gauge,
  "git-branch": GitBranch,
  globe: Globe,
  inbox: Inbox,
  "layout-grid": LayoutGrid,
  package: Package,
  "panel-right": PanelRight,
  "panel-top-close": PanelTopClose,
  pipette: Pipette,
  pointer: Pointer,
  "refresh-cw": RefreshCw,
  route: Route,
  ruler: Ruler,
  "scan-text": ScanText,
  shapes: Shapes,
  search: Search,
  shrink: Shrink,
  "square-x": SquareX,
  "text-cursor-input": TextCursorInput,
  timer: Timer,
  "toggle-right": ToggleRight,
  type: Type,
};

/**
 * The app's herbarium icon (brand/ICONS.md), light and dark renditions. Apps without one yet get an
 * empty specimen slot: a dashed outline with the app's Lucide glyph, waiting to be drawn.
 */
export function AppIcon({
  slug,
  name,
  size = 56,
  eager = false,
}: {
  slug: string;
  name: string;
  size?: number;
  eager?: boolean;
}) {
  const specimen = specimenFor(slug);
  if (specimen) {
    return (
      <picture className="inline-flex shrink-0" style={{ width: size, height: size }}>
        <source srcSet={asset(specimen.iconDark)} media="(prefers-color-scheme: dark)" />
        <img src={asset(specimen.icon)} alt="" width={size} height={size} loading={eager ? "eager" : "lazy"} decoding="async" />
      </picture>
    );
  }
  const Glyph = icons[name] ?? LayoutGrid;
  return (
    <span
      aria-hidden
      className="inline-flex shrink-0 items-center justify-center border border-dashed border-line-strong bg-slot text-muted"
      style={{ width: size, height: size, borderRadius: size * 0.225 }}
    >
      <Glyph size={size * 0.42} strokeWidth={1.5} />
    </span>
  );
}
