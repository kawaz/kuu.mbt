package main

// dockerSchema returns the kuu JSON schema for Docker CLI.
// This mirrors the MoonBit example (examples/20260308-mydocker/main.mbt)
// to verify cross-language schema compatibility.
func dockerSchema() []OptDef {
	return []OptDef{
		// Global options
		{Kind: "count", Name: "verbose", Shorts: "v", Global: true, Description: "Increase verbosity"},
		{Kind: "flag", Name: "debug", Shorts: "D", Global: true, Description: "Enable debug mode"},
		{Kind: "string", Name: "log-level", Default: "info", Shorts: "l", Global: true,
			Description: "Set the logging level", Choices: []string{"debug", "info", "warn", "error", "fatal"}},
		{Kind: "string", Name: "host", Shorts: "H", Global: true, Description: "Daemon socket to connect to"},

		// run
		{Kind: "command", Name: "run", Description: "Create and run a new container", Opts: []OptDef{
			{Kind: "flag", Name: "detach", Shorts: "d", Description: "Run container in background"},
			{Kind: "flag", Name: "interactive", Shorts: "i", Description: "Keep STDIN open"},
			{Kind: "flag", Name: "tty", Shorts: "t", Description: "Allocate a pseudo-TTY"},
			{Kind: "flag", Name: "rm", Description: "Automatically remove container when it exits"},
			{Kind: "string", Name: "name", Description: "Assign a name to the container"},
			{Kind: "append_string", Name: "publish", Shorts: "p", Description: "Publish a container's port(s) to the host"},
			{Kind: "append_string", Name: "volume", Shorts: "V", Description: "Bind mount a volume"},
			{Kind: "append_string", Name: "env", Shorts: "e", Description: "Set environment variables"},
			{Kind: "string", Name: "network", Description: "Connect a container to a network"},
			{Kind: "string", Name: "restart", Default: "no", Description: "Restart policy",
				Choices: []string{"no", "always", "unless-stopped", "on-failure"}},
			// Required: JSON に出力されるが、WASM bridge (src/wasm/main.mbt) は required を未サポート。
			// パーサ側が対応するまで required 制約は検証されない。
			{Kind: "positional", Name: "image", Required: true, Description: "Container image"},
			{Kind: "rest", Name: "command", Description: "Command to run in the container"},
		}},

		// build
		{Kind: "command", Name: "build", Description: "Build an image from a Dockerfile", Opts: []OptDef{
			{Kind: "append_string", Name: "tag", Shorts: "t", Description: "Name and optionally a tag (name:tag)"},
			{Kind: "string", Name: "file", Default: "Dockerfile", Shorts: "f", Description: "Name of the Dockerfile"},
			{Kind: "flag", Name: "no-cache", Description: "Do not use cache when building"},
			{Kind: "flag", Name: "pull", Description: "Always attempt to pull a newer version of the image"},
			{Kind: "append_string", Name: "build-arg", Description: "Set build-time variables"},
			{Kind: "string", Name: "target", Description: "Set the target build stage"},
			{Kind: "string", Name: "platform", Description: "Set platform (e.g. linux/amd64)"},
			{Kind: "positional", Name: "path", Description: "Build context path"},
		}},

		// ps
		{Kind: "command", Name: "ps", Description: "List containers", Opts: []OptDef{
			// Exclusive: JSON に出力されるが、WASM bridge (src/wasm/main.mbt) は exclusive を未サポート。
			// パーサ側が対応するまで排他制約は検証されない。
			{Kind: "flag", Name: "all", Shorts: "a", Exclusive: "ps-view", Description: "Show all containers (default: running only)"},
			{Kind: "flag", Name: "quiet", Shorts: "q", Description: "Only display container IDs"},
			{Kind: "string", Name: "format", Description: "Format output using a Go template"},
			{Kind: "append_string", Name: "filter", Shorts: "f", Description: "Filter output based on conditions"},
			{Kind: "int", Name: "last", Default: 0, Shorts: "n", Exclusive: "ps-view", Description: "Show n last created containers"},
		}},

		// images
		{Kind: "command", Name: "images", Description: "List images", Opts: []OptDef{
			{Kind: "flag", Name: "all", Shorts: "a", Description: "Show all images"},
			{Kind: "flag", Name: "quiet", Shorts: "q", Description: "Only show image IDs"},
			{Kind: "string", Name: "format", Description: "Format output"},
			{Kind: "append_string", Name: "filter", Shorts: "f", Description: "Filter output"},
			{Kind: "positional", Name: "repository", Description: "Repository to filter"},
		}},

		// pull
		{Kind: "command", Name: "pull", Description: "Download an image from a registry", Opts: []OptDef{
			{Kind: "flag", Name: "all-tags", Shorts: "a", Description: "Download all tagged images"},
			{Kind: "string", Name: "platform", Description: "Set platform"},
			{Kind: "flag", Name: "quiet", Shorts: "q", Description: "Suppress verbose output"},
			{Kind: "positional", Name: "image", Required: true, Description: "Image name[:tag|@digest]"},
		}},

		// push
		{Kind: "command", Name: "push", Description: "Upload an image to a registry", Opts: []OptDef{
			{Kind: "flag", Name: "all-tags", Shorts: "a", Description: "Push all tagged images"},
			{Kind: "flag", Name: "quiet", Shorts: "q", Description: "Suppress verbose output"},
			{Kind: "positional", Name: "image", Required: true, Description: "Image name[:tag]"},
		}},

		// exec
		{Kind: "command", Name: "exec", Description: "Execute a command in a running container", Opts: []OptDef{
			{Kind: "flag", Name: "interactive", Shorts: "i", Description: "Keep STDIN open"},
			{Kind: "flag", Name: "tty", Shorts: "t", Description: "Allocate a pseudo-TTY"},
			{Kind: "string", Name: "user", Shorts: "u", Description: "Username or UID"},
			{Kind: "string", Name: "workdir", Shorts: "w", Description: "Working directory inside the container"},
			{Kind: "append_string", Name: "env", Shorts: "e", Description: "Set environment variables"},
			{Kind: "positional", Name: "container", Required: true, Description: "Container ID or name"},
			{Kind: "rest", Name: "command", Description: "Command and arguments"},
		}},

		// compose (nested subcommands)
		{Kind: "command", Name: "compose", Description: "Docker Compose commands", Opts: []OptDef{
			{Kind: "append_string", Name: "file", Shorts: "f", Description: "Compose configuration files"},
			{Kind: "string", Name: "project-name", Shorts: "p", Description: "Project name"},
			{Kind: "string", Name: "env-file", Description: "Environment file path"},

			// compose up
			{Kind: "command", Name: "up", Description: "Create and start containers", Opts: []OptDef{
				{Kind: "flag", Name: "detach", Shorts: "d", Description: "Detached mode"},
				{Kind: "flag", Name: "build", Description: "Build images before starting"},
				{Kind: "flag", Name: "force-recreate", Description: "Recreate containers even if unchanged"},
				{Kind: "flag", Name: "no-deps", Description: "Don't start linked services"},
				{Kind: "int", Name: "scale", Default: 1, Description: "Number of containers for a service"},
				{Kind: "rest", Name: "services", Description: "Services to start"},
			}},

			// compose down
			{Kind: "command", Name: "down", Description: "Stop and remove containers, networks", Opts: []OptDef{
				{Kind: "string", Name: "rmi", Description: "Remove images (all or local)",
					Choices: []string{"all", "local"}},
				{Kind: "flag", Name: "volumes", Shorts: "V", Description: "Remove named volumes"},
				{Kind: "flag", Name: "remove-orphans", Description: "Remove containers for services not in the file"},
			}},

			// compose logs
			{Kind: "command", Name: "logs", Description: "View output from containers", Opts: []OptDef{
				{Kind: "flag", Name: "follow", Shorts: "f", Description: "Follow log output"},
				{Kind: "string", Name: "tail", Default: "all", Description: "Number of lines to show from the end"},
				{Kind: "flag", Name: "timestamps", Shorts: "t", Description: "Show timestamps"},
				{Kind: "rest", Name: "services", Description: "Services to show logs for"},
			}},

			// compose ps
			{Kind: "command", Name: "ps", Description: "List containers", Opts: []OptDef{
				{Kind: "flag", Name: "all", Shorts: "a", Description: "Show all containers"},
				{Kind: "flag", Name: "quiet", Shorts: "q", Description: "Only display IDs"},
				{Kind: "string", Name: "format", Description: "Format output"},
				{Kind: "rest", Name: "services", Description: "Services to filter"},
			}},
		}},

		// network (nested subcommands)
		{Kind: "command", Name: "network", Description: "Manage networks", Opts: []OptDef{
			// network create
			{Kind: "command", Name: "create", Description: "Create a network", Opts: []OptDef{
				{Kind: "string", Name: "driver", Default: "bridge", Shorts: "d", Description: "Driver to manage the network",
					Choices: []string{"bridge", "host", "overlay", "macvlan", "none"}},
				{Kind: "append_string", Name: "subnet", Description: "Subnet in CIDR format"},
				{Kind: "append_string", Name: "gateway", Description: "Gateway for the subnet"},
				{Kind: "flag", Name: "internal", Description: "Restrict external access"},
				{Kind: "append_string", Name: "label", Description: "Set metadata on the network"},
				{Kind: "positional", Name: "name", Required: true, Description: "Network name"},
			}},

			// network ls
			{Kind: "command", Name: "ls", Description: "List networks", Opts: []OptDef{
				{Kind: "string", Name: "format", Description: "Format output"},
				{Kind: "append_string", Name: "filter", Shorts: "f", Description: "Filter output"},
				{Kind: "flag", Name: "quiet", Shorts: "q", Description: "Only display IDs"},
			}},

			// network rm
			{Kind: "command", Name: "rm", Description: "Remove one or more networks", Opts: []OptDef{
				{Kind: "flag", Name: "force", Shorts: "f", Description: "Do not error if network does not exist"},
				{Kind: "rest", Name: "networks", Description: "Network names or IDs"},
			}},

			// network inspect
			{Kind: "command", Name: "inspect", Description: "Display detailed information on networks", Opts: []OptDef{
				{Kind: "string", Name: "format", Shorts: "f", Description: "Format output"},
				{Kind: "rest", Name: "networks", Description: "Network names or IDs"},
			}},
		}},

		// volume (nested subcommands)
		{Kind: "command", Name: "volume", Description: "Manage volumes", Opts: []OptDef{
			// volume create
			{Kind: "command", Name: "create", Description: "Create a volume", Opts: []OptDef{
				{Kind: "string", Name: "driver", Default: "local", Shorts: "d", Description: "Volume driver"},
				{Kind: "append_string", Name: "label", Description: "Set metadata on the volume"},
				{Kind: "append_string", Name: "opt", Shorts: "o", Description: "Set driver specific options"},
				{Kind: "positional", Name: "name", Description: "Volume name"},
			}},

			// volume ls
			{Kind: "command", Name: "ls", Description: "List volumes", Opts: []OptDef{
				{Kind: "string", Name: "format", Description: "Format output"},
				{Kind: "append_string", Name: "filter", Shorts: "f", Description: "Filter output"},
				{Kind: "flag", Name: "quiet", Shorts: "q", Description: "Only display IDs"},
			}},

			// volume rm
			{Kind: "command", Name: "rm", Description: "Remove one or more volumes", Opts: []OptDef{
				{Kind: "flag", Name: "force", Shorts: "f", Description: "Force removal"},
				{Kind: "rest", Name: "volumes", Description: "Volume names"},
			}},

			// volume inspect
			{Kind: "command", Name: "inspect", Description: "Display detailed information on volumes", Opts: []OptDef{
				{Kind: "string", Name: "format", Shorts: "f", Description: "Format output"},
				{Kind: "rest", Name: "volumes", Description: "Volume names"},
			}},
		}},
	}
}
