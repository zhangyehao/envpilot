package config

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"time"
)

type schedulerStatus struct {
	Backend      string    `json:"backend"`
	Registration string    `json:"registration"`
	TriggerState string    `json:"trigger_state"`
	LastTrigger  time.Time `json:"last_trigger"`
	LastOutcome  string    `json:"last_outcome,omitempty"`
}

// The marker previously written by updates enable is only a hint. Query the live
// scheduler on this node, which may no longer contain the recorded timer/job.
func queryScheduler(backend, launcher string) string {
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	var cmd *exec.Cmd
	switch backend {
	case "cron":
		cmd = exec.CommandContext(ctx, "crontab", "-l")
	case "systemd":
		cmd = exec.CommandContext(ctx, "systemctl", "--user", "show", "envpilot-updates.timer", "-p", "LoadState", "-p", "ActiveState", "-p", "UnitFileState")
	case "launchd":
		cmd = exec.CommandContext(ctx, "launchctl", "print", "gui/"+strconv.Itoa(os.Getuid())+"/com.envpilot.updates")
	case "tasks":
		shell, err := exec.LookPath("pwsh")
		if err != nil {
			shell = "powershell.exe"
		}
		script := `$ErrorActionPreference='Stop'
try { $task=Get-ScheduledTask -TaskName 'envpilot-updates' -TaskPath '\' }
catch { if ($_.CategoryInfo.Category -eq 'ObjectNotFound') { 'absent'; exit 0 }; throw }
if ($task.State -eq 'Disabled') { 'inactive' }
elseif ($task.Actions.Count -ne 1 -or $task.Actions[0].Arguments -notin @(` + PSQuote(taskArguments(launcher)) + "," + PSQuote("-NoProfile -NonInteractive -File "+strconv.Quote(launcher)) + `)) { 'mismatch' }
else { 'registered' }`
		cmd = exec.CommandContext(ctx, shell, "-NoProfile", "-NonInteractive", "-Command", script)
	default:
		return "unknown"
	}
	cmd.Env = append(os.Environ(), "LC_ALL=C")
	b, err := cmd.CombinedOutput()
	s := string(b)
	if err != nil {
		if backend == "cron" && strings.Contains(s, "no crontab for") || backend == "launchd" && strings.Contains(s, "Could not find service") || backend == "systemd" && strings.Contains(s, "LoadState=not-found") {
			return "absent"
		}
		return "unavailable"
	}
	switch backend {
	case "cron":
		block, e := cronUpdateBlock("", launcher, true)
		if e != nil {
			return "unknown"
		}
		if strings.Contains("\n"+strings.TrimRight(s, "\n")+"\n", "\n"+block) {
			return "registered"
		}
		if strings.Contains("\n"+strings.TrimRight(s, "\n")+"\n", "\n"+strings.Replace(block, "* * * * * /bin/bash", "17 * * * * /bin/bash", 1)) {
			return "registered_hourly"
		}
		if strings.Contains(s, "# >>> envpilot updates >>>") {
			return "mismatch"
		}
		return "absent"
	case "systemd":
		if strings.Contains(s, "LoadState=not-found") {
			return "absent"
		}
		if strings.Contains(s, "ActiveState=active") && strings.Contains(s, "UnitFileState=enabled") {
			return "registered"
		}
		return "inactive"
	case "tasks":
		switch strings.TrimSpace(s) {
		case "absent", "registered", "inactive", "mismatch":
			return strings.TrimSpace(s)
		}
		return "unknown"
	case "launchd":
		if !strings.Contains(s, launcher) {
			return "mismatch"
		}
	}
	return "registered"
}

func scheduleDirectory() string {
	host, _ := os.Hostname()
	sum := sha256.Sum256([]byte(strings.ToLower(host)))
	return filepath.Join(Dir(), "updates", "schedulers", hex.EncodeToString(sum[:8]))
}
func launcherName() string {
	name := "run.sh"
	if runtime.GOOS == "windows" {
		name = "run.ps1"
	}
	return name
}
func scheduleLauncher() string       { return filepath.Join(scheduleDirectory(), launcherName()) }
func legacyScheduleLauncher() string { return filepath.Join(Dir(), "updates", launcherName()) }

