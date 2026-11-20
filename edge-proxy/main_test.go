package main

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"
	"time"
)

const testSecret = "edge-secret-0123456789-abcdefghijklmnop"

type seen struct {
	Method, Path, Query, Host, Body string
	Header                          http.Header
}

// upstream records what reached it. It is TLS, like the real API.
func upstream(t *testing.T, status int) (*httptest.Server, *url.URL, chan seen) {
	t.Helper()
	got := make(chan seen, 4)
	srv := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		b, _ := io.ReadAll(r.Body)
		got <- seen{r.Method, r.URL.Path, r.URL.RawQuery, r.Host, string(b), r.Header.Clone()}
		w.Header().Set("X-From", "api")
		w.WriteHeader(status)
		_, _ = io.WriteString(w, `{"status":"healthy"}`)
	}))
	t.Cleanup(srv.Close)
	u, _ := url.Parse(srv.URL)
	return srv, u, got
}

func proxyFor(srv *httptest.Server, u *url.URL) http.Handler {
	return newHandler(u, testSecret, srv.Client().Transport)
}

func TestForwardsMethodPathQueryBodyAndAuthorizationToTheFixedUpstream(t *testing.T) {
	srv, u, got := upstream(t, http.StatusCreated)
	req := httptest.NewRequest(http.MethodPost, "https://zaypos-437e5.appspot.com/api/v1/sync/push?since=5&x=%2F", strings.NewReader(`{"a":1}`))
	req.Header.Set("Authorization", "Bearer jwt")
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set(userIPHeader, "203.0.113.9")
	rec := httptest.NewRecorder()

	proxyFor(srv, u).ServeHTTP(rec, req)

	if rec.Code != http.StatusCreated || rec.Header().Get("X-From") != "api" || rec.Body.String() != `{"status":"healthy"}` {
		t.Fatalf("response not passed back: %d %v %q", rec.Code, rec.Header(), rec.Body.String())
	}
	s := <-got
	if s.Method != "POST" || s.Path != "/api/v1/sync/push" || s.Query != "since=5&x=%2F" || s.Body != `{"a":1}` {
		t.Fatalf("request changed: %+v", s)
	}
	if s.Host != u.Host {
		t.Fatalf("Host = %q, want the upstream's %q", s.Host, u.Host)
	}
	if s.Header.Get("Authorization") != "Bearer jwt" || s.Header.Get("Content-Type") != "application/json" {
		t.Fatalf("end-to-end headers lost: %v", s.Header)
	}
	if s.Header.Get(secretHeader) != testSecret || s.Header.Get(clientIPHeader) != "203.0.113.9" {
		t.Fatalf("edge headers wrong: secret set=%v ip=%q", s.Header.Get(secretHeader) == testSecret, s.Header.Get(clientIPHeader))
	}
}

func TestAClientCannotSetTheEdgeHeadersOrGooglesHeaders(t *testing.T) {
	srv, u, got := upstream(t, http.StatusOK)
	req := httptest.NewRequest(http.MethodGet, "/health", nil)
	req.Header.Set("X-ZayPOS-Edge", "guess")
	req.Header.Add("X-ZayPOS-Edge", "guess2")
	req.Header.Set("X-ZayPOS-Client-IP", "198.51.100.66")
	req.Header.Set("X-ZayPOS-Anything", "x")
	req.Header.Set("X-Forwarded-For", "198.51.100.66")
	req.Header.Set("Forwarded", "for=198.51.100.66")
	req.Header.Set("X-Cloud-Trace-Context", "abc/1")
	req.Header.Set("X-Appengine-Country", "MM")
	req.Header.Set(userIPHeader, "203.0.113.9")

	proxyFor(srv, u).ServeHTTP(httptest.NewRecorder(), req)

	s := <-got
	if v := s.Header.Values(secretHeader); len(v) != 1 || v[0] != testSecret {
		t.Fatalf("secret header = %v, want exactly the proxy's", len(v))
	}
	if v := s.Header.Values(clientIPHeader); len(v) != 1 || v[0] != "203.0.113.9" {
		t.Fatalf("client IP = %v, want only Google's X-Appengine-User-Ip", v)
	}
	for _, h := range []string{"X-Zaypos-Anything", "X-Forwarded-For", "Forwarded", "X-Cloud-Trace-Context", "X-Appengine-Country", userIPHeader} {
		if s.Header.Get(h) != "" {
			t.Errorf("%s reached the upstream", h)
		}
	}
}

func TestWithoutAUsableAppEngineUserIPNoClientIPIsSent(t *testing.T) {
	for _, ip := range []string{"", "not-an-ip", "203.0.113.9, 198.51.100.1"} {
		srv, u, got := upstream(t, http.StatusOK)
		req := httptest.NewRequest(http.MethodGet, "/health", nil)
		if ip != "" {
			req.Header.Set(userIPHeader, ip)
		}
		proxyFor(srv, u).ServeHTTP(httptest.NewRecorder(), req)
		if s := <-got; s.Header.Get(clientIPHeader) != "" {
			t.Errorf("%q: client IP header sent", ip)
		}
	}
}

