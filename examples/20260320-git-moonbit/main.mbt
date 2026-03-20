///|
/// mygit — A git CLI mock built with kuu.
///
/// Demonstrates kuu's ability to handle complex CLI with:
///   - global options (--git-dir, --work-tree, -C, --no-pager, --bare, --color, -v)
///   - 15+ subcommands (commit, push, pull, checkout, switch, restore, branch, log, diff, add, status, merge, rebase, tag, remote, stash)
///   - nested subcommands (remote add/remove/rename/show, stash push/pop/list/drop/apply/show)
///   - flag with variation_false (--no-edit, --no-verify, --no-pager, --no-ff)
///   - count (-v/-vv/-vvv) with variation_reset (--no-verbose)
///   - exclusive constraints (--force vs --force-with-lease, --no-ff vs --ff-only)
///   - serial positional args (push <remote> <branch>, remote add <name> <url>)
///   - rest positional args (add <pathspec>...)
///   - dashdash (checkout -- file.txt)
///   - aliases (--cached/--staged)
///   - choices (--format, --color)
///   - implicit_value (--color)
///   - append_string (--author for log)
///   - require_cmd (remote)
///
/// Run:   cd examples/20260320-git-moonbit && moon run .
/// Test:  cd examples/20260320-git-moonbit && moon test
fn main {
  println("=== Demo 1: git commit ===")
  run_test(["commit", "-m", "initial commit", "--amend"])
  println("")
  println("=== Demo 2: git push ===")
  run_test(["push", "origin", "main", "--force"])
  println("")
  println("=== Demo 3: git log ===")
  run_test(["log", "--oneline", "--graph", "-n", "10"])
  println("")
  println("=== Demo 4: git remote add ===")
  run_test(["remote", "add", "upstream", "https://example.com/repo.git"])
  println("")
  println("=== Demo 5: git checkout with -- ===")
  run_test(["checkout", "main", "--", "file1.txt", "file2.txt"])
  println("")
  println("=== Demo 6: git stash push ===")
  run_test(["stash", "push", "-m", "WIP changes", "--include-untracked"])
  println("")
  println("=== Demo 7: global options ===")
  run_test(["--git-dir", "/tmp/repo/.git", "-vv", "--no-pager", "status", "--short"])
  println("")
  println("=== Demo 8: help ===")
  run_test(["--help"])
}

///|
fn run_test(args : Array[String]) -> Unit {
  println("  args: " + args.to_string())
  match build_and_parse(args) {
    Ok(info) => println(info)
    Err(msg) => println("  ERROR: " + msg)
  }
}

