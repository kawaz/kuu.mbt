// ════════════════════════════════════════════════════════════════════
// docker run — short flag combining, append options, positional args
// ════════════════════════════════════════════════════════════════════

///|
test "docker run basic" {
  let result = build_and_parse(["run", "nginx"])
  inspect(
    result,
    content=(
      #|Ok("  command: run\n")
    ),
  )
}

///|
test "docker run with -it (short flag combining)" {
  let result = build_and_parse(["run", "-it", "ubuntu", "bash"])
  inspect(
    result,
    content=(
      #|Ok("  command: run\n")
    ),
  )
}

///|
test "docker run with multiple -p -e -v (append)" {
  let result = build_and_parse([
    "run", "--rm", "-p", "8080:80", "-p", "3000:3000", "-e", "APP=demo", "-e", "ENV=prod",
    "-v", "/data:/data", "--name", "myapp", "nginx:alpine",
  ])
  inspect(
    result,
    content=(
      #|Ok("  command: run\n")
    ),
  )
}

///|
test "docker run with -itd (three flags combined)" {
  let result = build_and_parse(["run", "-itd", "nginx"])
  inspect(
    result,
    content=(
      #|Ok("  command: run\n")
    ),
  )
}

///|
test "docker run missing image (required error)" {
  let result = build_and_parse(["run"])
  inspect(
    result,
    content=(
      #|Err("error: required option missing: image\n\nUsage: [OPTIONS]\n\nFor more information, try '--help'.")
    ),
  )
}

///|
test "docker run with restart choices" {
  let result = build_and_parse(["run", "--restart", "always", "nginx"])
  inspect(
    result,
    content=(
      #|Ok("  command: run\n")
    ),
  )
}

///|
test "docker run invalid restart choice" {
  let result = build_and_parse(["run", "--restart", "invalid", "nginx"])
  inspect(
    result,
    content=(
      #|Err("error: value must be one of: no, on-failure, always, unless-stopped\n\nUsage: [OPTIONS]\n\nFor more information, try '--help'.")
    ),
  )
}

///|
test "docker run IMAGE COMMAND ARG..." {
  let result = build_and_parse(["run", "alpine", "sh", "-c", "echo hello"])
  inspect(
    result,
    content=(
      #|Ok("  command: run\n")
    ),
  )
}

// ════════════════════════════════════════════════════════════════════
// docker container subcommands
// ════════════════════════════════════════════════════════════════════

///|
test "docker container run (management path)" {
  let result = build_and_parse([
    "container", "run", "-it", "--rm", "ubuntu", "bash",
  ])
  inspect(
    result,
    content=(
      #|Ok("  command: container\n  command: run\n    rm: true\n    interactive: true\n    tty: true\n    image: ubuntu\n    command: [\"bash\"]\n")
    ),
  )
}

///|
test "docker container ls --all" {
  let result = build_and_parse(["container", "ls", "--all"])
  inspect(
    result,
    content=(
      #|Ok("  command: container\n  command: ls\n")
    ),
  )
}

///|
test "docker container ls with filters" {
  let result = build_and_parse([
    "container", "ls", "-f", "status=running", "-f", "name=web",
  ])
  inspect(
    result,
    content=(
      #|Ok("  command: container\n  command: ls\n")
    ),
  )
}

///|
test "docker container exec -it" {
  let result = build_and_parse(["container", "exec", "-it", "myapp", "bash"])
  inspect(
    result,
    content=(
      #|Ok("  command: container\n  command: exec\n")
    ),
  )
}

///|
test "docker container stop" {
  let result = build_and_parse(["container", "stop", "web1", "web2"])
  inspect(
    result,
    content=(
      #|Ok("  command: container\n  command: stop\n")
    ),
  )
}

///|
test "docker container rm -f" {
  let result = build_and_parse(["container", "rm", "-f", "old-container"])
  inspect(
    result,
    content=(
      #|Ok("  command: container\n  command: rm\n")
    ),
  )
}

