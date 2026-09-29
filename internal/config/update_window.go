package config

import (
	"fmt"
	"regexp"
	"time"
	_ "time/tzdata" // Platform bundles work without system zoneinfo.
)

var clockTime = regexp.MustCompile(`^(?:[01][0-9]|2[0-3]):[0-5][0-9]$`)

func validateUpdateWindow(u Updates) error {
	if !clockTime.MatchString(u.WindowStart) || !clockTime.MatchString(u.WindowEnd) || u.WindowStart == u.WindowEnd {
		return fmt.Errorf("updates.window_start/window_end must be distinct HH:MM values")
	}
	if u.Timezone == "" {
		return fmt.Errorf("updates.timezone is required")
	}
	if _, err := time.LoadLocation(u.Timezone); err != nil {
		return fmt.Errorf("updates.timezone must be Local or an IANA time zone")
	}
	return nil
}
func inUpdateWindow(u Updates, now time.Time) bool {
	loc, err := time.LoadLocation(u.Timezone)
	if err != nil {
		return false
	}
	clock := now.In(loc).Format("15:04")
	if u.WindowStart < u.WindowEnd {
		return clock >= u.WindowStart && clock < u.WindowEnd
	}
	return clock >= u.WindowStart || clock < u.WindowEnd
}
func nextUpdateWindow(u Updates, now time.Time) time.Time {
	if inUpdateWindow(u, now) {
		return now
	}
	// Walk actual minutes to handle DST gaps/folds. No waits or I/O.
	for next := now.Truncate(time.Minute).Add(time.Minute); next.Before(now.Add(48 * time.Hour)); next = next.Add(time.Minute) {
		if inUpdateWindow(u, next) {
			return next
		}
	}
	return now.Add(24 * time.Hour)
}
