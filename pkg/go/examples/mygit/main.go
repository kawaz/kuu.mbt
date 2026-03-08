// Package main demonstrates a git-like CLI built with the kuu Go API.
// This is a design mock — it does not compile, but illustrates the intended
// developer experience for Go users of the kuu CLI parser.
package main

import (
	"context"
	"fmt"
	"os"

	"github.com/kawaz/kuu/pkg/go/kuu"
)

// ─── Root command ─────────────────────────────────────────

type RootCmd struct {
	// _ struct{} タグでパーサレベルの設定を記述
	_ struct{} `kuu:",require_cmd,desc=mygit - A sample git-like CLI built with kuu"`

	// グローバルオプション
	Verbose int    `kuu:"--verbose,-v,count,global,desc=Increase verbosity (-v/-vv/-vvv),no-reset"`
	Quiet   bool   `kuu:"--quiet,-q,global,desc=Suppress output,exclusive=verbosity"`
	Color   string `kuu:"--color,global,default=auto,choices=always|never|auto,implicit=always,desc=When to use colors"`
	Debug   bool   `kuu:"--debug-internal,global,hidden,desc=Internal debug flag"`

	// サブコマンド (ポインタ型: nil = 未選択)
	Clone    *CloneCmd    `kuu:"clone,cmd,desc=Clone a repository"`
	Commit   *CommitCmd   `kuu:"commit,cmd,desc=Record changes"`
	Log      *LogCmd      `kuu:"log,cmd,desc=Show commit logs"`
	Add      *AddCmd      `kuu:"add,cmd,desc=Add file contents to the index"`
	Push     *PushCmd     `kuu:"push,cmd,desc=Update remote refs"`
	Pull     *PullCmd     `kuu:"pull,cmd,desc=Fetch and merge"`
	Branch   *BranchCmd   `kuu:"branch,cmd,desc=List/create/delete branches"`
	Checkout *CheckoutCmd `kuu:"checkout,cmd,desc=Switch branches or restore files"`
	Diff     *DiffCmd     `kuu:"diff,cmd,desc=Show changes between commits"`
	Status   *StatusCmd   `kuu:"status,cmd,desc=Show working tree status"`
	Tag      *TagCmd      `kuu:"tag,cmd,desc=Create/list/delete/verify tags"`
	Remote   *RemoteCmd   `kuu:"remote,cmd,desc=Manage tracked repositories"`
	Stash    *StashCmd    `kuu:"stash,cmd,desc=Stash changes"`
	Config   *ConfigCmd   `kuu:"config,cmd,desc=Get and set options"`
}

// ─── clone ────────────────────────────────────────────────

type CloneCmd struct {
	_ struct{} `kuu:",desc=mygit clone - Clone a repository"`

	URL       string `kuu:"url,pos,required,desc=Repository URL"`
	Directory string `kuu:"directory,pos,desc=Target directory"`
	Depth     int    `kuu:"--depth,default=0,value=N,desc=Shallow clone with N commits"`
	Branch    string `kuu:"--branch,-b,value=BRANCH,desc=Checkout this branch"`
	Bare      bool   `kuu:"--bare,desc=Create a bare repository"`
}

func (c *CloneCmd) Name() string        { return "clone" }
func (c *CloneCmd) Description() string { return "Clone a repository" }
func (c *CloneCmd) Run(ctx context.Context) error {
	fmt.Printf("Cloning %s", c.URL)
	if c.Directory != "" {
		fmt.Printf(" into %s", c.Directory)
	}
	fmt.Println()
	if c.Depth > 0 {
		fmt.Printf("  depth: %d\n", c.Depth)
	}
	if c.Branch != "" {
		fmt.Printf("  branch: %s\n", c.Branch)
	}
	if c.Bare {
		fmt.Println("  bare: true")
	}
	return nil
}

// ─── commit ───────────────────────────────────────────────

type CommitCmd struct {
	_ struct{} `kuu:",desc=mygit commit - Record changes"`

	Message    string `kuu:"--message,-m,required,value=MSG,desc=Commit message"`
	All        bool   `kuu:"--all,-a,desc=Stage all modified files"`
	Amend      bool   `kuu:"--amend,desc=Amend the previous commit"`
	Verify     bool   `kuu:"--verify,default=true,no-false,desc=Run pre-commit hooks (--no-verify to skip)"`
	ResetAutor bool   `kuu:"--author-date-is-committer-date,no-unset,desc=Override author date"`
}

func (c *CommitCmd) Name() string        { return "commit" }
func (c *CommitCmd) Description() string { return "Record changes" }
func (c *CommitCmd) Run(ctx context.Context) error {
	fmt.Printf("Committing: %s\n", c.Message)
	return nil
}

// ─── log ──────────────────────────────────────────────────

