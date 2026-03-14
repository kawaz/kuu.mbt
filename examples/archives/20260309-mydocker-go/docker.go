//go:build ignore

// ============================================================================
// docker.go — Docker CLI を kuu Go struct tag で完全再現！！
// NOTE: これはデザインモックです。kuu Go パッケージ (pkg/go/kuu) が
// 実装された暁に、この定義がそのまま動く理想の DX を示しています。
// 実際の動作検証は main.go + schema.go + bridge.go (WASM bridge 経由) で行います。
//
// 青山龍星（あおやま りゅうせい）だ！！ 覚えとけ！！
// この Docker CLI 定義ファイルには、俺の魂が込められてるぜ！！
// struct tag ひとつひとつに全力投球！！ 手を抜くなんてありえねぇ！！
//
// kuu の Go API が持つ表現力を、Docker っていうリアルワールドの
// 複雑な CLI で証明してやる！！ ネストしたサブコマンド？ グローバルオプション？
// 排他制約？ 全部まとめてかかってこい！！
//
// 燃えろ！！ 俺たちの CLI パーサ、kuu！！！
// ============================================================================
package main

import (
	"context"
	"fmt"
	"os"
	"strings"

	"github.com/kawaz/kuu/pkg/go/kuu"
)

// ─── Command interface ──────────────────────────────────────

type Command interface {
	Name() string
	Description() string
	Run(ctx context.Context) error
}

// ─── Root command ───────────────────────────────────────────

type DockerCmd struct {
	_ struct{} `kuu:",require_cmd,desc=A self-sufficient runtime for containers"`

	// Global options
	Verbose  int    `kuu:"--verbose,-v,count,global,desc=Increase verbosity"`
	Debug    bool   `kuu:"--debug,-D,global,desc=Enable debug mode"`
	LogLevel string `kuu:"--log-level,-l,global,default=info,choices=debug|info|warn|error|fatal,desc=Set the logging level"`
	Host     string `kuu:"--host,-H,global,desc=Daemon socket to connect to,value=HOST"`

	// Subcommands
	Run     *RunCmd     `kuu:"run,cmd,desc=Create and run a new container"`
	Build   *BuildCmd   `kuu:"build,cmd,desc=Build an image from a Dockerfile"`
	Ps      *PsCmd      `kuu:"ps,cmd,desc=List containers"`
	Images  *ImagesCmd  `kuu:"images,cmd,desc=List images"`
	Pull    *PullCmd    `kuu:"pull,cmd,desc=Download an image from a registry"`
	Push    *PushCmd    `kuu:"push,cmd,desc=Upload an image to a registry"`
	Exec    *ExecCmd    `kuu:"exec,cmd,desc=Execute a command in a running container"`
	Compose *ComposeCmd `kuu:"compose,cmd,desc=Define and run multi-container applications"`
	Network *NetworkCmd `kuu:"network,cmd,desc=Manage networks"`
	Volume  *VolumeCmd  `kuu:"volume,cmd,desc=Manage volumes"`
}

// ─── run ────────────────────────────────────────────────────

type RunCmd struct {
	_ struct{} `kuu:",desc=docker run - Create and run a new container"`

	Detach      bool     `kuu:"--detach,-d,desc=Run container in background and print container ID"`
	Interactive bool     `kuu:"--interactive,-i,desc=Keep STDIN open even if not attached"`
	TTY         bool     `kuu:"--tty,-t,desc=Allocate a pseudo-TTY"`
	Remove      bool     `kuu:"--rm,desc=Automatically remove the container when it exits"`
	Name        string   `kuu:"--name,desc=Assign a name to the container,value=NAME"`
	Publish     []string `kuu:"--publish,-p,append,desc=Publish a container's port(s) to the host,value=HOST:CONTAINER"`
	Volume      []string `kuu:"--volume,-V,append,desc=Bind mount a volume,value=SRC:DST"`
	Env         []string `kuu:"--env,-e,append,desc=Set environment variables,value=KEY=VALUE"`
	Network     string   `kuu:"--network,desc=Connect a container to a network,value=NETWORK"`
	Restart     string   `kuu:"--restart,default=no,desc=Restart policy to apply when a container exits,choices=no|always|unless-stopped|on-failure"`
	Image       string   `kuu:"image,pos,required,desc=Container image"`
	Command     []string `kuu:"command,rest,desc=Command to run in the container"`
}

