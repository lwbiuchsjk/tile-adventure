class_name OccupationSystem
extends RefCounted
## 占据归属与影响范围系统（M4）
##
## 设计原文：
##   tile-advanture-design/城建锚实装/M4_占据归属与影响范围.md
##   tile-advanture-design/持久slot基础功能设计.md §四 影响范围 / §六 交互规则 / §6.5 占据触发 MVP 边界
##
## 承载四条闭环：
##   1. 占据判定：单位移动 / 战斗胜利后到达 slot 格 → try_occupy 触发归属翻转
##   2. 原子重置：归属切换时 influence_range / garrison_turns / occupy_turns 一次性重置
##   3. 回合末快照：自阵营回合 tick 时累计 occupy_turns / garrison_turns / 增长 influence_range
##   4. 影响范围查询：供 M6 产出结算使用（slots_covering）
##
## 关键时序约定（M4 + M5 共锚点）：
##   - 快照触发点 = 自阵营回合**开始**（经 TickRegistry），与 M5 建造倒计时同锚
##   - 仅处理 slot.owner_faction == faction 的 slot（自阵营过滤），避免双方各 tick 一次导致 +2
##   - MVP 阶段由 WorldMap 在 _on_turn_ended 中触发 TickRegistry.run_ticks(PLAYER)；
##     敌方侧快照等 M7 把 WorldMap 迁至 start_faction_turn(ENEMY_1) 时自然生效
##
## 代价钩子（MVP 占位）：
##   can_pay_occupation_cost / pay_occupation_cost 恒返回 true / 空实现，
##   留待后续接入资源消耗校验（见《待跟踪事项索引》P1）


# ─────────────────────────────────────────
# 占据判定
# ─────────────────────────────────────────

## 尝试让 unit_faction 占据指定 slot（移动结束 / 战斗胜利后调用）
## 返回值：是否发生归属翻转（true = 翻转，false = 同势力或无效输入）
##
## MVP 边界（§6.5）：
##   - 若格上仍有敌方单位，本函数**不应被调用**（由战斗系统拦截，战后再触发）
##   - 调用前 can_pay_occupation_cost 应返回 true（MVP 恒成立）
static func try_occupy(slot: PersistentSlot, unit_faction: int) -> bool:
	if slot == null:
		push_warning("OccupationSystem.try_occupy: slot 为 null")
		return false
	if unit_faction == Faction.NONE:
		# 中立单位不会发起占据；未来若有中立单位概念可移除此判断
		return false

	# 同势力：不翻转，也不重置计数（驻扎累计由快照接管）
	if slot.owner_faction == unit_faction:
		return false

	# 代价校验（MVP 恒 true，未来接入资源消耗）
	if not can_pay_occupation_cost(slot, unit_faction):
		return false
	pay_occupation_cost(slot, unit_faction)

	# 原子重置（§4.5）：
	#   - owner 切换到新势力
	#   - influence_range 重置为 initial_range（旧势力覆盖立即消失、新势力初始覆盖立即生效）
	#   - garrison_turns / occupy_turns 清零
	#   - active_build 清空（被敌占取消在建，石料不退；M5 设计 §五"被敌占"）
	#   - level / 产出配置 / 历史记录保留，不动
	slot.owner_faction = unit_faction
	slot.influence_range = slot.initial_range
	slot.garrison_turns = 0
	slot.occupy_turns = 0
	slot.active_build = null
	return true


# ─────────────────────────────────────────
# 回合末快照
# ─────────────────────────────────────────