func inspectScheduler(path string, now time.Time) schedulerStatus {
	dir := scheduleDirectory()
	launcher := scheduleLauncher()
	s := schedulerStatus{Registration: "unavailable", TriggerState: "never"}
	if b, err := os.ReadFile(updateStatePath(path) + ".trigger"); err == nil {
		var beat scheduledTrigger
		if json.Unmarshal(b, &beat) == nil {
			s.LastTrigger = beat.At
			s.LastOutcome = beat.Outcome
		}
	}
	if !s.LastTrigger.IsZero() {
		s.TriggerState = "recent"
		if now.Sub(s.LastTrigger) > 2*time.Hour {
			s.TriggerState = "stale"
		}
	}
	record, e := os.ReadFile(filepath.Join(dir, "scheduler"))
	if os.IsNotExist(e) {
		old, _ := os.ReadFile(filepath.Join(Dir(), "updates", "scheduler"))
		if len(old) > 0 {
			record = old
			launcher = legacyScheduleLauncher()
		}
	}
	previous := strings.TrimSpace(string(record))
	backends := []string{"systemd", "cron"}
	switch runtime.GOOS {
	case "windows":
		backends = []string{"tasks"}
	case "darwin":
		backends = []string{"launchd"}
	}
	if containsComponent(backends, previous) {
		// Give a previously registered backend priority even if it reports inactive.
		backends = []string{previous}
	}
	for _, backend := range backends {
		status := queryScheduler(backend, launcher)
		if status != "unavailable" || s.Backend == "" {
			s.Backend, s.Registration = backend, status
		}
		if status == "registered" || status == "registered_hourly" || status == "mismatch" || status == "inactive" {
			break
		}
	}
	if s.Registration == "registered" || s.Registration == "registered_hourly" {
		body, err := os.ReadFile(launcher)
		path, _ = filepath.Abs(Expand(path))
		flag := " --config " + Quote(path) + "\n"
		if runtime.GOOS == "windows" {
			flag = " -Config " + PSQuote(path) + "\n"
		}
		switch {
		case err != nil:
			s.Registration = "missing_launcher"
		case !strings.Contains(string(body), flag):
			s.Registration = "other_config"
		case !strings.Contains(string(body), " updates tick"+flag):
			s.Registration = "legacy_launcher"
		}
	}
	return s
}

// Older generated launchers have no way to distinguish a timer activation
// from a manual "updates run". Only replace the exact command for this config.
func refreshScheduleLauncher(path string) error {
	if path == "" {
		path = filepath.Join(Dir(), "config.yaml")
	}
	launcher := legacyScheduleLauncher()
	b, err := os.ReadFile(launcher)
	if os.IsNotExist(err) {
		return nil
	}
	if err != nil {
		return err
	}
	path, err = filepath.Abs(Expand(path))
	if err != nil {
		return err
	}
	h, err := os.UserHomeDir()
	if err != nil {
		return err
	}
	line := "exec " + Quote(filepath.Join(h, ".local", "bin", "envpilot")) + " updates run --config " + Quote(path) + "\n"
	if runtime.GOOS == "windows" {
		line = "& " + PSQuote(filepath.Join(h, ".local", "bin", "envpilot.ps1")) + " updates run -Config " + PSQuote(path) + "\n"
	}
	if strings.Count(string(b), "\n"+line) != 1 {
		return nil
	}
	body := strings.Replace(string(b), "\n"+line, "\n"+strings.Replace(line, " updates run ", " updates tick ", 1), 1)
	return WriteAtomic(launcher, []byte(body), 0700)
}

type maintenanceReport struct {
	UpdateState
	Policy           Updates         `json:"policy"`
	Host             string          `json:"host"`
	MaintenanceOwner bool            `json:"maintenance_owner"`
	Scheduler        schedulerStatus `json:"scheduler"`
	NextWindow       time.Time       `json:"next_window"`
}