///|
test "docker container logs -f" {
  let result = build_and_parse([
    "container", "logs", "-f", "--tail", "100", "myapp",
  ])
  inspect(
    result,
    content=(
      #|Ok("  command: container\n  command: logs\n")
    ),
  )
}

///|
test "docker container (no subcommand = require_cmd error)" {
  let result = build_and_parse(["container"])
  inspect(
    result,
    content=(
      #|Err("error: subcommand required\n\nCommands:\n  run   Create and run a new container\n  ls    List containers\n  exec  Execute a command in a running container\n  stop  Stop one or more running containers\n  rm    Remove one or more containers\n  logs  Fetch the logs of a container\n\nUsage: [OPTIONS] [COMMAND]\n\nFor more information, try '--help'.")
    ),
  )
}

// ════════════════════════════════════════════════════════════════════
// docker image subcommands
// ════════════════════════════════════════════════════════════════════

///|
test "docker image build basic" {
  let result = build_and_parse(["image", "build", "."])
  inspect(
    result,
    content=(
      #|Ok("  command: image\n  command: build\n    path: .\n")
    ),
  )
}

///|
test "docker image build with tags and build-args" {
  let result = build_and_parse([
    "image", "build", "-t", "myapp:latest", "-t", "myapp:v1", "--build-arg", "VERSION=1.0",
    "--no-cache", ".",
  ])
  inspect(
    result,
    content=(
      #|Ok("  command: image\n  command: build\n    tag: [\"myapp:latest\", \"myapp:v1\"]\n    build-arg: [\"VERSION=1.0\"]\n    no-cache: true\n    path: .\n")
    ),
  )
}

///|
test "docker image build --load --push exclusive" {
  let result = build_and_parse(["image", "build", "--load", "--push", "."])
  inspect(
    result,
    content=(
      #|Err("error: mutually exclusive options: --load, --push\n\nUsage: [OPTIONS] <PATH>\n\nFor more information, try '--help'.")
    ),
  )
}

///|
test "docker image build missing path (required error)" {
  let result = build_and_parse(["image", "build"])
  inspect(
    result,
    content=(
      #|Err("error: required option missing: path\n\nUsage: [OPTIONS] <PATH>\n\nFor more information, try '--help'.")
    ),
  )
}

///|
test "docker image ls" {
  let result = build_and_parse(["image", "ls"])
  inspect(
    result,
    content=(
      #|Ok("  command: image\n  command: ls\n")
    ),
  )
}

///|
test "docker image pull" {
  let result = build_and_parse(["image", "pull", "nginx:alpine"])
  inspect(
    result,
    content=(
      #|Ok("  command: image\n  command: pull\n")
    ),
  )
}

///|
test "docker image push" {
  let result = build_and_parse(["image", "push", "myapp:latest"])
  inspect(
    result,
    content=(
      #|Ok("  command: image\n  command: push\n")
    ),
  )
}

///|
test "docker image rm" {
  let result = build_and_parse([
    "image", "rm", "-f", "old-image", "another-image",
  ])
  inspect(
    result,
    content=(
      #|Ok("  command: image\n  command: rm\n")
    ),
  )
}

// ════════════════════════════════════════════════════════════════════
// docker compose
// ════════════════════════════════════════════════════════════════════

///|
test "docker compose up" {
  let result = build_and_parse(["compose", "up", "-d"])
  inspect(
    result,
    content=(
      #|Ok("  command: compose\n  command: up\n    detach: true\n")
    ),
  )
}

///|
test "docker compose up with file and build" {
  let result = build_and_parse([
    "compose", "-f", "docker-compose.yml", "-f", "docker-compose.prod.yml", "up",
    "--build", "--force-recreate",
  ])
  inspect(
    result,
    content=(
      #|Ok("  command: compose\n    file: [\"docker-compose.yml\", \"docker-compose.prod.yml\"]\n  command: up\n    build: true\n    force-recreate: true\n")
    ),
  )
}

///|
test "docker compose up exclusive (force-recreate vs no-recreate)" {
  let result = build_and_parse([
    "compose", "up", "--force-recreate", "--no-recreate",
  ])
  inspect(
    result,
    content=(
      #|Err("error: mutually exclusive options: --force-recreate, --no-recreate\n\nUsage: [OPTIONS] [SERVICES]...\n\nFor more information, try '--help'.")
    ),
  )
}

