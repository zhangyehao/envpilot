package config

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"regexp"
	"runtime"
	"sort"
	"strings"
	"time"

	"github.com/pelletier/go-toml/v2"
)

var ErrModelRefresh = errors.New("E_CODEX_MODEL_REFRESH")
var catalogVersion = regexp.MustCompile(`^[0-9]+\.[0-9]+\.[0-9]+(?:[-+][A-Za-z0-9.-]+)?$`)
var modelID = regexp.MustCompile(`^[[:alnum:]][[:alnum:]_.:/@+-]{0,255}$`)

type modelEntry struct {
	ID     string `json:"id"`
	Hidden bool   `json:"hidden,omitempty"`
}
type catalogObservation struct {
	Status      string       `json:"status"`
	Version     string       `json:"version,omitempty"`
	Models      []modelEntry `json:"models,omitempty"`
	LastSuccess string       `json:"last_success,omitempty"`
}
type modelState struct {
	Checked         string             `json:"checked_at,omitempty"`
	ProviderID      string             `json:"provider_id,omitempty"`
	ProviderKey     string             `json:"provider_fingerprint,omitempty"`
	CatalogOverride bool               `json:"local_catalog_override"`
	Provider        catalogObservation `json:"provider"`
	Bundled         catalogObservation `json:"bundled"`
	Remote          catalogObservation `json:"remote"`
}

func PrintLastCodexStable(path string) error {
	state, err := readUpdateState(path)
	if err != nil {
		return err
	}
	for _, r := range state.Results {
		if r.Component == "codex" && stableVersion.MatchString(r.Latest) {
			fmt.Println(r.Latest)
			break
		}
	}
	return nil
}
func sortedModels(entries []modelEntry) ([]modelEntry, bool) {
	byID := map[string]modelEntry{}
	for _, e := range entries {
		if !modelID.MatchString(e.ID) {
			return nil, false
		}
		byID[e.ID] = e
	}
	out := make([]modelEntry, 0, len(byID))
	for _, e := range byID {
		out = append(out, e)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].ID < out[j].ID })
	return out, true
}

type modelProvider struct {
	Base string `toml:"base_url"`
	Key  string `toml:"env_key"`
}
type providerSelection struct {
	Name       string                   `toml:"model_provider"`
	Providers  map[string]modelProvider `toml:"model_providers"`
	OpenAIBase string                   `toml:"openai_base_url"`
	Override   string                   `toml:"model_catalog_json"`
}

