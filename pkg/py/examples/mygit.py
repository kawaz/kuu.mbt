"""
mygit -- A sample git-like CLI built with kuu-py.

This is a design mock (not executable) demonstrating the kuu Python high-level API.
It mirrors the MoonBit example at examples/20260308-mygit/main.mbt.
"""

from __future__ import annotations

from typing import Annotated, Literal

import kuu

# ─── App ───

app = kuu.App(name="mygit", description="A sample git-like CLI built with kuu")


# ─── Global Options ───


@app.global_options
@kuu.exclusive("verbose", "quiet")
def global_opts(
    verbose: Annotated[
        int,
        kuu.Count(short="v", help="Increase verbosity (-v, -vv, -vvv)", variation_reset="no"),
    ] = 0,
    quiet: Annotated[bool, kuu.Option(short="q", help="Suppress output")] = False,
    color: Annotated[
        Literal["always", "never", "auto"],
        kuu.Option(help="When to use colors", implicit_value="always"),
    ] = "auto",
    debug_internal: Annotated[
        bool,
        kuu.Option(hidden=True, help="Internal debug flag"),
    ] = False,
):
    """Global options available to all subcommands."""
    ...


# ─── clone ───


@app.command()
def clone(
    url: Annotated[str, kuu.Positional(help="Repository URL")],
    directory: Annotated[str | None, kuu.Positional(help="Target directory")] = None,
    depth: Annotated[int, kuu.Option(help="Shallow clone depth", value_name="N")] = 0,
    branch: Annotated[str, kuu.Option(short="b", help="Branch to checkout", value_name="BRANCH")] = "",
    bare: Annotated[bool, kuu.Option(help="Create a bare repository")] = False,
    ctx: kuu.Context = kuu.CONTEXT,
):
    """Clone a repository."""
    print(f"Cloning {url} (depth={depth}, branch={branch or '(default)'}, bare={bare})")
    if directory:
        print(f"  into {directory}")
    print(f"  verbose={ctx.globals.verbose}")


# ─── commit ───


@app.command()
@kuu.required("message")
def commit(
    message: Annotated[
        str,
        kuu.Option(
            short="m",
            help="Commit message",
            value_name="MSG",
            post=[kuu.filters.trim, kuu.filters.non_empty],
        ),
    ] = "",
    all: Annotated[bool, kuu.Option(short="a", help="Stage all modified files")] = False,
    amend: Annotated[bool, kuu.Option(help="Amend the previous commit")] = False,
    verify: Annotated[
        bool,
        kuu.Option(help="Run pre-commit hooks (--no-verify to skip)", variation_false="no"),
    ] = True,
    author_date_is_committer_date: Annotated[
        bool,
        kuu.Option(help="Override author date with committer date", variation_unset="no"),
    ] = False,
):
    """Record changes to the repository."""
    print(f"Committing: {message} (all={all}, amend={amend}, verify={verify})")


# ─── log ───


@app.command()
def log(
    oneline: Annotated[bool, kuu.Option(help="One line per commit")] = False,
    max_count: Annotated[int, kuu.Option(short="n", help="Limit number of commits", value_name="N")] = 0,
    author: Annotated[list[str], kuu.Option(help="Filter by author (repeatable)", value_name="PATTERN")] = [],
    format: Annotated[
        str,
        kuu.Option(
            help="Pretty-print format",
            choices=["oneline", "short", "medium", "full", "fuller", "reference", "raw"],
        ),
    ] = "medium",
    graph: Annotated[bool, kuu.Option(help="Draw text-based graph")] = False,
    paths: Annotated[list[str], kuu.Rest(help="Limit to paths")] = [],
):
    """Show commit logs."""
    print(f"Log: oneline={oneline}, max_count={max_count}, format={format}")
    if author:
        print(f"  authors: {author}")
    if paths:
        print(f"  paths: {paths}")


# ─── add ───


