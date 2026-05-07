class_name BattleUnit
extends RefCounted
## 战斗内单位（E 战斗就地展开 MVP）
##
## 设计原文：tile-advanture-design/探索体验实装/E_战斗就地展开_MVP.md §4.3
##
## 职责：
##   - 战斗内每个"格上单位"的状态载体（玩家方一支部队 = 一个 BattleUnit；敌方同理）
##   - 复用 TroopData 的 hp / 兵种 / 品质（不复制数据，只持引用）
##   - 增加战斗专属属性：战场坐标 / 移动 / 攻击范围 / 本回合行动标记
##
## 与 CharacterData / TroopData 的关系：
##   PLAYER 方：character + character.troop 都引用现有 _characters 数组中的对象
##   ENEMY  方：character == null；troop 引用 LevelSlot.troops 中的某一支
##   战斗内对 troop.current_hp 的修改会"反向"影响探索态数据——这是预期行为：
##   战斗结束后玩家 / 敌方部队的损血状态自然延续到探索态


# ─────────────────────────────────────
# 字段
# ─────────────────────────────────────

## 阵营：Faction.PLAYER / Faction.ENEMY_1
var owner_faction: int = 0

## 部队数据（hp / 兵种 / 品质）；持引用，不复制
var troop: TroopData = null

## 角色数据（仅 PLAYER 方有）；ENEMY 方为 null
var character: CharacterData = null

## 来源 LevelSlot（仅 ENEMY 方有）；用于战斗胜利时定位敌方包做奖励 / 清理
## PLAYER 方为 null
var source_level: LevelSlot = null

## 战场内格坐标（绝对世界坐标，与 MapSchema 共用坐标系）
var battle_position: Vector2i = Vector2i.ZERO

## 兵种移动力（来自 battle_unit_config.csv 的 move_range 字段）
var move_range: int = 0

## 兵种攻击范围（来自 battle_unit_config.csv 的 attack_range 字段；曼哈顿距离）
var attack_range: int = 0

## 本回合是否已移动（先移动后攻击，移动后不能再移动）
var has_moved: bool = false

## 本回合是否已攻击（攻击后回合结束）
var has_attacked: bool = false

## 是否在战场上（false = 未上场，§2.4 极端兜底）
## 未上场单位不参与战斗 / 不渲染；战斗结束后玩家方无变化、敌方按"消灭" / "保留"路径处理
var is_active: bool = true


# ─────────────────────────────────────
# 工具方法
# ─────────────────────────────────────

## 是否存活（hp > 0）
func is_alive() -> bool:
	return troop != null and troop.current_hp > 0


## 是否本回合还能行动（未结束 + 未跳过）
## "可行动" = 未结束（移动 + 攻击至少一项可做）
func can_act_this_turn() -> bool:
	return is_active and is_alive() and not has_attacked


## 重置回合标记（每回合开始调用）
func reset_turn_flags() -> void:
	has_moved = false
	has_attacked = false


## 显示文本（HUD / 调试用）
## E2 BattleHUD 接入时若需要"队长"前缀，再扩展（参考 WorldMap._get_all_troops_display 的处理）
func get_display_text() -> String:
	if troop == null:
		return "(空单位)"
	return "%s %d/%d" % [troop.get_display_text(), troop.current_hp, troop.max_hp]
