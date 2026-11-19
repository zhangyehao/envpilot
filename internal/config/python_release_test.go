package config

import (
	"encoding/json"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

func TestPythonLocalChecksumSources(t *testing.T) {
	if pythonTarget() == "" {
		t.Skip("standalone Python is supported on Linux and macOS")
	}
	dir := t.TempDir()
	name := "cpython-3.15.2+20261110-" + pythonTarget() + "-install_only.tar.gz"
	archive, manifest := filepath.Join(dir, name), filepath.Join(dir, "python.json")
	digest := strings.Repeat("a1", 32)
	write := func(path, content string) {
		t.Helper()
		if err := os.WriteFile(path, []byte(content), 0600); err != nil {
			t.Fatal(err)
		}
	}
	check := func(want string) {
		t.Helper()
		got, err := PythonLocalDigest(archive, manifest, false)
		if want == "" && err == nil || want != "" && (err != nil || got != want) {
			t.Fatalf("digest %q, err %v, want %q", got, err, want)
		}
	}
	check("")
	write(filepath.Join(dir, "SHA256SUMS"), digest+"  other-build.tar.gz\n")
	check("")
	write(filepath.Join(dir, "SHA256SUMS"), digest+"  other-build.tar.gz\n"+digest+" *"+name+"\r\n")
	check(digest)
	write(archive+".sha256", digest+"  other-build.tar.gz")
	check("")
	write(archive+".sha256", digest+"  "+name+"\n"+digest+"  "+name+"\n")
	check("")
	write(archive+".sha256", strings.ToUpper(digest))
	check(digest)
	manifestDigest := strings.Repeat("b0", 32)
	write(manifest, `{"latest":{"version":"20261110","assets":{"`+runtime.GOOS+"-"+runtime.GOARCH+`":{"name":"`+name+`","digest":"sha256:`+manifestDigest+`"}}}}`)
	check(manifestDigest)
	archive = strings.Replace(archive, "20261110", "20261111", 1)
	check("")
}

func TestPythonAssetMatchesExactOfficialBuild(t *testing.T) {
	target := pythonTarget()
	if target == "" {
		t.Skip("standalone Python is supported on Linux and macOS")
	}
	release := pythonRelease{Tag: "20261110"}
	name := "cpython-3.15.2+20261110-" + target + "-install_only.tar.gz"
	hash := strings.Repeat("ad", 32)
	release.Assets = []pythonAsset{
		{Name: strings.Replace(name, "3.15.2", "3.16.0rc1", 1)},
		{Name: strings.Replace(name, "20261110", "20261111", 1)},
		{Name: strings.Replace(name, target, "freethreaded-"+target, 1)},
		{Name: strings.Replace(name, "3.15.2", "3.12.1", 1)},
		{Name: name, Digest: "sha256:" + hash},
	}
	old := http.DefaultTransport
	t.Cleanup(func() { http.DefaultTransport = old })
	var requestPaths []string
	http.DefaultTransport = roundTripFunc(func(r *http.Request) (*http.Response, error) {
		requestPaths = append(requestPaths, r.URL.Path)
		var body string
		switch {
		case r.URL.String() == pythonReleaseAPI+"/latest":
			data, _ := json.Marshal(release)
			body = string(data)
		case r.URL.String() == pythonReleaseDownloads+"20261110/SHA256SUMS":
			body = hash + "  " + name
		case r.URL.String() == pythonReleaseAPI+"?per_page=1&page=1":
			pinned := pythonRelease{Tag: "20261001", Assets: []pythonAsset{
				{Name: strings.NewReplacer("3.15.2", "3.9.3", "20261110", "20261001").Replace(name), Digest: "sha256:" + hash},
			}}
			data, _ := json.Marshal([]pythonRelease{pinned})
			body = string(data)
		default:
			t.Fatalf("unexpected URL: %s", r.URL)
		}
		return &http.Response{StatusCode: 200, Body: io.NopCloser(strings.NewReader(body)), Header: http.Header{}}, nil
	})
	got, err := PythonAsset("")
	if err != nil || !strings.HasPrefix(got, "3.15.2\t"+pythonReleaseDownloads+release.Tag+"/") || !strings.HasSuffix(got, "\t"+hash) || len(requestPaths) != 1 {
		t.Fatal(got, err, requestPaths)
	}
	release.Assets[4].Digest = ""
	got, err = PythonAsset("3.15.2")
	if err != nil || !strings.HasSuffix(got, "\t"+hash) || len(requestPaths) != 3 {
		t.Fatal(got, err, requestPaths)
	}
	got, err = PythonAsset("3.9.3")
	if err != nil || !strings.HasPrefix(got, "3.9.3\t"+pythonReleaseDownloads+"20261001/") {
		t.Fatal(got, err)
	}
	release.Assets[4].Digest = "sha256:" + strings.Repeat("x", 64)
	if _, err := PythonAsset(""); err == nil {
		t.Fatal("malformed release digest accepted")
	}
}