@app.command()
def add(
    files: Annotated[list[str], kuu.Rest(help="Files to add")] = [],
    force: Annotated[bool, kuu.Option(short="f", help="Allow ignored files")] = False,
    dry_run: Annotated[bool, kuu.Option(aliases=["dryrun"], help="Don't actually add files")] = False,
    patch: Annotated[bool, kuu.Option(short="p", help="Interactively stage hunks")] = False,
):
    """Add file contents to the index."""
    print(f"Adding: {files} (force={force}, dry_run={dry_run}, patch={patch})")


# ─── push ───


@app.command()
@kuu.exclusive("force", "force_with_lease")
def push(
    remote: Annotated[str | None, kuu.Positional(help="Remote name")] = None,
    branch: Annotated[str | None, kuu.Positional(help="Branch name")] = None,
    force: Annotated[bool, kuu.Option(short="f", help="Force push")] = False,
    force_with_lease: Annotated[bool, kuu.Option(help="Safer force push")] = False,
    tags: Annotated[bool, kuu.Option(help="Push all tags")] = False,
    set_upstream: Annotated[bool, kuu.Option(short="u", help="Set upstream for the branch")] = False,
    delete: Annotated[bool, kuu.Option(short="d", help="Delete remote branch")] = False,
):
    """Update remote refs."""
    print(f"Pushing to {remote or '(default)'}/{branch or '(default)'} (force={force})")


# ─── pull ───


@app.command()
@kuu.exclusive("rebase", "ff_only")
def pull(
    remote: Annotated[str | None, kuu.Positional(help="Remote name")] = None,
    branch: Annotated[str | None, kuu.Positional(help="Branch name")] = None,
    rebase: Annotated[bool, kuu.Option(short="r", help="Rebase instead of merge")] = False,
    ff_only: Annotated[bool, kuu.Option(help="Only fast-forward merges")] = False,
):
    """Fetch and integrate remote changes."""
    print(f"Pulling {remote or '(default)'}/{branch or '(default)'} (rebase={rebase})")


# ─── branch ───


@app.command()
@kuu.exclusive("delete", "force_delete")
def branch(
    name: Annotated[str | None, kuu.Positional(help="Branch name")] = None,
    delete: Annotated[bool, kuu.Option(short="d", help="Delete a branch")] = False,
    force_delete: Annotated[bool, kuu.Option(aliases=["D"], help="Force delete a branch")] = False,
    list: Annotated[bool, kuu.Option(short="l", help="List branches")] = False,
    all: Annotated[bool, kuu.Option(short="a", help="Show both local and remote branches")] = False,
    move: Annotated[bool, kuu.Option(short="m", help="Move/rename a branch")] = False,
):
    """List, create, or delete branches."""
    print(f"Branch: {name or '(all)'} (delete={delete}, list={list})")


# ─── checkout ───


@app.command()
def checkout(
    branch: Annotated[str | None, kuu.Positional(help="Branch or commit to checkout")] = None,
    create: Annotated[str, kuu.Option(short="b", help="Create and checkout new branch", value_name="BRANCH")] = "",
    force: Annotated[bool, kuu.Option(short="f", help="Force checkout")] = False,
    files: Annotated[list[str], kuu.Dashdash(help="Files to restore")] = [],
):
    """Switch branches or restore files."""
    print(f"Checkout: {branch or create} (force={force})")
    if files:
        print(f"  files: {files}")


# ─── diff ───


@app.command()
def diff(
    staged: Annotated[bool, kuu.Option(aliases=["cached"], help="Show staged changes")] = False,
    stat: Annotated[bool, kuu.Option(help="Show diffstat only")] = False,
    unified: Annotated[
        int,
        kuu.Option(short="U", help="Lines of context", value_name="N", implicit_value=3),
    ] = 3,
    name_only: Annotated[bool, kuu.Option(help="Show only names of changed files")] = False,
    paths: Annotated[list[str], kuu.Rest(help="Limit to paths")] = [],
):
    """Show changes between commits."""
    print(f"Diff: staged={staged}, unified={unified}, stat={stat}")


