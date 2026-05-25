#!/usr/bin/env python3
"""校验调参面板 registry 条目有效性（MVP-D D.4）。

检查 assets/config/param_panel/_panel_registry.tres 的每条 ParamPanelRegistryEntry：
  1. tres_path 指向的 .tres 文件实际存在
  2. group（面板分类 category）非空
  3. realtime = true 的条目，其使用方应改为 var preload（否则 const cache bug 让实时调参不生效）

失败仅打印 warning，**不阻断**（exit 0）。未挂 pre-commit，按需手动跑：
    python3 tools/check_param_panel_coverage.py
"""

import re
import sys
import pathlib
import subprocess

ROOT = pathlib.Path(__file__).resolve().parent.parent
REGISTRY = ROOT / "assets/config/param_panel/_panel_registry.tres"


def main() -> int:
    if not REGISTRY.exists():
        print(f"[check_param_panel] registry 不存在，跳过: {REGISTRY}")
        return 0

    text = REGISTRY.read_text(encoding="utf-8")
    # 按 [sub_resource ...] 块拆分（每个 entry 一块）
    blocks = re.split(r"\[sub_resource ", text)
    warnings: list[str] = []
    count = 0

    for blk in blocks[1:]:
        m_path = re.search(r'tres_path\s*=\s*"([^"]*)"', blk)
        if not m_path:
            continue
        count += 1
        tres_path = m_path.group(1)
        m_group = re.search(r'group\s*=\s*&?"([^"]*)"', blk)
        group = m_group.group(1) if m_group else ""
        m_rt = re.search(r"realtime\s*=\s*(true|false)", blk)
        realtime = (m_rt.group(1) == "true") if m_rt else False

        # 1. tres_path 文件存在
        rel = tres_path.replace("res://", "")
        if not (ROOT / rel).exists():
            warnings.append(f"tres_path 不存在: {tres_path}")

        # 2. group 非空
        if not group:
            warnings.append(f"group 为空: {tres_path}")

        # 3. realtime=true → 使用方应 var preload（非 const，否则值类型字段直读 inline 拿旧值）
        if realtime:
            out = subprocess.run(
                ["grep", "-rn", f'preload("{tres_path}")', str(ROOT / "scripts")],
                capture_output=True, text=True,
            ).stdout
            for line in out.splitlines():
                if re.search(r"\bconst\b", line):
                    warnings.append(
                        f"realtime=true 但使用方为 const preload（应改 var）: {line.strip()}"
                    )

    print(f"[check_param_panel] 扫描 {count} 个 registry 条目")
    if warnings:
        print(f"[check_param_panel] ⚠ {len(warnings)} 项警告（不阻断）：")
        for w in warnings:
            print(f"  - {w}")
    else:
        print("[check_param_panel] ✓ 全部条目有效")
    return 0  # warning 不阻断


if __name__ == "__main__":
    sys.exit(main())
