///|
/// Docker CLI parser — build_and_parse builds the complete parser tree and parses args.
///
/// Structure:
///   docker [GLOBAL] container {run|ls|exec|stop|rm|logs} [OPTS] [ARGS]
///   docker [GLOBAL] image {build|ls|pull|push} [OPTS] [ARGS]
///   docker [GLOBAL] compose [-f FILE] {up|down} [OPTS] [ARGS]
///   docker [GLOBAL] network {create|ls|rm} [OPTS] [ARGS]
///   docker [GLOBAL] volume {create|ls|rm} [OPTS] [ARGS]
///   docker [GLOBAL] {run|ps|build|exec|pull|push} (shortcuts)

// ════════════════════════════════════════════════════════════════════
// Helpers
// ════════════════════════════════════════════════════════════════════

// Design rationale: kuu の値プリミティブ (string/int) は shorts/global を持たない。
// shorts や global が必要な場合は custom コンビネータに pre filter を渡す。
// トップレベル定数で1回だけ生成し、全箇所で共有する。

///|
/// Identity filter chain for custom[String] (string equivalent with shorts/global).
let str_pre : @core.FilterChain[String, String] = @core.Filter::map(fn(s) { s })

///|
/// Parse-int filter chain for custom[Int] (int equivalent with shorts/global).
let int_pre : @core.FilterChain[String, Int] = @core.Filter::parse_int()

///|
/// Append a line "  {key}: {value}" to buf if value is truthy.
fn write_flag(buf : StringBuilder, key : String, opt : @core.Opt[Bool]) -> Unit {
  if opt.get().unwrap() {
    buf.write_string("    " + key + ": true\n")
  }
}

///|
/// Append "    {key}: {value}\n" to buf if the opt is set and has a non-empty value.
/// Works for both named options and positionals (positionals are is_set when parsed).
fn write_str(
  buf : StringBuilder,
  key : String,
  opt : @core.Opt[String],
) -> Unit {
  if opt.is_set() {
    match opt.get() {
      Some(v) => if v != "" { buf.write_string("    " + key + ": " + v + "\n") }
      None => ()
    }
  }
}

///|
/// Append a line "  {key}: {value}" to buf if the int opt is set.
fn write_int(buf : StringBuilder, key : String, opt : @core.Opt[Int]) -> Unit {
  if opt.is_set() {
    buf.write_string(
      "    " + key + ": " + opt.get().unwrap().to_string() + "\n",
    )
  }
}

///|
/// Append a line "  {key}: [values]" to buf if the array is non-empty.
fn write_arr(
  buf : StringBuilder,
  key : String,
  opt : @core.Opt[Array[String]],
) -> Unit {
  match opt.get() {
    Some(v) =>
      if v.length() > 0 {
        buf.write_string("    " + key + ": " + v.to_string() + "\n")
      }
    None => ()
  }
}

// ════════════════════════════════════════════════════════════════════
// Setup functions (shared between management commands and shortcuts)
// ════════════════════════════════════════════════════════════════════

