package config

import (
	"context"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"time"
)

type mihomoDarwinListener struct {
	pid     string
	uid     string
	address string
}

func verifyMihomoListenerOwner(ctx context.Context, port int, expected, directory string) error {
	ctx, cancel := context.WithTimeout(ctx, 8*time.Second)
	defer cancel()
	command := exec.CommandContext(ctx, "/usr/sbin/lsof", "-nP", "-a", "-iTCP:"+strconv.Itoa(port), "-sTCP:LISTEN", "-Fpun")
	data, err := command.Output()
	if err != nil {
		if exit, ok := err.(*exec.ExitError); ok && exit.ExitCode() == 1 && len(data) == 0 {
			return errMihomoNoListener
		}
		return errMihomoUnverifiedOwner
	}
	listeners := []mihomoDarwinListener{}
	current := mihomoDarwinListener{}
	for _, line := range strings.Split(string(data), "\n") {
		if len(line) < 2 {
			continue
		}
		switch line[0] {
		case 'p':
			current = mihomoDarwinListener{pid: line[1:]}
		case 'u':
			current.uid = line[1:]
		case 'n':
			current.address = line[1:]
			listeners = append(listeners, current)
		}
	}
	exact, wildcard := []mihomoDarwinListener{}, []mihomoDarwinListener{}
	for _, listener := range listeners {
		if listener.address == "127.0.0.1:"+strconv.Itoa(port) {
			exact = append(exact, listener)
		} else if listener.address == "*:"+strconv.Itoa(port) || listener.address == "0.0.0.0:"+strconv.Itoa(port) {
			wildcard = append(wildcard, listener)
		}
	}
	listeners = exact
	if len(listeners) == 0 {
		listeners = wildcard
	}
	if len(listeners) == 0 {
		return errMihomoNoListener
	}
	for _, listener := range listeners {
		pid, err := strconv.Atoi(listener.pid)
		if err != nil || pid < 1 || listener.uid != strconv.Itoa(os.Geteuid()) {
			return errMihomoUnverifiedOwner
		}
		identity, err := exec.CommandContext(ctx, "/bin/ps", "-p", listener.pid, "-o", "uid=", "-o", "comm=").Output()
		if err != nil {
			return errMihomoUnverifiedOwner
		}
		line := strings.TrimSpace(string(identity))
		fields := strings.Fields(line)
		if len(fields) < 2 || fields[0] != listener.uid {
			return errMihomoUnverifiedOwner
		}
		path := strings.TrimSpace(strings.TrimPrefix(line, fields[0]))
		if !mihomoSameExecutable(path, expected) {
			return errMihomoUnverifiedOwner
		}
		// ps can reflect argv[0]. Also require the executable text mapping
		// reported by lsof, so changing the displayed command is insufficient.
		text, err := exec.CommandContext(ctx, "/usr/sbin/lsof", "-nP", "-a", "-p", listener.pid, "-d", "txt", "-Fn").Output()
		if err != nil {
			return errMihomoUnverifiedOwner
		}
		image := ""
		for _, field := range strings.Split(string(text), "\n") {
			if strings.HasPrefix(field, "n") {
				image = field[1:]
				break
			}
		}
		if !mihomoSameExecutable(image, expected) {
			return errMihomoUnverifiedOwner
		}
	}
	return nil
}
