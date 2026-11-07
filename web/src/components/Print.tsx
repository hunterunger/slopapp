import type { CSSProperties, ReactNode } from "react";
import { asset, specimenFor } from "@/lib/herbarium";

/**
 * A crisp panel with one botanical print inside it. The print is the plate used as a mask,
 * tinted 30% darker than the panel; anything placed on it should sit on its own flat surface.
 */
export function PrintPanel({
  plate,
  tile,
  className = "",
  position = "center",
  zoom,
  children,
}: {
  /** App slug whose plate to print. */
  plate: string;
  tile: string;
  className?: string;
  position?: string;
  /** Show a close-up instead of the whole plate: mask size as a multiple of the panel (e.g. 2.5). */
  zoom?: number;
  children?: ReactNode;
}) {
  const print = specimenFor(plate)?.print;
  const mask = print ? `url(${asset(print)})` : undefined;
  return (
    <div className={`panel ${className}`} style={{ "--tile": tile } as CSSProperties}>
      {mask && (
        <span
          aria-hidden
          className="print"
          style={{
            maskImage: mask,
            WebkitMaskImage: mask,
            maskPosition: position,
            WebkitMaskPosition: position,
            ...(zoom ? { maskSize: `${zoom * 100}%`, WebkitMaskSize: `${zoom * 100}%` } : {}),
          }}
        />
      )}
      {children}
    </div>
  );
}
