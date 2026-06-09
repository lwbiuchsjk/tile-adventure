class_name MapGenerator
## PCG 地图生成器
## 使用 FastNoiseLite 柏林噪声生成地形分布，并通过 BFS 校验起终点通达性。
## 所有生成参数从外部配置传入（GenerateConfig），不再硬编码常量。

# ─────────────────────────────────────────
# 生成配置（内部类）
# ─────────────────────────────────────────

## PCG 生成参数配置，所有字段由 WorldMap 从 CSV 配置加载后填入
class GenerateConfig:
	## 地图宽度（列数）
	var width: int = 32
	## 地图高度（行数）
	var height: int = 24
	## 随机种子
	var seed: int = 0
	## 通达性校验起点
	var start: Vector2i = Vector2i(1, 1)
	## 通达性校验终点
	var end: Vector2i = Vector2i(30, 22)
	## 通达性校验失败时最大重试次数
	var max_retries: int = 10

	# —— 噪声参数 ——
	## 【L1.3b 阶段 A】地形权威已收敛到 ChunkPCG（全局 noise 场常量），
	## 原 threshold_* / noise_frequency 字段随地形 noise 退役一并删除（codex P1-2 清死配置）；
	## 阈值重新调参化（让 ChunkPCG 接收/缓存地形参数）留议题 12「PCG 内容质量增强」MVP。

	# —— 地形配置（从 terrain_config.csv 加载）——
	## 地形移动力消耗表，BFS 通达性校验时需要此数据判断可通行性
	## 格式：{ TerrainType(int) : float }
	var terrain_costs: Dictionary = {}

	# —— M2 持久 slot 生成参数（从 map_config.csv 加载）——
	## 是否启用持久 slot 生成；MVP 默认开
	var generate_persistent_slots: bool = true
	## 与 PersistentSlotGenerator.GenConfig 字段一一对应
	## P0 X-A 后默认值：1 敌方核心 + 7 城镇（含玩家方占位）+ 18 村庄 = 26
	var persistent_total_count: int = 26
	var persistent_core_count: int = 1
	var persistent_town_count: int = 7
	var persistent_village_count: int = 18
	var persistent_min_dist_normal: int = 3
	var persistent_min_dist_core: int = 5
	var persistent_emerge_steps: int = 3
	var persistent_field_radius: int = 20
	var persistent_core_zone_min: float = 0.125
	var persistent_core_zone_max: float = 0.25
	var persistent_max_retries: int = 5
	## 每方开局归属下限（设计 §3.2 三桶下限；双方共享同一套配置）
	var persistent_faction_town_quota: int = 2
	var persistent_faction_village_quota: int = 6

# ─────────────────────────────────────────
# 公共接口
# ─────────────────────────────────────────

## 生成地图（L1.3b 阶段 A：无限模式）。返回 MapSchema；持久 slot 超出重试返回 null。
##
## L1.3b 阶段 A 改动：
##   - 地形权威收敛 ChunkPCG（缺陷 4）：terrain noise 固定 = config.seed（与 chunk world_seed 同源，
##     保证核心区与流式 chunk 地形一致），【不再随重试 reseed】——地形是确定性的，reseed 会破坏一致性
##   - 全图通达 BFS 退役（缺陷 5）：无界世界无终点、无法全图 BFS；换【局部出生校验】，
##     出生点周围开阔不足则微调出生点（写 schema.spawn_pos），不换 seed
##   - 持久 slot 失败仍可重试：仅换【slot 放置 rng seed】（在同一固定地形上重新撒点），不动地形
static func generate(config: GenerateConfig) -> MapSchema:
	# 地形 = 固定 config.seed 的全局 noise 场（不 reseed）
	var schema: MapSchema = _generate_once(config)

	# 局部出生校验（缺陷 5）：解析可走出生点，写回 schema.spawn_pos 供 MapBootstrap 回读
	schema.spawn_pos = _resolve_spawn(schema, config.start)

	# M2 持久 slot：失败时仅换 slot 放置 rng seed 在同一地形上重撒，不影响地形一致性
	if config.generate_persistent_slots:
		var slot_seed: int = config.seed
		for i in range(config.max_retries):
			if _attach_persistent_slots(schema, config, slot_seed):
				return schema
			slot_seed += 1
			push_warning("MapGenerator: 持久 slot 生成失败，第 %d 次重试（slot_seed=%d，地形不变）" % [i + 1, slot_seed])
		push_error("MapGenerator: 持久 slot 超出最大重试次数（%d），无法生成合规分布" % config.max_retries)
		return null

	return schema


