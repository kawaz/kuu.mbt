"""kuu WASM bridge の Python ラッパー

Node.js サブプロセスを経由して kuu_parse を呼び出す。
wasm-gc + js-string builtins は V8 依存のため、直接 wasmtime 等では実行不可。
"""

import json
import subprocess
import sys
from pathlib import Path
from dataclasses import dataclass
from typing import Optional, Union

BRIDGE_PATH = Path(__file__).parent / "kuu_bridge.mjs"


@dataclass
class CommandResult:
    """サブコマンドのパース結果"""
    name: str
    values: dict
    command: Optional["CommandResult"] = None

    @staticmethod
    def from_dict(d: dict) -> "CommandResult":
        cmd = None
        if d.get("command"):
            cmd = CommandResult.from_dict(d["command"])
        return CommandResult(name=d["name"], values=d["values"], command=cmd)


@dataclass
class ParseSuccess:
    """パース成功結果"""
    ok: bool
    values: dict
    command: Optional[CommandResult] = None


@dataclass
class ParseError:
    """パースエラー結果"""
    ok: bool
    error: Optional[str] = None
    help_requested: bool = False
    help: Optional[str] = None


ParseResult = Union[ParseSuccess, ParseError]


def kuu_parse(
    opts: list[dict],
    args: list[str],
    *,
    description: str = "",
    version: int = 1,
) -> ParseResult:
    """kuu WASM bridge を呼び出してパースを実行する"""
    input_data = {
        "version": version,
        "description": description,
        "opts": opts,
        "args": args,
    }
    input_json = json.dumps(input_data)

    try:
        proc = subprocess.run(
            ["node", str(BRIDGE_PATH)],
            input=input_json,
            capture_output=True,
            text=True,
            timeout=10,
        )
    except FileNotFoundError:
        return ParseError(
            ok=False,
            error="Node.js が見つかりません。kuu WASM bridge には Node.js v25+ が必要です。",
        )
    except subprocess.TimeoutExpired:
        return ParseError(ok=False, error="kuu_parse がタイムアウトしました")

    if proc.returncode != 0 and not proc.stdout:
        return ParseError(ok=False, error=proc.stderr or "unknown error")

    try:
        result = json.loads(proc.stdout)
    except json.JSONDecodeError as e:
        return ParseError(ok=False, error=f"kuu_parse の出力が不正な JSON です: {e}")

    if result.get("ok"):
        cmd = None
        if result.get("command"):
            cmd = CommandResult.from_dict(result["command"])
        return ParseSuccess(ok=True, values=result["values"], command=cmd)
    else:
        return ParseError(
            ok=False,
            error=result.get("error"),
            help_requested=result.get("help_requested", False),
            help=result.get("help"),
        )
