package config

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"regexp"
	"runtime"
	"sort"
	"strings"
	"time"

	"go.yaml.in/yaml/v3"
)

var yamlLineNumber = regexp.MustCompile(`\bline ([0-9]+)\b`)

// Edit the selected file itself, so the user can repair malformed YAML and an
// editor that stays open serves the same saved file that the scheduler reads.
func EditConfig(path string, overrides map[string]string, out io.Writer) error {
	before, priorErr := Load(path, overrides)
	_, originalFile := os.Stat(before.Path)
	editor := os.Getenv("EDITOR")
	if editor == "" {
		editor = "vi"
		if runtime.GOOS == "windows" {
			editor = "notepad.exe"
		}
	}
	if err := os.MkdirAll(filepath.Dir(before.Path), 0700); err != nil {
		return err
	}
	cmd := exec.Command(editor, before.Path)
	// Preserve PowerShell's existing support for executable editor scripts.
	if runtime.GOOS == "windows" && strings.EqualFold(filepath.Ext(editor), ".ps1") {
		shell, err := exec.LookPath("pwsh")
		if err != nil {
			shell = "powershell.exe"
		}
		cmd = exec.Command(shell, "-NoProfile", "-File", editor, before.Path)
	}
	cmd.Stdin, cmd.Stdout, cmd.Stderr = os.Stdin, os.Stdout, os.Stderr
	if err := cmd.Run(); err != nil {
		return err
	}
	if _, err := os.Stat(before.Path); errors.Is(err, os.ErrNotExist) && errors.Is(originalFile, os.ErrNotExist) {
		fmt.Fprintln(out, Text(before.Config.Language, "Editor closed without a saved configuration.", "编辑器退出时没有已保存的配置文件。"))
		return nil
	} else if err != nil {
		return err
	}
	after, err := Load(before.Path, overrides)
	if err != nil {
		// YAML type errors can quote the offending scalar. Give the file and
		// line for repair without copying credentials into logs or a terminal.
		lang := overrides["ENVPILOT_LANG"]
		if lang == "" {
			lang = before.Config.Language
		}
		hint := Text(lang, "Review field names, values and indentation.", "请检查字段名称、取值和缩进。")
		if line := yamlLineNumber.FindStringSubmatch(err.Error()); line != nil {
			hint = fmt.Sprintf(Text(lang, "Review line %s.", "请检查第 %s 行。"), line[1])
		} else {
			key, _, _ := strings.Cut(err.Error(), ":")
			// Only echo statically known YAML fields. Dynamic keys may be private.
			var schema yaml.Node
			if schema.Encode(Defaults()) == nil {
				n := &schema
				for _, part := range strings.Split(key, ".") {
					n = yamlField(n, part)
				}
				if n != nil {
					hint = fmt.Sprintf(Text(lang, "Review %s.", "请检查 %s。"), key)
				}
			}
		}
		return fmt.Errorf("E_CONFIG_EDIT_INVALID: %s. %s %s", before.Path, hint, Text(lang, "Use envpilot config edit to correct the saved file.", "请用 envpilot config edit 修正已保存的配置。"))
	}
	c := after.Config
	tr := func(en, zh string) string { return Text(c.Language, en, zh) }
	fmt.Fprintln(out, tr("Configuration is valid.", "配置校验通过。"), after.Path)
	if priorErr == nil {
		changed := changedConfigFields(before.Config, c)
		if len(changed) == 0 {
			fmt.Fprintln(out, tr("Effective settings are unchanged.", "生效设置没有变化。"))
		} else {
			fmt.Fprintln(out, tr("Changed settings:", "生效设置已变更："), strings.Join(changed, ", "))
		}
		for _, key := range changed {
			if strings.HasPrefix(key, "shell.") || strings.HasPrefix(key, "install.") {
				fmt.Fprintln(out, tr("Review installation and shell changes with envpilot plan, then run envpilot apply to apply them.", "用 envpilot plan 查看安装及 Shell 的拟议变更，再用 envpilot apply 应用。"))
				break
			}
		}
	}
	printEditPolicies(out, before.Config, c, priorErr != nil)
	s := inspectScheduler(after.Path, time.Now())
	switch s.Registration {
	case "registered", "registered_hourly":
		fmt.Fprintln(out, tr("The registered scheduler reads this file on its next wake.", "已登记的定时任务会在下次唤醒时读取此文件。"))
	case "legacy_launcher":
		fmt.Fprintln(out, tr("The existing launcher reads this file on its next run. To record scheduled triggers, run envpilot updates enable.", "旧版定时脚本将在下次运行时读取此文件。要记录实际触发时间，可运行 envpilot updates enable。"))
	case "absent":
		fmt.Fprintln(out, tr("No scheduler is registered. To enable scheduled maintenance for this file, run envpilot updates enable --config", "尚未登记定时任务。要定时维护该配置，请执行 envpilot updates enable --config"), Quote(after.Path))
	case "other_config":
		fmt.Fprintln(out, tr("The scheduler is registered for a different file. To select this file, run envpilot updates enable --config", "定时任务当前登记的是另一个配置文件。要切换至此文件，请执行 envpilot updates enable --config"), Quote(after.Path))
	default:
		fmt.Fprintln(out, tr("Scheduler registration needs review. Run envpilot doctor with this configuration.", "请用 envpilot doctor 查看此配置的调度器登记状态。"))
	}
	return nil
}

// Print field names only. Dynamic environment entries may be confidential.
func changedConfigFields(before, after Config) []string {
	asMap := func(c Config) map[string]any {
		data, _ := json.Marshal(c)
		var values map[string]any
		_ = json.Unmarshal(data, &values)
		return values
	}
	var names []string
	var walk func(string, any, any)
	walk = func(key string, left, right any) {
		if reflect.DeepEqual(left, right) {
			return
		}
		a, amap := left.(map[string]any)
		b, bmap := right.(map[string]any)
		if key == "env" || (!amap && !bmap) {
			names = append(names, key)
			return
		}
		if key != "" {
			key += "."
		}
		for k := range a {
			walk(key+k, a[k], b[k])
		}
		for k := range b {
			if _, ok := a[k]; !ok {
				walk(key+k, nil, b[k])
			}
		}
	}
	walk("", asMap(before), asMap(after))
	sort.Strings(names)
	return names
}

func printEditPolicies(w io.Writer, before, after Config, all bool) {
	tr := func(en, zh string) string { return Text(after.Language, en, zh) }
	mode := func(c Config, name string, names []string) string {
		if !c.Updates.Enabled || !containsComponent(names, name) {
			return tr("off", "已停用")
		}
		p := taskPolicy(c.Updates, name)
		if !p.AutoApply {
			return fmt.Sprintf(tr("check only, every %d day(s)", "仅检查，每 %d 天"), p.IntervalDays)
		}
		return fmt.Sprintf(tr("automatic, every %d day(s), %s–%s %s", "窗口内自动执行，每 %d 天，%s–%s %s"), p.IntervalDays, p.WindowStart, p.WindowEnd, p.Timezone)
	}
	previous, next := scheduledNames(before, true), scheduledNames(after, true)
	for _, name := range append(append([]string{}, Names...), "envpilot", "models", "subscription") {
		label := mode(after, name, next)
		if all || label != mode(before, name, previous) {
			fmt.Fprintf(w, "  %s: %s\n", name, label)
		}
	}
}
