package config

import (
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

func TestComponentReleaseAdapters(t *testing.T) {
	old := http.DefaultTransport
	t.Cleanup(func() { http.DefaultTransport = old })
	for _, component := range Names {
		t.Run(component, func(t *testing.T) {
			http.DefaultTransport = roundTripFunc(func(r *http.Request) (*http.Response, error) {
				if r.Header.Get("Authorization") != "" {
					t.Fatal("credential leaked")
				}
				body := `{"tag_name":"v3.4.5"}`
				switch component {
				case "git":
					if !strings.Contains(r.URL.Path, "/git/git/tags") {
						t.Fatal(r.URL)
					}
					body = `[{"name":"v2.55.0-rc1"},{"name":"v2.54.2"},{"name":"v2.54.1"}]`
				case "python":
					if !strings.Contains(r.URL.Path, "/astral-sh/python-build-standalone/") {
						t.Fatal(r.URL)
					}
					target := map[string]string{"linux/amd64": "x86_64-unknown-linux-gnu", "linux/arm64": "aarch64-unknown-linux-gnu", "darwin/amd64": "x86_64-apple-darwin", "darwin/arm64": "aarch64-apple-darwin"}[runtime.GOOS+"/"+runtime.GOARCH]
					body = fmt.Sprintf(`{"assets":[{"name":"cpython-3.14.0+20260924-%s-install_only.tar.gz"},{"name":"cpython-3.15.0rc2+20260924-%s-install_only.tar.gz"}]}`, target, target)
				case "codex":
					body = `{"version":"0.156.1"}`
				case "tmux":
					body = `{"tag_name":"3.5a"}`
				default:
					repo := map[string]string{"mihomo": "MetaCubeX/mihomo", "github": "cli/cli", "conda": "conda/conda", "mamba": "mamba-org/mamba"}[component]
					if !strings.Contains(r.URL.Path, repo+"/releases/latest") {
						t.Fatal(r.URL)
					}
				}
				return &http.Response{StatusCode: 200, Body: io.NopCloser(strings.NewReader(body)), Header: http.Header{}}, nil
			})
			v, err := latestUpdate(Defaults(), component)
			if component == "python" && runtime.GOOS == "windows" {
				if err == nil {
					t.Fatal("unsupported managed Python platform accepted")
				}
				return
			}
			expected := map[string]string{"git": "2.54.2", "python": "3.14.0", "codex": "0.156.1", "tmux": "3.5a"}[component]
			if expected == "" {
				expected = "3.4.5"
			}
			if err != nil || v != expected {
				t.Fatal(v, err)
			}
		})
	}
}

func TestInstalledVersionFormats(t *testing.T) {
	for output, want := range map[string]string{
		"git version 2.54.2.windows.1\n":     "2.54.2",
		"Python 3.14.0\n":                    "3.14.0",
		"tmux 3.5a\n":                        "3.5a",
		"Mihomo Meta v1.19.20 linux amd64\n": "1.19.20",
		"gh version 2.81.0 (2026-01-01)\n":   "2.81.0",
		"conda 25.9.1\n":                     "25.9.1",
		"2.3.3\n":                            "2.3.3",
	} {
		m := toolVersion.FindStringSubmatch(output)
		if len(m) < 2 || m[1] != want {
			t.Fatalf("%q -> %v", output, m)
		}
	}
}

func TestWindowsBatchVersionProbe(t *testing.T) {
	if runtime.GOOS != "windows" {
		t.Skip("Windows batch launcher")
	}
	dir := filepath.Join(t.TempDir(), "npm path & test")
	if err := os.MkdirAll(dir, 0700); err != nil {
		t.Fatal(err)
	}
	p := filepath.Join(dir, "codex.cmd")
	if err := os.WriteFile(p, []byte("@echo off\r\nif not \"%~1\"==\"--version\" exit /b 7\r\necho codex-cli 0.156.1\r\n"), 0600); err != nil {
		t.Fatal(err)
	}
	b, err := versionOutput(p, "--version")
	if err != nil || strings.TrimSpace(string(b)) != "codex-cli 0.156.1" {
		t.Fatal(string(b), err)
	}
}
