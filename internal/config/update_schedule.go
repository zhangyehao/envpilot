package config

import (
	"encoding/xml"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
)

func scheduleCommand(name string, args ...string) error {
	cmd := exec.Command(name, args...)
	// Scheduler failures contain no protected configuration.
	b, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("E_UPDATE_SCHEDULER: %s: %s", name, strings.TrimSpace(string(b)))
	}
	return nil
}

func cronUpdateBlock(existing, launcher string, enable bool) (string, error) {
	const begin, end = "# >>> envpilot updates >>>", "# <<< envpilot updates <<<"
	lines, out, inside := strings.Split(strings.TrimSuffix(existing, "\n"), "\n"), []string{}, false
	for _, line := range lines {
		switch line {
		case begin:
			if inside {
				return "", fmt.Errorf("E_UPDATE_CRONTAB: nested managed block")
			}
			inside = true
		case end:
			if !inside {
				return "", fmt.Errorf("E_UPDATE_CRONTAB: unmatched managed block")
			}
			inside = false
		default:
			if !inside {
				out = append(out, line)
			}
		}
	}
	if inside {
		return "", fmt.Errorf("E_UPDATE_CRONTAB: incomplete managed block")
	}
	body := strings.TrimRight(strings.Join(out, "\n"), "\n")
	if enable {
		if strings.ContainsAny(launcher, "\r\n%") {
			return "", fmt.Errorf("E_UPDATE_CRONTAB: unsupported path")
		}
		if body != "" {
			body += "\n"
		}
		body += begin + "\n17 * * * * /bin/bash " + Quote(launcher) + " >/dev/null 2>&1\n" + end
	}
	return body + "\n", nil
}

