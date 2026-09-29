package config

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"
)

type UpdateHistoryEntry struct {
	ID        string    `json:"id"`
	Started   time.Time `json:"started_at"`
	Finished  time.Time `json:"finished_at,omitempty"`
	Component string    `json:"component"`
	Origin    string    `json:"origin"`
	Before    string    `json:"before,omitempty"`
	After     string    `json:"after,omitempty"`
	Status    string    `json:"status"`
}

func BeginUpdateHistory(c Config, root, component string) (string, error) {
	if component != "envpilot" && !containsComponent(Names, component) {
		return "", fmt.Errorf("E_HISTORY_COMPONENT")
	}
	dir := filepath.Join(Dir(), "updates", "history")
	if err := os.MkdirAll(dir, 0700); err != nil {
		return "", err
	}
	f, err := os.CreateTemp(dir, "event-*.json")
	if err != nil {
		return "", err
	}
	defer f.Close()
	if err = f.Chmod(0600); err != nil {
		return "", err
	}
	id := filepath.Base(f.Name())
	before, _ := installedUpdate(c, root, component)
	origin := "manual"
	if os.Getenv("ENVPILOT_UPDATE_ORIGIN") == "automatic" {
		origin = "automatic"
	}
	entry := UpdateHistoryEntry{ID: id, Started: time.Now().UTC(), Component: component, Origin: origin, Before: before, Status: "in_progress"}
	err = json.NewEncoder(f).Encode(entry)
	return id, err
}
func FinishUpdateHistory(c Config, root, id, exitCode string) error {
	if !regexp.MustCompile(`^event-[A-Za-z0-9]+\.json$`).MatchString(id) {
		return fmt.Errorf("E_HISTORY_ID")
	}
	p := filepath.Join(Dir(), "updates", "history", id)
	b, err := os.ReadFile(p)
	var entry UpdateHistoryEntry
	if err == nil {
		err = json.Unmarshal(b, &entry)
	}
	if err != nil {
		return err
	}
	if !entry.Finished.IsZero() {
		return nil
	}
	if entry.Component == "envpilot" {
		if b, e := os.ReadFile(filepath.Join(Dir(), "command-root")); e == nil {
			root = strings.TrimSpace(string(b))
		}
	}
	entry.After, _ = installedUpdate(c, root, entry.Component)
	entry.Finished = time.Now().UTC()
	switch {
	case exitCode != "0":
		entry.Status = "failed"
	case entry.Before == "" && entry.After != "":
		entry.Status = "installed"
	case entry.After == "":
		entry.Status = "completed_version_unknown"
	case entry.Before == entry.After:
		entry.Status = "unchanged"
	default:
		entry.Status = "updated"
	}
	b, err = SafeJSON(entry)
	if err == nil {
		err = WriteAtomic(p, b, 0600)
	}
	return err
}
func UpdateHistory(c Config, days int, component, format string) error {
	if days < 1 || days > 36500 {
		return fmt.Errorf("history days must be between 1 and 36500")
	}
	if component != "" && component != "envpilot" && !containsComponent(Names, component) {
		return fmt.Errorf("E_HISTORY_COMPONENT")
	}
	entries := []UpdateHistoryEntry{}
	files, err := filepath.Glob(filepath.Join(Dir(), "updates", "history", "event-*.json"))
	if err != nil {
		return err
	}
	cutoff := time.Now().Add(-time.Duration(days) * 24 * time.Hour)
	for _, file := range files {
		b, e := os.ReadFile(file)
		if e != nil {
			return e
		}
		var entry UpdateHistoryEntry
		if e = json.Unmarshal(b, &entry); e != nil {
			return fmt.Errorf("E_HISTORY_STATE: %s", filepath.Base(file))
		}
		if entry.Started.Before(cutoff) || component != "" && entry.Component != component {
			continue
		}
		entries = append(entries, entry)
	}
	sort.Slice(entries, func(i, j int) bool { return entries[i].Started.After(entries[j].Started) })
	if format == "json" {
		b, _ := SafeJSON(entries)
		fmt.Println(string(b))
		return nil
	}
	fmt.Println(Text(c.Language, "Update history, last ", "更新历史，最近 ") + strconv.Itoa(days) + Text(c.Language, " days (recorded since this feature was enabled)", " 天（从启用本功能起记录）"))
	for _, entry := range entries {
		status, origin := entry.Status, entry.Origin
		if IsChinese(c.Language) {
			status = map[string]string{"updated": "已更新", "installed": "已安装", "unchanged": "版本未变", "failed": "失败", "in_progress": "进行中/未完成", "completed_version_unknown": "完成，版本未知"}[status]
			origin = map[string]string{"manual": "手动", "automatic": "自动"}[origin]
		}
		before, after := entry.Before, entry.After
		if before == "" {
			before = "?"
		}
		if after == "" {
			after = "?"
		}
		fmt.Printf("%s  %-9s  %s → %s  [%s/%s]\n", entry.Started.Local().Format("2006-01-02 15:04:05"), entry.Component, before, after, origin, status)
	}
	if len(entries) == 0 {
		fmt.Println(Text(c.Language, "No recorded updates in this period.", "此时间范围内没有更新记录。"))
	}
	return nil
}
