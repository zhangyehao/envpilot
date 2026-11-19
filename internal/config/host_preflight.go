package config

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"time"
)

type HostCheck struct {
	Name   string `json:"name"`
	Status string `json:"status"`
	Detail string `json:"detail"`
}

func boundedOutput(name string, args ...string) string {
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	out, err := exec.CommandContext(ctx, name, args...).Output()
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(out))
}

// Linux mountinfo encodes whitespace and backslashes in the mountpoint.
// Choose the deepest containing mount; a shared submount overrides a local /.
func homeMountType(home, mountinfo string) string {
	replacer := strings.NewReplacer(`\040`, " ", `\011`, "\t", `\012`, "\n", `\134`, `\`)
	best, kind := -1, ""
	for _, line := range strings.Split(mountinfo, "\n") {
		before, after, ok := strings.Cut(line, " - ")
		if !ok {
			continue
		}
		fields, fs := strings.Fields(before), strings.Fields(after)
		if len(fields) < 5 || len(fs) == 0 {
			continue
		}
		mount := replacer.Replace(fields[4])
		if len(mount) > best && withinRuntime(mount, home) {
			best, kind = len(mount), fs[0]
		}
	}
	return kind
}

func checkTemporary(dir string) error {
	tmp, err := os.MkdirTemp(dir, ".envpilot-preflight-")
	if err != nil {
		return err
	}
	defer os.RemoveAll(tmp)
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	if runtime.GOOS == "windows" {
		// Actually execute a system binary copy under the exact temporary path.
		b, err := os.ReadFile(filepath.Join(os.Getenv("SystemRoot"), "System32", "cmd.exe"))
		if err != nil {
			return err
		}
		target := filepath.Join(tmp, "check.exe")
		if err = os.WriteFile(target, b, 0700); err != nil {
			return err
		}
		return exec.CommandContext(ctx, target, "/d", "/c", "exit", "0").Run()
	}
	target := filepath.Join(tmp, "check")
	if err = os.WriteFile(target, []byte("#!/bin/sh\nexit 0\n"), 0700); err != nil {
		return err
	}
	return exec.CommandContext(ctx, target).Run()
}

func checkManagedProxy(c Config) (string, string) {
	endpoint := "https://github.com/"
	if c.Install.ReleaseSource == "gitee" {
		endpoint = "https://gitee.com/"
	}
	addr := net.JoinHostPort("127.0.0.1", strconv.Itoa(c.Mihomo.ProxyPort))
	p := &url.URL{Scheme: "http", Host: addr}
	transport := &http.Transport{Proxy: http.ProxyURL(p)}
	defer transport.CloseIdleConnections()
	client := &http.Client{Transport: transport, Timeout: 4 * time.Second, CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}
	req, _ := http.NewRequest(http.MethodHead, endpoint, nil)
	resp, err := client.Do(req)
	if err != nil {
		return "warn", fmt.Sprintf("%s → %s (%s)", addr, endpoint, Text(c.Language, "unreachable", "连接失败"))
	}
	resp.Body.Close()
	status := "ok"
	if resp.StatusCode >= 400 {
		status = "warn"
	}
	return status, fmt.Sprintf("%s → %s (HTTP %d)", addr, endpoint, resp.StatusCode)
}

func PrintPreflight(w io.Writer, c Config, jsonOutput bool) error {
	host, _ := os.Hostname()
	home, _ := os.UserHomeDir()
	text := func(en, zh string) string { return Text(c.Language, en, zh) }
	checks := []HostCheck{{"host", "ok", host}, {"platform", "ok", runtime.GOOS + "/" + runtime.GOARCH}}
	add := func(name, status, detail string) { checks = append(checks, HostCheck{name, status, detail}) }
	if runtime.GOOS == "linux" {
		libc := boundedOutput("getconf", "GNU_LIBC_VERSION")
		status := "ok"
		if libc == "" {
			status = "unknown"
			libc = text("GNU libc unavailable", "未探测到 glibc")
		}
		add("libc", status, libc)
	}
	temp := os.TempDir()
	if err := checkTemporary(temp); err != nil {
		add("temporary", "warn", temp+" "+text("write/execute failed", "无法写入或执行"))
	} else {
		add("temporary", "ok", temp+" "+text("write/execute passed", "可写、可执行"))
	}
	if c.Codex.Remote && runtime.GOOS != "windows" {
		target := Expand(c.Codex.Runtime)
		if target == "" {
			target = "/tmp"
		}
		// A new runtime directory may not exist. Test its nearest existing parent.
		for {
			_, err := os.Stat(target)
			if !os.IsNotExist(err) || target == filepath.Dir(target) {
				break
			}
			target = filepath.Dir(target)
		}
		if target != temp {
			if err := checkTemporary(target); err != nil {
				add("runtime_storage", "warn", target+" "+text("write/execute failed", "无法写入或执行"))
			} else {
				add("runtime_storage", "ok", target)
			}
		}
	}
	fs := ""
	if runtime.GOOS == "linux" {
		if data, err := os.ReadFile("/proc/self/mountinfo"); err == nil {
			if p, err := filepath.EvalSymlinks(home); err == nil {
				home = p
			}
			fs = homeMountType(home, string(data))
		}
	} else if runtime.GOOS == "windows" && strings.HasPrefix(home, `\\`) {
		fs = "smb"
	}
	if fs == "" {
		add("home_filesystem", "unknown", text("sharing could not be determined", "无法判断 home 是否共享"))
	} else {
		shared := map[string]bool{"nfs": true, "nfs4": true, "cifs": true, "smb": true, "smb3": true, "lustre": true, "gpfs": true, "ceph": true, "beegfs": true, "afs": true, "panfs": true, "fuse.sshfs": true}
		detail := text("verify shared use with the administrator", "是否跨节点共享请向管理员确认")
		if shared[fs] {
			detail = text("network filesystem; verify the maintenance host", "网络文件系统，请核对维护节点")
		}
		add("home_filesystem", "info", fs+" — "+detail)
	}
	owner := c.Updates.MaintenanceHost
	if owner == "" {
		owner = text("not configured", "未指定")
	}
	add("maintenance_host", "info", owner)
	sched := []string{}
	for _, cmd := range []string{"systemctl", "crontab", "launchctl", "schtasks.exe", "sbatch", "qsub", "bsub"} {
		if p, err := exec.LookPath(cmd); err == nil {
			sched = append(sched, filepath.Base(p))
		}
	}
	if len(sched) == 0 {
		add("scheduler_commands", "unknown", text("none found in PATH", "PATH 中未找到"))
	} else {
		add("scheduler_commands", "info", strings.Join(sched, ", "))
	}
	ssh := os.Getenv("SSH_CONNECTION") != "" || os.Getenv("SSH_CLIENT") != ""
	origin := text("current process PATH", "当前进程 PATH")
	if ssh {
		origin = text("this SSH session PATH", "本次 SSH 会话 PATH")
	}
	path, err := exec.LookPath("codex")
	if err != nil {
		add("codex", "warn", origin+" — "+text("codex unavailable", "未找到 codex"))
	} else {
		add("codex", "ok", origin+" — "+path)
	}
	s, detail := checkManagedProxy(c)
	add("proxy", s, detail)
	if jsonOutput {
		return json.NewEncoder(w).Encode(checks)
	}
	labels := map[string]string{"host": "主机", "platform": "系统/架构", "libc": "C 运行库", "temporary": "临时目录", "runtime_storage": "运行包存储", "home_filesystem": "Home 文件系统", "maintenance_host": "维护节点", "scheduler_commands": "可用调度器命令", "codex": "Codex", "proxy": "代理连通性"}
	for _, ch := range checks {
		if _, err := fmt.Fprintf(w, "%s [%s]  %s\n", text(ch.Name, labels[ch.Name]), ch.Status, ch.Detail); err != nil {
			return err
		}
	}
	return nil
}
