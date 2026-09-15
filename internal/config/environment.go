package config

import (
	"bufio"
	"fmt"
	"io"
	"net"
	"os"
	"strconv"
	"strings"
	"time"
)

// ReadEnvironment accepts assignment-only files. No shell syntax is evaluated.
func ReadEnvironment(path string) (map[string]string, error) {
	out := map[string]string{}
	path = Expand(path)
	if path == "" {
		return out, nil
	}
	st, err := os.Stat(path)
	if os.IsNotExist(err) {
		return out, nil
	}
	if err != nil {
		return nil, err
	}
	if err = CheckSecretPermissions(path, st); err != nil {
		return nil, err
	}
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	data, err := io.ReadAll(io.LimitReader(f, 1024*1024+1))
	if err != nil || len(data) > 1024*1024 {
		return nil, fmt.Errorf("protected environment file could not be read within its size limit")
	}
	decoded, _, err := decodeProfile(data)
	if err != nil {
		return nil, err
	}
	scan := bufio.NewScanner(strings.NewReader(decoded))
	for lineNo := 1; scan.Scan(); lineNo++ {
		line := strings.TrimSpace(scan.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		line = strings.TrimPrefix(line, "export ")
		line = strings.TrimPrefix(line, "$env:")
		kv := strings.SplitN(line, "=", 2)
		if len(kv) != 2 || !variable.MatchString(strings.TrimSpace(kv[0])) {
			return nil, fmt.Errorf("protected environment line %d is not an assignment", lineNo)
		}
		v := strings.TrimSpace(kv[1])
		if strings.Contains(v, "$(") || strings.Contains(v, "`") {
			return nil, fmt.Errorf("protected environment line %d contains executable syntax", lineNo)
		}
		if strings.HasPrefix(v, "'") {
			if !strings.HasSuffix(v, "'") || len(v) < 2 {
				return nil, fmt.Errorf("invalid quote on line %d", lineNo)
			}
			v = v[1 : len(v)-1]
		} else if strings.HasPrefix(v, `"`) {
			v, err = strconv.Unquote(v)
			if err != nil {
				return nil, fmt.Errorf("invalid quote on line %d", lineNo)
			}
		} else if strings.ContainsAny(v, " ;|&<>") {
			return nil, fmt.Errorf("quote the literal value on line %d", lineNo)
		}
		out[strings.TrimSpace(kv[0])] = v
	}
	return out, scan.Err()
}
func ResolveReference(ref Reference) (string, error) {
	if ref.Env != "" {
		return os.Getenv(ref.Env), nil
	}
	if ref.File == "" {
		return "", nil
	}
	p := Expand(ref.File)
	st, e := os.Stat(p)
	if os.IsNotExist(e) {
		return "", nil
	}
	if e != nil {
		return "", e
	}
	if e = CheckSecretPermissions(p, st); e != nil {
		return "", e
	}
	b, e := os.ReadFile(p)
	return strings.TrimSpace(string(b)), e
}
func (c Config) ChildEnvironment() (map[string]string, error) {
	out := map[string]string{}
	for _, kv := range os.Environ() {
		parts := strings.SplitN(kv, "=", 2)
		if len(parts) == 2 {
			out[parts[0]] = parts[1]
		}
	}
	values, e := ReadEnvironment(c.Secrets.File)
	if e != nil {
		return nil, e
	}
	for k, v := range values {
		if _, exists := out[k]; !exists {
			out[k] = v
		}
	}
	key, e := ResolveReference(c.Codex.APIKey)
	if e != nil {
		return nil, e
	}
	if key != "" {
		out["OPENAI_API_KEY"] = key
	}
	for k, v := range c.Env {
		out[k] = v
	}
	out["CODEX_HOME"] = Expand(c.Codex.Home)
	if c.Shell.AutoEnableProxy {
		address := fmt.Sprintf("127.0.0.1:%d", c.Mihomo.ProxyPort)
		conn, err := net.DialTimeout("tcp", address, time.Second)
		if err == nil {
			_ = conn.Close()
			for _, k := range []string{"http_proxy", "https_proxy", "HTTP_PROXY", "HTTPS_PROXY"} {
				out[k] = "http://" + address
			}
			if c.Mihomo.SOCKS {
				out["all_proxy"] = "socks5h://" + address
				out["ALL_PROXY"] = out["all_proxy"]
			}
			out["no_proxy"] = strings.Trim(out["no_proxy"]+",localhost,127.0.0.1,::1", ",")
			out["NO_PROXY"] = out["no_proxy"]
		}
	}
	return out, nil
}