# ─── status ───


@app.command()
def status(
    short: Annotated[bool, kuu.Option(short="s", help="Short format output")] = False,
    branch: Annotated[bool, kuu.Option(short="b", help="Show branch info")] = False,
    porcelain: Annotated[bool, kuu.Option(help="Machine-readable output")] = False,
):
    """Show working tree status."""
    print(f"Status: short={short}, branch={branch}, porcelain={porcelain}")


# ─── tag ───


@app.command()
@kuu.exclusive("list", "delete", "annotate")
def tag(
    tagname: Annotated[str | None, kuu.Positional(help="Tag name")] = None,
    list: Annotated[bool, kuu.Option(short="l", help="List tags")] = False,
    delete: Annotated[bool, kuu.Option(short="d", help="Delete a tag")] = False,
    annotate: Annotated[bool, kuu.Option(short="a", help="Make an annotated tag")] = False,
    message: Annotated[str, kuu.Option(short="m", help="Tag message", value_name="MSG")] = "",
):
    """Create, list, delete or verify tags."""
    print(f"Tag: {tagname} (list={list}, delete={delete}, annotate={annotate})")


# ─── remote (nested group) ───

remote = app.group(name="remote", help="Manage tracked repositories")


@remote.command()
def add(
    name: Annotated[str, kuu.Serial(group="remote-args", help="Remote name")],
    url: Annotated[str, kuu.Serial(group="remote-args", help="Remote URL")],
    fetch: Annotated[bool, kuu.Option(short="f", help="Fetch after adding")] = False,
):
    """Add a remote."""
    print(f"Remote add: {name} {url} (fetch={fetch})")


@remote.command()
def remove(
    name: Annotated[str, kuu.Positional(help="Remote name")],
):
    """Remove a remote."""
    print(f"Remote remove: {name}")


@remote.command()
def rename(
    old: Annotated[str, kuu.Serial(group="rename-args", help="Old remote name")],
    new: Annotated[str, kuu.Serial(group="rename-args", help="New remote name")],
):
    """Rename a remote."""
    print(f"Remote rename: {old} -> {new}")


# ─── stash (nested group) ───

stash = app.group(name="stash", help="Stash changes")


@stash.command()
def push(
    message: Annotated[str, kuu.Option(short="m", help="Stash message", value_name="MSG")] = "",
    files: Annotated[list[str], kuu.Dashdash(help="Files to stash")] = [],
):
    """Save local modifications."""
    print(f"Stash push: message={message}, files={files}")


@stash.command()
def pop(
    index: Annotated[int, kuu.Option(help="Stash index", value_name="N", implicit_value=0)] = 0,
):
    """Apply and remove stash."""
    print(f"Stash pop: index={index}")


@stash.command(name="list")
def stash_list():
    """List stash entries."""
    print("Stash list")


@stash.command()
def drop(
    index: Annotated[int, kuu.Option(help="Stash index to drop", value_name="N", implicit_value=0)] = 0,
):
    """Drop a stash entry."""
    print(f"Stash drop: index={index}")


# ─── config ───


@app.command()
@kuu.exclusive("global_", "local", "system")
def config(
    key: Annotated[str | None, kuu.Serial(group="config-args", help="Config key")] = None,
    value: Annotated[str | None, kuu.Serial(group="config-args", help="Config value")] = None,
    global_: Annotated[bool, kuu.Option(name="global", help="Use global config")] = False,
    local: Annotated[bool, kuu.Option(help="Use repository config")] = False,
    system: Annotated[bool, kuu.Option(help="Use system config")] = False,
):
    """Get and set options."""
    scope = "global" if global_ else "local" if local else "system" if system else "default"
    print(f"Config [{scope}]: {key}={value}")


# ─── Entry point ───

if __name__ == "__main__":
    app.run()
