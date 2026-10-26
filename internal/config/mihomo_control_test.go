package config

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
)

// Protocol fixtures are HTTP servers in the test process, not managed Mihomo
// executables. Only these tests substitute the OS owner check.
func mihomoFixtureCommand(c Config, action string, args []string, format string, input io.Reader, output io.Writer, interactive bool) error {
	return mihomoCommandCheckedIO(c, action, args, format, input, output, interactive, func(context.Context) error { return nil })
}

type fakeMihomoController struct {
	mu        sync.Mutex
	proxies   map[string]mihomoProxy
	secret    string
	ignorePut bool
	fail      bool
	putCount  int
	paths     []string
}

func (m *fakeMihomoController) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.paths = append(m.paths, r.URL.EscapedPath())
	if m.secret != "" && r.Header.Get("Authorization") != "Bearer "+m.secret {
		http.Error(w, "synthetic-private-secret", http.StatusUnauthorized)
		return
	}
	if m.fail {
		http.Error(w, "synthetic-private-response", http.StatusServiceUnavailable)
		return
	}
	if r.URL.Path == "/version" {
		_ = json.NewEncoder(w).Encode(map[string]any{"version": "test"})
		return
	}
	if r.URL.Path == "/proxies" {
		_ = json.NewEncoder(w).Encode(map[string]any{"proxies": m.proxies})
		return
	}
	name := strings.TrimPrefix(r.URL.Path, "/proxies/")
	if strings.HasSuffix(name, "/delay") {
		name = strings.TrimSuffix(name, "/delay")
		if name == "bad" {
			http.Error(w, "timeout secret", http.StatusGatewayTimeout)
			return
		}
		_ = json.NewEncoder(w).Encode(map[string]int{"delay": 25})
		return
	}
	p, ok := m.proxies[name]
	if !ok {
		http.NotFound(w, r)
		return
	}
	if r.Method == http.MethodPut {
		var choice struct {
			Name string `json:"name"`
		}
		if json.NewDecoder(r.Body).Decode(&choice) != nil || !mihomoContains(p.All, choice.Name) {
			http.Error(w, "bad member", 400)
			return
		}
		m.putCount++
		if !m.ignorePut {
			p.Now = choice.Name
			m.proxies[name] = p
		}
		w.WriteHeader(http.StatusNoContent)
		return
	}
	_ = json.NewEncoder(w).Encode(p)
}

func setupMihomoController(t *testing.T, secret string) (Config, *fakeMihomoController) {
	t.Helper()
	h := testHome(t)
	t.Setenv("MIHOMO_RUNTIME_DIR", "")
	t.Setenv("MIHOMO_SOURCE_CONFIG", "")
	if err := WriteAtomic(filepath.Join(h, ".config", "mihomo", "config.yaml"), []byte(fmt.Sprintf("secret: %q\n", secret)), 0600); err != nil {
		t.Fatal(err)
	}
	fake := &fakeMihomoController{
		secret: secret,
		proxies: map[string]mihomoProxy{
			"烟火云/选择": {Name: "烟火云/选择", Type: "Selector", Now: "🇺🇸 美国 · 01", All: []string{"🇺🇸 美国 · 01", "🇯🇵 日本 · 02", "自动选择", "bad"}},
			"自动选择":   {Name: "自动选择", Type: "URLTest", Now: "🇺🇸 美国 · 01", All: []string{"🇺🇸 美国 · 01"}},
			"GLOBAL": {Name: "GLOBAL", Type: "Selector", Now: "DIRECT", All: []string{"DIRECT", "烟火云/选择"}},
		},
	}
	server := httptest.NewServer(fake)
	t.Cleanup(server.Close)
	u, _ := url.Parse(server.URL)
	port, _ := strconv.Atoi(u.Port())
	c := Defaults()
	c.Language = "en"
	c.Mihomo.APIPort = port
	return c, fake
}

