package config

import (
	"bytes"
	"context"
	"errors"
	"io"
	"log"
	"net"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"syscall"
	"testing"
	"time"
)

const validSubscription = `proxies: []
proxy-groups:
  - name: select
    type: select
    proxies: [DIRECT]
rules: ["MATCH,select"]
`

func clearSubscriptionProxies(t *testing.T) {
	t.Helper()
	for _, key := range []string{"HTTP_PROXY", "http_proxy", "HTTPS_PROXY", "https_proxy", "ALL_PROXY", "all_proxy"} {
		t.Setenv(key, "")
	}
}

func subscriptionTestDownloader(options SubscriptionDownloadOptions) subscriptionDownloader {
	return subscriptionDownloader{options: options, sleep: func(context.Context, time.Duration) bool { return true }, client: newSubscriptionClient}
}

func TestProtectedSubscriptionTransport(t *testing.T) {
	clearSubscriptionProxies(t)
	target := filepath.Join(t.TempDir(), "config.yaml")
	_ = os.WriteFile(target, []byte("original"), 0600)
	var progress bytes.Buffer
	d := subscriptionTestDownloader(SubscriptionDownloadOptions{Network: "direct", Language: "en", Progress: &progress})
	d.client = func(*url.URL) *http.Client {
		return &http.Client{Transport: roundTripFunc(func(*http.Request) (*http.Response, error) {
			return nil, errors.New("secret-token-in-upstream-error")
		})}
	}
	err := d.download("https://example.invalid/?token=secret-token", target)
	if err == nil || strings.Contains(err.Error()+progress.String(), "secret-token") {
		t.Fatal("protected URL or upstream error leaked")
	}
	body, _ := os.ReadFile(target)
	if string(body) != "original" {
		t.Fatal("failed download changed configuration")
	}
	for _, input := range []string{"<html>login secret-token</html>", `{"error": "secret-token", "message":"expired"}`} {
		d.client = func(*url.URL) *http.Client {
			return &http.Client{Transport: roundTripFunc(func(*http.Request) (*http.Response, error) {
				return &http.Response{StatusCode: 200, Body: io.NopCloser(strings.NewReader(input))}, nil
			})}
		}
		err := d.download("https://example.invalid/?token=secret-token", target)
		if err == nil || strings.Contains(err.Error(), "secret-token") {
			t.Fatal("invalid response accepted or leaked")
		}
	}
	d.client = func(*url.URL) *http.Client {
		return &http.Client{Transport: roundTripFunc(func(*http.Request) (*http.Response, error) {
			return &http.Response{StatusCode: 200, Body: io.NopCloser(strings.NewReader(`{"proxies": [], "rules": ["MATCH,DIRECT"]}`))}, nil
		})}
	}
	if err = d.download("https://example.invalid/", target); err != nil {
		t.Fatal(err)
	}
	body, _ = os.ReadFile(target)
	if !strings.Contains(string(body), "proxies:") {
		t.Fatal("configuration was not normalized")
	}
}

func TestSubscriptionDirectIgnoresStaleProxy(t *testing.T) {
	clearSubscriptionProxies(t)
	t.Setenv("HTTP_PROXY", "http://127.0.0.1:1")
	t.Setenv("HTTPS_PROXY", "http://127.0.0.1:1")
	requests := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requests++
		if !strings.Contains(strings.ToLower(r.UserAgent()), "clash") {
			t.Error("missing compatible subscription user agent")
		}
		_, _ = io.WriteString(w, validSubscription)
	}))
	defer server.Close()
	for _, network := range []string{"direct", "auto"} {
		if err := DownloadSubscriptionWithOptions(server.URL+"/?token=private", filepath.Join(t.TempDir(), "config.yaml"), SubscriptionDownloadOptions{Network: network}); err != nil {
			t.Fatal(err)
		}
	}
	if requests != 2 {
		t.Fatalf("requests=%d", requests)
	}
}

func TestSubscriptionRetriesTransientHTTP(t *testing.T) {
	clearSubscriptionProxies(t)
	calls := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls++
		if calls < 3 {
			w.WriteHeader(504)
			_, _ = io.WriteString(w, "private upstream message")
			return
		}
		_, _ = io.WriteString(w, validSubscription)
	}))
	defer server.Close()
	d := subscriptionTestDownloader(SubscriptionDownloadOptions{Network: "direct"})
	delays := []time.Duration{}
	d.sleep = func(_ context.Context, delay time.Duration) bool { delays = append(delays, delay); return true }
	if err := d.download(server.URL, filepath.Join(t.TempDir(), "config.yaml")); err != nil {
		t.Fatal(err)
	}
	if calls != 3 || len(delays) != 2 || delays[0] != time.Second || delays[1] != 2*time.Second {
		t.Fatalf("calls=%d delays=%v", calls, delays)
	}
}

