class_name EnemyReinforcement
extends RefCounted
## 敌方增援生成（M7）
##
## 设计原文：
##   tile-advanture-design/城建锚实装/M7_敌方AI.md §范围「增援」
##   tile-advanture-design/敌方AI基础行为设计.md §3.2 / §3.3 增援生成规则
##
## 规则：
##   - 触发时机：每 5 敌方回合（由 EnemyAI._step_reinforcement 决定，本类不判断时机）
##   - 位置：敌方核心 persistent slot 的影响范围内（曼哈顿距离 ≤ influence_range）
##     且 is_passable 地形、无部队包 / 玩家单位 / 持久 slot 占用的空地
##   - 数量：MVP 一批 1 个 LevelSlot
##   - 随机池：复用 enemy_troop_pool.csv（通过 EnemyTroopGenerator.generate_troops）
##
## 静态纯函数；所有状态通过 WorldView facade 读写（MVP-β）


## 生成一批增援并注入 WorldView 暴露的 _level_slots 字典
## world_view: WorldView facade（强类型，访问点编译期可校验 —— MVP-β）
## force_tier: -1（默认）= 按 cycle 加权抽 tier；≥ 0 = 强制使用指定 tier（跳过抽样）
##             用于 P1-1a 修复：末周期 initial deploy 第 1 个 pack 强制 tier=3 保证最强敌人出现
## 返回：实际 spawn 的 LevelSlot；未找到空地 / 配置缺失时返回 null
##
## P0 第二阶段（整局节奏重设计）：
##   - spawn 锚改为 world_view.get_enemy_core_origin_pos()（PCG 缓存的原始位置，不查 owner）
##     原因：玩家占领前两周期 CORE_TOWN 后 owner 翻转，按 owner 查找会失效；用原始位置保证 spawn 持续
##   - tier 按当前 cycle 从 world_view.get_enemy_tier_ratio_rows() 加权抽样（默认路径）
##   - force_tier ≥ 0 时跳过权重抽样直接使用（initial deploy 末周期强制 tier 3）
static func spawn_batch(world_view: WorldView, force_tier: int = -1) -> LevelSlot:
	if world_view == null:
		return null

	var schema: MapSchema = world_view.get_schema()
	if schema == null:
		push_warning("EnemyReinforcement.spawn_batch: _schema 未初始化")
		return null

	# P0 第二阶段：用 WorldMap 缓存的 PCG 原始位置作 spawn 锚（不查 owner）
	var core_origin: Vector2i = world_view.get_enemy_core_origin_pos()
	if core_origin.x < 0 or core_origin.y < 0:
		push_warning("EnemyReinforcement.spawn_batch: _enemy_core_origin_pos 未缓存（PCG 后应有效），跳过本次")
		return null

	# 查 PersistentSlot 拿 influence_range（仍然要找 CORE_TOWN，但只用其位置半径，不用其 owner）
	# core_origin 即原始位置；只需 schema 中位置匹配即可（不管 owner 谁）
	var enemy_core: PersistentSlot = _find_slot_at(schema.persistent_slots, core_origin)
	if enemy_core == null:
		push_warning("EnemyReinforcement.spawn_batch: 原始位置 %s 未找到 PersistentSlot" % core_origin)
		return null

	# 收集影响范围内的可用空地
	var level_slots: Dictionary = world_view.get_level_slots()
	var resource_slots: Dictionary = world_view.get_resource_slots()
	var unit: UnitData = world_view.get_unit()
	var unit_pos: Vector2i = unit.position if unit != null else Vector2i(-1, -1)

	var candidates: Array[Vector2i] = _find_passable_empty_tiles(
		schema, core_origin, enemy_core.influence_range,
		level_slots, resource_slots, unit_pos
	)
	if candidates.is_empty():
		push_warning("EnemyReinforcement.spawn_batch: 核心影响范围内无空地，跳过本次")
		return null

	# 随机选一格
	var rng: RandomNumberGenerator = world_view.get_world_rng()
	var idx: int = 0
	if rng != null:
		idx = rng.randi_range(0, candidates.size() - 1)
	else:
		idx = randi_range(0, candidates.size() - 1)
	var spawn_pos: Vector2i = candidates[idx]

	# 生成部队数据
	var generator: EnemyTroopGenerator = world_view.get_enemy_generator()
	if generator == null:
		push_warning("EnemyReinforcement.spawn_batch: EnemyTroopGenerator 未初始化")
		return null

	# P0 第二阶段：按当前 cycle 从 tier_ratio 加权抽 tier；force_tier ≥ 0 时跳过抽样
	# P1-1a: 末周期 initial deploy 第 1 个 pack 传 force_tier=3 保证最强敌人出现
	var tier: int
	if force_tier >= 0:
		tier = force_tier
	else:
		var tier_rows: Array = world_view.get_enemy_tier_ratio_rows()
		tier = _pick_tier_for_cycle(tier_rows, RunState.cycle_index(), rng)

	var pack: LevelSlot = LevelSlot.new()
	pack.position = spawn_pos
	pack.state = LevelSlot.State.UNCHALLENGED
	pack.faction = Faction.ENEMY_1
	pack.difficulty = 0    # M7 MVP：增援不挂轮次难度（cycle 难度通过 tier 体现）
	pack.tier = tier
	pack.troops = generator.generate_troops_for_tier(tier)
	# rewards 保留空数组——被玩家击败仍可发常规奖励（若 MVP 不需要可保空）

	# 注册到 _level_slots
	level_slots[spawn_pos] = pack

	# 更新 MapSchema slot 标记（以便渲染识别为敌方格）
	var original_types: Dictionary = world_view.get_original_slot_types()
	if not original_types.has(spawn_pos):
		original_types[spawn_pos] = schema.get_slot(spawn_pos.x, spawn_pos.y)
	schema.set_slot(spawn_pos.x, spawn_pos.y, MapSchema.SlotType.FUNCTION)

	return pack