func (c *RunCmd) Name() string        { return "run" }
func (c *RunCmd) Description() string { return "Create and run a new container" }
func (c *RunCmd) Run(ctx context.Context) error {
	fmt.Printf("run: image=%s detach=%v interactive=%v tty=%v rm=%v\n",
		c.Image, c.Detach, c.Interactive, c.TTY, c.Remove)
	if c.Name != "" {
		fmt.Printf("  name=%s\n", c.Name)
	}
	if len(c.Publish) > 0 {
		fmt.Printf("  publish=%s\n", strings.Join(c.Publish, ", "))
	}
	if len(c.Volume) > 0 {
		fmt.Printf("  volume=%s\n", strings.Join(c.Volume, ", "))
	}
	if len(c.Env) > 0 {
		fmt.Printf("  env=%s\n", strings.Join(c.Env, ", "))
	}
	if c.Network != "" {
		fmt.Printf("  network=%s\n", c.Network)
	}
	fmt.Printf("  restart=%s\n", c.Restart)
	if len(c.Command) > 0 {
		fmt.Printf("  command=%s\n", strings.Join(c.Command, " "))
	}
	return nil
}

// ─── build ──────────────────────────────────────────────────

type BuildCmd struct {
	_ struct{} `kuu:",desc=docker build - Build an image from a Dockerfile"`

	Tag      []string `kuu:"--tag,-t,append,desc=Name and optionally a tag (name:tag),value=NAME:TAG"`
	File     string   `kuu:"--file,-f,default=Dockerfile,desc=Name of the Dockerfile,value=FILE"`
	NoCache  bool     `kuu:"--no-cache,desc=Do not use cache when building the image"`
	Pull     bool     `kuu:"--pull,desc=Always attempt to pull a newer version of the image"`
	BuildArg []string `kuu:"--build-arg,append,desc=Set build-time variables,value=KEY=VALUE"`
	Target   string   `kuu:"--target,desc=Set the target build stage to build,value=STAGE"`
	Platform string   `kuu:"--platform,desc=Set platform if server is multi-platform capable,value=PLATFORM"`
	Path     string   `kuu:"path,pos,desc=Build context path"`
}

func (c *BuildCmd) Name() string        { return "build" }
func (c *BuildCmd) Description() string { return "Build an image from a Dockerfile" }
func (c *BuildCmd) Run(ctx context.Context) error {
	fmt.Printf("build: file=%s no-cache=%v pull=%v\n", c.File, c.NoCache, c.Pull)
	if len(c.Tag) > 0 {
		fmt.Printf("  tag=%s\n", strings.Join(c.Tag, ", "))
	}
	if len(c.BuildArg) > 0 {
		fmt.Printf("  build-arg=%s\n", strings.Join(c.BuildArg, ", "))
	}
	if c.Target != "" {
		fmt.Printf("  target=%s\n", c.Target)
	}
	if c.Platform != "" {
		fmt.Printf("  platform=%s\n", c.Platform)
	}
	path := c.Path
	if path == "" {
		path = "."
	}
	fmt.Printf("  path=%s\n", path)
	return nil
}

// ─── ps ─────────────────────────────────────────────────────

type PsCmd struct {
	_ struct{} `kuu:",desc=docker ps - List containers"`

	All    bool     `kuu:"--all,-a,desc=Show all containers (default shows just running),exclusive=ps-view"`
	Quiet  bool     `kuu:"--quiet,-q,desc=Only display container IDs"`
	Format string   `kuu:"--format,desc=Format output using a custom template,value=FORMAT"`
	Filter []string `kuu:"--filter,-f,append,desc=Filter output based on conditions provided,value=FILTER"`
	Last   int      `kuu:"--last,-n,default=0,desc=Show n last created containers (includes all states),value=N,exclusive=ps-view"`
}

func (c *PsCmd) Name() string        { return "ps" }
func (c *PsCmd) Description() string { return "List containers" }
func (c *PsCmd) Run(ctx context.Context) error {
	fmt.Printf("ps: all=%v quiet=%v last=%d\n", c.All, c.Quiet, c.Last)
	if c.Format != "" {
		fmt.Printf("  format=%s\n", c.Format)
	}
	if len(c.Filter) > 0 {
		fmt.Printf("  filter=%s\n", strings.Join(c.Filter, ", "))
	}
	return nil
}

