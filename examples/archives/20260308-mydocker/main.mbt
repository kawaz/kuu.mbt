///|
/// mydocker — A Docker CLI subset built with kuu to demonstrate API expressiveness.
///
/// Showcases: sub() nesting (3 levels), flag, string_opt, int_opt, count,
/// append_string, positional, rest, dashdash, require_cmd, exclusive, required.
fn main {
  let args = [
    "--debug", "compose", "-f", "docker-compose.prod.yml",
    "-f", "docker-compose.override.yml", "up", "--detach", "--scale", "3",
    "web", "db",
  ]
  println("Parsing: " + args.to_string())
  println("")
  let result = run(args)
  match result {
    Ok(_) => ()
    Err(msg) => println("Error: " + msg)
  }
}

///|
fn run(args : Array[String]) -> Result[Unit, String] {
  // ─── Root parser ───
  let p = @core.Parser::new()
  p.set_description("mydocker - A Docker CLI subset built with kuu")

  // ─── Global options ───
  let verbose = p.count(
    name="verbose",
    shorts="v",
    global=true,
    description="Increase verbosity",
  )
  let debug = p.flag(
    name="debug",
    shorts="D",
    global=true,
    description="Enable debug mode",
  )
  let log_level = p.string(
    name="log-level",
    default="info",
    shorts="l",
    global=true,
    description="Set the logging level",
    choices=["debug", "info", "warn", "error", "fatal"],
  )
  let host = p.string(
    name="host",
    default="",
    shorts="H",
    global=true,
    description="Daemon socket to connect to",
    value_name="HOST",
  )

  // ─── Subcommand: run ───
  let run_cmd = p.sub(name="run", description="Create and run a new container")
  run_cmd.set_description("mydocker run - Run a command in a new container")
  let run_detach = run_cmd.flag(
    name="detach",
    shorts="d",
    description="Run container in background",
  )
  let run_interactive = run_cmd.flag(
    name="interactive",
    shorts="i",
    description="Keep STDIN open",
  )
  let run_tty = run_cmd.flag(
    name="tty",
    shorts="t",
    description="Allocate a pseudo-TTY",
  )
  let run_rm = run_cmd.flag(
    name="rm",
    description="Automatically remove container when it exits",
  )
  let run_name = run_cmd.string(
    name="name",
    default="",
    description="Assign a name to the container",
    value_name="NAME",
  )
  let run_publish = run_cmd.append_string(
    name="publish",
    shorts="p",
    description="Publish a container's port(s) to the host",
    value_name="HOST:CONTAINER",
  )
  let run_volume = run_cmd.append_string(
    name="volume",
    shorts="V",
    description="Bind mount a volume",
    value_name="SRC:DST",
  )
  let run_env = run_cmd.append_string(
    name="env",
    shorts="e",
    description="Set environment variables",
    value_name="KEY=VALUE",
  )
  let run_network = run_cmd.string(
    name="network",
    default="",
    description="Connect a container to a network",
    value_name="NETWORK",
  )
  let run_restart = run_cmd.string(
    name="restart",
    default="no",
    description="Restart policy to apply",
    choices=["no", "always", "unless-stopped", "on-failure"],
  )
  let run_image = run_cmd.positional(
    name="image",
    description="Container image",
  )
  run_cmd.required(run_image.as_ref())
  let run_command = run_cmd.rest(
    name="command",
    description="Command to run in the container",
  )

  // ─── Subcommand: build ───
  let build = p.sub(name="build", description="Build an image from a Dockerfile")
  build.set_description("mydocker build - Build an image")
  let build_tag = build.append_string(
    name="tag",
    shorts="t",
    description="Name and optionally a tag (name:tag)",
    value_name="NAME:TAG",
  )
  let build_file = build.string(
    name="file",
    default="Dockerfile",
    shorts="f",
    description="Name of the Dockerfile",
    value_name="FILE",
  )
  let build_no_cache = build.flag(
    name="no-cache",
    description="Do not use cache when building",
  )
  let build_pull = build.flag(
    name="pull",
    description="Always attempt to pull a newer version of the image",
  )
  let build_arg = build.append_string(
    name="build-arg",
    description="Set build-time variables",
    value_name="KEY=VALUE",
  )
  let build_target = build.string(
    name="target",
    default="",
    description="Set the target build stage",
    value_name="STAGE",
  )
  let build_platform = build.string(
    name="platform",
    default="",
    description="Set platform (e.g. linux/amd64)",
    value_name="PLATFORM",
  )
  let build_context = build.positional(
    name="path",
    description="Build context path",
  )

  // ─── Subcommand: ps ───
  let ps = p.sub(name="ps", description="List containers")
  ps.set_description("mydocker ps - List containers")
  let ps_all = ps.flag(
    name="all",
    shorts="a",
    description="Show all containers (default: running only)",
  )
  let ps_quiet = ps.flag(
    name="quiet",
    shorts="q",
    description="Only display container IDs",
  )
  let ps_format = ps.string(
    name="format",
    default="",
    description="Format output using a Go template",
    value_name="FORMAT",
  )
  let ps_filter = ps.append_string(
    name="filter",
    shorts="f",
    description="Filter output based on conditions",
    value_name="FILTER",
  )
  let ps_last = ps.int(
    name="last",
    default=0,
    shorts="n",
    description="Show n last created containers",
    value_name="N",
  )
  ps.exclusive([ps_all.as_ref(), ps_last.as_ref()])

  // ─── Subcommand: images ───
  let images = p.sub(name="images", description="List images")
  images.set_description("mydocker images - List images")
  let images_all = images.flag(
    name="all",
    shorts="a",
    description="Show all images",
  )
  let images_quiet = images.flag(
    name="quiet",
    shorts="q",
    description="Only show image IDs",
  )
  let images_format = images.string(
    name="format",
    default="",
    description="Format output",
    value_name="FORMAT",
  )
  let images_filter = images.append_string(
    name="filter",
    shorts="f",
    description="Filter output",
    value_name="FILTER",
  )
  let images_repo = images.positional(
    name="repository",
    description="Repository to filter",
  )

  // ─── Subcommand: pull ───
  let pull = p.sub(name="pull", description="Download an image from a registry")
  pull.set_description("mydocker pull - Pull an image")
  let pull_all_tags = pull.flag(
    name="all-tags",
    shorts="a",
    description="Download all tagged images",
  )
  let pull_platform = pull.string(
    name="platform",
    default="",
    description="Set platform",
    value_name="PLATFORM",
  )
  let pull_quiet = pull.flag(
    name="quiet",
    shorts="q",
    description="Suppress verbose output",
  )
  let pull_image = pull.positional(
    name="image",
    description="Image name[:tag|@digest]",
  )
  pull.required(pull_image.as_ref())

  // ─── Subcommand: push ───
  let push = p.sub(name="push", description="Upload an image to a registry")
  push.set_description("mydocker push - Push an image")
  let push_all_tags = push.flag(
    name="all-tags",
    shorts="a",
    description="Push all tagged images",
  )
  let push_quiet = push.flag(
    name="quiet",
    shorts="q",
    description="Suppress verbose output",
  )
  let push_image = push.positional(
    name="image",
    description="Image name[:tag]",
  )
  push.required(push_image.as_ref())

  // ─── Subcommand: exec ───
  let exec_cmd = p.sub(
    name="exec",
    description="Execute a command in a running container",
  )
  exec_cmd.set_description("mydocker exec - Execute in container")
  let exec_interactive = exec_cmd.flag(
    name="interactive",
    shorts="i",
    description="Keep STDIN open",
  )
  let exec_tty = exec_cmd.flag(
    name="tty",
    shorts="t",
    description="Allocate a pseudo-TTY",
  )
  let exec_user = exec_cmd.string(
    name="user",
    default="",
    shorts="u",
    description="Username or UID",
    value_name="USER",
  )
  let exec_workdir = exec_cmd.string(
    name="workdir",
    default="",
    shorts="w",
    description="Working directory inside the container",
    value_name="DIR",
  )
  let exec_env = exec_cmd.append_string(
    name="env",
    shorts="e",
    description="Set environment variables",
    value_name="KEY=VALUE",
  )
  let exec_container = exec_cmd.positional(
    name="container",
    description="Container ID or name",
  )
  exec_cmd.required(exec_container.as_ref())
  let exec_command = exec_cmd.rest(
    name="command",
    description="Command and arguments",
  )

  // ─── Subcommand: compose (nested 3 levels) ───
  let compose = p.sub(
    name="compose",
    description="Docker Compose commands",
  )
  compose.set_description("mydocker compose - Define and run multi-container applications")
  let compose_file = compose.append_string(
    name="file",
    shorts="f",
    description="Compose configuration files",
    value_name="FILE",
  )
  let compose_project = compose.string(
    name="project-name",
    default="",
    shorts="p",
    description="Project name",
    value_name="NAME",
  )
  let compose_env_file = compose.string(
    name="env-file",
    default="",
    description="Environment file path",
    value_name="PATH",
  )
  compose.require_cmd()

  // compose up
  let compose_up = compose.sub(name="up", description="Create and start containers")
  compose_up.set_description("mydocker compose up - Start services")
  let compose_up_detach = compose_up.flag(
    name="detach",
    shorts="d",
    description="Detached mode",
  )
  let compose_up_build = compose_up.flag(
    name="build",
    description="Build images before starting",
  )
  let compose_up_force_recreate = compose_up.flag(
    name="force-recreate",
    description="Recreate containers even if unchanged",
  )
  let compose_up_no_deps = compose_up.flag(
    name="no-deps",
    description="Don't start linked services",
  )
  let compose_up_scale = compose_up.int(
    name="scale",
    default=1,
    description="Number of containers for a service",
    value_name="N",
  )
  let compose_up_services = compose_up.rest(
    name="services",
    description="Services to start",
  )

  // compose down
  let compose_down = compose.sub(
    name="down",
    description="Stop and remove containers, networks",
  )
  compose_down.set_description("mydocker compose down - Stop services")
  let compose_down_rmi = compose_down.string(
    name="rmi",
    default="",
    description="Remove images (all or local)",
    choices=["all", "local"],
    implicit_value=Some(@core.Val("all")),
  )
  let compose_down_volumes = compose_down.flag(
    name="volumes",
    shorts="V",
    description="Remove named volumes",
  )
  let compose_down_remove_orphans = compose_down.flag(
    name="remove-orphans",
    description="Remove containers for services not in the file",
  )

  // compose logs
  let compose_logs = compose.sub(name="logs", description="View output from containers")
  compose_logs.set_description("mydocker compose logs - View logs")
  let compose_logs_follow = compose_logs.flag(
    name="follow",
    shorts="f",
    description="Follow log output",
  )
  let compose_logs_tail = compose_logs.string(
    name="tail",
    default="all",
    description="Number of lines to show from the end",
    value_name="N",
  )
  let compose_logs_timestamps = compose_logs.flag(
    name="timestamps",
    shorts="t",
    description="Show timestamps",
  )
  let compose_logs_services = compose_logs.rest(
    name="services",
    description="Services to show logs for",
  )

  // compose ps
  let compose_ps = compose.sub(name="ps", description="List containers")
  compose_ps.set_description("mydocker compose ps - List compose containers")
  let compose_ps_all = compose_ps.flag(
    name="all",
    shorts="a",
    description="Show all containers",
  )
  let compose_ps_quiet = compose_ps.flag(
    name="quiet",
    shorts="q",
    description="Only display IDs",
  )
  let compose_ps_format = compose_ps.string(
    name="format",
    default="",
    description="Format output",
    value_name="FORMAT",
  )
  let compose_ps_services = compose_ps.rest(
    name="services",
    description="Services to filter",
  )

  // ─── Subcommand: network (nested) ───
  let network = p.sub(name="network", description="Manage networks")
  network.set_description("mydocker network - Manage Docker networks")
  network.require_cmd()

  // network create
  let net_create = network.sub(name="create", description="Create a network")
  net_create.set_description("mydocker network create - Create a network")
  let net_create_driver = net_create.string(
    name="driver",
    default="bridge",
    shorts="d",
    description="Driver to manage the network",
    choices=["bridge", "host", "overlay", "macvlan", "none"],
  )
  let net_create_subnet = net_create.append_string(
    name="subnet",
    description="Subnet in CIDR format",
    value_name="CIDR",
  )
  let net_create_gateway = net_create.append_string(
    name="gateway",
    description="Gateway for the subnet",
    value_name="IP",
  )
  let net_create_internal = net_create.flag(
    name="internal",
    description="Restrict external access",
  )
  let net_create_label = net_create.append_string(
    name="label",
    description="Set metadata on the network",
    value_name="KEY=VALUE",
  )
  let net_create_name = net_create.positional(
    name="name",
    description="Network name",
  )
  net_create.required(net_create_name.as_ref())

  // network ls
  let net_ls = network.sub(name="ls", description="List networks")
  net_ls.set_description("mydocker network ls - List networks")
  let net_ls_format = net_ls.string(
    name="format",
    default="",
    description="Format output",
    value_name="FORMAT",
  )
  let net_ls_filter = net_ls.append_string(
    name="filter",
    shorts="f",
    description="Filter output",
    value_name="FILTER",
  )
  let net_ls_quiet = net_ls.flag(
    name="quiet",
    shorts="q",
    description="Only display IDs",
  )

  // network rm
  let net_rm = network.sub(name="rm", description="Remove one or more networks")
  net_rm.set_description("mydocker network rm - Remove networks")
  let net_rm_force = net_rm.flag(
    name="force",
    shorts="f",
    description="Do not error if network does not exist",
  )
  let net_rm_names = net_rm.rest(
    name="networks",
    description="Network names or IDs",
  )

  // network inspect
  let net_inspect = network.sub(
    name="inspect",
    description="Display detailed information on networks",
  )
  net_inspect.set_description("mydocker network inspect - Inspect networks")
  let net_inspect_format = net_inspect.string(
    name="format",
    default="",
    shorts="f",
    description="Format output",
    value_name="FORMAT",
  )
  let net_inspect_names = net_inspect.rest(
    name="networks",
    description="Network names or IDs",
  )

  // ─── Subcommand: volume (nested) ───
  let volume = p.sub(name="volume", description="Manage volumes")
  volume.set_description("mydocker volume - Manage Docker volumes")
  volume.require_cmd()

  // volume create
  let vol_create = volume.sub(name="create", description="Create a volume")
  vol_create.set_description("mydocker volume create - Create a volume")
  let vol_create_driver = vol_create.string(
    name="driver",
    default="local",
    shorts="d",
    description="Volume driver",
    value_name="DRIVER",
  )
  let vol_create_label = vol_create.append_string(
    name="label",
    description="Set metadata on the volume",
    value_name="KEY=VALUE",
  )
  let vol_create_opt = vol_create.append_string(
    name="opt",
    shorts="o",
    description="Set driver specific options",
    value_name="KEY=VALUE",
  )
  let vol_create_name = vol_create.positional(
    name="name",
    description="Volume name (optional, auto-generated if not given)",
  )

  // volume ls
  let vol_ls = volume.sub(name="ls", description="List volumes")
  vol_ls.set_description("mydocker volume ls - List volumes")
  let vol_ls_format = vol_ls.string(
    name="format",
    default="",
    description="Format output",
    value_name="FORMAT",
  )
  let vol_ls_filter = vol_ls.append_string(
    name="filter",
    shorts="f",
    description="Filter output",
    value_name="FILTER",
  )
  let vol_ls_quiet = vol_ls.flag(
    name="quiet",
    shorts="q",
    description="Only display IDs",
  )

  // volume rm
  let vol_rm = volume.sub(name="rm", description="Remove one or more volumes")
  vol_rm.set_description("mydocker volume rm - Remove volumes")
  let vol_rm_force = vol_rm.flag(
    name="force",
    shorts="f",
    description="Force removal",
  )
  let vol_rm_names = vol_rm.rest(
    name="volumes",
    description="Volume names",
  )

  // volume inspect
  let vol_inspect = volume.sub(
    name="inspect",
    description="Display detailed information on volumes",
  )
  vol_inspect.set_description("mydocker volume inspect - Inspect volumes")
  let vol_inspect_format = vol_inspect.string(
    name="format",
    default="",
    shorts="f",
    description="Format output",
    value_name="FORMAT",
  )
  let vol_inspect_names = vol_inspect.rest(
    name="volumes",
    description="Volume names",
  )

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
      // ─── Print globals ───
      println("=== Global Options ===")
      println("verbose: " + verbose.get().unwrap().to_string())
      println("debug: " + debug.get().unwrap().to_string())
      println("log-level: " + log_level.get().unwrap())
      let host_val = host.get().unwrap()
      if host_val != "" {
        println("host: " + host_val)
      }
      println("")

      // ─── Dispatch subcommands ───

      // run
      match result.child("run") {
        Some(_) => {
          println("=== run ===")
          println("image: " + run_image.get().unwrap())
          println("detach: " + run_detach.get().unwrap().to_string())
          println("interactive: " + run_interactive.get().unwrap().to_string())
          println("tty: " + run_tty.get().unwrap().to_string())
          println("rm: " + run_rm.get().unwrap().to_string())
          let name_val = run_name.get().unwrap()
          if name_val != "" {
            println("name: " + name_val)
          }
          let pubs = run_publish.get().unwrap()
          if pubs.length() > 0 {
            println("publish: " + pubs.to_string())
          }
          let vols = run_volume.get().unwrap()
          if vols.length() > 0 {
            println("volume: " + vols.to_string())
          }
          let envs = run_env.get().unwrap()
          if envs.length() > 0 {
            println("env: " + envs.to_string())
          }
          let net_val = run_network.get().unwrap()
          if net_val != "" {
            println("network: " + net_val)
          }
          println("restart: " + run_restart.get().unwrap())
          let cmd = run_command.get().unwrap()
          if cmd.length() > 0 {
            println("command: " + cmd.to_string())
          }
        }
        _ => ()
      }

      // build
      match result.child("build") {
        Some(_) => {
          println("=== build ===")
          let tags = build_tag.get().unwrap()
          if tags.length() > 0 {
            println("tag: " + tags.to_string())
          }
          println("file: " + build_file.get().unwrap())
          println("no-cache: " + build_no_cache.get().unwrap().to_string())
          println("pull: " + build_pull.get().unwrap().to_string())
          let bargs = build_arg.get().unwrap()
          if bargs.length() > 0 {
            println("build-arg: " + bargs.to_string())
          }
          let tgt = build_target.get().unwrap()
          if tgt != "" {
            println("target: " + tgt)
          }
          let plat = build_platform.get().unwrap()
          if plat != "" {
            println("platform: " + plat)
          }
          println("path: " + build_context.get().unwrap_or("."))
        }
        _ => ()
      }

      // ps
      match result.child("ps") {
        Some(_) => {
          println("=== ps ===")
          println("all: " + ps_all.get().unwrap().to_string())
          println("quiet: " + ps_quiet.get().unwrap().to_string())
          let fmt = ps_format.get().unwrap()
          if fmt != "" {
            println("format: " + fmt)
          }
          let filters = ps_filter.get().unwrap()
          if filters.length() > 0 {
            println("filter: " + filters.to_string())
          }
          let last_val = ps_last.get().unwrap()
          if last_val > 0 {
            println("last: " + last_val.to_string())
          }
        }
        _ => ()
      }

      // images
      match result.child("images") {
        Some(_) => {
          println("=== images ===")
          println("all: " + images_all.get().unwrap().to_string())
          println("quiet: " + images_quiet.get().unwrap().to_string())
          let fmt = images_format.get().unwrap()
          if fmt != "" {
            println("format: " + fmt)
          }
          let filters = images_filter.get().unwrap()
          if filters.length() > 0 {
            println("filter: " + filters.to_string())
          }
          println("repository: " + images_repo.get().unwrap_or("(all)"))
        }
        _ => ()
      }

      // pull
      match result.child("pull") {
        Some(_) => {
          println("=== pull ===")
          println("image: " + pull_image.get().unwrap())
          println("all-tags: " + pull_all_tags.get().unwrap().to_string())
          let plat = pull_platform.get().unwrap()
          if plat != "" {
            println("platform: " + plat)
          }
          println("quiet: " + pull_quiet.get().unwrap().to_string())
        }
        _ => ()
      }

      // push
      match result.child("push") {
        Some(_) => {
          println("=== push ===")
          println("image: " + push_image.get().unwrap())
          println("all-tags: " + push_all_tags.get().unwrap().to_string())
          println("quiet: " + push_quiet.get().unwrap().to_string())
        }
        _ => ()
      }

      // exec
      match result.child("exec") {
        Some(_) => {
          println("=== exec ===")
          println("container: " + exec_container.get().unwrap())
          println(
            "interactive: " + exec_interactive.get().unwrap().to_string(),
          )
          println("tty: " + exec_tty.get().unwrap().to_string())
          let user_val = exec_user.get().unwrap()
          if user_val != "" {
            println("user: " + user_val)
          }
          let wd = exec_workdir.get().unwrap()
          if wd != "" {
            println("workdir: " + wd)
          }
          let envs = exec_env.get().unwrap()
          if envs.length() > 0 {
            println("env: " + envs.to_string())
          }
          let cmd = exec_command.get().unwrap()
          if cmd.length() > 0 {
            println("command: " + cmd.to_string())
          }
        }
        _ => ()
      }

      // compose
      match result.child("compose") {
        Some(compose_result) => {
          println("=== compose ===")
          let files = compose_file.get().unwrap()
          if files.length() > 0 {
            println("file: " + files.to_string())
          }
          let proj = compose_project.get().unwrap()
          if proj != "" {
            println("project-name: " + proj)
          }
          let ef = compose_env_file.get().unwrap()
          if ef != "" {
            println("env-file: " + ef)
          }
          // compose up
          match compose_result.child("up") {
            Some(_) => {
              println("  --- up ---")
              println(
                "  detach: " + compose_up_detach.get().unwrap().to_string(),
              )
              println(
                "  build: " + compose_up_build.get().unwrap().to_string(),
              )
              println(
                "  force-recreate: " +
                compose_up_force_recreate.get().unwrap().to_string(),
              )
              println(
                "  no-deps: " + compose_up_no_deps.get().unwrap().to_string(),
              )
              println(
                "  scale: " + compose_up_scale.get().unwrap().to_string(),
              )
              let svcs = compose_up_services.get().unwrap()
              if svcs.length() > 0 {
                println("  services: " + svcs.to_string())
              }
            }
            _ => ()
          }
          // compose down
          match compose_result.child("down") {
            Some(_) => {
              println("  --- down ---")
              let rmi = compose_down_rmi.get().unwrap()
              if rmi != "" {
                println("  rmi: " + rmi)
              }
              println(
                "  volumes: " +
                compose_down_volumes.get().unwrap().to_string(),
              )
              println(
                "  remove-orphans: " +
                compose_down_remove_orphans.get().unwrap().to_string(),
              )
            }
            _ => ()
          }
          // compose logs
          match compose_result.child("logs") {
            Some(_) => {
              println("  --- logs ---")
              println(
                "  follow: " +
                compose_logs_follow.get().unwrap().to_string(),
              )
              println("  tail: " + compose_logs_tail.get().unwrap())
              println(
                "  timestamps: " +
                compose_logs_timestamps.get().unwrap().to_string(),
              )
              let svcs = compose_logs_services.get().unwrap()
              if svcs.length() > 0 {
                println("  services: " + svcs.to_string())
              }
            }
            _ => ()
          }
          // compose ps
          match compose_result.child("ps") {
            Some(_) => {
              println("  --- ps ---")
              println(
                "  all: " + compose_ps_all.get().unwrap().to_string(),
              )
              println(
                "  quiet: " + compose_ps_quiet.get().unwrap().to_string(),
              )
              let fmt = compose_ps_format.get().unwrap()
              if fmt != "" {
                println("  format: " + fmt)
              }
              let svcs = compose_ps_services.get().unwrap()
              if svcs.length() > 0 {
                println("  services: " + svcs.to_string())
              }
            }
            _ => ()
          }
        }
        _ => ()
      }

      // network
      match result.child("network") {
        Some(net_result) => {
          println("=== network ===")
          match net_result.child("create") {
            Some(_) => {
              println("  --- create ---")
              println("  name: " + net_create_name.get().unwrap())
              println("  driver: " + net_create_driver.get().unwrap())
              let subnets = net_create_subnet.get().unwrap()
              if subnets.length() > 0 {
                println("  subnet: " + subnets.to_string())
              }
              let gws = net_create_gateway.get().unwrap()
              if gws.length() > 0 {
                println("  gateway: " + gws.to_string())
              }
              println(
                "  internal: " +
                net_create_internal.get().unwrap().to_string(),
              )
              let labels = net_create_label.get().unwrap()
              if labels.length() > 0 {
                println("  label: " + labels.to_string())
              }
            }
            _ => ()
          }
          match net_result.child("ls") {
            Some(_) => {
              println("  --- ls ---")
              let fmt = net_ls_format.get().unwrap()
              if fmt != "" {
                println("  format: " + fmt)
              }
              let filters = net_ls_filter.get().unwrap()
              if filters.length() > 0 {
                println("  filter: " + filters.to_string())
              }
              println(
                "  quiet: " + net_ls_quiet.get().unwrap().to_string(),
              )
            }
            _ => ()
          }
          match net_result.child("rm") {
            Some(_) => {
              println("  --- rm ---")
              println(
                "  force: " + net_rm_force.get().unwrap().to_string(),
              )
              let names = net_rm_names.get().unwrap()
              if names.length() > 0 {
                println("  networks: " + names.to_string())
              }
            }
            _ => ()
          }
          match net_result.child("inspect") {
            Some(_) => {
              println("  --- inspect ---")
              let fmt = net_inspect_format.get().unwrap()
              if fmt != "" {
                println("  format: " + fmt)
              }
              let names = net_inspect_names.get().unwrap()
              if names.length() > 0 {
                println("  networks: " + names.to_string())
              }
            }
            _ => ()
          }
        }
        _ => ()
      }

      // volume
      match result.child("volume") {
        Some(vol_result) => {
          println("=== volume ===")
          match vol_result.child("create") {
            Some(_) => {
              println("  --- create ---")
              println(
                "  name: " + vol_create_name.get().unwrap_or("(auto)"),
              )
              println("  driver: " + vol_create_driver.get().unwrap())
              let labels = vol_create_label.get().unwrap()
              if labels.length() > 0 {
                println("  label: " + labels.to_string())
              }
              let opts = vol_create_opt.get().unwrap()
              if opts.length() > 0 {
                println("  opt: " + opts.to_string())
              }
            }
            _ => ()
          }
          match vol_result.child("ls") {
            Some(_) => {
              println("  --- ls ---")
              let fmt = vol_ls_format.get().unwrap()
              if fmt != "" {
                println("  format: " + fmt)
              }
              let filters = vol_ls_filter.get().unwrap()
              if filters.length() > 0 {
                println("  filter: " + filters.to_string())
              }
              println(
                "  quiet: " + vol_ls_quiet.get().unwrap().to_string(),
              )
            }
            _ => ()
          }
          match vol_result.child("rm") {
            Some(_) => {
              println("  --- rm ---")
              println(
                "  force: " + vol_rm_force.get().unwrap().to_string(),
              )
              let names = vol_rm_names.get().unwrap()
              if names.length() > 0 {
                println("  volumes: " + names.to_string())
              }
            }
            _ => ()
          }
          match vol_result.child("inspect") {
            Some(_) => {
              println("  --- inspect ---")
              let fmt = vol_inspect_format.get().unwrap()
              if fmt != "" {
                println("  format: " + fmt)
              }
              let names = vol_inspect_names.get().unwrap()
              if names.length() > 0 {
                println("  volumes: " + names.to_string())
              }
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
