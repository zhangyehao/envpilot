// Package config is the single configuration boundary for both installers.
package config

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"

	"go.yaml.in/yaml/v3"
)

type Reference struct {
	File string `yaml:"file,omitempty" json:"file,omitempty"`
	Env  string `yaml:"env,omitempty" json:"env,omitempty"`
}
type Install struct {
	Components    []string `yaml:"components" json:"components"`
	Mode          string   `yaml:"mode" json:"mode"`
	Prefix        string   `yaml:"prefix" json:"prefix"`
	ReleaseSource string   `yaml:"release_source" json:"release_source"`
}
type Shell struct {
	Enabled         bool     `yaml:"enabled" json:"enabled"`
	Conda           bool     `yaml:"conda" json:"conda"`
	Modules         []string `yaml:"modules" json:"modules"`
	AutoStartProxy  bool     `yaml:"auto_start_proxy" json:"auto_start_proxy"`
	AutoEnableProxy bool     `yaml:"auto_enable_proxy" json:"auto_enable_proxy"`
	LoadSecrets     bool     `yaml:"load_secrets" json:"load_secrets"`
	HistorySync     bool     `yaml:"history_sync" json:"history_sync"`
	LegacyAliases   bool     `yaml:"legacy_aliases" json:"legacy_aliases"`
	LegacyLocal     bool     `yaml:"legacy_local" json:"legacy_local"`
	Paths           []string `yaml:"paths" json:"paths"`
}
type Mihomo struct {
	ProxyPort    int       `yaml:"proxy_port" json:"proxy_port"`
	APIPort      int       `yaml:"api_port" json:"api_port"`
	SOCKS        bool      `yaml:"socks" json:"socks"`
	Subscription Reference `yaml:"subscription" json:"subscription"`
}
type Conda struct {
	Distribution string `yaml:"distribution" json:"distribution"`
	Prefix       string `yaml:"prefix,omitempty" json:"prefix,omitempty"`
}
type Codex struct {
	Remote       bool      `yaml:"remote" json:"remote"`
	Home         string    `yaml:"home" json:"home"`
	Runtime      string    `yaml:"runtime,omitempty" json:"runtime,omitempty"`
	ReadyTimeout int       `yaml:"ready_timeout" json:"ready_timeout"`
	BaseURL      string    `yaml:"base_url,omitempty" json:"base_url,omitempty"`
	APIKey       Reference `yaml:"api_key" json:"api_key"`
}
type Config struct {
	SourcePath string            `yaml:"-" json:"-"`
	Version    int               `yaml:"version" json:"version"`
	Language   string            `yaml:"language" json:"language"`
	Install    Install           `yaml:"install" json:"install"`
	Shell      Shell             `yaml:"shell" json:"shell"`
	Mihomo     Mihomo            `yaml:"mihomo" json:"mihomo"`
	Conda      Conda             `yaml:"conda" json:"conda"`
	Codex      Codex             `yaml:"codex" json:"codex"`
	Secrets    Reference         `yaml:"secrets" json:"secrets"`
	Env        map[string]string `yaml:"env" json:"env"`
}
type Resolved struct {
	Config  Config            `json:"config"`
	Sources map[string]string `json:"sources"`
	Path    string            `json:"path"`
}

var Names = []string{"mihomo", "git", "python", "conda", "mamba", "codex", "github", "tmux"}
var variable = regexp.MustCompile(`^[A-Za-z_][A-Za-z0-9_]*$`)
var sensitive = regexp.MustCompile(`(?i)key|token|secret|password|passwd|auth|subscription`)

var environmentFields = map[string]string{
	"ENVPILOT_LANG": "language", "ENVPILOT_MODE": "install.mode", "ENVPILOT_PREFIX": "install.prefix",
	"ENVPILOT_RELEASE_SOURCE": "install.release_source", "ENVPILOT_CONDA_DISTRIBUTION": "conda.distribution",
	"CODEX_HOME": "codex.home", "ENVPILOT_CODEX_RUNTIME_DIR": "codex.runtime",
	"ENVPILOT_CODEX_REMOTE_READY_TIMEOUT": "codex.ready_timeout", "ENVPILOT_CODEX_BASE_URL": "codex.base_url",
	"ENVPILOT_CODEX_SECRETS_FILE": "secrets.file", "MIHOMO_PROXY_PORT": "mihomo.proxy_port", "MIHOMO_API_PORT": "mihomo.api_port",
}

