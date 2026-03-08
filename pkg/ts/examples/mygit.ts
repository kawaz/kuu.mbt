/**
 * mygit.ts — kuu TypeScript 高級 API のモックサンプル
 *
 * このファイルは実行不要。TypeScript の型システムを使って
 * 「ユーザーがこう書ける」というゴールイメージを示す。
 *
 * core (WASM) が裏で動く前提だが、ここでは型レベルの設計のみ。
 */

// ============================================================
// 1. 型定義（pkg/ts/src/ に実装される想定）
// ============================================================

// --- コンビネータ定義型 ---

type PostFilter = "trim" | "nonEmpty";

interface FlagDef<D extends boolean = false> {
  readonly kind: "flag";
  readonly default?: D;
  readonly short?: string;
  readonly description?: string;
  readonly variationFalse?: string;
  readonly variationTrue?: string;
  readonly variationToggle?: string;
  readonly variationReset?: string;
  readonly variationUnset?: string;
  readonly hidden?: boolean;
}

interface StringOptDef<
  C extends readonly string[] = readonly string[],
  R extends boolean = false,
  Def extends string | undefined = undefined,
> {
  readonly kind: "stringOpt";
  readonly default?: Def;
  readonly choices?: C;
  readonly implicitValue?: string;
  readonly required?: R;
  readonly short?: string;
  readonly description?: string;
  readonly valueName?: string;
  readonly post?: readonly PostFilter[];
  readonly hidden?: boolean;
}

interface IntOptDef<
  R extends boolean = false,
  Def extends number | undefined = undefined,
> {
  readonly kind: "intOpt";
  readonly default?: Def;
  readonly implicitValue?: number;
  readonly required?: R;
  readonly short?: string;
  readonly description?: string;
  readonly valueName?: string;
  readonly hidden?: boolean;
}

interface CountDef {
  readonly kind: "count";
  readonly short?: string;
  readonly description?: string;
  readonly variationReset?: string;
  readonly hidden?: boolean;
}

interface AppendStringDef {
  readonly kind: "appendString";
  readonly short?: string;
  readonly description?: string;
  readonly valueName?: string;
  readonly hidden?: boolean;
}

interface AppendIntDef {
  readonly kind: "appendInt";
  readonly short?: string;
  readonly description?: string;
  readonly valueName?: string;
  readonly hidden?: boolean;
}

interface PositionalDef<R extends boolean = false> {
  readonly kind: "positional";
  readonly description?: string;
  readonly required?: R;
}

interface RestDef {
  readonly kind: "rest";
  readonly description?: string;
}

interface DashdashDef {
  readonly kind: "dashdash";
  readonly separator?: string;
}

// コンビネータのユニオン
type AnyOptDef =
  | FlagDef<any>
  | StringOptDef<any, any, any>
  | IntOptDef<any, any>
  | CountDef
  | AppendStringDef
  | AppendIntDef
  | PositionalDef<any>
  | RestDef
  | DashdashDef;

// --- サブコマンド定義型 ---

interface SubSchema<
  Opts extends Record<string, AnyOptDef> = Record<string, AnyOptDef>,
  Cmds extends Record<string, SubSchema> | undefined = undefined,
> {
  readonly description?: string;
  readonly requireCmd?: boolean;
  readonly options?: Opts;
  readonly exclusive?: ReadonlyArray<readonly string[]>;
  readonly commands?: Cmds;
}

interface RootSchema<
  G extends Record<string, AnyOptDef> = Record<string, AnyOptDef>,
  Cmds extends Record<string, SubSchema> = Record<string, SubSchema>,
> {
  readonly description?: string;
  readonly requireCmd?: boolean;
  readonly globals?: G;
  readonly exclusive?: ReadonlyArray<readonly string[]>;
  readonly commands?: Cmds;
}

// --- 型推論エンジン ---

// コンビネータ定義 → 値の型
type InferOptType<D> =
  D extends FlagDef<any>     ? boolean :
  D extends CountDef         ? number :
  D extends AppendStringDef  ? string[] :
  D extends AppendIntDef     ? number[] :
  D extends RestDef          ? string[] :
  D extends DashdashDef      ? string[] :
  D extends StringOptDef<infer C, infer _R, infer _D> ?
    (C extends readonly [] ? string :
     string[] extends C ? string :
     C[number]) :
  D extends IntOptDef<any, any> ? number :
  D extends PositionalDef<any>  ? string :
  never;

