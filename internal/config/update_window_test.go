package config

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestNightWindowBoundariesAndTimezone(t *testing.T) {
	u := Defaults().Updates
	u.Timezone = "Asia/Shanghai"
	for _, tc := range []struct {
		stamp  string
		inside bool
	}{
		{"2026-09-28T18:59:59Z", false}, // 02:59 Beijing
		{"2026-09-28T19:00:00Z", true},
		{"2026-09-28T20:59:59Z", true},
		{"2026-09-28T21:00:00Z", false},
	} {
		now, _ := time.Parse(time.RFC3339, tc.stamp)
		if inUpdateWindow(u, now) != tc.inside {
			t.Fatal(tc)
		}
		next := nextUpdateWindow(u, now)
		if !inUpdateWindow(u, next) || next.Before(now) {
			t.Fatal("invalid next window", next)
		}
	}
	u.WindowStart, u.WindowEnd = "23:00", "02:00"
	if !inUpdateWindow(u, time.Date(2026, 9, 28, 16, 0, 0, 0, time.UTC)) {
		t.Fatal("overnight window lost midnight")
	}
	u.Timezone = "America/New_York"
	u.WindowStart, u.WindowEnd = "02:30", "04:00"
	// The 02:30 wall clock does not exist on this DST transition.
	now, _ := time.Parse(time.RFC3339, "2026-03-08T06:59:00Z")
	if !inUpdateWindow(u, nextUpdateWindow(u, now)) {
		t.Fatal("DST gap not handled")
	}
}

func TestAutomaticUpdatesWaitUntilNight(t *testing.T) {
	testHome(t)
	c := Defaults()
	c.Updates.Components = []string{"codex"}
	c.Updates.Envpilot = false
	c.Updates.AutoApply = true
	c.Updates.Timezone = "Asia/Shanghai"
	now := time.Date(2026, 9, 29, 4, 0, 0, 0, time.UTC) // Noon Beijing.
	installed, applied := "0.156.0", 0
	u := updateRunner{
		now:       func() time.Time { return now },
		installed: func(Config, string, string) (string, error) { return installed, nil },
		latest:    func(Config, string) (string, error) { return "0.158.0", nil },
		apply:     func(Config, string, string, string) error { applied++; installed = "0.158.0"; return nil },
	}
	path := filepath.Join(Dir(), "config.yaml")
	state, err := u.run(c, ".", path, false)
	if err != nil || applied != 0 || state.Results[0].Status != "available" {
		t.Fatal("installed during daytime", state, err)
	}
	now = state.NextCheck.Add(-time.Second)
	_, _ = u.run(c, ".", path, false)
	if applied != 0 {
		t.Fatal("installed before window")
	}
	now = state.NextCheck
	state, err = u.run(c, ".", path, false)
	if err != nil || applied != 1 || state.Results[0].Status != "updated" {
		t.Fatal("missed night", state, err)
	}
}

func TestUpdateHistoryPreservesResultsAndIncompleteAttempts(t *testing.T) {
	home := testHome(t)
	root := filepath.Join(home, "repo")
	_ = os.MkdirAll(root, 0700)
	_ = os.WriteFile(filepath.Join(root, "VERSION"), []byte("0.4.3"), 0600)
	t.Setenv("ENVPILOT_UPDATE_ORIGIN", "automatic")
	id, err := BeginUpdateHistory(Defaults(), root, "envpilot")
	if err != nil {
		t.Fatal(err)
	}
	_ = os.WriteFile(filepath.Join(root, "VERSION"), []byte("0.4.4"), 0600)
	if err := FinishUpdateHistory(Defaults(), root, id, "0"); err != nil {
		t.Fatal(err)
	}
	p := filepath.Join(Dir(), "updates", "history", id)
	b, _ := os.ReadFile(p)
	var e UpdateHistoryEntry
	_ = json.Unmarshal(b, &e)
	if e.Before != "0.4.3" || e.After != "0.4.4" || e.Status != "updated" || e.Origin != "automatic" {
		t.Fatalf("%+v", e)
	}
	// Finishing a previous event twice must not rewrite its actual outcome.
	_ = FinishUpdateHistory(Defaults(), root, id, "1")
	after, _ := os.ReadFile(p)
	if string(after) != string(b) {
		t.Fatal("completed event overwritten")
	}
	incomplete, err := BeginUpdateHistory(Defaults(), root, "envpilot")
	if err != nil {
		t.Fatal(err)
	}
	b, _ = os.ReadFile(filepath.Join(Dir(), "updates", "history", incomplete))
	_ = json.Unmarshal(b, &e)
	if e.Status != "in_progress" {
		t.Fatal("interrupted operation fabricated as success")
	}
	if FinishUpdateHistory(Defaults(), root, "../escape", "0") == nil {
		t.Fatal("history traversal accepted")
	}
}
