#!/usr/bin/env python3
"""
GDScript 无类型 Variant 推断检测脚本（MVP-ε G2-4）

功能：扫描 scripts/**/*.gd 中 `var x = expr` 形式且 expr 可能返回 Variant
     但未加显式类型注解的行，按 CLAUDE.md「禁止对 Variant 使用 :=」精神
     补强 `var x = expr`（无类型）的同等检测，防止 LSP 推导失效。

设计：
  - 白名单：字面量 / 构造器 / 显式类型转换（as TypeName）通过
  - 阻断：`var x = obj.get(...)` / `var x = expr as Variant` / 其他可能 Variant 的右侧
  - 不强求所有 `var x = func_call()` 都加类型（函数返回值大多有 -> Type 注解）
    仅当右侧表达式形态明确可能产出 Variant 时报告

用法：
  python tools/check_variant_types.py              # 严格模式，发现违规阻断
  python tools/check_variant_types.py --report     # 仅报告不阻断（首次接入用）

退出码：
  0 — 通过
  1 — 存在违规（严格模式）或扫描错误
"""

import argparse
import os
import re
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
SCRIPTS_DIR = PROJECT_ROOT / "scripts"

# 跳过的目录
_SKIP_DIRS = {".godot", ".venv", "__pycache__"}

# 匹配 `var <name> = <expr>` 形式（不含 := 也不含 : Type）
# 关键：name 后允许空白 + `=`，但不能有 `:` 或 `:=`
_VAR_DECL = re.compile(
    r"^(?P<indent>\s*)var\s+(?P<name>[a-z_][a-z_0-9]*)\s*=\s*(?P<rhs>.+?)\s*$"
)

# 显式类型注解模式（已通过）
_TYPED_VAR = re.compile(r"^\s*var\s+[a-z_][a-z_0-9]*\s*:\s*\S")

# RHS 白名单（字面量 / 构造器 / 显式转型，视为已知类型）
_RHS_WHITELIST_PREFIXES = (
    # 数字字面量
    # 字符串字面量（"..." / '...'）
    '"', "'",
    # 构造器（GDScript 内置类型）
    "Vector2(", "Vector2i(", "Vector3(", "Vector3i(", "Vector4(", "Vector4i(",
    "Color(", "Color8(", "Rect2(", "Rect2i(",
    "Transform2D(", "Transform3D(", "Basis(", "Quaternion(", "Plane(",
    "AABB(", "Projection(", "PackedByteArray(", "PackedInt32Array(",
    "PackedInt64Array(", "PackedFloat32Array(", "PackedFloat64Array(",
    "PackedStringArray(", "PackedVector2Array(", "PackedVector3Array(",
    "PackedColorArray(", "StringName(", "NodePath(", "Callable(", "Signal(",
    "RID(",
)


def _is_numeric_literal(rhs: str) -> bool:
    """是否纯数字字面量（含负号）。"""
    return bool(re.match(r"^-?\d", rhs))


def _is_collection_literal(rhs: str) -> bool:
    """是否数组 / 字典字面量。"""
    return rhs.startswith("[") or rhs.startswith("{")


def _is_keyword_literal(rhs: str) -> bool:
    """是否关键字字面量（null / true / false）。"""
    return rhs in ("null", "true", "false")


def _is_explicit_cast(rhs: str) -> bool:
    """RHS 末尾是显式 as TypeName（含 GDScript 内置小写类型 int/float/bool/String 等）。"""
    # 允许 PascalCase 类型 + GDScript 内置小写类型；后者覆盖 `as int / as float / as bool / as String` 等
    return bool(re.search(r"\bas\s+([A-Z][A-Za-z_0-9]*|int|float|bool|String)\s*$", rhs))


def _is_whitelisted(rhs: str) -> bool:
    """RHS 是否落在白名单内（已知类型）。"""
    if _is_numeric_literal(rhs):
        return True
    if _is_collection_literal(rhs):
        return True
    if _is_keyword_literal(rhs):
        return True
    if _is_explicit_cast(rhs):
        return True
    if rhs.startswith(_RHS_WHITELIST_PREFIXES):
        return True
    return False