///|
fn build_and_parse(args : Array[String]) -> Result[String, String] {
  let p = @core.Parser::new()
  p.set_description("mygit - A git CLI mock built with kuu")

  // ─── Global options ───

  let git_dir = p.custom(
    name="git-dir",
    default="",
    global=true,
    pre=@core.Filter::map(fn(s) { s }), // identity: string() は global 未対応のため custom を使用
    description="Set the path to the repository (.git directory)",
    value_name="PATH",
  )
  let work_tree = p.custom(
    name="work-tree",
    default="",
    global=true,
    pre=@core.Filter::map(fn(s) { s }),
    description="Set the path to the working tree",
    value_name="PATH",
  )
  let change_dir = p.custom(
    name="C",
    default="",
    global=true,
    pre=@core.Filter::map(fn(s) { s }),
    description="Run as if git was started in <path>",
    value_name="PATH",
  )
  let no_pager = p.flag(
    name="no-pager",
    global=true,
    description="Do not pipe output into a pager",
  )
  let bare = p.flag(
    name="bare",
    global=true,
    description="Treat the repository as a bare repository",
  )
  let color = p.custom(
    name="color",
    default="auto",
    global=true,
    pre=@core.Filter::map(fn(s) { s }),
    description="When to use colors",
    choices=["always", "never", "auto"],
    implicit_value=Some(@core.Val("always")),
  )
  let verbose_global = p.count(
    name="verbose",
    shorts="v",
    global=true,
    description="Be more verbose (-v, -vv, -vvv)",
    variation_reset=Some("no"),
  )

  // ─── commit ───

  let commit = p.sub(name="commit", description="Record changes to the repository")
  commit.set_description("mygit commit - Record changes to the repository")
  let commit_message = commit.custom(
    name="message",
    default="",
    shorts="m",
    pre=@core.Filter::map(fn(s) { s }),
    description="Use the given <msg> as the commit message",
    value_name="MSG",
  )
  let commit_amend = commit.flag(
    name="amend",
    description="Amend the tip of the current branch",
  )
  let commit_edit = commit.flag(
    name="edit",
    default=true,
    shorts="e",
    description="Launch editor for commit message",
    variation_false=Some("no"),
  )
  let commit_all = commit.flag(
    name="all",
    shorts="a",
    description="Stage all modified and deleted files",
  )
  let commit_allow_empty = commit.flag(
    name="allow-empty",
    description="Allow recording an empty commit",
  )
  let commit_verify = commit.flag(
    name="verify",
    default=true,
    description="Run pre-commit and commit-msg hooks",
    variation_false=Some("no"),
  )
  let commit_author = commit.string(
    name="author",
    default="",
    description="Override the commit author",
    value_name="AUTHOR",
  )
  let commit_signoff = commit.flag(
    name="signoff",
    shorts="s",
    description="Add a Signed-off-by trailer",
  )
  let commit_date = commit.string(
    name="date",
    default="",
    description="Override the author date",
    value_name="DATE",
  )

  // ─── push ───

  let push = p.sub(name="push", description="Update remote refs")
  push.set_description("mygit push - Update remote refs along with associated objects")
  // serial のクロージャスコープから Opt を取り出すために Option 型の mut 変数を経由する
  let mut push_remote_opt : @core.Opt[String]? = None
  let mut push_branch_opt : @core.Opt[String]? = None
  push.serial(setup=fn(s) {
    push_remote_opt = Some(
      s.positional(name="remote", description="Repository to push to"),
    )
    push_branch_opt = Some(
      s.positional(name="branch", description="Branch to push"),
    )
  })
  let push_force = push.flag(
    name="force",
    shorts="f",
    description="Force push",
  )
  let push_force_lease = push.flag(
    name="force-with-lease",
    description="Safe force push",
  )
  push.exclusive([push_force.as_ref(), push_force_lease.as_ref()])
  let push_set_upstream = push.flag(
    name="set-upstream",
    shorts="u",
    description="Set upstream for the current branch",
  )
  let push_all = push.flag(
    name="all",
    description="Push all branches",
  )
  let push_tags = push.flag(
    name="tags",
    description="Push all tags",
  )
  let push_delete = push.flag(
    name="delete",
    shorts="d",
    description="Delete remote branch",
  )
  push.exclusive([push_all.as_ref(), push_delete.as_ref()])
  let push_dry_run = push.flag(
    name="dry-run",
    shorts="n",
    description="Dry run",
  )

  // ─── pull ───

  let pull = p.sub(name="pull", description="Fetch and integrate remote changes")
  pull.set_description(
    "mygit pull - Fetch from and integrate with another repository",
  )
  let mut pull_remote_opt : @core.Opt[String]? = None
  let mut pull_branch_opt : @core.Opt[String]? = None
  pull.serial(setup=fn(s) {
    pull_remote_opt = Some(
      s.positional(name="remote", description="Repository to pull from"),
    )
    pull_branch_opt = Some(
      s.positional(name="branch", description="Branch to pull"),
    )
  })
  let pull_rebase = pull.flag(
    name="rebase",
    description="Rebase instead of merge",
    variation_false=Some("no"),
  )
  let pull_ff_only = pull.flag(
    name="ff-only",
    description="Only fast-forward",
  )
  let pull_no_ff = pull.flag(
    name="no-ff",
    description="Create a merge commit even for fast-forward",
  )
  pull.exclusive([pull_ff_only.as_ref(), pull_no_ff.as_ref()])

  // ─── checkout ───

  // Design rationale: dashdash=false で自動 "--" ノードを抑制し、
  // 手動 dashdash() で branch positional と file pathspec を明示的に分離する
  let checkout = p.sub(
    name="checkout",
    aliases=["co"],
    dashdash=false,
    description="Switch branches or restore working tree files",
  )
  checkout.set_description("mygit checkout - Switch branches or restore files")
  let checkout_branch = checkout.positional(
    name="branch",
    description="Branch to checkout",
  )
  let checkout_new_branch = checkout.custom(
    name="new-branch",
    default="",
    shorts="b",
    pre=@core.Filter::map(fn(s) { s }),
    description="Create and checkout a new branch",
    value_name="NEW_BRANCH",
  )
  let checkout_track = checkout.flag(
    name="track",
    shorts="t",
    description="Set up tracking mode",
  )
  let checkout_force = checkout.flag(
    name="force",
    shorts="f",
    description="Force checkout (discard local changes)",
  )
  let checkout_dashdash = checkout.dashdash()

  // ─── switch ───

  let switch = p.sub(name="switch", description="Switch branches")
  switch.set_description("mygit switch - Switch branches")
  let switch_branch = switch.positional(
    name="branch",
    description="Branch to switch to",
  )
  let switch_create = switch.custom(
    name="create",
    default="",
    shorts="c",
    pre=@core.Filter::map(fn(s) { s }),
    description="Create and switch to a new branch",
    value_name="NEW_BRANCH",
  )
  let switch_detach = switch.flag(
    name="detach",
    description="Detach HEAD at the named commit",
  )
  let switch_track = switch.flag(
    name="track",
    shorts="t",
    description="Set up tracking mode",
  )

  // ─── restore ───

  let restore = p.sub(name="restore", description="Restore working tree files")
  restore.set_description("mygit restore - Restore working tree files")
  let restore_source = restore.custom(
    name="source",
    default="",
    shorts="s",
    pre=@core.Filter::map(fn(s) { s }),
    description="Restore from the given tree",
    value_name="TREE",
  )
  let restore_staged = restore.flag(
    name="staged",
    shorts="S",
    description="Restore the staging area",
  )
  let restore_worktree = restore.flag(
    name="worktree",
    shorts="W",
    description="Restore the working tree (default)",
  )
  let restore_files = restore.rest(
    name="pathspec",
    description="Files to restore",
  )

  // ─── branch ───

  let branch = p.sub(
    name="branch",
    aliases=["br"],
    description="List, create, or delete branches",
  )
  branch.set_description("mygit branch - List, create, or delete branches")
  let branch_name = branch.positional(
    name="branch-name",
    description="Branch name",
  )
  let branch_delete = branch.flag(
    name="delete",
    shorts="d",
    description="Delete a branch",
  )
  let branch_force_delete = branch.flag(
    name="force-delete",
    shorts="D",
    description="Force delete a branch",
  )
  branch.exclusive([branch_delete.as_ref(), branch_force_delete.as_ref()])
  let branch_move = branch.flag(
    name="move",
    shorts="m",
    description="Rename a branch",
  )
  let branch_force_move = branch.flag(
    name="force-move",
    shorts="M",
    description="Force rename a branch",
  )
  branch.exclusive([branch_move.as_ref(), branch_force_move.as_ref()])
  let branch_all = branch.flag(
    name="all",
    shorts="a",
    description="List both local and remote branches",
  )
  let branch_remotes = branch.flag(
    name="remotes",
    shorts="r",
    description="List remote branches",
  )
  let branch_list = branch.flag(
    name="list",
    description="List branches",
  )

  // ─── log ───

  let log = p.sub(name="log", description="Show commit logs")
  log.set_description("mygit log - Show commit logs")
  let log_max_count = log.custom(
    name="max-count",
    default=0,
    shorts="n",
    pre=@core.Filter::parse_int(),
    description="Limit the number of commits",
    value_name="N",
  )
  let log_oneline = log.flag(
    name="oneline",
    description="Shorthand for --format=oneline --abbrev-commit",
  )
  let log_graph = log.flag(name="graph", description="Draw a graph of commits")
  let log_all = log.flag(
    name="all",
    description="Show all refs",
  )
  let log_format = log.string(
    name="format",
    default="",
    description="Pretty-print format",
    choices=[
      "oneline", "short", "medium", "full", "fuller", "reference", "email", "raw",
    ],
    value_name="FORMAT",
  )
  let log_author = log.append_string(
    name="author",
    description="Filter by author (repeatable)",
    value_name="PATTERN",
  )
  let log_since = log.string(
    name="since",
    default="",
    description="Show commits after date",
    value_name="DATE",
  )
  let log_until = log.string(
    name="until",
    default="",
    description="Show commits before date",
    value_name="DATE",
  )
  let log_paths = log.rest(name="path", description="Show commits touching path")

  // ─── diff ───

  let diff = p.sub(name="diff", description="Show changes between commits")
  diff.set_description("mygit diff - Show changes between commits, trees, etc.")
  let diff_cached = diff.flag(
    name="cached",
    aliases=["staged"],
    description="Show staged changes",
  )
  let diff_name_only = diff.flag(
    name="name-only",
    description="Show only names of changed files",
  )
  let diff_stat = diff.flag(name="stat", description="Generate a diffstat")
  let diff_paths = diff.rest(name="path", description="Restrict diff to paths")

  // ─── add ───

  let add = p.sub(name="add", description="Add file contents to the index")
  add.set_description("mygit add - Add file contents to the index")
  let add_files = add.rest(
    name="pathspec",
    description="Files to add",
  )
  let add_all = add.flag(
    name="all",
    shorts="A",
    description="Add all changes (new, modified, deleted)",
  )
  let add_force = add.flag(
    name="force",
    shorts="f",
    description="Allow adding otherwise ignored files",
  )
  let add_dry_run = add.flag(
    name="dry-run",
    shorts="n",
    description="Don't actually add files, just show what would happen",
  )

  // ─── status ───

  let status = p.sub(
    name="status",
    aliases=["st"],
    description="Show the working tree status",
  )
  status.set_description("mygit status - Show the working tree status")
  let status_short = status.flag(
    name="short",
    shorts="s",
    description="Give output in short format",
  )
  let status_branch = status.flag(
    name="branch",
    shorts="b",
    description="Show branch info in short format",
  )
  let status_porcelain = status.flag(
    name="porcelain",
    description="Machine-readable output",
  )

  // ─── merge ───

  let merge = p.sub(
    name="merge",
    description="Join two or more development histories",
  )
  merge.set_description("mygit merge - Join development histories together")
  let merge_branch = merge.positional(
    name="branch",
    description="Branch to merge",
  )
  let merge_no_ff = merge.flag(
    name="no-ff",
    description="Create a merge commit even for fast-forward",
  )
  let merge_ff_only = merge.flag(
    name="ff-only",
    description="Only allow fast-forward merges",
  )
  merge.exclusive([merge_no_ff.as_ref(), merge_ff_only.as_ref()])
  let merge_squash = merge.flag(
    name="squash",
    description="Create a single commit instead of a merge",
  )
  let merge_message = merge.custom(
    name="message",
    default="",
    shorts="m",
    pre=@core.Filter::map(fn(s) { s }),
    description="Set the commit message",
    value_name="MSG",
  )
  let merge_abort = merge.flag(
    name="abort",
    description="Abort the current merge",
  )

  // ─── rebase ───

  let rebase = p.sub(
    name="rebase",
    description="Reapply commits on top of another base",
  )
  rebase.set_description("mygit rebase - Reapply commits on top of another base tip")
  let rebase_upstream = rebase.positional(
    name="upstream",
    description="Upstream branch",
  )
  let rebase_onto = rebase.string(
    name="onto",
    default="",
    description="Starting point for new commits",
    value_name="NEWBASE",
  )
  let rebase_interactive = rebase.flag(
    name="interactive",
    shorts="i",
    description="Interactive rebase",
  )
  let rebase_continue = rebase.flag(
    name="continue",
    description="Continue after resolving conflicts",
  )
  let rebase_abort = rebase.flag(
    name="abort",
    description="Abort and return to original branch",
  )
  let rebase_skip = rebase.flag(
    name="skip",
    description="Skip the current patch",
  )
  rebase.exclusive([
    rebase_continue.as_ref(),
    rebase_abort.as_ref(),
    rebase_skip.as_ref(),
  ])

  // ─── tag ───

  let tag = p.sub(name="tag", description="Create, list, delete or verify tags")
  tag.set_description("mygit tag - Create, list, delete or verify a tag object")
  let tag_name = tag.positional(name="tagname", description="Tag name")
  let tag_annotate = tag.flag(
    name="annotate",
    shorts="a",
    description="Make an annotated tag",
  )
  let tag_message = tag.custom(
    name="message",
    default="",
    shorts="m",
    pre=@core.Filter::map(fn(s) { s }),
    description="Tag message",
    value_name="MSG",
  )
  let tag_delete = tag.flag(
    name="delete",
    shorts="d",
    description="Delete a tag",
  )
  let tag_list = tag.flag(
    name="list",
    shorts="l",
    description="List tags",
  )
  let tag_force = tag.flag(
    name="force",
    shorts="f",
    description="Force creation (replace existing tag)",
  )

  // ─── remote (nested subcommands) ───

  let remote = p.sub(name="remote", description="Manage set of tracked repositories")
  remote.set_description("mygit remote - Manage set of tracked repositories")
  remote.require_cmd()

  let remote_add = remote.sub(name="add", description="Add a remote")
  remote_add.set_description("mygit remote add - Add a new remote")
  let mut remote_add_name_opt : @core.Opt[String]? = None
  let mut remote_add_url_opt : @core.Opt[String]? = None
  remote_add.serial(setup=fn(s) {
    remote_add_name_opt = Some(
      s.positional(name="name", description="Name of the remote"),
    )
    remote_add_url_opt = Some(
      s.positional(name="url", description="URL of the remote"),
    )
    s.never()
  })
  let remote_add_fetch = remote_add.flag(
    name="fetch",
    shorts="f",
    description="Fetch the remote after adding",
  )

  let remote_remove = remote.sub(
    name="remove",
    aliases=["rm"],
    description="Remove a remote",
  )
  remote_remove.set_description("mygit remote remove - Remove a remote")
  let remote_remove_name = remote_remove.positional(
    name="name",
    description="Name of the remote to remove",
  )

  let remote_rename = remote.sub(name="rename", description="Rename a remote")
  remote_rename.set_description("mygit remote rename - Rename a remote")
  let mut remote_rename_old_opt : @core.Opt[String]? = None
  let mut remote_rename_new_opt : @core.Opt[String]? = None
  remote_rename.serial(setup=fn(s) {
    remote_rename_old_opt = Some(
      s.positional(name="old", description="Current name"),
    )
    remote_rename_new_opt = Some(
      s.positional(name="new", description="New name"),
    )
    s.never()
  })

  let remote_show = remote.sub(name="show", description="Show information about remote")
  remote_show.set_description("mygit remote show - Show information about remote")
  let remote_show_name = remote_show.positional(
    name="name",
    description="Name of the remote",
  )

  // ─── stash (nested subcommands) ───

  let stash = p.sub(name="stash", description="Stash changes in a dirty working directory")
  stash.set_description("mygit stash - Stash the changes in a dirty working directory")

  let stash_push = stash.sub(name="push", description="Save local modifications")
  stash_push.set_description("mygit stash push - Save local modifications to a new stash")
  let stash_push_message = stash_push.custom(
    name="message",
    default="",
    shorts="m",
    pre=@core.Filter::map(fn(s) { s }),
    description="Stash message",
    value_name="MSG",
  )
  let stash_push_untracked = stash_push.flag(
    name="include-untracked",
    shorts="u",
    description="Include untracked files",
  )
  let stash_push_files = stash_push.rest(
    name="pathspec",
    description="Files to stash",
  )

  let stash_pop = stash.sub(name="pop", description="Apply and remove a stash")
  stash_pop.set_description("mygit stash pop - Apply and remove a single stash")
  let stash_pop_ref = stash_pop.positional(
    name="stash",
    description="Stash reference (e.g. stash@{0})",
  )

  let stash_apply = stash.sub(name="apply", description="Apply a stash without removing")
  stash_apply.set_description("mygit stash apply - Apply a stash without removing it")
  let stash_apply_ref = stash_apply.positional(
    name="stash",
    description="Stash reference",
  )

  let stash_drop = stash.sub(name="drop", description="Remove a single stash")
  stash_drop.set_description("mygit stash drop - Remove a single stashed state")
  let stash_drop_ref = stash_drop.positional(
    name="stash",
    description="Stash reference",
  )

  let _stash_list = stash.sub(name="list", description="List stashed changes")

  let stash_show = stash.sub(name="show", description="Show stash contents")
  stash_show.set_description("mygit stash show - Show changes in a stash")
  let stash_show_ref = stash_show.positional(
    name="stash",
    description="Stash reference",
  )

  // ─── Parse ───

  let result : Result[@core.ParseResult, @core.ParseError] = try? p.parse(args)
  match result {
    Err(@core.HelpRequested(text)) => Ok(text)
    Err(@core.ParseError(info)) => Err(info.to_string())
    Ok(result) => {
      let buf = StringBuilder::new()

      // Global options
      let git_dir_val = git_dir.get().unwrap()
      if git_dir_val != "" {
        buf.write_string("  git-dir: " + git_dir_val + "\n")
      }
      let work_tree_val = work_tree.get().unwrap()
      if work_tree_val != "" {
        buf.write_string("  work-tree: " + work_tree_val + "\n")
      }
      let change_dir_val = change_dir.get().unwrap()
      if change_dir_val != "" {
        buf.write_string("  -C: " + change_dir_val + "\n")
      }
      if no_pager.get().unwrap() {
        buf.write_string("  no-pager: true\n")
      }
      if bare.get().unwrap() {
        buf.write_string("  bare: true\n")
      }
      let color_val = color.get().unwrap()
      if color_val != "auto" {
        buf.write_string("  color: " + color_val + "\n")
      }
      let verbose_val = verbose_global.get().unwrap()
      if verbose_val > 0 {
        buf.write_string("  verbose: " + verbose_val.to_string() + "\n")
      }

      // ─── Dispatch subcommands ───

      match result.child("commit") {
        Some(_) => {
          buf.write_string("  command: commit\n")
          let msg = commit_message.get().unwrap()
          if msg != "" {
            buf.write_string("  message: \"" + msg + "\"\n")
          }
          if commit_amend.get().unwrap() {
            buf.write_string("  amend: true\n")
          }
          if not(commit_edit.get().unwrap()) {
            buf.write_string("  no-edit: true\n")
          }
          if commit_all.get().unwrap() {
            buf.write_string("  all: true\n")
          }
          if commit_allow_empty.get().unwrap() {
            buf.write_string("  allow-empty: true\n")
          }
          if not(commit_verify.get().unwrap()) {
            buf.write_string("  no-verify: true\n")
          }
          let author_val = commit_author.get().unwrap()
          if author_val != "" {
            buf.write_string("  author: \"" + author_val + "\"\n")
          }
          if commit_signoff.get().unwrap() {
            buf.write_string("  signoff: true\n")
          }
          let date_val = commit_date.get().unwrap()
          if date_val != "" {
            buf.write_string("  date: \"" + date_val + "\"\n")
          }
        }
        None => ()
      }

      match result.child("push") {
        Some(_) => {
          buf.write_string("  command: push\n")
          write_serial(buf, push_remote_opt, "remote")
          write_serial(buf, push_branch_opt, "branch")
          if push_force.get().unwrap() {
            buf.write_string("  force: true\n")
          }
          if push_force_lease.get().unwrap() {
            buf.write_string("  force-with-lease: true\n")
          }
          if push_set_upstream.get().unwrap() {
            buf.write_string("  set-upstream: true\n")
          }
          if push_all.get().unwrap() {
            buf.write_string("  all: true\n")
          }
          if push_tags.get().unwrap() {
            buf.write_string("  tags: true\n")
          }
          if push_delete.get().unwrap() {
            buf.write_string("  delete: true\n")
          }
          if push_dry_run.get().unwrap() {
            buf.write_string("  dry-run: true\n")
          }
        }
        None => ()
      }

      match result.child("pull") {
        Some(_) => {
          buf.write_string("  command: pull\n")
          write_serial(buf, pull_remote_opt, "remote")
          write_serial(buf, pull_branch_opt, "branch")
          if pull_rebase.is_set() {
            buf.write_string(
              "  rebase: " + pull_rebase.get().unwrap().to_string() + "\n",
            )
          }
          if pull_ff_only.get().unwrap() {
            buf.write_string("  ff-only: true\n")
          }
          if pull_no_ff.get().unwrap() {
            buf.write_string("  no-ff: true\n")
          }
        }
        None => ()
      }

      match result.child("checkout") {
        Some(_) => {
          buf.write_string("  command: checkout\n")
          write_positional(buf, checkout_branch, "branch")
          let new_branch_val = checkout_new_branch.get().unwrap()
          if new_branch_val != "" {
            buf.write_string("  new-branch: " + new_branch_val + "\n")
          }
          if checkout_track.get().unwrap() {
            buf.write_string("  track: true\n")
          }
          if checkout_force.get().unwrap() {
            buf.write_string("  force: true\n")
          }
          let dashdash_files = checkout_dashdash.get().unwrap()
          if dashdash_files.length() > 0 {
            buf.write_string("  -- " + dashdash_files.to_string() + "\n")
          }
        }
        None => ()
      }

      match result.child("switch") {
        Some(_) => {
          buf.write_string("  command: switch\n")
          write_positional(buf, switch_branch, "branch")
          let create_val = switch_create.get().unwrap()
          if create_val != "" {
            buf.write_string("  create: " + create_val + "\n")
          }
          if switch_detach.get().unwrap() {
            buf.write_string("  detach: true\n")
          }
          if switch_track.get().unwrap() {
            buf.write_string("  track: true\n")
          }
        }
        None => ()
      }

      match result.child("restore") {
        Some(_) => {
          buf.write_string("  command: restore\n")
          let source_val = restore_source.get().unwrap()
          if source_val != "" {
            buf.write_string("  source: " + source_val + "\n")
          }
          if restore_staged.get().unwrap() {
            buf.write_string("  staged: true\n")
          }
          if restore_worktree.get().unwrap() {
            buf.write_string("  worktree: true\n")
          }
          let restore_file_list = restore_files.get().unwrap()
          if restore_file_list.length() > 0 {
            buf.write_string("  files: " + restore_file_list.to_string() + "\n")
          }
        }
        None => ()
      }

      match result.child("branch") {
        Some(_) => {
          buf.write_string("  command: branch\n")
          write_positional(buf, branch_name, "name")
          if branch_delete.get().unwrap() {
            buf.write_string("  delete: true\n")
          }
          if branch_force_delete.get().unwrap() {
            buf.write_string("  force-delete: true\n")
          }
          if branch_move.get().unwrap() {
            buf.write_string("  move: true\n")
          }
          if branch_force_move.get().unwrap() {
            buf.write_string("  force-move: true\n")
          }
          if branch_all.get().unwrap() {
            buf.write_string("  all: true\n")
          }
          if branch_remotes.get().unwrap() {
            buf.write_string("  remotes: true\n")
          }
          if branch_list.get().unwrap() {
            buf.write_string("  list: true\n")
          }
        }
        None => ()
      }

      match result.child("log") {
        Some(_) => {
          buf.write_string("  command: log\n")
          let max_count_val = log_max_count.get().unwrap()
          if max_count_val > 0 {
            buf.write_string("  max-count: " + max_count_val.to_string() + "\n")
          }
          if log_oneline.get().unwrap() {
            buf.write_string("  oneline: true\n")
          }
          if log_graph.get().unwrap() {
            buf.write_string("  graph: true\n")
          }
          if log_all.get().unwrap() {
            buf.write_string("  all: true\n")
          }
          let format_val = log_format.get().unwrap()
          if format_val != "" {
            buf.write_string("  format: " + format_val + "\n")
          }
          let authors = log_author.get().unwrap()
          if authors.length() > 0 {
            buf.write_string("  author: " + authors.to_string() + "\n")
          }
          let since = log_since.get().unwrap()
          if since != "" {
            buf.write_string("  since: " + since + "\n")
          }
          let until = log_until.get().unwrap()
          if until != "" {
            buf.write_string("  until: " + until + "\n")
          }
          let paths = log_paths.get().unwrap()
          if paths.length() > 0 {
            buf.write_string("  paths: " + paths.to_string() + "\n")
          }
        }
        None => ()
      }

      match result.child("diff") {
        Some(_) => {
          buf.write_string("  command: diff\n")
          if diff_cached.get().unwrap() {
            buf.write_string("  cached: true\n")
          }
          if diff_name_only.get().unwrap() {
            buf.write_string("  name-only: true\n")
          }
          if diff_stat.get().unwrap() {
            buf.write_string("  stat: true\n")
          }
          let paths = diff_paths.get().unwrap()
          if paths.length() > 0 {
            buf.write_string("  paths: " + paths.to_string() + "\n")
          }
        }
        None => ()
      }

      match result.child("add") {
        Some(_) => {
          buf.write_string("  command: add\n")
          if add_all.get().unwrap() {
            buf.write_string("  all: true\n")
          }
          if add_force.get().unwrap() {
            buf.write_string("  force: true\n")
          }
          if add_dry_run.get().unwrap() {
            buf.write_string("  dry-run: true\n")
          }
          let add_file_list = add_files.get().unwrap()
          if add_file_list.length() > 0 {
            buf.write_string("  files: " + add_file_list.to_string() + "\n")
          }
        }
        None => ()
      }

      match result.child("status") {
        Some(_) => {
          buf.write_string("  command: status\n")
          if status_short.get().unwrap() {
            buf.write_string("  short: true\n")
          }
          if status_branch.get().unwrap() {
            buf.write_string("  branch: true\n")
          }
          if status_porcelain.get().unwrap() {
            buf.write_string("  porcelain: true\n")
          }
        }
        None => ()
      }

      match result.child("merge") {
        Some(_) => {
          buf.write_string("  command: merge\n")
          write_positional(buf, merge_branch, "branch")
          if merge_no_ff.get().unwrap() {
            buf.write_string("  no-ff: true\n")
          }
          if merge_ff_only.get().unwrap() {
            buf.write_string("  ff-only: true\n")
          }
          if merge_squash.get().unwrap() {
            buf.write_string("  squash: true\n")
          }
          let merge_msg = merge_message.get().unwrap()
          if merge_msg != "" {
            buf.write_string("  message: \"" + merge_msg + "\"\n")
          }
          if merge_abort.get().unwrap() {
            buf.write_string("  abort: true\n")
          }
        }
        None => ()
      }

      match result.child("rebase") {
        Some(_) => {
          buf.write_string("  command: rebase\n")
          write_positional(buf, rebase_upstream, "upstream")
          let onto = rebase_onto.get().unwrap()
          if onto != "" {
            buf.write_string("  onto: " + onto + "\n")
          }
          if rebase_interactive.get().unwrap() {
            buf.write_string("  interactive: true\n")
          }
          if rebase_continue.get().unwrap() {
            buf.write_string("  continue: true\n")
          }
          if rebase_abort.get().unwrap() {
            buf.write_string("  abort: true\n")
          }
          if rebase_skip.get().unwrap() {
            buf.write_string("  skip: true\n")
          }
        }
        None => ()
      }

      match result.child("tag") {
        Some(_) => {
          buf.write_string("  command: tag\n")
          write_positional(buf, tag_name, "name")
          if tag_annotate.get().unwrap() {
            buf.write_string("  annotate: true\n")
          }
          let tag_msg = tag_message.get().unwrap()
          if tag_msg != "" {
            buf.write_string("  message: \"" + tag_msg + "\"\n")
          }
          if tag_delete.get().unwrap() {
            buf.write_string("  delete: true\n")
          }
          if tag_list.get().unwrap() {
            buf.write_string("  list: true\n")
          }
          if tag_force.get().unwrap() {
            buf.write_string("  force: true\n")
          }
        }
        None => ()
      }

      match result.child("remote") {
        Some(remote_result) => {
          buf.write_string("  command: remote\n")
          match remote_result.child("add") {
            Some(_) => {
              buf.write_string("  subcommand: add\n")
              write_serial(buf, remote_add_name_opt, "name")
              write_serial(buf, remote_add_url_opt, "url")
              if remote_add_fetch.get().unwrap() {
                buf.write_string("  fetch: true\n")
              }
            }
            None => ()
          }
          match remote_result.child("remove") {
            Some(_) => {
              buf.write_string("  subcommand: remove\n")
              write_positional(buf, remote_remove_name, "name")
            }
            None => ()
          }
          match remote_result.child("rename") {
            Some(_) => {
              buf.write_string("  subcommand: rename\n")
              write_serial(buf, remote_rename_old_opt, "old")
              write_serial(buf, remote_rename_new_opt, "new")
            }
            None => ()
          }
          match remote_result.child("show") {
            Some(_) => {
              buf.write_string("  subcommand: show\n")
              write_positional(buf, remote_show_name, "name")
            }
            None => ()
          }
        }
        None => ()
      }

      match result.child("stash") {
        Some(stash_result) => {
          buf.write_string("  command: stash\n")
          match stash_result.child("push") {
            Some(_) => {
              buf.write_string("  subcommand: push\n")
              let stash_msg = stash_push_message.get().unwrap()
              if stash_msg != "" {
                buf.write_string("  message: \"" + stash_msg + "\"\n")
              }
              if stash_push_untracked.get().unwrap() {
                buf.write_string("  include-untracked: true\n")
              }
              let stash_files = stash_push_files.get().unwrap()
              if stash_files.length() > 0 {
                buf.write_string("  files: " + stash_files.to_string() + "\n")
              }
            }
            None => ()
          }
          match stash_result.child("pop") {
            Some(_) => {
              buf.write_string("  subcommand: pop\n")
              write_positional(buf, stash_pop_ref, "stash")
            }
            None => ()
          }
          match stash_result.child("apply") {
            Some(_) => {
              buf.write_string("  subcommand: apply\n")
              write_positional(buf, stash_apply_ref, "stash")
            }
            None => ()
          }
          match stash_result.child("drop") {
            Some(_) => {
              buf.write_string("  subcommand: drop\n")
              write_positional(buf, stash_drop_ref, "stash")
            }
            None => ()
          }
          match stash_result.child("list") {
            Some(_) => buf.write_string("  subcommand: list\n")
            None => ()
          }
          match stash_result.child("show") {
            Some(_) => {
              buf.write_string("  subcommand: show\n")
              write_positional(buf, stash_show_ref, "stash")
            }
            None => ()
          }
        }
        None => ()
      }

      Ok(buf.to_string())
    }
  }
}

