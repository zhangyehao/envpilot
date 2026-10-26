package config

import (
	"context"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"time"
	"unicode/utf16"
	"unsafe"
)

func verifyMihomoListenerOwner(ctx context.Context, port int, expected, directory string) error {
	shell := filepath.Join(os.Getenv("SystemRoot"), "System32", "WindowsPowerShell", "v1.0", "powershell.exe")
	if _, err := os.Stat(shell); err != nil {
		return errMihomoUnverifiedOwner
	}
	// All input interpolated into the helper is an already validated integer.
	// The process owner's SID and exact image path are compared independently.
	script := fmt.Sprintf(`
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$identity = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$listeners = @(Get-NetTCPConnection -State Listen -LocalPort %d -ErrorAction SilentlyContinue)
$exact = @($listeners | Where-Object { $_.LocalAddress -eq '127.0.0.1' })
if ($exact.Count -gt 0) { $listeners = $exact }
else {
  $ipv4 = @($listeners | Where-Object { $_.LocalAddress -eq '0.0.0.0' })
  if ($ipv4.Count -gt 0) { $listeners = $ipv4 }
  else { $listeners = @($listeners | Where-Object { $_.LocalAddress -eq '::' -or $_.LocalAddress -eq '::ffff:127.0.0.1' }) }
}
$owners = @(
  foreach ($entry in $listeners) {
    $process = Get-CimInstance Win32_Process -Filter ("ProcessId=" + $entry.OwningProcess)
    if (-not $process -or -not $process.ExecutablePath) { throw 'Unverified listener' }
    $owner = Invoke-CimMethod -InputObject $process -MethodName GetOwnerSid
    if ($owner.ReturnValue -ne 0 -or $owner.Sid -ne $identity) { throw 'Unverified owner' }
    @{ pid = [int]$entry.OwningProcess; path = [string]$process.ExecutablePath; command = [string]$process.CommandLine }
  }
)
ConvertTo-Json -Compress -Depth 3 -InputObject @{ owners = $owners }
`, port)
	characters := utf16.Encode([]rune(script))
	data := make([]byte, 2*len(characters))
	for i, character := range characters {
		binary.LittleEndian.PutUint16(data[i*2:], character)
	}
	ctx, cancel := context.WithTimeout(ctx, 8*time.Second)
	defer cancel()
	command := exec.CommandContext(ctx, shell, "-NoProfile", "-NonInteractive", "-EncodedCommand", base64.StdEncoding.EncodeToString(data))
	hideMihomoOwnerWindow(command)
	output, err := command.Output()
	if err != nil || len(output) > 64<<10 {
		return errMihomoUnverifiedOwner
	}
	var result struct {
		Owners []struct {
			PID     int    `json:"pid"`
			Path    string `json:"path"`
			Command string `json:"command"`
		} `json:"owners"`
	}
	if json.Unmarshal(output, &result) != nil {
		return errMihomoUnverifiedOwner
	}
	if len(result.Owners) == 0 {
		return errMihomoNoListener
	}
	for _, owner := range result.Owners {
		if owner.PID < 1 || !mihomoSameExecutable(owner.Path, expected) {
			return errMihomoUnverifiedOwner
		}
		if directory != "" && !mihomoWindowsTargetsConfig(owner.Command, directory) {
			return errMihomoUnverifiedOwner
		}
	}
	return nil
}

func mihomoWindowsTargetsConfig(commandLine, expectedDirectory string) bool {
	encoded, err := syscall.UTF16PtrFromString(commandLine)
	if err != nil || commandLine == "" {
		return false
	}
	var count int32
	arguments, err := syscall.CommandLineToArgv(encoded, &count)
	if err != nil {
		return false
	}
	defer syscall.LocalFree(syscall.Handle(uintptr(unsafe.Pointer(arguments))))
	if count < 1 || count > 8192 {
		return false
	}
	directory, configFile := "", ""
	for i := int32(1); i < count; i++ {
		argument := syscall.UTF16ToString(arguments[i][:])
		if argument == "--" {
			break
		}
		switch {
		case argument == "-d" || argument == "--d" || argument == "-f" || argument == "--f":
			if i+1 >= count {
				return false
			}
			i++
			value := syscall.UTF16ToString(arguments[i][:])
			if argument == "-d" || argument == "--d" {
				directory = value
			} else {
				configFile = value
			}
		case strings.HasPrefix(argument, "-d="):
			directory = strings.TrimPrefix(argument, "-d=")
		case strings.HasPrefix(argument, "--d="):
			directory = strings.TrimPrefix(argument, "--d=")
		case strings.HasPrefix(argument, "-f="):
			configFile = strings.TrimPrefix(argument, "-f=")
		case strings.HasPrefix(argument, "--f="):
			configFile = strings.TrimPrefix(argument, "--f=")
		}
	}
	if !filepath.IsAbs(directory) || !mihomoSameExecutable(directory, expectedDirectory) {
		return false
	}
	return configFile == "" || (filepath.IsAbs(configFile) &&
		mihomoSameExecutable(configFile, filepath.Join(expectedDirectory, "config.yaml")))
}