## M2：把 GenerateConfig 中的持久 slot 参数转交给 PersistentSlotGenerator
## 返回 true = 成功（schema.persistent_slots 已填充并通过校验）；false = 失败（调用方应换 seed 重试）
## seed 与地形 seed 同源，保证同 seed 同地图（含 slot 分布）
static func _attach_persistent_slots(
	schema: MapSchema,
	config: GenerateConfig,
	use_seed: int
) -> bool:
	var pcfg: PersistentSlotGenerator.GenConfig = PersistentSlotGenerator.GenConfig.new()
	pcfg.width = config.width
	pcfg.height = config.height
	pcfg.seed = use_seed
	pcfg.total_count = config.persistent_total_count
	pcfg.core_count = config.persistent_core_count
	pcfg.town_count = config.persistent_town_count
	pcfg.village_count = config.persistent_village_count
	pcfg.min_dist_normal = config.persistent_min_dist_normal
	pcfg.min_dist_core = config.persistent_min_dist_core
	pcfg.emerge_steps = config.persistent_emerge_steps
	pcfg.field_radius = config.persistent_field_radius
	pcfg.core_zone_min = config.persistent_core_zone_min
	pcfg.core_zone_max = config.persistent_core_zone_max
	pcfg.max_retries = config.persistent_max_retries
	pcfg.faction_town_quota = config.persistent_faction_town_quota
	pcfg.faction_village_quota = config.persistent_faction_village_quota

	var slots: Array[PersistentSlot] = PersistentSlotGenerator.generate(schema, pcfg)
	# 失败语义：generate() 内部超过 max_retries 时返回空数组
	if slots.is_empty():
		schema.persistent_slots = []
		return false
	schema.persistent_slots = slots
	return true

## 在已生成的地图上随机放置关卡 Slot（FUNCTION 类型）
## schema: 目标地图
## count: 最大放置数量
## exclude: 需要排除的坐标列表（如起点、终点）
## rng:    可选的注入 RNG；传 null 时退化为全局 RNG（保留旧调用兼容，但破坏 seed 复现）
## 返回实际放置的坐标列表
static func place_level_slots(
	schema: MapSchema,
	count: int,
	exclude: Array[Vector2i],
	rng: RandomNumberGenerator = null
) -> Array[Vector2i]:
	# 收集所有可通行且不在排除列表中的格子
	var candidates: Array[Vector2i] = []
	for y in range(schema.height):
		for x in range(schema.width):
			var pos: Vector2i = Vector2i(x, y)
			if exclude.has(pos):
				continue
			# 仅在可通行格上放置
			if not schema.is_passable(x, y):
				continue
			# 已有 Slot 的格子跳过
			if schema.get_slot(x, y) != MapSchema.SlotType.NONE:
				continue
			candidates.append(pos)

	# 随机打乱候选列表
	# 注入 RNG 走 Fisher-Yates 保证 seed 贯穿；未注入则退化全局 RNG（兼容旧调用方）
	if rng != null:
		_shuffle_with_rng(candidates, rng)
	else:
		candidates.shuffle()

	# 取前 count 个，放置 FUNCTION 类型 Slot
	var placed: Array[Vector2i] = []
	var actual_count: int = mini(count, candidates.size())
	for i in range(actual_count):
		var pos: Vector2i = candidates[i]
		schema.set_slot(pos.x, pos.y, MapSchema.SlotType.FUNCTION)
		placed.append(pos)

	return placed

# ─────────────────────────────────────────
# 私有：单次生成
# ─────────────────────────────────────────

