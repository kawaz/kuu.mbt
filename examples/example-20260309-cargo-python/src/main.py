"""mycargo — kuu WASM bridge を使った cargo CLI 引数パーサのデモ

実際の cargo 操作は行わず、パース結果を整形表示する。
"""

import sys
from kuu import kuu_parse, ParseSuccess, CommandResult
from cargo_schema import OPTS, DESCRIPTION

# グローバルオプションのデフォルト値を構築
GLOBAL_DEFAULTS: dict[str, object] = {}
KIND_DEFAULTS: dict[str, object] = {
    "flag": False,
    "count": 0,
    "string": "",
    "int": 0,
    "append_string": [],
    "append_int": [],
}
for opt in OPTS:
    if opt["kind"] != "command":
        GLOBAL_DEFAULTS[opt["name"]] = opt.get("default", KIND_DEFAULTS.get(opt["kind"]))


def format_value(value: object) -> str:
    """値を表示用にフォーマット"""
    if isinstance(value, list):
        return ", ".join(str(v) for v in value)
    return str(value)


def format_command(cmd: CommandResult, indent: str = "") -> str:
    """コマンド結果を再帰的に整形表示"""
    lines = [f"{indent}command: {cmd.name}"]

    for key, value in cmd.values.items():
        # デフォルト値は表示しない
        if value is False or value == 0 or value == "" or value is None:
            continue
        if isinstance(value, list) and len(value) == 0:
            continue
        lines.append(f"{indent}  {key}: {format_value(value)}")

    if cmd.command:
        lines.append(format_command(cmd.command, indent + "  "))

    return "\n".join(lines)


def main() -> None:
    args = sys.argv[1:]

    result = kuu_parse(OPTS, args, description=DESCRIPTION)

    if isinstance(result, ParseSuccess):
        lines: list[str] = []

        # デフォルト値でないグローバルオプションのみ表示
        non_default_globals = [
            (key, value)
            for key, value in result.values.items()
            if _is_non_default(key, value)
        ]

        if non_default_globals:
            lines.append("Global options:")
            for key, value in non_default_globals:
                lines.append(f"  {key}: {format_value(value)}")
            lines.append("")

        if result.command:
            lines.append(format_command(result.command))
        else:
            lines.append("(no subcommand specified)")
            lines.append("Run with --help for usage information.")

        print("\n".join(lines))
    elif result.help_requested:
        print(result.help)
    else:
        print(f"error: {result.error or 'unknown error'}", file=sys.stderr)
        print("", file=sys.stderr)
        print("Run with --help for more information.", file=sys.stderr)
        sys.exit(1)


def _is_non_default(key: str, value: object) -> bool:
    """値がデフォルトでないか判定"""
    default = GLOBAL_DEFAULTS.get(key)
    if isinstance(default, list) and isinstance(value, list):
        return len(value) > 0
    return value != default and value is not None


if __name__ == "__main__":
    main()
