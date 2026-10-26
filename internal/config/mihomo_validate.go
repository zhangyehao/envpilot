package config

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"time"
)

// ValidateMihomoConfig asks the installed engine to check a candidate before a
// working service is stopped. Native errors can contain subscription secrets.
func ValidateMihomoConfig(c Config, candidate string) error {
	name := "mihomo"
	if runtime.GOOS == "windows" {
		name += ".exe"
	}
	home, _ := os.UserHomeDir()
	// Existing Bash/PowerShell installations keep Mihomo in ~/software even
	// when install.prefix selects another root for other components.
	binary := filepath.Join(home, "software", "mihomo", name)
	if _, err := os.Stat(binary); os.IsNotExist(err) {
		binary = filepath.Join(Expand(c.Install.Prefix), "mihomo", name)
	}
	if _, err := os.Stat(binary); err != nil {
		return fmt.Errorf("E_MIHOMO_BINARY: %s", Text(c.Language,
			"install Mihomo before importing a subscription",
			"请先安装 Mihomo，再导入订阅"))
	}
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	command := exec.CommandContext(ctx, binary, "-t", "-d", filepath.Join(home, ".config", "mihomo"), "-f", candidate)
	if err := command.Run(); err != nil {
		if ctx.Err() != nil {
			return fmt.Errorf("E_MIHOMO_CONFIG_TIMEOUT: %s", Text(c.Language,
				"configuration validation timed out; existing configuration and service are unchanged",
				"配置校验超时，原有配置和服务保持不变"))
		}
		return fmt.Errorf("E_MIHOMO_CONFIG: %s", Text(c.Language,
			"Mihomo rejected the candidate configuration; existing configuration and service are unchanged",
			"Mihomo 拒绝了新配置，原有配置和服务保持不变"))
	}
	return nil
}
