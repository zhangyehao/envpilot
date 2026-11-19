package config

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"runtime"
	"strconv"
	"strings"
	"time"
)

var ErrUpdateBusy = errors.New("E_UPDATE_BUSY: another envpilot installation or update is running")

// A kernel lock is released even after a crash. Never unlink its inode.
func WithUpdateLock(fn func() error) error {
	if err := os.MkdirAll(Dir(), 0700); err != nil {
		return err
	}
	f, err := os.OpenFile(filepath.Join(Dir(), "update.lock"), os.O_CREATE|os.O_RDWR, 0600)
	if err != nil {
		return err
	}
	defer f.Close()
	if err = lockUpdateFile(f); err != nil {
		return ErrUpdateBusy
	}
	defer unlockUpdateFile(f)
	return fn()
}

func LockedCommand(args []string) error {
	if len(args) == 0 {
		return fmt.Errorf("update-lock requires a command")
	}
	return WithUpdateLock(func() error {
		cmd := exec.Command(args[0], args[1:]...)
		cmd.Env = append(os.Environ(), "ENVPILOT_UPDATE_LOCK_HELD=1")
		cmd.Stdin, cmd.Stdout, cmd.Stderr = os.Stdin, os.Stdout, os.Stderr
		return cmd.Run()
	})
}

type UpdateResult struct {
	LastUpstreamSuccess time.Time `json:"last_upstream_success"`
	PendingSwitch       bool      `json:"pending_switch,omitempty"`
	LastAttempt         time.Time `json:"last_attempt"`
	LastSuccess         time.Time `json:"last_success"`
	LastApplied         time.Time `json:"last_applied"`
	NextCheck           time.Time `json:"next_check"`
	Component           string    `json:"component"`
	Installed           string    `json:"installed,omitempty"`
	Latest              string    `json:"latest,omitempty"`
	Status              string    `json:"status"`
	ErrorCode           string    `json:"error_code,omitempty"`
}
type UpdateState struct {
	LastAttempt time.Time      `json:"last_attempt"`
	LastSuccess time.Time      `json:"last_success"`
	NextCheck   time.Time      `json:"next_check"`
	Results     []UpdateResult `json:"results"`
}

// Stable JSON is also consumed by monitoring tools. Do not store raw errors,
// headers, authentication or installer output in this public status file.
func updateStatePath(path string) string {
	path, _ = filepath.Abs(path)
	host, _ := os.Hostname()
	sum := sha256.Sum256([]byte(path + "\x00" + host))
	return filepath.Join(Dir(), "updates", hex.EncodeToString(sum[:8])+".json")
}
func readUpdateState(path string) (UpdateState, error) {
	var state UpdateState
	b, err := os.ReadFile(updateStatePath(path))
	if os.IsNotExist(err) {
		return state, nil
	}
	if err == nil {
		err = json.Unmarshal(b, &state)
	}
	return state, err
}

var stableVersion = regexp.MustCompile(`^v?([0-9]+)\.([0-9]+)\.([0-9]+)$`)

func newerVersion(latest, installed string) bool {
	a, b := stableVersion.FindStringSubmatch(latest), stableVersion.FindStringSubmatch(installed)
	if a == nil || b == nil {
		return false // Unknown/development builds must never be downgraded.
	}
	for i := 1; i <= 3; i++ {
		av, ae := strconv.ParseUint(a[i], 10, 64)
		bv, be := strconv.ParseUint(b[i], 10, 64)
		if ae != nil || be != nil {
			return false
		}
		if av != bv {
			return av > bv
		}
	}
	return false
}

// Metadata checks are bounded separately from package downloads. No provider
// credentials or GitHub tokens are attached to these public requests.
func fetchUpdateJSON(url string, dst any) error {
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	client := &http.Client{Timeout: 8 * time.Second}
	for attempt := 0; attempt < 3; attempt++ {
		req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
		if err != nil {
			return err
		}
		req.Header.Set("Accept", "application/json")
		req.Header.Set("User-Agent", "envpilot-update-check")
		resp, err := client.Do(req)
		retry, delay := false, time.Duration(1<<attempt)*time.Second
		if err == nil {
			if resp.StatusCode == 200 {
				b, readErr := io.ReadAll(io.LimitReader(resp.Body, (4<<20)+1))
				_ = resp.Body.Close()
				if readErr != nil || len(b) > 4<<20 {
					return fmt.Errorf("E_UPDATE_RESPONSE")
				}
				return json.Unmarshal(b, dst)
			}
			retry = resp.StatusCode == 429 || resp.StatusCode == 502 || resp.StatusCode == 503 || resp.StatusCode == 504 || resp.StatusCode == 500
			err = fmt.Errorf("E_UPDATE_HTTP_%d", resp.StatusCode)
			if after := resp.Header.Get("Retry-After"); after != "" {
				if n, e := strconv.Atoi(after); e == nil && n >= 0 {
					delay = time.Duration(n) * time.Second
				} else if at, e := http.ParseTime(after); e == nil {
					delay = time.Until(at)
				}
			}
			_ = resp.Body.Close()
		} else {
			retry = true
		}
		if !retry || attempt == 2 || delay > 8*time.Second {
			return err // Long rate limits are deferred to the next scheduled attempt.
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(max(delay, 0)):
		}
	}
	return fmt.Errorf("E_UPDATE_NETWORK")
}