func TestMihomoSelectUnicodeSecretAndPersistentRestore(t *testing.T) {
	c, fake := setupMihomoController(t, "synthetic-private-secret")
	var output bytes.Buffer
	err := mihomoFixtureCommand(c, "select", []string{"烟火云/选择", "🇯🇵 日本 · 02"}, "json", nil, &output, false)
	if err != nil {
		t.Fatal(err)
	}
	var selected mihomoSelectionResult
	if err := json.Unmarshal(output.Bytes(), &selected); err != nil || selected.Node != "🇯🇵 日本 · 02" {
		t.Fatalf("selection output: %s / %v", output.Bytes(), err)
	}
	path, _, err := mihomoSelectionPath(c)
	if err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(path)
	if err != nil || bytes.Contains(data, []byte(fake.secret)) {
		t.Fatalf("state not safe: %v", err)
	}
	if info, err := os.Stat(path); err != nil || (runtime.GOOS != "windows" && info.Mode().Perm() != 0600) {
		t.Fatalf("state mode: %v / %v", info, err)
	}
	fake.mu.Lock()
	p := fake.proxies["烟火云/选择"]
	p.Now = "🇺🇸 美国 · 01" // a fresh runtime loses its in-memory/cache choice
	fake.proxies["烟火云/选择"] = p
	encoded := false
	for _, path := range fake.paths {
		if strings.Contains(path, "%E7%83%9F") && strings.Contains(path, "%2F") {
			encoded = true
		}
	}
	fake.mu.Unlock()
	if !encoded {
		t.Fatal("group name was not correctly URL-escaped")
	}
	output.Reset()
	if err = mihomoFixtureCommand(c, "selection-restore", nil, "json", nil, &output, false); err != nil {
		t.Fatal(err)
	}
	fake.mu.Lock()
	defer fake.mu.Unlock()
	if fake.proxies["烟火云/选择"].Now != "🇯🇵 日本 · 02" {
		t.Fatal("saved choice not restored")
	}
}

func TestMihomoInputAndGroupValidation(t *testing.T) {
	c, fake := setupMihomoController(t, "")
	for _, tc := range []struct {
		args        []string
		input       string
		interactive bool
		code        string
	}{
		{nil, "", false, "E_INPUT_REQUIRED"},
		{nil, "", true, "E_INPUT_REQUIRED"},
		{nil, "0\n", true, "E_CANCELLED"},
		{nil, "999", true, "E_INPUT_REQUIRED"},
		{[]string{"自动选择", "🇺🇸 美国 · 01"}, "", false, "E_MIHOMO_GROUP"},
		{[]string{"烟火云/选择", "missing"}, "", false, "E_MIHOMO_NODE"},
	} {
		var output bytes.Buffer
		err := mihomoFixtureCommand(c, "select", tc.args, "text", strings.NewReader(tc.input), &output, tc.interactive)
		if err == nil || !strings.Contains(err.Error(), tc.code) {
			t.Fatalf("args=%q input=%q error=%v", tc.args, tc.input, err)
		}
	}
	if fake.putCount != 0 {
		t.Fatal("invalid input changed selection")
	}
	var output bytes.Buffer
	if err := mihomoFixtureCommand(c, "select", nil, "text", strings.NewReader("oops\n2\n"), &output, true); err != nil {
		t.Fatal(err)
	}
	if fake.proxies["烟火云/选择"].Now != "🇯🇵 日本 · 02" {
		t.Fatal("numbered choice failed")
	}
}

func TestMihomoMoreThanOneGroupRequiresExplicitChoice(t *testing.T) {
	c, fake := setupMihomoController(t, "")
	fake.proxies["other"] = mihomoProxy{Name: "other", Type: "Selector", Now: "A", All: []string{"A", "B"}}
	var output bytes.Buffer
	err := mihomoFixtureCommand(c, "test", nil, "text", nil, &output, false)
	if err == nil || !strings.Contains(err.Error(), "E_INPUT_REQUIRED") {
		t.Fatalf("ambiguous group: %v", err)
	}
	// Alphabetical ordering puts "other" first. The second input picks B.
	if err = mihomoFixtureCommand(c, "select", nil, "text", strings.NewReader("1\n2\n"), &output, true); err != nil {
		t.Fatal(err)
	}
	if fake.proxies["other"].Now != "B" {
		t.Fatal("interactive group selection failed")
	}
}

func TestMihomoRestoreMissingNodePreservesLiveAndSavedChoice(t *testing.T) {
	c, fake := setupMihomoController(t, "")
	if err := mihomoFixtureCommand(c, "select", []string{"烟火云/选择", "🇯🇵 日本 · 02"}, "json", nil, io.Discard, false); err != nil {
		t.Fatal(err)
	}
	path, _, _ := mihomoSelectionPath(c)
	before, _ := os.ReadFile(path)
	fake.mu.Lock()
	p := fake.proxies["烟火云/选择"]
	p.Now, p.All = "🇺🇸 美国 · 01", []string{"🇺🇸 美国 · 01"}
	fake.proxies["烟火云/选择"] = p
	fake.mu.Unlock()
	var output bytes.Buffer
	if err := mihomoFixtureCommand(c, "selection-restore", nil, "json", nil, &output, false); err != nil {
		t.Fatal(err)
	}
	var result mihomoRestoreResult
	if err := json.Unmarshal(output.Bytes(), &result); err != nil || len(result.Skipped) != 1 || len(result.Restored) != 0 {
		t.Fatalf("restore report: %s / %v", output.Bytes(), err)
	}
	after, _ := os.ReadFile(path)
	if !bytes.Equal(before, after) || fake.proxies["烟火云/选择"].Now != "🇺🇸 美国 · 01" {
		t.Fatal("missing member altered live or saved choice")
	}
}

