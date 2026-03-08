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
	// Default: show all demo scenarios
	scenarios := allScenarios()

	if len(os.Args) > 1 && os.Args[1] == "--scenario" && len(os.Args) > 2 {
		name := os.Args[2]
		filtered := []Scenario{}
		for _, s := range scenarios {
			if s.Name == name {
				filtered = append(filtered, s)
			}
		}
		if len(filtered) == 0 {
			fmt.Fprintf(os.Stderr, "Unknown scenario: %s\n", name)
			os.Exit(1)
		}
		scenarios = filtered
	}

	bridge, err := NewKuuBridge()
	if err != nil {
		fmt.Fprintf(os.Stderr, "Failed to start kuu bridge: %v\n", err)
		os.Exit(1)
	}
	defer bridge.Close()

	passed, failed := 0, 0
	for _, s := range scenarios {
		schema := &Schema{
			Version:     1,
			Description: "mydocker - A Docker CLI subset built with kuu",
			Opts:        dockerSchema(),
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
			if s.ExpectError {
				fmt.Printf("  PASS\n\n")
				passed++
			} else {
				fmt.Printf("  FAIL: unexpected error\n\n")
				failed++
			}
			continue
		}

		out, _ := json.MarshalIndent(result, "  ", "  ")
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
		os.Exit(1)
	}
}

// Scenario describes a test case for Docker CLI parsing.
type Scenario struct {
	Name        string
	Args        []string
	ExpectHelp  bool
	ExpectError bool
	Validate    func(*ParseResult) error
}
