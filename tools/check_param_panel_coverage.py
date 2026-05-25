#!/usr/bin/env python3
"""校验调参面板覆盖（MVP-D D.4）。

正向：registry 条目有效性
  - 每条 tres_path 指向的 .tres 实际存在
  - group（面板分类 category）非空
  - realtime = true 的条目，其使用方应改为 var preload（否则 const cache bug 让实时调参不生效）

反向（防遗忘，基于 @tunable 埋点标记，非全量扫描）：
  - 所有带 `## @tunable` 标记的调参 Resource，其同名 .tres 应已纳入面板
    （Push = ParamPanelScene 引用，或 Pull = registry 注册）
  - 标了 @tunable 却两边都没纳入 → 报告"待整理"

失败仅打印 warning，**不阻断**（exit 0）。未挂 pre-commit，按需手动跑：
    python3 tools/check_param_panel_coverage.py
"""

import re
import sys
import pathlib
import subprocess

ROOT = pathlib.Path(__file__).resolve().parent.parent
REGISTRY = ROOT / "assets/config/param_panel/_panel_registry.tres"
PANEL_DIR = ROOT / "assets/config/param_panel"
CONFIG_DIR = ROOT / "scripts/config"


def parse_registry_entries(text: str) -> list[dict]:
    entries: list[dict] = []
    for blk in re.split(r"\[sub_resource ", text)[1:]:
        m_path = re.search(r'tres_path\s*=\s*"([^"]*)"', blk)
        if not m_path:
            continue
        m_group = re.search(r'group\s*=\s*&?"([^"]*)"', blk)
        m_rt = re.search(r"realtime\s*=\s*(true|false)", blk)
        entries.append({
            "path": m_path.group(1),
            "group": m_group.group(1) if m_group else "",
            "realtime": (m_rt.group(1) == "true") if m_rt else False,
        })
    return entries


def main() -> int:
    warnings: list[str] = []

    # ---- 正向：registry 条目有效性 + 收集 Pull 路径 ----
    pull_paths: set[str] = set()
    reg_count = 0
    if REGISTRY.exists():
        entries = parse_registry_entries(REGISTRY.read_text(encoding="utf-8"))
        reg_count = len(entries)
        for e in entries:
            pull_paths.add(e["path"])
            rel = e["path"].replace("res://", "")
            if not (ROOT / rel).exists():
                warnings.append(f"[正向] registry tres_path 不存在: {e['path']}")
            if not e["group"]:
                warnings.append(f"[正向] registry group 为空: {e['path']}")
            if e["realtime"]:
                out = subprocess.run(
                    ["grep", "-rn", f'preload("{e["path"]}")', str(ROOT / "scripts")],
                    capture_output=True, text=True,
                ).stdout
                for line in out.splitlines():
                    if re.search(r"\bconst\b", line):
                        warnings.append(
                            f"[正向] realtime=true 但使用方 const preload（应改 var）: {line.strip()}"
                        )

    # ---- 收集 Push 路径（ParamPanelScene 引用的 Resource）----
    push_paths: set[str] = set()
    for tres in PANEL_DIR.glob("*.tres"):
        if tres.name == "_panel_registry.tres":
            continue
        for m in re.finditer(r'target_resource_path\s*=\s*"([^"]*)"', tres.read_text(encoding="utf-8")):
            push_paths.add(m.group(1))

    covered = push_paths | pull_paths

    # ---- 反向：@tunable 埋点标记 vs 面板覆盖 ----
    tunable_count = 0
    for gd in sorted(CONFIG_DIR.glob("*.gd")):
        text = gd.read_text(encoding="utf-8")
        if "@tunable" not in text:
            continue
        tunable_count += 1
        tres_rel = f"assets/config/{gd.stem}.tres"
        tres_path = f"res://{tres_rel}"
        if not (ROOT / tres_rel).exists():
            warnings.append(f"[反向] {gd.name} 标 @tunable 但缺同名 .tres: {tres_path}")
            continue
        if tres_path not in covered:
            warnings.append(
                f"[反向] {gd.name} 标 @tunable 但未纳入面板（Push/Pull 都没有），待整理: {tres_path}"
            )

    print(f"[check_param_panel] registry {reg_count} 条目 / Push {len(push_paths)} Resource / @tunable {tunable_count} 标记")
    if warnings:
        print(f"[check_param_panel] ⚠ {len(warnings)} 项警告（不阻断）：")
        for w in warnings:
            print(f"  - {w}")
    else:
        print("[check_param_panel] ✓ registry 条目全有效 + 所有 @tunable 标记的 Resource 均已纳入面板")
    return 0  # warning 不阻断


if __name__ == "__main__":
    sys.exit(main())
