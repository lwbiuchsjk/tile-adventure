class_name LevelSlot
extends RefCounted
## 关卡实体数据
## 关卡以 Slot 形式分布在地图上，有"未挑战/已挑战"两种状态。
## 已挑战的关卡不可再次进入。
## 每个关卡携带 1~N 支敌方部队，战斗结算时参与伤害计算。

## 关卡状态
enum State {
	UNCHALLENGED = 0,  ## 未挑战
	CHALLENGED   = 1,  ## 已挑战
}

## 关卡在地图上的格坐标
var position: Vector2i = Vector2i.ZERO

## 当前状态
var state: State = State.UNCHALLENGED

## 敌方部队列表（1~N 支）
var troops: Array[TroopData] = []

## 关卡难度（由轮次索引决定，影响 base_damage）
var difficulty: int = 0

## 关卡胜利奖励列表（初始化时预生成）
var rewards: Array[ItemData] = []

## 预留：敌方角色（当前为 null，后续支持敌方角色）
var character = null

## 判断是否已挑战
func is_challenged() -> bool:
	return state == State.CHALLENGED

## 标记为已挑战
func mark_challenged() -> void:
	state = State.CHALLENGED

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
