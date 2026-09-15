package config

import (
	"bufio"
	"crypto/rand"
	"crypto/sha1"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"regexp"
	"time"
)

func ProbeVersion(result map[string]any) (string, error) {
	agent, _ := result["userAgent"].(string)
	match := regexp.MustCompile(`^[^/\s]+/([0-9]+\.[0-9]+\.[0-9]+(?:[-+][A-Za-z0-9.-]+)?)`).FindStringSubmatch(agent)
	if len(match) != 2 {
		return "", fmt.Errorf("server did not identify its version")
	}
	return match[1], nil
}

// Probe verifies JSON-RPC initialize over the app-server Unix WebSocket.
// A listening socket alone is not evidence of a healthy Codex server.
func Probe(socket string) (map[string]any, error) {
	c, err := net.DialTimeout("unix", socket, 2*time.Second)
	if err != nil {
		return nil, err
	}
	defer c.Close()
	_ = c.SetDeadline(time.Now().Add(3 * time.Second))
	keyBytes := make([]byte, 16)
	if _, err = rand.Read(keyBytes); err != nil {
		return nil, err
	}
	key := base64.StdEncoding.EncodeToString(keyBytes)
	if _, err = fmt.Fprintf(c, "GET / HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: %s\r\nSec-WebSocket-Version: 13\r\n\r\n", key); err != nil {
		return nil, err
	}
	r := bufio.NewReader(c)
	resp, err := http.ReadResponse(r, &http.Request{Method: "GET"})
	if err != nil {
		return nil, err
	}
	if resp.StatusCode != 101 {
		return nil, fmt.Errorf("WebSocket upgrade returned %d", resp.StatusCode)
	}
	expected := sha1.Sum([]byte(key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"))
	if resp.Header.Get("Sec-WebSocket-Accept") != base64.StdEncoding.EncodeToString(expected[:]) {
		return nil, fmt.Errorf("invalid WebSocket handshake")
	}
	payload := []byte(`{"id":1,"method":"initialize","params":{"clientInfo":{"name":"envpilot","version":"0.4.0"},"capabilities":{}}}`)
	mask := make([]byte, 4)
	if _, err = rand.Read(mask); err != nil {
		return nil, err
	}
	frame := []byte{0x81, 0x80 | byte(len(payload))}
	if len(payload) >= 126 {
		frame = []byte{0x81, 0x80 | 126, byte(len(payload) >> 8), byte(len(payload))}
	}
	frame = append(frame, mask...)
	for i, b := range payload {
		frame = append(frame, b^mask[i%4])
	}
	if _, err = c.Write(frame); err != nil {
		return nil, err
	}
	for attempt := 0; attempt < 12; attempt++ {
		h := make([]byte, 2)
		if _, err = io.ReadFull(r, h); err != nil {
			return nil, err
		}
		n := uint64(h[1] & 127)
		if n == 126 {
			b := make([]byte, 2)
			if _, err = io.ReadFull(r, b); err != nil {
				return nil, err
			}
			n = uint64(binary.BigEndian.Uint16(b))
		}
		if n == 127 {
			b := make([]byte, 8)
			if _, err = io.ReadFull(r, b); err != nil {
				return nil, err
			}
			n = binary.BigEndian.Uint64(b)
		}
		if n > 1024*1024 {
			return nil, fmt.Errorf("oversized WebSocket message")
		}
		if h[1]&128 != 0 {
			return nil, fmt.Errorf("unexpected masked server frame")
		}
		b := make([]byte, int(n))
		if _, err = io.ReadFull(r, b); err != nil {
			return nil, err
		}
		if h[0]&15 == 8 {
			return nil, fmt.Errorf("server closed before initialization")
		}
		if h[0]&15 != 1 {
			continue
		}
		var message map[string]any
		if err = json.Unmarshal(b, &message); err != nil {
			return nil, err
		}
		if message["id"] != float64(1) {
			continue
		}
		if e, ok := message["error"]; ok {
			return nil, fmt.Errorf("initialize rejected: %v", e)
		}
		result, ok := message["result"].(map[string]any)
		if !ok {
			return nil, fmt.Errorf("invalid initialize result")
		}
		return result, nil
	}
	return nil, fmt.Errorf("initialize response missing")
}
