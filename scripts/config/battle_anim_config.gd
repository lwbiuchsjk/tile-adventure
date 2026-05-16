class_name BattleAnimConfig
extends Resource
## 战斗单位动画调参（MVP-B 阶段 3）
##
## 设计原文：
##   tile-advanture-design/参数Resource化/MVP-B_痛点优先批.md §范围 / Resource 文件清单
##   tile-advanture-design/战斗信息传达_战斗内_MVP.md（入口 1.2 §8 时长表）
##
## 用法：BattleAnimDirector / WorldMap 各自 preload 同一份 .tres
##   `const ANIM_CFG: BattleAnimConfig = preload("res://assets/config/battle_anim_config.tres")`
##   运行时 `ANIM_CFG.field_name` 访问。preload 是 Godot 资源单例，多处 preload 指向同一实例无内存损耗。
##
## 字段从 WorldMap.gd:639-667 迁出 22 个（11 普通动画 + 4 飘字色 + 7 致命一击升级参数）。


# ─────────────────────────────────────────
# 普通动画时长（秒）+ 几何参数
# ─────────────────────────────────────────

## 单位移动 Tween 时长（直线移动）
@export_range(0.0, 2.0, 0.05) var move_tween_duration: float = 0.35

## 攻击推冲 / 回弹 单段时长（推出去 + 拉回各一段）
@export_range(0.0, 1.0, 0.01) var thrust_duration: float = 0.15

## 目标颤抖时长（与推冲并行）
@export_range(0.0, 1.0, 0.01) var shake_duration: float = 0.20

## 单位死亡渐隐时长
@export_range(0.0, 2.0, 0.05) var die_duration: float = 0.30

## 伤害飘字上飘渐隐时长
@export_range(0.0, 3.0, 0.05) var float_damage_duration: float = 1.0

## 跳过飘字时长（敌方 skip turn 时显示"跳过"）
@export_range(0.0, 3.0, 0.05) var float_skip_duration: float = 0.6

## HP 条平滑过渡时长（P1-5：与攻击推冲完成同节奏）
@export_range(0.0, 2.0, 0.05) var hp_tween_duration: float = 0.30

## 敌方两次 step 之间最小间隔（让玩家看清 actor 切换）
@export_range(0.0, 2.0, 0.01) var enemy_step_gap: float = 0.18

## 推冲距离 = TILE_SIZE × 该比例（0.5 = 半格）
@export_range(0.0, 2.0, 0.05) var thrust_distance_ratio: float = 0.5

## 颤抖振幅（±px）
@export_range(0.0, 20.0, 0.5) var shake_amplitude: float = 2.0

## 颤抖在 shake_duration 内完成的正弦周期数
@export_range(0.0, 10.0, 0.5) var shake_oscillations: float = 3.0


# ─────────────────────────────────────────
# 飘字配色（与克制图标色板呼应；战斗内 MVP §8）
# ─────────────────────────────────────────

## counter_factor > 1.0 克制 → 优势绿
@export var float_color_advantage: Color = Color(0.3, 0.9, 0.3)

## counter_factor < 1.0 受克 → 劣势橙
@export var float_color_disadvantage: Color = Color(1.0, 0.55, 0.1)

## counter_factor = 1.0 中性 → 默认红
@export var float_color_neutral: Color = Color(0.9, 0.3, 0.3)

## 跳过飘字 → 灰
@export var float_color_skip: Color = Color(0.65, 0.65, 0.65)


# ─────────────────────────────────────────
# 致命一击（队长 COMA 触发的那一击专用 —— 更慢、幅度更大）
# 设计意图：让玩家清楚看到"这一击导致队长昏迷"的因果，强化转折感
# 触发：BattleSession._emit_unit_attacked 检测 target==leader && _is_leader_in_coma() 后传 is_killing_blow=true
# ─────────────────────────────────────────

@export_group("致命一击")

## 致命一击推冲/回弹单段时长（普通 0.15）
@export_range(0.0, 2.0, 0.05) var killing_thrust_duration: float = 0.40

## 致命一击推冲距离比（普通 0.5；满格推冲）
@export_range(0.0, 3.0, 0.1) var killing_thrust_distance_ratio: float = 1.0

## 致命一击目标颤抖时长（普通 0.20）
@export_range(0.0, 2.0, 0.05) var killing_shake_duration: float = 0.60

## 致命一击颤抖振幅 ±px（普通 2.0）
@export_range(0.0, 40.0, 0.5) var killing_shake_amplitude: float = 6.0

## 致命一击颤抖正弦周期数（普通 3.0）
@export_range(0.0, 20.0, 0.5) var killing_shake_oscillations: float = 5.0

## 致命一击 HP 条平滑过渡（普通 0.30）
@export_range(0.0, 3.0, 0.05) var killing_hp_tween_duration: float = 0.60

## 致命一击伤害飘字上飘时长（普通 1.0）
@export_range(0.0, 5.0, 0.05) var killing_float_damage_duration: float = 1.5
