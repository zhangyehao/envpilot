//go:build !windows

package config

import "syscall"

func ExecWithEnvironment(binary string, args []string, environment []string) error {
	return syscall.Exec(binary, append([]string{binary}, args...), environment)
}