// ─── images ─────────────────────────────────────────────────

type ImagesCmd struct {
	_ struct{} `kuu:",desc=docker images - List images"`

	All        bool     `kuu:"--all,-a,desc=Show all images (default hides intermediate images)"`
	Quiet      bool     `kuu:"--quiet,-q,desc=Only show image IDs"`
	Format     string   `kuu:"--format,desc=Format output using a custom template,value=FORMAT"`
	Filter     []string `kuu:"--filter,-f,append,desc=Filter output based on conditions provided,value=FILTER"`
	Repository string   `kuu:"repository,pos,desc=Repository name to filter by"`
}

func (c *ImagesCmd) Name() string        { return "images" }
func (c *ImagesCmd) Description() string { return "List images" }
func (c *ImagesCmd) Run(ctx context.Context) error {
	fmt.Printf("images: all=%v quiet=%v\n", c.All, c.Quiet)
	if c.Format != "" {
		fmt.Printf("  format=%s\n", c.Format)
	}
	if len(c.Filter) > 0 {
		fmt.Printf("  filter=%s\n", strings.Join(c.Filter, ", "))
	}
	if c.Repository != "" {
		fmt.Printf("  repository=%s\n", c.Repository)
	}
	return nil
}

// ─── pull ───────────────────────────────────────────────────

type PullCmd struct {
	_ struct{} `kuu:",desc=docker pull - Download an image from a registry"`

	AllTags  bool   `kuu:"--all-tags,-a,desc=Download all tagged images in the repository"`
	Platform string `kuu:"--platform,desc=Set platform if server is multi-platform capable,value=PLATFORM"`
	Quiet    bool   `kuu:"--quiet,-q,desc=Suppress verbose output"`
	Image    string `kuu:"image,pos,required,desc=Image name[:tag|@digest]"`
}

func (c *PullCmd) Name() string        { return "pull" }
func (c *PullCmd) Description() string { return "Download an image from a registry" }
func (c *PullCmd) Run(ctx context.Context) error {
	fmt.Printf("pull: image=%s all-tags=%v quiet=%v\n", c.Image, c.AllTags, c.Quiet)
	if c.Platform != "" {
		fmt.Printf("  platform=%s\n", c.Platform)
	}
	return nil
}

// ─── push ───────────────────────────────────────────────────

type PushCmd struct {
	_ struct{} `kuu:",desc=docker push - Upload an image to a registry"`

	AllTags bool   `kuu:"--all-tags,-a,desc=Push all tags of an image to the repository"`
	Quiet   bool   `kuu:"--quiet,-q,desc=Suppress verbose output"`
	Image   string `kuu:"image,pos,required,desc=Image name[:tag]"`
}

func (c *PushCmd) Name() string        { return "push" }
func (c *PushCmd) Description() string { return "Upload an image to a registry" }
func (c *PushCmd) Run(ctx context.Context) error {
	fmt.Printf("push: image=%s all-tags=%v quiet=%v\n", c.Image, c.AllTags, c.Quiet)
	return nil
}

// ─── exec ───────────────────────────────────────────────────

type ExecCmd struct {
	_ struct{} `kuu:",desc=docker exec - Execute a command in a running container"`

	Interactive bool     `kuu:"--interactive,-i,desc=Keep STDIN open even if not attached"`
	TTY         bool     `kuu:"--tty,-t,desc=Allocate a pseudo-TTY"`
	User        string   `kuu:"--user,-u,desc=Username or UID (format: <name|uid>[:<group|gid>]),value=USER"`
	Workdir     string   `kuu:"--workdir,-w,desc=Working directory inside the container,value=DIR"`
	Env         []string `kuu:"--env,-e,append,desc=Set environment variables,value=KEY=VALUE"`
	Container   string   `kuu:"container,pos,required,desc=Container ID or name"`
	Command     []string `kuu:"command,rest,desc=Command and arguments to execute"`
}

func (c *ExecCmd) Name() string        { return "exec" }
func (c *ExecCmd) Description() string { return "Execute a command in a running container" }
func (c *ExecCmd) Run(ctx context.Context) error {
	fmt.Printf("exec: container=%s interactive=%v tty=%v\n",
		c.Container, c.Interactive, c.TTY)
	if c.User != "" {
		fmt.Printf("  user=%s\n", c.User)
	}
	if c.Workdir != "" {
		fmt.Printf("  workdir=%s\n", c.Workdir)
	}
	if len(c.Env) > 0 {
		fmt.Printf("  env=%s\n", strings.Join(c.Env, ", "))
	}
	if len(c.Command) > 0 {
		fmt.Printf("  command=%s\n", strings.Join(c.Command, " "))
	}
	return nil
}

