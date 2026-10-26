package config

import (
	"context"
	"errors"
	"os"
	"os/user"
	"path/filepath"
	"runtime"
	"strings"
)

var errMihomoNoListener = errors.New("managed Mihomo API is not listening")
var errMihomoUnverifiedOwner = errors.New("Mihomo listener ownership could not be verified")

type mihomoOwnerVerifier func(context.Context) error

func mihomoManagedConfigDirectory(expected string) (string, error) {
	if runtime.GOOS != "windows" {
		return filepath.Dir(expected), nil
	}
	directory := os.Getenv("MIHOMO_SOURCE_CONFIG")
	if directory == "" {
		home, err := os.UserHomeDir()
		if err != nil {
			return "", errMihomoUnverifiedOwner
		}
		directory = filepath.Join(home, ".config", "mihomo")
	}
	if !filepath.IsAbs(directory) {
		return "", errMihomoUnverifiedOwner
	}
	return filepath.EvalSymlinks(directory)
}

func mihomoManagedExecutable(c Config) (string, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return "", err
	}
	if runtime.GOOS == "windows" {
		binary := filepath.Join(home, "software", "mihomo", "mihomo.exe")
		if _, err = os.Stat(binary); os.IsNotExist(err) {
			binary = filepath.Join(Expand(c.Install.Prefix), "mihomo", "mihomo.exe")
		}
		return filepath.EvalSymlinks(binary)
	}
	directory := os.Getenv("MIHOMO_RUNTIME_DIR")
	if directory == "" {
		username := ""
		if current, err := user.Current(); err == nil {
			username = current.Username
		}
		if username == "" {
			username = os.Getenv("USER")
		}
		host, err := os.Hostname()
		if err != nil || host == "" || username == "" || strings.ContainsAny(host+username, `/\`) {
			return "", errMihomoUnverifiedOwner
		}
		directory = filepath.Join("/tmp", username+"_mihomo_"+host)
	}
	if !filepath.IsAbs(directory) {
		return "", errMihomoUnverifiedOwner
	}
	return filepath.EvalSymlinks(filepath.Join(directory, "mihomo"))
}

func mihomoSameExecutable(actual, expected string) bool {
	actual, actualErr := filepath.EvalSymlinks(actual)
	expected, expectedErr := filepath.EvalSymlinks(expected)
	if actualErr != nil || expectedErr != nil {
		return false
	}
	if runtime.GOOS == "windows" {
		return strings.EqualFold(strings.TrimPrefix(actual, `\\?\`), strings.TrimPrefix(expected, `\\?\`))
	}
	return actual == expected
}