///|
fn setup_run_options(run : @core.Parser) -> Unit {
  run.set_description("mydocker run - Create and run a new container")
  // Flags
  let _rm = run.flag(
    name="rm",
    description="Automatically remove the container when it exits",
  )
  let _interactive = run.flag(
    name="interactive",
    shorts="i",
    description="Keep STDIN open even if not attached",
  )
  let _tty = run.flag(
    name="tty",
    shorts="t",
    description="Allocate a pseudo-TTY",
  )
  let _detach = run.flag(
    name="detach",
    shorts="d",
    description="Run container in background",
  )
  // String options (need shorts → custom)
  let _name = run.custom(
    name="name",
    default="",
    pre=str_pre,
    description="Assign a name to the container",
    value_name="NAME",
  )
  let _network = run.custom(
    name="network",
    default="",
    pre=str_pre,
    description="Connect a container to a network",
    value_name="NETWORK",
  )
  let _restart = run.custom(
    name="restart",
    default="no",
    pre=str_pre,
    description="Restart policy to apply",
    choices=["no", "on-failure", "always", "unless-stopped"],
    value_name="POLICY",
  )
  let _workdir = run.custom(
    name="workdir",
    shorts="w",
    default="",
    pre=str_pre,
    description="Working directory inside the container",
    value_name="DIR",
  )
  let _user = run.custom(
    name="user",
    shorts="u",
    default="",
    pre=str_pre,
    description="Username or UID",
    value_name="USER",
  )
  let _platform = run.custom(
    name="platform",
    default="",
    pre=str_pre,
    description="Set platform",
    value_name="PLATFORM",
  )
  // Append options (need shorts → custom_append)
  let _publish = run.custom_append(
    name="publish",
    shorts="p",
    pre=str_pre,
    description="Publish a container's port(s) to the host",
    value_name="PORT",
  )
  let _volume = run.custom_append(
    name="volume",
    shorts="v",
    pre=str_pre,
    description="Bind mount a volume",
    value_name="VOLUME",
  )
  let _env = run.custom_append(
    name="env",
    shorts="e",
    pre=str_pre,
    description="Set environment variables",
    value_name="VAR",
  )
  // Positional: IMAGE [COMMAND] [ARG...]
  let mut image_opt : @core.Opt[String]? = None
  let mut _cmd_opt : @core.Opt[Array[String]]? = None
  run.serial(setup=fn(sub) {
    image_opt = Some(
      sub.positional(name="image", description="Container image to run"),
    )
    _cmd_opt = Some(
      sub.rest(name="command", description="Command to run in the container"),
    )
    sub.never()
  })
  run.required(image_opt.unwrap().as_ref())
}

///|
fn setup_exec_options(exec : @core.Parser) -> Unit {
  exec.set_description(
    "mydocker exec - Execute a command in a running container",
  )
  let _interactive = exec.flag(
    name="interactive",
    shorts="i",
    description="Keep STDIN open even if not attached",
  )
  let _tty = exec.flag(
    name="tty",
    shorts="t",
    description="Allocate a pseudo-TTY",
  )
  let _detach = exec.flag(
    name="detach",
    shorts="d",
    description="Detached mode: run command in the background",
  )
  let _env = exec.custom_append(
    name="env",
    shorts="e",
    pre=str_pre,
    description="Set environment variables",
    value_name="VAR",
  )
  let _workdir = exec.custom(
    name="workdir",
    shorts="w",
    default="",
    pre=str_pre,
    description="Working directory inside the container",
    value_name="DIR",
  )
  // Positional: CONTAINER COMMAND [ARG...]
  let mut container_opt : @core.Opt[String]? = None
  let mut _cmd_opt : @core.Opt[Array[String]]? = None
  exec.serial(setup=fn(sub) {
    container_opt = Some(
      sub.positional(name="container", description="Target container"),
    )
    _cmd_opt = Some(sub.rest(name="command", description="Command to execute"))
    sub.never()
  })
  exec.required(container_opt.unwrap().as_ref())
}

///|
fn setup_build_options(build : @core.Parser) -> Unit {
  build.set_description("mydocker build - Build an image from a Dockerfile")
  let _tag = build.custom_append(
    name="tag",
    shorts="t",
    pre=str_pre,
    description="Name and optionally a tag",
    value_name="NAME:TAG",
  )
  let _file = build.custom(
    name="file",
    shorts="f",
    default="",
    pre=str_pre,
    description="Name of the Dockerfile",
    value_name="FILE",
  )
  let _build_arg = build.append_string(
    name="build-arg",
    description="Set build-time variables",
    value_name="KEY=VALUE",
  )
  let _no_cache = build.flag(
    name="no-cache",
    description="Do not use cache when building the image",
  )
  let _progress = build.string(
    name="progress",
    default="auto",
    description="Set type of progress output",
    choices=["auto", "plain", "tty", "rawjson"],
    value_name="TYPE",
  )
  let load = build.flag(
    name="load",
    description="Shorthand for --output=type=docker",
  )
  let push_flag = build.flag(
    name="push",
    description="Shorthand for --output=type=registry",
  )
  build.exclusive([load.as_ref(), push_flag.as_ref()])
  let path = build.positional(
    name="path",
    description="Build context (PATH | URL | -)",
  )
  build.required(path.as_ref())
}

///|
fn setup_pull_options(pull : @core.Parser) -> Unit {
  pull.set_description("mydocker pull - Download an image")
  let _all_tags = pull.flag(
    name="all-tags",
    shorts="a",
    description="Download all tagged images in the repository",
  )
  let _platform = pull.string(
    name="platform",
    default="",
    description="Set platform",
    value_name="PLATFORM",
  )
  let _quiet = pull.flag(
    name="quiet",
    shorts="q",
    description="Suppress verbose output",
  )
  let image = pull.positional(
    name="image",
    description="Image name (NAME[:TAG|@DIGEST])",
  )
  pull.required(image.as_ref())
}

