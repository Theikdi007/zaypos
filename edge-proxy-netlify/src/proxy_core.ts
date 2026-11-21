// ZayPOS edge proxy, Netlify version: route 1 to the API (docs/deploy/fallback-routes.md#plan-b-no-google-cloud-billing).
//
// Myanmar networks refuse the API server's IP but reach Netlify's edge. Every request is forwarded to ONE fixed upstream
// with two headers the API trusts only together (backend/src/ZayPOS.Api/Hosting/EdgeProxy.cs, from PR #20):
//
//   X-ZayPOS-Edge:      the shared secret (Netlify environment variable EDGE_PROXY_SECRET; never logged, never in git)
//   X-ZayPOS-Client-IP: the phone's address, from Netlify's context.ip (set by Netlify's edge, a client can't forge it)
//
// Same rules as the Go proxy in edge-proxy/main.go. Not an open proxy: scheme and host are fixed, only path, query,
// method, headers and body come from the request. No dependencies: runs on Netlify (Deno) and under `node --test`.

export const UPSTREAM = "https://api.zaypos.app";
export const MAX_BODY_BYTES = 32 * 1024 * 1024; // same cap as Caddy's request_body and the Go proxy
export const MIN_SECRET_LENGTH = 32; // same floor as the API (EdgeProxyOptions.MinSecretLength)
export const UPSTREAM_TIMEOUT_MS = 35_000; // Netlify gives an edge function 40 s to send response headers

const SECRET_HEADER = "x-zaypos-edge";
const CLIENT_IP_HEADER = "x-zaypos-client-ip";

// Hop-by-hop (RFC 9110 §7.6.1) plus headers only the proxy may set.
const HOP_BY_HOP = new Set([
  "connection", "keep-alive", "proxy-authenticate", "proxy-authorization", "proxy-connection",
  "te", "trailer", "transfer-encoding", "upgrade", "host", "content-length",
]);

/** Request headers a phone (or Netlify) sends that must not reach the API. */
function dropRequestHeader(name: string): boolean {
  return HOP_BY_HOP.has(name) ||
    name.startsWith("x-zaypos-") || // a client must never set the trusted headers
    name.startsWith("x-nf-") || // Netlify's own request metadata
    name.startsWith("x-forwarded-") || name === "forwarded" ||
    name === "x-real-ip" || name === "client-ip" || name === "true-client-ip" ||
    name === "x-country" || name === "x-language" || name === "traceparent" || name === "tracestate";
}

export interface ProxyOptions {
  /** EDGE_PROXY_SECRET; missing or short = refuse to forward (503), so shops never share one rate-limit bucket. */
  secret: string | undefined;
  /** Netlify's context.ip. */
  clientIp: string | undefined;
  fetch?: typeof fetch;
  log?: (line: string) => void;
}

export async function handle(request: Request, opts: ProxyOptions): Promise<Response> {
  const started = Date.now();
  const url = new URL(request.url);
  const log = opts.log ?? ((line: string) => console.log(line));

  if (url.pathname === "/_proxy/health") {
    return json(200, { status: "ok" });
  }
  const secret = opts.secret ?? "";
  if (secret.length < MIN_SECRET_LENGTH) {
    log(`config: EDGE_PROXY_SECRET missing or shorter than ${MIN_SECRET_LENGTH} chars`);
    return problem(503, "edge_not_configured");
  }

  const declared = request.headers.get("content-length");
  if (declared !== null && Number(declared) > MAX_BODY_BYTES) {
    return problem(413, "request_too_large");
  }

  const headers = new Headers();
  const named = connectionTokens(request.headers);
  request.headers.forEach((value, name) => {
    if (!dropRequestHeader(name) && !named.has(name)) headers.append(name, value);
  });
  headers.set(SECRET_HEADER, secret);
  const ip = (opts.clientIp ?? "").trim();
  if (isIp(ip)) headers.set(CLIENT_IP_HEADER, ip);

  // Concatenate, never resolve: a path like "//evil.example/x" stays a path on the upstream host.
  const target = UPSTREAM + url.pathname + url.search;

  const limit = { exceeded: false };
  const hasBody = request.body !== null && request.method !== "GET" && request.method !== "HEAD";
  const init: RequestInit & { duplex?: "half" } = {
    method: request.method,
    headers,
    redirect: "manual", // a 3xx from the API goes back to the phone as it is
    signal: AbortSignal.timeout(UPSTREAM_TIMEOUT_MS),
  };
  if (hasBody) {
    init.body = request.body!.pipeThrough(capBytes(MAX_BODY_BYTES, limit));
    init.duplex = "half";
  }

  let upstream: Response;
  try {
    upstream = await (opts.fetch ?? fetch)(target, init);
  } catch (err) {
    if (limit.exceeded) return problem(413, "request_too_large");
    log(`upstream error: ${request.method} ${url.pathname}: ${errorKind(err)}`);
    return problem(502, "edge_upstream_unavailable");
  }

  // fetch() has already decoded gzip/br, so the encoding and length headers no longer describe the body.
  const out = new Headers();
  const upstreamNamed = connectionTokens(upstream.headers);
  upstream.headers.forEach((value, name) => {
    if (!HOP_BY_HOP.has(name) && name !== "content-encoding" && !upstreamNamed.has(name)) out.append(name, value);
  });
  // Method, path, status, duration only: no query, no headers, no bodies, no tokens.
  log(`${request.method} ${url.pathname} ${upstream.status} ${Date.now() - started}ms`);
  return new Response(upstream.body, { status: upstream.status, statusText: upstream.statusText, headers: out });
}

function connectionTokens(h: Headers): Set<string> {
  return new Set((h.get("connection") ?? "").split(",").map((t) => t.trim().toLowerCase()).filter(Boolean));
}

/** Passes bytes through and errors the stream once more than `max` have gone by. */
function capBytes(max: number, state: { exceeded: boolean }): TransformStream<Uint8Array, Uint8Array> {
  let seen = 0;
  return new TransformStream({
    transform(chunk, controller) {
      seen += chunk.byteLength;
      if (seen > max) {
        state.exceeded = true;
        controller.error(new Error("request body over the cap"));
        return;
      }
      controller.enqueue(chunk);
    },
  });
}

const IPV4 = /^(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}$/;

/** IPv4 dotted quad, or IPv6 text (the API re-parses it with IPAddress.TryParse). */
export function isIp(s: string): boolean {
  if (IPV4.test(s)) return true;
  return s.length <= 45 && s.includes(":") && /^[0-9a-fA-F:.]+$/.test(s) && (s.match(/::/g) ?? []).length <= 1;
}

/** Short and free of anything request-specific (the Go proxy's errorKind). */
function errorKind(err: unknown): string {
  const name = err instanceof Error ? err.name : "";
  if (name === "TimeoutError") return "timeout";
  if (name === "AbortError") return "client went away";
  if (err instanceof TypeError) return "network";
  return "other";
}

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", "cache-control": "no-store" },
  });
}

function problem(status: number, code: string): Response {
  return new Response(JSON.stringify({ status, title: code, code }), {
    status,
    headers: { "content-type": "application/problem+json", "cache-control": "no-store" },
  });
}
