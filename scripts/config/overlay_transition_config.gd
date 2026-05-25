class_name OverlayTransitionConfig
extends Resource
## @tunable: 视觉动画
## OverlayTransitionUI 调参（MVP-B 阶段 2）
##
## 设计原文：
##   tile-advanture-design/参数Resource化/MVP-B_痛点优先批.md §范围 / Resource 文件清单
##   tile-advanture-design/事件流程与队长过渡_MVP.md（入口 2 MVP 2.1）
##
## 用法：使用方 `const CFG: OverlayTransitionConfig = preload("res://assets/config/overlay_transition_config.tres")`，
## 运行时 `CFG.field_name` 访问。
##
## 字段从 OverlayTransitionUI.gd 顶部 11 个 const 迁出 9 个活跃字段；
## ICON_FONT_SIZE / COUNT_FONT_SIZE 是 α.5 .tscn 化遗留死代码，直接删除不迁。
## PHASE_IDLE / A / B / C / D 5 个状态机枚举不迁（不是可调参数）。


# ─────────────────────────────────────────
# Fade 时长（秒）
# ─────────────────────────────────────────

## 整段黑屏 fade in 时长
@export_range(0.0, 3.0, 0.05) var fade_in_duration: float = 0.4

## 整段黑屏 fade out 时长
@export_range(0.0, 3.0, 0.05) var fade_out_duration: float = 0.4

## 单行文字逐句 fade in 时长
@export_range(0.0, 3.0, 0.05) var line_fade_in_duration: float = 0.4

## 单行文字驻留时长（fade in 完成后保持的秒数）
@export_range(0.0, 10.0, 0.1) var line_hold_duration: float = 1.5

## 图标 fade in 时长
@export_range(0.0, 3.0, 0.05) var icon_fade_in_duration: float = 0.2


# ─────────────────────────────────────────
# 文本与图标
# ─────────────────────────────────────────

## icon 兜底字符（payload 未提供 icon 时使用）
@export var icon_fallback: String = "🔥"

## 单行文字字号
@export_range(8, 96) var line_font_size: int = 24

## 单行文字颜色
@export var line_color: Color = Color(1, 1, 1, 1)


# ─────────────────────────────────────────
# 超时保护
# ─────────────────────────────────────────

## Phase B（全黑期 await midpoint signal）超时秒数
## 超时后强制走 Phase C，防止外部信号丢失导致 UI 卡死
@export_range(0.5, 30.0, 0.5) var phase_b_timeout_sec: float = 5.0
