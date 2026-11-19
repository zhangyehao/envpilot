package config

import (
	"encoding/json"
	"fmt"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"runtime"
	"strings"
)

const pythonReleaseAPI = "https://api.github.com/repos/astral-sh/python-build-standalone/releases"
const pythonReleaseDownloads = "https://github.com/astral-sh/python-build-standalone/releases/download/"

var pythonArchiveName = regexp.MustCompile(`^cpython-([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]{8})-(.+)-install_only\.tar\.gz$`)
var pythonDigest = regexp.MustCompile(`^[0-9a-fA-F]{64}$`)

type pythonAsset struct {
	Name   string `json:"name"`
	Digest string `json:"digest"`
}

type pythonRelease struct {
	Tag        string        `json:"tag_name"`
	Draft      bool          `json:"draft"`
	Prerelease bool          `json:"prerelease"`
	Assets     []pythonAsset `json:"assets"`
}

func pythonTarget() string {
	targets := map[string]string{"linux/amd64": "x86_64-unknown-linux-gnu", "linux/arm64": "aarch64-unknown-linux-gnu", "darwin/amd64": "x86_64-apple-darwin", "darwin/arm64": "aarch64-apple-darwin"}
	return targets[runtime.GOOS+"/"+runtime.GOARCH]
}

func (r pythonRelease) match(target, version string) (pythonAsset, string) {
	var selected pythonAsset
	best := ""
	if !r.Draft && !r.Prerelease {
		for _, asset := range r.Assets {
			m := pythonArchiveName.FindStringSubmatch(asset.Name)
			if m == nil || m[2] != r.Tag || m[3] != target || (version != "" && m[1] != version) {
				continue
			}
			if best == "" || newerVersion(m[1], best) {
				selected, best = asset, m[1]
			}
		}
	}
	return selected, best
}

func resolvePythonRelease(version string) (pythonRelease, pythonAsset, string, error) {
	var release pythonRelease
	target := pythonTarget()
	if target == "" {
		return release, pythonAsset{}, "", fmt.Errorf("E_UPDATE_PLATFORM")
	}
	if err := fetchUpdateJSON(pythonReleaseAPI+"/latest", &release); err != nil {
		return release, pythonAsset{}, "", err
	}
	if asset, v := release.match(target, version); v != "" {
		return release, asset, v, nil
	}
	// Preserve explicit-version lookup across the same most recent 30 releases
	// as the old installer. A page contains many build variants; bound its size.
	if version != "" && stableVersion.MatchString(version) {
		for page := 1; page <= 30; page++ {
			var releases []pythonRelease
			if err := fetchUpdateJSON(fmt.Sprintf("%s?per_page=1&page=%d", pythonReleaseAPI, page), &releases); err != nil {
				return release, pythonAsset{}, "", err
			}
			if len(releases) == 0 {
				break
			}
			if asset, v := releases[0].match(target, version); v != "" {
				return releases[0], asset, v, nil
			}
		}
	}
	return release, pythonAsset{}, "", fmt.Errorf("E_UPDATE_RELEASE: no matching stable Python package")
}

func expectedPythonDigest(data []byte, name string, allowBare bool) (string, error) {
	raw := strings.TrimSpace(string(data))
	if allowBare && pythonDigest.MatchString(raw) {
		return strings.ToLower(raw), nil
	}
	found := ""
	for _, line := range strings.Split(raw, "\n") {
		fields := strings.Fields(line)
		if len(fields) != 2 || strings.TrimPrefix(fields[1], "*") != name {
			continue
		}
		if !pythonDigest.MatchString(fields[0]) || found != "" {
			return "", fmt.Errorf("E_PYTHON_CHECKSUM: invalid or duplicate checksum for %s", name)
		}
		found = strings.ToLower(fields[0])
	}
	if found == "" {
		return "", fmt.Errorf("E_PYTHON_CHECKSUM: missing SHA-256 for %s", name)
	}
	return found, nil
}

// PythonAsset binds a digest to the same stable release, platform and filename
// as the archive URL. Shell callers consume its tab-separated fields.
func PythonAsset(version string) (string, error) {
	release, asset, v, err := resolvePythonRelease(version)
	if err != nil {
		return "", err
	}
	base := pythonReleaseDownloads + release.Tag + "/"
	digest := strings.TrimPrefix(asset.Digest, "sha256:")
	if asset.Digest == "" {
		sums, err := downloadBytes(base+"SHA256SUMS", 4<<20)
		if err != nil {
			return "", fmt.Errorf("E_PYTHON_CHECKSUM: %w", err)
		}
		digest, err = expectedPythonDigest(sums, asset.Name, false)
		if err != nil {
			return "", err
		}
	} else if digest == asset.Digest || !pythonDigest.MatchString(digest) {
		return "", fmt.Errorf("E_PYTHON_CHECKSUM: invalid release digest for %s", asset.Name)
	}
	// GitHub canonicalizes the literal '+' between version and date to %2B.
	return v + "\t" + base + strings.ReplaceAll(asset.Name, "+", "%2B") + "\t" + strings.ToLower(digest), nil
}

// PythonLocalDigest accepts an independently supplied release checksum or the
// exact matching asset in envpilot's bundled upstream manifest.
func PythonLocalDigest(archive, manifest string, online bool) (string, error) {
	name, err := url.PathUnescape(filepath.Base(archive))
	if err != nil {
		return "", fmt.Errorf("E_PYTHON_ASSET: invalid filename")
	}
	m := pythonArchiveName.FindStringSubmatch(name)
	if m == nil || m[3] != pythonTarget() {
		return "", fmt.Errorf("E_PYTHON_ASSET: expected an official stable install_only archive for this platform")
	}
	var bundled struct {
		Latest struct {
			Tag    string                 `json:"version"`
			Assets map[string]pythonAsset `json:"assets"`
		} `json:"latest"`
	}
	if b, err := os.ReadFile(manifest); err == nil {
		if err := json.Unmarshal(b, &bundled); err != nil {
			return "", fmt.Errorf("invalid Python manifest: %w", err)
		}
		asset := bundled.Latest.Assets[runtime.GOOS+"-"+runtime.GOARCH]
		if asset.Name == name && bundled.Latest.Tag == m[2] && strings.HasPrefix(asset.Digest, "sha256:") {
			digest := strings.TrimPrefix(asset.Digest, "sha256:")
			if !pythonDigest.MatchString(digest) {
				return "", fmt.Errorf("E_PYTHON_CHECKSUM: invalid bundled digest for %s", name)
			}
			return strings.ToLower(digest), nil
		}
	} else if !os.IsNotExist(err) {
		return "", err
	}
	for _, path := range []string{archive + ".sha256", filepath.Join(filepath.Dir(archive), "SHA256SUMS")} {
		data, err := os.ReadFile(path)
		if os.IsNotExist(err) {
			continue
		}
		if err != nil {
			return "", err
		}
		return expectedPythonDigest(data, name, path == archive+".sha256")
	}
	if online {
		sums, err := downloadBytes(pythonReleaseDownloads+m[2]+"/SHA256SUMS", 4<<20)
		if err != nil {
			return "", fmt.Errorf("E_PYTHON_CHECKSUM: %w", err)
		}
		return expectedPythonDigest(sums, name, false)
	}
	return "", fmt.Errorf("E_PYTHON_CHECKSUM: place the upstream SHA256SUMS or %s.sha256 beside the archive", name)
}
