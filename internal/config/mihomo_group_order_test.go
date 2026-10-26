package config

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

func TestMihomoGroupOrderConfiguration(t *testing.T) {
	testHome(t)
	path := filepath.Join(Dir(), "config.yaml")
	old, err := Load(path, nil)
	if err != nil || old.Config.Mihomo.GroupOrder == nil || len(old.Config.Mihomo.GroupOrder) != 0 {
		t.Fatalf("old/missing configuration must keep default ordering: %+v / %v", old.Config.Mihomo.GroupOrder, err)
	}
	for _, language := range []string{"en", "zh-CN"} {
		c := Defaults()
		c.Language = language
		data, err := Encode(c)
		if err != nil || !bytes.Contains(data, []byte("group_order: []")) {
			t.Fatalf("%s default config omits empty group_order: %s / %v", language, data, err)
		}
		if language == "en" && !bytes.Contains(data, []byte("Exact group names to show first")) {
			t.Fatal("English group_order explanation missing")
		}
		if language == "zh-CN" && !bytes.Contains(data, []byte("优先显示的策略组完整名称")) {
			t.Fatal("Chinese group_order explanation missing")
		}
		c.Mihomo.GroupOrder = []string{"烟火云", "手动 选择 🚀", "Future group"}
		data, err = Encode(c)
		if err != nil {
			t.Fatal(err)
		}
		if err = WriteAtomic(path, data, 0600); err != nil {
			t.Fatal(err)
		}
		loaded, err := Load(path, nil)
		if err != nil || !reflect.DeepEqual(loaded.Config.Mihomo.GroupOrder, c.Mihomo.GroupOrder) ||
			loaded.Sources["mihomo.group_order"] != "config" {
			t.Fatalf("group_order round trip/source: %+v / %v", loaded, err)
		}
	}
}

func TestMihomoGroupOrderValidation(t *testing.T) {
	testHome(t)
	path := filepath.Join(Dir(), "config.yaml")
	for _, tc := range []struct {
		yaml string
		want string
	}{
		{`[""]`, "nonblank"},
		{`[" \t "]`, "nonblank"},
		{`["\u00a0"]`, "nonblank"},
		{`["烟火云", "烟火云"]`, "duplicate"},
		{`["Group", "other", "Group"]`, "duplicate"},
		{`"烟火云"`, "cannot unmarshal"},
	} {
		if err := WriteAtomic(path, []byte("mihomo:\n  group_order: "+tc.yaml+"\n"), 0600); err != nil {
			t.Fatal(err)
		}
		_, err := Load(path, nil)
		if err == nil || !strings.Contains(err.Error(), tc.want) {
			t.Fatalf("invalid group_order %s accepted: %v", tc.yaml, err)
		}
		if tc.want != "cannot unmarshal" && Translate("zh-CN", err.Error()) == err.Error() {
			t.Fatalf("group_order diagnostic has no Chinese translation: %v", err)
		}
	}
	// Names match exactly: case and surrounding spaces may be significant in
	// an upstream group name. Valid names do not need to exist yet.
	c := Defaults()
	c.Mihomo.GroupOrder = []string{"Group", "group", " Group ", "Unknown future group"}
	if err := Validate(c); err != nil {
		t.Fatal(err)
	}
}