///|
fn setup_push_options(push : @core.Parser) -> Unit {
  push.set_description("mydocker push - Upload an image")
  let _all_tags = push.flag(
    name="all-tags",
    shorts="a",
    description="Push all tags of an image",
  )
  let _quiet = push.flag(
    name="quiet",
    shorts="q",
    description="Suppress verbose output",
  )
  let image = push.positional(
    name="image",
    description="Image name (NAME[:TAG])",
  )
  push.required(image.as_ref())
}

///|
fn setup_ps_options(ls : @core.Parser) -> Unit {
  ls.set_description("mydocker container ls - List containers")
  let _all = ls.flag(
    name="all",
    shorts="a",
    description="Show all containers (default shows just running)",
  )
  let _filter = ls.custom_append(
    name="filter",
    shorts="f",
    pre=str_pre,
    description="Filter output based on conditions provided",
    value_name="FILTER",
  )
  let _format = ls.string(
    name="format",
    default="",
    description="Format output using a custom template or json",
    value_name="FORMAT",
  )
  let _last = ls.custom(
    name="last",
    shorts="n",
    default=-1,
    pre=int_pre,
    description="Show n last created containers",
    value_name="N",
  )
  let _quiet = ls.flag(
    name="quiet",
    shorts="q",
    description="Only display container IDs",
  )
}

///|
fn setup_image_ls_options(ls : @core.Parser) -> Unit {
  ls.set_description("mydocker image ls - List images")
  let _all = ls.flag(
    name="all",
    shorts="a",
    description="Show all images (default hides intermediate images)",
  )
  let _filter = ls.custom_append(
    name="filter",
    shorts="f",
    pre=str_pre,
    description="Filter output based on conditions",
    value_name="FILTER",
  )
  let _format = ls.string(
    name="format",
    default="",
    description="Format output",
    value_name="FORMAT",
  )
  let _quiet = ls.flag(
    name="quiet",
    shorts="q",
    description="Only show image IDs",
  )
}

///|
fn setup_simple_create(parent : @core.Parser) -> Unit {
  let create = parent.sub(name="create", description="Create a resource")
  let _name = create.positional(name="name", description="Resource name")
  let _driver = create.custom(
    name="driver",
    shorts="d",
    default="",
    pre=str_pre,
    description="Driver to manage the resource",
    value_name="DRIVER",
  )
  let _label = create.append_string(
    name="label",
    description="Set metadata on a resource",
    value_name="KEY=VALUE",
  )
}

///|
fn setup_simple_ls(parent : @core.Parser) -> Unit {
  let ls = parent.sub(name="ls", aliases=["list"], description="List resources")
  let _filter = ls.custom_append(
    name="filter",
    shorts="f",
    pre=str_pre,
    description="Filter output",
    value_name="FILTER",
  )
  let _format = ls.string(
    name="format",
    default="",
    description="Format output",
    value_name="FORMAT",
  )
  let _quiet = ls.flag(name="quiet", shorts="q", description="Only display IDs")
}

///|
fn setup_simple_rm(parent : @core.Parser) -> Unit {
  let rm = parent.sub(
    name="rm",
    aliases=["remove"],
    description="Remove one or more resources",
  )
  let _force = rm.flag(name="force", shorts="f", description="Force removal")
  let _names = rm.rest(name="names", description="Resource name(s) or ID(s)")
}

// ════════════════════════════════════════════════════════════════════
// Main entry point
// ════════════════════════════════════════════════════════════════════

