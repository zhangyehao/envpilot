package config

import (
	"bytes"
	"context"
	"crypto/tls"
	"crypto/x509"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"

	"go.yaml.in/yaml/v3"
)

// SubscriptionDownloadOptions controls protected subscription retrieval. No URL,
// response body or raw transport error is written to Progress.
type SubscriptionDownloadOptions struct {
	Network   string    // auto (direct, then proxies), direct, or proxy
	ProxyPort int       // local managed proxy; zero selects 42290
	Language  string    // auto, en, or zh-CN; empty uses ENVPILOT_LANG
	Progress  io.Writer // nil keeps successful operations silent
}

const subscriptionMaxBytes = 32 * 1024 * 1024

// DownloadSubscription is retained for older installer adapters.
func DownloadSubscription(value, destination string) error {
	port, _ := strconv.Atoi(os.Getenv("MIHOMO_PROXY_PORT"))
	return DownloadSubscriptionWithOptions(value, destination, SubscriptionDownloadOptions{
		Network:   os.Getenv("ENVPILOT_SUBSCRIPTION_NETWORK"),
		ProxyPort: port, Language: os.Getenv("ENVPILOT_LANG"),
	})
}

func DownloadSubscriptionWithOptions(value, destination string, options SubscriptionDownloadOptions) error {
	return subscriptionDownloader{options: options, sleep: sleepSubscription, client: newSubscriptionClient}.download(value, destination)
}

type subscriptionRoute struct {
	name  string
	proxy *url.URL
}

type subscriptionFailure struct {
	code  string
	en    string
	zh    string
	retry bool
	delay time.Duration
}

func (f *subscriptionFailure) localized(lang string) string {
	return f.code + ": " + Text(lang, f.en, f.zh)
}

type subscriptionDownloader struct {
	options SubscriptionDownloadOptions
	sleep   func(context.Context, time.Duration) bool
	client  func(*url.URL) *http.Client
}

