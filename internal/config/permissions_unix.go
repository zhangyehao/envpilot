//go:build !windows

package config

import (
	"fmt"
	"os"
	"syscall"
)

func CheckSecretPermissions(path string, st os.FileInfo) error {
	if st.Mode().Perm() != 0600 && st.Mode().Perm() != 0400 {
		return fmt.Errorf("protected file must use mode 600 or 400: %s", path)
	}
	if stat, ok := st.Sys().(*syscall.Stat_t); !ok || stat.Uid != uint32(os.Getuid()) {
		return fmt.Errorf("protected file must belong to the current user: %s", path)
	}
	return nil
}

func platformChinese() bool { return false }
