class_name BattleVisualConfig
extends Resource
## 战斗视觉调参（MVP-B 阶段 4）
##
## 设计原文：
##   tile-advanture-design/参数Resource化/MVP-B_痛点优先批.md §范围 / Resource 文件清单
##   tile-advanture-design/战斗信息传达_战斗内_MVP.md §8 视觉规格基准
##
## 用法：WorldMap / WorldMapRenderer / BattleAnimDirector 各自 preload 同一份 .tres
##   `const VISUAL_CFG: BattleVisualConfig = preload("res://assets/config/battle_visual_config.tres")`
##   运行时 `VISUAL_CFG.field_name` 访问。preload 是 Godot 资源单例，多处指向同一实例无内存损耗。
##
## 字段从 WorldMap.gd:216-240/599-637 迁出 31 个（zoom / dim / tilt / 战场视觉 / HP / 克制图标）。
## EXPLORE_HUD_BOTTOM_RESERVE_PX + 派生 OFFSET_PX 保留 .gd（探索 HUD 范畴，非战斗视觉）。


# ─────────────────────────────────────────
# 战斗 Zoom / Dim overlay / 镜头倾斜
# ─────────────────────────────────────────

## 战场外预留格数（战场居中后四周留几格地图作缓冲）
@export_range(0, 5) var zoom_margin_grid: int = 1

## HUD 上下保留像素（CanvasLayer 不受 Camera zoom 影响，物理像素恒定占屏）
@export_range(0, 400) var zoom_hud_reserve_px: int = 120

## 战斗 zoom 平滑过渡时长（秒）—— 与 NightVisionConfig.battle_force_day_duration 同步
@export_range(0.0, 2.0, 0.05) var zoom_tween_duration: float = 0.3

## 战场外压暗 overlay 颜色（含 alpha；玩家注意力聚焦战场）
@export var dim_color: Color = Color(0.0, 0.0, 0.0, 0.50)

## overlay 覆盖范围 padding（像素）—— 保证 camera 视野完全覆盖（含 zoom out 后的视野扩张）
@export_range(0, 16384) var dim_padding_px: int = 4096

## 战斗镜头倾斜角度（弧度）—— 5° = 0.0873；HUD 在 CanvasLayer 自动保持水平
@export_range(0.0, 1.57, 0.001) var tilt_rad: float = 0.0872664626


# ─────────────────────────────────────────
# 战场 Arena 边框 + 移动 / 攻击范围
# ─────────────────────────────────────────

## 战场 arena 黄色边框颜色
@export var arena_border_color: Color = Color(1.0, 0.85, 0.0, 0.65)

## 战场 arena 边框线宽（px）
@export_range(0.0, 10.0, 0.5) var arena_border_width: float = 2.0

## 当前 actor 可移动格子填充色（白色半透）
@export var reachable_color: Color = Color(1.0, 1.0, 1.0, 0.16)

## 当前 actor 可攻击格子填充色（红色半透）
@export var attackable_color: Color = Color(1.0, 0.20, 0.20, 0.28)

## 攻击范围描边色（黄色，与 arena 同色调，避免与敌方红家族冲突）
@export var attackable_border_color: Color = Color(1.0, 0.85, 0.0, 0.85)

## 攻击范围描边线宽（px）
@export_range(0.0, 10.0, 0.5) var attackable_border_width: float = 3.5


# ─────────────────────────────────────────
# 当前 actor 圆环高亮
# ─────────────────────────────────────────

## 当前行动单位脚下圆环颜色
@export var current_actor_ring_color: Color = Color(1.0, 1.0, 1.0, 1.0)

## 当前行动单位圆环线宽（px）
@export_range(0.0, 10.0, 0.5) var current_actor_ring_width: float = 3.0


# ─────────────────────────────────────────
# HP 条（尺寸 + 3 段配色 + 背景 + 队长金边）
# ─────────────────────────────────────────

## HP 条宽度（px）
@export_range(8, 80) var hp_bar_width: int = 24

## HP 条高度（px）
@export_range(2, 20) var hp_bar_height: int = 4

## HP 满血段颜色（绿）
@export var hp_color_full: Color = Color(0.20, 0.85, 0.30, 1.0)

## HP 中血段颜色（黄）
@export var hp_color_mid: Color = Color(0.95, 0.85, 0.20, 1.0)

## HP 低血段颜色（红）
@export var hp_color_low: Color = Color(0.90, 0.25, 0.25, 1.0)

## HP 条背景色（黑色半透）
@export var hp_bar_bg_color: Color = Color(0.0, 0.0, 0.0, 0.55)

## 队长 HP 条金边色（#FFD700）—— 与克制图标分离的视觉标识
@export var leader_hp_border_color: Color = Color(1.0, 0.84, 0.0)

## 队长 HP 条金边线宽（px）
@export_range(0.0, 10.0, 0.5) var leader_hp_border_width: float = 2.0


# ─────────────────────────────────────────
# 兵种字符
# ─────────────────────────────────────────

## 兵种字符颜色（白色，高对比）
@export var troop_label_color: Color = Color(1, 1, 1)


# ─────────────────────────────────────────
# 克制图标（▲▼● 三态 + 尺寸 + 间距 + eps）
# ─────────────────────────────────────────

## 克制图标尺寸（px）—— 对 TILE_SIZE=72 占比约 25%
@export_range(2.0, 40.0, 1.0) var counter_icon_size: float = 12.0

## 克制图标左右间距（中心间距 px）
@export_range(2.0, 40.0, 1.0) var counter_icon_gap: float = 12.0

## ▲ 优势绿
@export var counter_icon_advantage: Color = Color(0.3, 0.85, 0.3)

## ▼ 劣势警示橙
@export var counter_icon_disadvantage: Color = Color(1.0, 0.55, 0.1)

## ● 中性亮白
@export var counter_icon_neutral: Color = Color(0.95, 0.95, 0.95)

## counter_factor 浮点比较误差容忍
@export_range(0.0001, 0.01, 0.0001) var counter_factor_eps: float = 0.001


# ─────────────────────────────────────────
# 单位头顶图标轨道 + 已行动灰
# ─────────────────────────────────────────

## 单位头顶图标距 radius 上方偏移（px）—— 与队长银三角共用轨道
@export_range(0.0, 30.0, 1.0) var head_offset: float = 8.0

## 玩家方已行动单位填充色（灰色）—— 与阵营色区分"已 / 未行动"
@export var player_acted_color: Color = Color(0.55, 0.55, 0.55)
