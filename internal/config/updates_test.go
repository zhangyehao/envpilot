package config

import (
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
	"time"
)

func TestUpdatePolicyDefaultsAndValidation(t *testing.T) {
	testHome(t)
	c := Defaults()
	if c.Updates.IntervalDays != 3 || !c.Updates.Enabled || c.Updates.AutoApply || len(c.Updates.Components) != len(Names) || !c.Updates.Envpilot {
		t.Fatalf("unexpected defaults: %+v", c.Updates)
	}
	for _, n := range []int{0, -1, 366} {
		c.Updates.IntervalDays = n
		if Validate(c) == nil {
			t.Fatalf("accepted interval %d", n)
		}
	}
	for _, sample := range []string{"config.example.en.yaml", "config.example.zh-CN.yaml"} {
		r, err := Load(filepath.Join("..", "..", "examples", sample), nil)
		if err != nil {
			t.Fatal(err)
		}
		if r.Config.Updates.IntervalDays != 3 {
			t.Fatal("sample drift")
		}
	}
}

func TestReferenceChoiceReplacesDefaults(t *testing.T) {
	testHome(t)
	path := filepath.Join(Dir(), "config.yaml")
	_ = WriteAtomic(path, []byte("codex:\n  api_key:\n    file: /protected/key\nmihomo:\n  subscription:\n    env: MIHOMO_SUBSCRIPTION_URL\n"), 0600)
	r, err := Load(path, nil)
	if err != nil {
		t.Fatal(err)
	}
	if r.Config.Codex.APIKey.Env != "" || r.Config.Mihomo.Subscription.File != "" {
		t.Fatal("reference retained default alternative")
	}
}

func TestUpdateSemanticComparison(t *testing.T) {
	for _, tc := range []struct {
		latest, current string
		newer           bool
	}{
		{"0.158.0", "0.99.0", true}, {"v0.4.4", "0.4.3", true},
		{"0.4.4", "0.4.4", false}, {"0.4.3", "0.4.4", false},
		{"0.158.0", "0.159.0-alpha.1", false}, {"dev", "0.4.3", false},
		{"0.4.4", "unknown", false}, {"999999999999999999999999.0.0", "1.0.0", false},
	} {
		if newerVersion(tc.latest, tc.current) != tc.newer {
			t.Fatalf("%+v", tc)
		}
	}
}

func TestUpdateIntervalCheckOnlyAndApply(t *testing.T) {
	testHome(t)
	c := Defaults()
	c.Updates.AutoApply = true
	c.Updates.Components = []string{"codex"}
	c.Updates.Timezone = "UTC"
	path := filepath.Join(Dir(), "config.yaml")
	now := time.Date(2026, 9, 29, 3, 0, 0, 0, time.UTC)
	versions := map[string]string{"codex": "0.156.1", "envpilot": "0.4.3"}
	latest := map[string]string{"codex": "0.158.0", "envpilot": "0.4.4"}
	calls, applied := 0, []string{}
	u := updateRunner{
		now:       func() time.Time { return now },
		installed: func(_ Config, _, component string) (string, error) { return versions[component], nil },
		latest:    func(_ Config, component string) (string, error) { calls++; return latest[component], nil },
		apply: func(_ Config, _, _, component string) error {
			applied = append(applied, component)
			versions[component] = latest[component]
			return nil
		},
	}
	state, err := u.run(c, ".", path, true)
	if err != nil || calls != 2 || len(applied) != 0 || state.Results[0].Status != "available" {
		t.Fatalf("check installed something: %+v, %v", state, err)
	}
	state, err = u.run(c, ".", path, false)
	if err != nil || !reflect.DeepEqual(applied, []string{"codex", "envpilot"}) || state.Results[0].Status != "updated" {
		t.Fatalf("apply failed: %+v, %v", state, err)
	}
	if !state.NextCheck.Equal(now.Add(72 * time.Hour)) {
		t.Fatal("interval is not exactly 3 days")
	}
	calls = 0
	now = now.Add(71 * time.Hour)
	_, _ = u.run(c, ".", path, false)
	if calls != 0 {
		t.Fatal("checked before due")
	}
	now = now.Add(time.Hour)
	_, _ = u.run(c, ".", path, false)
	if calls != 2 {
		t.Fatal("missed due check")
	}
}

