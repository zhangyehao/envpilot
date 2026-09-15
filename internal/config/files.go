package config

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"time"
)

const Begin = "# >>> envpilot >>>"
const End = "# <<< envpilot <<<"

func Init(path, lang string) error {
	if path == "" {
		path = filepath.Join(Dir(), "config.yaml")
	}
	path = Expand(path)
	if _, err := os.Stat(path); err == nil {
		return fmt.Errorf("configuration already exists: %s", path)
	} else if !os.IsNotExist(err) {
		return err
	}
	resolved, err := Load(path, nil)
	if err != nil {
		return err
	}
	c := resolved.Config
	if lang != "" {
		c.Language = lang
	}
	c = ImportLegacy(c)
	if err := Validate(c); err != nil {
		return err
	}
	body, err := Encode(c)
	if err != nil {
		return err
	}
	header := Text(c.Language, "# envpilot configuration. Edit here, then run: envpilot plan; envpilot apply\n# Secrets are references, never paste keys or subscription URLs here.\n", "# envpilot 统一配置。修改后执行：envpilot plan，再执行 envpilot apply。\n# 密钥和订阅地址通过文件/环境变量引用，请勿直接粘贴到本文件。\n")
	if err = os.MkdirAll(filepath.Dir(path), 0700); err != nil {
		return err
	}
	f, err := os.OpenFile(path, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0600)
	if err != nil {
		return err
	}
	_, err = f.Write(append([]byte(header), body...))
	e := f.Close()
	if err != nil {
		return err
	}
	return e
}
func ImportLegacy(c Config) Config {
	h, _ := os.UserHomeDir()
	legacy := false
	for _, p := range []string{filepath.Join(h, ".bashrc"), filepath.Join(h, ".zshrc"), filepath.Join(h, "Documents", "PowerShell", "Microsoft.PowerShell_profile.ps1"), filepath.Join(h, "Documents", "WindowsPowerShell", "Microsoft.PowerShell_profile.ps1")} {
		b, _ := os.ReadFile(p)
		if strings.Contains(string(b), "managed by envpilot") {
			legacy = true
		}
	}
	if legacy {
		if _, e := os.Stat(filepath.Join(h, ".config", "secrets", "api.env.ps1")); e == nil {
			c.Secrets.File = filepath.Join(h, ".config", "secrets", "api.env.ps1")
		}
	}

	b, _ := os.ReadFile(filepath.Join(Dir(), "shell.local"))
	if len(b) > 0 {
		c.Shell.LegacyLocal = true
	}
	if legacy {
		c.Shell.Conda = true
		c.Shell.AutoStartProxy = true
		c.Shell.AutoEnableProxy = true
		c.Shell.LoadSecrets = true
		c.Shell.HistorySync = true
		c.Shell.LegacyAliases = true
		c.Shell.LegacyLocal = true
	}
	// Only literal assignments are imported. User shell code is never evaluated.
	for _, line := range strings.Split(string(b), "\n") {
		line = strings.TrimSpace(strings.TrimPrefix(strings.TrimSpace(line), "export "))
		kv := strings.SplitN(line, "=", 2)
		if len(kv) != 2 {
			continue
		}
		v := strings.Trim(strings.TrimSpace(kv[1]), `"'`)
		if v != "0" && v != "1" && !regexp.MustCompile(`^[0-9]+$`).MatchString(v) {
			continue
		}
		switch kv[0] {
		case "BASHRC_INIT_CONDA":
			c.Shell.Conda = v == "1"
		case "BASHRC_AUTO_START_MIHOMO":
			c.Shell.AutoStartProxy = v == "1"
		case "BASHRC_AUTO_ENABLE_PROXY":
			c.Shell.AutoEnableProxy = v == "1"
		case "BASHRC_AUTO_LOAD_SECRETS":
			c.Shell.LoadSecrets = v == "1"
		case "BASHRC_ENABLE_HISTORY_SYNC":
			c.Shell.HistorySync = v == "1"
		case "MIHOMO_PROXY_PORT", "BASHRC_PROXY_PORT":
			fmt.Sscan(v, &c.Mihomo.ProxyPort)
		case "MIHOMO_API_PORT":
			fmt.Sscan(v, &c.Mihomo.APIPort)
		}
	}
	if b, e := os.ReadFile(filepath.Join(Dir(), "modules.list")); e == nil {
		for _, v := range strings.Split(string(b), "\n") {
			v = strings.TrimSpace(v)
			if v != "" && !strings.HasPrefix(v, "#") {
				c.Shell.Modules = append(c.Shell.Modules, v)
			}
		}
	}
	if b, e := os.ReadFile(filepath.Join(h, ".local", "bin", "codex")); e == nil && strings.Contains(string(b[:min(len(b), 512)]), "envpilot-managed-codex-wrapper") {
		c.Codex.Remote = true
	}
	return c
}
func Quote(s string) string   { return "'" + strings.ReplaceAll(s, "'", "'\\''") + "'" }
func PSQuote(s string) string { return "'" + strings.ReplaceAll(s, "'", "''") + "'" }
func Render(c Config, root, kind string) error {
	dir := filepath.Join(Dir(), "shell")
	env := c.Environment()
	var body strings.Builder
	for _, k := range SortedKeys(env) {
		_, public := environmentFields[k]
		if kind == "powershell" {
			if public {
				fmt.Fprintf(&body, "if ([string]::IsNullOrEmpty([Environment]::GetEnvironmentVariable('%s')) -or $env:%s -eq $env:ENVPILOT_MANAGED_%s) { $env:%s = %s; $env:ENVPILOT_MANAGED_%s = $env:%s }\n", k, k, k, k, PSQuote(env[k]), k, k)
			} else {
				fmt.Fprintf(&body, "$env:%s = %s\n", k, PSQuote(env[k]))
			}
		} else {
			if public {
				fmt.Fprintf(&body, "if [ -z \"${%s-}\" ] || [ \"${%s-}\" = \"${ENVPILOT_MANAGED_%s-}\" ]; then %s=%s; export ENVPILOT_MANAGED_%s=\"$%s\"; fi\n", k, k, k, k, Quote(env[k]), k, k)
			} else {
				fmt.Fprintf(&body, "%s=%s\n", k, Quote(env[k]))
			}
		}
	}

	if kind == "powershell" {
		fmt.Fprintf(&body, "$env:ENVPILOT_ROOT = %s\n", PSQuote(root))
		fmt.Fprintf(&body, "$EnvpilotExtraPaths = @(%s)\n", joinQuoted(c.Shell.Paths, PSQuote))
		fmt.Fprintf(&body, "$EnvpilotModules = @(%s)\n", joinQuoted(c.Shell.Modules, PSQuote))
		for _, k := range SortedKeys(c.Env) {
			fmt.Fprintf(&body, "$env:%s = %s\n", k, PSQuote(c.Env[k]))
		}
		return WriteAtomic(filepath.Join(dir, "config.ps1"), encodeProfile(body.String(), "utf8bom"), 0600)
	}
	fmt.Fprintf(&body, "ENVPILOT_ROOT=%s\n", Quote(root))
	fmt.Fprintf(&body, "ENVPILOT_EXTRA_PATHS=(%s)\n", joinShellQuoted(c.Shell.Paths))
	fmt.Fprintf(&body, "ENVPILOT_MODULES=(%s)\n", joinShellQuoted(c.Shell.Modules))
	for _, k := range SortedKeys(c.Env) {
		fmt.Fprintf(&body, "export %s=%s\n", k, Quote(c.Env[k]))
	}
	return WriteAtomic(filepath.Join(dir, "config.sh"), []byte(body.String()), 0600)
}
func joinShellQuoted(values []string) string {
	out := []string{}
	for _, value := range values {
		out = append(out, Quote(Expand(value)))
	}
	return strings.Join(out, " ")
}