func (d subscriptionDownloader) download(value, destination string) error {
	options := d.options
	if options.Language == "" {
		options.Language = os.Getenv("ENVPILOT_LANG")
	}
	if options.Network == "" {
		options.Network = "auto"
	}
	if options.ProxyPort == 0 {
		options.ProxyPort = 42290
	}
	if options.Network != "auto" && options.Network != "direct" && options.Network != "proxy" {
		return fmt.Errorf("E_SUBSCRIPTION_NETWORK: %s", Text(options.Language, "use auto, direct, or proxy", "请选择 auto、direct 或 proxy"))
	}
	if options.ProxyPort < 1 || options.ProxyPort > 65535 {
		return fmt.Errorf("E_SUBSCRIPTION_NETWORK: %s", Text(options.Language, "invalid local proxy port", "本地代理端口无效"))
	}
	value = strings.TrimSpace(value)
	parsed, err := url.Parse(value)
	if err != nil || parsed.Hostname() == "" || (parsed.Scheme != "http" && parsed.Scheme != "https") {
		return fmt.Errorf("E_SUBSCRIPTION_URL: %s", Text(options.Language, "provide a protected http(s) subscription URL", "请通过受保护文件或环境变量提供 http(s) 订阅地址"))
	}
	parsed.Fragment = ""
	routes := subscriptionRoutes(parsed, options)
	ctx, cancel := context.WithTimeout(context.Background(), 90*time.Second)
	defer cancel()
	failures := []string{}
	for _, route := range routes {
		routeName := route.name
		if IsChinese(options.Language) {
			routeName = map[string]string{"direct": "直连", "environment proxy": "环境代理", "local Mihomo proxy": "本地 Mihomo 代理"}[route.name]
		}
		if options.Progress != nil {
			fmt.Fprintln(options.Progress, Text(options.Language, "[INFO] Downloading subscription via ", "[INFO] 正在下载订阅，连接方式：")+routeName)
		}
		client := d.client(route.proxy)
		var failure *subscriptionFailure
		var data []byte
		for attempt := 0; attempt < 3; attempt++ {
			data, failure = fetchSubscription(ctx, client, parsed, route.proxy != nil)
			if failure == nil || !failure.retry || attempt == 2 || ctx.Err() != nil {
				break
			}
			delay := time.Duration(1<<attempt) * time.Second
			if failure.delay > delay {
				delay = failure.delay
			}
			// Retry-After is an upstream minimum, not a hint that can be
			// shortened to fit our local retry policy. Fail promptly when
			// the requested wait cannot fit, without trying another proxy.
			if deadline, ok := ctx.Deadline(); ok && failure.delay > 0 && delay >= time.Until(deadline) {
				failure.en += "; the requested retry interval exceeds the remaining download budget; try again later"
				failure.zh += "；服务端要求的重试间隔超过本次下载剩余时限，请稍后重试"
				break
			}
			if options.Progress != nil {
				fmt.Fprintf(options.Progress, "%s: %s; %s %d/3\n", routeName, failure.localized(options.Language), Text(options.Language, "retry", "重试"), attempt+2)
			}
			if !d.sleep(ctx, delay) {
				break
			}
		}
		if transport, ok := client.Transport.(interface{ CloseIdleConnections() }); ok {
			transport.CloseIdleConnections()
		}
		if failure == nil {
			if err := WriteAtomic(destination, data, 0600); err != nil {
				return fmt.Errorf("E_SUBSCRIPTION_WRITE: %s", Text(options.Language, "could not atomically save the validated subscription; previous file retained", "无法原子保存已校验的订阅；保留原文件"))
			}
			if options.Progress != nil {
				fmt.Fprintln(options.Progress, Text(options.Language, "[OK] Subscription downloaded and validated via ", "[OK] 订阅下载及校验成功，连接方式：")+routeName)
			}
			return nil
		}
		failures = append(failures, routeName+" ["+failure.localized(options.Language)+"]")
		if ctx.Err() != nil {
			break
		}
		// Authentication, missing URLs and rate limits are upstream decisions.
		// A final positive Retry-After also prevents immediate proxy fallback
		// for responses such as 503, even when retries were exhausted.
		if failure.delay > 0 || failure.code == "E_SUBSCRIPTION_AUTH" || failure.code == "E_SUBSCRIPTION_NOT_FOUND" || failure.code == "E_SUBSCRIPTION_RATE_LIMIT" {
			break
		}
	}
	return fmt.Errorf("E_SUBSCRIPTION_DOWNLOAD: %s. %s", strings.Join(failures, "; "), Text(options.Language,
		"Previous configuration retained. Check network/proxy access, or import a downloaded Mihomo YAML with --file.",
		"保留原配置。请检查网络及代理，或使用 --file 导入已下载的 Mihomo YAML。"))
}

func subscriptionRoutes(target *url.URL, options SubscriptionDownloadOptions) []subscriptionRoute {
	routes := []subscriptionRoute{}
	if options.Network != "proxy" {
		routes = append(routes, subscriptionRoute{name: "direct"})
	}
	if options.Network == "direct" {
		return routes
	}
	// Read each invocation's environment instead of ProxyFromEnvironment's
	// process-wide cache. Explicit proxy mode intentionally ignores NO_PROXY.
	keys := []string{"HTTPS_PROXY", "https_proxy", "ALL_PROXY", "all_proxy"}
	if target.Scheme == "http" {
		keys = []string{"HTTP_PROXY", "http_proxy", "ALL_PROXY", "all_proxy"}
	}
	seen := map[string]bool{}
	for _, key := range keys {
		value := strings.TrimSpace(os.Getenv(key))
		if value == "" {
			continue
		}
		if !strings.Contains(value, "://") {
			value = "http://" + value
		}
		proxy, err := url.Parse(value)
		if err != nil || proxy.Hostname() == "" || (proxy.Scheme != "http" && proxy.Scheme != "https" && proxy.Scheme != "socks5" && proxy.Scheme != "socks5h") {
			continue
		}
		if !seen[proxy.String()] {
			routes = append(routes, subscriptionRoute{name: "environment proxy", proxy: proxy})
			seen[proxy.String()] = true
		}
		// Match conventional uppercase/lowercase precedence, rather than trying
		// stale alternatives after an explicit environment proxy was chosen.
		break
	}
	local, _ := url.Parse("http://127.0.0.1:" + strconv.Itoa(options.ProxyPort))
	if !seen[local.String()] {
		routes = append(routes, subscriptionRoute{name: "local Mihomo proxy", proxy: local})
	}
	return routes
}

