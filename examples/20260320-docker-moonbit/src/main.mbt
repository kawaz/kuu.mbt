///|
/// mydocker — A Docker CLI mock built with kuu.
///
/// Demonstrates kuu's ability to handle complex multi-level subcommand CLIs with:
///   - multi-level subcommand nesting (container run, compose up, etc.)
///   - global options (--host, --debug, --log-level across all subcommands)
///   - append_string (-p, -e, -v for multiple values)
///   - short flag combining (-it = -i -t)
///   - subcommand aliases (ls/list/ps)
///   - choices (--log-level, --restart, --progress)
///   - exclusive (--force-recreate vs --no-recreate)
///   - required + positional + rest + serial (IMAGE COMMAND ARG...)
///   - implicit_value (--rmi)
///   - variation_false (--no-cache, --no-deps)
///   - env (DOCKER_HOST)
///   - require_cmd (container, image, compose need a subcommand)
fn main {
  println(
    "=== Demo 1: docker container run (short flag combining + append) ===",
  )
  run_test([
    "container", "run", "--rm", "-it", "-p", "8080:80", "-p", "3000:3000", "-e",
    "APP=demo", "-v", "/data:/data", "--name", "myapp", "nginx:alpine", "sh", "-c",
    "echo hello",
  ])
  println("")
  println("=== Demo 2: docker container ls (filter + format) ===")
  run_test([
    "container", "ls", "--all", "-f", "status=running", "--format", "json",
  ])
  println("")
  println("=== Demo 3: docker image build (tag + build-arg) ===")
  run_test([
    "image", "build", "-t", "myapp:latest", "-t", "myapp:v1.0", "--build-arg", "VERSION=1.0",
    "--no-cache", ".",
  ])
  println("")
  println("=== Demo 4: docker compose up (detach) ===")
  run_test(["compose", "-f", "docker-compose.yml", "up", "-d", "--build"])
  println("")
  println("=== Demo 5: docker exec (flag combining) ===")
  run_test(["exec", "-it", "myapp", "bash"])
  println("")
  println("=== Demo 6: docker --help ===")
  run_test(["--help"])
}

///|
fn run_test(args : Array[String], env? : Map[String, String] = {}) -> Unit {
  println("  args: " + args.to_string())
  if env.length() > 0 {
    println("  env: " + env.to_string())
  }
  match build_and_parse(args, env~) {
    Ok(info) => println(info)
    Err(msg) => println("  ERROR: " + msg)
  }
}
