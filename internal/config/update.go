package config

import (
	"archive/tar"
	"archive/zip"
	"compress/gzip"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"runtime"
	"strings"
	"time"
)

func RefreshScripts(c Config, root string) error {
	h, _ := os.UserHomeDir()
	for _, name := range []string{"mihomo_common.sh", "start_mihomo.sh", "stop_mihomo.sh", "status_mihomo.sh", "update_mihomo_subscription.sh"} {
		target := filepath.Join(Expand(c.Install.Prefix), "mihomo", name)
		if _, e := os.Stat(target); e == nil {
			b, e := os.ReadFile(filepath.Join(root, "templates", name))
			if e != nil {
				return e
			}
			if e = WriteAtomic(target, b, 0700); e != nil {
				return e
			}
		}
	}
	for _, pair := range [][2]string{{"codex-remote", "codex-remote.sh"}, {"codex", "codex-wrapper.sh"}} {
		target := filepath.Join(h, ".local", "bin", pair[0])
		old, e := os.ReadFile(target)
		if e != nil {
			continue
		}
		if !strings.Contains(string(old[:min(len(old), 512)]), "envpilot") {
			continue
		}
		b, e := os.ReadFile(filepath.Join(root, "templates", pair[1]))
		if e != nil {
			return e
		}
		if e = WriteAtomic(target, b, 0700); e != nil {
			return e
		}
	}
	return InstallCore(root)
}

func InstallCore(root string) error {
	version, err := os.ReadFile(filepath.Join(root, "VERSION"))
	if err != nil {
		return err
	}
	name := "envpilot-core"
	if runtime.GOOS == "windows" {
		name += ".exe"
	}
	source := filepath.Join(root, "bin", name)
	if _, err = os.Stat(source); err != nil {
		source, err = os.Executable()
		if err != nil {
			return err
		}
	}
	home, _ := os.UserHomeDir()
	target := filepath.Join(home, ".local", "lib", "envpilot", strings.TrimSpace(string(version)), name)
	source, _ = filepath.Abs(source)
	target, _ = filepath.Abs(target)
	if source != target {
		data, err := os.ReadFile(source)
		if err != nil {
			return err
		}
		if err = WriteAtomic(target, data, 0700); err != nil {
			return err
		}
	}
	return WriteAtomic(filepath.Join(Dir(), "core-path"), []byte(target+"\n"), 0600)
}

