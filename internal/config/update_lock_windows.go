package config

import (
	"os"
	"syscall"
	"unsafe"
)

var lockFileEx = syscall.NewLazyDLL("kernel32.dll").NewProc("LockFileEx")
var unlockFileEx = syscall.NewLazyDLL("kernel32.dll").NewProc("UnlockFileEx")

func lockUpdateFile(f *os.File) error {
	var overlap syscall.Overlapped
	ok, _, err := lockFileEx.Call(f.Fd(), 3, 0, 1, 0, uintptr(unsafe.Pointer(&overlap)))
	if ok == 0 {
		return err
	}
	return nil
}
func unlockUpdateFile(f *os.File) {
	var overlap syscall.Overlapped
	_, _, _ = unlockFileEx.Call(f.Fd(), 0, 1, 0, uintptr(unsafe.Pointer(&overlap)))
}
