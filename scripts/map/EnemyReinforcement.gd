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
## 静态纯函数；所有状态通过 WorldMap 引用读写


## 生成一批增援并注入 WorldMap 的 _level_slots 字典
## world_map: WorldMap 实例（强类型；重命名字段时编译期可报错 —— P2 审查项）
## 为兼容测试注入自定义 mock，接受 Object 类型（WorldMap 也是 Object）；
## 运行时仍可用 get()/属性访问来保持对 mock 的鸭类型友好
## 返回：实际 spawn 的 LevelSlot；未找到空地 / 配置缺失时返回 null
static func spawn_batch(world_map: Object) -> LevelSlot:
	if world_map == null:
		return null

	var schema = world_map.get("_schema")
	if schema == null:
		push_warning("EnemyReinforcement.spawn_batch: _schema 未初始化")
		return null

	# 找敌方核心 persistent slot
	var enemy_core: PersistentSlot = _find_enemy_core(schema.persistent_slots)
	if enemy_core == null:
		push_warning("EnemyReinforcement.spawn_batch: 未找到敌方核心城镇 slot")
		return null

	# 收集敌方核心影响范围内的可用空地
	var level_slots: Dictionary = world_map.get("_level_slots") as Dictionary
	var resource_slots_raw = world_map.get("_resource_slots")
	var resource_slots: Dictionary = resource_slots_raw if resource_slots_raw != null else {}
	var unit = world_map.get("_unit")
	var unit_pos: Vector2i = unit.position if unit != null else Vector2i(-1, -1)

	var candidates: Array[Vector2i] = _find_passable_empty_tiles(
		schema, enemy_core.position, enemy_core.influence_range,
		level_slots, resource_slots, unit_pos
	)
	if candidates.is_empty():
		push_warning("EnemyReinforcement.spawn_batch: 核心影响范围内无空地，跳过本次")
		return null

	# 随机选一格
	var rng = world_map.get("_world_rng")
	var idx: int = 0
	if rng != null:
		idx = rng.randi_range(0, candidates.size() - 1)
	else:
		idx = randi_range(0, candidates.size() - 1)
	var spawn_pos: Vector2i = candidates[idx]

	# 生成部队数据
	var generator = world_map.get("_enemy_generator")
	if generator == null:
		push_warning("EnemyReinforcement.spawn_batch: EnemyTroopGenerator 未初始化")
		return null

	var pack: LevelSlot = LevelSlot.new()
	pack.position = spawn_pos
	pack.state = LevelSlot.State.UNCHALLENGED
	pack.faction = Faction.ENEMY_1
	pack.difficulty = 0    # M7 MVP：增援不挂轮次难度
	pack.tier = 0
	pack.troops = generator.generate_troops()
	# rewards 保留空数组——被玩家击败仍可发常规奖励（若 MVP 不需要可保空）

	# 注册到 _level_slots
	level_slots[spawn_pos] = pack

	# 更新 MapSchema slot 标记（以便渲染识别为敌方格）
	var original_types: Dictionary = world_map.get("_original_slot_types") as Dictionary
	if not original_types.has(spawn_pos):
		original_types[spawn_pos] = schema.get_slot(spawn_pos.x, spawn_pos.y)
	schema.set_slot(spawn_pos.x, spawn_pos.y, MapSchema.SlotType.FUNCTION)

	return pack


# ─────────────────────────────────────────
# 内部工具
# ─────────────────────────────────────────

## 从 persistent_slots 里找敌方核心城镇
static func _find_enemy_core(persistent_slots: Array) -> PersistentSlot:
	for entry in persistent_slots:
		var slot: PersistentSlot = entry as PersistentSlot
		if slot == null:
			continue
		if slot.type == PersistentSlot.Type.CORE_TOWN and slot.owner_faction == Faction.ENEMY_1:
			return slot
	return null


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
