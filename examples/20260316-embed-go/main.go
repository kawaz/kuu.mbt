// embed-poc: embed+extract+exec パターンの実動検証。
//
// /usr/bin/pwd を go:embed で同梱し、展開して実行する。
// 「バイナリを embed して自然に実行できるか」を確認する PoC。
package main

import (
	"crypto/sha256"
	"embed"
	"encoding/hex"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
)

//go:embed bin/*
var binFS embed.FS

func main() {
	// 1. embedded バイナリを読み出す
	name := fmt.Sprintf("bin/embedded-cmd-%s-%s", runtime.GOOS, runtime.GOARCH)
	data, err := binFS.ReadFile(name)
	if err != nil {
		fmt.Fprintf(os.Stderr, "embedded binary not found: %v\n", err)
		os.Exit(1)
	}
	fmt.Printf("[1] embedded binary loaded: %d bytes\n", len(data))

	// 2. キャッシュディレクトリに展開
	path, err := extractToCache(data)
	if err != nil {
		fmt.Fprintf(os.Stderr, "extract failed: %v\n", err)
		os.Exit(1)
	}
	fmt.Printf("[2] extracted to: %s\n", path)

	// 3. 展開したバイナリを exec
	cmd := exec.Command(path)
	out, err := cmd.Output()
	if err != nil {
		fmt.Fprintf(os.Stderr, "exec failed: %v\n", err)
		os.Exit(1)
	}
	fmt.Printf("[3] exec result: %s", out)

	// 4. 2回目: キャッシュヒットの確認
	path2, err := extractToCache(data)
	if err != nil {
		fmt.Fprintf(os.Stderr, "second extract failed: %v\n", err)
		os.Exit(1)
	}
	if path == path2 {
		fmt.Printf("[4] cache hit confirmed (same path)\n")
	} else {
		fmt.Printf("[4] WARNING: cache miss (different path: %s)\n", path2)
	}

	fmt.Println("\n=== embed+extract+exec: OK ===")
}

func extractToCache(data []byte) (string, error) {
	hash := sha256.Sum256(data)
	hexHash := hex.EncodeToString(hash[:8])

	cacheDir, err := os.UserCacheDir()
	if err != nil {
		cacheDir = os.TempDir()
	}
	dir := filepath.Join(cacheDir, "kuu-embed-poc")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return "", fmt.Errorf("mkdir: %w", err)
	}

	binPath := filepath.Join(dir, "cmd-"+hexHash)
	if _, err := os.Stat(binPath); err == nil {
		return binPath, nil // cache hit
	}

	// Atomic write: temp → rename
	tmp, err := os.CreateTemp(dir, "cmd-*.tmp")
	if err != nil {
		return "", fmt.Errorf("tempfile: %w", err)
	}
	defer os.Remove(tmp.Name())
	if _, err := tmp.Write(data); err != nil {
		tmp.Close()
		return "", fmt.Errorf("write: %w", err)
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
