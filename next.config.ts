import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // Do not emit framework-generated AGENTS.md / CLAUDE.md files.
  agentRules: false,
};

export default nextConfig;