// ─── compose (nested subcommands) ───────────────────────────

type ComposeCmd struct {
	_ struct{} `kuu:",require_cmd,desc=docker compose - Define and run multi-container applications with Docker"`

	File        []string       `kuu:"--file,-f,append,desc=Compose configuration files,value=FILE"`
	ProjectName string         `kuu:"--project-name,-p,desc=Project name,value=NAME"`
	EnvFile     string         `kuu:"--env-file,desc=Specify an alternate environment file,value=PATH"`
	Up          *ComposeUpCmd  `kuu:"up,cmd,desc=Create and start containers"`
	Down        *ComposeDownCmd `kuu:"down,cmd,desc=Stop and remove containers and networks"`
	Logs        *ComposeLogsCmd `kuu:"logs,cmd,desc=View output from containers"`
	Ps          *ComposePsCmd  `kuu:"ps,cmd,desc=List containers"`
}

func (c *ComposeCmd) Name() string        { return "compose" }
func (c *ComposeCmd) Description() string { return "Define and run multi-container applications with Docker" }
func (c *ComposeCmd) Run(ctx context.Context) error {
	fmt.Printf("compose:")
	if len(c.File) > 0 {
		fmt.Printf(" file=%s", strings.Join(c.File, ", "))
	}
	if c.ProjectName != "" {
		fmt.Printf(" project-name=%s", c.ProjectName)
	}
	fmt.Println()
	// Dispatch to active subcommand
	switch {
	case c.Up != nil:
		return c.Up.Run(ctx)
	case c.Down != nil:
		return c.Down.Run(ctx)
	case c.Logs != nil:
		return c.Logs.Run(ctx)
	case c.Ps != nil:
		return c.Ps.Run(ctx)
	}
	return nil
}

// compose up

type ComposeUpCmd struct {
	_ struct{} `kuu:",desc=docker compose up - Create and start containers"`

	Detach        bool     `kuu:"--detach,-d,desc=Detached mode: Run containers in the background"`
	Build         bool     `kuu:"--build,desc=Build images before starting containers"`
	ForceRecreate bool     `kuu:"--force-recreate,desc=Recreate containers even if their configuration and image haven't changed"`
	NoDeps        bool     `kuu:"--no-deps,desc=Don't start linked services"`
	Scale         int      `kuu:"--scale,default=1,desc=Scale SERVICE to NUM instances,value=N"`
	Services      []string `kuu:"services,rest,desc=Services to start"`
}

func (c *ComposeUpCmd) Name() string        { return "up" }
func (c *ComposeUpCmd) Description() string { return "Create and start containers" }
func (c *ComposeUpCmd) Run(ctx context.Context) error {
	fmt.Printf("  up: detach=%v build=%v force-recreate=%v no-deps=%v scale=%d\n",
		c.Detach, c.Build, c.ForceRecreate, c.NoDeps, c.Scale)
	if len(c.Services) > 0 {
		fmt.Printf("    services=%s\n", strings.Join(c.Services, ", "))
	}
	return nil
}

// compose down

type ComposeDownCmd struct {
	_ struct{} `kuu:",desc=docker compose down - Stop and remove containers and networks"`

	Rmi            string `kuu:"--rmi,desc=Remove images used by services (all or local),choices=all|local,implicit=all"`
	Volumes        bool   `kuu:"--volumes,-V,desc=Remove named volumes declared in the volumes section"`
	RemoveOrphans  bool   `kuu:"--remove-orphans,desc=Remove containers for services not defined in the Compose file"`
}

func (c *ComposeDownCmd) Name() string        { return "down" }
func (c *ComposeDownCmd) Description() string { return "Stop and remove containers and networks" }
func (c *ComposeDownCmd) Run(ctx context.Context) error {
	fmt.Printf("  down: volumes=%v remove-orphans=%v\n", c.Volumes, c.RemoveOrphans)
	if c.Rmi != "" {
		fmt.Printf("    rmi=%s\n", c.Rmi)
	}
	return nil
}

// compose logs

