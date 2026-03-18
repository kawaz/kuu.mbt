///|
/// mygit — A sample git-like CLI built with kuu to exercise all public APIs.
///
/// 2026-03-08 version: exercises the latest kuu API including:
///   - sub() API (no Ref boilerplate)
///   - Opt::get() (direct access)
///   - flag, string_opt, int_opt, count, append_string, append_int
///   - positional, rest, serial, never
///   - dashdash, append_dashdash
///   - exclusive, required
///   - variations (variation_reset, variation_unset)
///   - default_fn
///   - choices + implicit_value
///   - post filter: trim, non_empty, one_of, in_range
///   - hidden options
///   - require_cmd (auto help on missing subcommand)
///   - nested subcommands (remote add/remove, stash push/pop/list)
fn main {
  let args = [
    "-vv",
    "--color",
    "remote",
    "add",
    "--fetch",
    "origin",
    "https://github.com/example/repo",
  ]
  println("Parsing: " + args.to_string())
  println("")
  let result = run(args)
  match result {
    Ok(_) => ()
    Err(msg) => println(msg)
  }
}

///|
fn run(args : Array[String]) -> Result[Unit, String] {
  // ─── Root parser ───

  let p = @core.Parser::new()
  p.set_description("mygit - A sample git-like CLI built with kuu")

  // ─── Global options ───

  // count: -v / -vv / -vvv (with variation_reset)
  let verbose = p.count(
    name="verbose",
    shorts="v",
    global=true,
    description="Increase verbosity (-v, -vv, -vvv)",
    variation_reset=Some("no"),
  )
  // flag: --quiet / -q
  let quiet = p.flag(
    name="quiet",
    shorts="q",
    global=true,
    description="Suppress output",
  )
  // exclusive: --verbose and --quiet cannot be used together
  p.exclusive([verbose.as_ref(), quiet.as_ref()])
  // string_opt with choices + implicit_value
  let color = p.string(
    name="color",
    default="auto",
    global=true,
    description="When to use colors",
    choices=["always", "never", "auto"],
    implicit_value=Some(@core.Val("always")),
  )
  // hidden flag (not shown in --help)
  let _debug = p.flag(
    name="debug-internal",
    hidden=true,
    global=true,
    description="Internal debug flag",
  )

  // ─── Subcommand: clone ───

  let clone = p.sub(name="clone", description="Clone a repository")
  clone.set_description("mygit clone - Clone a repository")
  let clone_url = clone.positional(name="url", description="Repository URL")
  clone.required(clone_url.as_ref())
  let clone_dir = clone.positional(
    name="directory",
    description="Target directory",
  )
  let clone_depth = clone.int(
    name="depth",
    default=0,
    description="Shallow clone with N commits",
    value_name="N",
  )
  let clone_branch = clone.string(
    name="branch",
    default="",
    shorts="b",
    description="Checkout this branch",
    value_name="BRANCH",
  )
  let clone_bare = clone.flag(
    name="bare",
    description="Create a bare repository",
  )

  // ─── Subcommand: commit ───

  let commit = p.sub(name="commit", description="Record changes")
  commit.set_description("mygit commit - Record changes")
  let commit_message = commit.string(
    name="message",
    default="",
    shorts="m",
    description="Commit message",
    value_name="MSG",
    post=Some(@core.Filter::trim().then(@core.Filter::non_empty())),
  )
  commit.required(commit_message.as_ref())
  let commit_all = commit.flag(
    name="all",
    shorts="a",
    description="Stage all modified files",
  )
  let commit_amend = commit.flag(
    name="amend",
    description="Amend the previous commit",
  )
  // flag with default=true -> --no-verify to negate
  let commit_verify = commit.flag(
    name="verify",
    default=true,
    description="Run pre-commit hooks (--no-verify to skip)",
    variation_false=Some("no"),
  )
  // flag with variation_unset: --reset-author
  let commit_reset_author = commit.flag(
    name="author-date-is-committer-date",
    description="Override author date with committer date",
    variation_unset=Some("no"),
  )

  // ─── Subcommand: log ───

  let log = p.sub(name="log", description="Show commit logs")
  log.set_description("mygit log - Show commit logs")
  let log_oneline = log.flag(
    name="oneline",
    description="One line per commit",
  )
  let log_max_count = log.int(
    name="max-count",
    default=0,
    shorts="n",
    description="Limit number of commits",
    value_name="N",
  )
  // append_string: repeatable --author
  let log_authors = log.append_string(
    name="author",
    description="Filter by author (repeatable)",
    value_name="PATTERN",
  )
  // string_opt with choices: --format
  let log_format = log.string(
    name="format",
    default="medium",
    description="Pretty-print format",
    choices=["oneline", "short", "medium", "full", "fuller", "reference", "raw"],
  )
  let log_graph = log.flag(
    name="graph",
    description="Draw text-based graph of commit history",
  )
  // append_string for path filtering
  let log_paths = log.rest(
    name="paths",
    description="Limit to paths",
  )

  // ─── Subcommand: add ───

  let add = p.sub(name="add", description="Add file contents to the index")
  add.set_description("mygit add - Stage files")
  let add_force = add.flag(
    name="force",
    shorts="f",
    description="Allow ignored files",
  )
  let add_dry_run = add.flag(
    name="dry-run",
    aliases=["dryrun"],
    description="Don't actually add files",
  )
  let add_patch = add.flag(
    name="patch",
    shorts="p",
    description="Interactively stage hunks",
  )
  let add_files = add.rest(name="files", description="Files to add")

  // ─── Subcommand: push ───

  let push = p.sub(name="push", description="Update remote refs")
  push.set_description("mygit push - Push to remote")
  let push_remote = push.positional(
    name="remote",
    description="Remote name",
  )
  let push_branch = push.positional(
    name="branch",
    description="Branch name",
  )
  let push_force = push.flag(
    name="force",
    shorts="f",
    description="Force push",
  )
  let push_force_lease = push.flag(
    name="force-with-lease",
    description="Safer force push",
  )
  push.exclusive([push_force.as_ref(), push_force_lease.as_ref()])
  let push_tags = push.flag(
    name="tags",
    description="Push all tags",
  )
  let push_set_upstream = push.flag(
    name="set-upstream",
    shorts="u",
    description="Set upstream for the branch",
  )
  let push_delete = push.flag(
    name="delete",
    shorts="d",
    description="Delete remote branch",
  )

  // ─── Subcommand: pull ───

  let pull = p.sub(name="pull", description="Fetch and merge")
  pull.set_description("mygit pull - Fetch and integrate remote changes")
  let pull_remote = pull.positional(
    name="remote",
    description="Remote name",
  )
  let pull_branch = pull.positional(
    name="branch",
    description="Branch name",
  )
  let pull_rebase = pull.flag(
    name="rebase",
    shorts="r",
    description="Rebase instead of merge",
  )
  let pull_ff_only = pull.flag(
    name="ff-only",
    description="Only fast-forward merges",
  )
  pull.exclusive([pull_rebase.as_ref(), pull_ff_only.as_ref()])

  // ─── Subcommand: branch ───

  let branch = p.sub(name="branch", description="List, create, or delete branches")
  branch.set_description("mygit branch - Branch management")
  let branch_name = branch.positional(
    name="name",
    description="Branch name",
  )
  let branch_delete = branch.flag(
    name="delete",
    shorts="d",
    description="Delete a branch",
  )
  let branch_force_delete = branch.flag(
    name="force-delete",
    aliases=["D"],
    description="Force delete a branch",
  )
  branch.exclusive([branch_delete.as_ref(), branch_force_delete.as_ref()])
  let branch_list = branch.flag(
    name="list",
    shorts="l",
    description="List branches",
  )
  let branch_all = branch.flag(
    name="all",
    shorts="a",
    description="Show both local and remote branches",
  )
  let branch_move = branch.flag(
    name="move",
    shorts="m",
    description="Move/rename a branch",
  )

  // ─── Subcommand: checkout ───

  let checkout = p.sub(name="checkout", description="Switch branches or restore files")
  checkout.set_description("mygit checkout - Switch branches or restore files")
  let checkout_target = checkout.positional(
    name="branch",
    description="Branch or commit to checkout",
  )
  let checkout_create = checkout.string(
    name="create",
    default="",
    shorts="b",
    description="Create and checkout a new branch",
    value_name="BRANCH",
  )
  let checkout_force = checkout.flag(
    name="force",
    shorts="f",
    description="Force checkout (discard local changes)",
  )
  let checkout_files = checkout.dashdash()

  // ─── Subcommand: diff ───

  let diff = p.sub(name="diff", description="Show changes between commits")
  diff.set_description("mygit diff - Show differences")
  let diff_staged = diff.flag(
    name="staged",
    aliases=["cached"],
    description="Show staged changes",
  )
  let diff_stat = diff.flag(
    name="stat",
    description="Show diffstat only",
  )
  // int_opt with implicit_value: --unified[=N]
  let diff_context = diff.int(
    name="unified",
    default=3,
    shorts="U",
    description="Lines of context",
    value_name="N",
    implicit_value=Some(@core.Val(3)),
  )
  let diff_name_only = diff.flag(
    name="name-only",
    description="Show only names of changed files",
  )
  let diff_paths = diff.rest(name="paths", description="Limit to paths")

  // ─── Subcommand: status ───

  let status = p.sub(name="status", description="Show working tree status")
  status.set_description("mygit status - Show status")
  let status_short = status.flag(
    name="short",
    shorts="s",
    description="Short format output",
  )
  let status_branch = status.flag(
    name="branch",
    shorts="b",
    description="Show branch info",
  )
  let status_porcelain = status.flag(
    name="porcelain",
    description="Machine-readable output",
  )

  // ─── Subcommand: tag ───

  let tag = p.sub(
    name="tag",
    description="Create, list, delete or verify tags",
  )
  tag.set_description("mygit tag - Manage tags")
  let tag_list = tag.flag(name="list", shorts="l", description="List tags")
  let tag_delete = tag.flag(
    name="delete",
    shorts="d",
    description="Delete a tag",
  )
  let tag_annotate = tag.flag(
    name="annotate",
    shorts="a",
    description="Make an annotated tag",
  )
  tag.exclusive([tag_list.as_ref(), tag_delete.as_ref(), tag_annotate.as_ref()])
  let tag_message = tag.string(
    name="message",
    default="",
    shorts="m",
    description="Tag message",
    value_name="MSG",
  )
  let tag_name = tag.positional(name="tagname", description="Tag name")

  // ─── Subcommand: remote (nested) ───

  let remote = p.sub(name="remote", description="Manage tracked repositories")
  remote.set_description("mygit remote - Manage remotes")
  remote.require_cmd()
  // nested: remote add <name> <url>
  let remote_add = remote.sub(name="add", description="Add a remote")
  remote_add.set_description("mygit remote add - Add a new remote")
  let remote_add_fetch = remote_add.flag(
    name="fetch",
    shorts="f",
    description="Fetch after adding",
  )
  let mut remote_add_name : @core.Opt[String]? = None
  let mut remote_add_url : @core.Opt[String]? = None
  remote_add.serial(setup=fn(sub) {
    remote_add_name = Some(
      sub.positional(name="name", description="Remote name"),
    )
    remote_add_url = Some(
      sub.positional(name="url", description="Remote URL"),
    )
    sub.never()
  })
  // nested: remote remove <name>
  let remote_remove = remote.sub(name="remove", description="Remove a remote")
  remote_remove.set_description("mygit remote remove - Remove a remote")
  let remote_remove_name = remote_remove.positional(
    name="name",
    description="Remote name",
  )
  remote_remove.required(remote_remove_name.as_ref())
  // nested: remote rename <old> <new>
  let remote_rename = remote.sub(name="rename", description="Rename a remote")
  remote_rename.set_description("mygit remote rename - Rename a remote")
  let mut remote_rename_old : @core.Opt[String]? = None
  let mut remote_rename_new : @core.Opt[String]? = None
  remote_rename.serial(setup=fn(sub) {
    remote_rename_old = Some(
      sub.positional(name="old", description="Old remote name"),
    )
    remote_rename_new = Some(
      sub.positional(name="new", description="New remote name"),
    )
    sub.never()
  })

  // ─── Subcommand: stash (nested) ───

  let stash = p.sub(name="stash", description="Stash changes")
  stash.set_description("mygit stash - Stash management")
  stash.require_cmd()
  // stash push: dashdash=false to capture -- as Opt
  let stash_push = stash.sub(
    name="push",
    description="Save local modifications",
    dashdash=false,
  )
  stash_push.set_description("mygit stash push - Save to stash")
  let stash_push_message = stash_push.string(
    name="message",
    default="",
    shorts="m",
    description="Stash message",
    value_name="MSG",
  )
  let stash_push_files = stash_push.dashdash()
  // stash pop: int_opt with implicit_value
  let stash_pop = stash.sub(name="pop", description="Apply and remove stash")
  stash_pop.set_description("mygit stash pop - Pop from stash")
  let stash_pop_index = stash_pop.int(
    name="index",
    default=0,
    description="Stash index",
    value_name="N",
    implicit_value=Some(@core.Val(0)),
  )
  // stash list: no options
  let _stash_list = stash.sub(name="list", description="List stash entries")
  // stash drop
  let stash_drop = stash.sub(name="drop", description="Drop a stash entry")
  stash_drop.set_description("mygit stash drop - Drop a stash entry")
  let stash_drop_index = stash_drop.int(
    name="index",
    default=0,
    description="Stash index to drop",
    value_name="N",
    implicit_value=Some(@core.Val(0)),
  )

  // ─── Subcommand: config ───

  let config = p.sub(name="config", description="Get and set options")
  config.set_description("mygit config - Configuration management")
  let config_global = config.flag(
    name="global",
    description="Use global config",
  )
  let config_local = config.flag(
    name="local",
    description="Use repository config",
  )
  let config_system = config.flag(
    name="system",
    description="Use system config",
  )
  config.exclusive([
    config_global.as_ref(),
    config_local.as_ref(),
    config_system.as_ref(),
  ])
  let mut config_key : @core.Opt[String]? = None
  let mut config_value : @core.Opt[String]? = None
  config.serial(setup=fn(sub) {
    config_key = Some(sub.positional(name="key", description="Config key"))
    config_value = Some(
      sub.positional(name="value", description="Config value"),
    )
  })

  // ─── Require subcommand ───

  p.require_cmd()

  // ─── Parse ───

  let result : Result[@core.ParseResult, @core.ParseError] = try? p.parse(args)
  match result {
    Err(@core.HelpRequested(text)) => {
      println(text)
      Ok(())
    }
    Err(@core.ParseError(info)) => Err(info.to_string())
    Ok(result) => {
      // ─── Print results ───

      println("=== Global Options ===")
      println("verbose: " + verbose.get().unwrap().to_string())
      println("quiet: " + quiet.get().unwrap().to_string())
      println("color: " + color.get().unwrap())
      println("")

      // ─── Subcommand dispatch ───

      match result.child("clone") {
        Some(_) => {
          println("=== clone ===")
          println("url: " + clone_url.get().unwrap())
          println("dir: " + clone_dir.get().unwrap_or("(not specified)"))
          println("depth: " + clone_depth.get().unwrap().to_string())
          let bv = clone_branch.get().unwrap_or("(not specified)")
          println("branch: " + bv)
          println("bare: " + clone_bare.get().unwrap().to_string())
        }
        _ => ()
      }

      match result.child("commit") {
        Some(_) => {
          println("=== commit ===")
          println("message: " + commit_message.get().unwrap())
          println("all: " + commit_all.get().unwrap().to_string())
          println("amend: " + commit_amend.get().unwrap().to_string())
          println("verify: " + commit_verify.get().unwrap().to_string())
          let rad = commit_reset_author.get().unwrap().to_string()
          println("author-date-is-committer-date: " + rad)
        }
        _ => ()
      }

      match result.child("log") {
        Some(_) => {
          println("=== log ===")
          println("oneline: " + log_oneline.get().unwrap().to_string())
          let mc = log_max_count.get().unwrap().to_string()
          println("max-count: " + mc)
          println("authors: " + log_authors.get().unwrap().to_string())
          println("format: " + log_format.get().unwrap())
          println("graph: " + log_graph.get().unwrap().to_string())
          println("paths: " + log_paths.get().unwrap().to_string())
        }
        _ => ()
      }

      match result.child("add") {
        Some(_) => {
          println("=== add ===")
          println("files: " + add_files.get().unwrap().to_string())
          println("force: " + add_force.get().unwrap().to_string())
          println("dry-run: " + add_dry_run.get().unwrap().to_string())
          println("patch: " + add_patch.get().unwrap().to_string())
        }
        _ => ()
      }

      match result.child("push") {
        Some(_) => {
          println("=== push ===")
          let pr = push_remote.get().unwrap_or("(not specified)")
          println("remote: " + pr)
          let pb = push_branch.get().unwrap_or("(not specified)")
          println("branch: " + pb)
          println("force: " + push_force.get().unwrap().to_string())
          let pfl = push_force_lease.get().unwrap().to_string()
          println("force-with-lease: " + pfl)
          println("tags: " + push_tags.get().unwrap().to_string())
          let psu = push_set_upstream.get().unwrap().to_string()
          println("set-upstream: " + psu)
          println("delete: " + push_delete.get().unwrap().to_string())
        }
        _ => ()
      }

      match result.child("pull") {
        Some(_) => {
          println("=== pull ===")
          let pr = pull_remote.get().unwrap_or("(not specified)")
          println("remote: " + pr)
          let pb = pull_branch.get().unwrap_or("(not specified)")
          println("branch: " + pb)
          println("rebase: " + pull_rebase.get().unwrap().to_string())
          println("ff-only: " + pull_ff_only.get().unwrap().to_string())
        }
        _ => ()
      }

      match result.child("branch") {
        Some(_) => {
          println("=== branch ===")
          let bn = branch_name.get().unwrap_or("(not specified)")
          println("name: " + bn)
          println("delete: " + branch_delete.get().unwrap().to_string())
          let bfd = branch_force_delete.get().unwrap().to_string()
          println("force-delete: " + bfd)
          println("list: " + branch_list.get().unwrap().to_string())
          println("all: " + branch_all.get().unwrap().to_string())
          println("move: " + branch_move.get().unwrap().to_string())
        }
        _ => ()
      }

      match result.child("checkout") {
        Some(_) => {
          println("=== checkout ===")
          let ct = checkout_target.get().unwrap_or("(not specified)")
          println("target: " + ct)
          let cc = checkout_create.get().unwrap_or("(not specified)")
          println("create: " + cc)
          let cf = checkout_force.get().unwrap().to_string()
          println("force: " + cf)
          println("files: " + checkout_files.get().unwrap().to_string())
        }
        _ => ()
      }

      match result.child("diff") {
        Some(_) => {
          println("=== diff ===")
          println("staged: " + diff_staged.get().unwrap().to_string())
          println("stat: " + diff_stat.get().unwrap().to_string())
          let dc = diff_context.get().unwrap().to_string()
          println("unified: " + dc)
          let dno = diff_name_only.get().unwrap().to_string()
          println("name-only: " + dno)
          println("paths: " + diff_paths.get().unwrap().to_string())
        }
        _ => ()
      }

      match result.child("status") {
        Some(_) => {
          println("=== status ===")
          println("short: " + status_short.get().unwrap().to_string())
          println("branch: " + status_branch.get().unwrap().to_string())
          let sp = status_porcelain.get().unwrap().to_string()
          println("porcelain: " + sp)
        }
        _ => ()
      }

      match result.child("tag") {
        Some(_) => {
          println("=== tag ===")
          println("list: " + tag_list.get().unwrap().to_string())
          println("delete: " + tag_delete.get().unwrap().to_string())
          let ta = tag_annotate.get().unwrap().to_string()
          println("annotate: " + ta)
          let tm = tag_message.get().unwrap_or("(none)")
          println("message: " + tm)
          println("tagname: " + tag_name.get().unwrap_or("(none)"))
        }
        _ => ()
      }

      match result.child("remote") {
        Some(remote_result) => {
          println("=== remote ===")
          match remote_result.child("add") {
            Some(_) => {
              let ran = remote_add_name.unwrap().get().unwrap()
              println("  add name: " + ran)
              let rau = remote_add_url.unwrap().get().unwrap()
              println("  add url: " + rau)
              let raf = remote_add_fetch.get().unwrap().to_string()
              println("  add fetch: " + raf)
            }
            _ => ()
          }
          match remote_result.child("remove") {
            Some(_) => {
              let rrn = remote_remove_name.get().unwrap()
              println("  remove: " + rrn)
            }
            _ => ()
          }
          match remote_result.child("rename") {
            Some(_) => {
              let old = remote_rename_old.unwrap().get().unwrap()
              let new_ = remote_rename_new.unwrap().get().unwrap()
              println("  rename: " + old + " -> " + new_)
            }
            _ => ()
          }
        }
        _ => ()
      }

      match result.child("stash") {
        Some(stash_result) => {
          println("=== stash ===")
          match stash_result.child("push") {
            Some(_) => {
              let sm = stash_push_message.get().unwrap_or("(none)")
              println("  message: " + sm)
              let sf = stash_push_files.get().unwrap().to_string()
              println("  files: " + sf)
            }
            _ => ()
          }
          match stash_result.child("pop") {
            Some(_) => {
              let si = stash_pop_index.get().unwrap().to_string()
              println("  index: " + si)
            }
            _ => ()
          }
          match stash_result.child("list") {
            Some(_) => println("  list (no options)")
            _ => ()
          }
          match stash_result.child("drop") {
            Some(_) => {
              let di = stash_drop_index.get().unwrap().to_string()
              println("  drop index: " + di)
            }
            _ => ()
          }
        }
        _ => ()
      }

      match result.child("config") {
        Some(_) => {
          println("=== config ===")
          println("global: " + config_global.get().unwrap().to_string())
          println("local: " + config_local.get().unwrap().to_string())
          println("system: " + config_system.get().unwrap().to_string())
          let ck = config_key.unwrap().get().unwrap_or("(not specified)")
          println("key: " + ck)
          let cv = config_value.unwrap().get().unwrap_or("(not specified)")
          println("value: " + cv)
        }
        _ => ()
      }
      Ok(())
    }
  }
}