## 生成无限模式 schema（地形权威收敛 ChunkPCG，缺陷 4）
## 不预分配 terrain_grid（病根 fix）；地形改由 set_infinite_terrain 注入的全局 noise 场直算；
## terrain noise seed 固定 = config.seed，与 MapBootstrap 的 chunk world_seed 同源
static func _generate_once(config: GenerateConfig) -> MapSchema:
	var schema: MapSchema = MapSchema.new()
	# allocate_terrain=false：无限模式不预分配全图地形数组（slot_grid 仍按核心区分配）
	schema.init(config.width, config.height, false)
	# 地形消耗配置（is_passable / get_terrain_cost 用）
	schema.terrain_costs = config.terrain_costs.duplicate()
	# 注入全局 noise 场：地形按需直算，核心区与流式 chunk 同源一致
	schema.set_infinite_terrain(config.seed)
	return schema

# ─────────────────────────────────────────
# 私有：局部出生校验（L1.3b 阶段 A，替代全图 BFS —— 缺陷 5）
# ─────────────────────────────────────────

## 解析出生点：首选点周围开阔足够则用首选点，否则向外环搜更优可走点（不换 seed）
## 无界世界无"终点"概念，校验从"start→end 全图连通"降级为"出生点周围有足够可走开阔地"
static func _resolve_spawn(
	schema: MapSchema,
	preferred: Vector2i,
	search_radius: int = 12,
	bfs_radius: int = 5,
	min_open: int = 12
) -> Vector2i:
	# 兜底候选：记录搜到的最开阔【可走】点（best_open >= 1 即代表该点可走）
	# 防 codex P1-1：方环搜索失败时不能盲目回退 preferred（可能不可走 → 玩家卡在山地）
	var best_pos: Vector2i = preferred
	var best_open: int = _local_open_count(schema, preferred, bfs_radius)
	if best_open >= min_open:
		return preferred

	# 向外按方环逐圈搜索（曼哈顿环）：优先满足 min_open，同时维护最佳可走兜底
	for r in range(1, search_radius + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				# 仅取当前环边缘格（避免重复扫内圈）
				if abs(dx) != r and abs(dy) != r:
					continue
				var cand: Vector2i = preferred + Vector2i(dx, dy)
				var oc: int = _local_open_count(schema, cand, bfs_radius)
				if oc >= min_open:
					return cand  # 满足开阔要求，直接采用
				if oc > best_open:
					best_open = oc
					best_pos = cand

	# 无满足 min_open 的点：退而求其次用搜到的最开阔【可走】点（保证可走，避免卡死）
	if best_open >= 1:
		push_warning("MapGenerator: 出生点周围开阔不足，降级到最佳可走点 %s（open=%d）" % [str(best_pos), best_open])
		return best_pos

	# 极端：搜索半径内完全无可走格（Perlin 地形下近乎不可能）→ 回退首选点 + 告警
	push_warning("MapGenerator: 出生点 %s 搜索半径内无可走格，回退首选点（请检查地形参数）" % str(preferred))
	return preferred


## 统计 start 周围 radius（切比雪夫）范围内、与 start 连通的可走格数量（有界 BFS）
## start 本身不可走 → 返回 0
static func _local_open_count(schema: MapSchema, start: Vector2i, radius: int) -> int:
	if not schema.is_passable(start.x, start.y):
		return 0

	var visited: Dictionary = {}
	var queue: Array[Vector2i] = [start]
	visited[start] = true
	var count: int = 0

	var directions: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0),
		Vector2i(0, 1), Vector2i(0, -1),
	]

	while queue.size() > 0:
		var current: Vector2i = queue.pop_front()
		count += 1
		for dir in directions:
			var neighbor: Vector2i = current + dir
			if visited.has(neighbor):
				continue
			# 限制在 start 周围 radius 方框内（局部，非全图）
			if abs(neighbor.x - start.x) > radius or abs(neighbor.y - start.y) > radius:
				continue
			if not schema.is_passable(neighbor.x, neighbor.y):
				continue
			visited[neighbor] = true
			queue.append(neighbor)

	return count


# ─────────────────────────────────────────
# 内部工具：注入 RNG 的 Fisher-Yates 洗牌
# ─────────────────────────────────────────

## 与 PersistentSlotGenerator._shuffle_with_rng 等价；保留独立副本避免跨模块依赖
## 用途：place_level_slots 等需要 seed 复现的随机洗牌点
static func _shuffle_with_rng(arr: Array[Vector2i], rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		if j != i:
			var tmp: Vector2i = arr[i]
			arr[i] = arr[j]
			arr[j] = tmp
