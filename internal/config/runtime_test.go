package config

import (
	"os"
	"path/filepath"
	"runtime"
	"testing"
)

func runtimeFixture(t *testing.T) string {
	t.Helper()
	root := t.TempDir()
	files := map[string]string{
		"codex-package.json":                            `{"layoutVersion":1,"version":"0.156.0","variant":"codex","entrypoint":"bin/codex","resourcesDir":"codex-resources","pathDir":"codex-path"}`,
		"bin/codex":                                     "#!/bin/sh\necho 'codex-cli 0.156.0'\n",
		"bin/codex-code-mode-host":                      "#!/bin/sh\nexit 0\n",
		"codex-path/rg":                                 "packaged rg",
		"codex-resources/models/catalog.json":           `{"models":["fixture-model"]}`,
		"codex-resources/voice/lib/gstreamer/plugin.so": "fixture library",
		"codex-resources/zsh/bin/zsh":                   "fixture shell",
		"future-component/data/model.dat":               "future package content must also survive",
	}
	for name, data := range files {
		path := filepath.Join(root, filepath.FromSlash(name))
		if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte(data), 0755); err != nil {
			t.Fatal(err)
		}
	}
	return root
}

func TestRuntimePackagePreservesEveryNestedComponent(t *testing.T) {
	source := runtimeFixture(t)
	layout, err := discoverRuntime(filepath.Join(source, "bin"))
	if err != nil {
		t.Fatal(err)
	}
	wantRoot, wantErr := os.Stat(source)
	actualRoot, actualErr := os.Stat(layout.Root)
	if layout.Kind != "package" || wantErr != nil || actualErr != nil || !os.SameFile(wantRoot, actualRoot) {
		t.Fatalf("wrong package root: %+v", layout)
	}
	dest := t.TempDir()
	if err = copyRuntime(layout, dest); err != nil {
		t.Fatal(err)
	}
	if err = VerifyRuntime(filepath.Join(source, "bin"), dest); err != nil {
		t.Fatal(err)
	}
	for _, path := range []string{"bin/codex-code-mode-host", "codex-path/rg", "codex-resources/models/catalog.json", "codex-resources/voice/lib/gstreamer/plugin.so", "future-component/data/model.dat"} {
		if _, err = os.Stat(filepath.Join(dest, filepath.FromSlash(path))); err != nil {
			t.Fatal(err)
		}
	}
	if err = os.Remove(filepath.Join(dest, "codex-resources", "models", "catalog.json")); err != nil {
		t.Fatal(err)
	}
	if VerifyRuntime(filepath.Join(source, "bin"), dest) == nil {
		t.Fatal("missing nested resource was accepted")
	}
}

func TestRuntimePackageLinksCannotEscapeSource(t *testing.T) {
	source := runtimeFixture(t)
	if err := os.Symlink("bin/codex", filepath.Join(source, "codex")); err != nil {
		t.Skipf("symlinks unavailable: %v", err)
	}
	layout, err := discoverRuntime(source)
	if err != nil {
		t.Fatal(err)
	}
	dest := t.TempDir()
	if err = copyRuntime(layout, dest); err != nil {
		t.Fatal(err)
	}
	if link, err := os.Readlink(filepath.Join(dest, "codex")); err != nil || filepath.ToSlash(link) != "bin/codex" {
		t.Fatalf("entry link was flattened: %q %v", link, err)
	}
	outside := filepath.Join(t.TempDir(), "private")
	if err = os.WriteFile(outside, []byte("do not copy"), 0600); err != nil {
		t.Fatal(err)
	}
	if err = os.Symlink(outside, filepath.Join(source, "codex-resources", "escape")); err != nil {
		t.Fatal(err)
	}
	if _, err = discoverRuntime(source); err == nil {
		t.Fatal("external package link accepted")
	}
}

func TestBareRuntimeDoesNotCopyUnrelatedPATHPrograms(t *testing.T) {
	source := t.TempDir()
	for _, name := range []string{"codex", "codex-code-mode-host", "unrelated-tool"} {
		if err := os.WriteFile(filepath.Join(source, name), []byte(name), 0755); err != nil {
			t.Fatal(err)
		}
	}
	layout, err := discoverRuntime(source)
	if err != nil {
		t.Fatal(err)
	}
	dest := t.TempDir()
	if err = copyRuntime(layout, dest); err != nil {
		t.Fatal(err)
	}
	if _, err = os.Stat(filepath.Join(dest, "bin", "unrelated-tool")); !os.IsNotExist(err) {
		t.Fatal("unrelated PATH program copied")
	}
	if err = VerifyRuntime(source, dest); err != nil {
		t.Fatal(err)
	}
}

