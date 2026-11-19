package config

import (
	"context"
	"encoding/json"
	"fmt"
	"net"
	"path/filepath"
	"regexp"
	"time"

	"github.com/gorilla/websocket"
)

func ProbeVersion(result map[string]any) (string, error) {
	agent, _ := result["userAgent"].(string)
	// Desktop uses a product name containing spaces. Read only the leading
	// product's version, never the trailing client's version in parentheses.
	match := regexp.MustCompile(`^[^/\r\n]+/([0-9]+\.[0-9]+\.[0-9]+(?:[-+][A-Za-z0-9.-]+)?)(?:\s|$)`).FindStringSubmatch(agent)
	if len(match) != 2 {
		return "", fmt.Errorf("server did not identify its version")
	}
	return match[1], nil
}

func ProbeHome(result map[string]any, expected string) error {
	reported, _ := result["codexHome"].(string)
	if reported == "" {
		return fmt.Errorf("server did not identify its Codex home")
	}
	actual, err := filepath.EvalSymlinks(reported)
	if err != nil {
		return fmt.Errorf("could not verify server Codex home: %w", err)
	}
	want, err := filepath.EvalSymlinks(expected)
	if err != nil {
		return err
	}
	actual, _ = filepath.Abs(actual)
	want, _ = filepath.Abs(want)
	if actual != want {
		return fmt.Errorf("server Codex home does not match the selected home")
	}
	return nil
}

// codexRPC uses one connection for initialization and subsequent read-only calls.
// The deadline covers all pages, so an unresponsive or busy server cannot stall cron.
type codexRPC struct {
	conn   *websocket.Conn
	nextID int
	hello  map[string]any
}

func openCodexRPC(socket, home string, timeout time.Duration) (*codexRPC, error) {
	dialer := websocket.Dialer{HandshakeTimeout: 2 * time.Second,
		NetDialContext: func(ctx context.Context, _, _ string) (net.Conn, error) {
			return (&net.Dialer{Timeout: 2 * time.Second}).DialContext(ctx, "unix", socket)
		}}
	conn, _, err := dialer.Dial("ws://localhost/", nil)
	if err != nil {
		return nil, err
	}
	conn.SetReadLimit(8 << 20)
	deadline := time.Now().Add(timeout)
	_ = conn.SetReadDeadline(deadline)
	_ = conn.SetWriteDeadline(deadline)
	rpc := &codexRPC{conn: conn}
	err = rpc.call("initialize", map[string]any{"clientInfo": map[string]string{"name": "envpilot", "version": "1"}, "capabilities": map[string]any{}}, &rpc.hello)
	if err == nil && home != "" {
		err = ProbeHome(rpc.hello, home)
	}
	if err != nil {
		conn.Close()
		return nil, err
	}
	return rpc, nil
}
func (s *codexRPC) initialized() error {
	return s.conn.WriteJSON(map[string]any{"method": "initialized"})
}
func (s *codexRPC) call(method string, params any, result any) error {
	s.nextID++
	if err := s.conn.WriteJSON(map[string]any{"id": s.nextID, "method": method, "params": params}); err != nil {
		return err
	}
	for {
		var response struct {
			ID     *int
			Result json.RawMessage
			Error  json.RawMessage
		}
		if err := s.conn.ReadJSON(&response); err != nil {
			return err
		}
		if response.ID == nil || *response.ID != s.nextID {
			continue
		}
		// Upstream errors may contain arbitrary request/configuration details.
		if len(response.Error) > 0 && string(response.Error) != "null" {
			return fmt.Errorf("Codex rejected %s", method)
		}
		if len(response.Result) == 0 || string(response.Result) == "null" {
			return fmt.Errorf("Codex omitted %s result", method)
		}
		return json.Unmarshal(response.Result, result)
	}
}
func Probe(socket string) (map[string]any, error) {
	s, err := openCodexRPC(socket, "", 3*time.Second)
	if err != nil {
		return nil, err
	}
	defer s.conn.Close()
	return s.hello, nil
}

// Codex keeps idle threads loaded. Check each loaded thread's execution status
// without asking for turns or messages. Fail closed on unknown protocol variants.
func codexActivity(socket, home string) (string, error) {
	s, err := openCodexRPC(socket, home, 10*time.Second)
	if err != nil {
		return "", err
	}
	defer s.conn.Close()
	if err = s.initialized(); err != nil {
		return "", err
	}
	cursor := ""
	for page := 0; page < 100; page++ {
		var list struct {
			Data       *[]string
			NextCursor string
		}
		if err = s.call("thread/loaded/list", map[string]any{"limit": 100, "cursor": optionalCursor(cursor)}, &list); err != nil {
			return "", err
		}
		if list.Data == nil {
			return "", fmt.Errorf("loaded thread list missing")
		}
		for _, id := range *list.Data {
			var read struct {
				Thread struct{ Status struct{ Type string } }
			}
			if err = s.call("thread/read", map[string]any{"threadId": id, "includeTurns": false}, &read); err != nil {
				return "", err
			}
			switch read.Thread.Status.Type {
			case "active":
				return "active", nil
			case "idle", "notLoaded":
			default:
				return "", fmt.Errorf("thread activity could not be established")
			}
		}
		if list.NextCursor == "" {
			return "idle", nil
		}
		if list.NextCursor == cursor {
			break
		}
		cursor = list.NextCursor
	}
	return "", fmt.Errorf("incomplete loaded thread list")
}
func optionalCursor(cursor string) any {
	if cursor == "" {
		return nil
	}
	return cursor
}
func PrintCodexActivity(socket, home string) error {
	if home == "" {
		return fmt.Errorf("expected Codex home is required")
	}
	activity, err := codexActivity(socket, home)
	if err == nil {
		fmt.Println(activity)
	}
	return err
}
