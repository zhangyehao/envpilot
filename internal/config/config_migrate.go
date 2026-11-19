package config

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"

	"go.yaml.in/yaml/v3"
)

func yamlField(mapping *yaml.Node, name string) *yaml.Node {
	if mapping == nil || mapping.Kind != yaml.MappingNode {
		return nil
	}
	for i := 0; i < len(mapping.Content); i += 2 {
		if mapping.Content[i].Value == name {
			return mapping.Content[i+1]
		}
	}
	return nil
}

func parsedConfig(data []byte, path string) (Config, error) {
	r := Resolved{Config: Defaults(), Sources: map[string]string{}}
	if err := decodeStored(data, path, &r); err != nil {
		return Config{}, err
	}
	return r.Config, Validate(r.Config)
}

// Migration takes defaults from the stored YAML. A temporary environment override
// must never become a persistent setting when a new release fills missing fields.
func MigrateConfig(r Resolved, apply bool, out io.Writer) error {
	migrate := func() error { return migrateConfig(r, apply, out) }
	if apply && os.Getenv("ENVPILOT_UPDATE_LOCK_HELD") != "1" {
		return WithUpdateLock(migrate)
	}
	return migrate()
}

func migrateConfig(r Resolved, apply bool, out io.Writer) error {
	// Follow a user's config symlink; replacing the link would detach their dotfiles.
	path, err := filepath.EvalSymlinks(r.Path)
	if err != nil {
		return err
	}
	original, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	stored, err := parsedConfig(original, path)
	if err != nil {
		return err
	}
	lang := r.Config.Language
	schema := stored
	schema.Language = lang // selects the annotation language, not the persisted language
	defaults, err := Encode(schema)
	if err != nil {
		return err
	}
	var doc, desired, effective yaml.Node
	if err = yaml.Unmarshal(original, &doc); err != nil {
		return err
	}
	if err = yaml.Unmarshal(defaults, &desired); err != nil {
		return err
	}
	yamlField(desired.Content[0], "language").Value = stored.Language
	effectiveData, err := Encode(r.Config)
	if err != nil {
		return err
	}
	if err = yaml.Unmarshal(effectiveData, &effective); err != nil {
		return err
	}
	var additions []string
	if err = addConfigFields(doc.Content[0], desired.Content[0], "", &additions); err != nil {
		return err
	}
	if len(additions) == 0 {
		fmt.Fprintln(out, Text(lang, "Configuration already contains all fields.", "主配置已包含全部字段。"))
		return nil
	}
	var buf bytes.Buffer
	enc := yaml.NewEncoder(&buf)
	enc.SetIndent(2)
	if err = enc.Encode(&doc); err != nil {
		return err
	}
	if err = enc.Close(); err != nil {
		return err
	}
	after, err := parsedConfig(buf.Bytes(), path)
	if err != nil {
		return err
	}
	beforeBytes, err := Encode(stored)
	if err != nil {
		return err
	}
	afterBytes, err := Encode(after)
	if err != nil {
		return err
	}
	if !bytes.Equal(beforeBytes, afterBytes) {
		return fmt.Errorf("E_MIGRATION: YAML inheritance or references changed the configuration; review the original file")
	}
	for _, key := range additions {
		parts := strings.Split(key, ".")
		lookup := func(node *yaml.Node, keys []string) *yaml.Node {
			for _, part := range keys {
				node = yamlField(node, part)
			}
			return node
		}
		src := r.Sources[key]
		if src == "" {
			src = "default"
		}
		node := lookup(effective.Content[0], parts)
		storedValue := lookup(desired.Content[0], parts)
		if len(parts) == 4 && parts[0] == "updates" && parts[1] == "policies" && node != nil && node.Tag == "!!null" {
			src = "updates." + parts[3]
			node = lookup(effective.Content[0], []string{"updates", parts[3]})
		}
		redact := strings.HasPrefix(key, "codex.api_key.") || strings.HasPrefix(key, "secrets.") || strings.HasPrefix(key, "mihomo.subscription.") || key == "codex.base_url"
		display := func(n *yaml.Node) string {
			if redact || n == nil {
				return "<hidden>"
			}
			var value any
			if n.Decode(&value) != nil {
				return "?"
			}
			b, _ := json.Marshal(value)
			return string(b)
		}
		val, write := display(node), display(storedValue)
		fmt.Fprintf(out, "+ %s = %s (%s)", key, val, src)
		if val != write {
			fmt.Fprintf(out, " [%s %s]", Text(lang, "write", "写入"), write)
		}
		fmt.Fprintln(out)
	}
	if !apply {
		return nil
	}
	snapshot, err := SnapshotCreate(r.Config, []string{r.Path, path})
	if err != nil {
		return err
	}
	current, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	if !bytes.Equal(current, original) {
		return fmt.Errorf("E_CONFIG_CHANGED: configuration changed during migration; run the preview again")
	}
	if err = WriteAtomic(path, buf.Bytes(), 0600); err != nil {
		return err
	}
	fmt.Fprintln(out, Text(lang, "Configuration updated. Snapshot:", "主配置已补齐。恢复快照："), snapshot)
	return nil
}

