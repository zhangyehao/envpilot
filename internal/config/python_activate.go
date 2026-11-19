package config

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

// ActivatePython validates a freshly extracted python-build-standalone release
// before replacing current. A retry, even for the same version, uses a new directory.
func ActivatePython(base, staging, version string) error {
	base, err := filepath.EvalSymlinks(base)
	if err != nil {
		return err
	}
	staging, err = filepath.EvalSymlinks(staging)
	if err != nil {
		return err
	}
	if filepath.Dir(staging) != base || !stableVersion.MatchString(version) || !strings.HasPrefix(filepath.Base(staging), version+".") {
		return fmt.Errorf("invalid Python staging directory")
	}
	var root, entry string
	for _, candidate := range []string{filepath.Join(staging, "python"), staging} {
		path := filepath.Join(candidate, "bin", "python3")
		for _, dir := range []string{candidate, filepath.Dir(path)} {
			resolved, err := filepath.EvalSymlinks(dir)
			if err == nil && !withinRuntime(staging, resolved) {
				return fmt.Errorf("Python package directory points outside staging")
			}
		}
		resolved, err := filepath.EvalSymlinks(path)
		if err != nil {
			continue
		}
		if !withinRuntime(staging, resolved) {
			return fmt.Errorf("bin/python3 points outside the staged package")
		}
		st, err := os.Stat(resolved)
		if err == nil && st.Mode().IsRegular() && st.Mode().Perm()&0111 != 0 {
			root, entry = candidate, path
			break
		}
	}
	if entry == "" {
		return fmt.Errorf("Python archive did not contain an executable bin/python3")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()
	// -I ignores inherited PYTHONHOME, PYTHONPATH and user site packages.
	b, err := exec.CommandContext(ctx, entry, "-I", "-c", "import sys, sysconfig; print('.'.join(map(str, sys.version_info[:3])))").Output()
	if err != nil || strings.TrimSpace(string(b)) != version {
		return fmt.Errorf("Python interpreter failed its startup or version check (expected %s)", version)
	}
	dir, err := os.MkdirTemp(base, ".activate-")
	if err != nil {
		return err
	}
	defer os.Remove(dir)
	link := filepath.Join(dir, "current")
	absolute, err := filepath.Abs(root)
	if err != nil {
		return err
	}
	if err = os.Symlink(absolute, link); err != nil {
		return err
	}
	defer os.Remove(link)
	current := filepath.Join(base, "current")
	// Old installations could contain a copied directory instead of a symlink.
	// Keep this backup on disk even after successful activation.
	if st, err := os.Lstat(current); err == nil && st.IsDir() {
		backup := filepath.Join(dir, "previous")
		if err := os.Rename(current, backup); err != nil {
			return err
		}
		if err := os.Rename(link, current); err != nil {
			if recoverErr := os.Rename(backup, current); recoverErr != nil {
				return fmt.Errorf("activation failed: %w; previous interpreter at %s (%v)", err, backup, recoverErr)
			}
			return err
		}
		return nil
	}
	return os.Rename(link, current)
}