func firstInstallationWindow(c Config, host string, now time.Time) time.Time {
	var next time.Time
	if c.Updates.Enabled && maintenanceOwner(c.Updates.MaintenanceHost, host) {
		for _, name := range scheduledNames(c, true) {
			p := taskPolicy(c.Updates, name)
			if p.AutoApply {
				next = earlier(next, nextUpdateWindow(p, now))
			}
		}
	}
	return next
}

func printMaintenance(c Config, path, format string, state UpdateState) error {
	if err := includeInstallationHistory(c, &state); err != nil {
		return err
	}
	names := scheduledNames(c, true)
	seen := map[string]bool{}
	for _, r := range state.Results {
		seen[r.Component] = true
	}
	for _, name := range names {
		if !seen[name] {
			state.Results = append(state.Results, UpdateResult{Component: name, Status: "never"})
		}
	}
	now := time.Now()
	host, _ := os.Hostname()
	report := maintenanceReport{state, c.Updates, host, maintenanceOwner(c.Updates.MaintenanceHost, host), inspectScheduler(path, now), firstInstallationWindow(c, host, now)}
	if format == "json" {
		b, e := SafeJSON(report)
		if e == nil {
			fmt.Println(string(b))
		}
		return e
	}
	tr := func(en, zh string) string { return Text(c.Language, en, zh) }
	mode := tr("check only", "仅检查")
	if c.Updates.AutoApply {
		mode = tr("nightly installation", "窗口内自动安装")
	}
	if !c.Updates.Enabled {
		mode = tr("disabled", "已禁用")
	}
	nextWindow := "-"
	if !report.NextWindow.IsZero() {
		loc, _ := time.LoadLocation(c.Updates.Timezone)
		nextWindow = report.NextWindow.In(loc).Format(time.RFC3339)
	}
	fmt.Printf("%s: %s | %d %s | %s–%s %s | %s %s\n", tr("Default update policy", "默认更新策略"), mode, c.Updates.IntervalDays, tr("days", "天"), c.Updates.WindowStart, c.Updates.WindowEnd, c.Updates.Timezone, tr("next window", "下次窗口"), nextWindow)
	if c.Updates.MaintenanceHost != "" {
		fmt.Printf("%s: %s (%s: %s)\n", tr("Maintenance host", "维护节点"), c.Updates.MaintenanceHost, tr("current host", "本节点"), host)
	}
	s := report.Scheduler
	reg := s.Registration
	regs := map[string]string{"registered": "已登记", "absent": "未登记", "inactive": "已停用", "mismatch": "登记内容不匹配", "unavailable": "系统调度器不可查询", "missing_launcher": "登记脚本缺失", "legacy_launcher": "旧脚本缺少触发记录", "other_config": "已登记其他配置", "unknown": "无法判断"}
	if IsChinese(c.Language) {
		reg = regs[reg]
		if s.Registration == "registered_hourly" {
			reg = "已登记（旧版每小时）"
		}
	}
	trigger := s.TriggerState
	if IsChinese(c.Language) {
		trigger = map[string]string{"never": "尚无记录", "stale": "超过两小时未触发", "recent": "最近两小时已触发"}[trigger]
	}
	outcome := s.LastOutcome
	if IsChinese(c.Language) {
		switch outcome {
		case "ok":
			outcome = "正常"
		case "running":
			outcome = "进行中"
		case "disabled":
			outcome = "已禁用"
		}
	}
	fmt.Printf("%s: %s %s | %s: %s (%s) %s\n", tr("Scheduler", "定时任务"), s.Backend, reg, tr("Last scheduled trigger", "上次定时触发"), updateTime(s.LastTrigger), trigger, outcome)
	if s.Registration != "registered" {
		fmt.Println(tr("Register or repair: envpilot updates enable", "登记或修复：envpilot updates enable"))
	}
	fmt.Printf("%s: %s / %s\n", tr("Last check / next check", "上次检查 / 下次检查"), updateTime(state.LastAttempt), updateTime(state.NextCheck))
	results := map[string]UpdateResult{}
	for _, v := range state.Results {
		results[v.Component] = v
	}
	for _, name := range names {
		v := results[name]
		p := taskPolicy(c.Updates, name)
		label := v.Status
		if label == "" {
			label = "never"
		}
		if IsChinese(c.Language) {
			labels := map[string]string{"never": "尚未执行", "current": "已是当前稳定版或更高版本", "available": "有新版本", "updated": "已更新", "failed": "失败", "not_installed": "未安装", "unmanaged_version": "非稳定版", "compatible": "保留兼容版本", "external": "外部安装", "checked": "已检查", "refreshed": "已刷新", "deferred": "切换已延后", "other_host": "在维护节点执行"}
			if value, ok := labels[label]; ok {
				label = value
			}
		}
		versions := v.Installed
		if v.Latest != "" {
			versions += " → " + v.Latest
		}
		settings := fmt.Sprintf("%d%s %s", p.IntervalDays, tr("d", "天"), tr("check", "检查"))
		if p.AutoApply {
			settings = fmt.Sprintf("%d%s %s–%s", p.IntervalDays, tr("d", "天"), p.WindowStart, p.WindowEnd)
		}
		fmt.Printf("  %-12s %-16s %s %s | %s | %s %s / %s %s\n", name, versions, label, v.ErrorCode, settings, tr("success", "最近成功"), updateTime(v.LastSuccess), tr("applied", "安装或刷新"), updateTime(v.LastApplied))
	}
	return nil
}