func addConfigFields(dst, schema *yaml.Node, parent string, added *[]string) error {
	if schema.Kind == yaml.MappingNode && dst.Kind == yaml.AliasNode {
		// Add local keys beside an alias, without editing its shared anchor.
		alias := *dst
		overlay := yaml.Node{Kind: yaml.MappingNode, Tag: "!!map", Content: []*yaml.Node{{Kind: yaml.ScalarNode, Tag: "!!merge", Value: "<<"}, &alias}}
		before := len(*added)
		if err := addConfigFields(&overlay, schema, parent, added); err != nil {
			return err
		}
		if len(*added) != before {
			*dst = overlay
		}
		return nil
	}
	if schema.Kind == yaml.MappingNode && dst.Tag == "!!null" {
		dst.Kind, dst.Tag, dst.Value = yaml.MappingNode, "!!map", ""
	}
	if dst.Kind != yaml.MappingNode || schema.Kind != yaml.MappingNode {
		return nil
	}
	// Resolve merge keys for membership only. Preserve the user's anchors, merge
	// directives and explicitly written values in the document we actually edit.
	var effective map[string]yaml.Node
	if err := dst.Decode(&effective); err != nil {
		return err
	}
	for i := 0; i < len(schema.Content); i += 2 {
		k, v := schema.Content[i], schema.Content[i+1]
		path := k.Value
		if parent != "" {
			path = parent + "." + path
		}
		if existing := yamlField(dst, k.Value); existing != nil {
			if err := addConfigFields(existing, v, path, added); err != nil {
				return err
			}
			continue
		}
		if value, inherited := effective[k.Value]; inherited {
			if v.Kind == yaml.MappingNode {
				before := len(*added)
				if value.Anchor != "" {
					value = yaml.Node{Kind: yaml.AliasNode, Value: value.Anchor, Alias: &yaml.Node{Kind: value.Kind, Tag: value.Tag, Anchor: value.Anchor, Content: value.Content}}
				}
				if err := addConfigFields(&value, v, path, added); err != nil {
					return err
				}
				if len(*added) != before {
					dst.Content = append(dst.Content, k, &value)
				}
			}
			continue
		}
		if v.Kind == yaml.MappingNode && len(v.Content) > 0 {
			empty := &yaml.Node{Kind: yaml.MappingNode, Tag: "!!map"}
			dst.Content = append(dst.Content, k, empty)
			if err := addConfigFields(empty, v, path, added); err != nil {
				return err
			}
		} else {
			dst.Content = append(dst.Content, k, v)
			*added = append(*added, path)
		}
	}
	return nil
}