func joinQuoted(values []string, q func(string) string) string {
	out := []string{}
	for _, v := range values {
		out = append(out, q(Expand(v)))
	}
	return strings.Join(out, ", ")
}
func ShellTarget(kind, override string) string {
	if override != "" {
		return Expand(override)
	}
	h, _ := os.UserHomeDir()
	if kind == "zsh" {
		return filepath.Join(h, ".zshrc")
	}
	if kind == "powershell" {
		return filepath.Join(h, "Documents", "PowerShell", "Microsoft.PowerShell_profile.ps1")
	}
	return filepath.Join(h, ".bashrc")
}
func stripBlock(data string) (string, error) {
	start := strings.Index(data, Begin)
	end := strings.Index(data, End)
	if start < 0 && end < 0 {
		return data, nil
	}
	if start < 0 || end < start || strings.Count(data, Begin) != 1 || strings.Count(data, End) != 1 {
		return data, fmt.Errorf("ambiguous envpilot markers; profile was preserved")
	}
	end += len(End)
	if strings.HasPrefix(data[end:], "\r\n") {
		end += 2
	} else if strings.HasPrefix(data[end:], "\n") {
		end++
	}
	return data[:start] + data[end:], nil
}
func InstallShell(c Config, root, kind, target string, remove bool) error {
	target = ShellTarget(kind, target)
	data, err := os.ReadFile(target)
	if err != nil && !os.IsNotExist(err) {
		return err
	}
	original, encoding := string(data), "raw"
	if kind == "powershell" {
		original, encoding, err = decodeProfile(data)
		if err != nil {
			return err
		}
	}
	text, err := stripBlock(original)
	if err != nil {
		return err
	}
	if !remove && strings.Contains(text, "managed by envpilot") {
		var hashes map[string][]string
		raw, e := os.ReadFile(filepath.Join(root, "compat", "profile-hashes.json"))
		if e != nil {
			return e
		}
		if e = json.Unmarshal(raw, &hashes); e != nil {
			return e
		}
		sum := sha256.Sum256([]byte(strings.ReplaceAll(text, "\r\n", "\n")))
		known := false
		for _, v := range hashes[kind] {
			if v == hex.EncodeToString(sum[:]) {
				known = true
			}
		}
		if !known {
			report := Text(c.Language, "Custom legacy profile preserved. Review migration before replacing it: ", "已保留含自定义修改的旧 profile；替换前请核对迁移：") + target + "\n"
			_ = WriteAtomic(filepath.Join(Dir(), "migration-pending.txt"), []byte(report), 0600)
			return fmt.Errorf("E_MIGRATION_PENDING: %s", strings.TrimSpace(report))
		}
		text = ""
	}
	if !remove {
		if err = Render(c, root, kind); err != nil {
			return err
		}
		name := "shell-init.sh"
		dest := "init.sh"
		if kind == "powershell" {
			name = "shell-init.ps1"
			dest = "init.ps1"
		}
		script, e := os.ReadFile(filepath.Join(root, "templates", name))
		if e != nil {
			return e
		}
		if e = WriteAtomic(filepath.Join(Dir(), "shell", dest), script, 0600); e != nil {
			return e
		}
		if text != "" && !strings.HasSuffix(text, "\n") {
			text += "\n"
		}
		p := filepath.Join(Dir(), "shell", dest)
		if kind == "powershell" {
			text += Begin + "\n$env:ENVPILOT_CONFIG_DIR = " + PSQuote(Dir()) + "\nif (Test-Path -LiteralPath " + PSQuote(p) + ") { . " + PSQuote(p) + " }\n" + End + "\n"
		} else {
			text += Begin + "\nENVPILOT_CONFIG_DIR=" + Quote(Dir()) + "\n[ ! -r " + Quote(p) + " ] || . " + Quote(p) + "\n" + End + "\n"
		}
	}
	if text == original {
		return nil
	}
	if len(data) > 0 {
		if err = WriteAtomic(target+".envpilot-backup-"+time.Now().UTC().Format("20060102T150405.000000000"), data, 0600); err != nil {
			return err
		}
	}
	mode := os.FileMode(0600)
	if st, e := os.Stat(target); e == nil {
		mode = st.Mode().Perm()
	}
	// Preserve symlinked dotfiles: update the target without replacing the symlink.
	if st, e := os.Lstat(target); e == nil && st.Mode()&os.ModeSymlink != 0 {
		target, err = filepath.EvalSymlinks(target)
		if err != nil {
			return err
		}
	}
	return WriteAtomic(target, encodeProfile(text, encoding), mode)
}

