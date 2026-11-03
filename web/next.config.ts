import type { NextConfig } from "next";

// Static export: `pnpm build` writes plain HTML/CSS/JS to `out/`, which any static
// host can serve. Set NEXT_BASE_PATH (e.g. "/slopapp") when hosting under a subpath,
// such as a GitHub Pages project site.
const basePath = process.env.NEXT_BASE_PATH || undefined;

const nextConfig: NextConfig = {
  output: "export",
  basePath,
  images: { unoptimized: true },
  turbopack: {
    rules: {
      "*.css": {
        loaders: ["@tailwindcss/turbopack"],
        as: "*.css",
      },
    },
  },
};

export default nextConfig;
