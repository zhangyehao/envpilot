package config

import (
	"archive/tar"
	"bytes"
	"compress/gzip"
	"crypto/sha256"
	"encoding/hex"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

type roundTripFunc func(*http.Request) (*http.Response, error)

func (f roundTripFunc) RoundTrip(r *http.Request) (*http.Response, error) { return f(r) }

func testArchive(t *testing.T, files map[string]string) []byte {
	t.Helper()
	var output bytes.Buffer
	gz := gzip.NewWriter(&output)
	tarWriter := tar.NewWriter(gz)
	for name, body := range files {
		if err := tarWriter.WriteHeader(&tar.Header{Name: name, Mode: 0700, Size: int64(len(body)), Typeflag: tar.TypeReg}); err != nil {
			t.Fatal(err)
		}
		if _, err := tarWriter.Write([]byte(body)); err != nil {
			t.Fatal(err)
		}
	}
	_ = tarWriter.Close()
	_ = gz.Close()
	return output.Bytes()
}

func TestArchiveTraversalRejected(t *testing.T) {
	dir := t.TempDir()
	archive := filepath.Join(dir, "test.tar.gz")
	data := testArchive(t, map[string]string{"../outside": "must not be written"})
	_ = os.WriteFile(archive, data, 0600)
	if err := extractPackage(archive, dir, ".tar.gz"); err == nil {
		t.Fatal("archive traversal accepted")
	}
}

func TestBundleUpdateTransaction(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("Unix executable fixtures; native Windows installation has a separate integration test")
	}
	for _, mode := range []string{"checksum-failure", "migration-failure", "success"} {
		t.Run(mode, func(t *testing.T) {
			home := testHome(t)
			root := filepath.Join(home, "old-release")
			_ = os.MkdirAll(root, 0700)
			_ = os.WriteFile(filepath.Join(root, "VERSION"), []byte("0.4.0\n"), 0600)
			profile := filepath.Join(home, ".bashrc")
			_ = os.WriteFile(profile, []byte("original"), 0600)
			script := "#!/bin/sh\nprintf modified > \"$HOME/.bashrc\"\n"
			if mode == "migration-failure" {
				script += "exit 1\n"
			}
			archive := testArchive(t, map[string]string{
				"envpilot-0.4.1/VERSION":           "0.4.1\n",
				"envpilot-0.4.1/bin/envpilot-core": "#!/bin/sh\nexit 0\n",
				"envpilot-0.4.1/envpilot.sh":       script,
			})
			digest := sha256.Sum256(archive)
			checksum := hex.EncodeToString(digest[:])
			if mode == "checksum-failure" {
				checksum = strings.Repeat("0", 64)
			}
			name := "envpilot-0.4.1-" + runtime.GOOS + "-" + runtime.GOARCH + ".tar.gz"
			oldTransport := http.DefaultTransport
			t.Cleanup(func() { http.DefaultTransport = oldTransport })
			http.DefaultTransport = roundTripFunc(func(r *http.Request) (*http.Response, error) {
				if r.Header.Get("Authorization") != "" {
					t.Error("release fetch transmitted a credential")
				}
				var body []byte
				switch {
				case strings.HasSuffix(r.URL.Path, "/latest"):
					body = []byte(`{"tag_name":"v0.4.1","draft":false,"prerelease":false}`)
				case strings.HasSuffix(r.URL.Path, "/SHA256SUMS"):
					body = []byte(checksum + "  " + name + "\n")
				default:
					body = archive
				}
				return &http.Response{StatusCode: 200, Body: io.NopCloser(bytes.NewReader(body)), Header: make(http.Header)}, nil
			})
			err := BundleUpdate(Defaults(), root, filepath.Join(Dir(), "config.yaml"))
			body, _ := os.ReadFile(profile)
			if mode == "success" {
				if err != nil || string(body) != "modified" {
					t.Fatalf("successful update failed: %v", err)
				}
			} else {
				if err == nil {
					t.Fatal("invalid update succeeded")
				}
				if string(body) != "original" {
					t.Fatal("failed update did not preserve original profile")
				}
			}
		})
	}
}