type ComposeLogsCmd struct {
	_ struct{} `kuu:",desc=docker compose logs - View output from containers"`

	Follow     bool     `kuu:"--follow,-f,desc=Follow log output"`
	Tail       string   `kuu:"--tail,default=all,desc=Number of lines to show from the end of the logs,value=N"`
	Timestamps bool     `kuu:"--timestamps,-t,desc=Show timestamps"`
	Services   []string `kuu:"services,rest,desc=Services to show logs for"`
}

func (c *ComposeLogsCmd) Name() string        { return "logs" }
func (c *ComposeLogsCmd) Description() string { return "View output from containers" }
func (c *ComposeLogsCmd) Run(ctx context.Context) error {
	fmt.Printf("  logs: follow=%v tail=%s timestamps=%v\n", c.Follow, c.Tail, c.Timestamps)
	if len(c.Services) > 0 {
		fmt.Printf("    services=%s\n", strings.Join(c.Services, ", "))
	}
	return nil
}

// compose ps

type ComposePsCmd struct {
	_ struct{} `kuu:",desc=docker compose ps - List containers"`

	All      bool     `kuu:"--all,-a,desc=Show all stopped containers"`
	Quiet    bool     `kuu:"--quiet,-q,desc=Only display IDs"`
	Format   string   `kuu:"--format,desc=Format output using a custom template,value=FORMAT"`
	Services []string `kuu:"services,rest,desc=Services to filter"`
}

func (c *ComposePsCmd) Name() string        { return "ps" }
func (c *ComposePsCmd) Description() string { return "List containers" }
func (c *ComposePsCmd) Run(ctx context.Context) error {
	fmt.Printf("  ps: all=%v quiet=%v\n", c.All, c.Quiet)
	if c.Format != "" {
		fmt.Printf("    format=%s\n", c.Format)
	}
	if len(c.Services) > 0 {
		fmt.Printf("    services=%s\n", strings.Join(c.Services, ", "))
	}
	return nil
}

// ─── network (nested subcommands) ───────────────────────────

type NetworkCmd struct {
	_ struct{} `kuu:",require_cmd,desc=docker network - Manage networks"`

	Create  *NetworkCreateCmd  `kuu:"create,cmd,desc=Create a network"`
	Ls      *NetworkLsCmd      `kuu:"ls,cmd,desc=List networks"`
	Rm      *NetworkRmCmd      `kuu:"rm,cmd,desc=Remove one or more networks"`
	Inspect *NetworkInspectCmd `kuu:"inspect,cmd,desc=Display detailed information on one or more networks"`
}

func (c *NetworkCmd) Name() string        { return "network" }
func (c *NetworkCmd) Description() string { return "Manage networks" }
func (c *NetworkCmd) Run(ctx context.Context) error {
	switch {
	case c.Create != nil:
		return c.Create.Run(ctx)
	case c.Ls != nil:
		return c.Ls.Run(ctx)
	case c.Rm != nil:
		return c.Rm.Run(ctx)
	case c.Inspect != nil:
		return c.Inspect.Run(ctx)
	}
	return nil
}

// network create

type NetworkCreateCmd struct {
	_ struct{} `kuu:",desc=docker network create - Create a network"`

	Driver   string   `kuu:"--driver,-d,default=bridge,desc=Driver to manage the Network,choices=bridge|host|overlay|macvlan|none"`
	Subnet   []string `kuu:"--subnet,append,desc=Subnet in CIDR format that represents a network segment,value=CIDR"`
	Gateway  []string `kuu:"--gateway,append,desc=IPv4 or IPv6 Gateway for the master subnet,value=IP"`
	Internal bool     `kuu:"--internal,desc=Restrict external access to the network"`
	Label    []string `kuu:"--label,append,desc=Set metadata on a network,value=KEY=VALUE"`
	Name     string   `kuu:"name,pos,required,desc=Network name"`
}

func (c *NetworkCreateCmd) Name() string        { return "create" }
func (c *NetworkCreateCmd) Description() string { return "Create a network" }
func (c *NetworkCreateCmd) Run(ctx context.Context) error {
	fmt.Printf("  network create: name=%s driver=%s internal=%v\n", c.Name, c.Driver, c.Internal)
	if len(c.Subnet) > 0 {
		fmt.Printf("    subnet=%s\n", strings.Join(c.Subnet, ", "))
	}
	if len(c.Gateway) > 0 {
		fmt.Printf("    gateway=%s\n", strings.Join(c.Gateway, ", "))
	}
	if len(c.Label) > 0 {
		fmt.Printf("    label=%s\n", strings.Join(c.Label, ", "))
	}
	return nil
}