func TestOwnHealthDoesNotCallTheUpstream(t *testing.T) {
	srv, u, got := upstream(t, http.StatusOK)
	rec := httptest.NewRecorder()
	proxyFor(srv, u).ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/_proxy/health", nil))
	if rec.Code != 200 || rec.Body.String() != `{"status":"ok"}` {
		t.Fatalf("got %d %q", rec.Code, rec.Body.String())
	}
	select {
	case <-got:
		t.Fatal("upstream was called")
	default:
	}
}

func TestUpstreamDownGives502WithoutDetails(t *testing.T) {
	srv, u, _ := upstream(t, http.StatusOK)
	srv.Close()
	rec := httptest.NewRecorder()
	proxyFor(srv, u).ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/health", nil))
	if rec.Code != http.StatusBadGateway || !strings.Contains(rec.Body.String(), `"edge_upstream_unavailable"`) {
		t.Fatalf("got %d %q", rec.Code, rec.Body.String())
	}
	if strings.Contains(rec.Body.String(), u.Host) {
		t.Fatal("502 body names the upstream")
	}
}

func TestBodiesOver32MBAreRefused(t *testing.T) {
	srv, u, got := upstream(t, http.StatusOK)
	big := bytes.Repeat([]byte("x"), maxBodyBytes+1)

	rec := httptest.NewRecorder()
	proxyFor(srv, u).ServeHTTP(rec, httptest.NewRequest(http.MethodPost, "/api/v1/x", bytes.NewReader(big)))
	if rec.Code != http.StatusRequestEntityTooLarge {
		t.Fatalf("declared length: got %d", rec.Code)
	}

	req := httptest.NewRequest(http.MethodPost, "/api/v1/x", io.MultiReader(bytes.NewReader(big))) // unknown length
	req.ContentLength = -1
	rec = httptest.NewRecorder()
	proxyFor(srv, u).ServeHTTP(rec, req)
	if rec.Code != http.StatusRequestEntityTooLarge {
		t.Fatalf("streamed: got %d", rec.Code)
	}
	select {
	case s := <-got:
		if len(s.Body) > maxBodyBytes {
			t.Fatal("more than 32 MB reached the upstream")
		}
	default:
	}
}

func TestUpstreamMustBeABareHTTPSHost(t *testing.T) {
	for _, ok := range []string{"https://api.zaypos.app", "https://api.zaypos.app/", "https://api.zaypos.app:8443"} {
		if _, err := parseUpstream(ok); err != nil {
			t.Errorf("%q refused: %v", ok, err)
		}
	}
	for _, bad := range []string{"", "http://api.zaypos.app", "https://api.zaypos.app/api", "https://u:p@api.zaypos.app",
		"https://api.zaypos.app?x=1", "api.zaypos.app", "https://"} {
		if _, err := parseUpstream(bad); err == nil {
			t.Errorf("%q accepted", bad)
		}
	}
}

func TestSecretIsReadWithTheMetadataTokenAndValidated(t *testing.T) {
	const name = "projects/zaypos-437e5/secrets/edge-proxy-secret/versions/latest"
	serve := func(value string, tokenStatus, secretStatus int) (string, string) {
		meta := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if r.Header.Get("Metadata-Flavor") != "Google" {
				w.WriteHeader(403)
				return
			}
			w.WriteHeader(tokenStatus)
			_ = json.NewEncoder(w).Encode(map[string]string{"access_token": "tok-123"})
		}))
		sm := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if r.Header.Get("Authorization") != "Bearer tok-123" || r.URL.Path != "/v1/"+name+":access" {
				w.WriteHeader(403)
				return
			}
			w.WriteHeader(secretStatus)
			_ = json.NewEncoder(w).Encode(map[string]any{"payload": map[string]string{"data": base64.StdEncoding.EncodeToString([]byte(value))}})
		}))
		t.Cleanup(meta.Close)
		t.Cleanup(sm.Close)
		return meta.URL, sm.URL + "/v1/"
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	c := &http.Client{Timeout: 5 * time.Second}

	tokenURL, base := serve(testSecret+"\n", 200, 200)
	if got, err := accessSecret(ctx, c, tokenURL, base, name); err != nil || got != testSecret {
		t.Fatalf("got %q, %v", got, err)
	}

	cases := []struct {
		value         string
		token, secret int
		want          string
	}{
		{"short", 200, 200, "shorter than 32"},
		{testSecret + "," + testSecret, 200, 200, "commas"},
		{testSecret, 500, 200, "metadata token: HTTP 500"},
		{testSecret, 200, 403, "HTTP 403"},
	}
	for _, tc := range cases {
		tokenURL, base := serve(tc.value, tc.token, tc.secret)
		_, err := accessSecret(ctx, c, tokenURL, base, name)
		if err == nil || !strings.Contains(err.Error(), tc.want) {
			t.Errorf("%+v: err = %v", tc, err)
		}
		if err != nil && (strings.Contains(err.Error(), testSecret) || strings.Contains(err.Error(), "tok-123")) {
			t.Errorf("error leaks a secret or token: %v", err)
		}
	}
	if _, err := accessSecret(ctx, c, tokenURL, base, "edge-proxy-secret"); err == nil {
		t.Error("a bare secret name was accepted")
	}
}
