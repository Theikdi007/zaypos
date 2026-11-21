// Netlify Edge Function entry: every path goes through the proxy (logic and rules in src/proxy_core.ts).
import type { Config, Context } from "@netlify/edge-functions";

import { handle } from "../../src/proxy_core.ts";

declare const Netlify: { env: { get(name: string): string | undefined } };

export default (request: Request, context: Context) =>
  handle(request, { secret: Netlify.env.get("EDGE_PROXY_SECRET"), clientIp: context.ip });

// No `cache` key on purpose: without `cache: "manual"` Netlify never caches an edge function's response.
export const config: Config = { path: "/*" };