// ─── Dispatch helpers ───

///|
/// Write "  {label}: {value}\n" if the positional opt has a value.
fn write_positional(
  buf : StringBuilder,
  opt : @core.Opt[String],
  label : String,
) -> Unit {
  if opt.is_set() {
    match opt.get() {
      Some(v) => buf.write_string("  " + label + ": " + v + "\n")
      None => ()
    }
  }
}

///|
/// Write "  {label}: {value}\n" from a serial positional opt (Opt[String]?).
fn write_serial(
  buf : StringBuilder,
  opt : @core.Opt[String]?,
  label : String
) -> Unit {
  match opt {
    Some(o) => write_positional(buf, o, label)
    None => ()
  }
}

// ─── Tests ───

test "commit: basic" {
  let result = build_and_parse(["commit", "-m", "initial commit"])
  inspect(result, content=(
    #|Ok("  command: commit\n  message: \"initial commit\"\n")
  ))
}

test "commit: amend with no-edit" {
  let result = build_and_parse(["commit", "--amend", "--no-edit"])
  inspect(result, content=(
    #|Ok("  command: commit\n  amend: true\n  no-edit: true\n")
  ))
}

test "commit: no-verify" {
  let result = build_and_parse(["commit", "-m", "fix", "--no-verify"])
  inspect(result, content=(
    #|Ok("  command: commit\n  message: \"fix\"\n  no-verify: true\n")
  ))
}

