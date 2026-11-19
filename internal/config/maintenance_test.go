package config

import (
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"runtime"
	"strings"
	"testing"
	"time"
)

func TestIndependentComponentCadenceAndSuccess(t *testing.T) {
	testHome(t)
	c := Defaults()
	c.Updates.Timezone = "UTC"
	c.Updates.Components = []string{"codex", "conda"}
	c.Updates.Envpilot = false
	day, automatic := 1, true
	c.Updates.Policies["codex"] = ComponentPolicy{IntervalDays: &day, AutoApply: &automatic}
	path := filepath.Join(Dir(), "config.yaml")
	now := time.Date(2026, 11, 20, 3, 20, 0, 0, time.UTC)
	versions := map[string]string{"codex": "1.0.0"}
	calls := map[string]int{}
	u := updateRunner{now: func() time.Time { return now }, installed: func(_ Config, _, n string) (string, error) {
		calls[n]++
		if n == "conda" {
			return "", errors.New("E_UPDATE_PROBE_TIMEOUT")
		}
		return versions[n], nil
	}, latest: func(Config, string) (string, error) { return "1.1.0", nil }, apply: func(Config, string, string, string) error { versions["codex"] = "1.1.0"; return nil }}
	st, err := u.run(c, ".", path, false)
	if err == nil || st.Results[0].Status != "updated" || !st.Results[0].LastSuccess.Equal(now) || !st.Results[0].LastApplied.Equal(now) || st.Results[1].ErrorCode != "E_UPDATE_PROBE_TIMEOUT" || !st.Results[1].LastSuccess.IsZero() {
		t.Fatal(st, err)
	}
	now = now.Add(time.Hour)
	before := calls["codex"]
	st, err = u.run(c, ".", path, false)
	if err == nil || calls["codex"] != before || !st.Results[0].NextCheck.Equal(now.Add(23*time.Hour)) || !st.Results[0].LastSuccess.Equal(now.Add(-time.Hour)) {
		t.Fatal(st, err, calls)
	}
}

func TestRefreshesRespectModeWindowHostAndOwnInterval(t *testing.T) {
	testHome(t)
	c := Defaults()
	c.Updates.Components = nil
	c.Updates.Envpilot = false
	c.Updates.Subscription = RefreshPolicy{true, 1}
	c.Updates.Timezone = "UTC"
	start, end := "18:20", "18:25"
	c.Updates.Policies["mihomo"] = ComponentPolicy{WindowStart: &start, WindowEnd: &end}
	path := filepath.Join(Dir(), "config.yaml")
	now := time.Date(2026, 11, 20, 18, 21, 0, 0, time.UTC)
	calls := []string{}
	u := updateRunner{now: func() time.Time { return now }, installed: func(Config, string, string) (string, error) { return "1.0.0", nil }, task: func(_ Config, _, _, name string) error { calls = append(calls, name); return nil }}
	st, err := u.run(c, ".", path, true)
	if err != nil || !reflect.DeepEqual(calls, []string{"models"}) {
		t.Fatal(st, err, calls)
	}
	c.Updates.MaintenanceHost = "different.example.invalid"
	st, err = u.run(c, ".", path, false)
	if err != nil || st.Results[1].Status != "other_host" || len(calls) != 1 {
		t.Fatal(st, err, calls)
	}
	c.Updates.MaintenanceHost = ""
	now = now.Add(time.Hour)
	st, err = u.run(c, ".", path, false)
	if err != nil || len(calls) != 1 || st.Results[1].NextCheck.Format("15:04") != "18:20" {
		t.Fatal(st, err, calls)
	}
	now = st.Results[1].NextCheck
	st, err = u.run(c, ".", path, false)
	if err != nil || !reflect.DeepEqual(calls, []string{"models", "subscription"}) || !st.Results[1].LastApplied.Equal(now) {
		t.Fatal(st, err, calls)
	}
	now = now.Add(time.Minute)
	_, err = u.run(c, ".", path, false)
	if err != nil || len(calls) != 2 {
		t.Fatal(err, calls)
	}
}

func TestMaintenanceHostAndPolicyInheritance(t *testing.T) {
	c := Defaults()
	if !maintenanceOwner("login02", "login02.hpc") || maintenanceOwner("login02.b", "login02.a") || maintenanceOwner("login", "login02") {
		t.Fatal("host comparison")
	}
	for _, v := range []string{"unknown", "subscription"} {
		c.Updates.Policies[v] = ComponentPolicy{}
		if Validate(c) == nil {
			t.Fatal("unknown component", v)
		}
		delete(c.Updates.Policies, v)
	}
	c.Updates.AutoApply = true
	f := false
	c.Updates.Policies["conda"] = ComponentPolicy{AutoApply: &f}
	if c.Updates.forComponent("conda").AutoApply || !c.Updates.forComponent("python").AutoApply {
		t.Fatal("explicit false or inherited default lost")
	}
	c.Updates.Subscription.IntervalDays = 0
	if Validate(c) == nil {
		t.Fatal("zero interval accepted")
	}
}