func externalEnvironment(name string) (string, bool) {
	value, exists := os.LookupEnv(name)
	if !exists || value == "" {
		return "", false
	}
	if managed, ok := os.LookupEnv("ENVPILOT_MANAGED_" + name); ok && managed == value {
		return "", false
	}
	if os.Getenv("ENVPILOT_PROFILE_ACTIVE") == "1" {
		legacy := map[string]string{"MIHOMO_PROXY_PORT": "ENVPILOT_LAST_MIHOMO_PROXY_PORT", "MIHOMO_API_PORT": "ENVPILOT_LAST_MIHOMO_API_PORT"}
		if marker := legacy[name]; marker != "" && os.Getenv(marker) == value {
			return "", false
		}
	}
	return value, true
}

func (r Resolved) Environment() map[string]string {
	values := r.Config.Environment()
	for key, field := range environmentFields {
		if value, ok := values[key]; ok && !strings.HasPrefix(r.Sources[field], "environment:") && r.Sources[field] != "argument" {
			values["ENVPILOT_MANAGED_"+key] = value
		}
	}
	return values
}

func Dir() string {
	if v := os.Getenv("ENVPILOT_CONFIG_DIR"); v != "" {
		return v
	}
	h, _ := os.UserHomeDir()
	return filepath.Join(h, ".config", "envpilot")
}
func Expand(p string) string {
	if p == "" {
		return ""
	}
	h, _ := os.UserHomeDir()
	if p == "~" {
		return h
	}
	if strings.HasPrefix(p, "~/") || strings.HasPrefix(p, `~\`) {
		return filepath.Join(h, p[2:])
	}
	return filepath.Clean(p)
}
func Defaults() Config {
	return Config{Version: 1, Language: "auto", Install: Install{Components: []string{}, Mode: "online", Prefix: "~/software", ReleaseSource: "github"}, Shell: Shell{Enabled: true, Modules: []string{}, Paths: []string{}}, Mihomo: Mihomo{ProxyPort: 42290, APIPort: 60290, Subscription: Reference{File: "~/.config/mihomo/subscription.url"}}, Conda: Conda{Distribution: "miniconda"}, Codex: Codex{Home: "~/.codex", ReadyTimeout: 60, APIKey: Reference{Env: "OPENAI_API_KEY"}}, Secrets: Reference{File: "~/.config/secrets/api.env"}, Env: map[string]string{}}
}
func Load(path string, overrides map[string]string) (Resolved, error) {
	if path == "" {
		path = filepath.Join(Dir(), "config.yaml")
	}
	path = Expand(path)
	r := Resolved{Config: Defaults(), Sources: map[string]string{}, Path: path}
	data, err := os.ReadFile(path)
	if err != nil && !os.IsNotExist(err) {
		return r, err
	}
	if err == nil {
		d := yaml.NewDecoder(bytes.NewReader(data))
		d.KnownFields(true)
		if err = d.Decode(&r.Config); err != nil {
			return r, fmt.Errorf("%s: %w", path, err)
		}
		var extra any
		if err = d.Decode(&extra); err != io.EOF {
			return r, fmt.Errorf("one YAML document is required")
		}
		var node yaml.Node
		if yaml.Unmarshal(data, &node) == nil {
			sourceFields(&node, "", r.Sources)
		}
	}
	c := &r.Config
	c.SourcePath = path
	set := func(env, key string, target *string) {
		if v, ok := externalEnvironment(env); ok {
			*target = v
			r.Sources[key] = "environment:" + env
		}
		if v, ok := overrides[env]; ok {
			*target = v
			r.Sources[key] = "argument"
		}
	}
	set("ENVPILOT_LANG", "language", &c.Language)
	set("ENVPILOT_MODE", "install.mode", &c.Install.Mode)
	set("ENVPILOT_PREFIX", "install.prefix", &c.Install.Prefix)
	set("ENVPILOT_RELEASE_SOURCE", "install.release_source", &c.Install.ReleaseSource)
	set("ENVPILOT_CONDA_DISTRIBUTION", "conda.distribution", &c.Conda.Distribution)
	set("CODEX_HOME", "codex.home", &c.Codex.Home)
	set("ENVPILOT_CODEX_RUNTIME_DIR", "codex.runtime", &c.Codex.Runtime)
	set("ENVPILOT_CODEX_BASE_URL", "codex.base_url", &c.Codex.BaseURL)
	set("ENVPILOT_CODEX_SECRETS_FILE", "secrets.file", &c.Secrets.File)
	for _, entry := range []struct {
		env, key string
		dst      *int
	}{{"MIHOMO_PROXY_PORT", "mihomo.proxy_port", &c.Mihomo.ProxyPort}, {"MIHOMO_API_PORT", "mihomo.api_port", &c.Mihomo.APIPort}, {"ENVPILOT_CODEX_REMOTE_READY_TIMEOUT", "codex.ready_timeout", &c.Codex.ReadyTimeout}} {
		v, ok := externalEnvironment(entry.env)
		if v == "" {
			ok = false
		}
		src := "environment:" + entry.env
		if o, present := overrides[entry.env]; present {
			v = o
			ok = true
			src = "argument"
		}
		if ok {
			n, e := strconv.Atoi(v)
			if e != nil {
				return r, fmt.Errorf("%s must be an integer", entry.key)
			}
			*entry.dst = n
			r.Sources[entry.key] = src
		}
	}
	return r, Validate(*c)
}
func sourceFields(n *yaml.Node, prefix string, dst map[string]string) {
	if n.Kind == yaml.DocumentNode {
		for _, v := range n.Content {
			sourceFields(v, prefix, dst)
		}
	}
	if n.Kind == yaml.MappingNode {
		for i := 0; i < len(n.Content); i += 2 {
			k := n.Content[i].Value
			if prefix != "" {
				k = prefix + "." + k
			}
			dst[k] = "config"
			sourceFields(n.Content[i+1], k, dst)
		}
	}
}
func Validate(c Config) error {
	if c.Version != 1 {
		return fmt.Errorf("unsupported config version %d (expected 1)", c.Version)
	}
	if c.Language != "auto" && c.Language != "en" && c.Language != "zh-CN" {
		return fmt.Errorf("language: use auto, en or zh-CN")
	}
	if c.Install.Mode != "online" && c.Install.Mode != "offline" {
		return fmt.Errorf("install.mode: use online or offline")
	}
	if c.Install.ReleaseSource != "github" && c.Install.ReleaseSource != "gitee" {
		return fmt.Errorf("install.release_source: use github or gitee")
	}
	if c.Install.Prefix == "" {
		return fmt.Errorf("install.prefix is required")
	}
	seen := map[string]bool{}
	for _, v := range c.Install.Components {
		found := false
		for _, n := range Names {
			if n == v {
				found = true
			}
		}
		if !found || seen[v] {
			return fmt.Errorf("invalid or duplicate install.components entry: %s", v)
		}
		seen[v] = true
	}
	if c.Mihomo.ProxyPort < 1 || c.Mihomo.ProxyPort > 65535 || c.Mihomo.APIPort < 1 || c.Mihomo.APIPort > 65535 || c.Mihomo.ProxyPort == c.Mihomo.APIPort {
		return fmt.Errorf("mihomo ports must be distinct integers between 1 and 65535")
	}
	if c.Conda.Distribution != "miniconda" && c.Conda.Distribution != "anaconda" {
		return fmt.Errorf("conda.distribution: use miniconda or anaconda")
	}
	if c.Codex.ReadyTimeout < 1 || c.Codex.ReadyTimeout > 600 {
		return fmt.Errorf("codex.ready_timeout must be between 1 and 600")
	}
	for _, r := range []Reference{c.Secrets, c.Codex.APIKey, c.Mihomo.Subscription} {
		if r.File != "" && r.Env != "" {
			return fmt.Errorf("a reference must choose file or env")
		}
		if r.Env != "" && !variable.MatchString(r.Env) {
			return fmt.Errorf("invalid environment variable reference")
		}
	}
	for k, v := range c.Env {
		if !variable.MatchString(k) {
			return fmt.Errorf("invalid env name %q", k)
		}
		if sensitive.MatchString(k) {
			return fmt.Errorf("env.%s: use a protected secret reference", k)
		}
		if strings.ContainsRune(v, 0) {
			return fmt.Errorf("env.%s contains NUL", k)
		}
	}
	return nil
}
func IsChinese(lang string) bool {
	if lang == "zh-CN" {
		return true
	}
	if lang != "auto" && lang != "" {
		return false
	}
	for _, k := range []string{"LC_ALL", "LC_MESSAGES", "LANG"} {
		if v := os.Getenv(k); v != "" {
			return strings.HasPrefix(strings.ToLower(v), "zh")
		}
	}
	return platformChinese()
}
func Text(lang, en, zh string) string {
	if IsChinese(lang) {
		return zh
	}
	return en
}
func flag(b bool) string {
	if b {
		return "1"
	}
	return "0"
}
func (c Config) Environment() map[string]string {
	m := map[string]string{"ENVPILOT_CONFIG_FILE": c.SourcePath, "EP_MODE": c.Install.Mode, "EP_PREFIX": Expand(c.Install.Prefix), "EP_CONDA_DISTRIBUTION": c.Conda.Distribution, "ENVPILOT_LANG": c.Language, "ENVPILOT_COMPONENTS": strings.Join(c.Install.Components, " "), "ENVPILOT_RELEASE_SOURCE": c.Install.ReleaseSource, "ENVPILOT_SHELL_ENABLED": flag(c.Shell.Enabled), "BASHRC_INIT_CONDA": flag(c.Shell.Conda), "BASHRC_AUTO_LOAD_MODULES": flag(len(c.Shell.Modules) > 0), "BASHRC_AUTO_START_MIHOMO": flag(c.Shell.AutoStartProxy), "BASHRC_AUTO_ENABLE_PROXY": flag(c.Shell.AutoEnableProxy), "BASHRC_AUTO_LOAD_SECRETS": flag(c.Shell.LoadSecrets), "BASHRC_ENABLE_HISTORY_SYNC": flag(c.Shell.HistorySync), "ENVPILOT_LEGACY_ALIASES": flag(c.Shell.LegacyAliases), "ENVPILOT_LEGACY_LOCAL": flag(c.Shell.LegacyLocal), "MIHOMO_PROXY_PORT": strconv.Itoa(c.Mihomo.ProxyPort), "MIHOMO_API_PORT": strconv.Itoa(c.Mihomo.APIPort), "BASHRC_PROXY_ENABLE_SOCKS": flag(c.Mihomo.SOCKS), "BASHRC_CONDA_PRIMARY_PREFIX": Expand(c.Conda.Prefix), "BASHRC_SECRETS_FILE": Expand(c.Secrets.File), "CODEX_HOME": Expand(c.Codex.Home), "ENVPILOT_CODEX_RUNTIME_DIR": Expand(c.Codex.Runtime), "ENVPILOT_CODEX_REMOTE_READY_TIMEOUT": strconv.Itoa(c.Codex.ReadyTimeout), "ENVPILOT_CODEX_SECRETS_FILE": Expand(c.Secrets.File), "ENVPILOT_CODEX_ENABLED": flag(c.Codex.Remote), "ENVPILOT_SUBSCRIPTION_FILE": Expand(c.Mihomo.Subscription.File), "ENVPILOT_SUBSCRIPTION_ENV": c.Mihomo.Subscription.Env, "ENVPILOT_API_KEY_ENV": c.Codex.APIKey.Env, "ENVPILOT_API_KEY_FILE": Expand(c.Codex.APIKey.File)}
	if c.Codex.BaseURL != "" {
		m["EP_CODEX_BASE_URL"] = c.Codex.BaseURL
	}
	return m
}
func SortedKeys(m map[string]string) []string {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	return keys
}
func SafeJSON(v any) ([]byte, error) { return json.MarshalIndent(v, "", "  ") }
func WriteAtomic(path string, data []byte, mode os.FileMode) error {
	if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
		return err
	}
	f, err := os.CreateTemp(filepath.Dir(path), ".envpilot-*")
	if err != nil {
		return err
	}
	defer os.Remove(f.Name())
	if err = f.Chmod(mode); err == nil {
		_, err = f.Write(data)
	}
	if err == nil {
		err = f.Sync()
	}
	closeErr := f.Close()
	if err != nil {
		return err
	}
	if closeErr != nil {
		return closeErr
	}
	return os.Rename(f.Name(), path)
}
func Encode(c Config) ([]byte, error) {
	var node yaml.Node
	if err := node.Encode(c); err != nil {
		return nil, err
	}
	comments := map[string][2]string{
		"version":                {"Configuration format version; not the application version.", "配置格式版本，不是软件版本。"},
		"language":               {"auto, en or zh-CN", "auto 自动选择、en 英文、zh-CN 简体中文。"},
		"install.components":     {"Choose components: mihomo, git, python, conda, mamba, codex, github, tmux.", "选择安装组件：mihomo、git、python、conda、mamba、codex、github、tmux。"},
		"install.mode":           {"Offline requires a platform package and matching component assets.", "offline 需要完整平台包和对应组件离线资源。"},
		"install.prefix":         {"User-space installation directory.", "用户态软件安装目录。"},
		"install.release_source": {"Where to download envpilot releases: github or gitee.", "envpilot 发布包来源：github 或 gitee。"},
		"shell":                  {"Opt in to environment changes; the original profile is preserved.", "按需启用环境变化；原 profile 内容保持不变。"},
		"shell.conda":            {"Initialize Conda in interactive shells, without activating base.", "在交互 Shell 中初始化 Conda，不自动激活 base。"},
		"shell.paths":            {"Append paths without replacing existing command priority.", "追加路径，保留原命令优先级。"},
		"shell.legacy_local":     {"Load the previous user-owned shell.local interactively.", "交互时加载已有的用户自定义 shell.local。"},
		"mihomo.subscription":    {"Choose file or env. Keep the actual subscription URL out of this YAML.", "file 或 env 二选一，实际订阅地址不写入本 YAML。"},
		"codex.remote":           {"Enable node-local runtime on Linux/macOS/WSL.", "在 Linux/macOS/WSL 启用节点本地运行目录。"},
		"codex.api_key":          {"Reference an API-key environment variable or protected file.", "引用存放 API key 的环境变量或受保护文件。"},
		"secrets":                {"Assignment-only environment file; Unix mode 600/400, current user owner.", "仅含变量赋值的文件；Unix 权限 600/400，属于当前用户。"},
		"env":                    {"Ordinary environment variables only; credentials use references above.", "只放常规环境变量；密钥使用上面的受保护引用。"},
	}
	var annotate func(*yaml.Node, string)
	annotate = func(n *yaml.Node, prefix string) {
		if n.Kind == yaml.MappingNode {
			for i := 0; i < len(n.Content); i += 2 {
				key := n.Content[i].Value
				if prefix != "" {
					key = prefix + "." + key
				}
				if pair, ok := comments[key]; ok {
					n.Content[i].HeadComment = Text(c.Language, pair[0], pair[1])
				}
				annotate(n.Content[i+1], key)
			}
		}
	}
	annotate(&node, "")
	var output bytes.Buffer
	encoder := yaml.NewEncoder(&output)
	encoder.SetIndent(2)
	err := encoder.Encode(&node)
	return output.Bytes(), err
}

func (c Config) OrderedComponents() []string {
	selected := map[string]bool{}
	for _, name := range c.Install.Components {
		selected[name] = true
	}
	result := []string{}
	for _, name := range Names {
		if selected[name] {
			result = append(result, name)
		}
	}
	return result
}
