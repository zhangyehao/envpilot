package config

import (
	"path/filepath"
	"strconv"
	"testing"
)

func TestMihomoWindowsConfigDirectoryIdentity(t *testing.T) {
	directory := filepath.Join(t.TempDir(), "managed path", "烟火")
	configFile := filepath.Join(directory, "config.yaml")
	if err := WriteAtomic(configFile, []byte("mode: rule\n"), 0600); err != nil {
		t.Fatal(err)
	}
	otherFile := filepath.Join(t.TempDir(), "other.yaml")
	if err := WriteAtomic(otherFile, []byte("mode: direct\n"), 0600); err != nil {
		t.Fatal(err)
	}
	// JSON string quoting doubles backslashes; Windows command-line quoting
	// needs the original path, enclosed in double quotes for spaces/Unicode.
	quote := func(path string) string { return `"` + path + `"` }
	for i, tc := range []struct {
		args string
		want bool
	}{
		{"-d " + quote(directory), true},
		{"--d=" + quote(directory), true},
		{"-d=" + quote(directory), true},
		{"-d " + quote(directory) + " -f " + quote(configFile), true},
		{"-d " + quote(directory) + " --f=" + quote(configFile), true},
		{"-d " + quote(directory) + " -f " + quote(otherFile), false},
		{"-d " + quote(directory) + " -d " + quote(filepath.Dir(otherFile)), false},
		{"-d " + quote(filepath.Dir(otherFile)) + " -d " + quote(directory), true},
		{"-d relative", false},
		{"-- -d " + quote(directory), false},
		{"-d", false},
		{"", false},
	} {
		t.Run(strconv.Itoa(i), func(t *testing.T) {
			if got := mihomoWindowsTargetsConfig(`"C:\tools\mihomo.exe" `+tc.args, directory); got != tc.want {
				t.Fatalf("configuration identity = %t, want %t for %s", got, tc.want, tc.args)
			}
		})
	}
}