def _is_suspicious_variant(rhs: str) -> bool:
    """RHS 是否明确可能产出 Variant（保守判定，仅报告高把握的形态）。"""
    # Object.get(...) / Dictionary.get(...) / Array.get(...) 都返回 Variant
    # 形如 xxx.get("key") / xxx.get("key", default) / xxx.get(idx)
    if re.search(r"\.get\s*\(", rhs):
        return True
    # 显式 `as Variant` 也算（虽然没意义）
    if re.search(r"\bas\s+Variant\b", rhs):
        return True
    return False


## 扫描错误计数（与 findings 分开记账；脚本主流程读取此值决定是否 exit 1）
_scan_errors: int = 0


def _scan_file(path: Path) -> list[tuple[int, str, str]]:
    """扫单文件返回违规列表 (行号, name, rhs)。读文件失败时累加 _scan_errors。"""
    global _scan_errors
    findings: list[tuple[int, str, str]] = []
    try:
        with path.open("r", encoding="utf-8") as fh:
            for i, line in enumerate(fh, 1):
                # 跳过已显式类型注解的行
                if _TYPED_VAR.match(line):
                    continue
                m = _VAR_DECL.match(line)
                if not m:
                    continue
                rhs = m.group("rhs").strip()
                # 去掉行末注释（# ...）后再判定
                # 注意字符串内的 # 不能误删；保守处理：仅当 # 在引号外
                rhs_no_comment = _strip_trailing_comment(rhs)
                if _is_whitelisted(rhs_no_comment):
                    continue
                if _is_suspicious_variant(rhs_no_comment):
                    findings.append((i, m.group("name"), rhs_no_comment))
    except (OSError, UnicodeDecodeError) as e:
        print(f"[check_variant_types] 读取 {path} 失败: {e}", file=sys.stderr)
        _scan_errors += 1
    return findings


def _strip_trailing_comment(rhs: str) -> str:
    """去掉 RHS 行末注释（保守：不解析字符串边界，仅做简单分割）。"""
    # 简单实现：如果 # 之前没有未闭合引号，认为是注释起点
    in_single = False
    in_double = False
    for idx, ch in enumerate(rhs):
        if ch == "'" and not in_double:
            in_single = not in_single
        elif ch == '"' and not in_single:
            in_double = not in_double
        elif ch == "#" and not in_single and not in_double:
            return rhs[:idx].strip()
    return rhs


def _walk_scripts() -> list[Path]:
    """遍历 scripts/ 下所有 .gd 文件。"""
    results: list[Path] = []
    if not SCRIPTS_DIR.exists():
        return results
    for dirpath, dirnames, filenames in os.walk(SCRIPTS_DIR):
        dirnames[:] = [d for d in dirnames if d not in _SKIP_DIRS]
        for fname in filenames:
            if fname.endswith(".gd"):
                results.append(Path(dirpath) / fname)
    return results


def main() -> int:
    parser = argparse.ArgumentParser(description="GDScript 无类型 Variant 检测")
    parser.add_argument(
        "--report",
        action="store_true",
        help="仅报告，不阻断（首次接入用）",
    )
    args = parser.parse_args()

    all_findings: list[tuple[Path, int, str, str]] = []
    for path in _walk_scripts():
        for ln, name, rhs in _scan_file(path):
            all_findings.append((path, ln, name, rhs))

    # 扫描错误（读文件失败）无论是否有 findings 都阻断 —— 与脚本头 docstring "扫描错误返回 1" 一致
    if _scan_errors > 0:
        print(f"[check_variant_types] 扫描错误 {_scan_errors} 处（见 stderr），阻断", file=sys.stderr)
        return 1

    if not all_findings:
        return 0

    print(f"[check_variant_types] 发现 {len(all_findings)} 处无类型 Variant 推断:")
    for path, ln, name, rhs in all_findings:
        rel = path.relative_to(PROJECT_ROOT)
        print(f"  {rel}:{ln}: var {name} = {rhs[:80]}")
        print(f"      建议改为 `var {name}: <类型> = ...` 或 `... as <类型>` 显式转型")

    if args.report:
        print("[check_variant_types] --report 模式，不阻断")
        return 0

    print("[check_variant_types] 阻断 commit。如需放行使用 --report；或为上述行加显式类型注解。")
    return 1


if __name__ == "__main__":
    sys.exit(main())
