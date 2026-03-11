// mydocker — Docker CLI argument parsing demo using kuu WASM bridge.
// 青山龍星だ！ kuuの実力を見せてやるぜ！
// GoからWASMブリッジ経由でDocker CLIの引数パースを完全実証するサンプルだ！
package main

import (
	"encoding/json"
	"fmt"
	"os"
)

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func run() error {
	// Default: show all demo scenarios
	scenarios := allScenarios()

	if len(os.Args) > 1 && os.Args[1] == "--scenario" {
		if len(os.Args) < 3 {
			return fmt.Errorf("--scenario requires a value")
		}
		name := os.Args[2]
		filtered := []Scenario{}
		for _, s := range scenarios {
			if s.Name == name {
				filtered = append(filtered, s)
			}
		}
		if len(filtered) == 0 {
			return fmt.Errorf("unknown scenario: %q", name)
		}
		scenarios = filtered
	}

	bridge, err := NewKuuBridge()
	if err != nil {
		return fmt.Errorf("failed to start kuu bridge: %w", err)
	}
	defer func() {
		if err := bridge.Close(); err != nil {
			fmt.Fprintf(os.Stderr, "warning: bridge close: %v\n", err)
		}
	}()

	opts := dockerSchema()
	passed, failed := 0, 0
	for _, s := range scenarios {
		schema := &Schema{
			Version:     1,
			Description: "mydocker - A Docker CLI subset built with kuu",
			Opts:        opts,
			Args:        s.Args,
		}
		result, err := bridge.Parse(schema)
		if err != nil {
			fmt.Fprintf(os.Stderr, "FAIL [%s]: bridge error: %v\n", s.Name, err)
			failed++
			continue
		}

		fmt.Printf("=== %s ===\n", s.Name)
		fmt.Printf("  args: %v\n", s.Args)

		if result.HelpRequested {
			fmt.Printf("  [help requested]\n")
			if s.Validate != nil {
				if err := s.Validate(result); err != nil {
					fmt.Printf("  FAIL: %v\n\n", err)
					failed++
					continue
				}
			}
			if s.ExpectHelp {
				fmt.Printf("  PASS\n\n")
				passed++
			} else {
				fmt.Printf("  FAIL: unexpected help\n\n")
				failed++
			}
			continue
		}

		if !result.OK {
			fmt.Printf("  [error] %s\n", result.Error)
			if s.Validate != nil {
				if err := s.Validate(result); err != nil {
					fmt.Printf("  FAIL: %v\n\n", err)
					failed++
					continue
				}
			}
			if s.ExpectError {
				fmt.Printf("  PASS\n\n")
				passed++
			} else {
				fmt.Printf("  FAIL: unexpected error\n\n")
				failed++
			}
			continue
		}

		out, err := json.MarshalIndent(result, "  ", "  ")
		if err != nil {
			fmt.Printf("  FAIL: marshal error: %v\n\n", err)
			failed++
			continue
		}
		fmt.Printf("  result: %s\n", out)

		if s.Validate != nil {
			if err := s.Validate(result); err != nil {
				fmt.Printf("  FAIL: %v\n\n", err)
				failed++
				continue
			}
		}
		fmt.Printf("  PASS\n\n")
		passed++
	}

	fmt.Printf("--- Results: %d passed, %d failed ---\n", passed, failed)
	if failed > 0 {
		return fmt.Errorf("%d scenario(s) failed", failed)
	}
	return nil
}
