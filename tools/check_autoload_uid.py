#!/usr/bin/env python3
"""
autoload UID 引用守卫脚本

背景：Godot 编辑器会话（桌面 GUI）+ imgui-godot 插件 `_enter_tree` 调
     `add_autoload_singleton(name, path)`，引擎会把 project.godot 的 autoload
     条目写成 UID 形式（如 `ImGuiRoot="*uid://dugmpnsxaagba"`）。
     UID → 文件路径的映射只存在 `.godot/uid_cache.bin`（被 .gitignore，不入 git）；
     当 uid_cache 失效（新 clone / 删 .godot / 切分支 / headless 与编辑器状态错位）时，
     autoload 解析 UID 失败 → "Unrecognized UID" / "node count is 0" /
     "Failed to instantiate an autoload" 反复报错。

     路径引用（`res://...`）直接定位文件、不经 UID 解析，免疫 uid_cache 失效。

功能：提交时若 staged 的 project.godot 在 [autoload] 段用了 UID 引用，
     自动扫描项目资源文件头解析出对应 res:// 路径，还原为路径引用并 re-stage，
     保证仓库内 autoload 永远是稳定的路径引用形式。

用法：
  python tools/check_autoload_uid.py     # pre-commit 使用

退出码：
  0 — project.godot 未在本次提交中 / autoload 已是路径引用 / 已自动还原成功
  1 — autoload 用 UID 但找不到对应资源文件，无法自动还原（需人工处理）
"""

import os
import re
import subprocess
import sys
from pathlib import Path

PROJECT_GODOT = "project.godot"

# 匹配 autoload 行：Name="*uid://xxxx" 或 Name="uid://xxxx"
# 捕获组：1=autoload 名 / 2=可选的 "*" 前缀 / 3=完整 uid://xxx
_AUTOLOAD_UID_RE = re.compile(r'^(\w+)="(\*?)(uid://[0-9a-z]+)"\s*$')


def is_project_godot_staged() -> bool:
    """project.godot 是否在本次提交的 staged 变更中。"""
    result = subprocess.run(
        ["git", "diff", "--cached", "--name-only"],
        capture_output=True,
        text=True,
        check=False,
    )
    return PROJECT_GODOT in result.stdout.split()


def find_res_path_for_uid(uid: str) -> str | None:
    """扫描项目 .tscn / .tres 资源文件头，找声明了该 uid 的文件，返回 res:// 路径。

    优先用 git grep（已跟踪文件），fallback 到文件系统 grep（覆盖未跟踪的新增资源）。
    """
    # git grep 已跟踪文件
    result = subprocess.run(
        ["git", "grep", "-l", f'uid="{uid}"', "--", "*.tscn", "*.tres"],
        capture_output=True,
        text=True,
        check=False,
    )
    files = [f for f in result.stdout.strip().splitlines() if f]
    if not files:
        # fallback：文件系统全扫（含未跟踪新增）
        result = subprocess.run(
            ["grep", "-rl", f'uid="{uid}"', "--include=*.tscn", "--include=*.tres", "."],
            capture_output=True,
            text=True,
            check=False,
        )
        files = [f.lstrip("./") for f in result.stdout.strip().splitlines() if f]
    if not files:
        return None
    # 取第一个匹配（autoload 目标资源理论上 uid 唯一）
    return "res://" + files[0]


def main() -> int:
    # 仅当 project.godot 在本次提交中才检查（不主动改用户没打算提交的文件）
    if not is_project_godot_staged():
        return 0
    if not os.path.exists(PROJECT_GODOT):
        return 0

    raw: str = Path(PROJECT_GODOT).read_text(encoding="utf-8")
    trailing: str = "\n" if raw.endswith("\n") else ""
    lines: list[str] = raw.splitlines()

    in_autoload: bool = False
    changed: bool = False
    fixed: list[tuple[str, str, str]] = []

    for i, line in enumerate(lines):
        stripped: str = line.strip()
        # 段切换：进入 / 离开 [autoload]
        if stripped == "[autoload]":
            in_autoload = True
            continue
        if stripped.startswith("[") and stripped.endswith("]"):
            in_autoload = False
            continue
        if not in_autoload:
            continue
        match = _AUTOLOAD_UID_RE.match(line)
        if match is None:
            continue
        name: str = match.group(1)
        star: str = match.group(2)
        uid: str = match.group(3)
        res_path: str | None = find_res_path_for_uid(uid)
        if res_path is None:
            print(f"✗ autoload {name} 用 UID 引用 {uid}，但找不到对应资源文件，无法自动还原")
            print("  请手动改为 res:// 路径引用后重新提交")
            return 1
        lines[i] = f'{name}="{star}{res_path}"'
        changed = True
        fixed.append((name, uid, res_path))

    if changed:
        Path(PROJECT_GODOT).write_text("\n".join(lines) + trailing, encoding="utf-8")
        subprocess.run(["git", "add", PROJECT_GODOT], check=False)
        for name, uid, res_path in fixed:
            print(f"  已还原 autoload UID→路径：{name}  {uid} → {res_path}")
        print("✓ project.godot autoload UID 引用已自动还原为路径引用并 re-stage")
        print("  根因：编辑器/插件把 autoload 写成 UID，UID 经 .godot/uid_cache 解析，cache 失效时报错")

    return 0


if __name__ == "__main__":
    sys.exit(main())
