package config

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"time"
)

// PrintToolPreflight exercises the installer's own checks without fetching a release.
func PrintToolPreflight(w io.Writer, r Resolved, root, name string, asJSON bool) error {
	if name != "git" && name != "python" {
		return fmt.Errorf("preflight: choose git or python")
	}
	result := HostCheck{Name: name, Status: "ok"}
	if runtime.GOOS == "windows" {
		result.Status = "info"
		result.Detail = Text(r.Config.Language, "Native Windows uses its package manager for this tool.", "原生 Windows 通过包管理器维护此工具。")
	} else {
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
		defer cancel()
		cmd := exec.CommandContext(ctx, "bash", filepath.Join(root, "scripts", "probe-managed-tool.sh"), name)
		cmd.Env = os.Environ()
		for key, value := range r.Environment() {
			cmd.Env = append(cmd.Env, key+"="+value)
		}
		output, err := cmd.CombinedOutput()
		result.Detail = strings.TrimSpace(string(output))
		if err != nil {
			result.Status = "failed"
			if result.Detail == "" {
				result.Detail = err.Error()
			}
		}
	}
	var err error
	if asJSON {
		err = json.NewEncoder(w).Encode([]HostCheck{result})
	} else {
		_, err = fmt.Fprintf(w, "%s [%s]\n%s\n", name, result.Status, result.Detail)
	}
	if err == nil && result.Status == "failed" {
		return fmt.Errorf("E_TOOL_PREFLIGHT: %s", name)
	}
	return err
}