test "commit: all options" {
  let result = build_and_parse([
    "commit", "-a", "-m", "msg", "--author", "Test <test@example.com>",
    "--signoff", "--date", "2024-01-01",
  ])
  inspect(result, content=(
    #|Ok("  command: commit\n  message: \"msg\"\n  all: true\n  author: \"Test <test@example.com>\"\n  signoff: true\n  date: \"2024-01-01\"\n")
  ))
}

test "push: basic" {
  let result = build_and_parse(["push", "origin", "main"])
  inspect(result, content=(
    #|Ok("  command: push\n  remote: origin\n  branch: main\n")
  ))
}

test "push: force" {
  let result = build_and_parse(["push", "origin", "main", "--force"])
  inspect(result, content=(
    #|Ok("  command: push\n  remote: origin\n  branch: main\n  force: true\n")
  ))
}

test "push: force-with-lease" {
  let result = build_and_parse(["push", "--force-with-lease", "origin", "main"])
  inspect(result, content=(
    #|Ok("  command: push\n  remote: origin\n  branch: main\n  force-with-lease: true\n")
  ))
}

test "push: exclusive force vs force-with-lease" {
  match build_and_parse(["push", "--force", "--force-with-lease"]) {
    Err(msg) =>
      assert_true(
        msg.has_prefix("error: mutually exclusive options: --force, --force-with-lease"),
      )
    Ok(_) => fail("expected error")
  }
}

