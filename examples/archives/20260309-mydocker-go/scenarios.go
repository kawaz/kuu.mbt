package main

import (
	"fmt"
	"strings"
)

// Scenario describes a test case for Docker CLI parsing.
type Scenario struct {
	Name        string
	Args        []string
	ExpectHelp  bool
	ExpectError bool
	Validate    func(*ParseResult) error
}

func allScenarios() []Scenario {
	return []Scenario{
		// --- Basic subcommands ---
		{
			Name: "run: basic container",
			Args: []string{"run", "--rm", "-it", "--name", "myapp", "ubuntu:latest", "bash"},
			Validate: func(r *ParseResult) error {
				cmd := r.Command
				if cmd == nil || cmd.Name != "run" {
					return fmt.Errorf("expected command 'run', got %v", cmd)
				}
				if v := cmd.Values["rm"]; v != true {
					return fmt.Errorf("expected rm=true, got %v", v)
				}
				if v := cmd.Values["interactive"]; v != true {
					return fmt.Errorf("expected interactive=true, got %v", v)
				}
				if v := cmd.Values["tty"]; v != true {
					return fmt.Errorf("expected tty=true, got %v", v)
				}
				if v := cmd.Values["name"]; v != "myapp" {
					return fmt.Errorf("expected name=myapp, got %v", v)
				}
				if v := cmd.Values["image"]; v != "ubuntu:latest" {
					return fmt.Errorf("expected image=ubuntu:latest, got %v", v)
				}
				rest, ok := cmd.Values["command"].([]any)
				if !ok || len(rest) != 1 || rest[0] != "bash" {
					return fmt.Errorf("expected command=[bash], got %v", cmd.Values["command"])
				}
				return nil
			},
		},
		{
			Name: "run: with env and ports",
			Args: []string{"run", "-d", "-p", "8080:80", "-p", "443:443",
				"-e", "NODE_ENV=production", "-e", "PORT=80",
				"--network", "mynet", "--restart", "always", "nginx:latest"},
			Validate: func(r *ParseResult) error {
				cmd := r.Command
				if cmd == nil || cmd.Name != "run" {
					return fmt.Errorf("expected command 'run'")
				}
				if v := cmd.Values["detach"]; v != true {
					return fmt.Errorf("expected detach=true")
				}
				ports, ok := cmd.Values["publish"].([]any)
				if !ok || len(ports) != 2 {
					return fmt.Errorf("expected 2 publish ports, got %v", cmd.Values["publish"])
				}
				envs, ok := cmd.Values["env"].([]any)
				if !ok || len(envs) != 2 {
					return fmt.Errorf("expected 2 env vars, got %v", cmd.Values["env"])
				}
				if v := cmd.Values["network"]; v != "mynet" {
					return fmt.Errorf("expected network=mynet, got %v", v)
				}
				if v := cmd.Values["restart"]; v != "always" {
					return fmt.Errorf("expected restart=always, got %v", v)
				}
				if v := cmd.Values["image"]; v != "nginx:latest" {
					return fmt.Errorf("expected image=nginx:latest, got %v", v)
				}
				return nil
			},
		},

		// --- build ---
		{
			Name: "build: with tags and build-args",
			Args: []string{"build", "-t", "myapp:latest", "-t", "myapp:v1.0",
				"--build-arg", "VERSION=1.0", "--file", "Dockerfile.prod",
				"--no-cache", "--platform", "linux/amd64", "."},
			Validate: func(r *ParseResult) error {
				cmd := r.Command
				if cmd == nil || cmd.Name != "build" {
					return fmt.Errorf("expected command 'build'")
				}
				tags, ok := cmd.Values["tag"].([]any)
				if !ok || len(tags) != 2 {
					return fmt.Errorf("expected 2 tags, got %v", cmd.Values["tag"])
				}
				if v := cmd.Values["file"]; v != "Dockerfile.prod" {
					return fmt.Errorf("expected file=Dockerfile.prod, got %v", v)
				}
				if v := cmd.Values["no-cache"]; v != true {
					return fmt.Errorf("expected no-cache=true")
				}
				if v := cmd.Values["path"]; v != "." {
					return fmt.Errorf("expected path=., got %v", v)
				}
				return nil
			},
		},

		// --- ps ---
		{
			Name: "ps: filter and format",
			Args: []string{"ps", "-a", "--filter", "status=running", "--filter", "name=web",
				"--format", "table {{.Names}}\t{{.Status}}"},
			Validate: func(r *ParseResult) error {
				cmd := r.Command
				if cmd == nil || cmd.Name != "ps" {
					return fmt.Errorf("expected command 'ps'")
				}
				if v := cmd.Values["all"]; v != true {
					return fmt.Errorf("expected all=true")
				}
				filters, ok := cmd.Values["filter"].([]any)
				if !ok || len(filters) != 2 {
					return fmt.Errorf("expected 2 filters, got %v", cmd.Values["filter"])
				}
				return nil
			},
		},

		// --- exec ---
		{
			Name: "exec: interactive shell",
			Args: []string{"exec", "-it", "-u", "root", "-w", "/app",
				"-e", "DEBUG=1", "mycontainer", "bash", "-c", "ls -la"},
			Validate: func(r *ParseResult) error {
				cmd := r.Command
				if cmd == nil || cmd.Name != "exec" {
					return fmt.Errorf("expected command 'exec'")
				}
				if v := cmd.Values["interactive"]; v != true {
					return fmt.Errorf("expected interactive=true")
				}
				if v := cmd.Values["tty"]; v != true {
					return fmt.Errorf("expected tty=true")
				}
				if v := cmd.Values["user"]; v != "root" {
					return fmt.Errorf("expected user=root, got %v", v)
				}
				if v := cmd.Values["container"]; v != "mycontainer" {
					return fmt.Errorf("expected container=mycontainer, got %v", v)
				}
				rest, ok := cmd.Values["command"].([]any)
				if !ok || len(rest) != 3 {
					return fmt.Errorf("expected command=[bash -c 'ls -la'], got %v", cmd.Values["command"])
				}
				return nil
			},
		},

		// --- compose (nested) ---
		{
			Name: "compose up: detached with files",
			Args: []string{"compose", "-f", "docker-compose.prod.yml",
				"-f", "docker-compose.override.yml", "up", "--detach", "--scale", "3",
				"web", "db"},
			Validate: func(r *ParseResult) error {
				cmd := r.Command
				if cmd == nil || cmd.Name != "compose" {
					return fmt.Errorf("expected command 'compose'")
				}
				files, ok := cmd.Values["file"].([]any)
				if !ok || len(files) != 2 {
					return fmt.Errorf("expected 2 files, got %v", cmd.Values["file"])
				}
				sub := cmd.Command
				if sub == nil || sub.Name != "up" {
					return fmt.Errorf("expected subcommand 'up', got %v", sub)
				}
				if v := sub.Values["detach"]; v != true {
					return fmt.Errorf("expected detach=true")
				}
				scale, ok := sub.Values["scale"].(float64)
				if !ok || scale != 3 {
					return fmt.Errorf("expected scale=3, got %v", sub.Values["scale"])
				}
				services, ok := sub.Values["services"].([]any)
				if !ok || len(services) != 2 {
					return fmt.Errorf("expected 2 services, got %v", sub.Values["services"])
				}
				return nil
			},
		},
		{
			Name: "compose down: with volumes",
			Args: []string{"compose", "-p", "myproject", "down", "--volumes", "--remove-orphans"},
			Validate: func(r *ParseResult) error {
				cmd := r.Command
				if cmd == nil || cmd.Name != "compose" {
					return fmt.Errorf("expected command 'compose'")
				}
				if v := cmd.Values["project-name"]; v != "myproject" {
					return fmt.Errorf("expected project-name=myproject, got %v", v)
				}
				sub := cmd.Command
				if sub == nil || sub.Name != "down" {
					return fmt.Errorf("expected subcommand 'down'")
				}
				if v := sub.Values["volumes"]; v != true {
					return fmt.Errorf("expected volumes=true")
				}
				if v := sub.Values["remove-orphans"]; v != true {
					return fmt.Errorf("expected remove-orphans=true")
				}
				return nil
			},
		},
		{
			Name: "compose logs: follow with tail",
			Args: []string{"compose", "logs", "-f", "--tail", "100", "--timestamps", "web", "api"},
			Validate: func(r *ParseResult) error {
				cmd := r.Command
				if cmd == nil || cmd.Name != "compose" {
					return fmt.Errorf("expected command 'compose'")
				}
				// compose の file オプションは指定していないので空配列であるべき
				files, ok := cmd.Values["file"].([]any)
				if !ok {
					return fmt.Errorf("expected file to be []any, got %T", cmd.Values["file"])
				}
				if len(files) != 0 {
					return fmt.Errorf("expected file to be empty (not set), got %v", files)
				}
				sub := cmd.Command
				if sub == nil || sub.Name != "logs" {
					return fmt.Errorf("expected subcommand 'logs'")
				}
				if v := sub.Values["follow"]; v != true {
					return fmt.Errorf("expected follow=true")
				}
				if v := sub.Values["tail"]; v != "100" {
					return fmt.Errorf("expected tail=100, got %v", v)
				}
				if v := sub.Values["timestamps"]; v != true {
					return fmt.Errorf("expected timestamps=true")
				}
				services, ok := sub.Values["services"].([]any)
				if !ok || len(services) != 2 {
					return fmt.Errorf("expected 2 services")
				}
				return nil
			},
		},

		// --- network (nested) ---
		{
			Name: "network create: with driver and subnet",
			Args: []string{"network", "create", "--driver", "overlay",
				"--subnet", "10.0.0.0/24", "--subnet", "10.0.1.0/24",
				"--gateway", "10.0.0.1", "--internal", "mynetwork"},
			Validate: func(r *ParseResult) error {
				cmd := r.Command
				if cmd == nil || cmd.Name != "network" {
					return fmt.Errorf("expected command 'network'")
				}
				sub := cmd.Command
				if sub == nil || sub.Name != "create" {
					return fmt.Errorf("expected subcommand 'create'")
				}
				if v := sub.Values["driver"]; v != "overlay" {
					return fmt.Errorf("expected driver=overlay, got %v", v)
				}
				subnets, ok := sub.Values["subnet"].([]any)
				if !ok || len(subnets) != 2 {
					return fmt.Errorf("expected 2 subnets")
				}
				if v := sub.Values["internal"]; v != true {
					return fmt.Errorf("expected internal=true")
				}
				if v := sub.Values["name"]; v != "mynetwork" {
					return fmt.Errorf("expected name=mynetwork, got %v", v)
				}
				return nil
			},
		},
		{
			Name: "network ls: quiet mode",
			Args: []string{"network", "ls", "-q", "--filter", "driver=bridge"},
			Validate: func(r *ParseResult) error {
				cmd := r.Command
				if cmd == nil || cmd.Name != "network" {
					return fmt.Errorf("expected command 'network'")
				}
				sub := cmd.Command
				if sub == nil || sub.Name != "ls" {
					return fmt.Errorf("expected subcommand 'ls'")
				}
				if v := sub.Values["quiet"]; v != true {
					return fmt.Errorf("expected quiet=true")
				}
				return nil
			},
		},

		// --- volume (nested) ---
		{
			Name: "volume create: with driver options",
			Args: []string{"volume", "create", "--driver", "local",
				"--opt", "type=nfs", "--opt", "o=addr=192.168.1.1",
				"--label", "env=prod", "myvolume"},
			Validate: func(r *ParseResult) error {
				cmd := r.Command
				if cmd == nil || cmd.Name != "volume" {
					return fmt.Errorf("expected command 'volume'")
				}
				sub := cmd.Command
				if sub == nil || sub.Name != "create" {
					return fmt.Errorf("expected subcommand 'create'")
				}
				if v := sub.Values["driver"]; v != "local" {
					return fmt.Errorf("expected driver=local, got %v", v)
				}
				opts, ok := sub.Values["opt"].([]any)
				if !ok || len(opts) != 2 {
					return fmt.Errorf("expected 2 opts, got %v", sub.Values["opt"])
				}
				if v := sub.Values["name"]; v != "myvolume" {
					return fmt.Errorf("expected name=myvolume, got %v", v)
				}
				return nil
			},
		},
		{
			Name: "volume rm: force removal",
			Args: []string{"volume", "rm", "-f", "vol1", "vol2", "vol3"},
			Validate: func(r *ParseResult) error {
				cmd := r.Command
				if cmd == nil || cmd.Name != "volume" {
					return fmt.Errorf("expected command 'volume'")
				}
				sub := cmd.Command
				if sub == nil || sub.Name != "rm" {
					return fmt.Errorf("expected subcommand 'rm'")
				}
				if v := sub.Values["force"]; v != true {
					return fmt.Errorf("expected force=true")
				}
				vols, ok := sub.Values["volumes"].([]any)
				if !ok || len(vols) != 3 {
					return fmt.Errorf("expected 3 volumes, got %v", sub.Values["volumes"])
				}
				return nil
			},
		},

		// --- Global options ---
		{
			Name: "global: verbose count with debug",
			Args: []string{"--debug", "-vvv", "--log-level", "debug", "ps"},
			Validate: func(r *ParseResult) error {
				if v := r.Values["debug"]; v != true {
					return fmt.Errorf("expected debug=true")
				}
				verbose, ok := r.Values["verbose"].(float64)
				if !ok || verbose != 3 {
					return fmt.Errorf("expected verbose=3, got %v", r.Values["verbose"])
				}
				if v := r.Values["log-level"]; v != "debug" {
					return fmt.Errorf("expected log-level=debug, got %v", v)
				}
				if r.Command == nil || r.Command.Name != "ps" {
					return fmt.Errorf("expected command 'ps'")
				}
				return nil
			},
		},

		// --- pull / push ---
		{
			Name: "pull: with platform",
			Args: []string{"pull", "--platform", "linux/arm64", "-q", "alpine:3.18"},
			Validate: func(r *ParseResult) error {
				cmd := r.Command
				if cmd == nil || cmd.Name != "pull" {
					return fmt.Errorf("expected command 'pull'")
				}
				if v := cmd.Values["platform"]; v != "linux/arm64" {
					return fmt.Errorf("expected platform=linux/arm64")
				}
				if v := cmd.Values["quiet"]; v != true {
					return fmt.Errorf("expected quiet=true")
				}
				if v := cmd.Values["image"]; v != "alpine:3.18" {
					return fmt.Errorf("expected image=alpine:3.18, got %v", v)
				}
				return nil
			},
		},
		{
			Name: "push: all tags",
			Args: []string{"push", "--all-tags", "myregistry.io/myapp"},
			Validate: func(r *ParseResult) error {
				cmd := r.Command
				if cmd == nil || cmd.Name != "push" {
					return fmt.Errorf("expected command 'push'")
				}
				if v := cmd.Values["all-tags"]; v != true {
					return fmt.Errorf("expected all-tags=true")
				}
				if v := cmd.Values["image"]; v != "myregistry.io/myapp" {
					return fmt.Errorf("expected image=myregistry.io/myapp, got %v", v)
				}
				return nil
			},
		},

		// --- Error cases ---
		{
			Name:        "error: unknown option",
			Args:        []string{"--nonexistent"},
			ExpectError: true,
			Validate: func(r *ParseResult) error {
				if !strings.Contains(r.Error, "nonexistent") {
					return fmt.Errorf("expected error to mention 'nonexistent', got: %s", r.Error)
				}
				return nil
			},
		},
		{
			Name:        "error: invalid choice",
			Args:        []string{"--log-level", "trace", "ps"},
			ExpectError: true,
			Validate: func(r *ParseResult) error {
				if !strings.Contains(r.Error, "must be one of") {
					return fmt.Errorf("expected error to mention 'must be one of', got: %s", r.Error)
				}
				return nil
			},
		},

		{
			Name: "no args: empty invocation",
			Args: []string{},
			Validate: func(r *ParseResult) error {
				// require_cmd がないのでパースは成功する。コマンドなしの挙動を確認。
				if r.Command != nil {
					return fmt.Errorf("expected no command, got %v", r.Command.Name)
				}
				return nil
			},
		},
		{
			Name:        "error: int with string value",
			Args:        []string{"ps", "--last", "abc"},
			ExpectError: true,
			Validate: func(r *ParseResult) error {
				if !strings.Contains(r.Error, "abc") {
					return fmt.Errorf("expected error to mention 'abc', got: %s", r.Error)
				}
				return nil
			},
		},
		{
			Name: "exec: -- separator",
			Args: []string{"exec", "-it", "mycontainer", "--", "ls", "-la", "--help"},
			Validate: func(r *ParseResult) error {
				cmd := r.Command
				if cmd == nil || cmd.Name != "exec" {
					return fmt.Errorf("expected command 'exec'")
				}
				if v := cmd.Values["container"]; v != "mycontainer" {
					return fmt.Errorf("expected container=mycontainer, got %v", v)
				}
				// -- 以降は rest (command) として渡される
				rest, ok := cmd.Values["command"].([]any)
				if !ok {
					return fmt.Errorf("expected command to be []any, got %T", cmd.Values["command"])
				}
				if len(rest) != 3 {
					return fmt.Errorf("expected 3 rest args, got %d: %v", len(rest), rest)
				}
				if rest[0] != "ls" || rest[1] != "-la" || rest[2] != "--help" {
					return fmt.Errorf("expected rest=[ls, -la, --help], got %v", rest)
				}
				return nil
			},
		},

		// --- Help ---
		{
			Name:       "help: root",
			Args:       []string{"--help"},
			ExpectHelp: true,
		},
		{
			Name:       "help: subcommand",
			Args:       []string{"run", "--help"},
			ExpectHelp: true,
		},
	}
}
