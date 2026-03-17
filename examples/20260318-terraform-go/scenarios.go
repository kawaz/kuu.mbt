package main

import "fmt"

type Scenario struct {
	Name        string
	Args        []string
	ExpectHelp  bool
	ExpectError bool
	Validate    func(*ParseResult) error
}

func expectCmd(r *ParseResult, name string) (*CommandResult, error) {
	if r.Command == nil || r.Command.Name != name {
		actual := "<nil>"
		if r.Command != nil {
			actual = r.Command.Name
		}
		return nil, fmt.Errorf("expected command %q, got %q", name, actual)
	}
	return r.Command, nil
}

func expectSubCmd(cmd *CommandResult, name string) (*CommandResult, error) {
	sub := cmd.Command
	if sub == nil || sub.Name != name {
		actual := "<nil>"
		if sub != nil {
			actual = sub.Name
		}
		return nil, fmt.Errorf("expected subcommand %q, got %q", name, actual)
	}
	return sub, nil
}

func expectValue(values map[string]any, key string, expected any) error {
	got, ok := values[key]
	if !ok {
		return fmt.Errorf("missing value %q", key)
	}
	if ef, ok := expected.(int); ok {
		expected = float64(ef)
	}
	if fmt.Sprintf("%v", got) != fmt.Sprintf("%v", expected) {
		return fmt.Errorf("value %q: expected %v, got %v", key, expected, got)
	}
	return nil
}

func expectStringSlice(values map[string]any, key string, expected []string) error {
	got, ok := values[key].([]any)
	if !ok {
		return fmt.Errorf("value %q: expected []string, got %T", key, values[key])
	}
	if len(got) != len(expected) {
		return fmt.Errorf("value %q: expected %d items, got %d", key, len(expected), len(got))
	}
	for i, v := range got {
		s, ok := v.(string)
		if !ok {
			return fmt.Errorf("value %q[%d]: expected string, got %T", key, i, v)
		}
		if s != expected[i] {
			return fmt.Errorf("value %q[%d]: expected %q, got %q", key, i, expected[i], s)
		}
	}
	return nil
}

