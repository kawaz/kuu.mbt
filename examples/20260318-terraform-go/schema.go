package main

func terraformSchema() []OptDef {
	return []OptDef{
		{Kind: "string", Name: "chdir", Description: "Switch to a different working directory before executing", Global: true},

		// plan
		{
			Kind:        "command",
			Name:        "plan",
			Description: "Show changes required by the current configuration",
			Opts: append(planCommonOpts(),
				OptDef{Kind: "string", Name: "out", Description: "Write a plan file to the given path"},
				OptDef{Kind: "flag", Name: "destroy", Description: "Select the destroy planning mode"},
				OptDef{Kind: "flag", Name: "refresh-only", Description: "Select the refresh-only planning mode"},
				OptDef{Kind: "flag", Name: "detailed-exitcode", Description: "Return detailed exit codes"},
			),
			Exclusive: [][]string{{"destroy", "replace"}},
		},

		// apply
		{
			Kind:        "command",
			Name:        "apply",
			Description: "Create or update infrastructure",
			Opts: append(applyOpts(),
				OptDef{Kind: "positional", Name: "plan-file"},
			),
		},

		// destroy
		{
			Kind:        "command",
			Name:        "destroy",
			Description: "Destroy previously-created infrastructure",
			Opts:        applyOpts(),
		},

		// init
		{
			Kind:        "command",
			Name:        "init",
			Description: "Prepare your working directory for other commands",
			Opts: []OptDef{
				{Kind: "flag", Name: "upgrade", Description: "Upgrade modules and plugins"},
				{Kind: "append_string", Name: "backend-config", Description: "Backend configuration"},
				{Kind: "flag", Name: "reconfigure", Description: "Reconfigure a backend"},
				{Kind: "flag", Name: "migrate-state", Description: "Reconfigure a backend and attempt to migrate state"},
				{Kind: "string", Name: "plugin-dir", Description: "Directory containing plugin binaries"},
				{Kind: "string", Name: "lockfile", Description: "Set a dependency lockfile mode", Choices: []string{"readonly"}},
				{Kind: "string", Name: "from-module", Description: "Copy contents of the given module into the target directory"},
			},
			Exclusive: [][]string{{"reconfigure", "migrate-state"}},
		},

		// fmt
		{
			Kind:        "command",
			Name:        "fmt",
			Description: "Reformat your configuration in the standard style",
			Opts: []OptDef{
				{Kind: "rest", Name: "target"},
				{Kind: "string", Name: "list", Description: "List files whose formatting differs", Default: "true", ImplicitValue: "true"},
				{Kind: "string", Name: "write", Description: "Write result to source file", Default: "true", ImplicitValue: "true"},
				{Kind: "flag", Name: "diff", Description: "Display diffs of formatting changes"},
				{Kind: "flag", Name: "check", Description: "Check if the input is formatted"},
				{Kind: "flag", Name: "recursive", Description: "Also process files in subdirectories"},
			},
		},

		// workspace
		{
			Kind:        "command",
			Name:        "workspace",
			Description: "Workspace management commands",
			RequireCmd:  true,
			Opts: []OptDef{
				{
					Kind: "command", Name: "new", Description: "Create a new workspace",
					Opts: append([]OptDef{
						{Kind: "positional", Name: "name"},
						{Kind: "string", Name: "state", Description: "Copy an existing state file into the new workspace"},
					}, stateLockOpts()...),
				},
				{Kind: "command", Name: "list", Description: "List workspaces"},
				{Kind: "command", Name: "show", Description: "Show the name of the current workspace"},
				{
					Kind: "command", Name: "select", Description: "Select a workspace",
					Opts: []OptDef{
						{Kind: "positional", Name: "name"},
					},
				},
				{
					Kind: "command", Name: "delete", Description: "Delete a workspace",
					Opts: append([]OptDef{
						{Kind: "positional", Name: "name"},
						{Kind: "flag", Name: "force", Description: "Remove even a non-empty workspace"},
					}, stateLockOpts()...),
				},
			},
		},

		// state
		{
			Kind:        "command",
			Name:        "state",
			Description: "Advanced state management",
			RequireCmd:  true,
			Opts: []OptDef{
				{
					Kind: "command", Name: "list", Description: "List resources in the state",
					Opts: []OptDef{
						{Kind: "string", Name: "state", Description: "Path to a state file"},
						{Kind: "string", Name: "id", Description: "Filter by resource ID"},
					},
				},
				{
					Kind: "command", Name: "show", Description: "Show a resource in the state",
					Opts: []OptDef{
						{Kind: "positional", Name: "address"},
						{Kind: "string", Name: "state", Description: "Path to a state file"},
					},
				},
				{
					Kind: "command", Name: "mv", Description: "Move an item in the state",
					Opts: append([]OptDef{
						{Kind: "positional", Name: "source"},
						{Kind: "positional", Name: "destination"},
						{Kind: "string", Name: "state", Description: "Path to a source state file"},
						{Kind: "string", Name: "state-out", Description: "Path to write the destination state"},
						{Kind: "flag", Name: "dry-run", Description: "Only print out what would be moved"},
					}, stateLockOpts()...),
				},
				{
					Kind: "command", Name: "rm", Description: "Remove instances from the state",
					Opts: append([]OptDef{
						{Kind: "rest", Name: "addresses"},
						{Kind: "string", Name: "state", Description: "Path to a state file"},
						{Kind: "flag", Name: "dry-run", Description: "Only print out what would be removed"},
					}, stateLockOpts()...),
				},
			},
		},

		// output
		{
			Kind:        "command",
			Name:        "output",
			Description: "Show output values from your root module",
			Opts: []OptDef{
				{Kind: "positional", Name: "name"},
				{Kind: "flag", Name: "json", Description: "Machine readable output"},
				{Kind: "flag", Name: "raw", Description: "Raw output for scripting"},
				{Kind: "string", Name: "state", Description: "Path to a state file"},
				{Kind: "flag", Name: "no-color", Description: "Disable color output"},
			},
			Exclusive: [][]string{{"json", "raw"}},
		},
	}
}

