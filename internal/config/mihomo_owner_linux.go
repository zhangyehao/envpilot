package config

import (
	"context"
	"os"
	"path/filepath"
	"strconv"
	"strings"
)

type mihomoLinuxSocket struct {
	inode string
	uid   int
}

func mihomoLinuxListeners(data []byte, port int, ipv6 bool) (exact, wildcard []mihomoLinuxSocket) {
	for _, line := range strings.Split(string(data), "\n") {
		fields := strings.Fields(line)
		if len(fields) < 10 || fields[3] != "0A" {
			continue
		}
		address := strings.Split(fields[1], ":")
		if len(address) != 2 {
			continue
		}
		number, err := strconv.ParseInt(address[1], 16, 32)
		if err != nil || int(number) != port {
			continue
		}
		uid, err := strconv.Atoi(fields[7])
		if err != nil || fields[9] == "0" {
			continue
		}
		socket := mihomoLinuxSocket{inode: fields[9], uid: uid}
		if !ipv6 && address[0] == "0100007F" {
			exact = append(exact, socket)
		} else if !ipv6 && address[0] == "00000000" {
			wildcard = append(wildcard, socket)
		} else if ipv6 && address[0] == "0000000000000000FFFF00000100007F" {
			exact = append(exact, socket)
		} else if ipv6 && address[0] == "00000000000000000000000000000000" {
			wildcard = append(wildcard, socket)
		}
	}
	return exact, wildcard
}

func verifyMihomoListenerOwner(ctx context.Context, port int, expected, directory string) error {
	tcp, err := os.ReadFile("/proc/net/tcp")
	if err != nil {
		return errMihomoUnverifiedOwner
	}
	exact, wildcard := mihomoLinuxListeners(tcp, port, false)
	listeners := exact
	if len(listeners) == 0 {
		listeners = wildcard
	}
	if len(listeners) == 0 {
		if tcp6, err := os.ReadFile("/proc/net/tcp6"); err == nil {
			exact, wildcard = mihomoLinuxListeners(tcp6, port, true)
			listeners = exact
			if len(listeners) == 0 {
				listeners = wildcard
			}
		} else if !os.IsNotExist(err) {
			return errMihomoUnverifiedOwner
		}
	}
	if len(listeners) == 0 {
		return errMihomoNoListener
	}
	wanted := map[string]bool{}
	for _, socket := range listeners {
		// The listener's effective creator UID is available without inspecting
		// another user's process or sending it any HTTP data.
		if socket.uid != os.Geteuid() {
			return errMihomoUnverifiedOwner
		}
		wanted[socket.inode] = true
	}
	confirmed := map[string]bool{}
	inspect := func(pid string) {
		if _, err := strconv.Atoi(pid); err != nil {
			return
		}
		root := filepath.Join("/proc", pid)
		executable, err := os.Readlink(filepath.Join(root, "exe"))
		if err != nil || !mihomoSameExecutable(executable, expected) {
			return
		}
		status, err := os.ReadFile(filepath.Join(root, "status"))
		if err != nil {
			return
		}
		uidOK := false
		for _, line := range strings.Split(string(status), "\n") {
			if strings.HasPrefix(line, "Uid:") {
				fields := strings.Fields(line)
				if len(fields) >= 3 {
					uid, err := strconv.Atoi(fields[2])
					uidOK = err == nil && uid == os.Geteuid()
				}
				break
			}
		}
		if !uidOK {
			return
		}
		fds, err := os.ReadDir(filepath.Join(root, "fd"))
		if err != nil {
			return
		}
		for _, fd := range fds {
			link, err := os.Readlink(filepath.Join(root, "fd", fd.Name()))
			if err != nil || !strings.HasPrefix(link, "socket:[") || !strings.HasSuffix(link, "]") {
				continue
			}
			inode := strings.TrimSuffix(strings.TrimPrefix(link, "socket:["), "]")
			if wanted[inode] {
				confirmed[inode] = true
			}
		}
	}
	// A pidfile is only a candidate: validate UID, exact executable and the
	// listener inode. Missing/reused pidfiles fall back to process discovery.
	if data, err := os.ReadFile(filepath.Join(filepath.Dir(expected), "mihomo.pid")); err == nil {
		inspect(strings.TrimSpace(string(data)))
	}
	if len(confirmed) == len(wanted) {
		return nil
	}
	inspect(strconv.Itoa(os.Getpid()))
	if len(confirmed) == len(wanted) {
		return nil
	}
	processes, err := os.ReadDir("/proc")
	if err != nil {
		return errMihomoUnverifiedOwner
	}
	for _, process := range processes {
		if ctx.Err() != nil {
			return errMihomoUnverifiedOwner
		}
		inspect(process.Name())
		if len(confirmed) == len(wanted) {
			return nil
		}
	}
	return errMihomoUnverifiedOwner
}
