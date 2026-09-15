package config

import (
	"bytes"
	"encoding/binary"
	"fmt"
	"unicode/utf16"
	"unicode/utf8"
)

func decodeProfile(data []byte) (string, string, error) {
	if bytes.HasPrefix(data, []byte{0xff, 0xfe}) || bytes.HasPrefix(data, []byte{0xfe, 0xff}) {
		if len(data)%2 != 0 {
			return "", "", fmt.Errorf("invalid UTF-16 profile")
		}
		little := data[0] == 0xff
		words := make([]uint16, (len(data)-2)/2)
		for i := range words {
			if little {
				words[i] = binary.LittleEndian.Uint16(data[2+i*2:])
			} else {
				words[i] = binary.BigEndian.Uint16(data[2+i*2:])
			}
		}
		encoding := "utf16be"
		if little {
			encoding = "utf16le"
		}
		return string(utf16.Decode(words)), encoding, nil
	}
	if !utf8.Valid(data) {
		return "", "", fmt.Errorf("E_PROFILE_ENCODING: profile is not UTF-8 or UTF-16; preserve it and convert its encoding before integration")
	}
	return string(bytes.TrimPrefix(data, []byte{0xef, 0xbb, 0xbf})), "utf8bom", nil
}

func encodeProfile(text, encoding string) []byte {
	if encoding == "utf8bom" {
		return append([]byte{0xef, 0xbb, 0xbf}, []byte(text)...)
	}
	if encoding != "utf16le" && encoding != "utf16be" {
		return []byte(text)
	}
	words := utf16.Encode([]rune(text))
	result := make([]byte, 2+len(words)*2)
	if encoding == "utf16le" {
		result[0] = 0xff
		result[1] = 0xfe
	} else {
		result[0] = 0xfe
		result[1] = 0xff
	}
	for i, word := range words {
		if encoding == "utf16le" {
			binary.LittleEndian.PutUint16(result[2+i*2:], word)
		} else {
			binary.BigEndian.PutUint16(result[2+i*2:], word)
		}
	}
	return result
}
