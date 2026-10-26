package config

import (
	"os/exec"
	"syscall"
)

func hideMihomoOwnerWindow(command *exec.Cmd) {
	command.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}
}
