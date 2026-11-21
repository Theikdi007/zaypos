// node --test test/   (Node >= 23.6 runs .ts directly; no dependencies)
import assert from "node:assert/strict";
import { test } from "node:test";

import { handle, isIp, MAX_BODY_BYTES, UPSTREAM } from "../src/proxy_core.ts";

const SECRET = "s".repeat(44);

type Seen = { url: string; method: string; headers: Headers; body: string | null };

function fakeUpstream(respond: (seen: Seen) => Response = () => new Response("ok", { status: 200 })) {
  const calls: Seen[] = [];
  const fetchImpl = (async (input: string, init: RequestInit) => {
    const body = init.body ? await new Response(init.body as ReadableStream).text() : null;
    const seen = { url: input, method: init.method!, headers: new Headers(init.headers), body };
    calls.push(seen);
    return respond(seen);
  }) as unknown as typeof fetch;
  return { calls, fetchImpl };
}

const quiet = () => {};

test("forwards method, path, query, body and Authorization to the fixed upstream", async () => {
  const up = fakeUpstream(() => new Response('{"a":1}', { status: 201, headers: { "content-type": "application/json", "x-request-id": "r1" } }));
  const res = await handle(
    new Request("https://zaypos-edge.netlify.app/api/v1/sync/push?x=1&y=2", {
      method: "POST",
      headers: { authorization: "Bearer t", "content-type": "application/json" },
      body: '{"units":[]}',
    }),
    { secret: SECRET, clientIp: "203.0.113.7", fetch: up.fetchImpl, log: quiet },
  );
  assert.equal(up.calls.length, 1);
  const c = up.calls[0];
  assert.equal(c.url, `${UPSTREAM}/api/v1/sync/push?x=1&y=2`);
  assert.equal(c.method, "POST");
  assert.equal(c.body, '{"units":[]}');
  assert.equal(c.headers.get("authorization"), "Bearer t");
  assert.equal(c.headers.get("content-type"), "application/json");
  assert.equal(c.headers.get("x-zaypos-edge"), SECRET);
  assert.equal(c.headers.get("x-zaypos-client-ip"), "203.0.113.7");
  assert.equal(res.status, 201);
  assert.equal(res.headers.get("x-request-id"), "r1");
  assert.equal(await res.text(), '{"a":1}');
});

test("all methods pass, and 4xx/5xx/3xx from the API come back unchanged", async () => {
  for (const [method, status] of [["GET", 404], ["PUT", 409], ["PATCH", 500], ["DELETE", 204], ["GET", 302]] as const) {
    const up = fakeUpstream(() => new Response(status === 204 ? null : "x", { status, headers: status === 302 ? { location: "/elsewhere" } : {} }));
    const res = await handle(new Request("https://e.netlify.app/api/v1/devices/1", { method }), {
      secret: SECRET, clientIp: "203.0.113.7", fetch: up.fetchImpl, log: quiet,
    });
    assert.equal(up.calls[0].method, method);
    assert.equal(res.status, status);
    if (status === 302) assert.equal(res.headers.get("location"), "/elsewhere");
  }
});

test("a client cannot set the edge headers, forwarded headers or Netlify's headers", async () => {
  const up = fakeUpstream();
  await handle(
    new Request("https://e.netlify.app/health", {
      headers: {
        "X-ZayPOS-Edge": "guess", "X-ZayPOS-Client-IP": "1.2.3.4", "x-zaypos-anything": "x",
        "X-Forwarded-For": "1.2.3.4", Forwarded: "for=1.2.3.4", "X-Real-IP": "1.2.3.4", "True-Client-IP": "1.2.3.4",
        "x-nf-client-connection-ip": "1.2.3.4", "x-nf-request-id": "n", "x-country": "MM", traceparent: "00-a-b-01",
        Connection: "x-secret-hop", "x-secret-hop": "drop me", "keep-alive": "timeout=5",
      },
    }),
    { secret: SECRET, clientIp: "203.0.113.7", fetch: up.fetchImpl, log: quiet },
  );
  const h = up.calls[0].headers;
  assert.equal(h.get("x-zaypos-edge"), SECRET);
  assert.equal(h.get("x-zaypos-client-ip"), "203.0.113.7");
  for (const name of ["x-zaypos-anything", "x-forwarded-for", "forwarded", "x-real-ip", "true-client-ip",
    "x-nf-client-connection-ip", "x-nf-request-id", "x-country", "traceparent", "connection", "x-secret-hop", "keep-alive"]) {
    assert.equal(h.get(name), null, name);
  }
});