func TestMihomoSaveFailureAndVerificationDoNotOverwriteState(t *testing.T) {
	c, fake := setupMihomoController(t, "")
	if err := mihomoFixtureCommand(c, "selection-save", nil, "text", nil, io.Discard, false); err != nil {
		t.Fatal(err)
	}
	path, _, _ := mihomoSelectionPath(c)
	before, _ := os.ReadFile(path)
	fake.fail = true
	if err := mihomoFixtureCommand(c, "selection-save", nil, "text", nil, io.Discard, false); err == nil {
		t.Fatal("broken controller was accepted")
	}
	fake.fail = false
	fake.ignorePut = true
	err := mihomoFixtureCommand(c, "select", []string{"烟火云/选择", "🇯🇵 日本 · 02"}, "json", nil, io.Discard, false)
	if err == nil || !strings.Contains(err.Error(), "E_MIHOMO_SELECTION_VERIFY") {
		t.Fatalf("unconfirmed PUT: %v", err)
	}
	after, _ := os.ReadFile(path)
	if !bytes.Equal(before, after) {
		t.Fatal("failure overwrote saved selections")
	}
}

func TestMihomoConcurrentSelectsKeepStateAndAPIConsistent(t *testing.T) {
	c, fake := setupMihomoController(t, "")
	var workers sync.WaitGroup
	failures := make(chan error, 10)
	for i := 0; i < 10; i++ {
		workers.Add(1)
		go func(i int) {
			defer workers.Done()
			node := "🇺🇸 美国 · 01"
			if i%2 == 0 {
				node = "🇯🇵 日本 · 02"
			}
			failures <- mihomoFixtureCommand(c, "select", []string{"烟火云/选择", node}, "json", nil, io.Discard, false)
		}(i)
	}
	workers.Wait()
	close(failures)
	for err := range failures {
		if err != nil {
			t.Fatal(err)
		}
	}
	state, exists, err := mihomoReadSelections(c)
	if err != nil || !exists {
		t.Fatalf("read state: exists=%t error=%v", exists, err)
	}
	fake.mu.Lock()
	defer fake.mu.Unlock()
	if state.Selections["烟火云/选择"] != fake.proxies["烟火云/选择"].Now {
		t.Fatal("persisted choice disagrees with serialized controller changes")
	}
}

func TestMihomoHealthUsesSecretAndBypassesEnvironmentProxy(t *testing.T) {
	c, fake := setupMihomoController(t, "synthetic-private-secret")
	var intercepted atomic.Int32
	proxy := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		intercepted.Add(1)
		http.Error(w, "unexpected proxy", http.StatusBadGateway)
	}))
	defer proxy.Close()
	t.Setenv("HTTP_PROXY", proxy.URL)
	t.Setenv("http_proxy", proxy.URL)
	if err := mihomoFixtureCommand(c, "health", nil, "text", nil, io.Discard, false); err != nil {
		t.Fatal(err)
	}
	if intercepted.Load() != 0 {
		t.Fatal("controller traffic used environment proxy")
	}
	fake.secret = "different-private-secret"
	err := mihomoFixtureCommand(c, "health", nil, "text", nil, io.Discard, false)
	if err == nil || !strings.Contains(err.Error(), "E_MIHOMO_AUTH") || strings.Contains(err.Error(), "private-secret") {
		t.Fatalf("authentication diagnostic leaked or missing: %v", err)
	}
}

func TestMihomoControllerRefusesRedirect(t *testing.T) {
	c, _ := setupMihomoController(t, "synthetic-private-secret")
	var leaked atomic.Int32
	target := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		leaked.Add(1)
		fmt.Fprint(w, `{"version":"unexpected"}`)
	}))
	defer target.Close()
	redirect := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Redirect(w, r, target.URL, http.StatusFound)
	}))
	defer redirect.Close()
	u, _ := url.Parse(redirect.URL)
	c.Mihomo.APIPort, _ = strconv.Atoi(u.Port())
	err := mihomoFixtureCommand(c, "health", nil, "text", nil, io.Discard, false)
	if err == nil || !strings.Contains(err.Error(), "HTTP 302") || leaked.Load() != 0 {
		t.Fatalf("redirect followed: calls=%d error=%v", leaked.Load(), err)
	}
}

