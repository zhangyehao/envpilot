package config

import (
	"bufio"
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	"go.yaml.in/yaml/v3"
)

type mihomoProxy struct {
	Name      string   `json:"name"`
	Type      string   `json:"type"`
	Now       string   `json:"now,omitempty"`
	All       []string `json:"all,omitempty"`
	Providers []string `json:"providers,omitempty"`
}

type mihomoController struct {
	config Config
	base   string
	secret string
	client *http.Client
}

type mihomoSelections struct {
	Version    int               `json:"version"`
	Host       string            `json:"host"`
	APIPort    int               `json:"api_port"`
	UpdatedAt  time.Time         `json:"updated_at"`
	Selections map[string]string `json:"selections"`
}

type mihomoSelectionResult struct {
	Group string `json:"group"`
	Node  string `json:"node"`
}

type mihomoRestoreResult struct {
	Restored []mihomoSelectionResult `json:"restored"`
	Skipped  []mihomoSelectionResult `json:"skipped"`
}

type mihomoDelayResult struct {
	Node      string `json:"node"`
	OK        bool   `json:"ok"`
	DelayMS   int    `json:"delay_ms"`
	ErrorCode string `json:"error_code,omitempty"`
}

func mihomoError(c Config, code, en, zh string) error {
	return fmt.Errorf("%s: %s", code, Text(c.Language, en, zh))
}

// MihomoCommand talks only to this node's loopback controller. Credentials stay
// in the protected Mihomo YAML and never enter CLI arguments or persisted state.
func MihomoCommand(c Config, action string, args []string, format string) error {
	info, err := os.Stdin.Stat()
	interactive := err == nil && info.Mode()&os.ModeCharDevice != 0 &&
		os.Getenv("EP_NON_INTERACTIVE") != "1" && os.Getenv("EP_CONFIG_APPLY") != "1" && format != "json"
	return mihomoCommandIO(c, action, args, format, os.Stdin, os.Stdout, interactive)
}

func mihomoCommandIO(c Config, action string, args []string, format string, input io.Reader, output io.Writer, interactive bool) error {
	return mihomoCommandCheckedIO(c, action, args, format, input, output, interactive, nil)
}

