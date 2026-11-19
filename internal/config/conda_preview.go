package config

import (
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"reflect"
	"regexp"
	"sort"

	"go.yaml.in/yaml/v3"
)

var condaLabel = regexp.MustCompile(`^[A-Za-z0-9_.+!*-]+$`)

// CondaPreview displays package identities and changed top-level keys. Channel URLs,
// channel tokens, arbitrary values and solver diagnostics never enter the output.
func CondaPreview(action, path string, in io.Reader, out io.Writer, lang string) error {
	switch action {
	case "packages":
		type pkg struct {
			Name        string
			Version     string
			BuildString string `json:"build_string"`
			Build       string
		}
		var plan struct {
			Success bool
			Actions struct{ Link, Unlink []pkg }
		}
		if err := json.NewDecoder(io.LimitReader(in, 16<<20)).Decode(&plan); err != nil || !plan.Success {
			return fmt.Errorf("E_CONDA_PLAN: %s", Text(lang, "unable to read the Conda dry-run result", "无法读取 Conda 预演结果"))
		}
		fmt.Fprintln(out, Text(lang, "Proposed changes to base packages", "base 环境拟变更的软件包"))
		if len(plan.Actions.Link)+len(plan.Actions.Unlink) == 0 {
			fmt.Fprintln(out, Text(lang, "No package changes.", "无需变更软件包。"))
			return nil
		}
		for _, op := range []struct {
			symbol string
			pkgs   []pkg
		}{{"-", plan.Actions.Unlink}, {"+", plan.Actions.Link}} {
			for _, p := range op.pkgs {
				build := p.BuildString
				if build == "" {
					build = p.Build
				}
				if !condaLabel.MatchString(p.Name) || !condaLabel.MatchString(p.Version) || (build != "" && !condaLabel.MatchString(build)) {
					return fmt.Errorf("E_CONDA_PLAN: invalid package record")
				}
				fmt.Fprintln(out, op.symbol, p.Name, p.Version, build)
			}
		}
		return nil
	case "condarc":
		home, err := os.UserHomeDir()
		if err != nil {
			return err
		}
		read := func(name string, optional bool) (map[string]any, error) {
			m := map[string]any{}
			b, err := os.ReadFile(name)
			if optional && os.IsNotExist(err) {
				return m, nil
			}
			if err != nil {
				return nil, err
			}
			if yaml.Unmarshal(b, &m) != nil {
				return nil, fmt.Errorf("E_CONDARC_YAML: %s", Text(lang, "cannot parse .condarc to compare changes", "无法解析 .condarc 或比较差异"))
			}
			return m, nil
		}
		old, err := read(filepath.Join(home, ".condarc"), true)
		if err != nil {
			return err
		}
		next, err := read(path, false)
		if err != nil {
			return err
		}
		keys := map[string]bool{}
		for k := range old {
			keys[k] = true
		}
		for k := range next {
			keys[k] = true
		}
		diff := []string{}
		for k := range keys {
			a, found := old[k]
			b, exists := next[k]
			var op string
			switch {
			case !found:
				op = "+"
			case !exists:
				op = "-"
			case !reflect.DeepEqual(a, b):
				op = "~"
			default:
				continue
			}
			if !condaLabel.MatchString(k) || len(k) > 64 {
				k = "<custom>"
			}
			diff = append(diff, op+" "+k)
		}
		sort.Strings(diff)
		fmt.Fprintln(out, Text(lang, "Proposed .condarc key changes (+ add, - remove, ~ modify)", "拟变更的 .condarc 字段（+ 新增，- 删除，~ 修改）"))
		if len(diff) == 0 {
			fmt.Fprintln(out, Text(lang, "No key changes.", "无字段变更。"))
		}
		for _, line := range diff {
			fmt.Fprintln(out, line)
		}
		return nil
	default:
		return fmt.Errorf("use conda-preview packages or condarc")
	}
}
