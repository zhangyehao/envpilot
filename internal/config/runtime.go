package config

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	goruntime "runtime"
	"sort"
	"strings"
	"time"
)

type runtimeEntry struct {
	Path   string      `json:"path"`
	Kind   string      `json:"kind"`
	Mode   fs.FileMode `json:"mode"`
	Link   string      `json:"link,omitempty"`
	Source string      `json:"-"`
}
type runtimeLayout struct {
	Root    string         `json:"source"`
	Kind    string         `json:"kind"`
	Version string         `json:"version,omitempty"`
	Entries []runtimeEntry `json:"entries"`
}

var runtimeStateNames = map[string]bool{
	".source.signature": true, ".runtime-metadata": true, ".runtime-manifest.json": true, ".version": true,
}

func withinRuntime(root, path string) bool {
	rel, err := filepath.Rel(root, path)
	return err == nil && rel != ".." && !strings.HasPrefix(rel, ".."+string(filepath.Separator)) && !filepath.IsAbs(rel)
}

func discoverRuntime(source string) (runtimeLayout, error) {
	source, err := filepath.EvalSymlinks(source)
	if err != nil {
		return runtimeLayout{}, err
	}
	source, err = filepath.Abs(source)
	if err != nil {
		return runtimeLayout{}, err
	}
	executable, err := filepath.EvalSymlinks(filepath.Join(source, "codex"))
	if err != nil {
		if _, manifestErr := os.Stat(filepath.Join(source, "codex-package.json")); manifestErr == nil {
			executable, err = filepath.EvalSymlinks(filepath.Join(source, "bin", "codex"))
		}
	}
	if err != nil {
		return runtimeLayout{}, err
	}
	if info, e := os.Stat(executable); e != nil || !info.Mode().IsRegular() {
		return runtimeLayout{}, fmt.Errorf("selected Codex entrypoint is not a regular executable")
	}
	layout := runtimeLayout{Root: source, Kind: "legacy"}
	for _, candidate := range []string{source, filepath.Dir(source)} {
		manifest := filepath.Join(candidate, "codex-package.json")
		b, readErr := os.ReadFile(manifest)
		if os.IsNotExist(readErr) {
			continue
		}
		if readErr != nil {
			return layout, readErr
		}
		var pkg struct {
			LayoutVersion int    `json:"layoutVersion"`
			Version       string `json:"version"`
			Variant       string `json:"variant"`
			Entrypoint    string `json:"entrypoint"`
			ResourcesDir  string `json:"resourcesDir"`
			PathDir       string `json:"pathDir"`
		}
		if err = json.Unmarshal(b, &pkg); err != nil {
			return layout, fmt.Errorf("invalid Codex package manifest: %w", err)
		}
		if pkg.LayoutVersion != 1 || pkg.Variant != "codex" || pkg.Entrypoint != "bin/codex" || pkg.Version == "" {
			return layout, fmt.Errorf("unsupported Codex package layout: %s", manifest)
		}
		entry, err := filepath.EvalSymlinks(filepath.Join(candidate, pkg.Entrypoint))
		if err != nil || entry != executable {
			return layout, fmt.Errorf("Codex package entrypoint does not match the selected executable")
		}
		for _, dir := range []string{pkg.ResourcesDir, pkg.PathDir} {
			if dir == "" || filepath.IsAbs(dir) || filepath.Clean(dir) != dir || dir == "." || strings.Contains(dir, "\\") || !withinRuntime(candidate, filepath.Join(candidate, dir)) {
				return layout, fmt.Errorf("invalid Codex package resource path")
			}
			st, err := os.Stat(filepath.Join(candidate, dir))
			if err != nil || !st.IsDir() {
				return layout, fmt.Errorf("Codex package directory is missing: %s", dir)
			}
		}
		layout.Root, layout.Kind, layout.Version = candidate, "package", pkg.Version
		for _, required := range []string{pkg.Entrypoint, "bin/codex-code-mode-host", filepath.Join(pkg.PathDir, "rg")} {
			info, e := os.Stat(filepath.Join(candidate, required))
			if e != nil || !info.Mode().IsRegular() || (goruntime.GOOS != "windows" && info.Mode().Perm()&0111 == 0) {
				return layout, fmt.Errorf("Codex package component is missing: %s", required)
			}
		}
		break
	}
	if layout.Kind == "legacy" && filepath.Base(source) == "codex" && filepath.Base(filepath.Dir(filepath.Dir(source))) == "vendor" {
		layout.Root, layout.Kind = filepath.Dir(source), "npm-vendor"
	}
	add := func(path, destination string) error {
		return filepath.WalkDir(path, func(current string, d fs.DirEntry, walkErr error) error {
			if walkErr != nil {
				return walkErr
			}
			rel, _ := filepath.Rel(path, current)
			dest := filepath.Join(destination, rel)
			if dest == "." {
				return nil
			}
			if runtimeStateNames[dest] {
				return fmt.Errorf("Codex package contains a reserved state filename: %s", dest)
			}
			info, err := d.Info()
			if err != nil {
				return err
			}
			e := runtimeEntry{Path: filepath.ToSlash(dest), Source: current, Mode: info.Mode().Perm()}
			switch {
			case d.Type()&os.ModeSymlink != 0:
				e.Kind = "link"
				e.Mode = 0 // Link permissions vary by OS and do not govern target access.
				target, err := filepath.EvalSymlinks(current)
				if err != nil {
					return fmt.Errorf("invalid package link %s: %w", e.Path, err)
				}
				if !withinRuntime(layout.Root, target) {
					return fmt.Errorf("Codex package link escapes its package: %s", e.Path)
				}
				link, err := os.Readlink(current)
				if err != nil {
					return err
				}
				if filepath.IsAbs(link) {
					link, err = filepath.Rel(filepath.Dir(current), target)
				}
				if err != nil {
					return err
				}
				e.Link = filepath.ToSlash(link)
			case d.IsDir():
				e.Kind = "dir"
			case info.Mode().IsRegular():
				e.Kind = "file"
			default:
				return fmt.Errorf("unsupported special file in Codex package: %s", e.Path)
			}
			layout.Entries = append(layout.Entries, e)
			return nil
		})
	}
	if layout.Kind != "legacy" {
		if err = add(layout.Root, "."); err != nil {
			return layout, err
		}
		if layout.Kind == "npm-vendor" {
			if _, err = os.Lstat(filepath.Join(layout.Root, "bin")); !os.IsNotExist(err) {
				return layout, fmt.Errorf("ambiguous npm Codex bin layout")
			}
			layout.Entries = append(layout.Entries, runtimeEntry{Path: "bin", Kind: "dir", Mode: 0755}, runtimeEntry{Path: "bin/codex", Kind: "link", Link: "../codex/codex"})
		}
	} else {
		// A bare PATH directory is not a package: never copy unrelated programs.
		layout.Entries = append(layout.Entries, runtimeEntry{Path: "bin", Kind: "dir", Mode: 0755})
		children, err := os.ReadDir(source)
		if err != nil {
			return layout, err
		}
		for _, child := range children {
			name := child.Name()
			if name == "codex" || strings.HasPrefix(name, "codex-") || name == "rg" || name == "bwrap" {
				if err = add(filepath.Join(source, name), filepath.Join("bin", name)); err != nil {
					return layout, err
				}
			}
		}
	}
	sort.Slice(layout.Entries, func(i, j int) bool { return layout.Entries[i].Path < layout.Entries[j].Path })
	return layout, nil
}