// The verifier argument is an internal test seam. Public commands always use
// OS listener/process ownership checks; no environment setting disables them.
func mihomoCommandCheckedIO(c Config, action string, args []string, format string, input io.Reader, output io.Writer, interactive bool, verifier mihomoOwnerVerifier) error {
	switch action {
	case "nodes":
		if len(args) > 1 {
			return mihomoError(c, "E_MIHOMO_ARGUMENT", "Use: envpilot mihomo nodes [GROUP]", "用法：envpilot mihomo nodes [策略组]")
		}
	case "select", "test":
		if len(args) > 2 {
			return mihomoError(c, "E_MIHOMO_ARGUMENT", "Use: envpilot mihomo "+action+" [GROUP] [NODE]", "用法：envpilot mihomo "+action+" [策略组] [节点]")
		}
		if action == "select" && len(args) < 2 && !interactive {
			return mihomoError(c, "E_INPUT_REQUIRED", "Non-interactive selection requires GROUP and NODE. Run envpilot mihomo nodes first.", "非交互选择需要提供策略组和节点名；先执行 envpilot mihomo nodes 查看。")
		}
	case "selection-save", "selection-restore", "health":
		if len(args) != 0 {
			return mihomoError(c, "E_MIHOMO_ARGUMENT", "This action takes no arguments.", "此操作不接受额外参数。")
		}
	default:
		return mihomoError(c, "E_MIHOMO_ARGUMENT", "Unknown Mihomo controller action.", "未知的 Mihomo 控制操作。")
	}
	if action == "selection-restore" {
		return mihomoRestore(c, format, output, verifier)
	}
	controller, err := newMihomoControllerChecked(c, verifier)
	if err != nil {
		return err
	}
	defer controller.client.CloseIdleConnections()
	if action == "health" {
		var response map[string]any
		return controller.request(http.MethodGet, "/version", nil, &response)
	}
	if action == "selection-save" {
		return mihomoWithSelectionLock(c, func() error {
			proxies, err := controller.proxies()
			if err != nil {
				return err
			}
			state, _, err := mihomoReadSelections(c)
			if err != nil {
				return err
			}
			for name, p := range proxies {
				if p.Type == "Selector" && mihomoContains(p.All, p.Now) {
					state.Selections[name] = p.Now
				}
			}
			return mihomoWriteSelections(c, state)
		})
	}
	proxies, err := controller.proxies()
	if err != nil {
		if action == "nodes" && (strings.HasPrefix(err.Error(), "E_MIHOMO_API:") || strings.HasPrefix(err.Error(), "E_MIHOMO_OWNER:")) {
			offline, readErr := mihomoConfiguredProxies(c)
			if readErr == nil {
				return mihomoList(c, offline, args, format, output, false)
			}
		}
		return err
	}
	if action == "nodes" {
		return mihomoList(c, proxies, args, format, output, true)
	}
	reader := bufio.NewReader(input)
	var group mihomoProxy
	if action == "test" && len(args) > 0 {
		// Automatic groups cannot be pinned manually, but their members can
		// still be tested without changing the policy.
		var found bool
		group, found = proxies[args[0]]
		if !found || len(group.All) == 0 {
			return mihomoError(c, "E_MIHOMO_GROUP", "The group does not exist or has no entries to test.", "该策略组不存在或没有可测试的成员。")
		}
	} else {
		group, err = mihomoChooseGroup(c, proxies, args, reader, output, interactive)
	}
	if err != nil {
		return err
	}
	if action == "test" {
		return mihomoTestNodes(controller, proxies, group, args, format, output)
	}
	node := ""
	if len(args) > 1 {
		node = args[1]
	} else {
		node, err = mihomoChoose(c, reader, output, Text(c.Language, "Choose a node (0 cancels)", "选择节点（输入 0 取消）"), group.All, group.Now)
		if err != nil {
			return err
		}
	}
	if !mihomoContains(group.All, node) {
		return mihomoError(c, "E_MIHOMO_NODE", "The node is not a member of this group; run envpilot mihomo nodes.", "该节点不在此策略组中；请执行 envpilot mihomo nodes 查看。")
	}
	err = mihomoWithSelectionLock(c, func() error {
		// Read persistent state before changing the server so a damaged state
		// file cannot produce an apparently successful but unrecorded choice.
		state, _, err := mihomoReadSelections(c)
		if err != nil {
			return err
		}
		if err = controller.selectNode(group.Name, node); err != nil {
			return err
		}
		state.Selections[group.Name] = node
		if err = mihomoWriteSelections(c, state); err != nil {
			return mihomoError(c, "E_MIHOMO_STATE", "The node changed, but its selection could not be saved. Check configuration directory permissions.", "节点已切换，但选择保存失败；请检查配置目录权限。")
		}
		return nil
	})
	if err != nil {
		return err
	}
	result := mihomoSelectionResult{Group: group.Name, Node: node}
	if format == "json" {
		return json.NewEncoder(output).Encode(result)
	}
	fmt.Fprintf(output, "%s: %s → %s\n", Text(c.Language, "Selected and saved", "已切换并保存"), group.Name, node)
	fmt.Fprintln(output, Text(c.Language, "New connections use this selection; existing connections may keep their current node.", "新连接使用此选择；已有连接可能继续使用原节点。"))
	return nil
}

func newMihomoController(c Config) (*mihomoController, error) {
	return newMihomoControllerChecked(c, nil)
}