// optional かどうかの判定
type IsNonOptional<D> =
  D extends FlagDef<any>    ? true :
  D extends CountDef        ? true :
  D extends AppendStringDef ? true :
  D extends AppendIntDef    ? true :
  D extends RestDef         ? true :
  D extends DashdashDef     ? true :
  D extends { required: true }  ? true :
  D extends { default: infer V } ? (V extends undefined ? false : true) :
  false;

// options レコード → 結果型 (required と optional を分離)
type InferOptions<Opts extends Record<string, AnyOptDef>> =
  { [K in keyof Opts as IsNonOptional<Opts[K]> extends true ? K : never]: InferOptType<Opts[K]> }
  & { [K in keyof Opts as IsNonOptional<Opts[K]> extends true ? never : K]?: InferOptType<Opts[K]> };

// サブコマンド → discriminated union
type InferCommand<Cmds extends Record<string, SubSchema>> = {
  [K in keyof Cmds & string]:
    Cmds[K] extends { commands: infer SC extends Record<string, SubSchema>; options: infer O extends Record<string, AnyOptDef> }
      ? { name: K; options: InferOptions<O>; command: InferCommand<SC> }
    : Cmds[K] extends { commands: infer SC extends Record<string, SubSchema> }
      ? { name: K; command: InferCommand<SC> }
    : Cmds[K] extends { options: infer O extends Record<string, AnyOptDef> }
      ? { name: K; options: InferOptions<O> }
    : { name: K };
}[keyof Cmds & string];

// トップレベル推論
type Infer<S> =
  S extends { globals: infer G extends Record<string, AnyOptDef>; commands: infer C extends Record<string, SubSchema> }
    ? { globals: InferOptions<G>; command: InferCommand<C> }
  : S extends { commands: infer C extends Record<string, SubSchema> }
    ? { command: InferCommand<C> }
  : S extends { globals: infer G extends Record<string, AnyOptDef> }
    ? { globals: InferOptions<G> }
  : {};

// --- コンビネータファクトリ関数 ---

declare function flag<D extends boolean = false>(
  opts?: Omit<FlagDef<D>, "kind">,
): FlagDef<D>;

declare function stringOpt<
  const C extends readonly string[] = readonly [],
  R extends boolean = false,
  Def extends string | undefined = undefined,
>(
  opts: Omit<StringOptDef<C, R, Def>, "kind">,
): StringOptDef<C, R, Def>;

declare function intOpt<
  R extends boolean = false,
  Def extends number | undefined = undefined,
>(
  opts: Omit<IntOptDef<R, Def>, "kind">,
): IntOptDef<R, Def>;

declare function count(
  opts?: Omit<CountDef, "kind">,
): CountDef;

declare function appendString(
  opts?: Omit<AppendStringDef, "kind">,
): AppendStringDef;

declare function appendInt(
  opts?: Omit<AppendIntDef, "kind">,
): AppendIntDef;

declare function positional<R extends boolean = false>(
  opts?: Omit<PositionalDef<R>, "kind">,
): PositionalDef<R>;

declare function rest(
  opts?: Omit<RestDef, "kind">,
): RestDef;

declare function dashdash(
  opts?: Omit<DashdashDef, "kind">,
): DashdashDef;

declare function sub<
  Opts extends Record<string, AnyOptDef> = Record<string, never>,
  Cmds extends Record<string, SubSchema> | undefined = undefined,
>(
  schema: Omit<SubSchema<Opts, Cmds>, never>,
): SubSchema<Opts, Cmds>;

// --- kuu() エントリポイント ---

interface KuuParser<S extends RootSchema> {
  parse(args: string[]): Promise<Infer<S>>;
}

declare function kuu<
  G extends Record<string, AnyOptDef>,
  Cmds extends Record<string, SubSchema>,
>(
  schema: RootSchema<G, Cmds>,
): KuuParser<RootSchema<G, Cmds>>;

// --- エラー型 ---

declare class KuuParseError extends Error {
  readonly helpText: string;
}

declare class KuuHelpRequested extends Error {
  readonly helpText: string;
}

// --- 網羅チェックヘルパー ---

function exhaustive(_: never): never {
  throw new Error("unreachable");
}

// ============================================================
// 2. mygit スキーマ定義 — ユーザーが書くコード
// ============================================================