func readProvider(c Config) (providerSelection, modelProvider, string) {
	var sel providerSelection
	file, err := os.Open(filepath.Join(Expand(c.Codex.Home), "config.toml"))
	if err == nil {
		defer file.Close()
		b, err := boundedRead(file, 2<<20)
		if err != nil || toml.Unmarshal(b, &sel) != nil {
			return sel, modelProvider{}, "invalid_provider_config"
		}
	} else if !os.IsNotExist(err) {
		return sel, modelProvider{}, "invalid_provider_config"
	}
	if sel.Name == "" {
		sel.Name = "openai"
	}
	if !modelID.MatchString(sel.Name) {
		return providerSelection{}, modelProvider{}, "invalid_provider_config"
	}
	p, ok := sel.Providers[sel.Name]
	if !ok && sel.Name == "openai" {
		p.Base = sel.OpenAIBase
		if p.Base == "" {
			p.Base = os.Getenv("OPENAI_BASE_URL")
		}
		if p.Base == "" {
			p.Base = "https://api.openai.com/v1"
		}
		p.Key = "OPENAI_API_KEY"
	}
	if p.Base == "" {
		return sel, p, "unknown_provider_endpoint"
	}
	return sel, p, ""
}
func boundedRead(r io.Reader, limit int64) ([]byte, error) {
	b, err := io.ReadAll(io.LimitReader(r, limit+1))
	if int64(len(b)) > limit {
		return nil, fmt.Errorf("response size limit exceeded")
	}
	return b, err
}
func providerModels(c Config, provider modelProvider) catalogObservation {
	u, err := url.Parse(provider.Base)
	if err != nil || u.Hostname() == "" || u.User != nil || u.RawQuery != "" || u.Fragment != "" ||
		(u.Scheme != "https" && !(u.Scheme == "http" && (u.Hostname() == "localhost" || net.ParseIP(u.Hostname()).IsLoopback()))) {
		return catalogObservation{Status: "unsafe_provider_endpoint"}
	}
	u.Path = strings.TrimRight(u.Path, "/") + "/models"
	req, err := http.NewRequest("GET", u.String(), nil)
	if err != nil {
		return catalogObservation{Status: "invalid_provider_config"}
	}
	if provider.Key != "" {
		if !variable.MatchString(provider.Key) {
			return catalogObservation{Status: "invalid_provider_config"}
		}
		env, err := c.ChildEnvironment()
		if err != nil {
			return catalogObservation{Status: "credential_unavailable"}
		}
		key := env[provider.Key]
		if key == "" && provider.Key == "OPENAI_API_KEY" {
			// Only the dedicated API-key field is usable for a provider. Never send
			// ChatGPT session, refresh or access tokens to a models endpoint.
			path := filepath.Join(Expand(c.Codex.Home), "auth.json")
			if st, e := os.Stat(path); e == nil && st.Mode().IsRegular() && st.Size() < 1<<20 && CheckSecretPermissions(path, st) == nil {
				b, _ := os.ReadFile(path)
				var auth struct {
					Key string `json:"OPENAI_API_KEY"`
				}
				if json.Unmarshal(b, &auth) == nil {
					key = auth.Key
				}
			}
		}
		if key == "" {
			return catalogObservation{Status: "credential_unavailable"}
		}
		req.Header.Set("Authorization", "Bearer "+key)
	}
	client := http.Client{Timeout: 12 * time.Second, CheckRedirect: func(_ *http.Request, _ []*http.Request) error { return http.ErrUseLastResponse }}
	resp, err := client.Do(req)
	if err != nil {
		return catalogObservation{Status: "provider_unreachable"}
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		return catalogObservation{Status: fmt.Sprintf("http_%d", resp.StatusCode)}
	}
	b, err := boundedRead(resp.Body, 8<<20)
	var result struct {
		Data    *[]modelEntry
		HasMore bool `json:"has_more"`
	}
	if err != nil || json.Unmarshal(b, &result) != nil || result.Data == nil || result.HasMore {
		return catalogObservation{Status: "incomplete_provider_catalog"}
	}
	entries, ok := sortedModels(*result.Data)
	if !ok {
		return catalogObservation{Status: "invalid_model_id"}
	}
	return catalogObservation{Status: "ok", Models: entries}
}

type limitedOutput struct {
	buffer bytes.Buffer
	limit  int
}

func (o *limitedOutput) Write(p []byte) (int, error) {
	if len(p) > o.limit-o.buffer.Len() {
		return 0, fmt.Errorf("output size limit exceeded")
	}
	return o.buffer.Write(p)
}