func newMihomoControllerChecked(c Config, verifier mihomoOwnerVerifier) (*mihomoController, error) {
	if c.Mihomo.APIPort < 1 || c.Mihomo.APIPort > 65535 {
		return nil, mihomoError(c, "E_MIHOMO_API", "Invalid controller port.", "控制接口端口无效。")
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return nil, err
	}
	source := filepath.Join(home, ".config", "mihomo")
	if configured := os.Getenv("MIHOMO_SOURCE_CONFIG"); configured != "" {
		source = configured
	}
	paths := []string{}
	if runtime := os.Getenv("MIHOMO_RUNTIME_DIR"); runtime != "" {
		paths = append(paths, filepath.Join(runtime, "config.yaml"))
	}
	paths = append(paths, filepath.Join(source, "config.yaml"))
	secret := ""
	for _, path := range paths {
		f, err := os.Open(path)
		if os.IsNotExist(err) {
			continue
		}
		if err != nil {
			return nil, mihomoError(c, "E_MIHOMO_CONFIG", "Cannot read the Mihomo controller configuration.", "无法读取 Mihomo 控制接口配置。")
		}
		var settings struct {
			Secret string `yaml:"secret"`
		}
		err = yaml.NewDecoder(io.LimitReader(f, 32<<20)).Decode(&settings)
		_ = f.Close()
		if err != nil && err != io.EOF {
			return nil, mihomoError(c, "E_MIHOMO_CONFIG", "Invalid Mihomo YAML; controller credentials were not read.", "Mihomo YAML 无效，无法读取控制接口认证配置。")
		}
		secret = settings.Secret
		break
	}
	if len(secret) > 16384 || strings.ContainsAny(secret, "\r\n") {
		return nil, mihomoError(c, "E_MIHOMO_CONFIG", "Invalid controller secret.", "控制接口认证配置无效。")
	}
	if verifier == nil {
		verifier = func(ctx context.Context) error {
			expected, err := mihomoManagedExecutable(c)
			if err != nil {
				return errMihomoUnverifiedOwner
			}
			directory, err := mihomoManagedConfigDirectory(expected)
			if err != nil {
				return errMihomoUnverifiedOwner
			}
			return verifyMihomoListenerOwner(ctx, c.Mihomo.APIPort, expected, directory)
		}
	}
	dialer := net.Dialer{Timeout: 3 * time.Second}
	transport := &http.Transport{
		Proxy: nil,
		DialContext: func(ctx context.Context, network, address string) (net.Conn, error) {
			// Ownership is checked before and after every newly established TCP
			// connection. HTTP keep-alive remains attached to that same verified
			// connection; reconnecting after a restart always checks again.
			if err := verifier(ctx); err != nil {
				return nil, err
			}
			connection, err := dialer.DialContext(ctx, network, address)
			if err != nil {
				return nil, err
			}
			if err = verifier(ctx); err != nil {
				connection.Close()
				return nil, err
			}
			return connection, nil
		},
		MaxIdleConnsPerHost:   4,
		ResponseHeaderTimeout: 8 * time.Second,
	}
	return &mihomoController{
		config: c, secret: secret,
		base: "http://127.0.0.1:" + strconv.Itoa(c.Mihomo.APIPort),
		client: &http.Client{
			Transport: transport,
			Timeout:   10 * time.Second,
			CheckRedirect: func(*http.Request, []*http.Request) error {
				// A controller must never redirect its bearer secret elsewhere.
				return http.ErrUseLastResponse
			},
		},
	}, nil
}

