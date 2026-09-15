package config

import (
	"encoding/json"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

func TestRestorePreflightPreventsPartialChanges(t *testing.T) {
	home := testHome(t)
	target := filepath.Join(home, ".bashrc")
	_ = os.WriteFile(target, []byte("original"), 0600)
	snapshot, err := SnapshotCreate(Defaults(), nil)
	if err != nil {
		t.Fatal(err)
	}
	_ = os.WriteFile(target, []byte("current"), 0600)
	raw, _ := os.ReadFile(filepath.Join(snapshot, "snapshot.json"))
	var manifest Snapshot
	_ = json.Unmarshal(raw, &manifest)
	manifest.Entries = append(manifest.Entries, SnapshotEntry{Path: filepath.Join(t.TempDir(), "outside"), Present: false})
	raw, _ = json.Marshal(manifest)
	_ = os.WriteFile(filepath.Join(snapshot, "snapshot.json"), raw, 0600)
	if err = SnapshotRestore(snapshot, Defaults()); err == nil {
		t.Fatal("unsafe target accepted")
	}
	after, _ := os.ReadFile(target)
	if string(after) != "current" {
		t.Fatal("restore changed files before complete validation")
	}
}

func TestProbeVersionUsesServerVersion(t *testing.T) {
	version, err := ProbeVersion(map[string]any{"userAgent": "envpilot/0.154.0 (Ubuntu; x86_64) (envpilot; 0.4.0)"})
	if err != nil || version != "0.154.0" {
		t.Fatalf("wrong server version: %s, %v", version, err)
	}
}

func TestGeneratedEnvironmentDoesNotMaskEditedYAML(t *testing.T) {
	home := testHome(t)
	path := filepath.Join(home, "config.yaml")
	_ = os.WriteFile(path, []byte("mihomo:\n  proxy_port: 43000\n"), 0600)
	t.Setenv("MIHOMO_PROXY_PORT", "42290")
	t.Setenv("ENVPILOT_MANAGED_MIHOMO_PROXY_PORT", "42290")
	resolved, err := Load(path, nil)
	if err != nil || resolved.Config.Mihomo.ProxyPort != 43000 {
		t.Fatalf("generated environment masked YAML: %v", err)
	}
	t.Setenv("MIHOMO_PROXY_PORT", "44000")
	resolved, err = Load(path, nil)
	if err != nil || resolved.Config.Mihomo.ProxyPort != 44000 {
		t.Fatalf("explicit environment lost priority: %v", err)
	}
}

func testHome(t *testing.T) string {
	t.Helper()
	h := t.TempDir()
	t.Setenv("HOME", h)
	t.Setenv("USERPROFILE", h)
	t.Setenv("ENVPILOT_CONFIG_DIR", filepath.Join(h, ".config", "envpilot"))
	for _, k := range []string{"ENVPILOT_LANG", "ENVPILOT_MODE", "ENVPILOT_PREFIX", "CODEX_HOME", "MIHOMO_PROXY_PORT", "MIHOMO_API_PORT"} {
		t.Setenv(k, "")
		os.Unsetenv(k)
	}
	return h
}
func TestConfigurationBoundary(t *testing.T) {
	testHome(t)
	path := filepath.Join(Dir(), "config.yaml")
	if err := Init(path, "zh-CN"); err != nil {
		t.Fatal(err)
	}
	if err := Init(path, "en"); err == nil {
		t.Fatal("init overwrote existing configuration")
	}
	t.Setenv("ENVPILOT_PREFIX", "/environment")
	r, err := Load(path, map[string]string{"ENVPILOT_PREFIX": "/argument"})
	if err != nil {
		t.Fatal(err)
	}
	if r.Config.Install.Prefix != "/argument" || r.Sources["install.prefix"] != "argument" {
		t.Fatalf("wrong precedence: %+v", r)
	}
	if r.Config.Shell.Conda || r.Config.Shell.AutoStartProxy || r.Config.Shell.LegacyAliases {
		t.Fatal("fresh install enables intrusive integration")
	}
}
func TestInvalidYAMLDoesNotExecute(t *testing.T) {
	h := testHome(t)
	p := filepath.Join(h, "config.yaml")
	for _, body := range []string{"version: 2\n", "version: 1\nunknown: x\n", "version: 1\nversion: 1\n", "version: 1\n---\nversion: 1\n", "mihomo:\n  proxy_port: 80\n  api_port: 80\n", "env:\n  OPENAI_API_KEY: private\n"} {
		if err := os.WriteFile(p, []byte(body), 0600); err != nil {
			t.Fatal(err)
		}
		if _, err := Load(p, nil); err == nil {
			t.Fatalf("invalid YAML accepted: %s", body)
		}
	}
	if err := os.WriteFile(p, []byte("env:\n  LITERAL: '$(touch SHOULD_NOT_EXIST)'\n"), 0600); err != nil {
		t.Fatal(err)
	}
	r, err := Load(p, nil)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(r.Config.Env["LITERAL"], "$(touch") {
		t.Fatal("literal value was evaluated")
	}
}
func TestProfilePreservationAndIdempotence(t *testing.T) {
	h := testHome(t)
	root := t.TempDir()
	_ = os.MkdirAll(filepath.Join(root, "templates"), 0700)
	_ = os.WriteFile(filepath.Join(root, "templates", "shell-init.sh"), []byte("# managed initialization\n"), 0600)
	p := filepath.Join(h, ".bashrc")
	original := "# user's functions\nproxy_on() { echo original; }\nalias git='git -c color.ui=always'\n"
	_ = os.WriteFile(p, []byte(original), 0644)
	if err := InstallShell(Defaults(), root, "bash", p, false); err != nil {
		t.Fatal(err)
	}
	first, _ := os.ReadFile(p)
	if !strings.HasPrefix(string(first), original) {
		t.Fatal("user profile changed")
	}
	if err := InstallShell(Defaults(), root, "bash", p, false); err != nil {
		t.Fatal(err)
	}
	second, _ := os.ReadFile(p)
	if string(first) != string(second) {
		t.Fatal("repeated integration changed profile")
	}
	if err := InstallShell(Defaults(), root, "bash", p, true); err != nil {
		t.Fatal(err)
	}
	removed, _ := os.ReadFile(p)
	if string(removed) != original {
		t.Fatal("remove did not preserve user content")
	}
}
func TestSnapshotSurvivesSubsequentChanges(t *testing.T) {
	h := testHome(t)
	p := filepath.Join(h, ".bashrc")
	_ = os.WriteFile(p, []byte("original\n"), 0600)
	first, err := SnapshotCreate(Defaults(), nil)
	if err != nil {
		t.Fatal(err)
	}
	_ = os.WriteFile(p, []byte("changed\n"), 0600)
	second, err := SnapshotCreate(Defaults(), nil)
	if err != nil {
		t.Fatal(err)
	}
	if first == second {
		t.Fatal("snapshot overwritten")
	}
	if err = SnapshotRestore(first, Defaults()); err != nil {
		t.Fatal(err)
	}
	b, _ := os.ReadFile(p)
	if string(b) != "original\n" {
		t.Fatal("original snapshot lost")
	}
}
func TestProtectedEnvironmentIsData(t *testing.T) {
	h := testHome(t)
	p := filepath.Join(h, "api.env")
	_ = os.WriteFile(p, []byte("export OPENAI_API_KEY='fixture-secret'\nOTHER=literal\n"), 0600)
	values, err := ReadEnvironment(p)
	if err != nil {
		t.Fatal(err)
	}
	if values["OPENAI_API_KEY"] != "fixture-secret" {
		t.Fatal("wrong secret")
	}
	_ = os.WriteFile(p, []byte("export KEY=$(touch unsafe)\n"), 0600)
	if _, err = ReadEnvironment(p); err == nil {
		t.Fatal("executable syntax accepted")
	}
	if runtime.GOOS != "windows" {
		_ = os.Chmod(p, 0644)
		if _, err = ReadEnvironment(p); err == nil {
			t.Fatal("insecure permissions accepted")
		}
	}
}