type LogCmd struct {
	_ struct{} `kuu:",desc=mygit log - Show commit logs"`

	Oneline  bool     `kuu:"--oneline,desc=One line per commit"`
	MaxCount int      `kuu:"--max-count,-n,default=0,value=N,desc=Limit number of commits"`
	Authors  []string `kuu:"--author,append,value=PATTERN,desc=Filter by author (repeatable)"`
	Format   string   `kuu:"--format,default=medium,choices=oneline|short|medium|full|fuller|reference|raw,desc=Pretty-print format"`
	Graph    bool     `kuu:"--graph,desc=Draw text-based graph"`
	Paths    []string `kuu:"paths,rest,desc=Limit to paths"`
}

func (c *LogCmd) Name() string        { return "log" }
func (c *LogCmd) Description() string { return "Show commit logs" }
func (c *LogCmd) Run(ctx context.Context) error {
	fmt.Println("Showing log")
	return nil
}

// ─── add ──────────────────────────────────────────────────

type AddCmd struct {
	_ struct{} `kuu:",desc=mygit add - Stage files"`

	Force  bool     `kuu:"--force,-f,desc=Allow ignored files"`
	DryRun bool     `kuu:"--dry-run,alias=dryrun,desc=Don't actually add files"`
	Patch  bool     `kuu:"--patch,-p,desc=Interactively stage hunks"`
	Files  []string `kuu:"files,rest,desc=Files to add"`
}

func (c *AddCmd) Name() string        { return "add" }
func (c *AddCmd) Description() string { return "Add file contents to the index" }
func (c *AddCmd) Run(ctx context.Context) error {
	fmt.Printf("Adding files: %v\n", c.Files)
	return nil
}

// ─── push ─────────────────────────────────────────────────

type PushCmd struct {
	_ struct{} `kuu:",desc=mygit push - Push to remote"`

	Remote         string `kuu:"remote,pos,desc=Remote name"`
	Branch         string `kuu:"branch,pos,desc=Branch name"`
	Force          bool   `kuu:"--force,-f,exclusive=push-force,desc=Force push"`
	ForceWithLease bool   `kuu:"--force-with-lease,exclusive=push-force,desc=Safer force push"`
	Tags           bool   `kuu:"--tags,desc=Push all tags"`
	SetUpstream    bool   `kuu:"--set-upstream,-u,desc=Set upstream for the branch"`
	Delete         bool   `kuu:"--delete,-d,desc=Delete remote branch"`
}

func (c *PushCmd) Name() string        { return "push" }
func (c *PushCmd) Description() string { return "Update remote refs" }
func (c *PushCmd) Run(ctx context.Context) error {
	fmt.Printf("Pushing to %s/%s\n", c.Remote, c.Branch)
	return nil
}

// ─── pull ─────────────────────────────────────────────────

type PullCmd struct {
	_ struct{} `kuu:",desc=mygit pull - Fetch and integrate"`

	Remote string `kuu:"remote,pos,desc=Remote name"`
	Branch string `kuu:"branch,pos,desc=Branch name"`
	Rebase bool   `kuu:"--rebase,-r,exclusive=pull-mode,desc=Rebase instead of merge"`
	FFOnly bool   `kuu:"--ff-only,exclusive=pull-mode,desc=Only fast-forward merges"`
}

func (c *PullCmd) Name() string        { return "pull" }
func (c *PullCmd) Description() string { return "Fetch and merge" }
func (c *PullCmd) Run(ctx context.Context) error {
	fmt.Println("Pulling")
	return nil
}

// ─── branch ───────────────────────────────────────────────

type BranchCmd struct {
	_ struct{} `kuu:",desc=mygit branch - Branch management"`

	Name        string `kuu:"name,pos,desc=Branch name"`
	Delete      bool   `kuu:"--delete,-d,exclusive=branch-delete,desc=Delete a branch"`
	ForceDelete bool   `kuu:"--force-delete,alias=D,exclusive=branch-delete,desc=Force delete"`
	List        bool   `kuu:"--list,-l,desc=List branches"`
	All         bool   `kuu:"--all,-a,desc=Show both local and remote"`
	Move        bool   `kuu:"--move,-m,desc=Move/rename a branch"`
}

func (c *BranchCmd) Name() string        { return "branch" }
func (c *BranchCmd) Description() string { return "List, create, or delete branches" }
func (c *BranchCmd) Run(ctx context.Context) error {
	fmt.Println("Branch operation")
	return nil
}

// ─── checkout ─────────────────────────────────────────────

type CheckoutCmd struct {
	_ struct{} `kuu:",desc=mygit checkout - Switch branches or restore files"`

	Target string   `kuu:"branch,pos,desc=Branch or commit to checkout"`
	Create string   `kuu:"--create,-b,value=BRANCH,desc=Create and checkout a new branch"`
	Force  bool     `kuu:"--force,-f,desc=Force checkout"`
	Files  []string `kuu:",dashdash,desc=Files to checkout"`
}

