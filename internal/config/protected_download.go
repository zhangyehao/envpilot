package config

import (
	"bytes"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"time"

	"go.yaml.in/yaml/v3"
)

func DownloadSubscription(value, destination string) error {
	value = strings.TrimSpace(value)
	parsed, err := url.Parse(value)
	if err != nil || parsed.Host == "" || (parsed.Scheme != "http" && parsed.Scheme != "https") {
		return fmt.Errorf("E_SUBSCRIPTION: provide a protected http(s) subscription URL")
	}
	client := http.Client{Timeout: 90 * time.Second}
	response, err := client.Get(value)
	if err != nil {
		return fmt.Errorf("E_SUBSCRIPTION: protected download failed; check the URL reference and network")
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return fmt.Errorf("E_SUBSCRIPTION: upstream returned HTTP %d", response.StatusCode)
	}
	data, err := io.ReadAll(io.LimitReader(response.Body, 32*1024*1024+1))
	if err != nil || len(data) > 32*1024*1024 || len(data) == 0 {
		return fmt.Errorf("E_SUBSCRIPTION: incomplete or oversized configuration")
	}
	var document yaml.Node
	decoder := yaml.NewDecoder(bytes.NewReader(data))
	if err = decoder.Decode(&document); err != nil || len(document.Content) != 1 || document.Content[0].Kind != yaml.MappingNode {
		return fmt.Errorf("E_SUBSCRIPTION: response must be a YAML mapping")
	}
	var extra any
	if decoder.Decode(&extra) != io.EOF {
		return fmt.Errorf("E_SUBSCRIPTION: expected one YAML document")
	}
	document.Content[0].Style = 0
	for i := 0; i < len(document.Content[0].Content); i += 2 {
		document.Content[0].Content[i].Style = 0
	}
	var normalized bytes.Buffer
	encoder := yaml.NewEncoder(&normalized)
	encoder.SetIndent(2)
	if encoder.Encode(&document) != nil {
		return fmt.Errorf("E_SUBSCRIPTION: could not normalize the configuration")
	}
	return WriteAtomic(destination, normalized.Bytes(), 0600)
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
