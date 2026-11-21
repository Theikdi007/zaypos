// ZayPOS edge proxy: the App Engine fallback route to the API (docs/deploy/fallback-routes.md).
//
// Myanmar networks refuse the API server's IP but let Google's own front end through, and App Engine apps are
// served from that front end. This service forwards every request to one fixed upstream (UPSTREAM, the API) and
// adds two headers the API trusts only together:
//
//	X-ZayPOS-Edge:      the shared secret (Secret Manager, read once at startup; never logged, never in app.yaml)
//	X-ZayPOS-Client-IP: the phone's address, from X-Appengine-User-Ip (set by Google, a client can't forge it)
//
// Not an open proxy: scheme and host are fixed, only path, query, method, headers and body come from the request.
// Standard library only.
package main

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"strings"
	"time"
)

const (
	secretHeader   = "X-Zaypos-Edge"      // canonical form of X-ZayPOS-Edge
	clientIPHeader = "X-Zaypos-Client-Ip" // canonical form of X-ZayPOS-Client-IP
	userIPHeader   = "X-Appengine-User-Ip"
	maxBodyBytes   = 32 << 20 // same cap as Caddy's request_body and App Engine's request limit
)

func main() {
	upstream, err := parseUpstream(os.Getenv("UPSTREAM"))
	if err != nil {
		log.Fatalf("config: %v", err)
	}
	secretName := os.Getenv("SECRET_NAME")
	if secretName == "" {
		log.Fatal("config: SECRET_NAME is required (projects/<p>/secrets/<s>/versions/latest)")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	secret, err := accessSecret(ctx, http.DefaultClient, metadataTokenURL, secretManagerBase, secretName)
	cancel()
	if err != nil {
		log.Fatalf("secret: %v", err) // the error text never contains the value
	}

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	srv := &http.Server{
		Addr:              ":" + port,
		Handler:           newHandler(upstream, secret, newTransport()),
		ReadHeaderTimeout: 10 * time.Second,
	}
	log.Printf("edge proxy → %s on :%s", upstream.Host, port)
	log.Fatal(srv.ListenAndServe())
}

// parseUpstream accepts only https://host[:port] with no path, query or credentials.
func parseUpstream(raw string) (*url.URL, error) {
	u, err := url.Parse(strings.TrimSpace(raw))
	if err != nil || raw == "" {
		return nil, errors.New("UPSTREAM must be set to https://<api host>")
	}
	if u.Scheme != "https" || u.Host == "" || u.User != nil || (u.Path != "" && u.Path != "/") || u.RawQuery != "" || u.Fragment != "" {
		return nil, fmt.Errorf("UPSTREAM must be https://host with nothing after the host, got %q", raw)
	}
	u.Path = ""
	return u, nil
}

func newTransport() *http.Transport {
	return &http.Transport{
		Proxy:                 nil,
		DialContext:           (&net.Dialer{Timeout: 5 * time.Second, KeepAlive: 30 * time.Second}).DialContext,
		ForceAttemptHTTP2:     true,
		TLSHandshakeTimeout:   10 * time.Second,
		ResponseHeaderTimeout: 60 * time.Second,
		IdleConnTimeout:       90 * time.Second,
		MaxIdleConnsPerHost:   32,
	}
}

func newHandler(upstream *url.URL, secret string, transport http.RoundTripper) http.Handler {
	proxy := &httputil.ReverseProxy{
		Rewrite: func(r *httputil.ProxyRequest) {
			// Rewrite has already removed hop-by-hop headers and the client's Forwarded / X-Forwarded-*.
			r.SetURL(upstream) // scheme + host fixed; Host header = upstream host
			for name := range r.Out.Header {
				n := strings.ToLower(name)
				if strings.HasPrefix(n, "x-zaypos-") || strings.HasPrefix(n, "x-appengine-") ||
					strings.HasPrefix(n, "x-google-") || n == "x-cloud-trace-context" || n == "traceparent" {
					r.Out.Header.Del(name)
				}
			}
			r.Out.Header.Set(secretHeader, secret)
			if ip := strings.TrimSpace(r.In.Header.Get(userIPHeader)); net.ParseIP(ip) != nil {
				r.Out.Header.Set(clientIPHeader, ip)
			}
		},
		Transport: transport,
		ErrorHandler: func(w http.ResponseWriter, req *http.Request, err error) {
			var tooBig *http.MaxBytesError
			if errors.As(err, &tooBig) {
				writeProblem(w, http.StatusRequestEntityTooLarge, "request_too_large")
				return
			}
			log.Printf("upstream error: %s %s: %s", req.Method, req.URL.Path, errorKind(err))
			writeProblem(w, http.StatusBadGateway, "edge_upstream_unavailable")
		},
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/_proxy/health", func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Cache-Control", "no-store")
		w.Header().Set("Content-Type", "application/json")
		_, _ = io.WriteString(w, `{"status":"ok"}`)
	})
	mux.Handle("/", http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.ContentLength > maxBodyBytes {
			writeProblem(w, http.StatusRequestEntityTooLarge, "request_too_large")
			return
		}
		r.Body = http.MaxBytesReader(w, r.Body, maxBodyBytes)
		start := time.Now()
		rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
		proxy.ServeHTTP(rec, r)
		// Method, path, status, duration only: no query, no headers, no bodies, no tokens.
		log.Printf("%s %s %d %dms", r.Method, r.URL.Path, rec.status, time.Since(start).Milliseconds())
	}))
	return mux
}