///|
fn build_and_parse(
  args : Array[String],
  env? : Map[String, String] = {},
) -> Result[String, String] {
  let p = @core.Parser::new()
  p.set_description("mydocker - A Docker CLI mock built with kuu")

  // ─── Global options ───
  // string/int with shorts/global require custom

  let config = p.custom(
    name="config",
    default="~/.docker",
    global=true,
    pre=str_pre,
    description="Location of client config files",
    value_name="DIR",
  )
  let host = p.custom(
    name="host",
    shorts="H",
    global=true,
    default="",
    pre=str_pre,
    description="Daemon socket to connect to",
    value_name="HOST",
    env="DOCKER_HOST",
  )
  let log_level = p.custom(
    name="log-level",
    shorts="l",
    global=true,
    default="info",
    pre=str_pre,
    description="Set the logging level",
    choices=["debug", "info", "warn", "error", "fatal"],
    value_name="LEVEL",
  )
  let debug = p.flag(
    name="debug",
    shorts="D",
    global=true,
    description="Enable debug mode",
  )
  let tls = p.flag(
    name="tls",
    global=true,
    description="Use TLS; implied by --tlsverify",
  )
  let tlsverify = p.flag(
    name="tlsverify",
    global=true,
    description="Use TLS and verify the remote",
  )

  // ─── Management command: container ───

  let container = p.sub(name="container", description="Manage containers")
  container.set_description("mydocker container - Manage containers")
  container.require_cmd()

  // container run (inline for formatting)
  let c_run = container.sub(
    name="run",
    description="Create and run a new container",
  )
  c_run.set_description(
    "mydocker container run - Create and run a new container",
  )
  let run_rm = c_run.flag(
    name="rm",
    description="Automatically remove the container when it exits",
  )
  let run_interactive = c_run.flag(
    name="interactive",
    shorts="i",
    description="Keep STDIN open even if not attached",
  )
  let run_tty = c_run.flag(
    name="tty",
    shorts="t",
    description="Allocate a pseudo-TTY",
  )
  let run_detach = c_run.flag(
    name="detach",
    shorts="d",
    description="Run container in background",
  )
  let run_name = c_run.custom(
    name="name",
    default="",
    pre=str_pre,
    description="Assign a name to the container",
    value_name="NAME",
  )
  let run_network = c_run.custom(
    name="network",
    default="",
    pre=str_pre,
    description="Connect a container to a network",
    value_name="NETWORK",
  )
  let run_restart = c_run.custom(
    name="restart",
    default="no",
    pre=str_pre,
    description="Restart policy to apply",
    choices=["no", "on-failure", "always", "unless-stopped"],
    value_name="POLICY",
  )
  let run_workdir = c_run.custom(
    name="workdir",
    shorts="w",
    default="",
    pre=str_pre,
    description="Working directory inside the container",
    value_name="DIR",
  )
  let run_user = c_run.custom(
    name="user",
    shorts="u",
    default="",
    pre=str_pre,
    description="Username or UID",
    value_name="USER",
  )
  let run_platform = c_run.custom(
    name="platform",
    default="",
    pre=str_pre,
    description="Set platform",
    value_name="PLATFORM",
  )
  let run_publish = c_run.custom_append(
    name="publish",
    shorts="p",
    pre=str_pre,
    description="Publish a container's port(s) to the host",
    value_name="PORT",
  )
  let run_volume = c_run.custom_append(
    name="volume",
    shorts="v",
    pre=str_pre,
    description="Bind mount a volume",
    value_name="VOLUME",
  )
  let run_env = c_run.custom_append(
    name="env",
    shorts="e",
    pre=str_pre,
    description="Set environment variables",
    value_name="VAR",
  )
  let mut run_image : @core.Opt[String]? = None
  let mut run_cmd : @core.Opt[Array[String]]? = None
  c_run.serial(setup=fn(sub) {
    run_image = Some(
      sub.positional(name="image", description="Container image to run"),
    )
    run_cmd = Some(
      sub.rest(name="command", description="Command to run in the container"),
    )
    sub.never()
  })
  c_run.required(run_image.unwrap().as_ref())

  // container ls
  let c_ls = container.sub(
    name="ls",
    aliases=["list", "ps"],
    description="List containers",
  )
  setup_ps_options(c_ls)

  // container exec
  let c_exec = container.sub(
    name="exec",
    description="Execute a command in a running container",
  )
  setup_exec_options(c_exec)

  // container stop
  let c_stop = container.sub(
    name="stop",
    description="Stop one or more running containers",
  )
  c_stop.set_description("mydocker container stop - Stop running containers")
  let _stop_time = c_stop.custom(
    name="time",
    shorts="t",
    default=10,
    pre=int_pre,
    description="Seconds to wait before killing",
    value_name="SECONDS",
  )
  let _stop_containers = c_stop.rest(
    name="containers",
    description="Container name(s) or ID(s)",
  )

  // container rm
  let c_rm = container.sub(
    name="rm",
    description="Remove one or more containers",
  )
  c_rm.set_description("mydocker container rm - Remove containers")
  let _crm_force = c_rm.flag(
    name="force",
    shorts="f",
    description="Force the removal of a running container",
  )
  let _crm_volumes = c_rm.flag(
    name="volumes",
    shorts="v",
    description="Remove anonymous volumes associated with the container",
  )
  let _crm_containers = c_rm.rest(
    name="containers",
    description="Container name(s) or ID(s)",
  )

  // container logs
  let c_logs = container.sub(
    name="logs",
    description="Fetch the logs of a container",
  )
  c_logs.set_description("mydocker container logs - Fetch container logs")
  let _logs_follow = c_logs.flag(
    name="follow",
    shorts="f",
    description="Follow log output",
  )
  let _logs_tail = c_logs.custom(
    name="tail",
    shorts="n",
    default="all",
    pre=str_pre,
    description="Number of lines to show from the end",
    value_name="N",
  )
  let _logs_timestamps = c_logs.flag(
    name="timestamps",
    shorts="t",
    description="Show timestamps",
  )
  let logs_container = c_logs.positional(
    name="container",
    description="Container name or ID",
  )
  c_logs.required(logs_container.as_ref())

  // ─── Management command: image ───

  let image = p.sub(name="image", description="Manage images")
  image.set_description("mydocker image - Manage images")
  image.require_cmd()

  // image build (inline for formatting)
  let i_build = image.sub(
    name="build",
    description="Build an image from a Dockerfile",
  )
  i_build.set_description("mydocker build - Build an image from a Dockerfile")
  let build_tag = i_build.custom_append(
    name="tag",
    shorts="t",
    pre=str_pre,
    description="Name and optionally a tag",
    value_name="NAME:TAG",
  )
  let build_file = i_build.custom(
    name="file",
    shorts="f",
    default="",
    pre=str_pre,
    description="Name of the Dockerfile",
    value_name="FILE",
  )
  let build_arg = i_build.append_string(
    name="build-arg",
    description="Set build-time variables",
    value_name="KEY=VALUE",
  )
  let build_no_cache = i_build.flag(
    name="no-cache",
    description="Do not use cache when building the image",
  )
  let build_progress = i_build.string(
    name="progress",
    default="auto",
    description="Set type of progress output",
    choices=["auto", "plain", "tty", "rawjson"],
    value_name="TYPE",
  )
  let build_load = i_build.flag(
    name="load",
    description="Shorthand for --output=type=docker",
  )
  let build_push = i_build.flag(
    name="push",
    description="Shorthand for --output=type=registry",
  )
  i_build.exclusive([build_load.as_ref(), build_push.as_ref()])
  let build_path = i_build.positional(
    name="path",
    description="Build context (PATH | URL | -)",
  )
  i_build.required(build_path.as_ref())

  // image ls
  let i_ls = image.sub(name="ls", aliases=["list"], description="List images")
  setup_image_ls_options(i_ls)

  // image pull
  let i_pull = image.sub(
    name="pull",
    description="Download an image from a registry",
  )
  setup_pull_options(i_pull)

  // image push
  let i_push = image.sub(
    name="push",
    description="Upload an image to a registry",
  )
  setup_push_options(i_push)

  // image rm
  let i_rm = image.sub(
    name="rm",
    aliases=["rmi"],
    description="Remove one or more images",
  )
  i_rm.set_description("mydocker image rm - Remove images")
  let _irm_force = i_rm.flag(
    name="force",
    shorts="f",
    description="Force removal of the image",
  )
  let _irm_images = i_rm.rest(
    name="images",
    description="Image name(s) or ID(s)",
  )

  // ─── Management command: compose ───

  let compose = p.sub(name="compose", description="Docker Compose")
  compose.set_description(
    "mydocker compose - Define and run multi-container apps",
  )
  compose.require_cmd()
  let compose_file = compose.custom_append(
    name="file",
    shorts="f",
    pre=str_pre,
    description="Compose configuration files",
    value_name="FILE",
  )
  let compose_project = compose.custom(
    name="project-name",
    shorts="p",
    default="",
    pre=str_pre,
    description="Project name",
    value_name="NAME",
  )

  // compose up (inline for formatting)
  let co_up = compose.sub(name="up", description="Create and start containers")
  co_up.set_description("mydocker compose up - Create and start containers")
  let up_detach = co_up.flag(
    name="detach",
    shorts="d",
    description="Detached mode: Run containers in the background",
  )
  let up_build = co_up.flag(
    name="build",
    description="Build images before starting containers",
  )
  let up_force_recreate = co_up.flag(
    name="force-recreate",
    description="Recreate containers even if their config hasn't changed",
  )
  let up_no_recreate = co_up.flag(
    name="no-recreate",
    description="Don't recreate containers if they already exist",
  )
  co_up.exclusive([up_force_recreate.as_ref(), up_no_recreate.as_ref()])
  let up_scale = co_up.append_string(
    name="scale",
    description="Scale SERVICE to NUM instances",
    value_name="SERVICE=NUM",
  )
  let up_services = co_up.rest(
    name="services",
    description="Service names to start",
  )

  // compose down (inline for formatting)
  let co_down = compose.sub(
    name="down",
    description="Stop and remove containers, networks",
  )
  co_down.set_description("mydocker compose down - Stop and remove containers")
  let down_rmi = co_down.string(
    name="rmi",
    default="",
    implicit_value=Some(@core.Val("all")),
    description="Remove images (all or local)",
    choices=["all", "local"],
    value_name="TYPE",
  )
  let down_volumes = co_down.flag(
    name="volumes",
    shorts="v",
    description="Remove named volumes declared in the volumes section",
  )
  let down_timeout = co_down.custom(
    name="timeout",
    shorts="t",
    default=10,
    pre=int_pre,
    description="Shutdown timeout in seconds",
    value_name="SECONDS",
  )
  let down_services = co_down.rest(name="services", description="Service names")

  // ─── Management command: network ───

  let network = p.sub(name="network", description="Manage networks")
  network.set_description("mydocker network - Manage networks")
  network.require_cmd()
  setup_simple_create(network)
  setup_simple_ls(network)
  setup_simple_rm(network)

  // ─── Management command: volume ───

  let volume = p.sub(name="volume", description="Manage volumes")
  volume.set_description("mydocker volume - Manage volumes")
  volume.require_cmd()
  setup_simple_create(volume)
  setup_simple_ls(volume)
  setup_simple_rm(volume)

  // ─── Top-level shortcuts ───

  // docker run (shortcut)
  let s_run = p.sub(name="run", description="Create and run a new container")
  setup_run_options(s_run)

  // docker ps (shortcut for container ls)
  let s_ps = p.sub(
    name="ps",
    description="List containers (shortcut for container ls)",
  )
  setup_ps_options(s_ps)

  // docker build (shortcut for image build)
  let s_build = p.sub(
    name="build",
    description="Build an image from a Dockerfile",
  )
  setup_build_options(s_build)

  // docker exec (shortcut)
  let s_exec = p.sub(
    name="exec",
    description="Execute a command in a running container",
  )
  setup_exec_options(s_exec)

  // docker pull (shortcut)
  let s_pull = p.sub(
    name="pull",
    description="Download an image from a registry",
  )
  setup_pull_options(s_pull)

  // docker push (shortcut)
  let s_push = p.sub(name="push", description="Upload an image to a registry")
  setup_push_options(s_push)

  // docker images (shortcut for image ls)
  let s_images = p.sub(
    name="images",
    description="List images (shortcut for image ls)",
  )
  setup_image_ls_options(s_images)

  // ─── Parse ───

  let result : Result[@core.ParseResult, @core.ParseError] = try? p.parse(
    args,
    env~,
  )
  match result {
    Err(@core.HelpRequested(text)) => Ok(text)
    Err(@core.ParseError(info)) => Err(info.to_string())
    Ok(pr) => {
      let buf = StringBuilder::new()

      // Global options (show only when explicitly set)
      write_str(buf, "config", config)
      write_str(buf, "host", host)
      write_str(buf, "log-level", log_level)
      if debug.get().unwrap() {
        buf.write_string("  debug: true\n")
      }
      if tls.get().unwrap() {
        buf.write_string("  tls: true\n")
      }
      if tlsverify.get().unwrap() {
        buf.write_string("  tlsverify: true\n")
      }

      // ─── Command dispatch ───

      // container
      match pr.child("container") {
        Some(cpr) => {
          buf.write_string("  command: container\n")
          match cpr.child("run") {
            Some(_) => {
              buf.write_string("  command: run\n")
              write_flag(buf, "rm", run_rm)
              write_flag(buf, "interactive", run_interactive)
              write_flag(buf, "tty", run_tty)
              write_flag(buf, "detach", run_detach)
              write_str(buf, "name", run_name)
              write_str(buf, "network", run_network)
              write_str(buf, "restart", run_restart)
              write_str(buf, "workdir", run_workdir)
              write_str(buf, "user", run_user)
              write_str(buf, "platform", run_platform)
              write_arr(buf, "publish", run_publish)
              write_arr(buf, "volume", run_volume)
              write_arr(buf, "env", run_env)
              write_str(buf, "image", run_image.unwrap())
              write_arr(buf, "command", run_cmd.unwrap())
            }
            None => ()
          }
          format_child_name(buf, cpr, "ls")
          format_child_name(buf, cpr, "exec")
          format_child_name(buf, cpr, "stop")
          format_child_name(buf, cpr, "rm")
          format_child_name(buf, cpr, "logs")
        }
        None => ()
      }

      // image
      match pr.child("image") {
        Some(ipr) => {
          buf.write_string("  command: image\n")
          match ipr.child("build") {
            Some(_) => {
              buf.write_string("  command: build\n")
              write_arr(buf, "tag", build_tag)
              write_str(buf, "file", build_file)
              write_arr(buf, "build-arg", build_arg)
              write_flag(buf, "no-cache", build_no_cache)
              write_str(buf, "progress", build_progress)
              write_flag(buf, "load", build_load)
              write_flag(buf, "push", build_push)
              write_str(buf, "path", build_path)
            }
            None => ()
          }
          format_child_name(buf, ipr, "ls")
          format_child_name(buf, ipr, "pull")
          format_child_name(buf, ipr, "push")
          format_child_name(buf, ipr, "rm")
        }
        None => ()
      }

      // compose
      match pr.child("compose") {
        Some(copr) => {
          buf.write_string("  command: compose\n")
          write_arr(buf, "file", compose_file)
          write_str(buf, "project-name", compose_project)
          match copr.child("up") {
            Some(_) => {
              buf.write_string("  command: up\n")
              write_flag(buf, "detach", up_detach)
              write_flag(buf, "build", up_build)
              write_flag(buf, "force-recreate", up_force_recreate)
              write_flag(buf, "no-recreate", up_no_recreate)
              write_arr(buf, "scale", up_scale)
              write_arr(buf, "services", up_services)
            }
            None => ()
          }
          match copr.child("down") {
            Some(_) => {
              buf.write_string("  command: down\n")
              write_str(buf, "rmi", down_rmi)
              write_flag(buf, "volumes", down_volumes)
              write_int(buf, "timeout", down_timeout)
              write_arr(buf, "services", down_services)
            }
            None => ()
          }
        }
        None => ()
      }

      // network
      match pr.child("network") {
        Some(npr) => {
          buf.write_string("  command: network\n")
          format_child_name(buf, npr, "create")
          format_child_name(buf, npr, "ls")
          format_child_name(buf, npr, "rm")
        }
        None => ()
      }

      // volume
      match pr.child("volume") {
        Some(vpr) => {
          buf.write_string("  command: volume\n")
          format_child_name(buf, vpr, "create")
          format_child_name(buf, vpr, "ls")
          format_child_name(buf, vpr, "rm")
        }
        None => ()
      }

      // Top-level shortcuts (not under management commands)
      format_child_name(buf, pr, "run")
      format_child_name(buf, pr, "ps")
      format_child_name(buf, pr, "build")
      format_child_name(buf, pr, "exec")
      format_child_name(buf, pr, "pull")
      format_child_name(buf, pr, "push")
      format_child_name(buf, pr, "images")

      Ok(buf.to_string())
    }
  }
}

///|
/// Format a simple child command (show command name only).
/// Options defined via setup_* helpers don't have handles in this scope,
/// so we just display the command name.
fn format_child_name(
  buf : StringBuilder,
  parent_pr : @core.ParseResult,
  name : String,
) -> Unit {
  match parent_pr.child(name) {
    Some(_) => buf.write_string("  command: " + name + "\n")
    None => ()
  }
}