func ConfigureUpdateSchedule(c Config, path string, enable bool) error {
	dir := filepath.Join(Dir(), "updates")
	record := filepath.Join(dir, "scheduler")
	old, _ := os.ReadFile(record)
	backend := strings.TrimSpace(string(old))
	h, _ := os.UserHomeDir()
	path, err := filepath.Abs(Expand(path))
	if err != nil {
		return err
	}
	if enable && !c.Updates.Enabled {
		return fmt.Errorf("E_UPDATE_DISABLED: set updates.enabled: true before enabling the scheduler")
	}
	command := filepath.Join(h, ".local", "bin", "envpilot")
	if runtime.GOOS == "windows" {
		command += ".ps1"
	}
	if enable {
		if _, err = os.Stat(command); err != nil {
			return fmt.Errorf("E_UPDATE_ENTRYPOINT: run envpilot setup-command first")
		}
		if err = os.MkdirAll(dir, 0700); err != nil {
			return err
		}
	}
	launcher := filepath.Join(dir, "run.sh")
	if runtime.GOOS == "windows" {
		launcher = filepath.Join(dir, "run.ps1")
	}
	if enable {
		// Capture paths only, never environment credentials, proxy passwords or keys.
		body := "#!/usr/bin/env bash\nset -eu\numask 077\nexport HOME=" + Quote(h) + "\nexport ENVPILOT_CONFIG_DIR=" + Quote(Dir()) + "\n"
		paths := []string{filepath.Join(h, ".local", "bin"), "/usr/local/bin", "/usr/bin", "/bin"}
		for _, p := range c.Shell.Paths {
			paths = append(paths, Expand(p))
		}
		body += "export PATH=" + Quote(strings.Join(paths, ":")) + "\n"
		body += "exec " + Quote(command) + " updates run --config " + Quote(path) + "\n"
		if runtime.GOOS == "windows" {
			body = "$ErrorActionPreference = 'Stop'\n$env:ENVPILOT_CONFIG_DIR = " + PSQuote(Dir()) + "\n& " + PSQuote(command) + " updates run -Config " + PSQuote(path) + "\nexit $LASTEXITCODE\n"
		}
		if err = WriteAtomic(launcher, []byte(body), 0700); err != nil {
			return err
		}
	}
	if backend == "" {
		if !enable {
			fmt.Println(Text(c.Language, "No update scheduler is registered.", "未登记更新定时任务。"))
			return nil
		}
		switch runtime.GOOS {
		case "windows":
			backend = "tasks"
		case "darwin":
			backend = "launchd"
		default:
			if exec.Command("systemctl", "--user", "show-environment").Run() == nil {
				backend = "systemd"
			} else {
				backend = "cron"
			}
		}
	}
	switch backend {
	case "systemd":
		unitDir := filepath.Join(h, ".config", "systemd", "user")
		unit := filepath.Join(unitDir, "envpilot-updates.service")
		timer := filepath.Join(unitDir, "envpilot-updates.timer")
		if enable {
			// systemd expands percent specifiers even inside quoted arguments.
			escaped := strconv.Quote(strings.ReplaceAll(launcher, "%", "%%"))
			if err = WriteAtomic(unit, []byte("[Unit]\nDescription=envpilot update checks\n[Service]\nType=oneshot\nExecStart=/bin/bash "+escaped+"\n"), 0600); err != nil {
				return err
			}
			if err = WriteAtomic(timer, []byte("[Unit]\nDescription=envpilot update checks (YAML interval)\n[Timer]\nOnCalendar=hourly\nPersistent=true\n[Install]\nWantedBy=timers.target\n"), 0600); err != nil {
				return err
			}
			if err = scheduleCommand("systemctl", "--user", "daemon-reload"); err == nil {
				err = scheduleCommand("systemctl", "--user", "enable", "--now", "envpilot-updates.timer")
			}
		} else {
			err = scheduleCommand("systemctl", "--user", "disable", "--now", "envpilot-updates.timer")
			if err == nil {
				_ = os.Remove(unit)
				_ = os.Remove(timer)
				err = scheduleCommand("systemctl", "--user", "daemon-reload")
			}
		}
	case "cron":
		cmd := exec.Command("crontab", "-l")
		cmd.Env = append(os.Environ(), "LC_ALL=C")
		existing, readErr := cmd.CombinedOutput()
		if readErr != nil {
			if !strings.Contains(string(existing), "no crontab for") {
				return fmt.Errorf("E_UPDATE_SCHEDULER: crontab unavailable; install/enable cron or run envpilot updates run from your scheduler")
			}
			existing = nil
		}
		var body string
		body, err = cronUpdateBlock(string(existing), launcher, enable)
		if err != nil {
			return err
		}
		if err = WriteAtomic(filepath.Join(dir, "crontab.before"), existing, 0600); err != nil {
			return err
		}
		cmd = exec.Command("crontab", "-")
		cmd.Stdin = strings.NewReader(body)
		if b, e := cmd.CombinedOutput(); e != nil {
			err = fmt.Errorf("E_UPDATE_SCHEDULER: %s", strings.TrimSpace(string(b)))
		}
	case "launchd":
		plist := filepath.Join(h, "Library", "LaunchAgents", "com.envpilot.updates.plist")
		label := "gui/" + strconv.Itoa(os.Getuid()) + "/com.envpilot.updates"
		if enable {
			var escaped strings.Builder
			_ = xml.EscapeText(&escaped, []byte(launcher))
			body := `<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>Label</key><string>com.envpilot.updates</string><key>ProgramArguments</key><array><string>/bin/bash</string><string>` + escaped.String() + `</string></array><key>StartInterval</key><integer>3600</integer><key>RunAtLoad</key><true/></dict></plist>`
			if err = WriteAtomic(plist, []byte(body), 0600); err != nil {
				return err
			}
			_ = exec.Command("launchctl", "bootout", label).Run()
			err = scheduleCommand("launchctl", "bootstrap", "gui/"+strconv.Itoa(os.Getuid()), plist)
		} else {
			err = scheduleCommand("launchctl", "bootout", label)
			if err == nil {
				_ = os.Remove(plist)
			}
		}
	case "tasks":
		shell, e := exec.LookPath("pwsh")
		if e != nil {
			shell = "powershell.exe"
		}
		script := "Unregister-ScheduledTask -TaskName 'envpilot-updates' -Confirm:$false -ErrorAction SilentlyContinue"
		if enable {
			// InteractiveToken runs as this user, without asking for/storing passwords.
			script = "$ErrorActionPreference='Stop'; $a=New-ScheduledTaskAction -Execute " + PSQuote(shell) + " -Argument " + PSQuote("-NoProfile -NonInteractive -File "+strconv.Quote(launcher)) + "; $t=New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Hours 1); $p=New-ScheduledTaskPrincipal -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive; $s=New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Hours 2); Register-ScheduledTask -TaskName 'envpilot-updates' -Action $a -Trigger $t -Principal $p -Settings $s -Force | Out-Null"
		}
		err = scheduleCommand(shell, "-NoProfile", "-NonInteractive", "-Command", script)
	default:
		return fmt.Errorf("E_UPDATE_SCHEDULER: unknown backend")
	}
	if err != nil {
		return err
	}
	if enable {
		if err = WriteAtomic(record, []byte(backend+"\n"), 0600); err != nil {
			return err
		}
		fmt.Println(Text(c.Language, "Update scheduler enabled. Checks follow updates.interval_days; automatic installation requires updates.auto_apply: true.", "已启用更新定时任务。检查间隔使用 updates.interval_days；自动安装需设置 updates.auto_apply: true。"))
		if c.Updates.AutoApply && containsComponent(c.Updates.Components, "codex") {
			fmt.Println(Text(c.Language, "Codex updates restart a running app-server and can interrupt tasks.", "Codex 更新会重启正在运行的 app-server，可能中断任务。"))
		}
	} else {
		_ = os.Remove(record)
		fmt.Println(Text(c.Language, "Update scheduler disabled; configuration and history were preserved.", "更新定时任务已禁用，配置和历史记录保留。"))
	}
	return nil
}