func TestCodexStagedUpdateRetriesSwitchWithoutReinstall(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("Unix app-server lifecycle")
	}
	testHome(t)
	c := Defaults()
	c.Updates.Components = []string{"codex"}
	c.Updates.Envpilot = false
	c.Updates.Models.Enabled = false
	c.Updates.Timezone = "UTC"
	c.Updates.AutoApply = true
	path := filepath.Join(Dir(), "config.yaml")
	now := time.Date(2026, 11, 20, 3, 10, 0, 0, time.UTC)
	version := "1.0.0"
	installs, switches := 0, 0
	busy := exec.Command("/bin/sh", "-c", "exit 75").Run()
	u := updateRunner{now: func() time.Time { return now }, installed: func(Config, string, string) (string, error) { return version, nil }, latest: func(Config, string) (string, error) { return "1.1.0", nil },
		apply: func(Config, string, string, string) error { installs++; version = "1.1.0"; return busy },
		task: func(_ Config, _, _, name string) error {
			if name != "codex-reconcile" {
				t.Fatal(name)
			}
			switches++
			return nil
		}}
	state, err := u.run(c, ".", path, false)
	if err != nil || state.Results[0].Status != "deferred" || !state.Results[0].LastApplied.IsZero() {
		t.Fatal(state, err)
	}
	now = now.Add(30 * time.Minute)
	state, err = u.run(c, ".", path, true)
	if err != nil || !state.Results[0].PendingSwitch || switches != 0 {
		t.Fatal(state, err, switches)
	}
	now = state.Results[0].NextCheck
	state, err = u.run(c, ".", path, false)
	if err != nil || installs != 1 || switches != 1 || state.Results[0].Status != "updated" || !state.Results[0].LastApplied.Equal(now) {
		t.Fatal(state, err, installs, switches)
	}
}

func TestDoctorChecksCronAndRecordsOnlySchedulerTrigger(t *testing.T) {
	if runtime.GOOS != "linux" {
		t.Skip("Linux crontab fixture")
	}
	home := testHome(t)
	path := filepath.Join(Dir(), "config.yaml")
	bin := filepath.Join(home, "fixture-bin")
	t.Setenv("PATH", bin)
	if err := WriteAtomic(filepath.Join(bin, "crontab"), []byte("#!/bin/sh\n/bin/cat \"$HOME/table\"\n"), 0700); err != nil {
		t.Fatal(err)
	}
	launcher := legacyScheduleLauncher()
	cmd := filepath.Join(home, ".local", "bin", "envpilot")
	_ = WriteAtomic(launcher, []byte("#!/bin/bash\nexec "+Quote(cmd)+" updates run --config "+Quote(path)+"\n"), 0700)
	_ = WriteAtomic(filepath.Join(Dir(), "updates", "scheduler"), []byte("cron\n"), 0600)
	_ = WriteAtomic(filepath.Join(home, "table"), []byte("0 0 * * * true\n"), 0600)
	if s := inspectScheduler(path, time.Now()); s.Registration != "absent" || s.TriggerState != "never" {
		t.Fatal(s)
	}
	body, err := cronUpdateBlock("", launcher, true)
	if err != nil {
		t.Fatal(err)
	}
	_ = WriteAtomic(filepath.Join(home, "table"), []byte(body), 0600)
	if s := inspectScheduler(path, time.Now()); s.Registration != "legacy_launcher" {
		t.Fatal(s)
	}
	if err = refreshScheduleLauncher(path); err != nil {
		t.Fatal(err)
	}
	c := Defaults()
	c.Updates.Enabled = false
	if err = UpdatesCommand(c, ".", path, "run", "json", nil); err != nil {
		t.Fatal(err)
	}
	if s := inspectScheduler(path, time.Now()); s.Registration != "registered" || !s.LastTrigger.IsZero() {
		t.Fatal(s)
	}
	if err = UpdatesCommand(c, ".", path, "tick", "json", nil); err != nil {
		t.Fatal(err)
	}
	if s := inspectScheduler(path, time.Now()); s.TriggerState != "recent" || s.LastOutcome != "disabled" {
		t.Fatal(s)
	}
	b, _ := os.ReadFile(launcher)
	if !strings.Contains(string(b), "updates tick --config") {
		t.Fatal(string(b))
	}
}