func TestMihomoGroupOrderListsAndInteractiveSelection(t *testing.T) {
	c, fake := setupMihomoController(t, "")
	nodes := []string{"美国01", "美国02", "日本01"}
	fake.proxies = map[string]mihomoProxy{
		"烟火云":    {Name: "烟火云", Type: "Selector", Now: nodes[0], All: append([]string{}, nodes...)},
		"Alpha":  {Name: "Alpha", Type: "Selector", Now: "DIRECT", All: []string{"DIRECT"}},
		"Beta":   {Name: "Beta", Type: "Selector", Now: "DIRECT", All: []string{"DIRECT"}},
		"Zulu":   {Name: "Zulu", Type: "Selector", Now: "DIRECT", All: []string{"DIRECT"}},
		"自动选择":   {Name: "自动选择", Type: "URLTest", Now: nodes[0], All: append([]string{}, nodes...)},
		"GLOBAL": {Name: "GLOBAL", Type: "Selector", Now: "DIRECT", All: []string{"DIRECT", "烟火云"}},
		"leaf":   {Name: "leaf", Type: "Shadowsocks"},
	}
	decodeGroups := func(output []byte, want []string, source string) {
		t.Helper()
		var result struct {
			Groups []mihomoProxy `json:"groups"`
			Source string        `json:"source"`
		}
		if err := json.Unmarshal(output, &result); err != nil {
			t.Fatal(err)
		}
		names := []string{}
		for _, group := range result.Groups {
			names = append(names, group.Name)
			if group.Name == "烟火云" && !reflect.DeepEqual(group.All, nodes) {
				t.Fatalf("node order was changed: %v", group.All)
			}
		}
		if !reflect.DeepEqual(names, want) || result.Source != source {
			t.Fatalf("group order/source = %q/%s, want %q/%s", names, result.Source, want, source)
		}
	}
	var output bytes.Buffer
	if err := mihomoFixtureCommand(c, "nodes", nil, "json", nil, &output, false); err != nil {
		t.Fatal(err)
	}
	decodeGroups(output.Bytes(), []string{"Alpha", "Beta", "GLOBAL", "Zulu", "烟火云", "自动选择"}, "controller")

	c.Mihomo.GroupOrder = []string{"Future group", "leaf", "烟火云", "Zulu", "自动选择", "GLOBAL"}
	output.Reset()
	if err := mihomoFixtureCommand(c, "nodes", nil, "json", nil, &output, false); err != nil {
		t.Fatal(err)
	}
	decodeGroups(output.Bytes(), []string{"烟火云", "Zulu", "自动选择", "GLOBAL", "Alpha", "Beta"}, "controller")
	output.Reset()
	if err := mihomoFixtureCommand(c, "nodes", nil, "text", nil, &output, false); err != nil {
		t.Fatal(err)
	}
	previous := -1
	for _, name := range []string{"烟火云", "Zulu", "自动选择", "GLOBAL", "Alpha", "Beta"} {
		position := strings.Index(output.String(), name+" [")
		if position <= previous {
			t.Fatalf("text list did not preserve group priority at %s: %s", name, output.String())
		}
		previous = position
	}
	output.Reset()
	if err := mihomoFixtureCommand(c, "nodes", []string{"Beta"}, "json", nil, &output, false); err != nil {
		t.Fatal(err)
	}
	decodeGroups(output.Bytes(), []string{"Beta"}, "controller")

	output.Reset()
	if err := mihomoFixtureCommand(c, "select", nil, "text", strings.NewReader("1\n2\n"), &output, true); err != nil {
		t.Fatal(err)
	}
	menu := strings.SplitN(output.String(), "Choose a node", 2)[0]
	for _, entry := range []string{"1. 烟火云\n", "2. Zulu\n", "3. Alpha\n", "4. Beta\n"} {
		if !strings.Contains(menu, entry) {
			t.Fatalf("configured manual menu order missing %q: %s", entry, menu)
		}
	}
	for _, ineligible := range []string{"GLOBAL", "自动选择", "Future group", "leaf"} {
		if strings.Contains(menu, ineligible) {
			t.Fatalf("ineligible priority became a manual group: %s", menu)
		}
	}
	if fake.proxies["烟火云"].Now != "美国02" || !reflect.DeepEqual(fake.proxies["烟火云"].All, nodes) {
		t.Fatalf("priority menu changed node ordering/choice: %+v", fake.proxies["烟火云"])
	}
	state, exists, err := mihomoReadSelections(c)
	if err != nil || !exists || state.Selections["烟火云"] != "美国02" {
		t.Fatalf("configured menu choice was not saved: %+v / %v", state, err)
	}

	// Offline nodes uses the same ordering, without reading the unknown API.
	home, _ := os.UserHomeDir()
	content := `proxy-groups:
  - name: Alpha
    type: select
    proxies: [DIRECT]
  - name: 烟火云
    type: select
    proxies: [美国01, 美国02, 日本01]
  - name: Beta
    type: select
    proxies: [DIRECT]
`
	if err := WriteAtomic(filepath.Join(home, ".config", "mihomo", "config.yaml"), []byte(content), 0600); err != nil {
		t.Fatal(err)
	}
	output.Reset()
	if err := mihomoCommandIO(c, "nodes", nil, "json", nil, &output, false); err != nil {
		t.Fatal(err)
	}
	decodeGroups(output.Bytes(), []string{"烟火云", "Alpha", "Beta"}, "configuration")
}