func (c *CheckoutCmd) Name() string        { return "checkout" }
func (c *CheckoutCmd) Description() string { return "Switch branches or restore files" }
func (c *CheckoutCmd) Run(ctx context.Context) error {
	fmt.Printf("Checkout: %s\n", c.Target)
	return nil
}

// ─── diff ─────────────────────────────────────────────────

type DiffCmd struct {
	_ struct{} `kuu:",desc=mygit diff - Show differences"`

	Staged   bool     `kuu:"--staged,alias=cached,desc=Show staged changes"`
	Stat     bool     `kuu:"--stat,desc=Show diffstat only"`
	Context  int      `kuu:"--unified,-U,default=3,value=N,implicit=3,desc=Lines of context"`
	NameOnly bool     `kuu:"--name-only,desc=Show only names of changed files"`
	Paths    []string `kuu:"paths,rest,desc=Limit to paths"`
}

func (c *DiffCmd) Name() string        { return "diff" }
func (c *DiffCmd) Description() string { return "Show changes between commits" }
func (c *DiffCmd) Run(ctx context.Context) error {
	fmt.Println("Showing diff")
	return nil
}

// ─── status ───────────────────────────────────────────────

type StatusCmd struct {
	_ struct{} `kuu:",desc=mygit status - Show status"`

	Short     bool `kuu:"--short,-s,desc=Short format output"`
	Branch    bool `kuu:"--branch,-b,desc=Show branch info"`
	Porcelain bool `kuu:"--porcelain,desc=Machine-readable output"`
}

func (c *StatusCmd) Name() string        { return "status" }
func (c *StatusCmd) Description() string { return "Show working tree status" }
func (c *StatusCmd) Run(ctx context.Context) error {
	fmt.Println("Showing status")
	return nil
}

// ─── tag ──────────────────────────────────────────────────

type TagCmd struct {
	_ struct{} `kuu:",desc=mygit tag - Manage tags"`

	List     bool   `kuu:"--list,-l,exclusive=tag-action,desc=List tags"`
	Delete   bool   `kuu:"--delete,-d,exclusive=tag-action,desc=Delete a tag"`
	Annotate bool   `kuu:"--annotate,-a,exclusive=tag-action,desc=Make an annotated tag"`
	Message  string `kuu:"--message,-m,value=MSG,desc=Tag message"`
	TagName  string `kuu:"tagname,pos,desc=Tag name"`
}

func (c *TagCmd) Name() string        { return "tag" }
func (c *TagCmd) Description() string { return "Create, list, delete or verify tags" }
func (c *TagCmd) Run(ctx context.Context) error {
	fmt.Println("Tag operation")
	return nil
}

// ─── remote (nested subcommands) ──────────────────────────

type RemoteCmd struct {
	_ struct{} `kuu:",require_cmd,desc=mygit remote - Manage remotes"`

	Add    *RemoteAddCmd    `kuu:"add,cmd,desc=Add a remote"`
	Remove *RemoteRemoveCmd `kuu:"remove,cmd,desc=Remove a remote"`
	Rename *RemoteRenameCmd `kuu:"rename,cmd,desc=Rename a remote"`
}

type RemoteAddCmd struct {
	_ struct{} `kuu:",desc=mygit remote add - Add a new remote"`

	Fetch bool   `kuu:"--fetch,-f,desc=Fetch after adding"`
	Name  string `kuu:"name,pos,desc=Remote name"`
	URL   string `kuu:"url,pos,desc=Remote URL"`
}

func (c *RemoteAddCmd) Name() string        { return "add" }
func (c *RemoteAddCmd) Description() string { return "Add a remote" }
func (c *RemoteAddCmd) Run(ctx context.Context) error {
	fmt.Printf("Adding remote %s -> %s\n", c.Name, c.URL)
	return nil
}

type RemoteRemoveCmd struct {
	_ struct{} `kuu:",desc=mygit remote remove - Remove a remote"`

	Name string `kuu:"name,pos,required,desc=Remote name"`
}

func (c *RemoteRemoveCmd) Name() string        { return "remove" }
func (c *RemoteRemoveCmd) Description() string { return "Remove a remote" }
func (c *RemoteRemoveCmd) Run(ctx context.Context) error {
	fmt.Printf("Removing remote: %s\n", c.Name)
	return nil
}

type RemoteRenameCmd struct {
	_ struct{} `kuu:",desc=mygit remote rename - Rename a remote"`

	Old string `kuu:"old,pos,desc=Old remote name"`
	New string `kuu:"new,pos,desc=New remote name"`
}

