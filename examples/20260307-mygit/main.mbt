///|
/// mygit — A sample git-like CLI built with kuu to exercise all public APIs.
///
/// Uses sub() API — no Ref boilerplate needed.
fn main {
  let args = [
    "-vv", "--color", "remote", "add", "origin", "https://github.com/example/repo",
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

  // count: -v / -vv / -vvv
  let verbose = p.count(
    name="verbose",
    short='v',
    global=true,
    description="Increase verbosity (-v, -vv, -vvv)",
  )
  // flag: --quiet / -q
  let quiet = p.flag(
    name="quiet",
    short='q',
    global=true,
    description="Suppress output",
  )
  // exclusive: --verbose and --quiet cannot be used together
  p.exclusive([verbose.as_ref(), quiet.as_ref()])
  // string_opt with choices + implicit_value
  let color = p.string_opt(
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
  let clone_depth = clone.int_opt(
    name="depth",
    default=0,
    description="Shallow clone with N commits",
    value_name="N",
  )
  let clone_branch = clone.string_opt(
    name="branch",
    default="",
    short='b',
    description="Checkout this branch",
    value_name="BRANCH",
  )

  // ─── Subcommand: commit ───

  let commit = p.sub(name="commit", description="Record changes")
  commit.set_description("mygit commit - Record changes")
  // string_opt with post filter: trim + non_empty validation
  let commit_message = commit.string_opt(
    name="message",
    default="",
    short='m',
    description="Commit message",
    value_name="MSG",
    post=Some(@core.Filter::trim().then(@core.Filter::non_empty())),
  )
  commit.required(commit_message.as_ref())
  let commit_all = commit.flag(
    name="all",
    short='a',
    description="Stage all modified files",
  )
  let commit_amend = commit.flag(
    name="amend",
    description="Amend the previous commit",
  )
  // flag with default=true → --no-verify to negate
  let commit_verify = commit.flag(
    name="verify",
    default=true,
    description="Run pre-commit hooks (--no-verify to skip)",
  )

  // ─── Subcommand: log ───

  let log = p.sub(name="log", description="Show commit logs")
  log.set_description("mygit log - Show commit logs")
  let log_oneline = log.flag(name="oneline", description="One line per commit")
  let log_max_count = log.int_opt(
    name="max-count",
    default=0,
    short='n',
    description="Limit number of commits",
    value_name="N",
  )
  // append_string: repeatable --author
  let log_authors = log.append_string(
    name="author",
    description="Filter by author (repeatable)",
    value_name="PATTERN",
  )

  // ─── Subcommand: add ───

  let add = p.sub(name="add", description="Add file contents to the index")
  add.set_description("mygit add - Stage files")
  let add_force = add.flag(
    name="force",
    short='f',
    description="Allow ignored files",
  )
  // flag with aliases
  let add_dry_run = add.flag(
    name="dry-run",
    aliases=["dryrun"],
    description="Don't actually add files",
  )
  // rest: <files...>
  let add_files = add.rest(name="files", description="Files to add")

  // ─── Subcommand: tag ───

  let tag = p.sub(name="tag", description="Create, list, delete or verify tags")
  tag.set_description("mygit tag - Manage tags")
  let tag_list = tag.flag(name="list", short='l', description="List tags")
  let tag_delete = tag.flag(
    name="delete",
    short='d',
    description="Delete a tag",
  )
  let tag_annotate = tag.flag(
    name="annotate",
    short='a',
    description="Make an annotated tag",
  )
  tag.exclusive([tag_list.as_ref(), tag_delete.as_ref(), tag_annotate.as_ref()])
  let tag_message = tag.string_opt(
    name="message",
    default="",
    short='m',
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
  let mut remote_add_name : @core.Opt[String]? = None
  let mut remote_add_url : @core.Opt[String]? = None
  remote_add.serial(setup=fn(sub) {
    remote_add_name = Some(
      sub.positional(name="name", description="Remote name"),
    )
    remote_add_url = Some(sub.positional(name="url", description="Remote URL"))
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
  let stash_push_message = stash_push.string_opt(
    name="message",
    default="",
    short='m',
    description="Stash message",
    value_name="MSG",
  )
  let stash_push_files = stash_push.dashdash()
  // stash pop: int_opt with implicit_value
  let stash_pop = stash.sub(name="pop", description="Apply and remove stash")
  stash_pop.set_description("mygit stash pop - Pop from stash")
  let stash_pop_index = stash_pop.int_opt(
    name="index",
    default=0,
    description="Stash index",
    value_name="N",
    implicit_value=Some(@core.Val(0)),
  )
  // stash list: no options
  let _stash_list = stash.sub(name="list", description="List stash entries")

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
  config.exclusive([config_global.as_ref(), config_local.as_ref()])
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
      // With sub(), opt.get() works directly — no Ref unwrap chain.

      match result.child("clone") {
        Some(_) => {
          println("=== clone ===")
          println("url: " + clone_url.get().unwrap())
          println("dir: " + clone_dir.get().unwrap_or("(not specified)"))
          println("depth: " + clone_depth.get().unwrap().to_string())
          println("branch: " + clone_branch.get().unwrap_or("(not specified)"))
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
        }
        _ => ()
      }

      match result.child("log") {
        Some(_) => {
          println("=== log ===")
          println("oneline: " + log_oneline.get().unwrap().to_string())
          println("max-count: " + log_max_count.get().unwrap().to_string())
          println("authors: " + log_authors.get().unwrap().to_string())
        }
        _ => ()
      }

      match result.child("add") {
        Some(_) => {
          println("=== add ===")
          println("files: " + add_files.get().unwrap().to_string())
          println("force: " + add_force.get().unwrap().to_string())
          println("dry-run: " + add_dry_run.get().unwrap().to_string())
        }
        _ => ()
      }

      match result.child("tag") {
        Some(_) => {
          println("=== tag ===")
          println("list: " + tag_list.get().unwrap().to_string())
          println("delete: " + tag_delete.get().unwrap().to_string())
          println("annotate: " + tag_annotate.get().unwrap().to_string())
          println("message: " + tag_message.get().unwrap_or("(none)"))
          println("tagname: " + tag_name.get().unwrap_or("(none)"))
        }
        _ => ()
      }

      match result.child("remote") {
        Some(remote_result) => {
          println("=== remote ===")
          match remote_result.child("add") {
            Some(_) => {
              println("  add name: " + remote_add_name.unwrap().get().unwrap())
              println("  add url: " + remote_add_url.unwrap().get().unwrap())
            }
            _ => ()
          }
          match remote_result.child("remove") {
            Some(_) => println("  remove: " + remote_remove_name.get().unwrap())
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
              println(
                "  message: " + stash_push_message.get().unwrap_or("(none)"),
              )
              println("  files: " + stash_push_files.get().unwrap().to_string())
            }
            _ => ()
          }
          match stash_result.child("pop") {
            Some(_) =>
              println("  index: " + stash_pop_index.get().unwrap().to_string())
            _ => ()
          }
          match stash_result.child("list") {
            Some(_) => println("  list (no options)")
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
          println(
            "key: " + config_key.unwrap().get().unwrap_or("(not specified)"),
          )
          let v = config_value.unwrap().get().unwrap_or("(not specified)")
          println("value: " + v)
        }
        _ => ()
      }
      Ok(())
    }
  }
}