const schema = kuu({
  description: "mygit - A sample git-like CLI built with kuu",
  requireCmd: true,

  globals: {
    verbose: count({ short: "v", description: "Increase verbosity (-v, -vv, -vvv)", variationReset: "no" }),
    quiet:   flag({ short: "q", description: "Suppress output" }),
    color:   stringOpt({
      default: "auto",
      choices: ["always", "never", "auto"] as const,
      implicitValue: "always",
      description: "When to use colors",
    }),
  },
  exclusive: [["verbose", "quiet"]],

  commands: {
    clone: sub({
      description: "Clone a repository",
      options: {
        url:       positional({ description: "Repository URL", required: true as const }),
        directory: positional({ description: "Target directory" }),
        depth:     intOpt({ default: 0, description: "Shallow clone depth", valueName: "N" }),
        branch:    stringOpt({ default: "", short: "b", description: "Checkout branch", valueName: "BRANCH" }),
        bare:      flag({ description: "Create a bare repository" }),
      },
    }),

    commit: sub({
      description: "Record changes",
      options: {
        message: stringOpt({
          default: "", short: "m", required: true as const,
          post: ["trim", "nonEmpty"] as const,
          description: "Commit message",
          valueName: "MSG",
        }),
        all:    flag({ short: "a", description: "Stage all modified files" }),
        amend:  flag({ description: "Amend the previous commit" }),
        verify: flag({ default: true, description: "Run pre-commit hooks", variationFalse: "no" }),
      },
    }),

    log: sub({
      description: "Show commit logs",
      options: {
        oneline:  flag({ description: "One line per commit" }),
        maxCount: intOpt({ default: 0, short: "n", description: "Limit commits", valueName: "N" }),
        author:   appendString({ description: "Filter by author (repeatable)", valueName: "PATTERN" }),
        format:   stringOpt({
          default: "medium",
          choices: ["oneline", "short", "medium", "full", "fuller", "reference", "raw"] as const,
          description: "Pretty-print format",
        }),
        graph:    flag({ description: "Draw text-based graph" }),
        paths:    rest({ description: "Limit to paths" }),
      },
    }),

    add: sub({
      description: "Add file contents to the index",
      options: {
        force:  flag({ short: "f", description: "Allow ignored files" }),
        dryRun: flag({ description: "Don't actually add files" }),
        patch:  flag({ short: "p", description: "Interactively stage hunks" }),
        files:  rest({ description: "Files to add" }),
      },
    }),

    push: sub({
      description: "Update remote refs",
      options: {
        remote:       positional({ description: "Remote name" }),
        branch:       positional({ description: "Branch name" }),
        force:        flag({ short: "f", description: "Force push" }),
        forceWithLease: flag({ description: "Safer force push" }),
        tags:         flag({ description: "Push all tags" }),
        setUpstream:  flag({ short: "u", description: "Set upstream" }),
        delete:       flag({ short: "d", description: "Delete remote branch" }),
      },
      exclusive: [["force", "forceWithLease"]],
    }),

    pull: sub({
      description: "Fetch and merge",
      options: {
        remote: positional({ description: "Remote name" }),
        branch: positional({ description: "Branch name" }),
        rebase: flag({ short: "r", description: "Rebase instead of merge" }),
        ffOnly: flag({ description: "Only fast-forward merges" }),
      },
      exclusive: [["rebase", "ffOnly"]],
    }),

    branch: sub({
      description: "List, create, or delete branches",
      options: {
        name:        positional({ description: "Branch name" }),
        delete:      flag({ short: "d", description: "Delete a branch" }),
        forceDelete: flag({ description: "Force delete a branch" }),
        list:        flag({ short: "l", description: "List branches" }),
        all:         flag({ short: "a", description: "Show all branches" }),
        move:        flag({ short: "m", description: "Move/rename a branch" }),
      },
      exclusive: [["delete", "forceDelete"]],
    }),

    checkout: sub({
      description: "Switch branches or restore files",
      options: {
        target: positional({ description: "Branch or commit to checkout" }),
        create: stringOpt({ default: "", short: "b", description: "Create new branch", valueName: "BRANCH" }),
        force:  flag({ short: "f", description: "Force checkout" }),
        files:  dashdash(),
      },
    }),

    diff: sub({
      description: "Show changes between commits",
      options: {
        staged:   flag({ description: "Show staged changes" }),
        stat:     flag({ description: "Show diffstat only" }),
        unified:  intOpt({ default: 3, short: "U", description: "Lines of context", valueName: "N", implicitValue: 3 }),
        nameOnly: flag({ description: "Show only names of changed files" }),
        paths:    rest({ description: "Limit to paths" }),
      },
    }),

    status: sub({
      description: "Show working tree status",
      options: {
        short:     flag({ short: "s", description: "Short format" }),
        branch:    flag({ short: "b", description: "Show branch info" }),
        porcelain: flag({ description: "Machine-readable output" }),
      },
    }),

    tag: sub({
      description: "Create, list, delete or verify tags",
      options: {
        list:     flag({ short: "l", description: "List tags" }),
        delete:   flag({ short: "d", description: "Delete a tag" }),
        annotate: flag({ short: "a", description: "Annotated tag" }),
        message:  stringOpt({ default: "", short: "m", description: "Tag message", valueName: "MSG" }),
        tagname:  positional({ description: "Tag name" }),
      },
      exclusive: [["list", "delete", "annotate"]],
    }),

    remote: sub({
      description: "Manage tracked repositories",
      requireCmd: true,
      commands: {
        add: sub({
          description: "Add a remote",
          options: {
            fetch: flag({ short: "f", description: "Fetch after adding" }),
            name:  positional({ description: "Remote name" }),
            url:   positional({ description: "Remote URL" }),
          },
        }),
        remove: sub({
          description: "Remove a remote",
          options: {
            name: positional({ description: "Remote name", required: true as const }),
          },
        }),
        rename: sub({
          description: "Rename a remote",
          options: {
            old: positional({ description: "Old remote name" }),
            new: positional({ description: "New remote name" }),
          },
        }),
      },
    }),

    stash: sub({
      description: "Stash changes",
      requireCmd: true,
      commands: {
        push: sub({
          description: "Save local modifications",
          options: {
            message: stringOpt({ default: "", short: "m", description: "Stash message", valueName: "MSG" }),
            files:   dashdash(),
          },
        }),
        pop: sub({
          description: "Apply and remove stash",
          options: {
            index: intOpt({ default: 0, description: "Stash index", valueName: "N", implicitValue: 0 }),
          },
        }),
        list: sub({
          description: "List stash entries",
        }),
        drop: sub({
          description: "Drop a stash entry",
          options: {
            index: intOpt({ default: 0, description: "Stash index to drop", valueName: "N", implicitValue: 0 }),
          },
        }),
      },
    }),

    config: sub({
      description: "Get and set options",
      options: {
        global: flag({ description: "Use global config" }),
        local:  flag({ description: "Use repository config" }),
        system: flag({ description: "Use system config" }),
        key:    positional({ description: "Config key" }),
        value:  positional({ description: "Config value" }),
      },
      exclusive: [["global", "local", "system"]],
    }),
  },
});