func newSubscriptionClient(proxy *url.URL) *http.Client {
	transport := &http.Transport{
		Proxy:                 nil,
		DialContext:           (&net.Dialer{Timeout: 5 * time.Second, KeepAlive: 30 * time.Second}).DialContext,
		TLSHandshakeTimeout:   8 * time.Second,
		ResponseHeaderTimeout: 15 * time.Second,
		ExpectContinueTimeout: time.Second,
		ForceAttemptHTTP2:     true,
		MaxIdleConns:          2,
		IdleConnTimeout:       15 * time.Second,
	}
	if proxy != nil {
		transport.Proxy = http.ProxyURL(proxy)
	}
	return &http.Client{Transport: transport, Timeout: 20 * time.Second, CheckRedirect: subscriptionRedirect}
}

func subscriptionRedirect(req *http.Request, via []*http.Request) error {
	// Subscription tokens often live in the query/path. net/http would otherwise
	// send that original URL in Referer to the redirect destination.
	req.Header.Del("Referer")
	if len(via) >= 5 {
		return errors.New("subscription redirect limit")
	}
	previous := via[len(via)-1].URL
	if previous.Scheme == "https" && req.URL.Scheme != "https" {
		return errors.New("subscription insecure redirect")
	}
	if req.URL.Scheme != "http" && req.URL.Scheme != "https" {
		return errors.New("subscription unsupported redirect")
	}
	original := via[0].URL
	if original.Scheme != req.URL.Scheme || original.Host != req.URL.Host {
		req.Header.Del("Authorization")
		req.Header.Del("Cookie")
		req.URL.User = nil
	}
	return nil
}

func fetchSubscription(ctx context.Context, client *http.Client, target *url.URL, proxied bool) ([]byte, *subscriptionFailure) {
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, target.String(), nil)
	if err != nil {
		return nil, &subscriptionFailure{"E_SUBSCRIPTION_URL", "invalid subscription URL", "订阅地址无效", false, 0}
	}
	request.Header.Set("User-Agent", "clash.meta/envpilot")
	request.Header.Set("Accept", "application/yaml, text/yaml, application/x-yaml, text/plain, */*")
	response, err := client.Do(request)
	if err != nil {
		return nil, subscriptionNetworkFailure(err, proxied)
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		failure := &subscriptionFailure{code: "E_SUBSCRIPTION_HTTP", en: fmt.Sprintf("upstream returned HTTP %d", response.StatusCode), zh: fmt.Sprintf("订阅服务返回 HTTP %d", response.StatusCode)}
		switch response.StatusCode {
		case 401, 403:
			failure.code = "E_SUBSCRIPTION_AUTH"
			failure.en += "; check subscription validity or provider access restrictions"
			failure.zh += "；请检查订阅有效期或供应商访问限制"
		case 404, 410:
			failure.code = "E_SUBSCRIPTION_NOT_FOUND"
		case 429:
			failure.code = "E_SUBSCRIPTION_RATE_LIMIT"
			failure.retry = true
		case 500, 502, 503, 504:
			failure.retry = true
		}
		failure.delay = subscriptionRetryAfter(response.Header.Get("Retry-After"), time.Now())
		return nil, failure
	}
	if strings.Contains(strings.ToLower(response.Header.Get("Content-Type")), "text/html") {
		return nil, &subscriptionFailure{"E_SUBSCRIPTION_HTML", "upstream returned an HTML page, not a Mihomo subscription", "订阅服务返回 HTML 网页，非 Mihomo 订阅配置", false, 0}
	}
	data, err := io.ReadAll(io.LimitReader(response.Body, subscriptionMaxBytes+1))
	if err != nil {
		return nil, &subscriptionFailure{"E_SUBSCRIPTION_BODY", "download interrupted before the configuration was complete", "下载中断，配置内容不完整", true, 0}
	}
	return normalizeSubscription(data)
}

