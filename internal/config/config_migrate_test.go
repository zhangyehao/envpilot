package config

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestMigrateStoredDefaultsWithEnvironmentAndAlternativeReferences(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("ENVPILOT_CONFIG_DIR", dir)
	t.Setenv("HOME", dir)
	t.Setenv("USERPROFILE", dir)
	t.Setenv("MIHOMO_API_PORT", "44002")
	path := filepath.Join(dir, "config.yaml")
	old := "# operator's note\nversion: 1\nmihomo:\n  subscription: {env: PRIVATE_SUBSCRIPTION_REF}\n  proxy_port: 41001 # site port\ncodex:\n  api_key: {file: '~/private/custom.key'}\nupdates:\n  auto_apply: false\n"
	if err := os.WriteFile(path, []byte(old), 0600); err != nil {
		t.Fatal(err)
	}
	load := func() Resolved {
		t.Helper()
		r, err := Load(path, nil)
		if err != nil {
			t.Fatal(err)
		}
		return r
	}
	var preview bytes.Buffer
	if err := MigrateConfig(load(), false, &preview); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(preview.String(), "mihomo.api_port = 44002 (environment:MIHOMO_API_PORT)") || strings.Contains(preview.String(), "PRIVATE_SUBSCRIPTION_REF") {
		t.Fatal(preview.String())
	}
	if data, _ := os.ReadFile(path); string(data) != old {
		t.Fatal("preview changed YAML")
	}
	if _, err := os.Stat(filepath.Join(dir, "latest-snapshot")); !os.IsNotExist(err) {
		t.Fatal("preview created a snapshot")
	}
	var applied bytes.Buffer
	if err := MigrateConfig(load(), true, &applied); err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	for _, want := range []string{"# operator's note", "# site port", "PRIVATE_SUBSCRIPTION_REF", "custom.key", "api_port: 60290", "maintenance_host:"} {
		if !strings.Contains(string(data), want) {
			t.Fatalf("missing %q", want)
		}
	}
	snapshot, _ := os.ReadFile(filepath.Join(dir, "latest-snapshot"))
	if len(snapshot) == 0 {
		t.Fatal("no restore point")
	}
	applied.Reset()
	if err := MigrateConfig(load(), true, &applied); err != nil {
		t.Fatal(err)
	}
	again, _ := os.ReadFile(path)
	snapshot2, _ := os.ReadFile(filepath.Join(dir, "latest-snapshot"))
	if !bytes.Equal(again, data) || !bytes.Equal(snapshot, snapshot2) {
		t.Fatal("second migration rewrote config or restore point")
	}
}

func TestCommandCandidates(t *testing.T) {
	if got := CommandCandidates([]string{"mihomo"}, "up", false); len(got) != 1 || got[0] != "update-subscription" {
		t.Fatal(got)
	}
	if got := CommandCandidates(nil, "updaet", true); len(got) == 0 || got[0] != "update" {
		t.Fatal(got)
	}
	if got := CommandCandidates([]string{"run", "--"}, "", false); len(got) != 0 {
		t.Fatal(got)
	}
}