## 自阵营回合 tick 时调用，更新该势力所属 slot 的计数与影响范围
## 由 TurnManager.start_faction_turn → TickRegistry.run_ticks(faction) 驱动
##
## 参数：
##   faction        —— 当前自阵营 ID（只处理 owner_faction == faction 的 slot）
##   all_slots      —— 地图上所有 PersistentSlot（通常传 MapSchema.persistent_slots）
##   units_by_pos   —— { Vector2i: int faction_id }，记录每格上的单位所属势力
##
## 规则：
##   - occupy_turns += 1（自势力拥有该 slot 的自阵营回合累计）
##   - garrison_turns：自势力单位在上 → +1；否则清零（断档）
##   - influence_range：自势力单位在上且未达 max → += growth_rate，封顶于 max_range
##   - influence_range 达 max 后保持不衰减（§4.4），仅归属切换才 reset
static func snapshot_turn_end(faction: int, all_slots: Array, units_by_pos: Dictionary) -> void:
	if faction == Faction.NONE:
		return
	for entry in all_slots:
		var slot: PersistentSlot = entry as PersistentSlot
		if slot == null:
			continue
		# 自阵营过滤：只处理归属于 faction 的 slot
		# 决策背景：若不过滤，双方各 tick 一次会导致 +2，影响范围增长机制基本被跳过
		if slot.owner_faction != faction:
			continue

		# 占据计数：归属稳定即累加（翻转回合在 try_occupy 中清零）
		slot.occupy_turns += 1

		# 驻扎判定：当前格上是否有自势力单位
		var has_own_unit: bool = _has_faction_unit_at(slot.position, faction, units_by_pos)
		if has_own_unit:
			slot.garrison_turns += 1
			# 影响范围按 growth_rate 增长，封顶 max_range
			if slot.influence_range < slot.max_range:
				slot.influence_range = mini(
					slot.influence_range + slot.growth_rate,
					slot.max_range
				)
		else:
			# 断档：无单位驻扎则清零 garrison_turns
			# influence_range 不回落（达 max 前保持当前值，由归属切换才重置）
			slot.garrison_turns = 0


# ─────────────────────────────────────────
# 影响范围查询（供 M6 产出结算）
# ─────────────────────────────────────────

## 查询某格被哪些同势力 slot 的影响范围覆盖
## pos         —— 目标格
## faction     —— 过滤势力（只计入 owner_faction == faction 的 slot）
## all_slots   —— 候选 slot 列表
## 返回：覆盖该格的 slot 数组（按 all_slots 顺序），空数组表示未被覆盖
##
## 距离度量：曼哈顿（与势力场 / 染色系统同口径，见 §四）
static func slots_covering(pos: Vector2i, faction: int, all_slots: Array) -> Array:
	var result: Array = []
	if faction == Faction.NONE:
		return result
	for entry in all_slots:
		var slot: PersistentSlot = entry as PersistentSlot
		if slot == null:
			continue
		if slot.owner_faction != faction:
			continue
		var d: int = absi(pos.x - slot.position.x) + absi(pos.y - slot.position.y)
		if d <= slot.influence_range:
			result.append(slot)
	return result


# ─────────────────────────────────────────
# 预留：占据代价钩子（MVP 不实装）
# ─────────────────────────────────────────

## 代价校验钩子：MVP 恒返回 true（无代价）
## 未来可在此插入资源 / 移动力 / 补给等消耗校验
static func can_pay_occupation_cost(_slot: PersistentSlot, _unit_faction: int) -> bool:
	return true


## 代价扣除钩子：MVP 空实现
## 未来在 try_occupy 内部已经确认可支付后调用，用于真正扣除资源
static func pay_occupation_cost(_slot: PersistentSlot, _unit_faction: int) -> void:
	pass


# ─────────────────────────────────────────
# 内部工具
# ─────────────────────────────────────────

## 判断 pos 上是否有 faction 势力的单位
## units_by_pos: { Vector2i: int faction_id }
## MVP 简化：每格至多一个单位（单位字典直接存势力 ID）
static func _has_faction_unit_at(pos: Vector2i, faction: int, units_by_pos: Dictionary) -> bool:
	if not units_by_pos.has(pos):
		return false
	var f: int = int(units_by_pos[pos])
	return f == faction
