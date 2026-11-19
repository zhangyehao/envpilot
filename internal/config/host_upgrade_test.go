package config

import (
	"bytes"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
	"time"
)

func TestPythonSymlinkActivationAndFailedRetry(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("Unix standalone installer")
	}
	base := t.TempDir()
	mk := func(name, target, body string) string {
		stage := filepath.Join(base, name)
		bin := filepath.Join(stage, "python", "bin")
		if err := os.MkdirAll(bin, 0700); err != nil {
			t.Fatal(err)
		}
		if body != "" {
			if err := os.WriteFile(filepath.Join(bin, "python3.15"), []byte(body), 0700); err != nil {
				t.Fatal(err)
			}
		}
		if err := os.Symlink(target, filepath.Join(bin, "python3")); err != nil {
			t.Fatal(err)
		}
		return stage
	}
	stage := mk("3.15.2.good", "python3.15", "#!/bin/sh\necho 3.15.2\n")
	if err := ActivatePython(base, stage, "3.15.2"); err != nil {
		t.Fatal(err)
	}
	current := filepath.Join(base, "current", "bin", "python3")
	old, err := filepath.EvalSymlinks(current)
	if err != nil {
		t.Fatal(err)
	}
	for _, bad := range []string{
		mk("3.15.2.escaping", old, ""),
		mk("3.15.2.broken", "missing", ""),
		mk("3.15.2.failed", "python3.15", "#!/bin/sh\nexit 2\n"),
		mk("3.15.2.different", "python3.15", "#!/bin/sh\necho 3.15.0\n"),
	} {
		if err := ActivatePython(base, bad, "3.15.2"); err == nil {
			t.Fatalf("activated %s", bad)
		}
		active, err := filepath.EvalSymlinks(current)
		if err != nil || active != old {
			t.Fatal(active, err)
		}
	}
}

func TestCondaProbeEnvironmentAndCodes(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("Unix version launcher")
	}
	dir := t.TempDir()
	t.Setenv("HOME", dir)
	t.Setenv("LD_LIBRARY_PATH", "sentinel")
	t.Setenv("PYTHONPATH", "broken")
	cfg := Defaults()
	cfg.Conda.Prefix = dir
	bin := filepath.Join(dir, "bin", "conda")
	if err := os.MkdirAll(filepath.Dir(bin), 0700); err != nil {
		t.Fatal(err)
	}
	write := func(body string) {
		t.Helper()
		if err := os.WriteFile(bin, []byte("#!/bin/sh\n"+body), 0700); err != nil {
			t.Fatal(err)
		}
	}
	// A real shared-filesystem probe took 11.14s. Exercise the command path
	// past the old ten-second deadline so lowering the limit fails this test.
	write("sleep 11\ntest -z \"$LD_LIBRARY_PATH$PYTHONPATH\" && test \"$CONDARC\" = \"$HOME/.condarc\" && echo 'conda 26.1.0'\n")
	got, err := installedComponent(cfg, "conda")
	if err != nil || got != "26.1.0" {
		t.Fatal(got, err)
	}
	for body, want := range map[string]string{"echo 'unparseable'": "E_UPDATE_PROBE_FORMAT", "exit 9": "E_UPDATE_PROBE_COMMAND"} {
		write(body)
		_, err := installedComponent(cfg, "conda")
		if err == nil || err.Error() != want {
			t.Fatal(err)
		}
	}
	write("exec sleep 2")
	if _, err := probeVersionOutput(bin, "--version", 30*time.Millisecond, true); err == nil || err.Error() != "E_UPDATE_PROBE_TIMEOUT" {
		t.Fatal(err)
	}
}

func TestPortableExportExcludesSecretsPathsAndOverrides(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "config.yaml")
	raw := "version: 1\nlanguage: en\ninstall:\n  prefix: /old/install\n  components: [conda, codex]\ncodex:\n  home: /old/credentials\n  base_url: https://example.invalid/?token=secret\nupdates:\n  interval_days: 7\nenv:\n  NOTE: do-not-copy\n"
	if err := os.WriteFile(path, []byte(raw), 0600); err != nil {
		t.Fatal(err)
	}
	t.Setenv("ENVPILOT_LANG", "zh-CN")
	data, err := PortableConfig(path)
	if err != nil {
		t.Fatal(err)
	}
	for _, bad := range []string{"secret", "old/", "do-not-copy", "zh-CN", "maintenance_host:"} {
		if bytes.Contains(data, []byte(bad)) {
			t.Fatalf("exported %s", bad)
		}
	}
	for _, good := range []string{"language: en", "interval_days: 7", "codex"} {
		if !bytes.Contains(data, []byte(good)) {
			t.Fatal(good)
		}
	}
	p := filepath.Join(dir, "config.toml")
	cfg := Defaults()
	cfg.Codex.Home = dir
	for _, src := range []string{"model='gpt-6'\nmodel_reasoning_effort='high'\n[model_providers.a]\nexperimental_bearer_token='secret'\n",
		"model='https://secret'\n", "model=\"name\\nsecret\"\n", "model='sk-test'\n", "invalid # secret"} {
		if err := os.WriteFile(p, []byte(src), 0600); err != nil {
			t.Fatal(err)
		}
		b, err := PortableCodexPreferences(cfg)
		if strings.HasPrefix(src, "model='gpt-6'") {
			if err != nil || strings.Contains(string(b), "secret") || !strings.Contains(string(b), "high") {
				t.Fatal(string(b), err)
			}
		} else if err == nil || strings.Contains(err.Error(), "secret") {
			t.Fatal(err)
		}
	}
}

func TestCondaPreviewRedactsChannelsAndShowsPlan(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("HOME", dir)
	t.Setenv("USERPROFILE", dir)
	a := filepath.Join(dir, ".condarc")
	b := filepath.Join(dir, "template")
	if os.WriteFile(a, []byte("channels: [https://secret.invalid]\nauto_activate_base: true\n"), 0600) != nil || os.WriteFile(b, []byte("channels: [defaults]\n"), 0600) != nil {
		t.Fatal("fixture")
	}
	var out bytes.Buffer
	if err := CondaPreview("condarc", b, nil, &out, "en"); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(out.String(), "~ channels") || !strings.Contains(out.String(), "- auto_activate_base") || strings.Contains(out.String(), "secret") {
		t.Fatal(out.String())
	}
	out.Reset()
	sample := "{\"success\":true,\"actions\":{\"LINK\":[{\"name\":\"conda\",\"version\":\"26.3\",\"channel\":\"https://secret.invalid\"}]}}"
	if err := CondaPreview("packages", "", strings.NewReader(sample), &out, "en"); err != nil || !strings.Contains(out.String(), "+ conda 26.3") || strings.Contains(out.String(), "secret") {
		t.Fatal(out.String(), err)
	}
}

func TestHomeMountLongestBoundary(t *testing.T) {
	if runtime.GOOS != "linux" {
		t.Skip("Linux mountinfo")
	}
	const mounts = "1 2 8:1 / / rw - ext4 /dev/root rw\n3 2 0:1 / /work/home rw - nfs4 server:/home rw\n4 2 0:2 / /work/home\\0402 rw - lustre h:/l rw"
	for p, want := range map[string]string{"/work/home/user": "nfs4", "/work/home-unrelated": "ext4", "/work/home 2/user": "lustre"} {
		if got := homeMountType(p, mounts); got != want {
			t.Fatal(p, got)
		}
	}
}