test "push: set-upstream" {
  let result = build_and_parse(["push", "-u", "origin", "feature/test"])
  inspect(result, content=(
    #|Ok("  command: push\n  remote: origin\n  branch: feature/test\n  set-upstream: true\n")
  ))
}

test "pull: basic" {
  let result = build_and_parse(["pull", "origin", "main"])
  inspect(result, content=(
    #|Ok("  command: pull\n  remote: origin\n  branch: main\n")
  ))
}

test "pull: rebase" {
  let result = build_and_parse(["pull", "--rebase"])
  inspect(result, content=(
    #|Ok("  command: pull\n  rebase: true\n")

  ))
}

test "pull: no-rebase" {
  let result = build_and_parse(["pull", "--no-rebase"])
  inspect(result, content=(
    #|Ok("  command: pull\n  rebase: false\n")

  ))
}

test "pull: exclusive ff-only vs no-ff" {
  match build_and_parse(["pull", "--ff-only", "--no-ff"]) {
    Err(msg) =>
      assert_true(
        msg.has_prefix("error: mutually exclusive options: --ff-only, --no-ff"),
      )
    Ok(_) => fail("expected error")
  }
}

test "checkout: branch" {
  let result = build_and_parse(["checkout", "main"])
  inspect(result, content=(
    #|Ok("  command: checkout\n  branch: main\n")

  ))
}

