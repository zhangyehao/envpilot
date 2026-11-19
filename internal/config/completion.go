package config

import (
	"embed"
	"fmt"
	"sort"
	"strings"
)

//go:embed completions/*
var completions embed.FS

func CompletionScript(shell string) (string, error) {
	switch shell {
	case "bash", "zsh", "powershell":
	default:
		return "", fmt.Errorf("choose bash, zsh or powershell")
	}
	b, err := completions.ReadFile("completions/" + shell)
	return string(b), err
}

var commandWords = map[string]string{
	"":       "apply apply-shell codex completion config doctor help init install mihomo plan preflight reset restore resume rollback run self-test self-update setup-command shell snapshot update update-manifests update-mihomo-cache updates upgrade version",
	"config": "edit export migrate show validate", "config migrate": "--preview --yes", "config export": "--portable --codex-preferences",
	"completion": "bash zsh powershell", "init": "--policy", "--policy": "check nightly",
	"codex": "models remote", "codex remote": "disable enable ready reconcile repair restart stage status stop verify warm",
	"codex models": "refresh status", "mihomo": "nodes port ports restart select start status stop test update-subscription",
	"mihomo update-subscription": "--file --network", "--network": "auto direct proxy",
	"shell": "install remove", "updates": "check disable enable history run status", "updates history": "--component --days --json",
	"doctor": "--json", "preflight": "git python --json", "--lang": "auto en zh-CN", "--mode": "offline online",
}

func CommandCandidates(context []string, word string, fuzzy bool) []string {
	if len(word) > 48 || len(context) > 4 {
		return nil
	}
	path := strings.Join(context, " ")
	var list []string
	switch path {
	case "install", "update", "upgrade", "--component":
		list = append([]string{"all"}, Names...)
	default:
		list = strings.Fields(commandWords[path])
	}
	if len(context) > 0 && strings.HasPrefix(context[len(context)-1], "--") {
		list = strings.Fields(commandWords[context[len(context)-1]])
		if context[len(context)-1] == "--component" {
			list = append([]string{"envpilot"}, Names...)
		}
	}
	if strings.HasPrefix(word, "--") && !fuzzy {
		list = append(list, "--config", "--lang", "--help")
	}
	sort.Strings(list)
	var results []string
	for _, s := range list {
		if len(results) > 0 && results[len(results)-1] == s {
			continue
		}
		if (!fuzzy && strings.HasPrefix(s, word)) || (fuzzy && len(word) >= 3 && distance(s, word) <= min(2, len(word)/3)) {
			results = append(results, s)
		}
	}
	if !fuzzy && len(results) == 0 && len(word) >= 3 {
		return CommandCandidates(context, word, true)
	}
	return results
}

// Optimal string alignment distance also recognizes swapped adjacent letters.
func distance(a, b string) int {
	d := make([][]int, len(a)+1)
	for i := range d {
		d[i] = make([]int, len(b)+1)
		d[i][0] = i
	}
	for j := 0; j <= len(b); j++ {
		d[0][j] = j
	}
	for i := 1; i <= len(a); i++ {
		for j := 1; j <= len(b); j++ {
			cost := 1
			if a[i-1] == b[j-1] {
				cost = 0
			}
			d[i][j] = min(d[i-1][j]+1, d[i][j-1]+1, d[i-1][j-1]+cost)
			if i > 1 && j > 1 && a[i-1] == b[j-2] && a[i-2] == b[j-1] {
				d[i][j] = min(d[i][j], d[i-2][j-2]+1)
			}
		}
	}
	return d[len(a)][len(b)]
}
