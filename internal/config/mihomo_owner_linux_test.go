package config

import (
	"context"
	"errors"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"strconv"
	"testing"
)

func TestMihomoLinuxListenerTable(t *testing.T) {
	const fixture = `  sl  local_address rem_address st tx_queue rx_queue tr tm->when retrnsmt uid timeout inode
   0: 0100007F:2382 00000000:0000 0A 00000000:00000000 00:00000000 00000000 1001 0 101
   1: 00000000:2382 00000000:0000 0A 00000000:00000000 00:00000000 00000000 2002 0 102
   2: 0100007F:2382 00000000:0000 01 00000000:00000000 00:00000000 00000000 1001 0 103
   3: 0100007F:2383 00000000:0000 0A 00000000:00000000 00:00000000 00000000 1001 0 104
   4: 0200007F:2382 00000000:0000 0A 00000000:00000000 00:00000000 00000000 1001 0 105
   5: 0100007F:2382 00000000:0000 0A 00000000:00000000 00:00000000 00000000 1001 0 0
   6: 0100007F:2382 00000000:0000 0A 00000000:00000000 00:00000000 00000000 bad 0 106
   7: 0100007F:GGGG 00000000:0000 0A 00000000:00000000 00:00000000 00000000 1001 0 107
`
	exact, wildcard := mihomoLinuxListeners([]byte(fixture), 9090, false)
	if len(exact) != 1 || exact[0].inode != "101" || exact[0].uid != 1001 ||
		len(wildcard) != 1 || wildcard[0].inode != "102" || wildcard[0].uid != 2002 {
		t.Fatalf("listener parsing: exact=%+v wildcard=%+v", exact, wildcard)
	}
	const ipv6 = `0: 0000000000000000FFFF00000100007F:2382 00000000000000000000000000000000:0000 0A 00000000:00000000 00:00000000 00000000 1001 0 201
1: 00000000000000000000000000000000:2382 00000000000000000000000000000000:0000 0A 00000000:00000000 00:00000000 00000000 1001 0 202
2: 00000000000000000000000001000000:2382 00000000000000000000000000000000:0000 0A 00000000:00000000 00:00000000 00000000 1001 0 203
`
	exact, wildcard = mihomoLinuxListeners([]byte(ipv6), 9090, true)
	if len(exact) != 1 || exact[0].inode != "201" || len(wildcard) != 1 || wildcard[0].inode != "202" {
		t.Fatalf("IPv6 listener parsing: exact=%+v wildcard=%+v", exact, wildcard)
	}
}

func TestMihomoLinuxPidFileCannotSubstituteForSocketOwnership(t *testing.T) {
	listener, err := net.Listen("tcp4", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer listener.Close()
	port := listener.Addr().(*net.TCPAddr).Port
	directory := t.TempDir()
	expected := filepath.Join(directory, "mihomo")
	if err := os.WriteFile(expected, []byte("unrelated executable"), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(directory, "mihomo.pid"), []byte(strconv.Itoa(os.Getpid())), 0600); err != nil {
		t.Fatal(err)
	}
	if err := verifyMihomoListenerOwner(context.Background(), port, expected, ""); !errors.Is(err, errMihomoUnverifiedOwner) {
		t.Fatalf("forged pidfile accepted without matching executable: %v", err)
	}
}

func TestMihomoLinuxMissingPidFileDoesNotHideManagedListener(t *testing.T) {
	listener, err := net.Listen("tcp4", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer listener.Close()
	executable, err := os.Executable()
	if err != nil {
		t.Fatal(err)
	}
	directory := t.TempDir()
	expected := filepath.Join(directory, "mihomo")
	if err := os.Symlink(executable, expected); err != nil {
		t.Fatal(err)
	}
	port := listener.Addr().(*net.TCPAddr).Port
	for _, pid := range []string{"", "999999999", fmt.Sprint(os.Getppid()), "../../not-a-pid"} {
		if pid != "" {
			if err := os.WriteFile(filepath.Join(directory, "mihomo.pid"), []byte(pid), 0600); err != nil {
				t.Fatal(err)
			}
		}
		if err := verifyMihomoListenerOwner(context.Background(), port, expected, ""); err != nil {
			t.Fatalf("missing/stale pidfile %q hid valid listener: %v", pid, err)
		}
	}
}
