class_name LevelSlot
extends RefCounted
## 关卡实体数据
## 关卡以 Slot 形式分布在地图上，有两种状态：
##   UNCHALLENGED: 未挑战，可交互
##   DEFEATED: 已击败，从地图移除
## 每个关卡携带 1~N 支敌方部队，战斗结算时参与伤害计算。
##
## ⚠ 历史枚举（2026-05-17 REPELLED 清理批清除）：
##   - CHALLENGED：M1 重构（2026-04-22）后已不再写入；本批一并清除
##   - REPELLED：E5 战场制重构后击退路径不可达（mark_repelled / tick_cooldown 0 调用方）；本批一并清除
## 历史细节可经 git log 追溯。

## 关卡状态
enum State {
	UNCHALLENGED = 0,  ## 未挑战
	DEFEATED     = 1,  ## 已击败
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

## L1.3a 阶段 C：climax 决战 boss 标记。为 true 的 pack 参战时该场 = climax 决战
## （BattleCoordinator 据此 set_climax_battle → 决定昏迷 sudden-death / 胜利 dispatch_climax_victory）。
## 标记随 pack 移动而保留，比固定坐标可靠。EC 扎营时钟触发 spawn 时置位。
var is_climax_boss: bool = false

## 关卡胜利奖励列表（初始化时预生成）
var rewards: Array[ItemData] = []

# ─────────────────────────────────────────
# M1 新增字段（敌方 AI §4.2 / 城建锚 §三）
# ─────────────────────────────────────────

## 归属势力 ID（Faction.NONE / PLAYER / ENEMY_1 ...）
## 默认 NONE 中立；M2 地图生成 / M7 敌方 AI 创建敌方部队时写入
var faction: int = Faction.NONE

## 本回合剩余移动力（M3 回合开始时按部队最大移动力重置；M7 移动消耗）
var remaining_movement: int = 0

## 本回合是否已移动（M7 用于跳过已移动单位的决策）
var has_moved_this_turn: bool = false

## AI 决策缓存（M7 写入，键值由 M7 定义；MVP 先空字典占位）
## 用途示例：缓存当前 A* 路径、当前目标 slot、上一回合行动类型等
var ai_cache: Dictionary = {}

## 判断是否已击败
func is_defeated() -> bool:
	return state == State.DEFEATED

## 判断该关卡是否阻挡通行（仅未挑战状态阻挡）
## 注：与 is_interactable() 当前等价；保留独立函数避免后续扩展状态时双处改动的隐性耦合
func is_blocking() -> bool:
	return state == State.UNCHALLENGED

## 判断是否可交互（仅未挑战状态可触发战斗）
func is_interactable() -> bool:
	return state == State.UNCHALLENGED

## 标记为已击败
func mark_defeated() -> void:
	state = State.DEFEATED

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