func TestMihomoOfflineNodesRequireNoPythonOrController(t *testing.T) {
	c, _ := setupMihomoController(t, "")
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	c.Mihomo.APIPort = listener.Addr().(*net.TCPAddr).Port
	listener.Close()
	home, _ := os.UserHomeDir()
	content := "proxies:\n  - name: Node A\n    type: ss\n    password: synthetic-secret\nproxy-groups:\n  - name: My Group\n    type: select\n    proxies: [Node A]\n  - name: Provider Group\n    type: select\n    use: [subscription]\n"
	if err = WriteAtomic(filepath.Join(home, ".config", "mihomo", "config.yaml"), []byte(content), 0600); err != nil {
		t.Fatal(err)
	}
	var output bytes.Buffer
	if err = mihomoFixtureCommand(c, "nodes", nil, "json", nil, &output, false); err != nil {
		t.Fatal(err)
	}
	var result struct {
		Running bool          `json:"running"`
		Groups  []mihomoProxy `json:"groups"`
	}
	if err = json.Unmarshal(output.Bytes(), &result); err != nil || result.Running || len(result.Groups) != 2 || strings.Contains(output.String(), "synthetic-secret") {
		t.Fatalf("offline output: %s / %v", output.Bytes(), err)
	}
	err = mihomoFixtureCommand(c, "select", []string{"My Group", "Node A"}, "json", nil, io.Discard, false)
	if err == nil || !strings.Contains(err.Error(), "E_MIHOMO_API") {
		t.Fatalf("stopped selection: %v", err)
	}
}

func TestMihomoRuntimeSecretTakesPrecedenceAndStateIsNodeScoped(t *testing.T) {
	c, _ := setupMihomoController(t, "runtime-private-secret")
	home, _ := os.UserHomeDir()
	if err := WriteAtomic(filepath.Join(home, ".config", "mihomo", "config.yaml"), []byte("secret: old-secret\n"), 0600); err != nil {
		t.Fatal(err)
	}
	runtimeDir := t.TempDir()
	t.Setenv("MIHOMO_RUNTIME_DIR", runtimeDir)
	if err := WriteAtomic(filepath.Join(runtimeDir, "config.yaml"), []byte("secret: runtime-private-secret\n"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := mihomoFixtureCommand(c, "health", nil, "text", nil, io.Discard, false); err != nil {
		t.Fatal(err)
	}
	if err := mihomoFixtureCommand(c, "selection-save", nil, "text", nil, io.Discard, false); err != nil {
		t.Fatal(err)
	}
	state, _, err := mihomoReadSelections(c)
	if err != nil {
		t.Fatal(err)
	}
	state.Host = "another-node"
	if err = mihomoWriteSelections(c, state); err != nil {
		t.Fatal(err)
	}
	if err = mihomoFixtureCommand(c, "selection-restore", nil, "text", nil, io.Discard, false); err == nil || !strings.Contains(err.Error(), "E_MIHOMO_STATE") {
		t.Fatalf("foreign state applied: %v", err)
	}
}

func TestMihomoConnectionTestDoesNotChangeSelection(t *testing.T) {
	c, fake := setupMihomoController(t, "")
	var output bytes.Buffer
	if err := mihomoFixtureCommand(c, "test", []string{"烟火云/选择"}, "json", nil, &output, false); err != nil {
		t.Fatal(err)
	}
	var result struct {
		Results []mihomoDelayResult `json:"results"`
	}
	if err := json.Unmarshal(output.Bytes(), &result); err != nil || len(result.Results) != 3 {
		t.Fatalf("delay report: %s / %v", output.Bytes(), err)
	}
	if result.Results[2].OK || fake.putCount != 0 {
		t.Fatal("failed test accepted or selection changed")
	}
	output.Reset()
	if err := mihomoFixtureCommand(c, "test", []string{"烟火云/选择", "bad"}, "text", nil, &output, false); err == nil || !strings.Contains(err.Error(), "E_MIHOMO_TEST_FAILED") {
		t.Fatalf("all failures returned success: %v", err)
	}
	if err := mihomoFixtureCommand(c, "test", []string{"自动选择"}, "text", nil, io.Discard, false); err != nil {
		t.Fatalf("testing an automatic group must not require manual selection support: %v", err)
	}
}

func TestMihomoEmptyJSONListsAreArrays(t *testing.T) {
	c, fake := setupMihomoController(t, "")
	var output bytes.Buffer
	if err := mihomoFixtureCommand(c, "selection-restore", nil, "json", nil, &output, false); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(output.String(), `"restored":[]`) || !strings.Contains(output.String(), `"skipped":[]`) {
		t.Fatalf("missing selection JSON: %s", output.String())
	}
	output.Reset()
	fake.proxies = map[string]mihomoProxy{}
	if err := mihomoFixtureCommand(c, "nodes", nil, "json", nil, &output, false); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(output.String(), `"groups":[]`) {
		t.Fatalf("empty groups JSON: %s", output.String())
	}
}