type SnapshotEntry struct {
	Path    string `json:"path"`
	Present bool   `json:"present"`
	Mode    uint32 `json:"mode"`
	Link    string `json:"link,omitempty"`
	File    string `json:"file,omitempty"`
}
type Snapshot struct {
	Version int             `json:"version"`
	Created string          `json:"created"`
	Entries []SnapshotEntry `json:"entries"`
	Note    string          `json:"note"`
}

func SnapshotCreate(c Config, extra []string) (string, error) {
	h, _ := os.UserHomeDir()
	paths := []string{filepath.Join(h, ".bashrc"), filepath.Join(h, ".zshrc"), filepath.Join(h, ".condarc"), filepath.Join(Dir(), "config.yaml"), filepath.Join(Dir(), "shell.local"), filepath.Join(Dir(), "command-root"), filepath.Join(h, ".local", "bin", "envpilot"), filepath.Join(h, ".local", "bin", "codex"), filepath.Join(h, ".local", "bin", "codex-remote"), filepath.Join(Expand(c.Codex.Home), "config.toml"), filepath.Join(Expand(c.Codex.Home), "auth.json"), filepath.Join(Dir(), "codex-source"), filepath.Join(Dir(), "core-path"), filepath.Join(Dir(), "state"), filepath.Join(Dir(), "state.ps1.txt"), filepath.Join(h, ".local", "bin", "envpilot.ps1"), Expand(c.Secrets.File), filepath.Join(h, ".config", "mihomo", "config.yaml"), filepath.Join(h, ".config", "mihomo", "subscription.url"), Expand(c.Mihomo.Subscription.File)}
	paths = append(paths, extra...)
	for _, name := range []string{"init.sh", "config.sh", "init.ps1", "config.ps1"} {
		paths = append(paths, filepath.Join(Dir(), "shell", name))
	}
	for _, name := range []string{"mihomo_common.sh", "start_mihomo.sh", "stop_mihomo.sh", "status_mihomo.sh", "update_mihomo_subscription.sh"} {
		paths = append(paths, filepath.Join(Expand(c.Install.Prefix), "mihomo", name))
	}
	for _, d := range []string{filepath.Join(Dir(), "shell"), filepath.Join(Expand(c.Install.Prefix), "mihomo")} {
		_ = filepath.WalkDir(d, func(p string, de os.DirEntry, e error) error {
			if e == nil && !de.IsDir() && (strings.HasSuffix(p, ".sh") || strings.HasSuffix(p, ".ps1")) {
				paths = append(paths, p)
			}
			return nil
		})
	}
	base := filepath.Join(Dir(), "snapshots")
	if err := os.MkdirAll(base, 0700); err != nil {
		return "", err
	}
	dir, err := os.MkdirTemp(base, time.Now().UTC().Format("20060102T150405.000000000")+"-")
	if err != nil {
		return "", err
	}
	if err := os.Mkdir(filepath.Join(dir, "files"), 0700); err != nil {
		return "", err
	}

	s := Snapshot{Version: 1, Created: time.Now().UTC().Format(time.RFC3339), Note: "Managed file snapshot; external package-manager transactions and sessions are not rolled back."}
	seen := map[string]bool{}
	for _, p := range paths {
		if p == "" || seen[p] {
			continue
		}
		seen[p] = true
		e := SnapshotEntry{Path: p}
		st, err := os.Lstat(p)
		if err != nil && !os.IsNotExist(err) {
			return "", err
		}
		if err == nil {
			e.Present = true
			e.Mode = uint32(st.Mode().Perm())
			if st.Mode()&os.ModeSymlink != 0 {
				e.Link, err = os.Readlink(p)
			} else if st.Mode().IsRegular() {
				var b []byte
				b, err = os.ReadFile(p)
				e.File = fmt.Sprintf("files/%d", len(s.Entries))
				if err == nil {
					err = WriteAtomic(filepath.Join(dir, e.File), b, 0600)
				}
			} else {
				continue
			}
			if err != nil {
				return "", err
			}
		}
		s.Entries = append(s.Entries, e)
	}
	b, _ := SafeJSON(s)
	if err := WriteAtomic(filepath.Join(dir, "snapshot.json"), b, 0600); err != nil {
		return "", err
	}
	if err := WriteAtomic(filepath.Join(Dir(), "latest-snapshot"), []byte(dir+"\n"), 0600); err != nil {
		return "", err
	}
	return dir, nil
}
func SnapshotRestore(path string, c Config) error {
	if path == "" {
		b, e := os.ReadFile(filepath.Join(Dir(), "latest-snapshot"))
		if e != nil {
			return e
		}
		path = strings.TrimSpace(string(b))
	}
	raw, e := os.ReadFile(filepath.Join(path, "snapshot.json"))
	if e != nil {
		return e
	}
	var s Snapshot
	if e = json.Unmarshal(raw, &s); e != nil {
		return e
	}
	if s.Version != 1 {
		return fmt.Errorf("unsupported snapshot")
	}
	// Resolve and read the complete restore set before changing any destination.
	type restoreItem struct {
		entry SnapshotEntry
		data  []byte
	}
	desired := []restoreItem{}
	previous := []restoreItem{}
	seen := map[string]bool{}
	for _, entry := range s.Entries {
		target, err := filepath.Abs(entry.Path)
		if err != nil {
			return err
		}
		if !safeSnapshotTarget(target, c) || seen[target] {
			return fmt.Errorf("unsafe or duplicate snapshot target: %s", target)
		}
		seen[target] = true
		entry.Path = target
		var data []byte
		if entry.Present && entry.Link == "" {
			if !regexp.MustCompile(`^files/[0-9]+$`).MatchString(entry.File) {
				return fmt.Errorf("invalid snapshot file")
			}
			data, err = os.ReadFile(filepath.Join(path, entry.File))
			if err != nil {
				return err
			}
		}
		old := SnapshotEntry{Path: target}
		var oldData []byte
		st, err := os.Lstat(target)
		if err != nil && !os.IsNotExist(err) {
			return err
		}
		if err == nil {
			old.Present = true
			old.Mode = uint32(st.Mode().Perm())
			if st.Mode()&os.ModeSymlink != 0 {
				old.Link, err = os.Readlink(target)
			} else if st.Mode().IsRegular() {
				oldData, err = os.ReadFile(target)
			} else {
				return fmt.Errorf("restore target is not a file: %s", target)
			}
			if err != nil {
				return err
			}
		}
		desired = append(desired, restoreItem{entry, data})
		previous = append(previous, restoreItem{old, oldData})
	}
	for i, item := range desired {
		if err := restoreFile(item.entry, item.data); err != nil {
			for j := i; j >= 0; j-- {
				if rollbackErr := restoreFile(previous[j].entry, previous[j].data); rollbackErr != nil {
					return fmt.Errorf("restore failed: %v; rollback failed at %s: %w", err, previous[j].entry.Path, rollbackErr)
				}
			}
			return err
		}
	}
	return nil
}