func TestSubscriptionRateLimitBoundedAndPrivate(t *testing.T) {
	clearSubscriptionProxies(t)
	t.Setenv("HTTPS_PROXY", "http://private-user:private-password@proxy.invalid:8080")
	for _, status := range []int{429, 503} {
		for _, format := range []string{"seconds", "date"} {
			for _, lang := range []string{"en", "zh-CN"} {
				t.Run(strconv.Itoa(status)+"/"+format+"/"+lang, func(t *testing.T) {
					target := filepath.Join(t.TempDir(), "config.yaml")
					if err := os.WriteFile(target, []byte("original"), 0600); err != nil {
						t.Fatal(err)
					}
					calls, routes := 0, 0
					var progress bytes.Buffer
					d := subscriptionTestDownloader(SubscriptionDownloadOptions{Network: "auto", Language: lang, Progress: &progress})
					d.client = func(proxy *url.URL) *http.Client {
						routes++
						if proxy != nil {
							t.Error("Retry-After caused proxy fallback")
						}
						return &http.Client{Transport: roundTripFunc(func(*http.Request) (*http.Response, error) {
							calls++
							retryAfter := "120"
							if format == "date" {
								retryAfter = time.Now().UTC().Add(120 * time.Second).Format(http.TimeFormat)
							}
							return &http.Response{
								StatusCode: status,
								Header:     http.Header{"Retry-After": []string{retryAfter}},
								Body:       io.NopCloser(strings.NewReader("private upstream token")),
							}, nil
						})}
					}
					var delays []time.Duration
					d.sleep = func(_ context.Context, delay time.Duration) bool { delays = append(delays, delay); return true }
					err := d.download("https://private-user:private-password@example.invalid/?token=private", target)
					code := "E_SUBSCRIPTION_HTTP"
					if status == 429 {
						code = "E_SUBSCRIPTION_RATE_LIMIT"
					}
					if err == nil || !strings.Contains(err.Error(), code) || strings.Contains(err.Error()+progress.String(), "private") {
						t.Fatalf("unexpected error: %v", err)
					}
					if calls != 1 || routes != 1 || len(delays) != 0 {
						t.Fatalf("upstream wait bypassed: calls=%d routes=%d delays=%v", calls, routes, delays)
					}
					diagnostic, route := "exceeds the remaining download budget", "direct"
					if lang == "zh-CN" {
						diagnostic, route = "超过本次下载剩余时限", "直连"
					}
					if !strings.Contains(err.Error(), diagnostic) || !strings.Contains(err.Error(), route) {
						t.Fatalf("localized budget diagnostic missing: %v", err)
					}
					if data, err := os.ReadFile(target); err != nil || string(data) != "original" {
						t.Fatalf("failed download changed configuration: %q, %v", data, err)
					}
				})
			}
		}
	}
}

func TestSubscriptionRetryAfterShortWaitAndSuccess(t *testing.T) {
	clearSubscriptionProxies(t)
	for _, status := range []int{429, 503} {
		for _, format := range []string{"3", "20", "date"} {
			t.Run(strconv.Itoa(status)+"/"+format, func(t *testing.T) {
				calls, routes := 0, 0
				var retryDate time.Time
				d := subscriptionTestDownloader(SubscriptionDownloadOptions{Network: "auto"})
				d.client = func(*url.URL) *http.Client {
					routes++
					return &http.Client{Transport: roundTripFunc(func(*http.Request) (*http.Response, error) {
						calls++
						if calls == 1 {
							retryAfter := format
							if format == "date" {
								retryDate = time.Now().UTC().Add(20 * time.Second).Truncate(time.Second)
								retryAfter = retryDate.Format(http.TimeFormat)
							}
							return &http.Response{
								StatusCode: status,
								Header:     http.Header{"Retry-After": []string{retryAfter}},
								Body:       io.NopCloser(strings.NewReader("")),
							}, nil
						}
						return &http.Response{StatusCode: 200, Body: io.NopCloser(strings.NewReader(validSubscription))}, nil
					})}
				}
				var delays []time.Duration
				d.sleep = func(_ context.Context, delay time.Duration) bool { delays = append(delays, delay); return true }
				started := time.Now()
				err := d.download("https://example.invalid/subscription", filepath.Join(t.TempDir(), "config.yaml"))
				finished := time.Now()
				if err != nil || calls != 2 || routes != 1 || len(delays) != 1 {
					t.Fatalf("retry failed: calls=%d routes=%d delays=%v error=%v", calls, routes, delays, err)
				}
				if format == "date" {
					if delays[0] < retryDate.Sub(finished) || delays[0] > retryDate.Sub(started) {
						t.Fatalf("HTTP-date wait shortened or extended: %v", delays)
					}
				} else {
					seconds, _ := strconv.Atoi(format)
					if delays[0] != time.Duration(seconds)*time.Second {
						t.Fatalf("numeric wait changed: %v", delays)
					}
				}
			})
		}
	}
}