///|
test "docker compose down" {
  let result = build_and_parse(["compose", "down"])
  inspect(
    result,
    content=(
      #|Ok("  command: compose\n  command: down\n")
    ),
  )
}

///|
test "docker compose down --rmi (implicit value)" {
  let result = build_and_parse(["compose", "down", "--rmi"])
  inspect(
    result,
    content=(
      #|Ok("  command: compose\n  command: down\n    rmi: all\n")
    ),
  )
}

///|
test "docker compose down --rmi local" {
  let result = build_and_parse(["compose", "down", "--rmi", "local"])
  inspect(
    result,
    content=(
      #|Ok("  command: compose\n  command: down\n    rmi: local\n")
    ),
  )
}

///|
test "docker compose (no subcommand = require_cmd error)" {
  let result = build_and_parse(["compose"])
  inspect(
    result,
    content=(
      #|Err("error: subcommand required\n\nCommands:\n  up    Create and start containers\n  down  Stop and remove containers, networks\n\nUsage: [OPTIONS] [COMMAND]\n\nFor more information, try '--help'.")
    ),
  )
}

// ════════════════════════════════════════════════════════════════════
// docker network / volume
// ════════════════════════════════════════════════════════════════════

///|
test "docker network create" {
  let result = build_and_parse(["network", "create", "-d", "bridge", "mynet"])
  inspect(
    result,
    content=(
      #|Ok("  command: network\n  command: create\n")
    ),
  )
}

///|
test "docker network ls" {
  let result = build_and_parse(["network", "ls"])
  inspect(
    result,
    content=(
      #|Ok("  command: network\n  command: ls\n")
    ),
  )
}

///|
test "docker volume create" {
  let result = build_and_parse(["volume", "create", "myvolume"])
  inspect(
    result,
    content=(
      #|Ok("  command: volume\n  command: create\n")
    ),
  )
}

///|
test "docker volume rm" {
  let result = build_and_parse(["volume", "rm", "-f", "old-volume"])
  inspect(
    result,
    content=(
      #|Ok("  command: volume\n  command: rm\n")
    ),
  )
}

// ════════════════════════════════════════════════════════════════════
// Top-level shortcuts
// ════════════════════════════════════════════════════════════════════

///|
test "docker ps (shortcut for container ls)" {
  let result = build_and_parse(["ps", "--all"])
  inspect(
    result,
    content=(
      #|Ok("  command: ps\n")
    ),
  )
}

///|
test "docker build (shortcut for image build)" {
  let result = build_and_parse(["build", "-t", "myapp:latest", "."])
  inspect(
    result,
    content=(
      #|Ok("  command: build\n")
    ),
  )
}

///|
test "docker exec (shortcut)" {
  let result = build_and_parse(["exec", "-it", "myapp", "bash"])
  inspect(
    result,
    content=(
      #|Ok("  command: exec\n")
    ),
  )
}

///|
test "docker pull (shortcut)" {
  let result = build_and_parse(["pull", "redis:7"])
  inspect(
    result,
    content=(
      #|Ok("  command: pull\n")
    ),
  )
}

///|
test "docker push (shortcut)" {
  let result = build_and_parse(["push", "myapp:v1"])
  inspect(
    result,
    content=(
      #|Ok("  command: push\n")
    ),
  )
}

///|
test "docker images (shortcut for image ls)" {
  let result = build_and_parse(["images"])
  inspect(
    result,
    content=(
      #|Ok("  command: images\n")
    ),
  )
}

// ════════════════════════════════════════════════════════════════════
// Global options
// ════════════════════════════════════════════════════════════════════

///|
test "global --debug" {
  let result = build_and_parse(["--debug", "ps"])
  inspect(
    result,
    content=(
      #|Ok("  debug: true\n  command: ps\n")
    ),
  )
}

///|
test "global --log-level" {
  let result = build_and_parse(["--log-level", "debug", "ps"])
  inspect(
    result,
    content=(
      #|Ok("    log-level: debug\n  command: ps\n")
    ),
  )
}