func (m *mihomoController) request(method, path string, body any, result any) error {
	var reader io.Reader
	if body != nil {
		data, err := json.Marshal(body)
		if err != nil {
			return err
		}
		reader = bytes.NewReader(data)
	}
	request, err := http.NewRequest(method, m.base+path, reader)
	if err != nil {
		return mihomoError(m.config, "E_MIHOMO_API", "Could not construct the controller request.", "无法构造控制接口请求。")
	}
	if m.secret != "" {
		request.Header.Set("Authorization", "Bearer "+m.secret)
	}
	if body != nil {
		request.Header.Set("Content-Type", "application/json")
	}
	response, err := m.client.Do(request)
	if err != nil {
		if errors.Is(err, errMihomoUnverifiedOwner) {
			return mihomoError(m.config, "E_MIHOMO_OWNER", "The API listener is not verified as this user's managed Mihomo on this node. No HTTP request was sent; check envpilot mihomo status and the configured ports.", "无法确认 API 监听器属于当前用户、当前节点的受管 Mihomo。未发送 HTTP 请求；请用 envpilot mihomo status 检查实例和端口。")
		}
		return mihomoError(m.config, "E_MIHOMO_API", "The local Mihomo controller is unavailable. Run envpilot mihomo start and check envpilot mihomo status.", "本地 Mihomo 控制接口不可用。请执行 envpilot mihomo start，再用 envpilot mihomo status 检查。")
	}
	defer response.Body.Close()
	if response.StatusCode == http.StatusUnauthorized || response.StatusCode == http.StatusForbidden {
		return mihomoError(m.config, "E_MIHOMO_AUTH", "Controller authentication failed. Check the secret in the active Mihomo configuration.", "控制接口认证失败，请检查正在使用的 Mihomo 配置中的 secret。")
	}
	if response.StatusCode < 200 || response.StatusCode > 299 {
		return mihomoError(m.config, "E_MIHOMO_API_HTTP", fmt.Sprintf("The local controller returned HTTP %d.", response.StatusCode), fmt.Sprintf("本地控制接口返回 HTTP %d。", response.StatusCode))
	}
	if result == nil {
		return nil
	}
	data, err := io.ReadAll(io.LimitReader(response.Body, (8<<20)+1))
	if err != nil || len(data) > 8<<20 || json.Unmarshal(data, result) != nil {
		return mihomoError(m.config, "E_MIHOMO_API_RESPONSE", "Invalid or incomplete controller response.", "控制接口返回的数据无效或不完整。")
	}
	return nil
}

func (m *mihomoController) proxies() (map[string]mihomoProxy, error) {
	var response struct {
		Proxies map[string]mihomoProxy `json:"proxies"`
	}
	if err := m.request(http.MethodGet, "/proxies", nil, &response); err != nil {
		return nil, err
	}
	if response.Proxies == nil {
		return nil, mihomoError(m.config, "E_MIHOMO_API_RESPONSE", "Controller response has no proxy list.", "控制接口未返回节点列表。")
	}
	for name, proxy := range response.Proxies {
		proxy.Name = name
		response.Proxies[name] = proxy
	}
	return response.Proxies, nil
}

func (m *mihomoController) selectNode(group, node string) error {
	path := "/proxies/" + url.PathEscape(group)
	var current mihomoProxy
	if err := m.request(http.MethodGet, path, nil, &current); err != nil {
		return err
	}
	if current.Type != "Selector" {
		return mihomoError(m.config, "E_MIHOMO_GROUP", "Only a Selector group supports manual selection.", "只有手动选择（Selector）策略组支持指定节点。")
	}
	if !mihomoContains(current.All, node) {
		return mihomoError(m.config, "E_MIHOMO_NODE", "The node is no longer in this group; refresh the node list.", "该节点已不在此策略组中，请重新查看节点列表。")
	}
	if err := m.request(http.MethodPut, path, map[string]string{"name": node}, nil); err != nil {
		return err
	}
	if err := m.request(http.MethodGet, path, nil, &current); err != nil {
		return err
	}
	if current.Now != node {
		return mihomoError(m.config, "E_MIHOMO_SELECTION_VERIFY", "The controller did not confirm the requested selection; it was not saved.", "控制接口未确认所请求的节点选择，因此未保存。")
	}
	return nil
}