// npm installs Windows command shims alongside node_modules. Launch the native
// vendor executable for a probe to preserve literal arguments and bounded execution.
func windowsNpmCodex(shim string) string {
	triple, arch := "x86_64-pc-windows-msvc", "x64"
	if runtime.GOARCH == "arm64" {
		triple, arch = "aarch64-pc-windows-msvc", "arm64"
	}
	org := filepath.Join(filepath.Dir(shim), "node_modules", "@openai")
	for _, pkg := range []string{filepath.Join(org, "codex-win32-"+arch), filepath.Join(org, "codex", "node_modules", "@openai", "codex-win32-"+arch), filepath.Join(org, "codex")} {
		for _, bin := range []string{"bin", "codex"} {
			candidate := filepath.Join(pkg, "vendor", triple, bin, "codex.exe")
			if st, e := os.Stat(candidate); e == nil && st.Mode().IsRegular() {
				return candidate
			}
		}
	}
	return ""
}
func bundledModels(c Config, binary string) catalogObservation {
	if binary == "" {
		suffix := ""
		if runtime.GOOS == "windows" {
			suffix = ".exe"
		}
		for _, name := range []string{"bin/codex", "codex"} {
			candidate := filepath.Join(Expand(c.Codex.Home), "packages/standalone/current", name+suffix)
			if st, e := os.Stat(candidate); e == nil && st.Mode().IsRegular() {
				binary = candidate
				break
			}
		}
		if binary == "" {
			binary, _ = exec.LookPath("codex")
			if runtime.GOOS == "windows" && strings.EqualFold(filepath.Ext(binary), ".cmd") {
				binary = windowsNpmCodex(binary)
			}
		}
	}
	if binary == "" {
		return catalogObservation{Status: "cli_unavailable"}
	}
	// Use an empty Codex home for this read. This excludes configured catalog
	// files, authentication, plugins and user caches from the bundled result.
	temp, err := os.MkdirTemp("", "envpilot-bundled-")
	if err != nil {
		return catalogObservation{Status: "cli_probe_failed"}
	}
	defer os.RemoveAll(temp)
	run := func(args ...string) ([]byte, error) {
		ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
		defer cancel()
		cmd := exec.CommandContext(ctx, binary, args...)
		cmd.WaitDelay = time.Second
		cmd.Dir = temp
		cmd.Env = append(os.Environ(), "CODEX_HOME="+temp)
		out := limitedOutput{limit: 8 << 20}
		cmd.Stdout = &out
		err := cmd.Run()
		return out.buffer.Bytes(), err
	}
	b, err := run("debug", "models", "--bundled")
	if err != nil {
		help, e := run("debug", "models", "--help")
		if e != nil || !bytes.Contains(help, []byte("--bundled")) {
			return catalogObservation{Status: "cli_bundled_unsupported"}
		}
		return catalogObservation{Status: "cli_probe_failed"}
	}
	var result struct {
		Models *[]struct{ Slug, Visibility string }
	}
	if json.Unmarshal(b, &result) != nil || result.Models == nil {
		return catalogObservation{Status: "invalid_bundled_catalog"}
	}
	var entries []modelEntry
	for _, m := range *result.Models {
		entries = append(entries, modelEntry{m.Slug, m.Visibility == "hide"})
	}
	entries, ok := sortedModels(entries)
	if !ok {
		return catalogObservation{Status: "invalid_model_id"}
	}
	version := ""
	if v, e := run("--version"); e == nil {
		for _, line := range strings.Split(string(v), "\n") {
			if rest, ok := strings.CutPrefix(strings.TrimSpace(line), "codex-cli "); ok && catalogVersion.MatchString(rest) {
				version = rest
				break
			}
		}
	}
	return catalogObservation{Status: "ok", Models: entries, Version: version}
}
func remoteModels(home string) catalogObservation {
	socket := filepath.Join(home, "app-server-control", "app-server-control.sock")
	if _, err := os.Stat(socket); os.IsNotExist(err) {
		return catalogObservation{Status: "service_offline"}
	}
	rpc, err := openCodexRPC(socket, home, 15*time.Second)
	if err != nil {
		return catalogObservation{Status: "handshake_failed"}
	}
	defer rpc.conn.Close()
	version, err := ProbeVersion(rpc.hello)
	if err != nil || rpc.initialized() != nil {
		return catalogObservation{Status: "handshake_failed"}
	}
	var entries []modelEntry
	cursor := ""
	for page := 0; page < 100; page++ {
		var result struct {
			Data       *[]modelEntry
			NextCursor string
		}
		err = rpc.call("model/list", map[string]any{"includeHidden": true, "limit": 100, "cursor": optionalCursor(cursor)}, &result)
		if err != nil || result.Data == nil {
			break
		}
		entries = append(entries, (*result.Data)...)
		if result.NextCursor == "" {
			entries, ok := sortedModels(entries)
			if !ok {
				break
			}
			return catalogObservation{Status: "ok", Version: version, Models: entries}
		}
		if result.NextCursor == cursor {
			break
		}
		cursor = result.NextCursor
	}
	return catalogObservation{Status: "service_catalog_failed", Version: version}
}