func UpdatesCommand(c Config, root, path, action, format string) error {
	switch action {
	case "enable", "disable":
		return ConfigureUpdateSchedule(c, path, action == "enable")
	case "status":
		state, err := readUpdateState(path)
		if err != nil {
			return err
		}
		return printMaintenance(c, path, format, state)
	case "check", "run", "tick":
		beat := scheduledTrigger{At: time.Now().UTC(), Outcome: "running"}
		if action == "tick" {
			if err := beat.save(path); err != nil {
				return err
			}
		}
		var state UpdateState
		err := WithUpdateLock(func() error {
			var e error
			state, e = defaultUpdateRunner().run(c, root, path, action == "check")
			return e
		})
		if action == "tick" {
			switch {
			case errors.Is(err, ErrUpdateBusy):
				beat.Outcome = "E_UPDATE_BUSY"
			case err != nil && err.Error() == "E_UPDATE_OFFLINE":
				beat.Outcome = "E_UPDATE_OFFLINE"
			case err != nil:
				beat.Outcome = "E_UPDATE_FAILED"
			case !c.Updates.Enabled:
				beat.Outcome = "disabled"
			default:
				beat.Outcome = "ok"
			}
			if saveErr := beat.save(path); err == nil {
				err = saveErr
			}
		}
		if !errors.Is(err, ErrUpdateBusy) && action != "tick" {
			if printErr := printMaintenance(c, path, format, state); err == nil {
				err = printErr
			}
		}
		return err
	default:
		return fmt.Errorf("use envpilot updates check|run|status|history|enable|disable")
	}
}

type scheduledTrigger struct {
	At      time.Time `json:"at"`
	Outcome string    `json:"outcome"`
}

func (b scheduledTrigger) save(path string) error {
	file := updateStatePath(path) + ".trigger"
	if err := os.MkdirAll(filepath.Dir(file), 0700); err != nil {
		return err
	}
	lock, err := os.OpenFile(file+".lock", os.O_CREATE|os.O_RDWR, 0600)
	if err != nil {
		return err
	}
	defer lock.Close()
	// A long-running tick may finish after a later tick reported a busy lock.
	for n := 0; ; n++ {
		err = lockUpdateFile(lock)
		if err == nil {
			break
		}
		if n >= 20 {
			return err
		}
		time.Sleep(5 * time.Millisecond)
	}
	defer unlockUpdateFile(lock)
	if previous, err := os.ReadFile(file); err == nil {
		var stored scheduledTrigger
		if json.Unmarshal(previous, &stored) == nil && stored.At.After(b.At) {
			return nil
		}
	}
	data, err := json.Marshal(b)
	if err != nil {
		return err
	}
	return WriteAtomic(file, data, 0600)
}
