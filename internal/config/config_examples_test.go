package config

import (
	"os"
	"path/filepath"
	"reflect"
	"sort"
	"testing"

	"go.yaml.in/yaml/v3"
)

func TestExamplesListEveryEditableField(t *testing.T) {
	paths := func(data []byte) []string {
		var n yaml.Node
		if err := yaml.Unmarshal(data, &n); err != nil {
			t.Fatal(err)
		}
		fields := map[string]string{}
		sourceFields(&n, "", fields)
		var names []string
		for k := range fields {
			names = append(names, k)
		}
		sort.Strings(names)
		return names
	}
	data, err := Encode(Defaults())
	if err != nil {
		t.Fatal(err)
	}
	expected := paths(data)
	for _, file := range []string{"config.example.en.yaml", "config.example.zh-CN.yaml"} {
		data, err = os.ReadFile(filepath.Join("..", "..", "examples", file))
		if err != nil {
			t.Fatal(err)
		}
		if _, err := parsedConfig(data, file); err != nil {
			t.Fatal(err)
		}
		if actual := paths(data); !reflect.DeepEqual(actual, expected) {
			t.Errorf("%s fields differ from init: %v vs %v", file, actual, expected)
		}
	}
}