func TestSubscriptionRetryAfterExhaustionDoesNotFallback(t *testing.T) {
	clearSubscriptionProxies(t)
	t.Setenv("HTTPS_PROXY", "http://proxy.invalid:8080")
	calls, routes := 0, 0
	d := subscriptionTestDownloader(SubscriptionDownloadOptions{Network: "auto"})
	d.client = func(*url.URL) *http.Client {
		routes++
		return &http.Client{Transport: roundTripFunc(func(*http.Request) (*http.Response, error) {
			calls++
			return &http.Response{
				StatusCode: 503,
				Header:     http.Header{"Retry-After": []string{"3"}},
				Body:       io.NopCloser(strings.NewReader("")),
			}, nil
		})}
	}
	var delays []time.Duration
	d.sleep = func(_ context.Context, delay time.Duration) bool { delays = append(delays, delay); return true }
	err := d.download("https://example.invalid/subscription", filepath.Join(t.TempDir(), "config.yaml"))
	if err == nil || !strings.Contains(err.Error(), "503") || calls != 3 || routes != 1 || len(delays) != 2 {
		t.Fatalf("exhausted Retry-After bypassed: calls=%d routes=%d delays=%v error=%v", calls, routes, delays, err)
	}
	for _, delay := range delays {
		if delay != 3*time.Second {
			t.Fatalf("Retry-After changed: %v", delays)
		}
	}
}

func TestSubscriptionHTTPAuthenticationDoesNotRetryOrFallback(t *testing.T) {
	clearSubscriptionProxies(t)
	for _, status := range []int{401, 403, 404, 410} {
		calls := 0
		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { calls++; w.WriteHeader(status) }))
		d := subscriptionTestDownloader(SubscriptionDownloadOptions{Network: "auto"})
		err := d.download(server.URL, filepath.Join(t.TempDir(), "config.yaml"))
		server.Close()
		if err == nil || calls != 1 || !strings.Contains(err.Error(), strconv.Itoa(status)) {
			t.Fatalf("status=%d calls=%d err=%v", status, calls, err)
		}
	}
}

func TestSubscriptionAutoFallsBackToManagedProxy(t *testing.T) {
	clearSubscriptionProxies(t)
	t.Setenv("HTTPS_PROXY", "http://127.0.0.1:1")
	var routes []string
	d := subscriptionTestDownloader(SubscriptionDownloadOptions{Network: "auto", ProxyPort: 43210})
	d.client = func(proxy *url.URL) *http.Client {
		route := "direct"
		if proxy != nil {
			route = proxy.Host
		}
		routes = append(routes, route)
		return &http.Client{Transport: roundTripFunc(func(*http.Request) (*http.Response, error) {
			switch route {
			case "direct":
				return nil, &net.DNSError{Err: "private resolver token", Name: "private.example"}
			case "127.0.0.1:1":
				return nil, &net.OpError{Op: "dial", Net: "tcp", Err: syscall.ECONNREFUSED}
			default:
				return &http.Response{StatusCode: 200, Body: io.NopCloser(strings.NewReader(validSubscription))}, nil
			}
		})}
	}
	if err := d.download("https://protected.example/secret", filepath.Join(t.TempDir(), "config.yaml")); err != nil {
		t.Fatal(err)
	}
	if strings.Join(routes, ",") != "direct,127.0.0.1:1,127.0.0.1:43210" {
		t.Fatalf("routes=%v", routes)
	}
}

