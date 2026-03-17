package main

import (
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
	var scenarioFilter string
	for i, arg := range os.Args[1:] {
		if arg == "--scenario" && i+1 < len(os.Args[1:]) {
			scenarioFilter = os.Args[i+2]
		}
	}

	scenarios := allScenarios()
	if scenarioFilter != "" {
		filtered := []Scenario{}
		for _, s := range scenarios {
			if s.Name == scenarioFilter {
				filtered = append(filtered, s)
			}
		}
		if len(filtered) == 0 {
			return fmt.Errorf("unknown scenario: %q", scenarioFilter)
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

	passed, failed := 0, 0
	for _, s := range scenarios {
		schema := &Schema{
			Version:     1,
			Description: "myterraform",
			Opts:        terraformSchema(),
			Args:        s.Args,
			RequireCmd:  true,
		}

		result, err := bridge.Parse(schema)
		if err != nil {
			fmt.Printf("\033[31mFAIL\033[0m %s\n  bridge error: %v\n", s.Name, err)
			failed++
			continue
		}

		if result.HelpRequested {
			if s.ExpectHelp {
				fmt.Printf("\033[32mPASS\033[0m %s (help requested)\n", s.Name)
				passed++
			} else {
				fmt.Printf("\033[31mFAIL\033[0m %s\n  unexpected help request\n", s.Name)
				failed++
			}
			continue
		}

		if !result.OK {
			if s.ExpectError {
				fmt.Printf("\033[32mPASS\033[0m %s (expected error: %s)\n", s.Name, result.Error)
				passed++
			} else {
				fmt.Printf("\033[31mFAIL\033[0m %s\n  parse error: %s\n", s.Name, result.Error)
				failed++
			}
			continue
		}

		if s.ExpectError {
			fmt.Printf("\033[31mFAIL\033[0m %s\n  expected error but parse succeeded\n", s.Name)
			failed++
			continue
		}

		if s.Validate != nil {
			if err := s.Validate(result); err != nil {
				fmt.Printf("\033[31mFAIL\033[0m %s\n  validation: %v\n", s.Name, err)
				failed++
				continue
			}
		}

		fmt.Printf("\033[32mPASS\033[0m %s\n", s.Name)
		passed++
	}

	fmt.Printf("\n--- Results: %d passed, %d failed ---\n", passed, failed)
	if failed > 0 {
		return fmt.Errorf("%d scenario(s) failed", failed)
	}
	return nil
}
