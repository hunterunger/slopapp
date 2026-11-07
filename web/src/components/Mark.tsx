import { glyphPaths, glyphTransform } from "@/components/Logo";

/** One-color Slopapp mark (brand/mark-mono.svg): the launcher glyph, two stacked layers. */
export function Mark({ className = "size-7" }: { className?: string }) {
  return (
    <svg viewBox="200 200 1600 1600" aria-hidden className={className}>
      <g fill="currentColor" transform={glyphTransform}>
        <path d={glyphPaths.lower} />
        <path d={glyphPaths.upper} />
      </g>
    </svg>
  );
}