func fileChangeIdentity(info fs.FileInfo) string {
	// ctime/inode detect replacement and writes with restored mtime. Do not use
	// atime, which changes merely by hashing or executing an otherwise valid file.
	v := reflect.ValueOf(info.Sys())
	if v.Kind() == reflect.Pointer {
		v = v.Elem()
	}
	if !v.IsValid() || v.Kind() != reflect.Struct {
		return ""
	}
	var values []any
	for _, name := range []string{"Dev", "Ino", "Ctim", "Ctimespec", "Ctime", "Ctimensec", "CreationTime"} {
		if field := v.FieldByName(name); field.IsValid() && field.CanInterface() {
			values = append(values, field.Interface())
		}
	}
	return fmt.Sprint(values...)
}

func runtimeFingerprint(layout runtimeLayout, target string, content bool) (string, error) {
	hash := sha256.New()
	fmt.Fprintf(hash, "envpilot-runtime-layout-v2\x00%s\x00", layout.Kind)
	expected := map[string]bool{}
	for _, entry := range layout.Entries {
		expected[entry.Path] = true
		path := entry.Source
		if target != "" {
			path = filepath.Join(target, filepath.FromSlash(entry.Path))
		}
		fmt.Fprintf(hash, "%s\x00%s\x00%o\x00%s\x00", entry.Path, entry.Kind, entry.Mode, entry.Link)
		if path == "" {
			fmt.Fprint(hash, "\x00")
			continue
		} // synthetic compatibility directory/link
		info, err := os.Lstat(path)
		if err != nil {
			return "", err
		}
		kind := "file"
		if info.IsDir() {
			kind = "dir"
		} else if info.Mode()&os.ModeSymlink != 0 {
			kind = "link"
		} else if !info.Mode().IsRegular() {
			kind = "special"
		}
		if kind != entry.Kind || (kind != "link" && goruntime.GOOS != "windows" && info.Mode().Perm() != entry.Mode) {
			return "", fmt.Errorf("Codex runtime type or permissions mismatch: %s", entry.Path)
		}
		if kind == "link" && target != "" {
			link, err := os.Readlink(path)
			if err != nil || filepath.ToSlash(link) != entry.Link {
				return "", fmt.Errorf("Codex runtime link mismatch: %s", entry.Path)
			}
		}
		if !content {
			fmt.Fprintf(hash, "%d\x00%d\x00%s\x00", info.Size(), info.ModTime().UnixNano(), fileChangeIdentity(info))
			if kind == "link" {
				link, err := os.Readlink(path)
				if err != nil {
					return "", err
				}
				fmt.Fprint(hash, link)
			}
		} else if kind == "file" {
			fmt.Fprintf(hash, "%d\x00", info.Size())
			file, err := os.Open(path)
			if err != nil {
				return "", err
			}
			_, err = io.Copy(hash, file)
			closeErr := file.Close()
			if err != nil {
				return "", err
			}
			if closeErr != nil {
				return "", closeErr
			}
		}
		fmt.Fprint(hash, "\x00")
	}
	if target != "" {
		err := filepath.WalkDir(target, func(path string, d fs.DirEntry, err error) error {
			if err != nil {
				return err
			}
			rel, _ := filepath.Rel(target, path)
			if rel == "." {
				return nil
			}
			if runtimeStateNames[rel] && !d.IsDir() {
				return nil
			}
			if !expected[filepath.ToSlash(rel)] {
				return fmt.Errorf("unexpected file in Codex runtime: %s", rel)
			}
			return nil
		})
		if err != nil {
			return "", err
		}
	}
	return hex.EncodeToString(hash.Sum(nil)), nil
}