func TestUpdateFailureOfflineDisabledAndVerification(t *testing.T) {
	for _, mode := range []string{"network", "install", "unchanged", "offline", "disabled", "missing", "beta"} {
		t.Run(mode, func(t *testing.T) {
			testHome(t)
			c := Defaults()
			c.Updates.AutoApply = true
			c.Updates.Components = []string{"codex"}
			c.Updates.Envpilot = false
			now := time.Date(2026, 9, 29, 3, 0, 0, 0, time.UTC)
			c.Updates.Timezone = "UTC"
			calls := 0
			u := updateRunner{
				now: func() time.Time { return now },
				installed: func(Config, string, string) (string, error) {
					if mode == "missing" {
						return "", nil
					}
					if mode == "beta" {
						return "0.160.0-alpha.1", nil
					}
					return "0.156.0", nil
				},
				latest: func(Config, string) (string, error) {
					calls++
					if mode == "network" {
						return "", errors.New("secret-token")
					}
					return "0.158.0", nil
				},
				apply: func(Config, string, string, string) error {
					if mode == "install" {
						return errors.New("secret-token")
					}
					return nil
				},
			}
			if mode == "offline" {
				c.Install.Mode = "offline"
			}
			if mode == "disabled" {
				c.Updates.Enabled = false
			}
			path := filepath.Join(Dir(), "config.yaml")
			state, err := u.run(c, ".", path, false)
			switch mode {
			case "offline", "disabled", "missing", "beta":
				if calls != 0 {
					t.Fatal("unwanted upstream request")
				}
				if mode == "offline" && err == nil {
					t.Fatal("offline check succeeded")
				}
			default:
				if err == nil || state.Results[0].Status != "failed" {
					t.Fatalf("false success: %+v %v", state, err)
				}
				if !state.NextCheck.Equal(now.Add(time.Hour)) {
					t.Fatal("failed update did not defer")
				}
				b, _ := os.ReadFile(updateStatePath(path))
				if strings.Contains(string(b), "secret-token") {
					t.Fatal("status leaked error contents")
				}
			}
		})
	}
}

func TestUpdateLockExcludesConcurrentCommandsAndReleases(t *testing.T) {
	testHome(t)
	if err := WithUpdateLock(func() error {
		returnErr := WithUpdateLock(func() error { t.Error("concurrent writer entered"); return nil })
		if !errors.Is(returnErr, ErrUpdateBusy) {
			t.Fatalf("lock did not reject: %v", returnErr)
		}
		return nil
	}); err != nil {
		t.Fatal(err)
	}
	if err := WithUpdateLock(func() error { return nil }); err != nil {
		t.Fatal("lock not released", err)
	}
}

func TestUpdateHTTPRetryAndReleaseValidation(t *testing.T) {
	for _, mode := range []string{"504-recovery", "sustained", "rate-limited", "prerelease", "stable"} {
		t.Run(mode, func(t *testing.T) {
			old := http.DefaultTransport
			t.Cleanup(func() { http.DefaultTransport = old })
			attempts := 0
			http.DefaultTransport = roundTripFunc(func(r *http.Request) (*http.Response, error) {
				attempts++
				if r.Header.Get("Authorization") != "" {
					t.Fatal("credentials on update request")
				}
				status, body, header := 200, `{"tag_name":"v0.4.4"}`, http.Header{}
				switch mode {
				case "504-recovery":
					if attempts == 1 {
						status = 504
						header.Set("Retry-After", "0")
					}
				case "sustained":
					status = 503
					header.Set("Retry-After", "0")
				case "rate-limited":
					status = 429
					header.Set("Retry-After", "120")
				case "prerelease":
					body = `{"tag_name":"v0.4.5","prerelease":true}`
				}
				return &http.Response{StatusCode: status, Header: header, Body: io.NopCloser(strings.NewReader(body))}, nil
			})
			v, err := latestUpdate(Defaults(), "envpilot")
			if mode == "stable" || mode == "504-recovery" {
				if err != nil || v != "0.4.4" {
					t.Fatal(v, err)
				}
			} else if err == nil {
				t.Fatal("bad release accepted")
			}
			if mode == "504-recovery" && attempts != 2 || mode == "sustained" && attempts != 3 || mode == "rate-limited" && attempts != 1 {
				t.Fatal("unbounded or incorrect retries", attempts)
			}
		})
	}
}

func TestCronManagedBlockPreservesJobs(t *testing.T) {
	original := "MAILTO=user@example.invalid\n0 2 * * * /home/user/backup\n"
	first, err := cronUpdateBlock(original, "/home/user name/.config/envpilot/updates/run.sh", true)
	if err != nil {
		t.Fatal(err)
	}
	second, err := cronUpdateBlock(first, "/home/user name/.config/envpilot/updates/run.sh", true)
	if err != nil || first != second {
		t.Fatal("scheduler registration not idempotent")
	}
	removed, err := cronUpdateBlock(second, "", false)
	if err != nil || removed != original {
		t.Fatal("removed user jobs")
	}
	for _, bad := range []string{"# >>> envpilot updates >>>\nx\n", "# <<< envpilot updates <<<\n"} {
		if _, err := cronUpdateBlock(bad, "/a", true); err == nil {
			t.Fatal("damaged crontab changed")
		}
	}
}

func TestShortenedUpdateInterval(t *testing.T) {
	testHome(t)
	path := filepath.Join(Dir(), "config.yaml")
	now := time.Now().UTC()
	state := UpdateState{LastAttempt: now.Add(-48 * time.Hour), NextCheck: now.Add(24 * time.Hour)}
	b, _ := json.Marshal(state)
	_ = WriteAtomic(updateStatePath(path), b, 0600)
	c := Defaults()
	c.Updates.IntervalDays = 1
	c.Updates.Components = nil
	c.Updates.Envpilot = false
	u := defaultUpdateRunner()
	u.now = func() time.Time { return now }
	state, err := u.run(c, ".", path, false)
	if err != nil || !state.LastAttempt.Equal(now) {
		t.Fatal("edited interval ignored", err)
	}
}