test "checkout: new branch" {
  let result = build_and_parse(["checkout", "-b", "feature/new"])
  inspect(result, content=(
    #|Ok("  command: checkout\n  new-branch: feature/new\n")


  ))
}

test "checkout: dashdash" {
  let result = build_and_parse([
    "checkout", "main", "--", "file1.txt", "file2.txt",
  ])
  inspect(result, content=(
    #|Ok("  command: checkout\n  branch: main\n  -- [\"file1.txt\", \"file2.txt\"]\n")

  ))
}

test "checkout: alias co" {
  let result = build_and_parse(["co", "main"])
  inspect(result, content=(
    #|Ok("  command: checkout\n  branch: main\n")

  ))
}

test "switch: branch" {
  let result = build_and_parse(["switch", "main"])
  inspect(result, content=(
    #|Ok("  command: switch\n  branch: main\n")
  ))
}

test "switch: create" {
  let result = build_and_parse(["switch", "-c", "feature/new"])
  inspect(result, content=(
    #|Ok("  command: switch\n  create: feature/new\n")

  ))
}

test "restore: staged" {
  let result = build_and_parse(["restore", "--staged", "file.txt"])
  inspect(result, content=(
    #|Ok("  command: restore\n  staged: true\n  files: [\"file.txt\"]\n")
  ))
}