func TestRuntimeResourceChangesAndCacheDamageRebuildGeneration(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("Unix runtime execution")
	}
	source := runtimeFixture(t)
	source = filepath.Join(source, "bin")
	cache := t.TempDir()
	first, err := StageRuntime(source, cache, "0")
	if err != nil {
		t.Fatal(err)
	}
	if again, err := StageRuntime(source, cache, "0"); err != nil || again != "" {
		t.Fatalf("unchanged package recopied: %q %v", again, err)
	}
	resource := filepath.Join(filepath.Dir(source), "codex-resources", "models", "catalog.json")
	if err = os.WriteFile(resource, []byte(`{"models":["fixture-model","new-resource"]}`), 0755); err != nil {
		t.Fatal(err)
	}
	second, err := StageRuntime(source, cache, "0")
	if err != nil || second == first || second == "" {
		t.Fatalf("resource-only update ignored: %q %v", second, err)
	}
	if err = os.Remove(filepath.Join(second, "bin", "codex-code-mode-host")); err != nil {
		t.Fatal(err)
	}
	third, err := StageRuntime(source, cache, "0")
	if err != nil || third == second || third == "" {
		t.Fatalf("missing helper not repaired: %q %v", third, err)
	}
	if err = VerifyRuntime(source, third); err != nil {
		t.Fatal(err)
	}
	if err = os.WriteFile(filepath.Join(source, "codex"), []byte("#!/bin/sh\nexit 1\n"), 0755); err != nil {
		t.Fatal(err)
	}
	if _, err = StageRuntime(source, cache, "verify"); err == nil {
		t.Fatal("invalid new source accepted")
	}
	active, err := filepath.EvalSymlinks(filepath.Join(cache, "current"))
	if err != nil || active != third {
		t.Fatal("failed staging switched away from last verified runtime")
	}
}

func TestRuntimeRejectsUnknownPackageLayout(t *testing.T) {
	source := runtimeFixture(t)
	if err := os.WriteFile(filepath.Join(source, "codex-package.json"), []byte(`{"layoutVersion":999}`), 0600); err != nil {
		t.Fatal(err)
	}
	if _, err := discoverRuntime(filepath.Join(source, "bin")); err == nil {
		t.Fatal("unknown package layout silently treated as a bare executable")
	}
}

func TestIncompleteSourcePackagePreservesPreviousGeneration(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("Unix runtime execution")
	}
	source := runtimeFixture(t)
	cache := t.TempDir()
	first, err := StageRuntime(source, cache, "0")
	if err != nil {
		t.Fatal(err)
	}
	if err = os.Remove(filepath.Join(source, "bin", "codex-code-mode-host")); err != nil {
		t.Fatal(err)
	}
	if _, err = StageRuntime(source, cache, "verify"); err == nil {
		t.Fatal("incomplete source package accepted")
	}
	active, err := filepath.EvalSymlinks(filepath.Join(cache, "current"))
	if err != nil || active != first {
		t.Fatal("incomplete source replaced the working runtime")
	}
}

func TestNpmVendorKeepsSiblingPathAndResources(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("Unix runtime symlink layout")
	}
	root := filepath.Join(t.TempDir(), "vendor", "x86_64-unknown-linux-musl")
	for _, name := range []string{"codex/codex", "codex/codex-code-mode-host", "path/rg", "resources/catalog.json"} {
		path := filepath.Join(root, filepath.FromSlash(name))
		if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte(name), 0755); err != nil {
			t.Fatal(err)
		}
	}
	source := filepath.Join(root, "codex")
	layout, err := discoverRuntime(source)
	if err != nil {
		t.Fatal(err)
	}
	dest := t.TempDir()
	if err = copyRuntime(layout, dest); err != nil {
		t.Fatal(err)
	}
	if err = VerifyRuntime(source, dest); err != nil {
		t.Fatal(err)
	}
	if _, err = os.Stat(filepath.Join(dest, "bin", "codex")); err != nil {
		t.Fatal(err)
	}
}