test("without a usable context.ip no client IP is sent", async () => {
  for (const ip of [undefined, "", "not-an-ip", "1.2.3", "999.1.1.1", "1.2.3.4, 5.6.7.8"]) {
    const up = fakeUpstream();
    await handle(new Request("https://e.netlify.app/health"), { secret: SECRET, clientIp: ip, fetch: up.fetchImpl, log: quiet });
    assert.equal(up.calls[0].headers.get("x-zaypos-client-ip"), null, String(ip));
  }
  const up = fakeUpstream();
  await handle(new Request("https://e.netlify.app/health"), { secret: SECRET, clientIp: "2001:db8::7", fetch: up.fetchImpl, log: quiet });
  assert.equal(up.calls[0].headers.get("x-zaypos-client-ip"), "2001:db8::7");
});

test("a path that looks like a URL stays on the upstream host", async () => {
  const up = fakeUpstream();
  await handle(new Request("https://e.netlify.app//evil.example/x"), { secret: SECRET, clientIp: "203.0.113.7", fetch: up.fetchImpl, log: quiet });
  assert.ok(up.calls[0].url.startsWith(`${UPSTREAM}/`));
  assert.equal(new URL(up.calls[0].url).host, new URL(UPSTREAM).host);
});

test("own health answers without calling the upstream, even without a secret", async () => {
  const up = fakeUpstream();
  const res = await handle(new Request("https://e.netlify.app/_proxy/health"), { secret: undefined, clientIp: "203.0.113.7", fetch: up.fetchImpl, log: quiet });
  assert.equal(res.status, 200);
  assert.deepEqual(await res.json(), { status: "ok" });
  assert.equal(res.headers.get("cache-control"), "no-store");
  assert.equal(up.calls.length, 0);
});

test("a missing or short secret refuses to forward (503), so shops never share one rate-limit bucket", async () => {
  for (const secret of [undefined, "", "short"]) {
    const up = fakeUpstream();
    const logs: string[] = [];
    const res = await handle(new Request("https://e.netlify.app/health"), { secret, clientIp: "203.0.113.7", fetch: up.fetchImpl, log: (l) => logs.push(l) });
    assert.equal(res.status, 503);
    assert.equal((await res.json()).code, "edge_not_configured");
    assert.equal(up.calls.length, 0);
  }
});

test("a secret stored with surrounding whitespace or a trailing newline is sent trimmed", async () => {
  const up = fakeUpstream();
  await handle(new Request("https://e.netlify.app/health"), { secret: `${SECRET}\n`, clientIp: "203.0.113.7", fetch: up.fetchImpl, log: quiet });
  assert.equal(up.calls[0].headers.get("x-zaypos-edge"), SECRET);
  const short = fakeUpstream();
  const res = await handle(new Request("https://e.netlify.app/health"), { secret: `  ${"s".repeat(31)}\n`, clientIp: "203.0.113.7", fetch: short.fetchImpl, log: quiet });
  assert.equal(res.status, 503, "whitespace does not count towards the 32-char minimum");
});

test("upstream down gives 502 without details, and the log has no secret, token or query", async () => {
  const logs: string[] = [];
  const failing = (async () => { throw new TypeError("connect ECONNREFUSED 45.32.1.2:443"); }) as unknown as typeof fetch;
  const res = await handle(
    new Request("https://e.netlify.app/api/v1/sync/pull?cursor=abc", { headers: { authorization: "Bearer tok" } }),
    { secret: SECRET, clientIp: "203.0.113.7", fetch: failing, log: (l) => logs.push(l) },
  );
  assert.equal(res.status, 502);
  const body = await res.text();
  assert.deepEqual(JSON.parse(body), { status: 502, title: "edge_upstream_unavailable", code: "edge_upstream_unavailable" });
  assert.ok(!body.includes("45.32"));
  const all = logs.join("\n");
  assert.ok(all.includes("upstream error: GET /api/v1/sync/pull: network"));
  for (const leak of [SECRET, "tok", "cursor", "45.32"]) assert.ok(!all.includes(leak), leak);
});

