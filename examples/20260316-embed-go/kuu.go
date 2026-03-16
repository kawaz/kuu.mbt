// Package main demonstrates the embed+extract+exec pattern for kuu-cli integration.
//
// Architecture:
//
//	Host binary
//	  └── //go:embed kuu-cli  (platform-specific binary embedded at build time)
//	        └── extract to temp on first use
//	              └── exec: stdin JSON → stdout JSON
//
// The DX layer builds OptAST JSON, execs kuu-cli, and unmarshals the result.
// Users interact with a Go-native API — the subprocess is an implementation detail.
package main

import (
	"crypto/sha256"
	"embed"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
)

// binFS holds the embedded kuu-cli binaries.
// In a real build, this would contain platform-specific binaries:
//
//	bin/kuu-cli-linux-amd64
//	bin/kuu-cli-darwin-arm64
//	etc.
//
// For this PoC, we fall back to PATH lookup if no embedded binary is found.
//
//go:embed bin/*
var binFS embed.FS

var (
	resolvedPath string
	resolveOnce  sync.Once
	resolveErr   error
)

// resolveKuuCLI extracts the embedded kuu-cli binary to a cache directory,
// or falls back to PATH lookup. The binary is cached by content hash so
// extraction only happens once per version.
func resolveKuuCLI() (string, error) {
	resolveOnce.Do(func() {
		resolvedPath, resolveErr = doResolve()
	})
	return resolvedPath, resolveErr
}

func doResolve() (string, error) {
	// 1. Try embedded binary for this platform
	binName := fmt.Sprintf("bin/kuu-cli-%s-%s", runtime.GOOS, runtime.GOARCH)
	data, err := binFS.ReadFile(binName)
	if err == nil {
		return extractToCache(data)
	}

	// 2. Fall back to PATH
	path, err := exec.LookPath("kuu-cli")
	if err == nil {
		return path, nil
	}

	return "", fmt.Errorf("kuu-cli not found: no embedded binary for %s/%s and not in PATH", runtime.GOOS, runtime.GOARCH)
}

// extractToCache writes the binary to ~/.cache/kuu/kuu-cli-<hash>,
// skipping if already present.
func extractToCache(data []byte) (string, error) {
	hash := sha256.Sum256(data)
	hexHash := hex.EncodeToString(hash[:8]) // short hash is enough

	cacheDir, err := os.UserCacheDir()
	if err != nil {
		cacheDir = os.TempDir()
	}
	dir := filepath.Join(cacheDir, "kuu")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return "", fmt.Errorf("create cache dir: %w", err)
	}

	binPath := filepath.Join(dir, "kuu-cli-"+hexHash)
	if _, err := os.Stat(binPath); err == nil {
		return binPath, nil // already extracted
	}

	// Atomic write: write to temp, then rename
	tmp, err := os.CreateTemp(dir, "kuu-cli-*.tmp")
	if err != nil {
		return "", fmt.Errorf("create temp: %w", err)
	}
	defer os.Remove(tmp.Name())
	if _, err := tmp.Write(data); err != nil {
		tmp.Close()
		return "", fmt.Errorf("write binary: %w", err)
	}
	tmp.Close()
	if err := os.Chmod(tmp.Name(), 0o755); err != nil {
		return "", fmt.Errorf("chmod: %w", err)
	}
	if err := os.Rename(tmp.Name(), binPath); err != nil {
		return "", fmt.Errorf("rename: %w", err)
	}
	return binPath, nil
}

// --- Schema types (same as WASM bridge JSON protocol v1) ---

type Schema struct {
	Version     int       `json:"version"`
	Description string    `json:"description,omitempty"`
	Opts        []OptDef  `json:"opts"`
	Args        []string  `json:"args"`
	RequireCmd  bool      `json:"require_cmd,omitempty"`
	Exclusive   [][]string `json:"exclusive,omitempty"`
	Required    []string  `json:"required,omitempty"`
}