func TestSubscriptionExplicitProxySkipsDirect(t *testing.T) {
	clearSubscriptionProxies(t)
	requests := 0
	proxy := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requests++
		if !r.URL.IsAbs() || r.URL.Host != "protected.invalid" {
			t.Errorf("not a proxy request")
		}
		_, _ = io.WriteString(w, validSubscription)
	}))
	defer proxy.Close()
	t.Setenv("HTTP_PROXY", proxy.URL)
	d := subscriptionTestDownloader(SubscriptionDownloadOptions{Network: "proxy"})
	if err := d.download("http://protected.invalid/token", filepath.Join(t.TempDir(), "config.yaml")); err != nil {
		t.Fatal(err)
	}
	if requests != 1 {
		t.Fatal("proxy not used")
	}
}

func TestSubscriptionRedirectDoesNotForwardCredentials(t *testing.T) {
	clearSubscriptionProxies(t)
	received := false
	destination := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		received = true
		if r.Header.Get("Referer") != "" || r.Header.Get("Authorization") != "" || r.Header.Get("Cookie") != "" {
			t.Error("redirect leaked credentials")
		}
		_, _ = io.WriteString(w, validSubscription)
	}))
	defer destination.Close()
	origin := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { http.Redirect(w, r, destination.URL, http.StatusFound) }))
	defer origin.Close()
	parsed, _ := url.Parse(origin.URL + "/?token=private")
	parsed.User = url.UserPassword("private-user", "private-password")
	if err := DownloadSubscriptionWithOptions(parsed.String(), filepath.Join(t.TempDir(), "config.yaml"), SubscriptionDownloadOptions{Network: "direct"}); err != nil {
		t.Fatal(err)
	}
	if !received {
		t.Fatal("redirect was not followed")
	}
	first, _ := http.NewRequest(http.MethodGet, "https://example.invalid/token", nil)
	next, _ := http.NewRequest(http.MethodGet, "http://example.invalid/next", nil)
	if subscriptionRedirect(next, []*http.Request{first}) == nil {
		t.Fatal("HTTPS downgrade accepted")
	}
}

func TestSubscriptionTLSAndErrorClassification(t *testing.T) {
	clearSubscriptionProxies(t)
	server := httptest.NewUnstartedServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { _, _ = io.WriteString(w, validSubscription) }))
	server.Config.ErrorLog = log.New(io.Discard, "", 0)
	server.StartTLS()
	defer server.Close()
	err := DownloadSubscriptionWithOptions(server.URL+"/?token=private", filepath.Join(t.TempDir(), "config.yaml"), SubscriptionDownloadOptions{Network: "direct"})
	if err == nil || !strings.Contains(err.Error(), "E_SUBSCRIPTION_TLS") || strings.Contains(err.Error(), "private") {
		t.Fatalf("unexpected TLS result: %v", err)
	}
	cases := []struct {
		err   error
		proxy bool
		code  string
	}{
		{&net.DNSError{Err: "private", Name: "private"}, false, "E_SUBSCRIPTION_DNS"},
		{context.DeadlineExceeded, false, "E_SUBSCRIPTION_TIMEOUT"},
		{&net.OpError{Op: "dial", Err: syscall.ECONNREFUSED}, true, "E_SUBSCRIPTION_PROXY_REFUSED"},
		{&net.OpError{Op: "dial", Err: syscall.ECONNREFUSED}, false, "E_SUBSCRIPTION_CONNECT"},
	}
	for _, test := range cases {
		if got := subscriptionNetworkFailure(test.err, test.proxy); got.code != test.code || strings.Contains(got.en, "private") {
			t.Fatalf("classification=%+v", got)
		}
	}
}

type subscriptionBrokenReader struct{}

func (subscriptionBrokenReader) Read([]byte) (int, error) {
	return 0, errors.New("private response body interrupted")
}

