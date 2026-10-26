package config

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
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
	"sync/atomic"
	"testing"
)

func mihomoOwnerTestExecutable(t *testing.T) string {
	t.Helper()
	home, err := os.UserHomeDir()
	if err != nil {
		t.Fatal(err)
	}
	directory := filepath.Join(home, "software", "mihomo")
	name := "mihomo.exe"
	if runtime.GOOS != "windows" {
		directory = t.TempDir()
		name = "mihomo"
		t.Setenv("MIHOMO_RUNTIME_DIR", directory)
	}
	path := filepath.Join(directory, name)
	if err := WriteAtomic(path, []byte("not a running executable"), 0700); err != nil {
		t.Fatal(err)
	}
	return path
}

func TestMihomoPublicCommandsRefuseUnmanagedListener(t *testing.T) {
	c, fake := setupMihomoController(t, "synthetic-private-secret")
	mihomoOwnerTestExecutable(t)
	home, _ := os.UserHomeDir()
	content := "secret: synthetic-private-secret\nproxy-groups:\n  - name: My Group\n    type: select\n    proxies: [Node A]\n"
	if err := WriteAtomic(filepath.Join(home, ".config", "mihomo", "config.yaml"), []byte(content), 0600); err != nil {
		t.Fatal(err)
	}
	state, _, err := mihomoReadSelections(c)
	if err != nil {
		t.Fatal(err)
	}
	state.Selections["My Group"] = "Node A"
	if err := mihomoWriteSelections(c, state); err != nil {
		t.Fatal(err)
	}
	for _, action := range []string{"health", "select", "test", "selection-save", "selection-restore"} {
		var args []string
		if action == "select" || action == "test" {
			args = []string{"My Group", "Node A"}
		}
		// Exercise the exported entry point: callers cannot supply a verifier.
		err := MihomoCommand(c, action, args, "json")
		if err == nil || !strings.HasPrefix(err.Error(), "E_MIHOMO_OWNER:") {
			t.Fatalf("%s accepted an unmanaged listener: %v", action, err)
		}
		if strings.Contains(err.Error(), "synthetic-private") {
			t.Fatalf("%s error exposed credentials", action)
		}
	}
	var output bytes.Buffer
	if err := mihomoCommandIO(c, "nodes", nil, "json", nil, &output, false); err != nil {
		t.Fatal(err)
	}
	var result struct {
		Running bool          `json:"running"`
		Source  string        `json:"source"`
		Groups  []mihomoProxy `json:"groups"`
	}
	if err := json.Unmarshal(output.Bytes(), &result); err != nil || result.Running ||
		result.Source != "configuration" || len(result.Groups) != 1 || result.Groups[0].Name != "My Group" {
		t.Fatalf("nodes should use only local configuration: %s / %v", output.Bytes(), err)
	}
	fake.mu.Lock()
	defer fake.mu.Unlock()
	if len(fake.paths) != 0 {
		t.Fatalf("unmanaged listener received HTTP requests: %v", fake.paths)
	}
}

func TestMihomoOwnerRecheckedBeforeSendingCredentials(t *testing.T) {
	c, fake := setupMihomoController(t, "synthetic-private-secret")
	var checks atomic.Int32
	verify := func(context.Context) error {
		if checks.Add(1) == 1 {
			return nil
		}
		return errMihomoUnverifiedOwner
	}
	err := mihomoCommandCheckedIO(c, "health", nil, "json", nil, io.Discard, false, verify)
	if err == nil || !strings.HasPrefix(err.Error(), "E_MIHOMO_OWNER:") || checks.Load() != 2 {
		t.Fatalf("connection owner change was accepted: checks=%d error=%v", checks.Load(), err)
	}
	fake.mu.Lock()
	defer fake.mu.Unlock()
	if len(fake.paths) != 0 {
		t.Fatalf("HTTP request sent before the second ownership check: %v", fake.paths)
	}
}

func TestMihomoVerifiedConnectionReuseAndReconnect(t *testing.T) {
	c, _ := setupMihomoController(t, "synthetic-private-secret")
	var checks atomic.Int32
	verify := func(context.Context) error {
		checks.Add(1)
		return nil
	}
	controller, err := newMihomoControllerChecked(c, verify)
	if err != nil {
		t.Fatal(err)
	}
	defer controller.client.CloseIdleConnections()
	for i := 0; i < 3; i++ {
		var version map[string]any
		if err := controller.request(http.MethodGet, "/version", nil, &version); err != nil {
			t.Fatal(err)
		}
	}
	if checks.Load() != 2 {
		t.Fatalf("keep-alive connection was not reused: ownership checks=%d", checks.Load())
	}
	controller.client.CloseIdleConnections()
	var version map[string]any
	if err := controller.request(http.MethodGet, "/version", nil, &version); err != nil {
		t.Fatal(err)
	}
	if checks.Load() != 4 {
		t.Fatalf("a new connection was not rechecked: ownership checks=%d", checks.Load())
	}
}

func TestMihomoNativeListenerOwnership(t *testing.T) {
	if runtime.GOOS != "linux" && runtime.GOOS != "windows" && runtime.GOOS != "darwin" {
		t.Skip("unsupported process inspection platform fails closed")
	}
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {}))
	defer server.Close()
	u, _ := url.Parse(server.URL)
	port, _ := strconv.Atoi(u.Port())
	executable, err := os.Executable()
	if err != nil {
		t.Fatal(err)
	}
	if err := verifyMihomoListenerOwner(context.Background(), port, executable, ""); err != nil {
		t.Fatalf("OS rejected this process's own listener: %v", err)
	}
	other := filepath.Join(t.TempDir(), "different-executable")
	if err := os.WriteFile(other, []byte("unrelated"), 0700); err != nil {
		t.Fatal(err)
	}
	if err := verifyMihomoListenerOwner(context.Background(), port, other, ""); !errors.Is(err, errMihomoUnverifiedOwner) {
		t.Fatalf("OS accepted a different executable: %v", err)
	}
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	unused := listener.Addr().(*net.TCPAddr).Port
	listener.Close()
	if err := verifyMihomoListenerOwner(context.Background(), unused, executable, ""); !errors.Is(err, errMihomoNoListener) {
		t.Fatalf("missing listener diagnostic: %v", err)
	}
}

func TestMihomoManagedExecutableRequiresNodeRuntime(t *testing.T) {
	testHome(t)
	c := Defaults()
	t.Setenv("MIHOMO_RUNTIME_DIR", filepath.Join(t.TempDir(), "missing-runtime"))
	if _, err := mihomoManagedExecutable(c); err == nil {
		t.Fatal("missing managed executable accepted")
	}
	expected := mihomoOwnerTestExecutable(t)
	actual, err := mihomoManagedExecutable(c)
	if err != nil || !mihomoSameExecutable(actual, expected) {
		t.Fatalf("managed runtime not located: %q / %v", actual, err)
	}
	if runtime.GOOS != "windows" {
		t.Setenv("MIHOMO_RUNTIME_DIR", "relative")
		if _, err := mihomoManagedExecutable(c); !errors.Is(err, errMihomoUnverifiedOwner) {
			t.Fatalf("relative runtime accepted: %v", err)
		}
	}
}