type OptDef struct {
	Kind          string   `json:"kind"`
	Name          string   `json:"name"`
	Description   string   `json:"description,omitempty"`
	Shorts        string   `json:"shorts,omitempty"`
	Default       any      `json:"default,omitempty"`
	Global        bool     `json:"global,omitempty"`
	Hidden        bool     `json:"hidden,omitempty"`
	Aliases       []string `json:"aliases,omitempty"`
	Choices       []string `json:"choices,omitempty"`
	ImplicitValue any      `json:"implicit_value,omitempty"`
	Opts          []OptDef `json:"opts,omitempty"` // for command/serial
	RequireCmd    bool     `json:"require_cmd,omitempty"`
}

type ParseResult struct {
	OK            bool            `json:"ok"`
	Values        map[string]any  `json:"values,omitempty"`
	Command       *CommandResult  `json:"command,omitempty"`
	Error         string          `json:"error,omitempty"`
	Help          string          `json:"help,omitempty"`
	HelpRequested bool            `json:"help_requested,omitempty"`
}

type CommandResult struct {
	Name    string          `json:"name"`
	Values  map[string]any  `json:"values,omitempty"`
	Command *CommandResult  `json:"command,omitempty"`
}

// --- kuu-cli execution ---

// KuuParse sends a schema+args to kuu-cli and returns the parsed result.
// This is the core of the embed pattern — all the complexity is hidden here.
func KuuParse(schema *Schema) (*ParseResult, error) {
	kuuCLI, err := resolveKuuCLI()
	if err != nil {
		return nil, err
	}

	data, err := json.Marshal(schema)
	if err != nil {
		return nil, fmt.Errorf("marshal schema: %w", err)
	}

	cmd := exec.Command(kuuCLI, "parse")
	cmd.Stdin = strings.NewReader(string(data))
	cmd.Stderr = os.Stderr

	stdout, err := cmd.Output()
	if err != nil {
		// kuu-cli may exit non-zero for parse errors — check if we got JSON
		if exitErr, ok := err.(*exec.ExitError); ok && len(stdout) > 0 {
			_ = exitErr // we have stdout, try parsing it
		} else {
			return nil, fmt.Errorf("exec kuu-cli: %w", err)
		}
	}

	var result ParseResult
	if err := json.Unmarshal(stdout, &result); err != nil {
		return nil, fmt.Errorf("unmarshal result: %w (raw: %s)", err, stdout)
	}
	return &result, nil
}

// --- Convenience: self-re-exec pattern ---

// IsSelfKuuCLI checks if this process was invoked as an embedded kuu-cli.
// Used for the "multicall binary" pattern where the host program can also
// act as kuu-cli when invoked with a special env var.
//
// Usage in main():
//
//	if kuu.IsSelfKuuCLI() {
//	    kuu.RunAsKuuCLI()  // reads stdin, writes stdout, exits
//	}
//	// ... normal app logic
func IsSelfKuuCLI() bool {
	return os.Getenv("KUU_PARSE") == "1"
}

// RunSelfAsKuuCLI re-executes this binary with KUU_PARSE=1 to make it
// act as kuu-cli. This is an alternative to embedding a separate binary —
// the host program IS the kuu-cli.
//
// Requires: the host binary has kuu parsing logic compiled in (e.g., via
// MoonBit native → cgo, or a pure Go re-implementation of kuu core).
//
// For now, this is a placeholder showing the pattern.
func RunSelfAsKuuCLI() error {
	input, err := io.ReadAll(os.Stdin)
	if err != nil {
		return fmt.Errorf("read stdin: %w", err)
	}
	// In a real implementation, this would call the embedded kuu core.
	// For now, return an error indicating the pattern.
	_ = input
	return fmt.Errorf("RunSelfAsKuuCLI: not yet implemented (requires kuu core compiled into host binary)")
}
