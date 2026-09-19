import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // The talent pages read their data files from disk, so make sure they're deployed
  outputFileTracingIncludes: {
    "/*": ["./lib/talent-data/**/*"],
  },
};

export default nextConfig;