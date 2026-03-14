// git CLI スキーマ定義
// WASM bridge の JSON schema として git CLI のオプション構造を定義する

import type { KuuOpt } from "./kuu-wasm.ts";

// アプリケーションの説明
export const description = "mygit - A sample git-like CLI built with kuu";

// git CLI のオプションスキーマ
export const opts: KuuOpt[] = [
  // --- グローバルオプション ---
  {
    kind: "count",
    name: "verbose",
    shorts: "v",
    global: true,
    description: "冗長出力を増やす (-v, -vv, -vvv)",
  },
  {
    kind: "string",
    name: "color",
    global: true,
    description: "カラー出力の制御",
    choices: ["always", "never", "auto"],
    default: "auto",
  },

  // --- サブコマンド: clone ---
  {
    kind: "command",
    name: "clone",
    description: "リポジトリをクローンする",
    opts: [
      { kind: "positional", name: "url", description: "リポジトリURL" },
      {
        kind: "string",
        name: "branch",
        shorts: "b",
        description: "チェックアウトするブランチ",
        default: "",
      },
      {
        kind: "int",
        name: "depth",
        description: "浅いクローンのコミット数",
        default: 0,
      },
      {
        kind: "flag",
        name: "bare",
        description: "ベアリポジトリとして作成",
      },
    ],
  },

  // --- サブコマンド: commit ---
  {
    kind: "command",
    name: "commit",
    description: "変更を記録する",
    opts: [
      {
        kind: "string",
        name: "message",
        shorts: "m",
        description: "コミットメッセージ",
        default: "",
      },
      {
        kind: "flag",
        name: "all",
        shorts: "a",
        description: "変更されたファイルを全てステージ",
      },
      {
        kind: "flag",
        name: "amend",
        description: "直前のコミットを修正",
      },
    ],
  },

  // --- サブコマンド: log ---
  {
    kind: "command",
    name: "log",
    description: "コミットログを表示する",
    opts: [
      {
        kind: "flag",
        name: "oneline",
        description: "1行表示",
      },
      {
        kind: "int",
        name: "max-count",
        shorts: "n",
        description: "表示するコミット数の上限",
        default: 0,
      },
      {
        kind: "append_string",
        name: "author",
        description: "著者でフィルタ（繰り返し可）",
      },
      {
        kind: "string",
        name: "format",
        description: "出力フォーマット",
        choices: [
          "oneline",
          "short",
          "medium",
          "full",
          "fuller",
          "reference",
          "raw",
        ],
        default: "medium",
      },
      {
        kind: "flag",
        name: "graph",
        description: "コミット履歴のグラフを描画",
      },
      {
        kind: "rest",
        name: "paths",
        description: "パスでフィルタ",
      },
    ],
  },

  // --- サブコマンド: add ---
  {
    kind: "command",
    name: "add",
    description: "ファイルをインデックスに追加する",
    opts: [
      {
        kind: "flag",
        name: "force",
        shorts: "f",
        description: "無視されたファイルも追加",
      },
      {
        kind: "flag",
        name: "dry-run",
        description: "実際には追加しない",
      },
      {
        kind: "flag",
        name: "patch",
        shorts: "p",
        description: "対話的にハンクをステージ",
      },
      {
        kind: "rest",
        name: "files",
        description: "追加するファイル",
      },
    ],
  },

  // --- サブコマンド: push ---
  {
    kind: "command",
    name: "push",
    description: "リモート参照を更新する",
    opts: [
      {
        kind: "positional",
        name: "remote",
        description: "リモート名",
      },
      {
        kind: "rest",
        name: "refspecs",
        description: "リファレンス指定",
      },
      {
        kind: "flag",
        name: "force",
        shorts: "f",
        description: "強制プッシュ",
      },
      {
        kind: "flag",
        name: "tags",
        description: "全タグをプッシュ",
      },
      {
        kind: "flag",
        name: "set-upstream",
        shorts: "u",
        description: "ブランチの上流を設定",
      },
      {
        kind: "flag",
        name: "delete",
        shorts: "d",
        description: "リモートブランチを削除",
      },
    ],
  },

  // --- サブコマンド: pull ---
  {
    kind: "command",
    name: "pull",
    description: "フェッチしてマージする",
    opts: [
      {
        kind: "positional",
        name: "remote",
        description: "リモート名",
      },
      {
        kind: "rest",
        name: "refspecs",
        description: "リファレンス指定",
      },
      {
        kind: "flag",
        name: "rebase",
        shorts: "r",
        description: "マージの代わりにリベース",
      },
      {
        kind: "flag",
        name: "ff-only",
        description: "ファストフォワードのみ",
      },
    ],
  },

  // --- サブコマンド: branch ---
  {
    kind: "command",
    name: "branch",
    description: "ブランチの一覧・作成・削除",
    opts: [
      {
        kind: "positional",
        name: "name",
        description: "ブランチ名",
      },
      {
        kind: "flag",
        name: "delete",
        shorts: "d",
        description: "ブランチを削除",
      },
      {
        kind: "flag",
        name: "list",
        shorts: "l",
        description: "ブランチを一覧表示",
      },
      {
        kind: "flag",
        name: "all",
        shorts: "a",
        description: "ローカルとリモートのブランチを表示",
      },
      {
        kind: "flag",
        name: "move",
        shorts: "m",
        description: "ブランチを移動/リネーム",
      },
    ],
  },

  // --- サブコマンド: checkout ---
  {
    kind: "command",
    name: "checkout",
    description: "ブランチを切り替える",
    opts: [
      {
        kind: "positional",
        name: "branch",
        description: "切り替え先のブランチ",
      },
      {
        kind: "string",
        name: "create",
        shorts: "b",
        description: "新しいブランチを作成して切り替え",
        default: "",
      },
      {
        kind: "flag",
        name: "force",
        shorts: "f",
        description: "強制チェックアウト",
      },
    ],
  },

  // --- サブコマンド: diff ---
  {
    kind: "command",
    name: "diff",
    description: "差分を表示する",
    opts: [
      {
        kind: "flag",
        name: "staged",
        aliases: ["cached"],
        description: "ステージされた変更を表示",
      },
      {
        kind: "flag",
        name: "stat",
        description: "差分統計のみ表示",
      },
      {
        kind: "int",
        name: "unified",
        shorts: "U",
        description: "コンテキスト行数",
        default: 3,
      },
      {
        kind: "flag",
        name: "name-only",
        description: "変更されたファイル名のみ表示",
      },
      {
        kind: "rest",
        name: "paths",
        description: "パスでフィルタ",
      },
    ],
  },

  // --- サブコマンド: status ---
  {
    kind: "command",
    name: "status",
    description: "作業ツリーの状態を表示する",
    opts: [
      {
        kind: "flag",
        name: "short",
        shorts: "s",
        description: "短縮形式で表示",
      },
      {
        kind: "flag",
        name: "branch",
        shorts: "b",
        description: "ブランチ情報を表示",
      },
      {
        kind: "flag",
        name: "porcelain",
        description: "機械可読形式で出力",
      },
    ],
  },

  // --- サブコマンド: tag ---
  {
    kind: "command",
    name: "tag",
    description: "タグの作成・一覧・削除",
    opts: [
      {
        kind: "flag",
        name: "list",
        shorts: "l",
        description: "タグを一覧表示",
      },
      {
        kind: "flag",
        name: "delete",
        shorts: "d",
        description: "タグを削除",
      },
      {
        kind: "flag",
        name: "annotate",
        shorts: "a",
        description: "注釈付きタグを作成",
      },
      {
        kind: "string",
        name: "message",
        shorts: "m",
        description: "タグメッセージ",
        default: "",
      },
      {
        kind: "positional",
        name: "tagname",
        description: "タグ名",
      },
    ],
  },

  // --- サブコマンド: remote (ネスト) ---
  {
    kind: "command",
    name: "remote",
    description: "リモートリポジトリを管理する",
    opts: [
      // remote add
      {
        kind: "command",
        name: "add",
        description: "リモートを追加",
        opts: [
          {
            kind: "positional",
            name: "name",
            description: "リモート名",
          },
          {
            kind: "rest",
            name: "urls",
            description: "リモートURL",
          },
          {
            kind: "flag",
            name: "fetch",
            shorts: "f",
            description: "追加後にフェッチ",
          },
        ],
      },
      // remote remove
      {
        kind: "command",
        name: "remove",
        description: "リモートを削除",
        opts: [
          {
            kind: "positional",
            name: "name",
            description: "リモート名",
          },
        ],
      },
      // remote rename
      {
        kind: "command",
        name: "rename",
        description: "リモートをリネーム",
        opts: [
          {
            kind: "positional",
            name: "old",
            description: "旧リモート名",
          },
          {
            kind: "rest",
            name: "remaining",
            description: "残りの引数",
          },
        ],
      },
    ],
  },

  // --- サブコマンド: stash (ネスト) ---
  {
    kind: "command",
    name: "stash",
    description: "変更を一時退避する",
    opts: [
      // stash push
      {
        kind: "command",
        name: "push",
        description: "変更を退避",
        opts: [
          {
            kind: "string",
            name: "message",
            shorts: "m",
            description: "退避メッセージ",
            default: "",
          },
          {
            kind: "rest",
            name: "files",
            description: "退避するファイル",
          },
        ],
      },
      // stash pop
      {
        kind: "command",
        name: "pop",
        description: "退避を適用して削除",
        opts: [
          {
            kind: "int",
            name: "index",
            description: "退避インデックス",
            default: 0,
          },
        ],
      },
      // stash list
      {
        kind: "command",
        name: "list",
        description: "退避一覧を表示",
        opts: [],
      },
      // stash drop
      {
        kind: "command",
        name: "drop",
        description: "退避を削除",
        opts: [
          {
            kind: "int",
            name: "index",
            description: "削除する退避インデックス",
            default: 0,
          },
        ],
      },
    ],
  },

  // --- サブコマンド: config ---
  {
    kind: "command",
    name: "config",
    description: "設定を管理する",
    opts: [
      {
        kind: "positional",
        name: "key",
        description: "設定キー",
      },
      {
        kind: "rest",
        name: "remaining",
        description: "残りの引数",
      },
    ],
  },
];