func mergeObservation(old, next catalogObservation, now string) catalogObservation {
	if next.Status == "ok" {
		next.LastSuccess = now
		return next
	}
	next.LastSuccess = old.LastSuccess
	next.Models = old.Models
	if next.Version == "" {
		next.Version = old.Version
	}
	return next
}
func withoutTimes(s modelState) modelState {
	s.Checked = ""
	s.Provider.LastSuccess = ""
	s.Bundled.LastSuccess = ""
	s.Remote.LastSuccess = ""
	// Normalize empty catalogs after a JSON round trip (omitempty drops an empty slice).
	for _, o := range []*catalogObservation{&s.Provider, &s.Bundled, &s.Remote} {
		if len(o.Models) == 0 {
			o.Models = nil
		}
	}
	return s
}
func modelCachePath(c Config) string {
	host, _ := os.Hostname()
	home, _ := filepath.Abs(Expand(c.Codex.Home))
	key := sha256.Sum256([]byte(host + "\x00" + home + "\x00" + c.SourcePath))
	return filepath.Join(Dir(), "models", fmt.Sprintf("%x.json", key[:12]))
}
func loadModelState(path string) (modelState, error) {
	var state modelState
	b, err := os.ReadFile(path)
	if os.IsNotExist(err) {
		return state, nil
	}
	if err == nil {
		err = json.Unmarshal(b, &state)
	}
	return state, err
}
func catalogStatus(lang, code string) string {
	if strings.HasPrefix(code, "http_") {
		return "HTTP " + strings.TrimPrefix(code, "http_")
	}
	labels := map[string][2]string{
		"ok":                          {"ok", "成功"},
		"never_checked":               {"never checked", "尚未检查"},
		"offline_mode":                {"offline policy", "当前为离线模式"},
		"service_offline":             {"service offline", "服务未启动"},
		"unknown_provider_endpoint":   {"provider endpoint unknown", "供应商地址未知"},
		"invalid_provider_config":     {"invalid provider config", "供应商配置无法读取"},
		"unsafe_provider_endpoint":    {"invalid or unsafe provider endpoint", "供应商地址格式或安全条件不符"},
		"provider_unreachable":        {"provider unreachable", "无法连接供应商"},
		"credential_unavailable":      {"credential unavailable", "缺少或无法读取凭据"},
		"incomplete_provider_catalog": {"provider returned an incomplete list", "供应商目录不完整"},
		"invalid_model_id":            {"unexpected model ID format", "模型 ID 格式异常"},
		"cli_unavailable":             {"CLI unavailable", "未找到 CLI"},
		"cli_bundled_unsupported":     {"CLI does not expose its bundled catalog", "此 CLI 未提供内置目录查询"},
		"invalid_bundled_catalog":     {"invalid bundled catalog", "内置目录格式异常"},
		"cli_probe_failed":            {"CLI probe failed", "CLI 探测失败"},
		"handshake_failed":            {"service handshake failed", "服务握手失败"},
		"service_catalog_failed":      {"model/list failed or incomplete", "model/list 失败或返回不完整"},
	}
	if label, ok := labels[code]; ok {
		return Text(lang, label[0], label[1])
	}
	return code
}
func printModelState(c Config, s modelState, format string) error {
	if format == "json" {
		return json.NewEncoder(os.Stdout).Encode(s)
	}
	fmt.Printf("%s %s\n", Text(c.Language, "Last checked:", "上次检查："), s.Checked)
	if s.CatalogOverride {
		fmt.Println(Text(c.Language, "Codex config selects a local model catalog.", "Codex 配置指定了本地模型目录。"))
	}
	for _, source := range []struct {
		Label string
		Obs   catalogObservation
	}{
		{Text(c.Language, "Provider", "供应商") + " (" + s.ProviderID + ")", s.Provider},
		{Text(c.Language, "Bundled CLI catalog", "CLI 内置目录"), s.Bundled},
		{Text(c.Language, "Control socket model/list", "控制 socket 的 model/list"), s.Remote},
	} {
		o := source.Obs
		status := o.Status
		if status == "" {
			status = "never_checked"
		}
		fmt.Printf("%s: %s", source.Label, catalogStatus(c.Language, status))
		if o.Version != "" {
			fmt.Printf("  v%s", o.Version)
		}
		if o.LastSuccess != "" {
			fmt.Printf("  %s %s", Text(c.Language, "last success", "上次成功"), o.LastSuccess)
		}
		fmt.Println()
		if len(o.Models) > 0 {
			ids := make([]string, 0, len(o.Models))
			for _, m := range o.Models {
				label := m.ID
				if m.Hidden {
					label += Text(c.Language, " (hidden)", "（隐藏）")
				}
				ids = append(ids, label)
			}
			fmt.Println("  " + strings.Join(ids, ", "))
		}
	}
	return nil
}

