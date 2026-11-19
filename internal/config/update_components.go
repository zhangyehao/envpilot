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
		// Existing installers place Mihomo under ~/software even if other tools
		// use a custom install.prefix. Follow the native validator's order.
		candidates = append(candidates, filepath.Join(h, "software", "mihomo", name), filepath.Join(prefix, "mihomo", name))
	case "github", "tmux":
		candidates = append(candidates, filepath.Join(h, ".local", "bin", name), filepath.Join(h, ".local", "envpilot", "bin", name))
	case "conda", "mamba":
		dist := c.Conda.Distribution + "3"
		bases := []string{filepath.Join(prefix, dist), filepath.Join(h, dist), filepath.Join(h, "software", dist)}
		other := "anaconda3"
		if dist == "anaconda3" {
			other = "miniconda3"
		}
		bases = append(bases, filepath.Join(prefix, other), filepath.Join(h, other), filepath.Join(h, "software", other))
		if c.Conda.Prefix != "" {
			bases = []string{Expand(c.Conda.Prefix)}
		}
		for _, base := range bases {
			candidates = append(candidates, filepath.Join(base, "bin", name))
			if component == "mamba" {
				candidates = append(candidates, filepath.Join(base, "condabin", name))
			}
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
	// A pinned prefix names an installation. A similarly named command in
	// another environment must not be reported as its installed version.
	if (component == "conda" || component == "mamba") && c.Conda.Prefix != "" {
		return "", false
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
	timeout := 10 * time.Second
	conda := component == "conda" || component == "mamba"
	if conda {
		timeout = 60 * time.Second
	}
	b, err := probeVersionOutput(path, arg, timeout, conda)
	if err != nil {
		return "", err
	}
	match := toolVersion.FindStringSubmatch(string(b))
	if len(match) < 2 {
		return "", fmt.Errorf("E_UPDATE_PROBE_FORMAT")
	}
	return match[1], nil
}

// Windows npm/Conda launchers can be batch files. Pass their path as data
// through PowerShell rather than interpolating it into a cmd.exe command.
func versionOutput(path, arg string) ([]byte, error) {
	return probeVersionOutput(path, arg, 10*time.Second, false)
}

func cleanCondaEnvironment(env []string, condarc string) []string {
	// Keep in sync with ep_run_conda_clean and Invoke-CleanConda.
	remove := map[string]bool{"LD_LIBRARY_PATH": true, "PYTHONHOME": true, "PYTHONPATH": true, "CONDA_CHANNELS": true,
		"CONDA_DEFAULT_CHANNELS": true, "CONDA_CUSTOM_CHANNELS": true, "CONDA_SOLVER": true, "CONDARC": true}
	result := make([]string, 0, len(env)+1)
	for _, item := range env {
		key, _, _ := strings.Cut(item, "=")
		if runtime.GOOS == "windows" {
			key = strings.ToUpper(key)
		}
		if !remove[key] {
			result = append(result, item)
		}
	}
	return append(result, "CONDARC="+condarc)
}

func probeVersionOutput(path, arg string, timeout time.Duration, conda bool) ([]byte, error) {
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, path, arg)
	env := os.Environ()
	if conda {
		home, err := os.UserHomeDir()
		if err != nil {
			return nil, fmt.Errorf("E_UPDATE_PROBE_COMMAND")
		}
		env = cleanCondaEnvironment(env, filepath.Join(home, ".condarc"))
	} else {
		env = append(env, "PATH="+filepath.Dir(path)+string(os.PathListSeparator)+os.Getenv("PATH"))
	}
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
	b, err := cmd.Output()
	if ctx.Err() == context.DeadlineExceeded {
		return nil, fmt.Errorf("E_UPDATE_PROBE_TIMEOUT")
	}
	if err != nil {
		return nil, fmt.Errorf("E_UPDATE_PROBE_COMMAND")
	}
	return b, nil
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