func mihomoConfiguredProxies(c Config) (map[string]mihomoProxy, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return nil, err
	}
	source := filepath.Join(home, ".config", "mihomo")
	if configured := os.Getenv("MIHOMO_SOURCE_CONFIG"); configured != "" {
		source = configured
	}
	f, err := os.Open(filepath.Join(source, "config.yaml"))
	if err != nil {
		return nil, err
	}
	defer f.Close()
	var document struct {
		Proxies []struct {
			Name string `yaml:"name"`
			Type string `yaml:"type"`
		} `yaml:"proxies"`
		Groups []struct {
			Name    string   `yaml:"name"`
			Type    string   `yaml:"type"`
			Proxies []string `yaml:"proxies"`
			Use     []string `yaml:"use"`
		} `yaml:"proxy-groups"`
	}
	if err = yaml.NewDecoder(io.LimitReader(f, 32<<20)).Decode(&document); err != nil {
		return nil, mihomoError(c, "E_MIHOMO_CONFIG", "Invalid Mihomo configuration.", "Mihomo 配置无效。")
	}
	proxies := map[string]mihomoProxy{}
	for _, p := range document.Proxies {
		proxies[p.Name] = mihomoProxy{Name: p.Name, Type: p.Type}
	}
	types := map[string]string{"select": "Selector", "url-test": "URLTest", "fallback": "Fallback", "load-balance": "LoadBalance", "relay": "Relay"}
	for _, g := range document.Groups {
		kind := types[g.Type]
		if kind == "" {
			kind = g.Type
		}
		proxies[g.Name] = mihomoProxy{Name: g.Name, Type: kind, All: g.Proxies, Providers: g.Use}
	}
	return proxies, nil
}

func mihomoList(c Config, proxies map[string]mihomoProxy, args []string, format string, out io.Writer, running bool) error {
	groups := []mihomoProxy{}
	if len(args) == 1 {
		p, ok := proxies[args[0]]
		if !ok || (len(p.All) == 0 && len(p.Providers) == 0) {
			return mihomoError(c, "E_MIHOMO_GROUP", "The group does not exist or has no selectable entries.", "该策略组不存在或没有可选项。")
		}
		groups = append(groups, p)
	} else {
		names := make([]string, 0, len(proxies))
		for name, p := range proxies {
			if len(p.All) > 0 || len(p.Providers) > 0 {
				names = append(names, name)
			}
		}
		mihomoSortGroupNames(names, c.Mihomo.GroupOrder)
		for _, name := range names {
			groups = append(groups, proxies[name])
		}
	}
	if format == "json" {
		source := "controller"
		if !running {
			source = "configuration"
		}
		return json.NewEncoder(out).Encode(map[string]any{"groups": groups, "running": running, "source": source})
	}
	if !running {
		fmt.Fprintln(out, Text(c.Language, "Controller unavailable; showing the saved configuration. Start Mihomo to see current selections and provider nodes.", "控制接口未运行或不可用，以下来自已保存配置；启动 Mihomo 后可查看当前选择及订阅提供者节点。"))
	}
	if len(groups) == 0 {
		fmt.Fprintln(out, Text(c.Language, "No policy groups are loaded. Check the subscription configuration.", "未加载策略组，请检查订阅配置。"))
		return nil
	}
	for _, p := range groups {
		label := Text(c.Language, "automatic group", "自动策略组")
		if p.Type == "Selector" {
			label = Text(c.Language, "manual selection", "手动选择")
		}
		fmt.Fprintf(out, "%s [%s / %s]\n", p.Name, label, p.Type)
		if running {
			fmt.Fprintf(out, "  %s: %s\n", Text(c.Language, "Current", "当前"), p.Now)
		}
		for i, name := range p.All {
			marker := " "
			if name == p.Now {
				marker = "*"
			}
			suffix := ""
			if child, ok := proxies[name]; ok && len(child.All) > 0 {
				suffix = " [" + Text(c.Language, "group", "策略组") + "]"
			}
			fmt.Fprintf(out, "  %s %d. %s%s\n", marker, i+1, name, suffix)
		}
		if len(p.Providers) != 0 {
			fmt.Fprintln(out, "  "+Text(c.Language, "Provider nodes are loaded after startup.", "订阅提供者节点需启动后加载。"))
		}
	}
	fmt.Fprintln(out, Text(c.Language, "Choose interactively: envpilot mihomo select", "按编号选择：envpilot mihomo select"))
	return nil
}

// Only group names are sorted. Membership and the subscription's node order
// remain unchanged; preferences for absent or ineligible groups have no effect.
func mihomoSortGroupNames(names, preferred []string) {
	priority := make(map[string]int, len(preferred))
	for i, name := range preferred {
		priority[name] = i
	}
	sort.Slice(names, func(i, j int) bool {
		left, leftPreferred := priority[names[i]]
		right, rightPreferred := priority[names[j]]
		if leftPreferred != rightPreferred {
			return leftPreferred
		}
		if leftPreferred {
			return left < right
		}
		return names[i] < names[j]
	})
}