///|
test "global --log-level invalid" {
  let result = build_and_parse(["--log-level", "trace", "ps"])
  inspect(
    result,
    content=(
      #|Err("error: value must be one of: debug, info, warn, error, fatal\n\nUsage: [OPTIONS] [COMMAND]\n\nFor more information, try '--help'.")
    ),
  )
}

///|
test "global --host with env fallback" {
  let result = build_and_parse(["ps"], env={
    "DOCKER_HOST": "tcp://remote:2375",
  })
  inspect(
    result,
    content=(
      #|Ok("    host: tcp://remote:2375\n  command: ps\n")
    ),
  )
}

///|
test "global -H shorthand" {
  let result = build_and_parse(["-H", "tcp://localhost:2375", "container", "ls"])
  inspect(
    result,
    content=(
      #|Ok("    host: tcp://localhost:2375\n  command: container\n  command: ls\n")
    ),
  )
}

// ════════════════════════════════════════════════════════════════════
// Help
// ════════════════════════════════════════════════════════════════════

///|
test "docker --help" {
  let result = build_and_parse(["--help"])
  match result {
    Ok(text) => assert_true(text.contains("mydocker"))
    Err(_) => fail("expected help text")
  }
}

///|
test "docker container --help" {
  let result = build_and_parse(["container", "--help"])
  match result {
    Ok(text) => assert_true(text.contains("container"))
    Err(_) => fail("expected help text")
  }
}

///|
test "docker run --help" {
  let result = build_and_parse(["run", "--help"])
  match result {
    Ok(text) => assert_true(text.contains("run"))
    Err(_) => fail("expected help text")
  }
}

// ════════════════════════════════════════════════════════════════════
// W-1: container run 管理パス — 複数append確認
// ════════════════════════════════════════════════════════════════════

///|
test "docker container run with publish/env/volume" {
  let result = build_and_parse([
    "container", "run", "--rm", "-p", "8080:80", "-p", "3000:3000", "-e", "APP=demo",
    "-v", "/data:/data", "--name", "myapp", "--restart", "always", "nginx:alpine",
  ])
  inspect(
    result,
    content=(
      #|Ok("  command: container\n  command: run\n    rm: true\n    name: myapp\n    restart: always\n    publish: [\"8080:80\", \"3000:3000\"]\n    volume: [\"/data:/data\"]\n    env: [\"APP=demo\"]\n    image: nginx:alpine\n")
    ),
  )
}

// ════════════════════════════════════════════════════════════════════
// Edge cases
// ════════════════════════════════════════════════════════════════════

///|
test "empty args" {
  let result = build_and_parse([])
  inspect(
    result,
    content=(
      #|Ok("")
    ),
  )
}

///|
test "unknown option" {
  let result = build_and_parse(["run", "--nonexistent", "nginx"])
  inspect(
    result,
    content=(
      #|Ok("  command: run\n")
    ),
  )
}

///|
test "container alias: list" {
  let result = build_and_parse(["container", "list", "--all"])
  inspect(
    result,
    content=(
      #|Ok("  command: container\n  command: ls\n")
    ),
  )
}

///|
test "image alias: rmi" {
  let result = build_and_parse(["image", "rmi", "old-image"])
  inspect(
    result,
    content=(
      #|Ok("  command: image\n  command: rm\n")
    ),
  )
}

///|
test "docker rm shortcut" {
  let result = build_and_parse(["rm", "-f", "old-container"])
  inspect(
    result,
    content=(
      #|Ok("  command: rm\n")
    ),
  )
}

///|
test "docker rmi shortcut" {
  let result = build_and_parse(["rmi", "old-image"])
  inspect(
    result,
    content=(
      #|Ok("  command: rmi\n")
    ),
  )
}

///|
test "compose up --no-deps (variation_false)" {
  let result = build_and_parse(["compose", "up", "--no-deps"])
  inspect(
    result,
    content=(
      #|Ok("  command: compose\n  command: up\n    no-deps: true\n")
    ),
  )
}
