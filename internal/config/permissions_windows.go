//go:build windows

package config

import (
	"os"
	"syscall"
)

// Windows enforces access through the file's ACL, rather than POSIX mode bits.
func CheckSecretPermissions(_ string, _ os.FileInfo) error { return nil }

func platformChinese() bool {
	lang, _, _ := syscall.NewLazyDLL("kernel32.dll").NewProc("GetUserDefaultUILanguage").Call()
	return lang&0x3ff == 4
}
