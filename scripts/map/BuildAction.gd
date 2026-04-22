class_name BuildAction
extends RefCounted
## 在建动作数据
## 表示 PersistentSlot 当前进行中的建造任务（MVP 仅升级一种）
## 设计原文：tile-advanture-design/持久slot升级建造设计.md §三 / §四
##
## 字段约定：
##   action_type     —— 动作类型（MVP 仅 UPGRADE）
##   target_level    —— 目标等级（升级完成后 PersistentSlot.level 应等于此值）
##   remaining_turns —— 剩余 tick 回合数；归零时由 M3 回合框架触发完成
##
## 完成时机：升级建造设计 §5.5——"下一自阵营回合开始优先 tick"

## 动作类型枚举
## MVP 仅 UPGRADE；预留 DEMOLISH（拆除）/ REPAIR（修复）等扩展位
enum ActionType {
	UPGRADE = 0,  ## 升级（提升 level）
}

## 当前在建动作类型
var action_type: ActionType = ActionType.UPGRADE

## 升级目标等级（仅 UPGRADE 动作有效）
## MVP 范围 1..3；新建从 0 起、最高 3 级
var target_level: int = 1

## 剩余 tick 回合数（≥ 0）
## MVP 阶段全部 1 回合（升级建造设计 §5.3）；M5 配置中可调
var remaining_turns: int = 1


## 推进一次 tick，返回是否完成
## 设计上由 M3 回合框架在"下一自阵营回合开始"统一调用
## 此处仅做计数推进，完成结算（修改宿主 slot 等级 / 释放槽位）由调用方负责
func tick() -> bool:
	if remaining_turns > 0:
		remaining_turns -= 1
	return remaining_turns <= 0


## 是否已完成（剩余回合数 ≤ 0）
func is_finished() -> bool:
	return remaining_turns <= 0