// planCommonOpts returns options shared by plan, apply, and destroy.
func planCommonOpts() []OptDef {
	return []OptDef{
		{Kind: "append_string", Name: "var", Description: "Set a Terraform variable"},
		{Kind: "append_string", Name: "var-file", Description: "Set variables from a file"},
		{Kind: "append_string", Name: "target", Description: "Resource to target"},
		{Kind: "append_string", Name: "replace", Description: "Resource to replace"},
		{Kind: "string", Name: "lock", Description: "Don't hold a state lock", Default: "true", ImplicitValue: "true"},
		{Kind: "string", Name: "lock-timeout", Description: "Duration to retry a state lock", Default: "0s"},
		{Kind: "string", Name: "input", Description: "Ask for input for variables", Default: "true", ImplicitValue: "true"},
		{Kind: "flag", Name: "json", Description: "Machine readable output"},
		{Kind: "int", Name: "parallelism", Description: "Limit the number of concurrent operations", Default: 10},
	}
}

// applyOpts returns options for apply and destroy (planCommonOpts + auto-approve).
func applyOpts() []OptDef {
	return append(planCommonOpts(),
		OptDef{Kind: "flag", Name: "auto-approve", Description: "Skip interactive approval of plan"},
	)
}

// stateLockOpts returns lock-related options for state subcommands.
func stateLockOpts() []OptDef {
	return []OptDef{
		{Kind: "string", Name: "lock", Description: "Don't hold a state lock", Default: "true", ImplicitValue: "true"},
		{Kind: "string", Name: "lock-timeout", Description: "Duration to retry a state lock", Default: "0s"},
	}
}
