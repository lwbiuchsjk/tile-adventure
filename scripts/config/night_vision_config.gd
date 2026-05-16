class_name NightVisionConfig
extends Resource
## 夜晚视野子系统调参（MVP-B 阶段 1）
##
## 设计原文：
##   tile-advanture-design/参数Resource化/MVP-B_痛点优先批.md §范围 / Resource 文件清单
##   tile-advanture-design/夜晚视野_MVP.md
##
## 用法：使用方 `const CFG: NightVisionConfig = preload("res://assets/config/night_vision_config.tres")`，
## 运行时 `CFG.field_name` 访问。编辑器内双击 .tres 在 inspector 调字段，存盘后下次启动生效。
##
## 字段从 NightVisionLayer.gd 顶部 10 个 const 迁出（去 NIGHT_/FOG_/DAY_ 前缀，snake_case）。
## `NIGHT_OVERLAY_MATERIAL` (ShaderMaterial preload) 不迁——是资源引用而非可调参数。


# ─────────────────────────────────────────
# CanvasLayer 层数
# ─────────────────────────────────────────

## 夜晚遮罩 CanvasLayer 层数（介于世界 layer=0 与 UILayer=10 之间，让 HUD 不被夜晚遮罩压暗）
@export_range(1, 9) var overlay_canvas_layer: int = 5

## 浓雾外敌人信号 CanvasLayer 层数（在夜晚遮罩之上、UILayer 之下；信号菱形绕开黑幕）
@export_range(1, 9) var fog_signal_canvas_layer: int = 6


# ─────────────────────────────────────────
# 视野半径与浓雾衰减
# ─────────────────────────────────────────

## 玩家队伍光源照亮半径（格数）—— 屏幕像素空间转换时 × TILE_SIZE × camera.zoom
@export_range(0.5, 20.0, 0.1) var vision_radius_grids: float = 3.5

## 浓雾过渡带宽度（格数）—— shader smoothstep 衰减带，让光源边缘平滑而非硬切
@export_range(0.0, 5.0, 0.05) var fog_falloff_grids: float = 0.75


# ─────────────────────────────────────────
# 昼夜 / 战斗 Fade 时长
# ─────────────────────────────────────────

## 昼夜切换 fade 时长（秒）—— DAY ↔ NIGHT 平滑过渡
@export_range(0.0, 3.0, 0.05) var fade_duration: float = 0.6

## 战斗强制白天 fade 时长（秒）—— 与战斗 zoom BATTLE_ZOOM_TWEEN_DURATION 同步
@export_range(0.0, 3.0, 0.05) var battle_force_day_duration: float = 0.3


# ─────────────────────────────────────────
# 浓雾外敌人闪烁参数
# 公式：alpha = blink_base_alpha + blink_amp * (sin(2πt/blink_period + phase) * 0.5 + 0.5)
# ─────────────────────────────────────────

## 闪烁 alpha 基线（最小值）
@export_range(0.0, 1.0, 0.01) var blink_base_alpha: float = 0.35

## 闪烁 alpha 振幅（叠加在 base 之上）
@export_range(0.0, 1.0, 0.01) var blink_amp: float = 0.45

## 闪烁周期（秒）—— 一次完整正弦周期的时长
@export_range(0.1, 10.0, 0.1) var blink_period: float = 1.6


# ─────────────────────────────────────────
# 浓雾外敌人信号菱形
# 屏幕像素半径 = TILE_SIZE × camera.zoom.x × fog_signal_diamond_scale
# ─────────────────────────────────────────

## 信号菱形相对 TILE_SIZE × zoom 的缩放比例（半径系数）
@export_range(0.05, 1.0, 0.01) var fog_signal_diamond_scale: float = 0.30
