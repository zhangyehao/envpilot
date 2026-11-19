package config

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// A provider failure retains the last successful IDs and timestamp. A failed
// retry changes only checked_at and therefore must not generate a notification.
func TestCodexModelHistoryPreservesLastSuccess(t *testing.T) {
	old := mergeObservation(catalogObservation{}, catalogObservation{Status: "ok", Models: []modelEntry{{ID: "one", Hidden: true}}}, "yesterday")
	failed := mergeObservation(old, catalogObservation{Status: "http_503"}, "today")
	if failed.LastSuccess != "yesterday" || len(failed.Models) != 1 || !failed.Models[0].Hidden {
		t.Fatal(failed)
	}
	if equal := withoutTimes(modelState{Checked: "today", Provider: failed}); equal.Checked != "" || equal.Provider.LastSuccess != "" {
		t.Fatal(equal)
	}
}
func TestProviderModelsUsesSelectedKeyAndDoesNotFollowRedirect(t *testing.T) {
	c := Defaults()
	c.Codex.Home = t.TempDir()
	c.Secrets.File = ""
	c.Codex.APIKey = Reference{}
	t.Setenv("SELECTED_TEST_API_KEY", "secret-fixture")
	hits := 0
	redirected := false
	redirect := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { redirected = true }))
	defer redirect.Close()
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		hits++
		if r.URL.Path != "/v1/models" || r.Header.Get("Authorization") != "Bearer secret-fixture" {
			t.Error("invalid path or missing selected credential")
		}
		if hits == 2 {
			http.Redirect(w, r, redirect.URL, http.StatusFound)
			return
		}
		fmt.Fprint(w, `{"data":[{"id":"z-1"},{"id":"a-1"}]}`)
	}))
	defer server.Close()
	data := fmt.Sprintf("model_provider = 'example'\n[model_providers.example]\nbase_url = %q\nenv_key = 'SELECTED_TEST_API_KEY'\n", server.URL+"/v1")
	if err := os.WriteFile(filepath.Join(c.Codex.Home, "config.toml"), []byte(data), 0600); err != nil {
		t.Fatal(err)
	}
	_, provider, status := readProvider(c)
	if status != "" {
		t.Fatal(status)
	}
	got := providerModels(c, provider)
	if got.Status != "ok" || len(got.Models) != 2 || got.Models[0].ID != "a-1" {
		t.Fatal(got)
	}
	got = providerModels(c, provider)
	if redirected || got.Status != "http_302" {
		t.Fatal("redirect followed or hidden")
	}
	b, _ := json.Marshal(got)
	if strings.Contains(string(b), "secret-fixture") {
		t.Fatal("leaked credential")
	}
}
