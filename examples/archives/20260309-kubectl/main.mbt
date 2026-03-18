///|
/// mykubectl — A sample kubectl-like CLI built with kuu to exercise key APIs.
///
/// Demonstrates:
///   - sub() for subcommands (get, apply, delete, describe, logs, exec)
///   - Nested subcommands (config view / use-context / set-context)
///   - Global options with global=true (--kubeconfig, --context, --namespace)
///   - Same short option (-f) bound to different longs per subcommand
///     (--filename in get/apply/delete vs --follow in logs)
///   - choices + implicit_value (--output, --dry-run, --cascade, --validate)
///   - append_string for repeatable options (--filename)
///   - dashdash for exec (-- COMMAND [args...])
///   - flag with default=true + variation_false (--wait / --no-wait)
///   - variation_false for --no-headers
///   - exclusive constraints (--force vs --grace-period)
///   - required options (apply --filename)
///   - count (--v verbosity)
///   - serial positionals (config set-context)
///   - int_opt with in_range filter (--tail, --grace-period)
///   - rest positionals (get TYPE [NAME...])
fn main {
  let args = [
    "--namespace",
    "production",
    "get",
    "pods",
    "nginx-abc123",
    "--output",
    "json",
    "--show-labels",
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
  p.set_description(
    "mykubectl - A sample kubectl-like CLI built with kuu",
  )

  // ─── Global options ───

  let kubeconfig = p.string(
    name="kubeconfig",
    default="",
    global=true,
    description="Path to the kubeconfig file",
    value_name="PATH",
  )
  let context = p.string(
    name="context",
    default="",
    global=true,
    description="The name of the kubeconfig context to use",
    value_name="NAME",
  )
  let ns = p.string(
    name="namespace",
    default="default",
    shorts="n",
    global=true,
    description="Namespace scope for this request",
    value_name="NS",
  )
  let verbosity = p.int(
    name="v",
    default=0,
    global=true,
    description="Log verbosity level (0-9)",
    value_name="LEVEL",
    post=Some(@core.Filter::in_range(0, 9)),
  )

  // ─── Subcommand: get ───

  let get = p.sub(name="get", description="Display one or many resources")
  get.set_description("mykubectl get - Display one or many resources")
  // positional: TYPE [NAME...]
  let get_resources = get.rest(
    name="resources",
    description="Resource type and optional name(s)",
  )
  let get_output = get.string(
    name="output",
    default="",
    shorts="o",
    description="Output format",
    value_name="FORMAT",
    choices=["wide", "json", "yaml", "name"],
    implicit_value=Some(@core.Val("json")),
  )
  let get_selector = get.string(
    name="selector",
    default="",
    shorts="l",
    description="Label selector (e.g. app=nginx)",
    value_name="SELECTOR",
  )
  let get_field_selector = get.string(
    name="field-selector",
    default="",
    description="Field selector (e.g. status.phase=Running)",
    value_name="SELECTOR",
  )
  let get_all_namespaces = get.flag(
    name="all-namespaces",
    shorts="A",
    description="List across all namespaces",
  )
  let get_watch = get.flag(
    name="watch",
    shorts="w",
    description="Watch for changes",
  )
  let get_show_labels = get.flag(
    name="show-labels",
    description="Show labels as the last column",
  )
  let get_no_headers = get.flag(
    name="headers",
    default=true,
    description="Print column headers (--no-headers to hide)",
    variation_false=Some("no"),
  )
  let get_sort_by = get.string(
    name="sort-by",
    default="",
    description="Sort by JSONPath expression",
    value_name="JSONPATH",
  )
  let get_filename = get.append_string(
    name="filename",
    shorts="f",
    description="Filename(s) to identify resource",
    value_name="FILE",
  )
  let get_recursive = get.flag(
    name="recursive",
    shorts="R",
    description="Process directory recursively with -f",
  )
  let get_chunk_size = get.int(
    name="chunk-size",
    default=500,
    description="Chunk size for pagination",
    value_name="N",
  )

  // ─── Subcommand: apply ───

  let apply = p.sub(
    name="apply",
    description="Apply a configuration to a resource by file name",
  )
  apply.set_description(
    "mykubectl apply - Apply a configuration to a resource",
  )
  let apply_filename = apply.append_string(
    name="filename",
    shorts="f",
    description="Files that contain configurations to apply (required)",
    value_name="FILE",
  )
  apply.required(apply_filename.as_ref())
  let apply_recursive = apply.flag(
    name="recursive",
    shorts="R",
    description="Process directory recursively",
  )
  let apply_kustomize = apply.string(
    name="kustomize",
    default="",
    shorts="k",
    description="Kustomize directory",
    value_name="DIR",
  )
  let apply_selector = apply.string(
    name="selector",
    default="",
    shorts="l",
    description="Label selector to filter on",
    value_name="SELECTOR",
  )
  let apply_dry_run = apply.string(
    name="dry-run",
    default="none",
    description="Dry run mode",
    value_name="MODE",
    choices=["none", "client", "server"],
  )
  let apply_force = apply.flag(
    name="force",
    description="Force apply (delete and re-create)",
  )
  let apply_server_side = apply.flag(
    name="server-side",
    description="Server-side apply",
  )
  let apply_field_manager = apply.string(
    name="field-manager",
    default="",
    description="Field manager name",
    value_name="NAME",
  )
  let apply_prune = apply.flag(
    name="prune",
    description="Prune resources not in files",
  )
  let apply_validate = apply.string(
    name="validate",
    default="strict",
    description="Validation mode",
    value_name="MODE",
    choices=["strict", "warn", "ignore"],
  )
  let apply_output = apply.string(
    name="output",
    default="",
    shorts="o",
    description="Output format",
    value_name="FORMAT",
    choices=["json", "yaml", "name"],
  )

  // ─── Subcommand: delete ───

  let delete = p.sub(
    name="delete",
    description="Delete resources by file, stdin, resource/name, or label",
  )
  delete.set_description("mykubectl delete - Delete resources")
  let delete_resources = delete.rest(
    name="resources",
    description="Resource type and optional name(s)",
  )
  let delete_filename = delete.append_string(
    name="filename",
    shorts="f",
    description="Files containing resources to delete",
    value_name="FILE",
  )
  let delete_recursive = delete.flag(
    name="recursive",
    shorts="R",
    description="Process directory recursively",
  )
  let delete_selector = delete.string(
    name="selector",
    default="",
    shorts="l",
    description="Label selector",
    value_name="SELECTOR",
  )
  let delete_all = delete.flag(
    name="all",
    description="Delete all resources of the specified type",
  )
  let delete_all_namespaces = delete.flag(
    name="all-namespaces",
    shorts="A",
    description="All namespaces",
  )
  let delete_cascade = delete.string(
    name="cascade",
    default="background",
    description="Cascade deletion mode",
    value_name="MODE",
    choices=["background", "orphan", "foreground"],
  )
  let delete_grace_period = delete.int(
    name="grace-period",
    default=-1,
    description="Grace period in seconds (-1 for server default)",
    value_name="SECONDS",
  )
  let delete_force = delete.flag(
    name="force",
    description="Immediate deletion (grace-period=0)",
  )
  let delete_wait = delete.flag(
    name="wait",
    default=true,
    description="Wait for deletion to complete (--no-wait to skip)",
    variation_false=Some("no"),
  )
  let delete_dry_run = delete.string(
    name="dry-run",
    default="none",
    description="Dry run mode",
    value_name="MODE",
    choices=["none", "client", "server"],
  )
  let delete_output = delete.string(
    name="output",
    default="",
    shorts="o",
    description="Output format",
    value_name="FORMAT",
    choices=["json", "yaml", "name"],
  )
  let delete_ignore_not_found = delete.flag(
    name="ignore-not-found",
    description="Treat \"not found\" as success",
  )
  let delete_timeout = delete.string(
    name="timeout",
    default="0s",
    description="Wait timeout (e.g. 5m0s)",
    value_name="DURATION",
  )
  // --force implies --grace-period=0, so they are mutually exclusive
  delete.exclusive([delete_force.as_ref(), delete_grace_period.as_ref()])

  // ─── Subcommand: describe ───

  let describe = p.sub(
    name="describe",
    description="Show details of a specific resource",
  )
  describe.set_description(
    "mykubectl describe - Show details of a resource",
  )
  let describe_resources = describe.rest(
    name="resources",
    description="Resource type and optional name prefix",
  )
  let describe_selector = describe.string(
    name="selector",
    default="",
    shorts="l",
    description="Label selector",
    value_name="SELECTOR",
  )
  let describe_all_namespaces = describe.flag(
    name="all-namespaces",
    shorts="A",
    description="All namespaces",
  )
  let describe_filename = describe.append_string(
    name="filename",
    shorts="f",
    description="Files to find resources",
    value_name="FILE",
  )
  let describe_recursive = describe.flag(
    name="recursive",
    shorts="R",
    description="Process directory recursively",
  )
  let describe_show_events = describe.flag(
    name="show-events",
    default=true,
    description="Show events (--no-show-events to hide)",
    variation_false=Some("no"),
  )
  let describe_chunk_size = describe.int(
    name="chunk-size",
    default=500,
    description="Chunk size for pagination",
    value_name="N",
  )

  // ─── Subcommand: logs ───
  // Note: -f here means --follow, NOT --filename (different from get/apply/delete)

  let logs = p.sub(
    name="logs",
    description="Print the logs for a container in a pod",
  )
  logs.set_description("mykubectl logs - Print container logs")
  let logs_pod = logs.positional(name="pod", description="Pod name")
  logs.required(logs_pod.as_ref())
  let logs_container = logs.string(
    name="container",
    default="",
    shorts="c",
    description="Container name (multi-container pods)",
    value_name="NAME",
  )
  // -f is --follow here (NOT --filename like in other subcommands)
  let logs_follow = logs.flag(
    name="follow",
    shorts="f",
    description="Follow log output (stream)",
  )
  let logs_previous = logs.flag(
    name="previous",
    shorts="p",
    description="Previous terminated container logs",
  )
  let logs_since = logs.string(
    name="since",
    default="",
    description="Logs newer than a relative duration (e.g. 5s, 2m, 3h)",
    value_name="DURATION",
  )
  let logs_since_time = logs.string(
    name="since-time",
    default="",
    description="Logs after a specific date (RFC3339)",
    value_name="TIMESTAMP",
  )
  let logs_timestamps = logs.flag(
    name="timestamps",
    description="Include timestamps in output",
  )
  let logs_tail = logs.int(
    name="tail",
    default=-1,
    description="Lines of recent log to display (-1 for all)",
    value_name="LINES",
  )
  let logs_all_containers = logs.flag(
    name="all-containers",
    description="All containers in the pod",
  )
  let logs_prefix = logs.flag(
    name="prefix",
    description="Prefix each log line with pod/container name",
  )
  let logs_selector = logs.string(
    name="selector",
    default="",
    shorts="l",
    description="Label selector for multiple pods",
    value_name="SELECTOR",
  )
  let logs_max_log_requests = logs.int(
    name="max-log-requests",
    default=5,
    description="Max concurrent log requests",
    value_name="N",
    post=Some(@core.Filter::in_range(1, 100)),
  )

  // ─── Subcommand: exec ───
  // Uses dashdash to capture COMMAND [args...] after --

  let exec = p.sub(
    name="exec",
    description="Execute a command in a container",
  )
  exec.set_description("mykubectl exec - Execute a command in a container")
  let exec_pod = exec.positional(name="pod", description="Pod name")
  exec.required(exec_pod.as_ref())
  let exec_container = exec.string(
    name="container",
    default="",
    shorts="c",
    description="Container name",
    value_name="NAME",
  )
  let exec_stdin = exec.flag(
    name="stdin",
    shorts="i",
    description="Pass stdin to the container",
  )
  let exec_tty = exec.flag(
    name="tty",
    shorts="t",
    description="Stdin is a TTY",
  )
  let exec_quiet = exec.flag(
    name="quiet",
    shorts="q",
    description="Only print output from the remote session",
  )
  let exec_command = exec.dashdash()

  // ─── Subcommand: config (nested) ───

  let config = p.sub(
    name="config",
    description="Modify kubeconfig files",
  )
  config.set_description("mykubectl config - Modify kubeconfig files")
  config.require_cmd()

  // config view
  let config_view = config.sub(
    name="view",
    description="Display merged kubeconfig settings",
  )
  config_view.set_description(
    "mykubectl config view - Display kubeconfig",
  )
  let config_view_minify = config_view.flag(
    name="minify",
    description="Remove all information not used by current-context",
  )
  let config_view_flatten = config_view.flag(
    name="flatten",
    description="Flatten the resulting kubeconfig",
  )
  let config_view_output = config_view.string(
    name="output",
    default="yaml",
    shorts="o",
    description="Output format",
    value_name="FORMAT",
    choices=["yaml", "json"],
  )

  // config use-context
  let config_use_ctx = config.sub(
    name="use-context",
    description="Set the current-context in a kubeconfig file",
  )
  config_use_ctx.set_description(
    "mykubectl config use-context - Switch context",
  )
  let config_use_ctx_name = config_use_ctx.positional(
    name="context",
    description="Context name to switch to",
  )
  config_use_ctx.required(config_use_ctx_name.as_ref())

  // config set-context (serial: NAME --cluster --user --namespace)
  let config_set_ctx = config.sub(
    name="set-context",
    description="Set a context entry in kubeconfig",
  )
  config_set_ctx.set_description(
    "mykubectl config set-context - Set a context entry",
  )
  let config_set_ctx_name = config_set_ctx.positional(
    name="context",
    description="Context name",
  )
  config_set_ctx.required(config_set_ctx_name.as_ref())
  let config_set_ctx_cluster = config_set_ctx.string(
    name="cluster",
    default="",
    description="Cluster for the context",
    value_name="NAME",
  )
  let config_set_ctx_user = config_set_ctx.string(
    name="user",
    default="",
    description="User for the context",
    value_name="NAME",
  )
  let config_set_ctx_ns = config_set_ctx.string(
    name="namespace",
    default="",
    description="Default namespace for the context",
    value_name="NS",
  )

  // ─── Require subcommand ───

  p.require_cmd()

  // ─── Parse ───

  let result : Result[@core.ParseResult, @core.ParseError] = try? p.parse(
    args,
  )
  match result {
    Err(@core.HelpRequested(text)) => {
      println(text)
      Ok(())
    }
    Err(@core.ParseError(info)) => Err(info.to_string())
    Ok(result) => {
      // ─── Print global options ───

      println("=== Global Options ===")
      let kc = kubeconfig.get().unwrap_or("(not specified)")
      println("kubeconfig: " + kc)
      let ctx = context.get().unwrap_or("(not specified)")
      println("context: " + ctx)
      println("namespace: " + ns.get().unwrap())
      println("verbosity: " + verbosity.get().unwrap().to_string())
      println("")

      // ─── Subcommand dispatch ───

      match result.child("get") {
        Some(_) => {
          println("=== get ===")
          let res = get_resources.get().unwrap().to_string()
          println("resources: " + res)
          let out = get_output.get().unwrap_or("(default)")
          println("output: " + out)
          let sel = get_selector.get().unwrap_or("(none)")
          println("selector: " + sel)
          let fs = get_field_selector.get().unwrap_or("(none)")
          println("field-selector: " + fs)
          let an = get_all_namespaces.get().unwrap().to_string()
          println("all-namespaces: " + an)
          println("watch: " + get_watch.get().unwrap().to_string())
          let sl = get_show_labels.get().unwrap().to_string()
          println("show-labels: " + sl)
          let hdr = get_no_headers.get().unwrap().to_string()
          println("headers: " + hdr)
          let sb = get_sort_by.get().unwrap_or("(none)")
          println("sort-by: " + sb)
          let fn_ = get_filename.get().unwrap().to_string()
          println("filename: " + fn_)
          let rec = get_recursive.get().unwrap().to_string()
          println("recursive: " + rec)
          let cs = get_chunk_size.get().unwrap().to_string()
          println("chunk-size: " + cs)
        }
        _ => ()
      }

      match result.child("apply") {
        Some(_) => {
          println("=== apply ===")
          let fn_ = apply_filename.get().unwrap().to_string()
          println("filename: " + fn_)
          let rec = apply_recursive.get().unwrap().to_string()
          println("recursive: " + rec)
          let kust = apply_kustomize.get().unwrap_or("(none)")
          println("kustomize: " + kust)
          let sel = apply_selector.get().unwrap_or("(none)")
          println("selector: " + sel)
          println("dry-run: " + apply_dry_run.get().unwrap())
          let force = apply_force.get().unwrap().to_string()
          println("force: " + force)
          let ss = apply_server_side.get().unwrap().to_string()
          println("server-side: " + ss)
          let fm = apply_field_manager.get().unwrap_or("(none)")
          println("field-manager: " + fm)
          println("prune: " + apply_prune.get().unwrap().to_string())
          println("validate: " + apply_validate.get().unwrap())
          let out = apply_output.get().unwrap_or("(default)")
          println("output: " + out)
        }
        _ => ()
      }

      match result.child("delete") {
        Some(_) => {
          println("=== delete ===")
          let res = delete_resources.get().unwrap().to_string()
          println("resources: " + res)
          let fn_ = delete_filename.get().unwrap().to_string()
          println("filename: " + fn_)
          let rec = delete_recursive.get().unwrap().to_string()
          println("recursive: " + rec)
          let sel = delete_selector.get().unwrap_or("(none)")
          println("selector: " + sel)
          println("all: " + delete_all.get().unwrap().to_string())
          let an = delete_all_namespaces.get().unwrap().to_string()
          println("all-namespaces: " + an)
          println("cascade: " + delete_cascade.get().unwrap())
          let gp = delete_grace_period.get().unwrap().to_string()
          println("grace-period: " + gp)
          let force = delete_force.get().unwrap().to_string()
          println("force: " + force)
          println("wait: " + delete_wait.get().unwrap().to_string())
          println("dry-run: " + delete_dry_run.get().unwrap())
          let out = delete_output.get().unwrap_or("(default)")
          println("output: " + out)
          let inf = delete_ignore_not_found.get().unwrap().to_string()
          println("ignore-not-found: " + inf)
          let to = delete_timeout.get().unwrap_or("0s")
          println("timeout: " + to)
        }
        _ => ()
      }

      match result.child("describe") {
        Some(_) => {
          println("=== describe ===")
          let res = describe_resources.get().unwrap().to_string()
          println("resources: " + res)
          let sel = describe_selector.get().unwrap_or("(none)")
          println("selector: " + sel)
          let an = describe_all_namespaces.get().unwrap().to_string()
          println("all-namespaces: " + an)
          let fn_ = describe_filename.get().unwrap().to_string()
          println("filename: " + fn_)
          let rec = describe_recursive.get().unwrap().to_string()
          println("recursive: " + rec)
          let se = describe_show_events.get().unwrap().to_string()
          println("show-events: " + se)
          let cs = describe_chunk_size.get().unwrap().to_string()
          println("chunk-size: " + cs)
        }
        _ => ()
      }

      match result.child("logs") {
        Some(_) => {
          println("=== logs ===")
          println("pod: " + logs_pod.get().unwrap())
          let ctr = logs_container.get().unwrap_or("(default)")
          println("container: " + ctr)
          let fol = logs_follow.get().unwrap().to_string()
          println("follow: " + fol)
          let prev = logs_previous.get().unwrap().to_string()
          println("previous: " + prev)
          let since = logs_since.get().unwrap_or("(none)")
          println("since: " + since)
          let st = logs_since_time.get().unwrap_or("(none)")
          println("since-time: " + st)
          let ts = logs_timestamps.get().unwrap().to_string()
          println("timestamps: " + ts)
          let tail = logs_tail.get().unwrap().to_string()
          println("tail: " + tail)
          let ac = logs_all_containers.get().unwrap().to_string()
          println("all-containers: " + ac)
          let pfx = logs_prefix.get().unwrap().to_string()
          println("prefix: " + pfx)
          let sel = logs_selector.get().unwrap_or("(none)")
          println("selector: " + sel)
          let mlr = logs_max_log_requests.get().unwrap().to_string()
          println("max-log-requests: " + mlr)
        }
        _ => ()
      }

      match result.child("exec") {
        Some(_) => {
          println("=== exec ===")
          println("pod: " + exec_pod.get().unwrap())
          let ctr = exec_container.get().unwrap_or("(default)")
          println("container: " + ctr)
          let si = exec_stdin.get().unwrap().to_string()
          println("stdin: " + si)
          println("tty: " + exec_tty.get().unwrap().to_string())
          println("quiet: " + exec_quiet.get().unwrap().to_string())
          let cmd = exec_command.get().unwrap().to_string()
          println("command: " + cmd)
        }
        _ => ()
      }

      match result.child("config") {
        Some(config_result) => {
          println("=== config ===")
          match config_result.child("view") {
            Some(_) => {
              println("  === view ===")
              let min = config_view_minify.get().unwrap().to_string()
              println("  minify: " + min)
              let flat = config_view_flatten.get().unwrap().to_string()
              println("  flatten: " + flat)
              let out = config_view_output.get().unwrap()
              println("  output: " + out)
            }
            _ => ()
          }
          match config_result.child("use-context") {
            Some(_) => {
              println("  === use-context ===")
              let name = config_use_ctx_name.get().unwrap()
              println("  context: " + name)
            }
            _ => ()
          }
          match config_result.child("set-context") {
            Some(_) => {
              println("  === set-context ===")
              let name = config_set_ctx_name.get().unwrap()
              println("  context: " + name)
              let cl = config_set_ctx_cluster.get().unwrap_or("(none)")
              println("  cluster: " + cl)
              let user = config_set_ctx_user.get().unwrap_or("(none)")
              println("  user: " + user)
              let ns = config_set_ctx_ns.get().unwrap_or("(none)")
              println("  namespace: " + ns)
            }
            _ => ()
          }
        }
        _ => ()
      }
      Ok(())
    }
  }
}
