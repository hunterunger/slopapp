import {
  AppWindow,
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
  Pipette,
  RefreshCw,
  Route,
  Ruler,
  ScanText,
  Search,
  Shrink,
  SquareX,
  Timer,
  ToggleRight,
  Type,
  type LucideIcon,
} from "lucide-react";

// Explicit map keeps the static export small and avoids client-side icon loading.
// Add an entry here when a new app uses a new Lucide icon.
const icons: Record<string, LucideIcon> = {
  "app-window": AppWindow,
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
  pipette: Pipette,
  "refresh-cw": RefreshCw,
  route: Route,
  ruler: Ruler,
  "scan-text": ScanText,
  search: Search,
  shrink: Shrink,
  "square-x": SquareX,
  timer: Timer,
  "toggle-right": ToggleRight,
  type: Type,
};

/** Forest rounded-square tile with a cream glyph, matching the generated macOS app icons. */
export function AppIcon({ name, size = 56 }: { name: string; size?: number }) {
  const Glyph = icons[name] ?? LayoutGrid;
  return (
    <span
      aria-hidden
      className="inline-flex shrink-0 items-center justify-center bg-forest text-cream shadow-sm ring-1 ring-black/5 dark:ring-cream/15"
      style={{ width: size, height: size, borderRadius: size * 0.225 }}
    >
      <Glyph size={size * 0.5} strokeWidth={2} />
    </span>
  );
}
