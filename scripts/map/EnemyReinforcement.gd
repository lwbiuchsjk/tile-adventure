class_name EnemyReinforcement
extends RefCounted
## 敌方增援生成（M7）
##
## 设计原文：
##   tile-advanture-design/城建锚实装/M7_敌方AI.md §范围「增援」
##   tile-advanture-design/敌方AI基础行为设计.md §3.2 / §3.3 增援生成规则
##
## 规则（L1.3c 阶段 C 起）：
##   - 触发时机：每 5 敌方回合（由 EnemyAI._step_reinforcement 决定，本类不判断时机）
##   - 位置：玩家视野外暗影环带——视野态 == SHADOW ∧ 距玩家 ∈ [ring_min, ring_max] ∧ 地形可走
##     ∧ 无部队包 / 玩家单位 / 持久 slot 占用的空地（敌人"从黑暗中、从远方"出现）
##   - 数量：单批 1 个 LevelSlot；场上敌方 pack 数 ≥ enemy_pack_global_cap 时停刷
##   - 随机池：复用 enemy_troop_pool.csv（通过 EnemyTroopGenerator.generate_troops）
##
## 静态纯函数；所有状态通过 WorldView facade 读写（MVP-β）

## 无效锚哨兵（L1.3c 阶段 A：出生居中后负坐标合法，不能再用 (-1,-1)/"x<0" 表示无效锚）
const NO_ANCHOR: Vector2i = Vector2i(-2147483648, -2147483648)

## L1.3c 阶段 C：敌方生成参数（全局上限 + 暗影环带半径）
## 用 static var preload（非 const）：调参面板 entry_enemy_spawn 设 realtime=true，
## 面板反射 set 需避开 const 的编译期内联（D5 const cache bug）——static var 直读运行时值，
## 拖动滑块即时影响下一次 spawn_batch（cap / ring 每拍重读，无需重启）
static var SPAWN_CFG: EnemySpawnParamResource = preload("res://assets/config/enemy_spawn_param_resource.tres")


## 生成一批增援并注入 WorldView 暴露的 _level_slots 字典
## world_view: WorldView facade（强类型，访问点编译期可校验 —— MVP-β）
## force_tier: -1（默认）= 按 cycle 加权抽 tier；≥ 0 = 强制使用指定 tier（跳过抽样）
##             climax boss 走 anchor 模式分支时传 force_tier=3 保证最强敌人出现
## 返回：实际 spawn 的 LevelSlot；无合法空地 / 触顶上限 / 配置缺失时返回 null
##
## tier 抽样（整局节奏重设计，威胁数值仍读 cycle 冻结表，递增曲线留 ③ L1.3d）：
##   - tier 按当前 cycle 从 world_view.get_enemy_tier_ratio_rows() 加权抽样（默认路径）
##   - force_tier ≥ 0 时跳过权重抽样直接使用
##
## L1.3a 阶段 C：新增可选 anchor_pos + anchor_range——指定 spawn 锚点（玩家/据点附近），
## 用于 climax boss"防守向·向玩家进军"。anchor_pos 有效（≠ NO_ANCHOR）且 anchor_range > 0 时
## 以锚点 + 半径取空地；否则走默认增援分支。
## L1.3c 阶段 A：锚有效性判定从"x/y ≥ 0"改为哨兵比较——出生居中后负坐标是合法世界坐标。
##
## L1.3c 阶段 C：默认增援分支重写——敌人不再从"缓存的敌核心锚"刷出，而是从
## "玩家视野外暗影环带"采样（视野态 == SHADOW ∧ 距玩家 ∈ [ring_min, ring_max] ∧ 地形可走）。
## 体验：敌人永远从黑暗中、从远方向玩家走来，视野内绝不凭空出怪。另加全局 pack 上限守卫。
## ⚠ 锚语义边界（设计 §五阶段 C ⚠ 块）：两条锚分支语义相反且都保留——
##   - 默认锚分支（本函数 else）：常规增援，"从远方暗影中来"（玩家视野外 SHADOW 环带）；
##   - anchor 模式分支（调用方显式传 anchor_pos/anchor_range，climax boss 用）：boss"向玩家逼近"，
##     锚在玩家/据点附近，本阶段不动。
##   全局 pack 上限只作用于默认锚分支，climax boss（sudden-death 必现强敌）不受限。
static func spawn_batch(world_view: WorldView, force_tier: int = -1, anchor_pos: Vector2i = NO_ANCHOR, anchor_range: int = -1) -> LevelSlot:
	if world_view == null:
		return null

	var schema: MapSchema = world_view.get_schema()
	if schema == null:
		push_warning("EnemyReinforcement.spawn_batch: _schema 未初始化")
		return null

	var level_slots: Dictionary = world_view.get_level_slots()
	var resource_slots: Dictionary = world_view.get_resource_slots()
	var unit: UnitData = world_view.get_unit()
	# 占位哨兵用 NO_ANCHOR（codex P2 修复）：负坐标合法后 (-1,-1) 是真实世界格，会误判占用
	var unit_pos: Vector2i = unit.position if unit != null else NO_ANCHOR

	# 候选空地收集：锚点模式（climax）走菱形邻域；默认模式走玩家视野外暗影环带
	var candidates: Array[Vector2i]
	if anchor_pos != NO_ANCHOR and anchor_range > 0:
		# L1.3a/L1.3c：anchor 模式分支（climax boss 向玩家逼近）——不受全局上限约束、不走暗影环带
		candidates = _find_passable_empty_tiles(
			schema, anchor_pos, anchor_range,
			level_slots, resource_slots, unit_pos
		)
	else:
		# L1.3c 阶段 C：默认增援分支——玩家视野外暗影环带采样
		# 全局 pack 上限守卫（仅本分支；触顶停刷，敌人数量不无限膨胀）
		if _count_enemy_packs(level_slots) >= SPAWN_CFG.enemy_pack_global_cap:
			return null
		# 无玩家单位时无法定位环带（理论上不应发生）——静默跳过本拍
		if unit == null:
			return null
		candidates = _find_shadow_ring_tiles(
			world_view, schema, unit.position,
			SPAWN_CFG.enemy_spawn_ring_min, SPAWN_CFG.enemy_spawn_ring_max,
			level_slots, resource_slots
		)

	if candidates.is_empty():
		# 暗影环带暂无合法格（视野全亮 / 被占满）是常态，静默跳过本拍，不刷 warning
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

