package config

import (
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"runtime"
	"strings"
	"time"
)

func (p Updates) forComponent(name string) Updates {
	o := p.Policies[name]
	if o.IntervalDays != nil {
		p.IntervalDays = *o.IntervalDays
	}
	if o.AutoApply != nil {
		p.AutoApply = *o.AutoApply
	}
	if o.WindowStart != nil {
		p.WindowStart = *o.WindowStart
	}
	if o.WindowEnd != nil {
		p.WindowEnd = *o.WindowEnd
	}
	return p
}

func validateMaintenance(u Updates) error {
	if strings.ContainsAny(u.MaintenanceHost, " \r\n\t/\\") {
		return fmt.Errorf("updates.maintenance_host: enter a hostname")
	}
	for name := range u.Policies {
		if name != "envpilot" && !containsComponent(Names, name) {
			return fmt.Errorf("unknown updates.policies component: %s", name)
		}
		p := u.forComponent(name)
		if p.IntervalDays < 1 || p.IntervalDays > 365 {
			return fmt.Errorf("updates.policies.%s.interval_days: expected 1-365", name)
		}
		if err := validateUpdateWindow(p); err != nil {
			return fmt.Errorf("updates.policies.%s: %w", name, err)
		}
	}
	for name, p := range map[string]RefreshPolicy{"subscription": u.Subscription, "models": u.Models} {
		if p.IntervalDays < 1 || p.IntervalDays > 365 {
			return fmt.Errorf("updates.%s.interval_days: expected 1-365", name)
		}
	}
	return nil
}

// An explicitly qualified name must match in full (two clusters may share short names).
func maintenanceOwner(configured, host string) bool {
	if configured == "" {
		return true
	}
	configured, host = strings.TrimSuffix(configured, "."), strings.TrimSuffix(host, ".")
	if !strings.Contains(configured, ".") {
		host, _, _ = strings.Cut(host, ".")
	}
	return strings.EqualFold(configured, host)
}

func earlier(a, b time.Time) time.Time {
	if a.IsZero() || (!b.IsZero() && b.Before(a)) {
		return b
	}
	return a
}

func dueAt(prev UpdateResult, p Updates, now time.Time) time.Time {
	if prev.LastAttempt.IsZero() {
		return time.Time{}
	}
	switch prev.Status {
	case "failed":
		return prev.LastAttempt.Add(time.Hour)
	case "deferred":
		if p.AutoApply {
			return nextUpdateWindow(p, prev.LastAttempt.Add(time.Hour))
		}
	case "available":
		if p.AutoApply {
			return nextUpdateWindow(p, now)
		}
	}
	due := prev.LastAttempt.Add(time.Duration(p.IntervalDays) * 24 * time.Hour)
	if prev.Component == "subscription" {
		return nextUpdateWindow(p, due)
	}
	return due
}

func scheduledNames(c Config, tasks bool) []string {
	names := append([]string(nil), c.Updates.Components...)
	if tasks && c.Updates.Models.Enabled {
		names = append(names, "models")
	}
	if tasks && c.Updates.Subscription.Enabled {
		names = append(names, "subscription")
	}
	// Self-update may replace the command root.
	if c.Updates.Envpilot {
		names = append(names, "envpilot")
	}
	return names
}

func taskPolicy(u Updates, name string) Updates {
	switch name {
	case "models":
		p := u.forComponent("codex")
		p.IntervalDays = u.Models.IntervalDays
		p.AutoApply = false
		return p
	case "subscription":
		p := u.forComponent("mihomo")
		p.IntervalDays = u.Subscription.IntervalDays
		p.AutoApply = true
		return p
	default:
		return u.forComponent(name)
	}
}

func (u updateRunner) run(c Config, root, path string, force bool) (UpdateState, error) {
	state, err := readUpdateState(path)
	if err != nil {
		return state, fmt.Errorf("E_UPDATE_STATE: %w", err)
	}
	if !force && !c.Updates.Enabled {
		return state, nil
	}
	if c.Install.Mode == "offline" {
		return state, fmt.Errorf("E_UPDATE_OFFLINE")
	}
	now := u.now().UTC()
	oldState := state
	host, _ := os.Hostname()
	owner := maintenanceOwner(c.Updates.MaintenanceHost, host)
	previous := map[string]UpdateResult{}
	for _, r := range state.Results {
		// State files prior to 0.5.0 have only a batch attempt timestamp.
		if r.LastAttempt.IsZero() && r.Status != "never" && r.Status != "other_host" {
			r.LastAttempt = state.LastAttempt
		}
		previous[r.Component] = r
	}
	state.Results = nil
	names := scheduledNames(c, u.task != nil)
	for _, name := range names {
		r := previous[name]
		r.Component = name
		if r.Status == "" {
			r.Status = "never"
		}
		state.Results = append(state.Results, r)
	}
	state.NextCheck = time.Time{}
	didWork := false
	for i, name := range names {
		p := taskPolicy(c.Updates, name)
		p.AutoApply = p.AutoApply && owner
		r := state.Results[i]
		next := dueAt(r, p, now)
		checked := false
		switch {
		case name == "subscription" && !owner:
			r.Status = "other_host"
			next = time.Time{}
		case name == "subscription" && (force || !inUpdateWindow(p, u.now())):
			// A manual updates check never replaces a subscription or restarts a service.
			if next.IsZero() || next.Before(now) {
				next = nextUpdateWindow(p, now)
			}
		case force || !now.Before(next):
			didWork = true
			checked = true
			r = u.check(c, root, path, r, p, !force)
			r.LastAttempt = u.now().UTC()
			if r.Status != "failed" && r.Status != "deferred" && r.Status != "not_installed" && r.Status != "external" && r.Status != "unmanaged_version" {
				r.LastSuccess = r.LastAttempt
			}
			if r.Status == "updated" || r.Status == "refreshed" {
				r.LastApplied = r.LastAttempt
			}
			next = dueAt(r, p, r.LastAttempt)
			state.LastAttempt = now
		}
		r.NextCheck = next
		state.NextCheck = earlier(state.NextCheck, next)
		state.Results[i] = r
		// A later component can time out, or the launcher can be interrupted.
		// Commit each completed observation while the update lock is still held.
		if checked && i+1 < len(names) {
			if err := writeMaintenanceState(path, state); err != nil {
				return state, err
			}
		}
	}
	if len(names) == 0 {
		// Preserve timestamps for an explicitly empty watch list.
		next := state.LastAttempt.Add(time.Duration(c.Updates.IntervalDays) * 24 * time.Hour)
		if force || !now.Before(next) {
			state.LastAttempt = now
			didWork = true
		}
		state.NextCheck = state.LastAttempt.Add(time.Duration(c.Updates.IntervalDays) * 24 * time.Hour)
	}
	failed := false
	for _, r := range state.Results {
		failed = failed || r.Status == "failed"
	}
	if didWork && !failed {
		state.LastSuccess = now
	}
	if !reflect.DeepEqual(oldState, state) {
		err = writeMaintenanceState(path, state)
	}
	if err == nil && didWork && failed {
		return state, fmt.Errorf("E_UPDATE_FAILED")
	}
	return state, err
}