func mihomoChooseGroup(c Config, proxies map[string]mihomoProxy, args []string, reader *bufio.Reader, out io.Writer, interactive bool) (mihomoProxy, error) {
	if len(args) > 0 {
		group, ok := proxies[args[0]]
		if !ok || group.Type != "Selector" {
			return mihomoProxy{}, mihomoError(c, "E_MIHOMO_GROUP", "Choose a Selector group shown by envpilot mihomo nodes.", "请选择 envpilot mihomo nodes 中的手动选择（Selector）策略组。")
		}
		return group, nil
	}
	names := []string{}
	for name, p := range proxies {
		if p.Type == "Selector" && name != "GLOBAL" {
			names = append(names, name)
		}
	}
	mihomoSortGroupNames(names, c.Mihomo.GroupOrder)
	if len(names) == 1 {
		return proxies[names[0]], nil
	}
	if len(names) == 0 {
		return mihomoProxy{}, mihomoError(c, "E_MIHOMO_GROUP", "No manual policy group is loaded. To use GLOBAL, name it explicitly.", "未加载手动策略组；若要操作 GLOBAL，请显式指定组名。")
	}
	if !interactive {
		return mihomoProxy{}, mihomoError(c, "E_INPUT_REQUIRED", "More than one manual group exists; specify GROUP.", "存在多个手动策略组，请指定策略组名。")
	}
	name, err := mihomoChoose(c, reader, out, Text(c.Language, "Choose a policy group (0 cancels)", "选择策略组（输入 0 取消）"), names, "")
	if err != nil {
		return mihomoProxy{}, err
	}
	return proxies[name], nil
}

func mihomoChoose(c Config, reader *bufio.Reader, out io.Writer, prompt string, options []string, current string) (string, error) {
	if len(options) == 0 {
		return "", mihomoError(c, "E_MIHOMO_NODE", "No choices are available.", "没有可选项。")
	}
	fmt.Fprintln(out, prompt)
	for i, name := range options {
		marker := " "
		if name == current {
			marker = "*"
		}
		fmt.Fprintf(out, "  %s %d. %s\n", marker, i+1, name)
	}
	for {
		fmt.Fprint(out, "> ")
		line, err := reader.ReadString('\n')
		if err != nil && len(line) == 0 {
			return "", mihomoError(c, "E_INPUT_REQUIRED", "No selection was read; nothing changed.", "未读到选择，未作任何更改。")
		}
		value := strings.TrimSpace(line)
		if value == "0" || strings.EqualFold(value, "q") {
			return "", mihomoError(c, "E_CANCELLED", "Selection cancelled; nothing changed.", "已取消选择，未作任何更改。")
		}
		n, parseErr := strconv.Atoi(value)
		if parseErr == nil && n >= 1 && n <= len(options) {
			return options[n-1], nil
		}
		if err != nil {
			return "", mihomoError(c, "E_INPUT_REQUIRED", "No valid selection was read; nothing changed.", "未读到有效选择，未作任何更改。")
		}
		fmt.Fprintln(out, Text(c.Language, "Enter a number from the list, or 0 to cancel.", "请输入列表中的编号，或输入 0 取消。"))
	}
}

func mihomoContains(values []string, value string) bool {
	for _, candidate := range values {
		if candidate == value {
			return true
		}
	}
	return false
}

func mihomoSelectionPath(c Config) (string, string, error) {
	host, err := os.Hostname()
	if err != nil || host == "" {
		return "", "", mihomoError(c, "E_MIHOMO_STATE", "Cannot identify the current node.", "无法识别当前节点。")
	}
	safe := host
	if strings.ContainsAny(safe, `/\:`) || safe == "." || safe == ".." {
		sum := sha256.Sum256([]byte(host))
		safe = hex.EncodeToString(sum[:12])
	}
	path := filepath.Join(Dir(), "mihomo-selections", safe+"-"+strconv.Itoa(c.Mihomo.APIPort)+".json")
	return path, host, nil
}