func downloadBytes(url string, limit int64) ([]byte, error) {
	client := http.Client{Timeout: 90 * time.Second}
	resp, e := client.Get(url)
	if e != nil {
		return nil, e
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		return nil, fmt.Errorf("download returned HTTP %d", resp.StatusCode)
	}
	b, e := io.ReadAll(io.LimitReader(resp.Body, limit+1))
	if e == nil && int64(len(b)) > limit {
		return nil, fmt.Errorf("release response exceeds size limit")
	}
	return b, e
}
func BundleUpdate(c Config, root, configPath string) error {
	api := "https://api.github.com/repos/zhangyehao/envpilot/releases/latest"
	base := "https://github.com/zhangyehao/envpilot/releases/download/"
	if c.Install.ReleaseSource == "gitee" {
		api = "https://gitee.com/api/v5/repos/zhangyehao0422/envpilot/releases/latest"
		base = "https://gitee.com/zhangyehao0422/envpilot/releases/download/"
	}
	b, e := downloadBytes(api, 4<<20)
	if e != nil {
		return e
	}
	var release struct {
		Tag        string `json:"tag_name"`
		Draft      bool   `json:"draft"`
		Prerelease bool   `json:"prerelease"`
	}
	if e = json.Unmarshal(b, &release); e != nil {
		return e
	}
	if release.Draft || release.Prerelease || !regexp.MustCompile(`^v[0-9]+\.[0-9]+\.[0-9]+$`).MatchString(release.Tag) {
		return fmt.Errorf("invalid stable release metadata")
	}
	version := strings.TrimPrefix(release.Tag, "v")
	old, e := os.ReadFile(filepath.Join(root, "VERSION"))
	if e != nil {
		return e
	}
	if strings.TrimSpace(string(old)) == version {
		fmt.Println(Text(c.Language, "envpilot is already up to date.", "envpilot 已是最新版本。"))
		return RefreshScripts(c, root)
	}
	arch := runtime.GOARCH
	if arch == "arm" {
		arch = "armv7"
	}
	extension := ".tar.gz"
	if runtime.GOOS == "windows" {
		extension = ".zip"
	}
	name := fmt.Sprintf("envpilot-%s-%s-%s%s", version, runtime.GOOS, arch, extension)
	sums, e := downloadBytes(base+release.Tag+"/SHA256SUMS", 1<<20)
	if e != nil {
		return e
	}
	expected := ""
	for _, line := range strings.Split(string(sums), "\n") {
		fields := strings.Fields(line)
		if len(fields) == 2 && fields[1] == name {
			expected = fields[0]
		}
	}
	if len(expected) != 64 {
		return fmt.Errorf("matching release checksum is missing")
	}
	archive, e := downloadBytes(base+release.Tag+"/"+name, 512<<20)
	if e != nil {
		return e
	}
	digest := sha256.Sum256(archive)
	if hex.EncodeToString(digest[:]) != expected {
		return fmt.Errorf("release checksum mismatch")
	}
	h, _ := os.UserHomeDir()
	releases := filepath.Join(h, ".local", "share", "envpilot", "releases")
	if e = os.MkdirAll(releases, 0700); e != nil {
		return e
	}
	staging, e := os.MkdirTemp(releases, ".staging-")
	if e != nil {
		return e
	}
	defer os.RemoveAll(staging)
	archivePath := filepath.Join(staging, "package"+extension)
	if e = os.WriteFile(archivePath, archive, 0600); e != nil {
		return e
	}
	if e = extractPackage(archivePath, staging, extension); e != nil {
		return e
	}
	newRoot := filepath.Join(staging, "envpilot-"+version)
	meta, e := os.ReadFile(filepath.Join(newRoot, "VERSION"))
	if e != nil || strings.TrimSpace(string(meta)) != version {
		return fmt.Errorf("release VERSION mismatch")
	}
	final := filepath.Join(releases, version+"-"+time.Now().UTC().Format("20060102T150405"))
	if e = os.Rename(newRoot, final); e != nil {
		return e
	}
	coreName := "envpilot-core"
	if runtime.GOOS == "windows" {
		coreName += ".exe"
	}
	core := filepath.Join(final, "bin", coreName)
	check := exec.Command(core, "validate", "--config", configPath)
	check.Stdout = os.Stdout
	check.Stderr = os.Stderr
	if e = check.Run(); e != nil {
		return fmt.Errorf("new version cannot load the configuration: %w", e)
	}
	snapshot, e := SnapshotCreate(c, nil)
	if e != nil {
		return e
	}
	var command *exec.Cmd
	if runtime.GOOS == "windows" {
		shell, e := exec.LookPath("pwsh")
		if e != nil {
			shell = "powershell"
		}
		command = exec.Command(shell, "-NoProfile", "-File", filepath.Join(final, "envpilot.ps1"), "apply-shell", "-Yes", "-NonInteractive", "-Config", configPath)
	} else {
		command = exec.Command("bash", filepath.Join(final, "envpilot.sh"), "apply-shell", "--yes", "--non-interactive", "--config", configPath)
	}
	command.Env = append(os.Environ(), "EP_CONFIG_APPLY=1", "ENVPILOT_CORE="+core)
	command.Stdout = os.Stdout
	command.Stderr = os.Stderr
	if e = command.Run(); e != nil {
		restoreErr := SnapshotRestore(snapshot, c)
		return fmt.Errorf("migration failed: %v; managed-file restoration: %v; snapshot: %s", e, restoreErr, snapshot)
	}
	if e = RefreshScripts(c, final); e != nil {
		restoreErr := SnapshotRestore(snapshot, c)
		return fmt.Errorf("script refresh failed: %v; managed-file restoration: %v; snapshot: %s", e, restoreErr, snapshot)
	}
	fmt.Println(Text(c.Language, "envpilot updated to ", "envpilot 已更新至 ") + version)
	return nil
}
func extractPackage(path, destination, extension string) error {
	var total int64
	write := func(name string, size int64, mode os.FileMode, r io.Reader) error {
		clean := filepath.Clean(filepath.FromSlash(name))
		if filepath.IsAbs(clean) || clean == ".." || strings.HasPrefix(clean, ".."+string(filepath.Separator)) {
			return fmt.Errorf("unsafe archive path")
		}
		total += size
		if size < 0 || total > 1<<30 {
			return fmt.Errorf("archive exceeds size limit")
		}
		target := filepath.Join(destination, clean)
		if e := os.MkdirAll(filepath.Dir(target), 0700); e != nil {
			return e
		}
		f, e := os.OpenFile(target, os.O_CREATE|os.O_EXCL|os.O_WRONLY, mode.Perm())
		if e != nil {
			return e
		}
		_, e = io.CopyN(f, r, size)
		closeErr := f.Close()
		if e != nil {
			return e
		}
		return closeErr
	}
	if extension == ".zip" {
		z, e := zip.OpenReader(path)
		if e != nil {
			return e
		}
		defer z.Close()
		for _, f := range z.File {
			if f.FileInfo().IsDir() {
				continue
			}
			if !f.Mode().IsRegular() {
				return fmt.Errorf("archive links are not allowed")
			}
			r, e := f.Open()
			if e != nil {
				return e
			}
			e = write(f.Name, int64(f.UncompressedSize64), f.Mode(), r)
			_ = r.Close()
			if e != nil {
				return e
			}
		}
		return nil
	}
	f, e := os.Open(path)
	if e != nil {
		return e
	}
	defer f.Close()
	gz, e := gzip.NewReader(f)
	if e != nil {
		return e
	}
	defer gz.Close()
	tr := tar.NewReader(gz)
	for {
		header, e := tr.Next()
		if e == io.EOF {
			return nil
		}
		if e != nil {
			return e
		}
		if header.Typeflag == tar.TypeDir {
			continue
		}
		if header.Typeflag != tar.TypeReg {
			return fmt.Errorf("archive links are not allowed")
		}
		if e = write(header.Name, header.Size, os.FileMode(header.Mode), tr); e != nil {
			return e
		}
	}
}
