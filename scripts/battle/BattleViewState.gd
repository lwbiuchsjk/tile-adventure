class_name BattleViewState
extends RefCounted
## 战斗瞬时视觉态载体（MVP-γ 阶段 1）
##
## 设计原文：
##   tile-advanture-design/代码健康度回看/MVP-γ_拆分批1.md §数据结构
##
## 职责：
##   收敛战斗内单位的"瞬时视觉态" —— 原先散落在 WorldMap 的 3 个字典
##   （_battle_unit_visual_offsets / _battle_dying_units / _battle_displayed_hps）。
##   BattleAnimDirector（写方）在 Tween 推进中写入，WorldMapRenderer（读方，阶段 2）
##   在 _draw 中只读消费。本类是写方与读方之间的唯一数据接口。
##
## 生命周期：
##   与 BattleAnimDirector 一样由 WorldMap 在 _init_subsystems 创建、跨战斗复用；
##   每场战斗结束 / 中断时由 WorldMap 调 clear() 一次性清空（替代原 WorldMap 内
##   3 处 .clear() 散调用）。


## BattleUnit → 像素偏移（叠加在 battle_position * TILE_SIZE 之上）
## 用途：移动 Tween / 攻击推冲 / 颤抖；动画完成后 erase 自动恢复原位
var unit_visual_offsets: Dictionary = {}

## BattleUnit → alpha（1.0 → 0.0）
## 用途：死亡渐隐过程中的单位；渐隐完成后 erase
var dying_units: Dictionary = {}

## BattleUnit → 显示中的 HP（float，便于补间）
## 用途：被攻击单位 HP 条平滑过渡；不在字典时直接读 troop.current_hp
var displayed_hps: Dictionary = {}


## 战斗结束 / 中断时一次性清空 3 个字典
func clear() -> void:
	unit_visual_offsets.clear()
	dying_units.clear()
	displayed_hps.clear()
