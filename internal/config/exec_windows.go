//go:build windows

package config

import (
	"os"
	"os/exec"
)

func ExecWithEnvironment(binary string, args []string, environment []string) error {
	command := exec.Command(binary, args...)
	command.Env = environment
	command.Stdin = os.Stdin
	command.Stdout = os.Stdout
	command.Stderr = os.Stderr
	if err := command.Run(); err != nil {
		if exit, ok := err.(*exec.ExitError); ok {
			os.Exit(exit.ExitCode())
		}
		return err
	}
	return nil
}
