const lower =
  "M1601.142,1489.151C1563.427,1571.294 1480.418,1628.397 1384.177,1628.397L906.968,1628.397C775.279,1628.397 668.364,1521.482 668.364,1389.792L668.364,912.583C668.364,816.343 725.466,733.334 807.61,695.618C793.718,725.874 785.971,759.528 785.971,794.976C702.29,994.769 730.068,1143.188 785.971,1272.185C785.971,1403.875 892.886,1510.79 1024.575,1510.79C1149.397,1588.848 1315.126,1596.706 1501.784,1510.79C1537.233,1510.79 1570.886,1503.043 1601.142,1489.151Z";
const upper =
  "M1867.775,667.589L1867.775,1144.798C1867.775,1276.488 1760.86,1383.403 1629.171,1383.403L1151.962,1383.403C1020.273,1383.403 913.358,1276.488 913.358,1144.798L913.358,667.589C913.358,535.9 1020.273,428.985 1151.962,428.985L1629.171,428.985C1760.86,428.985 1867.775,535.9 1867.775,667.589Z";
/** The glyph's own skew (the owner's mark; also in apps/Slopapp/Icon.py). */
export const glyphTransform = "matrix(.958822 -.606118 .958822 .606118 -1202.183393 1145.091684)";
export const glyphPaths = { lower, upper };

/** Full-color Slopapp tile (brand/logo.svg): a birch sheet over an ochre one on moss, flat (the launcher icon without its print). */
export function Logo({ className = "size-8" }: { className?: string }) {
  const place = "translate(256 256) scale(.2458) translate(-1000 -1000)";
  return (
    <svg viewBox="0 0 512 512" aria-hidden className={className}>
      <rect width="512" height="512" rx="115" fill="#6B7A45" />
      <g transform={place}>
        <g transform={glyphTransform}>
          <path fill="#E0B054" d={lower} />
          <path fill="#F5F0E8" d={upper} />
        </g>
      </g>
    </svg>
  );
}