func TestSubscriptionInvalidBodiesPreserveTarget(t *testing.T) {
	clearSubscriptionProxies(t)
	cases := []struct{ body, contentType string }{
		{"", ""}, {"<html>private</html>", ""}, {validSubscription, "text/html"},
		{"token: private\n", ""}, {"proxies: []\nrules: [unterminated", ""},
		{"proxies: []\nrules: []\n---\nprivate: value", ""},
		{"proxies: []\nproxies: []\nrules: []", ""},
		{"proxies: [private]\nrules: []", ""},
		{"proxy-providers: {private: value}\nproxy-groups: []", ""},
		{"proxies: []\nrules: [1]", ""},
	}
	for _, test := range cases {
		target := filepath.Join(t.TempDir(), "config.yaml")
		_ = os.WriteFile(target, []byte("original"), 0600)
		d := subscriptionTestDownloader(SubscriptionDownloadOptions{Network: "direct"})
		d.client = func(*url.URL) *http.Client {
			return &http.Client{Transport: roundTripFunc(func(*http.Request) (*http.Response, error) {
				return &http.Response{StatusCode: 200, Header: http.Header{"Content-Type": []string{test.contentType}}, Body: io.NopCloser(strings.NewReader(test.body))}, nil
			})}
		}
		err := d.download("https://private.invalid/token", target)
		data, _ := os.ReadFile(target)
		if err == nil || strings.Contains(err.Error(), "private") || string(data) != "original" {
			t.Fatalf("invalid body accepted/leaked/replaced target: %v", err)
		}
	}
	d := subscriptionTestDownloader(SubscriptionDownloadOptions{Network: "direct"})
	d.client = func(*url.URL) *http.Client {
		return &http.Client{Transport: roundTripFunc(func(*http.Request) (*http.Response, error) {
			return &http.Response{StatusCode: 200, Body: io.NopCloser(subscriptionBrokenReader{})}, nil
		})}
	}
	err := d.download("https://private.invalid/token", filepath.Join(t.TempDir(), "config.yaml"))
	if err == nil || !strings.Contains(err.Error(), "E_SUBSCRIPTION_BODY") || strings.Contains(err.Error(), "private") {
		t.Fatalf("incomplete body result: %v", err)
	}
	if _, failure := normalizeSubscription(bytes.Repeat([]byte("x"), subscriptionMaxBytes+1)); failure == nil || failure.code != "E_SUBSCRIPTION_SIZE" {
		t.Fatal("oversized body accepted")
	}
}

func TestImportSubscriptionProtectedAndOffline(t *testing.T) {
	dir := t.TempDir()
	source, target := filepath.Join(dir, "source.yaml"), filepath.Join(dir, "config.yaml")
	_ = os.WriteFile(source, []byte(validSubscription), 0600)
	_ = os.WriteFile(target, []byte("old"), 0600)
	if err := ImportSubscription(source, target); err != nil {
		t.Fatal(err)
	}
	data, _ := os.ReadFile(target)
	if !bytes.Contains(data, []byte("proxy-groups:")) {
		t.Fatal("import not normalized")
	}
	original := string(data)
	_ = os.WriteFile(source, []byte("error: private"), 0600)
	if err := ImportSubscription(source, target); err == nil || strings.Contains(err.Error(), "private") {
		t.Fatalf("invalid import: %v", err)
	}
	data, _ = os.ReadFile(target)
	if string(data) != original {
		t.Fatal("invalid import replaced destination")
	}
	if runtime.GOOS != "windows" {
		_ = os.Chmod(source, 0644)
		if err := ImportSubscription(source, target); err == nil {
			t.Fatal("unsafe permissions accepted")
		}
	}
}

func TestSubscriptionRetryAfterAndOptions(t *testing.T) {
	now := time.Date(2026, 10, 26, 12, 0, 0, 0, time.UTC)
	for _, test := range []struct {
		value string
		delay time.Duration
	}{
		{"3", 3 * time.Second},
		{" 120 ", 120 * time.Second},
		{"-1", 0},
		{"garbage", 0},
		{"999999999", 999999999 * time.Second},
		{"99999999999", time.Duration(1<<63 - 1)},
		{"999999999999999999999999999999999999", time.Duration(1<<63 - 1)},
		{now.Add(5 * time.Second).Format(http.TimeFormat), 5 * time.Second},
		{now.Add(120 * time.Second).Format(http.TimeFormat), 120 * time.Second},
		{now.Add(-time.Minute).Format(http.TimeFormat), 0},
	} {
		if got := subscriptionRetryAfter(test.value, now); got != test.delay {
			t.Fatalf("Retry-After %q: %v", test.value, got)
		}
	}
	for _, options := range []SubscriptionDownloadOptions{{Network: "invalid"}, {Network: "direct", ProxyPort: -1}} {
		if DownloadSubscriptionWithOptions("https://example.invalid", filepath.Join(t.TempDir(), "config.yaml"), options) == nil {
			t.Fatal("invalid options accepted")
		}
	}
}
