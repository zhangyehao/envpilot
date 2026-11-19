package config

import (
	"bytes"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"strings"

	"github.com/pelletier/go-toml/v2"
	"go.yaml.in/yaml/v3"
)

// PortableConfig exports persisted preferences, including defaults for omitted
// fields. The allowlist deliberately excludes paths, env, provider URLs,
// secret references, proxy ports and the shared-home maintenance host.
func PortableConfig(path string) ([]byte, error) {
	b, err := os.ReadFile(Expand(path))
	if err != nil {
		return nil, err
	}
	c, err := parsedConfig(b, path)
	if err != nil {
		return nil, fmt.Errorf("E_PORTABLE_CONFIG: invalid configuration")
	}
	// Work from typed data only. Comments, YAML anchors, extension fields and
	// environment overrides in the current process must not leak into the export.
	var all yaml.Node
	if err = all.Encode(c); err != nil {
		return nil, err
	}
	allow := map[string][]string{
		"version": nil, "language": nil,
		"install": {"components", "release_source"},
		"shell":   {"enabled", "conda", "prefer_managed", "history_sync", "legacy_aliases"},
		"conda":   {"distribution", "condarc_policy"},
		"codex":   {"remote", "ready_timeout"},
		"mihomo":  {"group_order", "subscription_network", "socks"},
		"updates": {"enabled", "interval_days", "auto_apply", "components", "envpilot", "window_start", "window_end", "timezone", "policies", "models", "subscription"},
	}
	dst := &yaml.Node{Kind: yaml.MappingNode}
	for i := 0; i < len(all.Content); i += 2 {
		key, val := all.Content[i], all.Content[i+1]
		fields, ok := allow[key.Value]
		if !ok {
			continue
		}
		if fields != nil {
			selected := &yaml.Node{Kind: yaml.MappingNode}
			for j := 0; j < len(val.Content); j += 2 {
				if containsComponent(fields, val.Content[j].Value) {
					selected.Content = append(selected.Content, val.Content[j], val.Content[j+1])
				}
			}
			val = selected
		}
		dst.Content = append(dst.Content, key, val)
	}
	var buf bytes.Buffer
	enc := yaml.NewEncoder(&buf)
	enc.SetIndent(2)
	if err := enc.Encode(dst); err != nil {
		return nil, err
	}
	return buf.Bytes(), nil
}

// Only export top-level, portable model choices. Parse errors are intentionally
// generic: a TOML parser may include the line containing a credential.
func PortableCodexPreferences(c Config) ([]byte, error) {
	f, err := os.Open(filepath.Join(Expand(c.Codex.Home), "config.toml"))
	if err != nil {
		return nil, err
	}
	defer f.Close()
	const limit = 2 << 20
	b, err := io.ReadAll(io.LimitReader(f, limit+1))
	if err != nil || len(b) > limit {
		return nil, fmt.Errorf("E_CODEX_PREFERENCES: cannot read config.toml")
	}
	var p struct {
		Model  string `toml:"model,omitempty"`
		Effort string `toml:"model_reasoning_effort,omitempty"`
	}
	if toml.Unmarshal(b, &p) != nil {
		return nil, fmt.Errorf("E_CODEX_PREFERENCES: invalid TOML")
	}
	if p.Model != "" {
		model := strings.ToLower(p.Model)
		if len(model) > 200 {
			return nil, fmt.Errorf("E_CODEX_PREFERENCES: invalid model ID")
		}
		for _, part := range strings.Split(model, "/") {
			if !regexp.MustCompile(`^[a-z0-9][a-z0-9_.:+-]*$`).MatchString(part) ||
				strings.HasPrefix(part, "sk-") || strings.HasPrefix(part, "ghp_") || strings.HasPrefix(part, "github_pat_") {
				return nil, fmt.Errorf("E_CODEX_PREFERENCES: invalid model ID")
			}
		}
	}
	if p.Effort != "" && !containsComponent([]string{"none", "minimal", "low", "medium", "high", "xhigh", "max", "ultra"}, p.Effort) {
		return nil, fmt.Errorf("E_CODEX_PREFERENCES: unknown model_reasoning_effort")
	}
	return toml.Marshal(p)
}