func writeProblem(w http.ResponseWriter, status int, code string) {
	w.Header().Set("Content-Type", "application/problem+json")
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(map[string]any{"status": status, "title": code, "code": code})
}

// errorKind keeps upstream errors short and free of anything request-specific.
func errorKind(err error) string {
	var ne net.Error
	switch {
	case errors.Is(err, context.Canceled):
		return "client went away"
	case errors.As(err, &ne) && ne.Timeout():
		return "timeout"
	default:
		var op *net.OpError
		if errors.As(err, &op) {
			return "network: " + op.Op
		}
		return "other"
	}
}

type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (s *statusRecorder) WriteHeader(code int)        { s.status = code; s.ResponseWriter.WriteHeader(code) }
func (s *statusRecorder) Unwrap() http.ResponseWriter { return s.ResponseWriter }

// ---------------------------------------------------------------- Secret Manager, without client libraries

var (
	metadataTokenURL  = "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token"
	secretManagerBase = "https://secretmanager.googleapis.com/v1/"
)

// accessSecret reads one secret version with the App Engine service account's token from the metadata server.
// Errors describe the step and HTTP status only, never a token or the value.
func accessSecret(ctx context.Context, c *http.Client, tokenURL, base, name string) (string, error) {
	if !strings.HasPrefix(name, "projects/") || !strings.Contains(name, "/secrets/") || !strings.Contains(name, "/versions/") {
		return "", fmt.Errorf("SECRET_NAME must look like projects/<p>/secrets/<s>/versions/<v>")
	}
	req, _ := http.NewRequestWithContext(ctx, http.MethodGet, tokenURL, nil)
	req.Header.Set("Metadata-Flavor", "Google")
	var tok struct {
		AccessToken string `json:"access_token"`
	}
	if err := getJSON(c, req, &tok); err != nil {
		return "", fmt.Errorf("metadata token: %w", err)
	}
	if tok.AccessToken == "" {
		return "", errors.New("metadata token: empty")
	}

	req, _ = http.NewRequestWithContext(ctx, http.MethodGet, base+name+":access", nil)
	req.Header.Set("Authorization", "Bearer "+tok.AccessToken)
	var out struct {
		Payload struct {
			Data string `json:"data"`
		} `json:"payload"`
	}
	if err := getJSON(c, req, &out); err != nil {
		return "", fmt.Errorf("secret %s: %w", name, err)
	}
	raw, err := base64.StdEncoding.DecodeString(out.Payload.Data)
	if err != nil {
		return "", fmt.Errorf("secret %s: payload is not base64", name)
	}
	secret := strings.TrimSpace(string(raw))
	if len(secret) < 32 {
		return "", fmt.Errorf("secret %s: shorter than 32 characters (the API refuses it too)", name)
	}
	if strings.ContainsAny(secret, ",\r\n") {
		return "", fmt.Errorf("secret %s: must not contain commas or line breaks", name)
	}
	return secret, nil
}

func getJSON(c *http.Client, req *http.Request, v any) error {
	res, err := c.Do(req)
	if err != nil {
		return errors.New(errorKind(err))
	}
	defer res.Body.Close()
	if res.StatusCode != http.StatusOK {
		_, _ = io.Copy(io.Discard, io.LimitReader(res.Body, 1<<16))
		return fmt.Errorf("HTTP %d", res.StatusCode)
	}
	return json.NewDecoder(io.LimitReader(res.Body, 1<<16)).Decode(v)
}