# ─────────────────────────────────────────
# 内部工具
# ─────────────────────────────────────────

## P0 第二阶段：按位置查 persistent_slot（不查 owner）
## 替代旧的 _find_enemy_core(查 owner=ENEMY_1)；spawn 锚改为原始位置后无需 owner 过滤
static func _find_slot_at(persistent_slots: Array, pos: Vector2i) -> PersistentSlot:
	for entry in persistent_slots:
		var slot: PersistentSlot = entry as PersistentSlot
		if slot == null:
			continue
		if slot.position == pos:
			return slot
	return null


## P0 第二阶段：按当前 cycle 从 tier_ratio 加权抽 tier
##
## tier_rows 行结构：{cycle_index: int, tier: int, count: int}
## count 即该 (cycle, tier) 组合的权重；累加同 cycle 的 count 得总权重，加权随机选 tier
##
## 兜底：tier_rows 空 / 当前 cycle 无配置 → 返回 tier 0
static func _pick_tier_for_cycle(tier_rows: Array, cycle: int, rng: RandomNumberGenerator) -> int:
	if tier_rows == null or tier_rows.is_empty():
		return 0
	# 收集当前 cycle 的 (tier, count) 列表 + 累加权重
	var entries: Array = []   # 每项为 [tier, cumulative_weight]
	var total_weight: int = 0
	for row_v in tier_rows:
		var row: Dictionary = row_v as Dictionary
		if row == null:
			continue
		if int(row.get("cycle_index", "-1")) != cycle:
			continue
		var count: int = int(row.get("count", "0"))
		if count <= 0:
			continue
		var tier: int = int(row.get("tier", "0"))
		total_weight += count
		entries.append([tier, total_weight])
	if entries.is_empty() or total_weight <= 0:
		return 0
	# 加权随机
	var roll: int
	if rng != null:
		roll = rng.randi_range(1, total_weight)
	else:
		roll = randi_range(1, total_weight)
	for item_v in entries:
		var item: Array = item_v as Array
		if roll <= int(item[1]):
			return int(item[0])
	return 0


## 找给定范围内的可用空地：曼哈顿距离 ≤ range + 可通行 + 无占用
## 占用判定：_level_slots 任意状态 / _resource_slots 未采集 / 玩家单位 / 任意 persistent_slot 位置
## resource_slots 可传空字典（开局前资源点尚未生成时）
static func _find_passable_empty_tiles(
	schema, center: Vector2i, range_val: int,
	level_slots: Dictionary, resource_slots: Dictionary, unit_pos: Vector2i
) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	# 预扫描 persistent_slots 占用的格
	var persistent_occupied: Dictionary = {}
	for entry in schema.persistent_slots:
		var ps: PersistentSlot = entry as PersistentSlot
		if ps != null:
			persistent_occupied[ps.position] = true

	for dy in range(-range_val, range_val + 1):
		var y: int = center.y + dy
		if y < 0 or y >= schema.height:
			continue
		var dx_max: int = range_val - absi(dy)
		for dx in range(-dx_max, dx_max + 1):
			var x: int = center.x + dx
			if x < 0 or x >= schema.width:
				continue
			var pos: Vector2i = Vector2i(x, y)
			# 地形不可通行 → 跳过
			if not schema.is_passable(x, y):
				continue
			# 已被占用 → 跳过
			if level_slots.has(pos):
				continue
			if resource_slots != null and resource_slots.has(pos):
				continue
			if pos == unit_pos:
				continue
			if persistent_occupied.has(pos):
				continue
			result.append(pos)
	return result
