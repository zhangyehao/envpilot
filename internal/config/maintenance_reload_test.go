package config

import (
	"bytes"
	"errors"
	"os"
	"path/filepath"
	"reflect"
	"runtime"
	"strings"
	"testing"
	"time"
)

func TestMaintenanceRechecksSavedPolicyBeforeStartingWork(t *testing.T) {
	testHome(t)
	const base = "updates:\n  auto_apply: true\n  components: [codex]\n  envpilot: false\n  timezone: UTC\n  models: {enabled: false}\n"
	for _, tc := range []struct {
		name                 string
		initial, replacement string
		duringProbe          bool
		wantErr              error
	}{
		{"component-off", base, base + "  policies: {codex: {auto_apply: false}}\n", false, errUpdateConfigChanged},
		{"subscription-off", base + "  subscription: {enabled: true}\n", base, true, errUpdateConfigChanged},
		{"invalid-after-check", base, "updates: [invalid\n", false, errUpdateConfigInvalid},
	} {
		t.Run(tc.name, func(t *testing.T) {
			path := filepath.Join(t.TempDir(), "custom.yaml")
			if err := os.WriteFile(path, []byte(tc.initial), 0600); err != nil {
				t.Fatal(err)
			}
			args := map[string]string{"ENVPILOT_PREFIX": filepath.Join(t.TempDir(), "override")}
			cfg, err := Load(path, args)
			if err != nil {
				t.Fatal(err)
			}
			changed := false
			save := func() {
				t.Helper()
				if !changed {
					if err := WriteAtomic(path, []byte(tc.replacement), 0600); err != nil {
						t.Fatal(err)
					}
					changed = true
				}
			}
			actions := []string{}
			u := updateRunner{
				now:          func() time.Time { return time.Date(2026, 11, 20, 3, 20, 0, 0, time.UTC) },
				verifyConfig: currentPolicyGuard(cfg.Config, path, args),
				installed: func(_ Config, _, n string) (string, error) {
					if tc.duringProbe && n == "mihomo" {
						save()
					}
					return "1.0.0", nil
				},
				latest: func(_ Config, n string) (string, error) {
					if !tc.duringProbe {
						save()
						return "1.1.0", nil
					}
					return "1.0.0", nil
				},
				apply: func(_ Config, _, _, n string) error { actions = append(actions, n); return nil },
				task:  func(_ Config, _, _, n string) error { actions = append(actions, n); return nil },
			}
			_, err = u.run(cfg.Config, ".", path, false)
			for _, n := range actions {
				if n != "codex-reconcile" || !tc.duringProbe {
					t.Fatalf("started stale work: %v", actions)
				}
			}
			if !changed || !errors.Is(err, tc.wantErr) {
				t.Fatalf("saved=%v err=%v", changed, err)
			}
			if tc.name == "component-off" {
				cfg, err = Load(path, args)
				if err != nil {
					t.Fatal(err)
				}
				u.verifyConfig = currentPolicyGuard(cfg.Config, path, args)
				st, err := u.run(cfg.Config, ".", path, false)
				if err != nil || len(actions) != 0 || st.Results[0].Status != "available" {
					t.Fatal(st, actions, err)
				}
			}
		})
	}
}

func TestLauncherUsesLivePathsAndPreservesCustomizations(t *testing.T) {
	h := testHome(t)
	current := filepath.Join(Dir(), "custom.yml")
	command := filepath.Join(h, ".local", "bin", "envpilot")
	canonical := launcherBody(h, current, command)
	path := scheduleLauncher()
	custom := "# site-specific launcher\n"
	if err := WriteAtomic(path, []byte(custom), 0700); err != nil {
		t.Fatal(err)
	}
	if err := installLauncher(path, canonical, "en"); err != nil {
		t.Fatal(err)
	}
	if err := installLauncher(path, canonical, "en"); err != nil {
		t.Fatal(err)
	}
	copies, _ := filepath.Glob(path + ".previous-*")
	if len(copies) != 1 {
		t.Fatal(copies)
	}
	backup, err := os.ReadFile(copies[0])
	if err != nil || string(backup) != custom {
		t.Fatal(err)
	}
	userBin := filepath.Join(h, "sites", "bin")
	if got := filepath.SplitList(scheduledPath(h, []string{userBin, userBin})); !reflect.DeepEqual(got, []string{h, userBin}) {
		t.Fatal(got)
	}
	if runtime.GOOS != "windows" {
		old := strings.Replace(canonical, "/usr/bin:/bin'", "/usr/bin:/bin:/old/site/bin'", 1)
		if old == canonical {
			t.Fatal("invalid test fixture")
		}
		if err := WriteAtomic(path, []byte(old), 0700); err != nil {
			t.Fatal(err)
		}
		if err := refreshScheduleLauncher(current); err != nil {
			t.Fatal(err)
		}
		updated, err := os.ReadFile(path)
		if err != nil || string(updated) != canonical {
			t.Fatal(string(updated), err)
		}
		if err := refreshScheduleLauncher(current); err != nil {
			t.Fatal(err)
		}
		copies, _ = filepath.Glob(path + ".previous-*")
		if len(copies) != 2 {
			t.Fatal(copies)
		}
	}
}

func TestDeletedConfigNeverStartsAutomaticWork(t *testing.T) {
	testHome(t)
	path := filepath.Join(t.TempDir(), "custom.yaml")
	if err := os.WriteFile(path, []byte("{}\n"), 0600); err != nil {
		t.Fatal(err)
	}
	args := map[string]string{"ENVPILOT_PREFIX": t.TempDir()}
	c, err := Load(path, args)
	if err != nil {
		t.Fatal(err)
	}
	check := currentPolicyGuard(c.Config, path, args)
	if err := os.Remove(path); err != nil {
		t.Fatal(err)
	}
	if err := check(false); !errors.Is(err, errUpdateConfigInvalid) {
		t.Fatal(err)
	}
	// Even removal before the guard was constructed cannot authorize a write.
	if err := currentPolicyGuard(c.Config, path, args)(true); !errors.Is(err, errUpdateConfigInvalid) {
		t.Fatal(err)
	}
}

func TestEditReportUsesOnlyFieldNamesAndEffectivePolicy(t *testing.T) {
	before := Defaults()
	before.Updates.AutoApply = true
	after := Defaults()
	after.Updates.AutoApply = true
	disabled := false
	after.Updates.Policies["git"] = ComponentPolicy{AutoApply: &disabled}
	after.Env["EXAMPLE"] = "private-value"
	after.Mihomo.Subscription = Reference{Env: "PRIVATE_REFERENCE"}
	got := changedConfigFields(before, after)
	want := []string{"env", "mihomo.subscription.env", "mihomo.subscription.file", "updates.policies.git.auto_apply"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("%v", got)
	}
	var out bytes.Buffer
	after.Language = "en"
	printEditPolicies(&out, before, after, false)
	if strings.TrimSpace(out.String()) != "git: check only, every 3 day(s)" {
		t.Fatal(out.String())
	}
}