func latestUpdate(c Config, component string) (string, error) {
	if component != "codex" && component != "envpilot" {
		return latestComponent(component)
	}
	if component == "codex" {
		var data struct {
			Version string `json:"version"`
		}
		if err := fetchUpdateJSON("https://registry.npmjs.org/@openai/codex/latest", &data); err != nil {
			return "", err
		}
		if !stableVersion.MatchString(data.Version) {
			return "", fmt.Errorf("E_UPDATE_RELEASE")
		}
		return data.Version, nil
	}
	url := "https://api.github.com/repos/zhangyehao/envpilot/releases/latest"
	if c.Install.ReleaseSource == "gitee" {
		url = "https://gitee.com/api/v5/repos/zhangyehao0422/envpilot/releases/latest"
	}
	var data struct {
		Tag        string `json:"tag_name"`
		Draft      bool   `json:"draft"`
		Prerelease bool   `json:"prerelease"`
	}
	if err := fetchUpdateJSON(url, &data); err != nil {
		return "", err
	}
	if data.Draft || data.Prerelease || !stableVersion.MatchString(data.Tag) {
		return "", fmt.Errorf("E_UPDATE_RELEASE")
	}
	return strings.TrimPrefix(data.Tag, "v"), nil
}

func installedUpdate(c Config, root, component string) (string, error) {
	if component != "codex" && component != "envpilot" {
		return installedComponent(c, component)
	}
	if component == "envpilot" {
		b, err := os.ReadFile(filepath.Join(root, "VERSION"))
		return strings.TrimSpace(string(b)), err
	}
	suffix := ""
	if runtime.GOOS == "windows" {
		suffix = ".exe"
	}
	h, _ := os.UserHomeDir()
	candidates := []string{
		filepath.Join(Expand(c.Codex.Home), "packages", "standalone", "current", "bin", "codex"+suffix),
		filepath.Join(Expand(c.Codex.Home), "packages", "standalone", "current", "codex"+suffix),
		filepath.Join(h, ".local", "bin", "codex"+suffix),
	}
	if p, err := exec.LookPath("codex"); err == nil {
		candidates = append(candidates, p)
	}
	for _, dir := range c.Shell.Paths {
		candidates = append(candidates, filepath.Join(Expand(dir), "codex"+suffix))
	}
	npm, _ := filepath.Glob(filepath.Join(h, ".nvm", "versions", "node", "*", "bin", "codex"))
	candidates = append(candidates, npm...)
	candidates = append(candidates, filepath.Join(h, "software", "node22", "bin", "codex"))
	if runtime.GOOS == "windows" {
		candidates = append(candidates, filepath.Join(os.Getenv("APPDATA"), "npm", "codex.cmd"))
	}
	for _, p := range candidates {
		st, err := os.Stat(p)
		if err != nil || st.IsDir() {
			continue
		}
		b, err := versionOutput(p, "--version")
		if err != nil {
			return "", fmt.Errorf("E_UPDATE_PROBE")
		}
		for _, line := range strings.Split(string(b), "\n") {
			if strings.HasPrefix(line, "codex-cli ") {
				return strings.TrimSpace(strings.TrimPrefix(line, "codex-cli ")), nil
			}
		}
		return "", fmt.Errorf("E_UPDATE_PROBE")
	}
	return "", nil // Not installed: automatic checks never install a new component.
}

type updateRunner struct {
	now          func() time.Time
	latest       func(Config, string) (string, error)
	installed    func(Config, string, string) (string, error)
	apply        func(Config, string, string, string) error
	task         func(Config, string, string, string) error
	verifyConfig func(bool) error
}

func defaultUpdateRunner() updateRunner {
	return updateRunner{now: time.Now, latest: latestUpdate, installed: installedUpdate, apply: applyUpdate, task: applyUpdate}
}
func applyUpdate(c Config, root, path, component string) error {
	command := []string{"update", component}
	if component == "envpilot" {
		command = []string{"self-update"}
	}
	switch component {
	case "subscription":
		command = []string{"mihomo", "update-subscription"}
	case "models":
		command = []string{"codex", "models", "refresh"}
	case "codex-reconcile":
		command = []string{"codex", "remote", "reconcile"}
	case "codex-verify":
		command = []string{"codex", "remote", "verify-if-running"}
	}
	var cmd *exec.Cmd
	if runtime.GOOS == "windows" {
		shell, err := exec.LookPath("pwsh")
		if err != nil {
			shell = "powershell"
		}
		args := append([]string{"-NoProfile", "-File", filepath.Join(root, "envpilot.ps1")}, command...)
		args = append(args, "-Yes", "-NonInteractive", "-Config", path)
		cmd = exec.Command(shell, args...)
	} else {
		args := append([]string{filepath.Join(root, "envpilot.sh")}, command...)
		args = append(args, "--yes", "--non-interactive", "--config", path)
		cmd = exec.Command("bash", args...)
	}
	cmd.Env = append(os.Environ(), "ENVPILOT_UPDATE_LOCK_HELD=1", "ENVPILOT_UPDATE_ORIGIN=automatic")
	logPath := filepath.Join(Dir(), "updates", "install.log")
	if err := os.MkdirAll(filepath.Dir(logPath), 0700); err != nil {
		return err
	}
	if st, err := os.Stat(logPath); err == nil && st.Size() > 2<<20 {
		if err = os.Rename(logPath, logPath+".previous"); err != nil {
			return err
		}
	}
	log, err := os.OpenFile(logPath, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0600)
	if err != nil {
		return err
	}
	defer log.Close()
	_, _ = fmt.Fprintf(log, "\n%s %s\n", time.Now().UTC().Format(time.RFC3339), component)
	// stdout is reserved for the structured updates report.
	cmd.Stdout, cmd.Stderr = io.MultiWriter(os.Stderr, log), io.MultiWriter(os.Stderr, log)
	// No stdin: unattended updates cannot prompt for input.
	return cmd.Run()
}
func updateTime(t time.Time) string {
	if t.IsZero() {
		return "-"
	}
	return t.Local().Format(time.RFC3339)
}