// network ls

type NetworkLsCmd struct {
	_ struct{} `kuu:",desc=docker network ls - List networks"`

	Format string   `kuu:"--format,desc=Format output using a custom template,value=FORMAT"`
	Filter []string `kuu:"--filter,-f,append,desc=Provide filter values,value=FILTER"`
	Quiet  bool     `kuu:"--quiet,-q,desc=Only display network IDs"`
}

func (c *NetworkLsCmd) Name() string        { return "ls" }
func (c *NetworkLsCmd) Description() string { return "List networks" }
func (c *NetworkLsCmd) Run(ctx context.Context) error {
	fmt.Printf("  network ls: quiet=%v\n", c.Quiet)
	if c.Format != "" {
		fmt.Printf("    format=%s\n", c.Format)
	}
	if len(c.Filter) > 0 {
		fmt.Printf("    filter=%s\n", strings.Join(c.Filter, ", "))
	}
	return nil
}

// network rm

type NetworkRmCmd struct {
	_ struct{} `kuu:",desc=docker network rm - Remove one or more networks"`

	Force    bool     `kuu:"--force,-f,desc=Do not error if the network does not exist"`
	Networks []string `kuu:"networks,rest,desc=Network names or IDs to remove"`
}

func (c *NetworkRmCmd) Name() string        { return "rm" }
func (c *NetworkRmCmd) Description() string { return "Remove one or more networks" }
func (c *NetworkRmCmd) Run(ctx context.Context) error {
	fmt.Printf("  network rm: force=%v networks=%s\n", c.Force, strings.Join(c.Networks, ", "))
	return nil
}

// network inspect

type NetworkInspectCmd struct {
	_ struct{} `kuu:",desc=docker network inspect - Display detailed information on one or more networks"`

	Format   string   `kuu:"--format,-f,desc=Format output using a custom template,value=FORMAT"`
	Networks []string `kuu:"networks,rest,desc=Network names or IDs to inspect"`
}

func (c *NetworkInspectCmd) Name() string        { return "inspect" }
func (c *NetworkInspectCmd) Description() string { return "Display detailed information on one or more networks" }
func (c *NetworkInspectCmd) Run(ctx context.Context) error {
	fmt.Printf("  network inspect: networks=%s\n", strings.Join(c.Networks, ", "))
	if c.Format != "" {
		fmt.Printf("    format=%s\n", c.Format)
	}
	return nil
}

// ─── volume (nested subcommands) ────────────────────────────

type VolumeCmd struct {
	_ struct{} `kuu:",require_cmd,desc=docker volume - Manage volumes"`

	Create  *VolumeCreateCmd  `kuu:"create,cmd,desc=Create a volume"`
	Ls      *VolumeLsCmd      `kuu:"ls,cmd,desc=List volumes"`
	Rm      *VolumeRmCmd      `kuu:"rm,cmd,desc=Remove one or more volumes"`
	Inspect *VolumeInspectCmd `kuu:"inspect,cmd,desc=Display detailed information on one or more volumes"`
}

func (c *VolumeCmd) Name() string        { return "volume" }
func (c *VolumeCmd) Description() string { return "Manage volumes" }
func (c *VolumeCmd) Run(ctx context.Context) error {
	switch {
	case c.Create != nil:
		return c.Create.Run(ctx)
	case c.Ls != nil:
		return c.Ls.Run(ctx)
	case c.Rm != nil:
		return c.Rm.Run(ctx)
	case c.Inspect != nil:
		return c.Inspect.Run(ctx)
	}
	return nil
}

// volume create

type VolumeCreateCmd struct {
	_ struct{} `kuu:",desc=docker volume create - Create a volume"`

	Driver string   `kuu:"--driver,-d,default=local,desc=Specify volume driver name,value=DRIVER"`
	Label  []string `kuu:"--label,append,desc=Set metadata for a volume,value=KEY=VALUE"`
	Opt    []string `kuu:"--opt,-o,append,desc=Set driver specific options,value=KEY=VALUE"`
	Name   string   `kuu:"name,pos,desc=Volume name (auto-generated if not specified)"`
}