func subscriptionNetworkFailure(err error, proxied bool) *subscriptionFailure {
	var dns *net.DNSError
	var cert *tls.CertificateVerificationError
	var authority x509.UnknownAuthorityError
	var hostname x509.HostnameError
	var record tls.RecordHeaderError
	var urlError *url.Error
	switch {
	case errors.As(err, &dns):
		return &subscriptionFailure{"E_SUBSCRIPTION_DNS", "DNS resolution failed; check this node's resolver", "DNS 解析失败，请检查当前节点的域名解析", true, 0}
	case errors.As(err, &cert), errors.As(err, &authority), errors.As(err, &hostname), errors.As(err, &record):
		return &subscriptionFailure{"E_SUBSCRIPTION_TLS", "TLS verification or handshake failed; check certificates and HTTPS access", "TLS 校验或握手失败，请检查证书及 HTTPS 访问", false, 0}
	case errors.Is(err, syscall.ECONNREFUSED):
		if proxied {
			return &subscriptionFailure{"E_SUBSCRIPTION_PROXY_REFUSED", "proxy connection refused; the configured proxy may be stopped", "代理连接被拒绝，配置的代理可能已停止", false, 0}
		}
		return &subscriptionFailure{"E_SUBSCRIPTION_CONNECT", "connection refused by upstream", "订阅服务拒绝连接", true, 0}
	case errors.Is(err, context.DeadlineExceeded):
		return &subscriptionFailure{"E_SUBSCRIPTION_TIMEOUT", "connection or download timed out", "连接或下载超时", true, 0}
	case errors.As(err, &urlError) && strings.Contains(urlError.Err.Error(), "subscription "):
		return &subscriptionFailure{"E_SUBSCRIPTION_REDIRECT", "unsafe or excessive redirect rejected", "已拒绝不安全或过多的重定向", false, 0}
	}
	var timeout net.Error
	if errors.As(err, &timeout) && timeout.Timeout() {
		return &subscriptionFailure{"E_SUBSCRIPTION_TIMEOUT", "connection or download timed out", "连接或下载超时", true, 0}
	}
	// Classify by types, never by formatting the raw error, URL or HTTP body.
	return &subscriptionFailure{"E_SUBSCRIPTION_CONNECT", "network connection failed", "网络连接失败", true, 0}
}

func subscriptionRetryAfter(value string, now time.Time) time.Duration {
	value = strings.TrimSpace(value)
	seconds, err := strconv.ParseUint(value, 10, 64)
	const maxDuration = time.Duration(1<<63 - 1)
	if err == nil {
		if seconds > uint64(maxDuration/time.Second) {
			return maxDuration
		}
		return time.Duration(seconds) * time.Second
	}
	if errors.Is(err, strconv.ErrRange) {
		// Even an unrepresentably large delay must never turn into an
		// immediate retry; this sentinel always exceeds our request budget.
		return maxDuration
	}
	if date, err := http.ParseTime(value); err == nil {
		if delay := date.Sub(now); delay > 0 {
			return delay
		}
	}
	return 0
}

func sleepSubscription(ctx context.Context, delay time.Duration) bool {
	timer := time.NewTimer(delay)
	defer timer.Stop()
	select {
	case <-ctx.Done():
		return false
	case <-timer.C:
		return true
	}
}