// Persist only model identifiers, visibility, versions and timestamps. Explicit
// refresh and cron share a node-local identity and serialize concurrent writes.
func CodexModelsCommand(c Config, binary string, args []string, format string) error {
	if len(args) != 1 || (args[0] != "refresh" && args[0] != "status") || (format != "json" && format != "text") {
		return fmt.Errorf("usage: envpilot codex models status|refresh [--json]")
	}
	path := modelCachePath(c)
	if args[0] == "status" {
		state, err := loadModelState(path)
		if err != nil {
			return err
		}
		if state.Checked == "" && format != "json" {
			fmt.Println(Text(c.Language, "No observation yet. Run envpilot codex models refresh.", "尚无检查记录，请运行 envpilot codex models refresh。"))
			return nil
		}
		return printModelState(c, state, format)
	}
	if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
		return err
	}
	lock, err := os.OpenFile(path+".lock", os.O_CREATE|os.O_RDWR, 0600)
	if err != nil {
		return err
	}
	defer lock.Close()
	if err = lockUpdateFile(lock); err != nil {
		return fmt.Errorf("E_CODEX_MODELS_BUSY")
	}
	defer unlockUpdateFile(lock)
	old, err := loadModelState(path)
	if err != nil {
		return err
	}
	now := time.Now().UTC().Format(time.RFC3339)
	sel, p, status := readProvider(c)
	key := sha256.Sum256([]byte(sel.Name + "\x00" + p.Base + "\x00" + p.Key))
	state := modelState{Checked: now, ProviderID: sel.Name, ProviderKey: fmt.Sprintf("%x", key[:12]), CatalogOverride: sel.Override != ""}
	prior := old.Provider
	if state.ProviderKey != old.ProviderKey {
		prior = catalogObservation{}
	}
	provider := catalogObservation{Status: status}
	if c.Install.Mode == "offline" {
		provider.Status = "offline_mode"
	} else if status == "" {
		provider = providerModels(c, p)
	}
	state.Provider = mergeObservation(prior, provider, now)
	state.Bundled = mergeObservation(old.Bundled, bundledModels(c, binary), now)
	state.Remote = mergeObservation(old.Remote, remoteModels(Expand(c.Codex.Home)), now)
	b, err := json.MarshalIndent(state, "", "  ")
	if err != nil {
		return err
	}
	if err = WriteAtomic(path, b, 0600); err != nil {
		return err
	}
	if !reflect.DeepEqual(withoutTimes(state), withoutTimes(old)) {
		if err = printModelState(c, state, format); err != nil {
			return err
		}
	}
	if state.Provider.Status != "ok" && state.Provider.Status != "offline_mode" {
		return ErrModelRefresh
	}
	if state.Remote.Status != "ok" && state.Remote.Status != "service_offline" {
		return ErrModelRefresh
	}
	if state.Bundled.Status != "ok" && state.Bundled.Status != "cli_bundled_unsupported" {
		return ErrModelRefresh
	}
	return nil
}
