package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"os/exec"
	"sync"
	"time"
)

// KuuBridge wraps the Node.js kuu WASM bridge process.
// It communicates via stdin/stdout using NDJSON protocol.
type KuuBridge struct {
	cmd    *exec.Cmd
	stdin  io.WriteCloser
	reader *bufio.Reader
	mu     sync.Mutex
}

// NewKuuBridge starts the Node.js bridge process.
func NewKuuBridge() (*KuuBridge, error) {
	cmd := exec.Command("node", "kuu_bridge.mjs")
	cmd.Stderr = os.Stderr
	stdin, err := cmd.StdinPipe()
	if err != nil {
		return nil, fmt.Errorf("stdin pipe: %w", err)
	}
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		stdin.Close()
		return nil, fmt.Errorf("stdout pipe: %w", err)
	}
	if err := cmd.Start(); err != nil {
		stdin.Close()
		return nil, fmt.Errorf("start node: %w", err)
	}
	return &KuuBridge{
		cmd:    cmd,
		stdin:  stdin,
		reader: bufio.NewReader(stdout),
	}, nil
}

// Parse sends a schema+args JSON to kuu and returns the parsed result.
func (b *KuuBridge) Parse(schema *Schema) (*ParseResult, error) {
	b.mu.Lock()
	defer b.mu.Unlock()

	data, err := json.Marshal(schema)
	if err != nil {
		return nil, fmt.Errorf("marshal schema: %w", err)
	}
	if _, err := fmt.Fprintf(b.stdin, "%s\n", data); err != nil {
		return nil, fmt.Errorf("write to bridge: %w", err)
	}

	line, err := b.reader.ReadBytes('\n')
	if err != nil {
		return nil, fmt.Errorf("read from bridge: %w", err)
	}

	var result ParseResult
	if err := json.Unmarshal(line, &result); err != nil {
		return nil, fmt.Errorf("unmarshal result: %w", err)
	}
	return &result, nil
}

// Close shuts down the bridge process.
// It closes stdin to signal EOF, then waits up to 5 seconds for the process
// to exit gracefully. If the process does not exit in time, it is killed.
func (b *KuuBridge) Close() error {
	b.stdin.Close()
	done := make(chan error, 1)
	go func() { done <- b.cmd.Wait() }()
	select {
	case err := <-done:
		return err
	case <-time.After(5 * time.Second):
		if err := b.cmd.Process.Kill(); err != nil {
			return fmt.Errorf("bridge process did not exit in time and kill failed: %w", err)
		}
		return <-done // Wait for process cleanup after Kill
	}
}

// Schema represents a kuu WASM bridge input.
type Schema struct {
	Version     int        `json:"version"`
	Description string     `json:"description,omitempty"`
	Opts        []OptDef   `json:"opts"`
	Args        []string   `json:"args"`
	Exclusive   [][]string `json:"exclusive,omitempty"`
	Required    []string   `json:"required,omitempty"`
	RequireCmd  bool       `json:"require_cmd,omitempty"`
}

// OptDef defines a single option in the kuu schema.
type OptDef struct {
	Kind          string     `json:"kind"`
	Name          string     `json:"name"`
	Description   string     `json:"description,omitempty"`
	Shorts        string     `json:"shorts,omitempty"`
	Default       any        `json:"default,omitempty"`
	ImplicitValue any        `json:"implicit_value,omitempty"`
	Global        bool       `json:"global,omitempty"`
	Hidden        bool       `json:"hidden,omitempty"`
	Aliases       []string   `json:"aliases,omitempty"`
	Choices       []string   `json:"choices,omitempty"`
	Opts          []OptDef   `json:"opts,omitempty"`       // for kind="command"
	Exclusive     [][]string `json:"exclusive,omitempty"`  // command-level exclusive groups
	Required      []string   `json:"required,omitempty"`   // command-level required options
	RequireCmd    bool       `json:"require_cmd,omitempty"`
}

// ParseResult represents a kuu parse result.
type ParseResult struct {
	OK            bool           `json:"ok"`
	Values        map[string]any `json:"values,omitempty"`
	Command       *CommandResult `json:"command,omitempty"`
	Error         string         `json:"error,omitempty"`
	Help          string         `json:"help,omitempty"`
	HelpRequested bool           `json:"help_requested,omitempty"`
}

// CommandResult represents a matched subcommand.
type CommandResult struct {
	Name    string             `json:"name"`
	Values  map[string]any     `json:"values,omitempty"`
	Command *CommandResult     `json:"command,omitempty"`
}