func (c *RemoteRenameCmd) Name() string        { return "rename" }
func (c *RemoteRenameCmd) Description() string { return "Rename a remote" }
func (c *RemoteRenameCmd) Run(ctx context.Context) error {
	fmt.Printf("Renaming remote: %s -> %s\n", c.Old, c.New)
	return nil
}

// ─── stash (nested subcommands) ───────────────────────────

type StashCmd struct {
	_ struct{} `kuu:",require_cmd,desc=mygit stash - Stash management"`

	Push *StashPushCmd `kuu:"push,cmd,desc=Save local modifications"`
	Pop  *StashPopCmd  `kuu:"pop,cmd,desc=Apply and remove stash"`
	List *StashListCmd `kuu:"list,cmd,desc=List stash entries"`
	Drop *StashDropCmd `kuu:"drop,cmd,desc=Drop a stash entry"`
}

type StashPushCmd struct {
	_ struct{} `kuu:",desc=mygit stash push - Save to stash,dashdash=false"`

	Message string   `kuu:"--message,-m,value=MSG,desc=Stash message"`
	Files   []string `kuu:",dashdash,desc=Files to stash"`
}

func (c *StashPushCmd) Name() string        { return "push" }
func (c *StashPushCmd) Description() string { return "Save local modifications" }
func (c *StashPushCmd) Run(ctx context.Context) error {
	fmt.Printf("Stash push: %s\n", c.Message)
	return nil
}

type StashPopCmd struct {
	_ struct{} `kuu:",desc=mygit stash pop - Pop from stash"`

	Index int `kuu:"--index,default=0,value=N,implicit=0,desc=Stash index"`
}

func (c *StashPopCmd) Name() string        { return "pop" }
func (c *StashPopCmd) Description() string { return "Apply and remove stash" }
func (c *StashPopCmd) Run(ctx context.Context) error {
	fmt.Printf("Stash pop: %d\n", c.Index)
	return nil
}

type StashListCmd struct {
	_ struct{} `kuu:",desc=mygit stash list - List stash entries"`
}

func (c *StashListCmd) Name() string        { return "list" }
func (c *StashListCmd) Description() string { return "List stash entries" }
func (c *StashListCmd) Run(ctx context.Context) error {
	fmt.Println("Stash list")
	return nil
}

type StashDropCmd struct {
	_ struct{} `kuu:",desc=mygit stash drop - Drop a stash entry"`

	Index int `kuu:"--index,default=0,value=N,implicit=0,desc=Stash index to drop"`
}

func (c *StashDropCmd) Name() string        { return "drop" }
func (c *StashDropCmd) Description() string { return "Drop a stash entry" }
func (c *StashDropCmd) Run(ctx context.Context) error {
	fmt.Printf("Stash drop: %d\n", c.Index)
	return nil
}

// ─── config ───────────────────────────────────────────────

type ConfigCmd struct {
	_ struct{} `kuu:",desc=mygit config - Configuration management"`

	Global bool   `kuu:"--global,exclusive=config-scope,desc=Use global config"`
	Local  bool   `kuu:"--local,exclusive=config-scope,desc=Use repository config"`
	System bool   `kuu:"--system,exclusive=config-scope,desc=Use system config"`
	Key    string `kuu:"key,pos,desc=Config key"`
	Value  string `kuu:"value,pos,desc=Config value"`
}

func (c *ConfigCmd) Name() string        { return "config" }
func (c *ConfigCmd) Description() string { return "Get and set options" }
func (c *ConfigCmd) Run(ctx context.Context) error {
	if c.Value != "" {
		fmt.Printf("Setting %s = %s\n", c.Key, c.Value)
	} else {
		fmt.Printf("Getting %s\n", c.Key)
	}
	return nil
}

// ─── main ─────────────────────────────────────────────────

func main() {
	// 方法1: Parse + 手動ディスパッチ
	root, err := kuu.Parse[RootCmd](os.Args[1:])
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}

	fmt.Printf("verbose=%d color=%s\n", root.Verbose, root.Color)

	switch {
	case root.Clone != nil:
		root.Clone.Run(context.Background())
	case root.Commit != nil:
		root.Commit.Run(context.Background())
	case root.Remote != nil:
		switch {
		case root.Remote.Add != nil:
			root.Remote.Add.Run(context.Background())
		case root.Remote.Remove != nil:
			root.Remote.Remove.Run(context.Background())
		case root.Remote.Rename != nil:
			root.Remote.Rename.Run(context.Background())
		}
	// ... 他のサブコマンド
	}

	// 方法2: Execute で自動ディスパッチ (Command interface 実装時)
	// if err := kuu.Execute[RootCmd](context.Background(), os.Args[1:]); err != nil {
	//     os.Exit(1)
	// }
}