func (c *VolumeCreateCmd) Name() string        { return "create" }
func (c *VolumeCreateCmd) Description() string { return "Create a volume" }
func (c *VolumeCreateCmd) Run(ctx context.Context) error {
	name := c.Name
	if name == "" {
		name = "(auto)"
	}
	fmt.Printf("  volume create: name=%s driver=%s\n", name, c.Driver)
	if len(c.Label) > 0 {
		fmt.Printf("    label=%s\n", strings.Join(c.Label, ", "))
	}
	if len(c.Opt) > 0 {
		fmt.Printf("    opt=%s\n", strings.Join(c.Opt, ", "))
	}
	return nil
}

// volume ls

type VolumeLsCmd struct {
	_ struct{} `kuu:",desc=docker volume ls - List volumes"`

	Format string   `kuu:"--format,desc=Format output using a custom template,value=FORMAT"`
	Filter []string `kuu:"--filter,-f,append,desc=Provide filter values,value=FILTER"`
	Quiet  bool     `kuu:"--quiet,-q,desc=Only display volume names"`
}

func (c *VolumeLsCmd) Name() string        { return "ls" }
func (c *VolumeLsCmd) Description() string { return "List volumes" }
func (c *VolumeLsCmd) Run(ctx context.Context) error {
	fmt.Printf("  volume ls: quiet=%v\n", c.Quiet)
	if c.Format != "" {
		fmt.Printf("    format=%s\n", c.Format)
	}
	if len(c.Filter) > 0 {
		fmt.Printf("    filter=%s\n", strings.Join(c.Filter, ", "))
	}
	return nil
}

// volume rm

type VolumeRmCmd struct {
	_ struct{} `kuu:",desc=docker volume rm - Remove one or more volumes"`

	Force   bool     `kuu:"--force,-f,desc=Force the removal of one or more volumes"`
	Volumes []string `kuu:"volumes,rest,desc=Volume names to remove"`
}

func (c *VolumeRmCmd) Name() string        { return "rm" }
func (c *VolumeRmCmd) Description() string { return "Remove one or more volumes" }
func (c *VolumeRmCmd) Run(ctx context.Context) error {
	fmt.Printf("  volume rm: force=%v volumes=%s\n", c.Force, strings.Join(c.Volumes, ", "))
	return nil
}

// volume inspect

type VolumeInspectCmd struct {
	_ struct{} `kuu:",desc=docker volume inspect - Display detailed information on one or more volumes"`

	Format  string   `kuu:"--format,-f,desc=Format output using a custom template,value=FORMAT"`
	Volumes []string `kuu:"volumes,rest,desc=Volume names to inspect"`
}

func (c *VolumeInspectCmd) Name() string        { return "inspect" }
func (c *VolumeInspectCmd) Description() string { return "Display detailed information on one or more volumes" }
func (c *VolumeInspectCmd) Run(ctx context.Context) error {
	fmt.Printf("  volume inspect: volumes=%s\n", strings.Join(c.Volumes, ", "))
	if c.Format != "" {
		fmt.Printf("    format=%s\n", c.Format)
	}
	return nil
}

// ─── main ───────────────────────────────────────────────────

func main() {
	root, err := kuu.Parse[DockerCmd](os.Args[1:])
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}

	// Print global options
	fmt.Printf("=== Global Options ===\n")
	fmt.Printf("verbose=%d debug=%v log-level=%s\n", root.Verbose, root.Debug, root.LogLevel)
	if root.Host != "" {
		fmt.Printf("host=%s\n", root.Host)
	}
	fmt.Println()

	// Dispatch subcommands via Command interface
	ctx := context.Background()
	var cmd Command
	switch {
	case root.Run != nil:
		cmd = root.Run
	case root.Build != nil:
		cmd = root.Build
	case root.Ps != nil:
		cmd = root.Ps
	case root.Images != nil:
		cmd = root.Images
	case root.Pull != nil:
		cmd = root.Pull
	case root.Push != nil:
		cmd = root.Push
	case root.Exec != nil:
		cmd = root.Exec
	case root.Compose != nil:
		cmd = root.Compose
	case root.Network != nil:
		cmd = root.Network
	case root.Volume != nil:
		cmd = root.Volume
	}

	if cmd != nil {
		fmt.Printf("=== %s ===\n", cmd.Name())
		if err := cmd.Run(ctx); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
	}
}
