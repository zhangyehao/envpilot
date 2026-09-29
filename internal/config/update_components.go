package config

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"runtime"
	"strings"
	"time"
)

func containsComponent(names []string, name string) bool {
	for _, v := range names {
		if v == name {
			return true
		}
	}
	return false
}

var toolVersion = regexp.MustCompile(`(?:^|[ /v])([0-9]+\.[0-9]+(?:\.[0-9]+)?[a-z]?)(?:\.windows\.[0-9]+)?(?:[ \r\n(]|$)`)
var tmuxVersion = regexp.MustCompile(`^([0-9]+)\.([0-9]+)([a-z]?)$`)

func knownComponentVersion(component, v string) bool {
	return stableVersion.MatchString(v) || component == "tmux" && tmuxVersion.MatchString(v)
}
func newerComponentVersion(component, latest, installed string) bool {
	if component != "tmux" {
		return newerVersion(latest, installed)
	}
	a, b := tmuxVersion.FindStringSubmatch(latest), tmuxVersion.FindStringSubmatch(installed)
	if a == nil || b == nil {
		return newerVersion(latest, installed)
	}
	if a[1] == b[1] && a[2] == b[2] {
		return a[3] > b[3]
	}
	return newerVersion(a[1]+"."+a[2]+".0", b[1]+"."+b[2]+".0")
}

func componentTool(c Config, component string) (string, bool) {
	h, _ := os.UserHomeDir()
	prefix := Expand(c.Install.Prefix)
	commands := map[string]string{"git": "git", "python": "python3", "mihomo": "mihomo", "conda": "conda", "mamba": "mamba", "github": "gh", "tmux": "tmux"}
	name := commands[component]
	if name == "" {
		return "", false
	}
	candidates := []string{}
	switch component {
	case "git", "python":
		candidates = append(candidates, filepath.Join(prefix, component, "current", "bin", name))
	case "mihomo":
		candidates = append(candidates, filepath.Join(prefix, "mihomo", "mihomo"))
	case "github", "tmux":
		candidates = append(candidates, filepath.Join(h, ".local", "bin", name), filepath.Join(h, ".local", "envpilot", "bin", name))
	case "conda", "mamba":
		for _, base := range []string{Expand(c.Conda.Prefix), filepath.Join(prefix, "miniconda3"), filepath.Join(prefix, "anaconda3"), filepath.Join(h, "miniconda3"), filepath.Join(h, "anaconda3"), os.Getenv("CONDA_PREFIX")} {
			if base == "" {
				continue
			}
			candidates = append(candidates, filepath.Join(base, "bin", name))
			if runtime.GOOS == "windows" {
				candidates = append(candidates, filepath.Join(base, "Scripts", name+".exe"), filepath.Join(base, "Library", "bin", name+".exe"))
			}
		}
	}
	for _, p := range candidates {
		if st, err := os.Stat(p); err == nil && !st.IsDir() {
			return p, true
		}
		if runtime.GOOS == "windows" {
			if st, err := os.Stat(p + ".exe"); err == nil && !st.IsDir() {
				return p + ".exe", true
			}
		}
	}
	names := []string{name}
	if component == "python" {
		names = append(names, "python")
	}
	for _, name := range names {
		if p, err := exec.LookPath(name); err == nil {
			// Conda/Mamba already own their base prefix and update via their solver.
			return p, component == "conda" || component == "mamba"
		}
	}
	return "", false
}
func installedComponent(c Config, component string) (string, error) {
	path, _ := componentTool(c, component)
	if path == "" {
		return "", nil
	}
	arg := "--version"
	if component == "tmux" {
		arg = "-V"
	}
	if component == "mihomo" {
		arg = "-v"
	}
	b, err := versionOutput(path, arg)
	if err != nil {
		return "", fmt.Errorf("E_UPDATE_PROBE")
	}
	match := toolVersion.FindStringSubmatch(string(b))
	if len(match) < 2 {
		return "", fmt.Errorf("E_UPDATE_PROBE")
	}
	return match[1], nil
}