test "restore: source" {
  let result = build_and_parse([
    "restore", "--source", "HEAD~1", "file1.txt", "file2.txt",
  ])
  inspect(result, content=(
    #|Ok("  command: restore\n  source: HEAD~1\n  files: [\"file1.txt\", \"file2.txt\"]\n")
  ))
}

test "branch: list" {
  let result = build_and_parse(["branch", "--list"])
  inspect(result, content=(
    #|Ok("  command: branch\n  list: true\n")

  ))
}

test "branch: delete" {
  let result = build_and_parse(["branch", "-d", "old-branch"])
  inspect(result, content=(
    #|Ok("  command: branch\n  name: old-branch\n  delete: true\n")
  ))
}

test "branch: force delete" {
  let result = build_and_parse(["branch", "-D", "old-branch"])
  inspect(result, content=(
    #|Ok("  command: branch\n  name: old-branch\n  force-delete: true\n")
  ))
}

test "branch: all" {
  let result = build_and_parse(["branch", "-a"])
  inspect(result, content=(
    #|Ok("  command: branch\n  all: true\n")

  ))
}

test "branch: alias br" {
  let result = build_and_parse(["br", "--list"])
  inspect(result, content=(
    #|Ok("  command: branch\n  list: true\n")

  ))
}

test "log: basic" {
  let result = build_and_parse(["log", "--oneline", "--graph", "-n", "10"])
  inspect(result, content=(
    #|Ok("  command: log\n  max-count: 10\n  oneline: true\n  graph: true\n")
  ))
}

test "log: format" {
  let result = build_and_parse(["log", "--format", "short"])
  inspect(result, content=(
    #|Ok("  command: log\n  format: short\n")
  ))
}

test "log: author filter" {
  let result = build_and_parse([
    "log", "--author", "Alice", "--author", "Bob",
  ])
  inspect(result, content=(
    #|Ok("  command: log\n  author: [\"Alice\", \"Bob\"]\n")
  ))
}

test "log: since until" {
  let result = build_and_parse([
    "log", "--since", "2024-01-01", "--until", "2024-12-31",
  ])
  inspect(result, content=(
    #|Ok("  command: log\n  since: 2024-01-01\n  until: 2024-12-31\n")
  ))
}

test "diff: cached" {
  let result = build_and_parse(["diff", "--cached"])
  inspect(result, content=(
    #|Ok("  command: diff\n  cached: true\n")
  ))
}

test "diff: staged alias" {
  let result = build_and_parse(["diff", "--staged"])
  inspect(result, content=(
    #|Ok("  command: diff\n  cached: true\n")
  ))
}

test "diff: stat with paths" {
  let result = build_and_parse(["diff", "--stat", "src/", "lib/"])
  inspect(result, content=(
    #|Ok("  command: diff\n  stat: true\n  paths: [\"src/\", \"lib/\"]\n")
  ))
}

test "add: files" {
  let result = build_and_parse(["add", "file1.txt", "file2.txt"])
  inspect(result, content=(
    #|Ok("  command: add\n  files: [\"file1.txt\", \"file2.txt\"]\n")
  ))
}

test "add: all" {
  let result = build_and_parse(["add", "-A"])
  inspect(result, content=(
    #|Ok("  command: add\n  all: true\n")
  ))
}

test "status: short branch" {
  let result = build_and_parse(["status", "-sb"])
  inspect(result, content=(
    #|Ok("  command: status\n  short: true\n  branch: true\n")
  ))
}

test "status: porcelain" {
  let result = build_and_parse(["status", "--porcelain"])
  inspect(result, content=(
    #|Ok("  command: status\n  porcelain: true\n")
  ))
}

test "status: alias st" {
  let result = build_and_parse(["st", "--short"])
  inspect(result, content=(
    #|Ok("  command: status\n  short: true\n")
  ))
}

test "merge: basic" {
  let result = build_and_parse(["merge", "feature/test"])
  inspect(result, content=(
    #|Ok("  command: merge\n  branch: feature/test\n")
  ))
}

test "merge: no-ff" {
  let result = build_and_parse(["merge", "--no-ff", "feature/test"])
  inspect(result, content=(
    #|Ok("  command: merge\n  branch: feature/test\n  no-ff: true\n")
  ))
}

test "merge: squash with message" {
  let result = build_and_parse([
    "merge", "--squash", "-m", "Squash merge", "feature/test",
  ])
  inspect(result, content=(
    #|Ok("  command: merge\n  branch: feature/test\n  squash: true\n  message: \"Squash merge\"\n")
  ))
}

test "merge: exclusive no-ff vs ff-only" {
  match build_and_parse(["merge", "--no-ff", "--ff-only", "branch"]) {
    Err(msg) =>
      assert_true(
        msg.has_prefix("error: mutually exclusive options: --no-ff, --ff-only"),
      )
    Ok(_) => fail("expected error")
  }
}

test "rebase: basic" {
  let result = build_and_parse(["rebase", "main"])
  inspect(result, content=(
    #|Ok("  command: rebase\n  upstream: main\n")
  ))
}

test "rebase: interactive" {
  let result = build_and_parse(["rebase", "-i", "HEAD~3"])
  inspect(result, content=(
    #|Ok("  command: rebase\n  upstream: HEAD~3\n  interactive: true\n")
  ))
}

test "rebase: onto" {
  let result = build_and_parse(["rebase", "--onto", "main", "feature"])
  inspect(result, content=(
    #|Ok("  command: rebase\n  upstream: feature\n  onto: main\n")
  ))
}

test "rebase: continue" {
  let result = build_and_parse(["rebase", "--continue"])
  inspect(result, content=(
    #|Ok("  command: rebase\n  continue: true\n")

  ))
}