func RuntimeMetadata(source string) (string, error) {
	layout, err := discoverRuntime(source)
	if err != nil {
		return "", err
	}
	metadata, err := runtimeFingerprint(layout, "", false)
	return layout.Root + "|" + metadata, err
}

func copyRuntime(layout runtimeLayout, target string) error {
	for _, entry := range layout.Entries {
		dest := filepath.Join(target, filepath.FromSlash(entry.Path))
		if err := os.MkdirAll(filepath.Dir(dest), 0700); err != nil {
			return err
		}
		switch entry.Kind {
		case "dir":
			if err := os.MkdirAll(dest, 0700); err != nil {
				return err
			}
		case "link":
			if err := os.Symlink(filepath.FromSlash(entry.Link), dest); err != nil {
				return err
			}
		case "file":
			in, err := os.Open(entry.Source)
			if err != nil {
				return err
			}
			out, err := os.OpenFile(dest, os.O_CREATE|os.O_EXCL|os.O_WRONLY, entry.Mode)
			if err != nil {
				in.Close()
				return err
			}
			_, err = io.Copy(out, in)
			inErr, outErr := in.Close(), out.Close()
			if err != nil {
				return err
			}
			if inErr != nil {
				return inErr
			}
			if outErr != nil {
				return outErr
			}
		}
		if entry.Kind == "file" {
			if err := os.Chmod(dest, entry.Mode); err != nil {
				return err
			}
		}
	}
	for i := len(layout.Entries) - 1; i >= 0; i-- {
		entry := layout.Entries[i]
		if entry.Kind == "dir" {
			if err := os.Chmod(filepath.Join(target, filepath.FromSlash(entry.Path)), entry.Mode); err != nil {
				return err
			}
		}
	}
	return nil
}