// ============================================================
// 3. パース結果の型を確認（型チェックのみ、実行不要）
// ============================================================

type MyGitResult = Infer<typeof schema>;

// ============================================================
// 4. ディスパッチコード — ユーザーが書くコード
// ============================================================

async function main() {
  try {
    const result: MyGitResult = await schema.parse(process.argv.slice(2));

    // globals は常にアクセス可能（全て non-optional）
    const { verbose, quiet, color } = result.globals;
    //       ^number  ^boolean ^"always"|"never"|"auto"

    console.log(`verbose=${verbose}, quiet=${quiet}, color=${color}`);

    // command は discriminated union
    switch (result.command.name) {

      case "clone": {
        const { url, directory, depth, branch, bare } = result.command.options;
        //       ^string (required)
        //            ^string|undefined (optional positional)
        //                       ^number (has default)
        //                               ^string (has default)
        //                                        ^boolean (flag)
        console.log(`Cloning ${url} into ${directory ?? "."}`);
        console.log(`  depth=${depth}, branch=${branch}, bare=${bare}`);
        break;
      }

      case "commit": {
        const { message, all, amend, verify } = result.command.options;
        //       ^string (required + nonEmpty)
        //                ^boolean  ^boolean  ^boolean
        console.log(`Committing: ${message}`);
        console.log(`  all=${all}, amend=${amend}, verify=${verify}`);
        break;
      }

      case "log": {
        const { oneline, maxCount, author, format, graph, paths } = result.command.options;
        //       ^boolean ^number   ^string[] ^literal-union ^boolean ^string[]
        console.log(`Log: oneline=${oneline}, maxCount=${maxCount}`);
        console.log(`  authors=${author.join(",")}, format=${format}`);
        console.log(`  graph=${graph}, paths=${paths.join(",")}`);
        break;
      }

      case "add": {
        const { force, dryRun, patch, files } = result.command.options;
        console.log(`Add: force=${force}, dryRun=${dryRun}, patch=${patch}`);
        console.log(`  files=${files.join(" ")}`);
        break;
      }

      case "push": {
        const { remote, branch, force, forceWithLease, tags, setUpstream } = result.command.options;
        //       ^string|undefined (optional positional)
        console.log(`Push: remote=${remote}, branch=${branch}`);
        console.log(`  force=${force}, lease=${forceWithLease}, tags=${tags}, upstream=${setUpstream}`);
        break;
      }

      case "pull": {
        const { remote, branch, rebase, ffOnly } = result.command.options;
        console.log(`Pull: remote=${remote}, branch=${branch}`);
        console.log(`  rebase=${rebase}, ffOnly=${ffOnly}`);
        break;
      }

      case "branch": {
        const { name, delete: del, forceDelete, list, all, move } = result.command.options;
        console.log(`Branch: name=${name}, delete=${del}, forceDelete=${forceDelete}`);
        console.log(`  list=${list}, all=${all}, move=${move}`);
        break;
      }

      case "checkout": {
        const { target, create, force, files } = result.command.options;
        console.log(`Checkout: target=${target}, create=${create}`);
        console.log(`  force=${force}, dashdash files=${files.join(" ")}`);
        break;
      }

      case "diff": {
        const { staged, stat, unified, nameOnly, paths } = result.command.options;
        console.log(`Diff: staged=${staged}, stat=${stat}, unified=${unified}`);
        console.log(`  nameOnly=${nameOnly}, paths=${paths.join(",")}`);
        break;
      }

      case "status": {
        const { short: isShort, branch: showBranch, porcelain } = result.command.options;
        console.log(`Status: short=${isShort}, branch=${showBranch}, porcelain=${porcelain}`);
        break;
      }

      case "tag": {
        const { list, delete: del, annotate, message, tagname } = result.command.options;
        console.log(`Tag: list=${list}, delete=${del}, annotate=${annotate}`);
        console.log(`  message=${message}, tagname=${tagname}`);
        break;
      }

      case "remote": {
        // ネストした discriminated union
        switch (result.command.command.name) {
          case "add": {
            const { fetch, name, url } = result.command.command.options;
            //       ^boolean ^string|undefined ^string|undefined
            console.log(`Remote add: name=${name}, url=${url}, fetch=${fetch}`);
            break;
          }
          case "remove": {
            const { name } = result.command.command.options;
            //       ^string (required)
            console.log(`Remote remove: ${name}`);
            break;
          }
          case "rename": {
            // old, new は optional positional
            const opts = result.command.command.options;
            console.log(`Remote rename: ${opts.old} -> ${opts.new}`);
            break;
          }
          default: exhaustive(result.command.command);
        }
        break;
      }

      case "stash": {
        switch (result.command.command.name) {
          case "push": {
            const { message, files } = result.command.command.options;
            console.log(`Stash push: message=${message}, files=${files.join(" ")}`);
            break;
          }
          case "pop": {
            const { index } = result.command.command.options;
            console.log(`Stash pop: index=${index}`);
            break;
          }
          case "list": {
            console.log("Stash list");
            break;
          }
          case "drop": {
            const { index } = result.command.command.options;
            console.log(`Stash drop: index=${index}`);
            break;
          }
          default: exhaustive(result.command.command);
        }
        break;
      }

      case "config": {
        const { global: isGlobal, local: isLocal, system: isSystem, key, value } = result.command.options;
        console.log(`Config: global=${isGlobal}, local=${isLocal}, system=${isSystem}`);
        console.log(`  key=${key}, value=${value}`);
        break;
      }

      default:
        exhaustive(result.command);
    }
  } catch (e) {
    if (e instanceof KuuHelpRequested) {
      console.log(e.helpText);
      process.exit(0);
    }
    if (e instanceof KuuParseError) {
      console.error(e.message);
      console.error(e.helpText);
      process.exit(1);
    }
    throw e;
  }
}

main();
