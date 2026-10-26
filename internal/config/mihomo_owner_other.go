//go:build !linux && !windows && !darwin

package config

import "context"

func verifyMihomoListenerOwner(context.Context, int, string, string) error {
	return errMihomoUnverifiedOwner
}