func mihomoWithSelectionLock(c Config, action func() error) error {
	path, _, err := mihomoSelectionPath(c)
	if err != nil {
		return err
	}
	if err = os.MkdirAll(filepath.Dir(path), 0700); err != nil {
		return mihomoError(c, "E_MIHOMO_STATE", "Cannot create the selection state directory.", "无法创建节点选择状态目录。")
	}
	if info, err := os.Lstat(path + ".lock"); err == nil && info.Mode()&os.ModeSymlink != 0 {
		return mihomoError(c, "E_MIHOMO_STATE", "The selection lock must not be a symlink.", "节点选择锁不能是符号链接。")
	}
	f, err := os.OpenFile(path+".lock", os.O_CREATE|os.O_RDWR, 0600)
	if err != nil {
		return mihomoError(c, "E_MIHOMO_STATE", "Cannot open the selection lock.", "无法打开节点选择锁。")
	}
	defer f.Close()
	until := time.Now().Add(20 * time.Second)
	for {
		if err = lockUpdateFile(f); err == nil {
			break
		}
		if time.Now().After(until) {
			return mihomoError(c, "E_MIHOMO_BUSY", "Another node selection operation is running; try again shortly.", "另一个节点选择操作正在执行，请稍后重试。")
		}
		time.Sleep(50 * time.Millisecond)
	}
	defer unlockUpdateFile(f)
	return action()
}

func mihomoReadSelections(c Config) (mihomoSelections, bool, error) {
	path, host, err := mihomoSelectionPath(c)
	if err != nil {
		return mihomoSelections{}, false, err
	}
	state := mihomoSelections{Version: 1, Host: host, APIPort: c.Mihomo.APIPort, Selections: map[string]string{}}
	f, err := os.Open(path)
	if os.IsNotExist(err) {
		return state, false, nil
	}
	if err != nil {
		return state, false, mihomoError(c, "E_MIHOMO_STATE", "Cannot read saved node selections.", "无法读取已保存的节点选择。")
	}
	defer f.Close()
	data, err := io.ReadAll(io.LimitReader(f, (1<<20)+1))
	if err != nil || len(data) > 1<<20 || json.Unmarshal(data, &state) != nil ||
		state.Version != 1 || state.Host != host || state.APIPort != c.Mihomo.APIPort || state.Selections == nil {
		return state, false, mihomoError(c, "E_MIHOMO_STATE", "Invalid saved selections or state belongs to another node/controller; the file was preserved.", "已保存的选择无效或属于其他节点/控制接口，原文件已保留。")
	}
	return state, true, nil
}

func mihomoWriteSelections(c Config, state mihomoSelections) error {
	path, _, err := mihomoSelectionPath(c)
	if err != nil {
		return err
	}
	state.UpdatedAt = time.Now().UTC()
	data, err := json.MarshalIndent(state, "", "  ")
	if err != nil {
		return err
	}
	return WriteAtomic(path, append(data, '\n'), 0600)
}

