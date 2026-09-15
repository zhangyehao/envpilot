package config

import (
	"errors"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestProtectedSubscriptionTransport(t *testing.T) {
	target := filepath.Join(t.TempDir(), "config.yaml")
	_ = os.WriteFile(target, []byte("original"), 0600)
	original := http.DefaultTransport
	t.Cleanup(func() { http.DefaultTransport = original })
	http.DefaultTransport = roundTripFunc(func(*http.Request) (*http.Response, error) { return nil, errors.New("secret-token-in-upstream-error") })
	err := DownloadSubscription("https://example.invalid/?token=secret-token", target)
	if err == nil || strings.Contains(err.Error(), "secret-token") {
		t.Fatal("protected URL or upstream error leaked")
	}
	body, _ := os.ReadFile(target)
	if string(body) != "original" {
		t.Fatal("failed download changed configuration")
	}
	http.DefaultTransport = roundTripFunc(func(*http.Request) (*http.Response, error) {
		return &http.Response{StatusCode: 200, Body: io.NopCloser(strings.NewReader("<html>login</html>"))}, nil
	})
	if DownloadSubscription("https://example.invalid/", target) == nil {
		t.Fatal("HTML accepted as configuration")
	}
	http.DefaultTransport = roundTripFunc(func(*http.Request) (*http.Response, error) {
		return &http.Response{StatusCode: 200, Body: io.NopCloser(strings.NewReader(`{"proxies": [], "rules": ["MATCH,DIRECT"]}`))}, nil
	})
	if err = DownloadSubscription("https://example.invalid/", target); err != nil {
		t.Fatal(err)
	}
	body, _ = os.ReadFile(target)
	if !strings.Contains(string(body), "proxies:") {
		t.Fatal("configuration was not normalized")
	}
}