## L1.3c 阶段 C：统计场上敌方 pack 数（全局上限守卫用）
## 仅计 _level_slots 中 faction == ENEMY_1 的 LevelSlot；climax boss 也计入（仅占 1，不影响语义）
static func _count_enemy_packs(level_slots: Dictionary) -> int:
	var n: int = 0
	for slot_v in level_slots.values():
		var slot: LevelSlot = slot_v as LevelSlot
		if slot != null and slot.faction == Faction.ENEMY_1:
			n += 1
	return n


## L1.3c 阶段 C：玩家视野外暗影环带候选格收集
## 条件全满足才入选：曼哈顿距玩家 ∈ [ring_min, ring_max] ∧ 视野态 == SHADOW（玩家不可见）
##   ∧ 地形可走（schema.is_passable 路由 ChunkPCG 纯函数直算，不触发 chunk 加载）∧ 无占用
## 体验保证：敌人只从玩家看不见的远方暗影中刷出，视野内永不凭空出怪
static func _find_shadow_ring_tiles(
	world_view: WorldView, schema, player_pos: Vector2i,
	ring_min: int, ring_max: int,
	level_slots: Dictionary, resource_slots: Dictionary
) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	# 预扫描 persistent_slots 占用的格
	var persistent_occupied: Dictionary = {}
	for entry in schema.persistent_slots:
		var ps: PersistentSlot = entry as PersistentSlot
		if ps != null:
			persistent_occupied[ps.position] = true

	# 曼哈顿环带枚举：外圈用 ring_max 限定行/列范围，内圈用 ring_min 剔除近身格
	for dy in range(-ring_max, ring_max + 1):
		var dx_max: int = ring_max - absi(dy)
		if dx_max < 0:
			continue
		for dx in range(-dx_max, dx_max + 1):
			var dist: int = absi(dx) + absi(dy)
			if dist < ring_min:
				continue   # 环带内圈：距玩家太近（视野内/边缘），跳过
			var pos: Vector2i = Vector2i(player_pos.x + dx, player_pos.y + dy)
			# 地形不可通行 → 跳过（无限模式路由 ChunkPCG 任意坐标可查）
			if not schema.is_passable(pos.x, pos.y):
				continue
			# 必须落在暗影（玩家不可见）—— "从黑暗中出现"的体验红线
			if not world_view.is_tile_shadow(pos):
				continue
			# 占用判定：_level_slots 任意状态 / _resource_slots / persistent_slot
			if level_slots.has(pos):
				continue
			if resource_slots != null and resource_slots.has(pos):
				continue
			if persistent_occupied.has(pos):
				continue
			result.append(pos)
	return result


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

	# L1.3c 阶段 A：width/height 有界过滤退役——无界世界负坐标合法，
	# 可走性由 schema.is_passable 唯一裁决（无限模式路由 ChunkPCG 任意坐标可查）
	for dy in range(-range_val, range_val + 1):
		var y: int = center.y + dy
		var dx_max: int = range_val - absi(dy)
		for dx in range(-dx_max, dx_max + 1):
			var x: int = center.x + dx
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