func mihomoRestore(c Config, format string, out io.Writer, verifier mihomoOwnerVerifier) error {
	return mihomoWithSelectionLock(c, func() error {
		state, exists, err := mihomoReadSelections(c)
		if err != nil {
			return err
		}
		if !exists {
			if format == "json" {
				return json.NewEncoder(out).Encode(mihomoRestoreResult{Restored: []mihomoSelectionResult{}, Skipped: []mihomoSelectionResult{}})
			}
			return nil
		}
		controller, err := newMihomoControllerChecked(c, verifier)
		if err != nil {
			return err
		}
		defer controller.client.CloseIdleConnections()
		proxies, err := controller.proxies()
		if err != nil {
			return err
		}
		result := mihomoRestoreResult{Restored: []mihomoSelectionResult{}, Skipped: []mihomoSelectionResult{}}
		for _, group := range SortedKeys(state.Selections) {
			node := state.Selections[group]
			choice := mihomoSelectionResult{Group: group, Node: node}
			p, found := proxies[group]
			if !found || p.Type != "Selector" || !mihomoContains(p.All, node) {
				result.Skipped = append(result.Skipped, choice)
				if format != "json" {
					fmt.Fprintf(out, "%s: %s → %s\n", Text(c.Language, "Saved group/node is missing; current selection preserved", "原策略组或节点已不存在，保留当前选择"), group, node)
				}
				continue
			}
			if err = controller.selectNode(group, node); err != nil {
				return err
			}
			result.Restored = append(result.Restored, choice)
			if format != "json" {
				fmt.Fprintf(out, "%s: %s → %s\n", Text(c.Language, "Restored selection", "已恢复选择"), group, node)
			}
		}
		if format == "json" {
			return json.NewEncoder(out).Encode(result)
		}
		return nil
	})
}

func mihomoTestNodes(controller *mihomoController, proxies map[string]mihomoProxy, group mihomoProxy, args []string, format string, out io.Writer) error {
	c := controller.config
	nodes := []string{}
	if len(args) > 1 {
		if !mihomoContains(group.All, args[1]) {
			return mihomoError(c, "E_MIHOMO_NODE", "The node is not a member of this group.", "该节点不在此策略组中。")
		}
		nodes = append(nodes, args[1])
	} else {
		for _, node := range group.All {
			p := proxies[node]
			if len(p.All) == 0 && node != "DIRECT" && node != "REJECT" && p.Type != "Direct" && p.Type != "Reject" {
				nodes = append(nodes, node)
			}
		}
	}
	if len(nodes) == 0 {
		return mihomoError(c, "E_MIHOMO_NODE", "No direct node entries are in this group. Specify a member to test a nested policy group.", "此策略组没有直接节点项；可指定一个成员名来测试嵌套策略组。")
	}
	if len(nodes) > 128 {
		return mihomoError(c, "E_MIHOMO_ARGUMENT", "More than 128 nodes are in this group; specify one node to test.", "此组超过 128 个节点，请指定要测试的节点名。")
	}
	results := make([]mihomoDelayResult, len(nodes))
	jobs := make(chan int)
	var workers sync.WaitGroup
	for worker := 0; worker < min(4, len(nodes)); worker++ {
		workers.Add(1)
		go func() {
			defer workers.Done()
			for i := range jobs {
				row := mihomoDelayResult{Node: nodes[i]}
				var result struct {
					Delay *int `json:"delay"`
				}
				query := url.Values{"timeout": {"5000"}, "url": {"https://www.gstatic.com/generate_204"}}.Encode()
				err := controller.request(http.MethodGet, "/proxies/"+url.PathEscape(nodes[i])+"/delay?"+query, nil, &result)
				if err == nil && result.Delay != nil && *result.Delay >= 0 {
					row.OK, row.DelayMS = true, *result.Delay
				} else {
					row.ErrorCode = "E_MIHOMO_TEST_FAILED"
				}
				results[i] = row
			}
		}()
	}
	for i := range nodes {
		jobs <- i
	}
	close(jobs)
	workers.Wait()
	if format == "json" {
		if err := json.NewEncoder(out).Encode(map[string]any{"group": group.Name, "results": results}); err != nil {
			return err
		}
	} else {
		fmt.Fprintln(out, Text(c.Language, "Connection tests (the selected node is not changed):", "连通性测试（不会改变当前选择）："))
		for _, result := range results {
			if result.OK {
				fmt.Fprintf(out, "  %s: %d ms\n", result.Node, result.DelayMS)
			} else {
				fmt.Fprintf(out, "  %s: %s\n", result.Node, Text(c.Language, "unreachable or timed out", "不可达或超时"))
			}
		}
	}
	for _, result := range results {
		if result.OK {
			return nil
		}
	}
	return mihomoError(c, "E_MIHOMO_TEST_FAILED", "All tested nodes failed. Check the network and subscription.", "所测试的节点均失败，请检查网络和订阅。")
}