func VerifyRuntime(source, target string) error {
	if target == "" {
		return fmt.Errorf("runtime verification requires a target directory")
	}
	layout, err := discoverRuntime(source)
	if err != nil {
		return err
	}
	want, err := runtimeFingerprint(layout, "", true)
	if err != nil {
		return err
	}
	got, err := runtimeFingerprint(layout, target, true)
	if err != nil {
		return err
	}
	if got != want {
		return fmt.Errorf("Codex runtime contents differ from the complete source package")
	}
	return nil
}

// StageRuntime is called under the manager's staging lock. It never stops a
// process or changes CODEX_HOME. Only a complete verified generation is activated.
func StageRuntime(source, root, mode string) (string, error) {
	if root == "" {
		return "", fmt.Errorf("runtime staging requires a target directory")
	}
	if mode != "0" && mode != "1" && mode != "verify" {
		return "", fmt.Errorf("invalid runtime staging mode")
	}
	layout, err := discoverRuntime(source)
	if err != nil {
		return "", err
	}
	root, err = filepath.Abs(root)
	if err != nil {
		return "", err
	}
	if withinRuntime(layout.Root, root) {
		return "", fmt.Errorf("runtime cache must not be inside the source package")
	}
	if info, e := os.Lstat(root); e == nil && (!info.IsDir() || info.Mode()&os.ModeSymlink != 0) {
		return "", fmt.Errorf("unsafe runtime directory: %s", root)
	}
	if err = os.MkdirAll(root, 0700); err != nil {
		return "", err
	}
	root, err = filepath.EvalSymlinks(root)
	if err != nil {
		return "", err
	}
	if withinRuntime(layout.Root, root) {
		return "", fmt.Errorf("runtime cache must not be inside the source package")
	}
	releases := filepath.Join(root, "releases")
	for _, dir := range []string{releases} {
		if st, e := os.Lstat(dir); e == nil && (!st.IsDir() || st.Mode()&os.ModeSymlink != 0) {
			return "", fmt.Errorf("unsafe runtime directory: %s", dir)
		}
		if err = os.MkdirAll(dir, 0700); err != nil {
			return "", err
		}
	}
	metadata, err := RuntimeMetadata(source)
	if err != nil {
		return "", err
	}
	read := func(path string) string { b, _ := os.ReadFile(path); return strings.TrimSpace(string(b)) }
	digest := read(filepath.Join(root, ".source-digest"))
	if mode != "0" || metadata != read(filepath.Join(root, ".source-metadata")) || len(digest) != 64 {
		digest, err = runtimeFingerprint(layout, "", true)
		if err != nil {
			return "", err
		}
	}
	if _, err = hex.DecodeString(digest); err != nil || len(digest) != 64 {
		return "", fmt.Errorf("invalid runtime digest")
	}
	current := filepath.Join(root, "current")
	generation := filepath.Join(releases, digest)
	if active, e := filepath.EvalSymlinks(current); e == nil {
		if !withinRuntime(root, active) {
			return "", fmt.Errorf("runtime current points outside its cache")
		}
		if read(filepath.Join(active, ".source.signature")) == digest {
			generation = active
		}
	}
	runtimeMeta, metaErr := "", error(nil)
	if info, e := os.Lstat(generation); e == nil && info.IsDir() && info.Mode()&os.ModeSymlink == 0 {
		runtimeMeta, metaErr = runtimeFingerprint(layout, generation, false)
	} else {
		metaErr = fmt.Errorf("runtime generation is absent or unsafe")
	}
	valid := metaErr == nil && runtimeMeta == read(filepath.Join(generation, ".runtime-metadata"))
	if valid && mode != "0" {
		actual, e := runtimeFingerprint(layout, generation, true)
		valid = e == nil && actual == digest
	}
	created := ""
	if !valid || mode == "1" {
		staged, err := os.MkdirTemp(releases, ".staging-")
		if err != nil {
			return "", err
		}
		defer os.RemoveAll(staged)
		if err = copyRuntime(layout, staged); err != nil {
			return "", err
		}
		if err = VerifyRuntime(source, staged); err != nil {
			return "", err
		}
		after, err := RuntimeMetadata(source)
		if err != nil || after != metadata {
			return "", fmt.Errorf("Codex source changed while staging; retry after the installer finishes")
		}
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		output, probeErr := exec.CommandContext(ctx, filepath.Join(staged, "bin", "codex"), "--version").CombinedOutput()
		cancel()
		version := ""
		for _, line := range strings.Split(string(output), "\n") {
			if strings.HasPrefix(line, "codex-cli ") {
				version = strings.TrimSpace(strings.TrimPrefix(line, "codex-cli "))
				break
			}
		}
		if probeErr != nil || version == "" {
			return "", fmt.Errorf("the staged Codex executable failed its version probe; the running server was preserved")
		}
		if layout.Version != "" && version != layout.Version {
			return "", fmt.Errorf("Codex binary version does not match its package manifest")
		}
		manifest, _ := json.MarshalIndent(layout, "", "  ")
		for name, data := range map[string][]byte{".version": []byte(version + "\n"), ".source.signature": []byte(digest + "\n"), ".runtime-manifest.json": manifest} {
			if err = WriteAtomic(filepath.Join(staged, name), data, 0600); err != nil {
				return "", err
			}
		}
		if _, e := os.Lstat(generation); e == nil {
			generation = filepath.Join(releases, digest+"-"+filepath.Base(staged))
		}
		if err = os.Rename(staged, generation); err != nil {
			return "", err
		}
		runtimeMeta, err = runtimeFingerprint(layout, generation, false)
		if err != nil {
			return "", err
		}
		if err = WriteAtomic(filepath.Join(generation, ".runtime-metadata"), []byte(runtimeMeta+"\n"), 0600); err != nil {
			return "", err
		}
		created = generation
	}
	if err = WriteAtomic(filepath.Join(root, ".source-metadata"), []byte(metadata+"\n"), 0600); err != nil {
		return "", err
	}
	if err = WriteAtomic(filepath.Join(root, ".source-digest"), []byte(digest+"\n"), 0600); err != nil {
		return "", err
	}
	link := filepath.Join(root, fmt.Sprintf(".current-%d", time.Now().UnixNano()))
	if err = os.Symlink(generation, link); err != nil {
		return "", err
	}
	defer os.Remove(link)
	legacy := ""
	if st, e := os.Lstat(current); e == nil && st.IsDir() {
		legacy = filepath.Join(releases, fmt.Sprintf("legacy-%d", time.Now().UnixNano()))
		if err = os.Rename(current, legacy); err != nil {
			return "", err
		}
	}
	if err = os.Rename(link, current); err != nil {
		if legacy != "" {
			_ = os.Rename(legacy, current)
		}
		return "", err
	}
	return created, nil
}
