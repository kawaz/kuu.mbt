// embed-poc: kuu-cli embed+extract+exec pattern demonstration.
//
// Shows how a Go program can embed the kuu-cli binary and use it for
// CLI argument parsing without requiring Node.js or any runtime dependency.
//
// The kuu-cli binary is embedded via //go:embed and extracted to a cache
// directory on first use. Subsequent runs reuse the cached binary.
//
// Usage:
//   go run . --verbose --host example.com serve --port 3000
//   go run . --help
//   go run . clone --depth 1 https://github.com/user/repo
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
	// Self-re-exec check (multicall binary pattern)
	if IsSelfKuuCLI() {
		return RunSelfAsKuuCLI()
	}

	schema := &Schema{
		Version:     1,
		Description: "embed-poc - kuu-cli embed pattern demo",
		Opts: []OptDef{
			{Kind: "count", Name: "verbose", Shorts: "v", Global: true, Description: "Increase verbosity"},
			{Kind: "string", Name: "host", Default: "localhost", Description: "Server host"},
			{Kind: "command", Name: "serve", Description: "Start server", Opts: []OptDef{
				{Kind: "int", Name: "port", Default: 8080, Description: "Port number"},
				{Kind: "flag", Name: "tls", Description: "Enable TLS"},
			}},
			{Kind: "command", Name: "clone", Description: "Clone a repository", Opts: []OptDef{
				{Kind: "int", Name: "depth", Default: 0, Description: "Shallow clone depth"},
				{Kind: "positional", Name: "url", Description: "Repository URL"},
			}},
		},
		Args: os.Args[1:],
	}

	result, err := KuuParse(schema)
	if err != nil {
		return fmt.Errorf("kuu parse: %w", err)
	}

	if result.HelpRequested {
		fmt.Println(result.Help)
		return nil
	}

	if !result.OK {
		fmt.Fprintf(os.Stderr, "error: %s\n", result.Error)
		if result.Help != "" {
			fmt.Fprintln(os.Stderr, result.Help)
		}
		os.Exit(1)
	}

	out, _ := json.MarshalIndent(result, "", "  ")
	fmt.Println(string(out))
	return nil
}