// Windows npm/Conda launchers can be batch files. Pass their path as data
// through PowerShell rather than interpolating it into a cmd.exe command.
func versionOutput(path, arg string) ([]byte, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, path, arg)
	env := append(os.Environ(), "PATH="+filepath.Dir(path)+string(os.PathListSeparator)+os.Getenv("PATH"))
	if runtime.GOOS == "windows" && (strings.EqualFold(filepath.Ext(path), ".cmd") || strings.EqualFold(filepath.Ext(path), ".bat")) {
		shell, err := exec.LookPath("pwsh")
		if err != nil {
			shell = "powershell.exe"
		}
		cmd = exec.CommandContext(ctx, shell, "-NoProfile", "-NonInteractive", "-Command",
			"& $env:ENVPILOT_VERSION_EXECUTABLE $env:ENVPILOT_VERSION_ARGUMENT; exit $LASTEXITCODE")
		env = append(env, "ENVPILOT_VERSION_EXECUTABLE="+path, "ENVPILOT_VERSION_ARGUMENT="+arg)
	}
	cmd.Env = env
	cmd.WaitDelay = time.Second
	return cmd.Output()
}
func managedUpdateComponent(c Config, component string) bool {
	_, managed := componentTool(c, component)
	return managed
}

func latestComponent(component string) (string, error) {
	repos := map[string]string{"mihomo": "MetaCubeX/mihomo", "github": "cli/cli", "conda": "conda/conda", "mamba": "mamba-org/mamba", "tmux": "tmux/tmux"}
	if component == "git" {
		var tags []struct {
			Name string `json:"name"`
		}
		if err := fetchUpdateJSON("https://api.github.com/repos/git/git/tags?per_page=30", &tags); err != nil {
			return "", err
		}
		best := "0.0.0"
		for _, tag := range tags {
			v := strings.TrimPrefix(tag.Name, "v")
			if newerVersion(v, best) {
				best = v
			}
		}
		if best == "0.0.0" {
			return "", fmt.Errorf("E_UPDATE_RELEASE")
		}
		return best, nil
	}
	if component == "python" {
		var release struct {
			Draft      bool `json:"draft"`
			Prerelease bool `json:"prerelease"`
			Assets     []struct {
				Name string `json:"name"`
			} `json:"assets"`
		}
		if err := fetchUpdateJSON("https://api.github.com/repos/astral-sh/python-build-standalone/releases/latest", &release); err != nil {
			return "", err
		}
		targets := map[string]string{"linux/amd64": "x86_64-unknown-linux-gnu", "linux/arm64": "aarch64-unknown-linux-gnu", "darwin/amd64": "x86_64-apple-darwin", "darwin/arm64": "aarch64-apple-darwin"}
		target := targets[runtime.GOOS+"/"+runtime.GOARCH]
		if target == "" || release.Draft || release.Prerelease {
			return "", fmt.Errorf("E_UPDATE_PLATFORM")
		}
		pattern := regexp.MustCompile(`^cpython-([0-9]+\.[0-9]+\.[0-9]+)\+[^/]+-` + regexp.QuoteMeta(target) + `-install_only\.tar\.gz$`)
		best := "0.0.0"
		for _, asset := range release.Assets {
			match := pattern.FindStringSubmatch(asset.Name)
			if len(match) > 1 && newerVersion(match[1], best) {
				best = match[1]
			}
		}
		if best == "0.0.0" {
			return "", fmt.Errorf("E_UPDATE_RELEASE")
		}
		return best, nil
	}
	repo := repos[component]
	if repo == "" {
		return "", fmt.Errorf("E_UPDATE_COMPONENT")
	}
	var data struct {
		Tag        string `json:"tag_name"`
		Draft      bool   `json:"draft"`
		Prerelease bool   `json:"prerelease"`
	}
	if err := fetchUpdateJSON("https://api.github.com/repos/"+repo+"/releases/latest", &data); err != nil {
		return "", err
	}
	v := strings.TrimPrefix(data.Tag, "v")
	if data.Draft || data.Prerelease || !knownComponentVersion(component, v) {
		return "", fmt.Errorf("E_UPDATE_RELEASE")
	}
	return v, nil
}

// Used by the existing Bash installers so a stale repository manifest or
// bundled cache cannot pin an explicit online update to an old release.
func LatestComponent(component string) (string, error) { return latestComponent(component) }
