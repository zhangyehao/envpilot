package main

import (
	"bufio"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/zhangyehao/envpilot/internal/config"
)

var version = "0.5.1"

func main() {
	if err := run(os.Args[1:]); err != nil {
		// Refresh already reports source-specific changes. Preserve failure for the scheduler
		// without repeatedly printing the same catalog error on an unchanged observation.
		if errors.Is(err, config.ErrModelRefresh) {
			os.Exit(4)
		}
		if err == config.ErrModelRefresh {
			os.Exit(1)
		}
		fmt.Fprintln(os.Stderr, "E_ENVPILOT:", config.Translate(os.Getenv("ENVPILOT_LANG"), err.Error()))
		os.Exit(1)
	}
}
func run(args []string) error {
	if len(args) == 0 {
		return fmt.Errorf("usage: envpilot-core <init|validate|show|export|plan|render|shell|snapshot|restore|run|version>")
	}
	cmd := args[0]
	args = args[1:]
	if cmd == "complete" || cmd == "suggest" {
		if len(args) == 0 || !strings.HasPrefix(args[0], "word=") {
			return nil
		}
		for _, candidate := range config.CommandCandidates(args[1:], strings.TrimPrefix(args[0], "word="), cmd == "suggest") {
			fmt.Println(candidate)
		}
		return nil
	}
	path, lang, format, root, kind, target := "", "", "json", "", "bash", ""
	envFile, keyEnv, keyFile := "", "", ""
	expectedHome := ""
	runtimeSource, stageMode := "", "0"
	historyDays, historyComponent := 30, ""
	checkOnly := false
	stream := false
	rest := []string{}
	overrides := map[string]string{}
	if v := os.Getenv("ENVPILOT_OVERRIDES"); v != "" {
		if e := json.Unmarshal([]byte(v), &overrides); e != nil {
			return e
		}
	}
	for i := 0; i < len(args); i++ {
		a := args[i]
		if a == "--" {
			rest = append(rest, args[i+1:]...)
			break
		}
		switch a {
		case "--config", "--lang", "--format", "--root", "--shell", "--target", "--socket", "--env-file", "--key-env", "--key-file", "--expected-home", "--source", "--stage-mode", "--days", "--component":
			if i+1 >= len(args) {
				return fmt.Errorf("%s requires a value", a)
			}
			i++
			switch a {
			case "--days":
				var err error
				historyDays, err = strconv.Atoi(args[i])
				if err != nil {
					return fmt.Errorf("history days must be an integer")
				}
			case "--component":
				historyComponent = args[i]
			case "--source":
				runtimeSource = args[i]
			case "--stage-mode":
				stageMode = args[i]
			case "--expected-home":
				expectedHome = args[i]
			case "--env-file":
				envFile = args[i]
			case "--key-env":
				keyEnv = args[i]
			case "--key-file":
				keyFile = args[i]
			case "--config":
				path = args[i]
			case "--lang":
				lang = args[i]
				overrides["ENVPILOT_LANG"] = lang
			case "--format":
				format = args[i]
			case "--root":
				root = args[i]
			case "--shell":
				kind = args[i]
			case "--target", "--socket":
				target = args[i]
			}
		case "--stream":
			stream = true
		case "--check":
			checkOnly = true
		default:
			rest = append(rest, a)
		}
	}
	if cmd == "version" {
		fmt.Println(version)
		return nil
	}
	if cmd == "update-lock" {
		err := config.LockedCommand(rest)
		if child, ok := err.(*exec.ExitError); ok && child.ExitCode() > 0 {
			os.Exit(child.ExitCode())
		}
		return err
	}
	if cmd == "message" {
		if lang == "" {
			lang = os.Getenv("ENVPILOT_LANG")
		}
		if stream {
			scanner := bufio.NewScanner(os.Stdin)
			scanner.Buffer(make([]byte, 4096), 8*1024*1024)
			for scanner.Scan() {
				fmt.Println(config.Translate(lang, scanner.Text()))
			}
			return scanner.Err()
		}
		b, err := io.ReadAll(io.LimitReader(os.Stdin, 1024*1024))
		if err != nil {
			return err
		}
		fmt.Print(config.Translate(lang, string(b)))
		return nil
	}

	if cmd == "exec-with-env" {
		c := config.Defaults()
		c.Secrets = config.Reference{File: envFile}
		c.Codex.APIKey = config.Reference{File: keyFile, Env: keyEnv}
		if home := os.Getenv("CODEX_HOME"); home != "" {
			c.Codex.Home = home
		}
		values, err := c.ChildEnvironment()
		if err != nil {
			return err
		}
		if checkOnly {
			return nil
		}
		if target == "" {
			return fmt.Errorf("executable target is required")
		}
		environment := []string{}
		for _, key := range config.SortedKeys(values) {
			environment = append(environment, key+"="+values[key])
		}
		return config.ExecWithEnvironment(target, rest, environment)
	}

	if cmd == "install-core" {
		return config.InstallCore(root)
	}
	if cmd == "python-asset" {
		if len(rest) != 1 {
			return fmt.Errorf("python-asset requires a requested version (empty for latest)")
		}
		asset, err := config.PythonAsset(rest[0])
		if err == nil {
			fmt.Println(asset)
		}
		return err
	}
	if cmd == "python-local-digest" {
		if len(rest) != 3 || (rest[2] != "online" && rest[2] != "offline") {
			return fmt.Errorf("python-local-digest requires an archive, manifest path and online/offline mode")
		}
		digest, err := config.PythonLocalDigest(rest[0], rest[1], rest[2] == "online")
		if err == nil {
			fmt.Println(digest)
		}
		return err
	}
	if cmd == "probe" {
		result, err := config.Probe(target)
		if err != nil {
			return err
		}
		if expectedHome != "" {
			if err := config.ProbeHome(result, expectedHome); err != nil {
				return err
			}
		}
		if format == "version" {
			version, err := config.ProbeVersion(result)
			if err == nil {
				fmt.Println(version)
			}
			return err
		}
		b, err := json.Marshal(result)
		if err == nil {
			fmt.Println(string(b))
		}
		return err
	}
	if cmd == "runtime-metadata" {
		value, err := config.RuntimeMetadata(runtimeSource)
		if err == nil {
			fmt.Println(value)
		}
		return err
	}
	if cmd == "runtime-stage" {
		value, err := config.StageRuntime(runtimeSource, target, stageMode)
		if err == nil && value != "" {
			fmt.Println(value)
		}
		return err
	}
	if cmd == "runtime-verify" {
		return config.VerifyRuntime(runtimeSource, target)
	}

	if cmd == "codex-activity" {
		return config.PrintCodexActivity(target, expectedHome)
	}
	if cmd == "runtime-activate" {
		return config.ActivateRuntime(target, runtimeSource)
	}
	if cmd == "python-activate" {
		if len(rest) != 3 {
			return fmt.Errorf("python-activate BASE STAGING VERSION")
		}
		return config.ActivatePython(rest[0], rest[1], rest[2])
	}
	if cmd == "init" {
		policy := "check"
		if len(rest) != 0 {
			if len(rest) != 2 || rest[0] != "--policy" {
				return fmt.Errorf("init --policy check|nightly")
			}
			policy = rest[1]
		}
		if err := config.InitWithPolicy(path, lang, policy); err != nil {
			return err
		}
		fmt.Println(config.Text(lang, "Configuration created. Edit it with envpilot config edit, then run envpilot plan. Register maintenance with envpilot updates enable.", "配置已创建。请执行 envpilot config edit 和 envpilot plan；要让维护策略定时运行，请执行 envpilot updates enable。"))
		return nil
	}
	if cmd == "config-edit" {
		return config.EditConfig(path, overrides, os.Stdout)
	}
	r, err := config.Load(path, overrides)
	if err != nil {
		return err
	}
	c := r.Config
	switch cmd {
	case "config-migrate":
		if len(rest) != 1 || (rest[0] != "--preview" && rest[0] != "--apply") {
			return fmt.Errorf("choose --preview or --apply")
		}
		return config.MigrateConfig(r, rest[0] == "--apply", os.Stdout)
	case "host-preflight":
		if target != "" {
			return config.PrintToolPreflight(os.Stdout, r, root, target, format == "json")
		}
		return config.PrintPreflight(os.Stdout, r.Config, format == "json")
	case "config-codex-preferences":
		b, err := config.PortableCodexPreferences(r.Config)
		if err == nil {
			_, err = os.Stdout.Write(b)
		}
		return err
	case "config-portable":
		b, err := config.PortableConfig(r.Path)
		if err == nil {
			_, err = os.Stdout.Write(b)
		}
		return err
	case "completion":
		if len(rest) != 1 {
			return fmt.Errorf("choose bash, zsh or powershell")
		}
		s, err := config.CompletionScript(rest[0])
		if err == nil {
			fmt.Print(s)
		}
		return err
	case "codex-upstream":
		return config.PrintLastCodexStable(r.Path)
	case "conda-preview":
		if len(rest) == 0 || len(rest) > 2 {
			return fmt.Errorf("conda-preview packages|condarc [PATH]")
		}
		file := ""
		if len(rest) == 2 {
			file = rest[1]
		}
		return config.CondaPreview(rest[0], file, os.Stdin, os.Stdout, c.Language)
	case "codex-models":
		return config.CodexModelsCommand(c, runtimeSource, rest, format)
	case "protected-download":
		data, err := io.ReadAll(io.LimitReader(os.Stdin, 64*1024))
		if err != nil {
			return fmt.Errorf("E_SUBSCRIPTION_INPUT: could not read the protected reference")
		}
		return config.DownloadSubscriptionWithOptions(string(data), target, config.SubscriptionDownloadOptions{
			Network: c.Mihomo.SubscriptionNetwork, ProxyPort: c.Mihomo.ProxyPort,
			Language: c.Language, Progress: os.Stderr,
		})
	case "subscription-import":
		return config.ImportSubscription(runtimeSource, target)
	case "mihomo-validate":
		return config.ValidateMihomoConfig(c, target)
	case "mihomo":
		if len(rest) == 0 {
			return fmt.Errorf("E_INPUT_REQUIRED: mihomo action")
		}
		return config.MihomoCommand(c, rest[0], rest[1:], format)
	case "latest-component":
		v, err := config.LatestComponent(target)
		if err == nil {
			fmt.Println(v)
		}
		return err
	case "history-begin":
		if len(rest) != 1 {
			return fmt.Errorf("history-begin requires a component")
		}
		id, err := config.BeginUpdateHistory(c, root, rest[0])
		if err == nil {
			fmt.Println(id)
		}
		return err
	case "history-finish":
		if len(rest) != 2 {
			return fmt.Errorf("history-finish requires id and exit code")
		}
		return config.FinishUpdateHistory(c, root, rest[0], rest[1])
	case "updates":
		action := "status"
		if len(rest) > 0 {
			action = rest[0]
		}
		if action == "history" {
			return config.UpdateHistory(c, historyDays, historyComponent, format)
		}
		return config.UpdatesCommand(c, root, r.Path, action, format, overrides)
	case "secret-export":
		values, err := config.ReadEnvironment(c.Secrets.File)
		if err != nil {
			return err
		}
		if format == "nul" {
			for _, k := range config.SortedKeys(values) {
				fmt.Printf("%s\x00%s\x00", k, values[k])
			}
		} else {
			b, e := json.Marshal(values)
			if e != nil {
				return e
			}
			fmt.Println(string(b))
		}
	case "self-update":
		return config.BundleUpdate(c, root, r.Path)
	case "refresh":
		return config.RefreshScripts(c, root)
	case "preflight":
		return config.Preflight(c)
	case "validate":
		fmt.Println(config.Text(c.Language, "Configuration is valid.", "配置校验通过。"))
	case "show":
		b, e := config.SafeJSON(r)
		if e != nil {
			return e
		}
		fmt.Println(string(b))
	case "export":
		m := r.Environment()
		if format == "nul" {
			for _, k := range config.SortedKeys(m) {
				fmt.Printf("%s\x00%s\x00", k, m[k])
			}
		} else {
			b, e := json.Marshal(m)
			if e != nil {
				return e
			}
			fmt.Println(string(b))
		}
	case "plan":
		fmt.Println(config.Text(c.Language, "Configuration:", "配置文件："), r.Path)
		fmt.Println(config.Text(c.Language, "Components (install order):", "组件（安装顺序）："), strings.Join(c.OrderedComponents(), ", "))
		fmt.Println(config.Text(c.Language, "Install prefix:", "安装位置："), config.Expand(c.Install.Prefix))
		fmt.Printf("%s %s\n", config.Text(c.Language, "Network mode:", "网络模式："), c.Install.Mode)
		fmt.Printf("%s %t; %s %t\n", config.Text(c.Language, "Shell integration:", "Shell 接入："), c.Shell.Enabled, config.Text(c.Language, "Codex remote:", "Codex 远程运行："), c.Codex.Remote)
		fmt.Println(config.Text(c.Language, "Existing tools are inspected before installation. User profile content is preserved; managed files are snapshotted before changes. Credentials remain in referenced files/environment.", "安装前检查现有工具；保留用户 profile 内容，修改受管文件前创建快照。凭据保留在引用的文件或环境变量中。"))
	case "render":
		return config.Render(c, root, kind)
	case "shell":
		return config.InstallShell(c, root, kind, target, len(rest) > 0 && rest[0] == "remove")
	case "snapshot":
		extra := []string{r.Path}
		if target != "" {
			extra = append(extra, target)
		}
		p, e := config.SnapshotCreate(c, extra)
		if e != nil {
			return e
		}
		fmt.Println(p)
	case "restore":
		p := ""
		if len(rest) > 0 {
			p = rest[0]
		}
		return config.SnapshotRestore(p, c)
	case "run":
		if len(rest) == 0 {
			return fmt.Errorf("run requires a command after --")
		}
		childEnv, err := c.ChildEnvironment()
		if err != nil {
			return err
		}
		e := []string{}
		for _, key := range config.SortedKeys(childEnv) {
			if key != "PATH" {
				e = append(e, key+"="+childEnv[key])
			}
		}

		prefix := config.Expand(c.Install.Prefix)
		paths := []string{filepath.Join(prefix, "git", "current", "bin"), filepath.Join(prefix, "python", "current", "bin"), filepath.Join(prefix, "tmux", "current", "bin")}
		h, _ := os.UserHomeDir()
		paths = append(paths, filepath.Join(h, ".local", "bin"))
		paths = append(paths, c.Shell.Paths...)
		newPath := strings.Join(paths, string(os.PathListSeparator)) + string(os.PathListSeparator) + os.Getenv("PATH")
		e = append(e, "PATH="+newPath)
		// LookPath must use the child PATH, without changing the parent shell.
		old := os.Getenv("PATH")
		_ = os.Setenv("PATH", newPath)
		bin, er := exec.LookPath(rest[0])
		_ = os.Setenv("PATH", old)
		if er != nil {
			return er
		}
		p := exec.Command(bin, rest[1:]...)
		p.Env = e
		p.Stdin = os.Stdin
		p.Stdout = os.Stdout
		p.Stderr = os.Stderr
		if er = p.Run(); er != nil {
			if x, ok := er.(*exec.ExitError); ok {
				os.Exit(x.ExitCode())
			}
			return er
		}
	default:
		return fmt.Errorf("unknown core command: %s", cmd)
	}
	return nil
}