func normalizeSubscription(data []byte) ([]byte, *subscriptionFailure) {
	if len(data) > subscriptionMaxBytes || len(bytes.TrimSpace(data)) == 0 {
		return nil, &subscriptionFailure{"E_SUBSCRIPTION_SIZE", "configuration is empty or exceeds 32 MiB", "配置为空或超过 32 MiB 大小限制", false, 0}
	}
	if bytes.HasPrefix(bytes.TrimSpace(data), []byte("<")) {
		return nil, &subscriptionFailure{"E_SUBSCRIPTION_HTML", "response is an HTML/XML page, not a Mihomo subscription", "返回内容为 HTML/XML 网页，非 Mihomo 订阅配置", false, 0}
	}
	failure := &subscriptionFailure{"E_SUBSCRIPTION_YAML", "response is not a complete Mihomo YAML configuration; expected proxies/proxy-providers and proxy-groups/rules", "返回内容不是完整的 Mihomo YAML 配置；需要 proxies/proxy-providers 及 proxy-groups/rules", false, 0}
	var document yaml.Node
	decoder := yaml.NewDecoder(bytes.NewReader(data))
	if err := decoder.Decode(&document); err != nil || len(document.Content) != 1 || document.Content[0].Kind != yaml.MappingNode {
		return nil, failure
	}
	var extra any
	if decoder.Decode(&extra) != io.EOF {
		return nil, failure
	}
	// Decode once to validate duplicate keys, aliases and collection types.
	// Parser diagnostics may contain credentials and are intentionally discarded.
	var fields map[string]any
	if err := document.Decode(&fields); err != nil {
		return nil, failure
	}
	proxyList, hasProxyList := fields["proxies"].([]any)
	providers, hasProviders := fields["proxy-providers"].(map[string]any)
	groups, hasGroups := fields["proxy-groups"].([]any)
	rules, hasRules := fields["rules"].([]any)
	if (!hasProxyList && !hasProviders) || (!hasGroups && !hasRules) {
		return nil, failure
	}
	for _, node := range append(proxyList, groups...) {
		if _, ok := node.(map[string]any); !ok {
			return nil, failure
		}
	}
	for _, provider := range providers {
		if _, ok := provider.(map[string]any); !ok {
			return nil, failure
		}
	}
	for _, rule := range rules {
		if _, ok := rule.(string); !ok {
			return nil, failure
		}
	}
	document.Content[0].Style = 0
	for i := 0; i < len(document.Content[0].Content); i += 2 {
		document.Content[0].Content[i].Style = 0
	}
	var normalized bytes.Buffer
	encoder := yaml.NewEncoder(&normalized)
	encoder.SetIndent(2)
	if encoder.Encode(&document) != nil || encoder.Close() != nil {
		return nil, failure
	}
	return normalized.Bytes(), nil
}

// ImportSubscription validates a local full configuration without any network
// access. The source contains proxy credentials and must use protected-file
// permissions on Unix; the original target is retained on every validation error.
func ImportSubscription(source, destination string) error {
	lang := os.Getenv("ENVPILOT_LANG")
	source = Expand(source)
	file, err := os.Open(source)
	if err != nil {
		return fmt.Errorf("E_SUBSCRIPTION_FILE: %s", Text(lang, "could not open the subscription file", "无法打开订阅配置文件"))
	}
	defer file.Close()
	st, err := file.Stat()
	if err != nil || !st.Mode().IsRegular() {
		return fmt.Errorf("E_SUBSCRIPTION_FILE: %s", Text(lang, "subscription source must be a regular file", "订阅来源必须为普通文件"))
	}
	if err := CheckSecretPermissions(source, st); err != nil {
		return fmt.Errorf("E_SUBSCRIPTION_FILE: %s", Text(lang, "protect the subscription file: current-user ownership and mode 600 or 400 are required on Unix", "请保护订阅文件：Unix 下需要当前用户属主及 600 或 400 权限"))
	}
	data, err := io.ReadAll(io.LimitReader(file, subscriptionMaxBytes+1))
	if err != nil {
		return fmt.Errorf("E_SUBSCRIPTION_FILE: %s", Text(lang, "could not read the subscription file", "无法读取订阅配置文件"))
	}
	data, failure := normalizeSubscription(data)
	if failure != nil {
		return errors.New(failure.localized(lang))
	}
	if err = WriteAtomic(destination, data, 0600); err != nil {
		return fmt.Errorf("E_SUBSCRIPTION_WRITE: %s", Text(lang, "could not atomically save the validated subscription; previous file retained", "无法原子保存已校验的订阅；保留原文件"))
	}
	return nil
}

func Preflight(c Config) error {
	if !c.Shell.AutoStartProxy {
		return nil
	}
	home, _ := os.UserHomeDir()
	if info, err := os.Stat(filepath.Join(home, ".config", "mihomo", "config.yaml")); err == nil && info.Size() > 0 {
		return nil
	}
	value, err := ResolveReference(c.Mihomo.Subscription)
	if err != nil {
		return err
	}
	if value == "" {
		return fmt.Errorf("E_INPUT_REQUIRED: shell.auto_start_proxy needs an existing Mihomo config or a readable mihomo.subscription reference")
	}
	parsed, err := url.Parse(value)
	if err != nil || parsed.Host == "" || (parsed.Scheme != "http" && parsed.Scheme != "https") {
		return fmt.Errorf("E_INPUT_REQUIRED: mihomo.subscription must reference an http(s) URL")
	}
	return nil
}