func writeMaintenanceState(path string, state UpdateState) error {
	b, err := SafeJSON(state)
	if err != nil {
		return err
	}
	return WriteAtomic(updateStatePath(path), b, 0600)
}

func probeCode(err error) string {
	for _, code := range []string{"E_UPDATE_PROBE_TIMEOUT", "E_UPDATE_PROBE_COMMAND", "E_UPDATE_PROBE_FORMAT"} {
		if err.Error() == code || strings.HasPrefix(err.Error(), code+":") {
			return code
		}
	}
	return "E_UPDATE_PROBE"
}

func actionError(r UpdateResult, err error, code string) UpdateResult {
	var exit *exec.ExitError
	if r.Component == "codex" && errors.As(err, &exit) && exit.ExitCode() == 75 {
		r.PendingSwitch = true
		r.Status, r.ErrorCode = "deferred", "E_CODEX_BUSY"
	} else {
		r.Status, r.ErrorCode = "failed", code
	}
	return r
}

func (u updateRunner) check(c Config, root, path string, r UpdateResult, p Updates, allowApply bool) UpdateResult {
	name := r.Component
	r.ErrorCode = ""
	tool := name
	if name == "models" {
		tool = "codex"
	}
	if name == "subscription" {
		tool = "mihomo"
	}
	v, err := u.installed(c, root, tool)
	r.Installed = v
	if err != nil {
		return actionError(r, err, probeCode(err))
	}
	if v == "" {
		r.Status = "not_installed"
		return r
	}
	if name == "models" || name == "subscription" {
		if err = u.task(c, root, path, name); err != nil {
			return actionError(r, err, "E_UPDATE_REFRESH")
		}
		r.Status = "checked"
		if name == "subscription" {
			r.Status = "refreshed"
		}
		return r
	}
	if !knownComponentVersion(name, v) {
		r.Status = "unmanaged_version"
		return r
	}
	if name != "codex" && name != "envpilot" && !managedUpdateComponent(c, name) {
		r.Status = "external"
		return r
	}
	if name == "codex" && c.Updates.MaintenanceHost != "" && u.task != nil && runtime.GOOS != "windows" {
		host, _ := os.Hostname()
		if !maintenanceOwner(c.Updates.MaintenanceHost, host) {
			if err = u.task(c, root, path, "codex-verify"); err != nil {
				return actionError(r, err, "E_UPDATE_NODE_VERIFY")
			}
		}
	}
	latest, err := u.latest(c, name)
	if err != nil {
		return actionError(r, err, "E_UPDATE_CHECK")
	}
	r.Latest, r.LastUpstreamSuccess = latest, u.now().UTC()
	automatic := allowApply && p.AutoApply && inUpdateWindow(p, u.now())
	if !newerComponentVersion(name, r.Latest, v) {
		if name == "codex" && r.PendingSwitch && !automatic {
			r.Status, r.ErrorCode = "deferred", "E_CODEX_PENDING"
			return r
		}
		if name == "codex" && automatic && u.task != nil && runtime.GOOS != "windows" {
			if err = u.task(c, root, path, "codex-reconcile"); err != nil {
				return actionError(r, err, "E_UPDATE_VERIFY")
			}
			if r.PendingSwitch {
				r.Status = "updated"
				r.PendingSwitch = false
				return r
			}
		}
		r.Status = "current"
		return r
	}
	r.Status = "available"
	if !automatic {
		return r
	}
	if err = u.apply(c, root, path, name); err != nil {
		if name == "codex" {
			r.PendingSwitch = true
		}
		return actionError(r, err, "E_UPDATE_APPLY")
	}
	if name == "envpilot" {
		if b, e := os.ReadFile(filepath.Join(Dir(), "command-root")); e == nil {
			root = strings.TrimSpace(string(b))
		}
	}
	actual, err := u.installed(c, root, name)
	if err != nil || !knownComponentVersion(name, actual) || ((name == "codex" || name == "envpilot") && newerVersion(r.Latest, actual)) {
		r.Status, r.ErrorCode = "failed", "E_UPDATE_VERIFY"
		return r
	}
	r.Status = "updated"
	r.PendingSwitch = false
	if actual == v {
		r.Status = "compatible"
	}
	r.Installed = actual
	return r
}
