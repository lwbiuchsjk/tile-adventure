class_name LevelSlot
extends RefCounted
## 关卡实体数据
## 关卡以 Slot 形式分布在地图上，有三种状态：
##   UNCHALLENGED: 未挑战，可交互
##   REPELLED: 已击退，冷却中，不可交互，不可通行
##   DEFEATED: 已击败，从地图移除
## 每个关卡携带 1~N 支敌方部队，战斗结算时参与伤害计算。

## 关卡状态
enum State {
	UNCHALLENGED = 0,  ## 未挑战
	CHALLENGED   = 1,  ## 已挑战（兼容旧逻辑，等同 DEFEATED）
	REPELLED     = 2,  ## 已击退，冷却中
	DEFEATED     = 3,  ## 已击败
}

## 关卡在地图上的格坐标
var position: Vector2i = Vector2i.ZERO

## 当前状态
var state: State = State.UNCHALLENGED

## 敌方部队列表（1~N 支）
var troops: Array[TroopData] = []

## 关卡难度（由轮次索引决定，影响 base_damage）
var difficulty: int = 0

## 强度档位（0=弱, 1=中, 2=强, 3=超）
var tier: int = 0

## 关卡胜利奖励列表（初始化时预生成）
var rewards: Array[ItemData] = []

## 击退冷却剩余回合数（仅 REPELLED 状态使用）
var cooldown_turns: int = 0

## 预留：敌方角色（当前为 null，后续支持敌方角色）
var character = null

## 判断是否已挑战（兼容旧接口，CHALLENGED/DEFEATED/REPELLED 均视为已挑战）
func is_challenged() -> bool:
	return state != State.UNCHALLENGED

## 判断是否处于击退冷却状态
func is_repelled() -> bool:
	return state == State.REPELLED

## 判断是否已击败
func is_defeated() -> bool:
	return state == State.DEFEATED or state == State.CHALLENGED

## 判断该关卡是否阻挡通行（未挑战和击退状态均阻挡）
func is_blocking() -> bool:
	return state == State.UNCHALLENGED or state == State.REPELLED

## 判断是否可交互（仅未挑战状态可触发战斗）
func is_interactable() -> bool:
	return state == State.UNCHALLENGED

## 标记为已挑战（兼容旧接口，实际标记为 DEFEATED）
func mark_challenged() -> void:
	state = State.DEFEATED

## 标记为已击败
func mark_defeated() -> void:
	state = State.DEFEATED

## 标记为已击退，设置冷却回合数
func mark_repelled(cooldown: int) -> void:
	state = State.REPELLED
	cooldown_turns = cooldown

## 冷却递减（每回合调用）
## 返回 true 表示冷却结束，已恢复为可交互状态
func tick_cooldown() -> bool:
	if state != State.REPELLED:
		return false
	cooldown_turns -= 1
	if cooldown_turns <= 0:
		cooldown_turns = 0
		state = State.UNCHALLENGED
		return true
	return false

## 对敌方部队应用伤害
## damages: 与 troops 列表一一对应的伤害值
func apply_enemy_damages(damages: Array[int]) -> void:
	for i in range(mini(troops.size(), damages.size())):
		troops[i].take_damage(damages[i])

## 移除兵力为 0 的敌方部队
## 返回 true 表示全部敌方部队被消灭
func remove_defeated_troops() -> bool:
	var alive: Array[TroopData] = []
	for troop in troops:
		if not troop.is_defeated():
			alive.append(troop)
	troops = alive
	return troops.is_empty()

## 获取敌方部队组成的显示文本（如"剑兵(R)×1, 弓兵(SR)×1"）
func get_troops_display() -> String:
	if troops.is_empty():
		return "无敌方部队"
	# 统计相同类型+品质的部队数量
	var counts: Dictionary = {}
	for troop in troops:
		var key: String = troop.get_display_text()
		if counts.has(key):
			counts[key] = int(counts[key]) + 1
		else:
			counts[key] = 1
	# 拼接显示文本
	var parts: Array[String] = []
	for key in counts:
		var k: String = key as String
		var count: int = int(counts[k])
		if count > 1:
			parts.append("%s×%d" % [k, count])
		else:
			parts.append(k)
	return ", ".join(parts)

## 获取敌方部队详细状态（含兵力信息，用于战斗预览）
func get_troops_detail_display() -> String:
	if troops.is_empty():
		return "无敌方部队"
	var parts: Array[String] = []
	for troop in troops:
		parts.append("%s %d/%d" % [troop.get_display_text(), troop.current_hp, troop.max_hp])
	return ", ".join(parts)

## 获取奖励的显示文本
func get_rewards_display() -> String:
	if rewards.is_empty():
		return "无奖励"
	var parts: Array[String] = []
	for item in rewards:
		if item.stack_count > 1:
			parts.append("%s×%d" % [item.get_display_text(), item.stack_count])
		else:
			parts.append(item.get_display_text())
	return ", ".join(parts)
