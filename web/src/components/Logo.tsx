import { useId } from "react";

/** Full-color Slopapp tile (brand/logo.svg): a tidy grid of apps with slop poured over the top. */
export function Logo({ className = "size-8" }: { className?: string }) {
  const clip = useId();
  return (
    <svg viewBox="0 0 512 512" aria-hidden className={className}>
      <defs>
        <clipPath id={clip}>
          <rect width="512" height="512" rx="115" />
        </clipPath>
      </defs>
      <g clipPath={`url(#${clip})`}>
        <rect width="512" height="512" fill="#0F3D2E" />
        <g fill="#FAF6EC">
          <rect x="128" y="186" width="112" height="112" rx="30" />
          <rect x="272" y="186" width="112" height="112" rx="30" />
          <rect x="128" y="330" width="112" height="112" rx="30" />
          <rect x="272" y="330" width="112" height="112" rx="30" />
        </g>
        <path
          fill="#3DBE74"
          transform="translate(0 -22)"
          d="M0 0H512V128C512 150 496 160 478 152C458 143 446 156 444 176V214A18 18 0 0 1 408 214V184C408 166 392 160 376 168C354 179 340 172 326 160C310 146 290 150 288 172V262A20 20 0 0 1 248 262V190C248 170 232 162 214 170C196 178 186 176 176 166C166 156 152 158 150 176V196A14 14 0 0 1 122 196V170C120 152 104 146 88 154C64 166 40 166 24 154C12 145 0 146 0 160Z"
        />
      </g>
    </svg>
  );
}