func allScenarios() []Scenario {
	return []Scenario{
		// --- plan ---
		{
			Name: "plan: basic with var and target",
			Args: []string{"plan", "--var", "region=us-east-1", "--target", "aws_instance.web"},
			Validate: func(r *ParseResult) error {
				cmd, err := expectCmd(r, "plan")
				if err != nil {
					return err
				}
				if err := expectStringSlice(cmd.Values, "var", []string{"region=us-east-1"}); err != nil {
					return err
				}
				return expectStringSlice(cmd.Values, "target", []string{"aws_instance.web"})
			},
		},
		{
			Name: "plan: multiple vars and var-files",
			Args: []string{"plan", "--var", "region=us-east-1", "--var", "env=prod", "--var-file", "base.tfvars", "--var-file", "prod.tfvars"},
			Validate: func(r *ParseResult) error {
				cmd, err := expectCmd(r, "plan")
				if err != nil {
					return err
				}
				if err := expectStringSlice(cmd.Values, "var", []string{"region=us-east-1", "env=prod"}); err != nil {
					return err
				}
				return expectStringSlice(cmd.Values, "var-file", []string{"base.tfvars", "prod.tfvars"})
			},
		},
		{
			Name: "plan: output to file with lock disabled",
			Args: []string{"plan", "--out", "plan.tfplan", "--lock=false"},
			Validate: func(r *ParseResult) error {
				cmd, err := expectCmd(r, "plan")
				if err != nil {
					return err
				}
				if err := expectValue(cmd.Values, "out", "plan.tfplan"); err != nil {
					return err
				}
				return expectValue(cmd.Values, "lock", "false")
			},
		},
		{
			Name: "plan: destroy mode",
			Args: []string{"plan", "--destroy"},
			Validate: func(r *ParseResult) error {
				cmd, err := expectCmd(r, "plan")
				if err != nil {
					return err
				}
				return expectValue(cmd.Values, "destroy", true)
			},
		},
		{
			Name: "plan: refresh-only mode",
			Args: []string{"plan", "--refresh-only"},
			Validate: func(r *ParseResult) error {
				cmd, err := expectCmd(r, "plan")
				if err != nil {
					return err
				}
				return expectValue(cmd.Values, "refresh-only", true)
			},
		},

		// --- apply ---
		{
			Name: "apply: with plan file",
			Args: []string{"apply", "saved.tfplan"},
			Validate: func(r *ParseResult) error {
				cmd, err := expectCmd(r, "apply")
				if err != nil {
					return err
				}
				return expectValue(cmd.Values, "plan-file", "saved.tfplan")
			},
		},
		{
			Name: "apply: auto-approve with vars",
			Args: []string{"apply", "--auto-approve", "--var", "region=us-east-1"},
			Validate: func(r *ParseResult) error {
				cmd, err := expectCmd(r, "apply")
				if err != nil {
					return err
				}
				if err := expectValue(cmd.Values, "auto-approve", true); err != nil {
					return err
				}
				return expectStringSlice(cmd.Values, "var", []string{"region=us-east-1"})
			},
		},
		{
			Name: "apply: json output mode",
			Args: []string{"apply", "--auto-approve", "--json"},
			Validate: func(r *ParseResult) error {
				cmd, err := expectCmd(r, "apply")
				if err != nil {
					return err
				}
				if err := expectValue(cmd.Values, "json", true); err != nil {
					return err
				}
				return expectValue(cmd.Values, "auto-approve", true)
			},
		},

		// --- destroy ---
		{
			Name: "destroy: basic",
			Args: []string{"destroy", "--auto-approve"},
			Validate: func(r *ParseResult) error {
				cmd, err := expectCmd(r, "destroy")
				if err != nil {
					return err
				}
				return expectValue(cmd.Values, "auto-approve", true)
			},
		},
		{
			Name: "destroy: with target",
			Args: []string{"destroy", "--auto-approve", "--target", "aws_instance.web"},
			Validate: func(r *ParseResult) error {
				cmd, err := expectCmd(r, "destroy")
				if err != nil {
					return err
				}
				if err := expectValue(cmd.Values, "auto-approve", true); err != nil {
					return err
				}
				return expectStringSlice(cmd.Values, "target", []string{"aws_instance.web"})
			},
		},

		// --- init ---
		{
			Name: "init: upgrade with backend config",
			Args: []string{"init", "--upgrade", "--backend-config", "key=value", "--backend-config", "path=config.tf"},
			Validate: func(r *ParseResult) error {
				cmd, err := expectCmd(r, "init")
				if err != nil {
					return err
				}
				if err := expectValue(cmd.Values, "upgrade", true); err != nil {
					return err
				}
				return expectStringSlice(cmd.Values, "backend-config", []string{"key=value", "path=config.tf"})
			},
		},
		{
			Name: "init: reconfigure",
			Args: []string{"init", "--reconfigure"},
			Validate: func(r *ParseResult) error {
				cmd, err := expectCmd(r, "init")
				if err != nil {
					return err
				}
				return expectValue(cmd.Values, "reconfigure", true)
			},
		},
		{
			Name:        "init: reconfigure and migrate-state exclusive",
			Args:        []string{"init", "--reconfigure", "--migrate-state"},
			ExpectError: true,
		},

		// --- fmt ---
		{
			Name: "fmt: check mode",
			Args: []string{"fmt", "--check", "--diff"},
			Validate: func(r *ParseResult) error {
				cmd, err := expectCmd(r, "fmt")
				if err != nil {
					return err
				}
				if err := expectValue(cmd.Values, "check", true); err != nil {
					return err
				}
				return expectValue(cmd.Values, "diff", true)
			},
		},
		{
			Name: "fmt: multiple targets",
			Args: []string{"fmt", "--recursive", "modules/", "environments/"},
			Validate: func(r *ParseResult) error {
				cmd, err := expectCmd(r, "fmt")
				if err != nil {
					return err
				}
				if err := expectValue(cmd.Values, "recursive", true); err != nil {
					return err
				}
				return expectStringSlice(cmd.Values, "target", []string{"modules/", "environments/"})
			},
		},
		{
			Name: "fmt: list=false write=false",
			Args: []string{"fmt", "--list=false", "--write=false"},
			Validate: func(r *ParseResult) error {
				cmd, err := expectCmd(r, "fmt")
				if err != nil {
					return err
				}
				if err := expectValue(cmd.Values, "list", "false"); err != nil {
					return err
				}
				return expectValue(cmd.Values, "write", "false")
			},
		},

		// --- workspace ---
		{
			Name: "workspace new: create workspace",
			Args: []string{"workspace", "new", "staging"},
			Validate: func(r *ParseResult) error {
				cmd, err := expectCmd(r, "workspace")
				if err != nil {
					return err
				}
				sub, err := expectSubCmd(cmd, "new")
				if err != nil {
					return err
				}
				return expectValue(sub.Values, "name", "staging")
			},
		},
		{
			Name: "workspace list",
			Args: []string{"workspace", "list"},
			Validate: func(r *ParseResult) error {
				cmd, err := expectCmd(r, "workspace")
				if err != nil {
					return err
				}
				_, err = expectSubCmd(cmd, "list")
				return err
			},
		},
		{
			Name: "workspace select: switch workspace",
			Args: []string{"workspace", "select", "production"},
			Validate: func(r *ParseResult) error {
				cmd, err := expectCmd(r, "workspace")
				if err != nil {
					return err
				}
				sub, err := expectSubCmd(cmd, "select")
				if err != nil {
					return err
				}
				return expectValue(sub.Values, "name", "production")
			},
		},
		{
			Name: "workspace delete: force",
			Args: []string{"workspace", "delete", "--force", "old-workspace"},
			Validate: func(r *ParseResult) error {
				cmd, err := expectCmd(r, "workspace")
				if err != nil {
					return err
				}
				sub, err := expectSubCmd(cmd, "delete")
				if err != nil {
					return err
				}
				if err := expectValue(sub.Values, "force", true); err != nil {
					return err
				}
				return expectValue(sub.Values, "name", "old-workspace")
			},
		},

		// --- state ---
		{
			Name: "state list: with id filter",
			Args: []string{"state", "list", "--state", "terraform.tfstate", "--id", "i-abc123"},
			Validate: func(r *ParseResult) error {
				cmd, err := expectCmd(r, "state")
				if err != nil {
					return err
				}
				sub, err := expectSubCmd(cmd, "list")
				if err != nil {
					return err
				}
				if err := expectValue(sub.Values, "state", "terraform.tfstate"); err != nil {
					return err
				}
				return expectValue(sub.Values, "id", "i-abc123")
			},
		},
		{
			Name: "state mv: move resource",
			Args: []string{"state", "mv", "aws_instance.old", "aws_instance.new"},
			Validate: func(r *ParseResult) error {
				cmd, err := expectCmd(r, "state")
				if err != nil {
					return err
				}
				sub, err := expectSubCmd(cmd, "mv")
				if err != nil {
					return err
				}
				if err := expectValue(sub.Values, "source", "aws_instance.old"); err != nil {
					return err
				}
				return expectValue(sub.Values, "destination", "aws_instance.new")
			},
		},
		{
			Name: "state rm: dry-run",
			Args: []string{"state", "rm", "--dry-run", "aws_instance.web", "aws_instance.db"},
			Validate: func(r *ParseResult) error {
				cmd, err := expectCmd(r, "state")
				if err != nil {
					return err
				}
				sub, err := expectSubCmd(cmd, "rm")
				if err != nil {
					return err
				}
				if err := expectValue(sub.Values, "dry-run", true); err != nil {
					return err
				}
				return expectStringSlice(sub.Values, "addresses", []string{"aws_instance.web", "aws_instance.db"})
			},
		},

		// --- output ---
		{
			Name: "output: json format",
			Args: []string{"output", "--json"},
			Validate: func(r *ParseResult) error {
				cmd, err := expectCmd(r, "output")
				if err != nil {
					return err
				}
				return expectValue(cmd.Values, "json", true)
			},
		},
		{
			Name: "output: specific name raw",
			Args: []string{"output", "--raw", "my_output"},
			Validate: func(r *ParseResult) error {
				cmd, err := expectCmd(r, "output")
				if err != nil {
					return err
				}
				if err := expectValue(cmd.Values, "name", "my_output"); err != nil {
					return err
				}
				return expectValue(cmd.Values, "raw", true)
			},
		},

		// --- global / misc ---
		{
			Name: "global: chdir option",
			Args: []string{"--chdir=environments/prod", "plan", "--var", "env=prod"},
			Validate: func(r *ParseResult) error {
				if err := expectValue(r.Values, "chdir", "environments/prod"); err != nil {
					return err
				}
				cmd, err := expectCmd(r, "plan")
				if err != nil {
					return err
				}
				return expectStringSlice(cmd.Values, "var", []string{"env=prod"})
			},
		},
		{
			Name:       "help: plan help",
			Args:       []string{"plan", "--help"},
			ExpectHelp: true,
		},
		{
			Name:        "error: unknown option",
			Args:        []string{"plan", "--unknown-option"},
			ExpectError: true,
		},
		{
			Name:        "error: plan destroy and replace exclusive",
			Args:        []string{"plan", "--destroy", "--replace", "aws_instance.web"},
			ExpectError: true,
		},
		{
			Name:        "error: output json and raw exclusive",
			Args:        []string{"output", "--json", "--raw"},
			ExpectError: true,
		},
	}
}
