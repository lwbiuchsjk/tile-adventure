class_name ResourceRenderConfig
extends Resource
## 一次性资源点视觉调参（MVP-B.2 阶段 3）
##
## 设计原文：
##   tile-advanture-design/参数Resource化/MVP-B.2_剩余地图const扩批.md §阶段 3 字段构成
##
## 用法：使用方 `const CFG: ResourceRenderConfig = preload("res://assets/config/resource_render_config.tres")`，
## 运行时 `CFG.field_name` 访问。编辑器内双击 .tres 在 inspector 调字段，存盘后下次启动生效。
##
## 字段从 WorldMap.gd 顶部活跃 3 个 BLIND_BOX_* const 迁出。
## **scope 调整（2026-05-17 实装盘点）**：原设计 7 字段（4 资源类型色 + 3 盲盒），实装盘点发现
## `RESOURCE_SUPPLY/HP/EXP/STONE_COLOR` 4 个无任何使用方（M6 视觉统一为盲盒态后死代码遗留），
## 一并清理而非迁入备用。当前 Resource 仅装 3 个活跃 BLIND_BOX_* 字段。
## 命名约定：去 RESOURCE_ 前缀（同 Resource 名已隐含），blind_box_ 前缀保留以备未来扩展资源类型色时区分。


# ─────────────────────────────────────────
# 盲盒（M6 视觉统一：采集前不显示具体类型，避免与"等权采集"规则冲突）
# UI 重构步骤 5：从冷灰 #8C8C99 改为暖浅灰 #B8B8B0（接近木箱感）+ 白描边
# ─────────────────────────────────────────

@export_group("盲盒")

## 盲盒底色（暖浅灰 #B8B8B0，更像"可拾取对象"而非占位符）
@export var blind_box_color: Color = Color(0.72, 0.72, 0.69)

## 盲盒白描边色 alpha 0.85
@export var blind_box_outline: Color = Color(1.0, 1.0, 1.0, 0.85)

## 盲盒描边宽度（像素）
@export_range(0.5, 10.0, 0.1) var blind_box_outline_width: float = 2.0