test("a normal request logs only method, path, status and duration", async () => {
  const logs: string[] = [];
  const up = fakeUpstream();
  await handle(new Request("https://e.netlify.app/api/v1/sync/pull?cursor=abc", { headers: { authorization: "Bearer tok" } }),
    { secret: SECRET, clientIp: "203.0.113.7", fetch: up.fetchImpl, log: (l) => logs.push(l) });
  assert.equal(logs.length, 1);
  assert.match(logs[0], /^GET \/api\/v1\/sync\/pull 200 \d+ms$/);
});

test("bodies over 32 MB are refused: by Content-Length at once, and by counting when streamed", async () => {
  const up = fakeUpstream();
  const declared = await handle(
    new Request("https://e.netlify.app/api/v1/sync/push", { method: "POST", headers: { "content-length": String(MAX_BODY_BYTES + 1) }, body: "x" }),
    { secret: SECRET, clientIp: "203.0.113.7", fetch: up.fetchImpl, log: quiet },
  );
  assert.equal(declared.status, 413);
  assert.equal(up.calls.length, 0);

  const chunk = new Uint8Array(1024 * 1024);
  let sent = 0;
  const stream = new ReadableStream<Uint8Array>({
    pull(c) { if (sent > MAX_BODY_BYTES) c.close(); else { sent += chunk.byteLength; c.enqueue(chunk); } },
  });
  const streamed = await handle(
    new Request("https://e.netlify.app/api/v1/sync/push", { method: "POST", body: stream, duplex: "half" } as RequestInit),
    { secret: SECRET, clientIp: "203.0.113.7", fetch: up.fetchImpl, log: quiet },
  );
  assert.equal(streamed.status, 413);
  assert.equal((await streamed.json()).code, "request_too_large");
});

test("a body at the cap still passes", async () => {
  const up = fakeUpstream();
  const res = await handle(
    new Request("https://e.netlify.app/api/v1/sync/push", { method: "POST", body: "y".repeat(1024) }),
    { secret: SECRET, clientIp: "203.0.113.7", fetch: up.fetchImpl, log: quiet },
  );
  assert.equal(res.status, 200);
  assert.equal(up.calls[0].body!.length, 1024);
});

test("decoded responses lose content-encoding/length; hop-by-hop response headers are dropped", async () => {
  const up = fakeUpstream(() => new Response("plain", {
    headers: { "content-encoding": "gzip", "content-type": "text/plain", connection: "x-up-hop", "x-up-hop": "1", "transfer-encoding": "chunked", "set-cookie": "a=1" },
  }));
  const res = await handle(new Request("https://e.netlify.app/health"), { secret: SECRET, clientIp: "203.0.113.7", fetch: up.fetchImpl, log: quiet });
  assert.equal(res.headers.get("content-encoding"), null);
  assert.equal(res.headers.get("x-up-hop"), null);
  assert.equal(res.headers.get("transfer-encoding"), null);
  assert.equal(res.headers.get("content-type"), "text/plain");
  assert.equal(res.headers.get("set-cookie"), "a=1");
});

test("the upstream is a bare https host", () => {
  const u = new URL(UPSTREAM);
  assert.equal(u.protocol, "https:");
  assert.equal(u.pathname, "/");
  assert.equal(u.search, "");
  assert.equal(UPSTREAM.endsWith("/"), false);
});

test("isIp", () => {
  for (const ok of ["1.2.3.4", "255.255.255.255", "::1", "2001:db8::7", "::ffff:1.2.3.4"]) assert.ok(isIp(ok), ok);
  for (const bad of ["", "1.2.3", "256.1.1.1", "01.2.3.4", "a.b.c.d", "1::2::3", "host:80x"]) assert.ok(!isIp(bad), bad);
});