test "rebase: exclusive continue vs abort" {
  match build_and_parse(["rebase", "--continue", "--abort"]) {
    Err(msg) =>
      assert_true(
        msg.has_prefix("error: mutually exclusive options: --continue, --abort"),
      )
    Ok(_) => fail("expected error")
  }
}

test "tag: create annotated" {
  let result = build_and_parse(["tag", "-a", "v1.0", "-m", "Release 1.0"])
  inspect(result, content=(
    #|Ok("  command: tag\n  name: v1.0\n  annotate: true\n  message: \"Release 1.0\"\n")
  ))
}

test "tag: delete" {
  let result = build_and_parse(["tag", "-d", "v0.9"])
  inspect(result, content=(
    #|Ok("  command: tag\n  name: v0.9\n  delete: true\n")
  ))
}

test "tag: list" {
  let result = build_and_parse(["tag", "-l"])
  inspect(result, content=(
    #|Ok("  command: tag\n  list: true\n")

  ))
}

test "remote: add" {
  let result = build_and_parse([
    "remote", "add", "upstream", "https://example.com/repo.git",
  ])
  inspect(result, content=(
    #|Ok("  command: remote\n  subcommand: add\n  name: upstream\n  url: https://example.com/repo.git\n")
  ))
}

test "remote: add with fetch" {
  let result = build_and_parse([
    "remote", "add", "-f", "upstream", "https://example.com/repo.git",
  ])
  inspect(result, content=(
    #|Ok("  command: remote\n  subcommand: add\n  name: upstream\n  url: https://example.com/repo.git\n  fetch: true\n")
  ))
}

test "remote: remove" {
  let result = build_and_parse(["remote", "remove", "upstream"])
  inspect(result, content=(
    #|Ok("  command: remote\n  subcommand: remove\n  name: upstream\n")
  ))
}

test "remote: remove alias rm" {
  let result = build_and_parse(["remote", "rm", "upstream"])
  inspect(result, content=(
    #|Ok("  command: remote\n  subcommand: remove\n  name: upstream\n")
  ))
}

test "remote: rename" {
  let result = build_and_parse(["remote", "rename", "origin", "upstream"])
  inspect(result, content=(
    #|Ok("  command: remote\n  subcommand: rename\n  old: origin\n  new: upstream\n")
  ))
}

test "remote: show" {
  let result = build_and_parse(["remote", "show", "origin"])
  inspect(result, content=(
    #|Ok("  command: remote\n  subcommand: show\n  name: origin\n")
  ))
}

test "remote: missing subcommand" {
  match build_and_parse(["remote"]) {
    Err(msg) =>
      assert_true(msg.has_prefix("error: subcommand required"))
    Ok(_) => fail("expected error")
  }
}

test "stash: push" {
  let result = build_and_parse([
    "stash", "push", "-m", "WIP", "--include-untracked",
  ])
  inspect(result, content=(
    #|Ok("  command: stash\n  subcommand: push\n  message: \"WIP\"\n  include-untracked: true\n")
  ))
}

test "stash: push with files" {
  let result = build_and_parse(["stash", "push", "file1.txt", "file2.txt"])
  inspect(result, content=(
    #|Ok("  command: stash\n  subcommand: push\n  files: [\"file1.txt\", \"file2.txt\"]\n")
  ))
}

test "stash: pop" {
  let result = build_and_parse(["stash", "pop"])
  inspect(result, content=(
    #|Ok("  command: stash\n  subcommand: pop\n")

  ))
}

test "stash: pop with ref" {
  let result = build_and_parse(["stash", "pop", "stash@{1}"])
  inspect(result, content=(
    #|Ok("  command: stash\n  subcommand: pop\n  stash: stash@{1}\n")
  ))
}

test "stash: list" {
  let result = build_and_parse(["stash", "list"])
  inspect(result, content=(
    #|Ok("  command: stash\n  subcommand: list\n")
  ))
}

test "stash: drop" {
  let result = build_and_parse(["stash", "drop", "stash@{0}"])
  inspect(result, content=(
    #|Ok("  command: stash\n  subcommand: drop\n  stash: stash@{0}\n")
  ))
}

test "global: verbose count" {
  let result = build_and_parse(["-vvv", "status"])
  inspect(result, content=(
    #|Ok("  verbose: 3\n  command: status\n")
  ))
}

test "global: git-dir" {
  let result = build_and_parse(["--git-dir", "/tmp/.git", "status"])
  inspect(result, content=(
    #|Ok("  git-dir: /tmp/.git\n  command: status\n")
  ))
}

test "global: no-pager with subcommand" {
  let result = build_and_parse(["--no-pager", "log", "--oneline"])
  inspect(result, content=(
    #|Ok("  no-pager: true\n  command: log\n  oneline: true\n")
  ))
}

test "global: color always" {
  let result = build_and_parse(["--color", "always", "status"])
  inspect(result, content=(
    #|Ok("  color: always\n  command: status\n")
  ))
}

test "global: color implicit" {
  let result = build_and_parse(["--color", "diff"])
  inspect(result, content=(
    #|Ok("  color: always\n  command: diff\n")
  ))
}

test "help: top level" {
  let result = build_and_parse(["--help"])
  assert_true(result is Ok(_))
}

test "help: commit" {
  let result = build_and_parse(["commit", "--help"])
  assert_true(result is Ok(_))
}

test "help: remote" {
  let result = build_and_parse(["remote", "--help"])
  assert_true(result is Ok(_))
}

test "no arguments" {
  let result = build_and_parse([])
  inspect(result, content=(
    #|Ok("")
  ))
}

test "error: unknown option" {
  match build_and_parse(["--nonexistent"]) {
    Err(_) => ()
    Ok(_) => fail("expected error")
  }
}

test "stash: no subcommand" {
  let result = build_and_parse(["stash"])
  inspect(result, content=(
    #|Ok("  command: stash\n")
  ))
}

test "diff: dashdash" {
  let result = build_and_parse(["diff", "--", "file.txt"])
  inspect(result, content=(
    #|Ok("  command: diff\n  paths: [\"file.txt\"]\n")
  ))
}

test "add: dashdash" {
  let result = build_and_parse(["add", "--", "file.txt"])
  inspect(result, content=(
    #|Ok("  command: add\n  files: [\"file.txt\"]\n")
  ))
}

test "push: exclusive all vs delete" {
  match build_and_parse(["push", "--all", "--delete"]) {
    Err(msg) =>
      assert_true(
        msg.has_prefix("error: mutually exclusive options: --all, --delete"),
      )
    Ok(_) => fail("expected error")
  }
}

test "branch: force delete with -D" {
  let result = build_and_parse(["branch", "-D", "old-branch"])
  inspect(result, content=(
    #|Ok("  command: branch\n  name: old-branch\n  force-delete: true\n")
  ))
}