func restoreFile(entry SnapshotEntry, data []byte) error {
	if !entry.Present {
		err := os.Remove(entry.Path)
		if os.IsNotExist(err) {
			return nil
		}
		return err
	}
	if entry.Link != "" {
		if err := os.MkdirAll(filepath.Dir(entry.Path), 0700); err != nil {
			return err
		}
		if err := os.Remove(entry.Path); err != nil && !os.IsNotExist(err) {
			return err
		}
		return os.Symlink(entry.Link, entry.Path)
	}
	return WriteAtomic(entry.Path, data, os.FileMode(entry.Mode))
}

func resolvedLocation(path string) (string, error) {
	absolute, err := filepath.Abs(path)
	if err != nil {
		return "", err
	}
	parent, suffix := filepath.Dir(absolute), filepath.Base(absolute)
	for {
		resolved, err := filepath.EvalSymlinks(parent)
		if err == nil {
			return filepath.Join(resolved, suffix), nil
		}
		if !os.IsNotExist(err) || filepath.Dir(parent) == parent {
			return "", err
		}
		suffix = filepath.Join(filepath.Base(parent), suffix)
		parent = filepath.Dir(parent)
	}
}

func safeSnapshotTarget(path string, c Config) bool {
	resolved, err := resolvedLocation(path)
	if err != nil {
		return false
	}
	if c.SourcePath != "" {
		allowed, e := resolvedLocation(c.SourcePath)
		if e == nil && allowed == resolved {
			return true
		}
	}
	home, _ := os.UserHomeDir()
	for _, base := range []string{home, Expand(c.Install.Prefix), Dir()} {
		actual, e := filepath.EvalSymlinks(base)
		if e != nil {
			actual, e = resolvedLocation(base)
		}
		if e != nil {
			continue
		}
		rel, e := filepath.Rel(actual, resolved)
		if e == nil && rel != "." && rel != ".." && !strings.HasPrefix(rel, ".."+string(filepath.Separator)) {
			return true
		}
	}
	return false
}
