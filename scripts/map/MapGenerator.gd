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

	# —— 噪声参数（从 pcg_config.csv 加载）——
	## 高于此值 → 高山
	var threshold_mountain: float = 0.45
	## 高于此值 → 高地
	var threshold_highland: float = 0.15
	## 高于此值 → 平地，低于则 → 洼地
	var threshold_flatland: float = -0.25
	## 噪声频率，越低地形过渡越平滑
	var noise_frequency: float = 0.08

	# —— 地形配置（从 terrain_config.csv 加载）——
	## 地形移动力消耗表，BFS 通达性校验时需要此数据判断可通行性
	## 格式：{ TerrainType(int) : float }
	var terrain_costs: Dictionary = {}

	# —— M2 持久 slot 生成参数（从 map_config.csv 加载）——
	## 是否启用持久 slot 生成；MVP 默认开
	var generate_persistent_slots: bool = true
	## 与 PersistentSlotGenerator.GenConfig 字段一一对应
	var persistent_total_count: int = 26
	var persistent_core_count: int = 2
	var persistent_town_count: int = 6
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

## 生成地图。返回通过通达性 + 持久 slot 校验的 MapSchema；超出重试次数返回 null。
## M2：通达校验后追加持久 slot 八阶段流水线，失败时换 seed 重试整张地图
static func generate(config: GenerateConfig) -> MapSchema:
	var retry_seed: int = config.seed

	for i in range(config.max_retries):
		var schema: MapSchema = _generate_once(config, retry_seed)
		if not _validate_connectivity(schema, config.start, config.end):
			# 通达性校验失败，递增种子后重试
			retry_seed += 1
			push_warning("MapGenerator: 通达性校验失败，第 %d 次重试（seed=%d）" % [i + 1, retry_seed])
			continue

		# M2 接入：持久 slot 生成失败也应换 seed 重试整张地图，避免"无城建锚地图"静默通过
		if config.generate_persistent_slots:
			if not _attach_persistent_slots(schema, config, retry_seed):
				retry_seed += 1
				push_warning("MapGenerator: 持久 slot 生成失败，第 %d 次重试整图（seed=%d）" % [i + 1, retry_seed])
				continue

		return schema

	push_error("MapGenerator: 超出最大重试次数（%d），无法生成合规地图" % config.max_retries)
	return null


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

## 根据给定种子生成一张地图（不含通达性校验）
static func _generate_once(config: GenerateConfig, use_seed: int) -> MapSchema:
	var schema: MapSchema = MapSchema.new()
	schema.init(config.width, config.height)
	# 将地形消耗配置注入 schema，供 BFS 校验时使用
	schema.terrain_costs = config.terrain_costs.duplicate()

	# 初始化柏林噪声
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = use_seed
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.frequency = config.noise_frequency

	# 遍历每格，按噪声值映射地形类型
	for y in range(config.height):
		for x in range(config.width):
			var value: float = noise.get_noise_2d(float(x), float(y))
			var terrain: MapSchema.TerrainType
			if value > config.threshold_mountain:
				terrain = MapSchema.TerrainType.MOUNTAIN
			elif value > config.threshold_highland:
				terrain = MapSchema.TerrainType.HIGHLAND
			elif value > config.threshold_flatland:
				terrain = MapSchema.TerrainType.FLATLAND
			else:
				terrain = MapSchema.TerrainType.LOWLAND
			schema.set_terrain(x, y, terrain)

	return schema

# ─────────────────────────────────────────
# 私有：通达性校验（BFS）
# ─────────────────────────────────────────

## 使用 BFS 验证 start → end 是否存在可通行路径。
## 使用 BFS 而非 A*：通达性校验只需判断连通性，无需最短路，BFS 更简洁高效。
static func _validate_connectivity(schema: MapSchema, start: Vector2i, end: Vector2i) -> bool:
	# 起点或终点本身不可通行，直接失败
	if not schema.is_passable(start.x, start.y):
		return false
	if not schema.is_passable(end.x, end.y):
		return false

	var visited: Dictionary = {}
	var queue: Array[Vector2i] = [start]
	visited[start] = true

	# 四方向邻居（不含斜向）
	var directions: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0),
		Vector2i(0, 1), Vector2i(0, -1),
	]

	while queue.size() > 0:
		var current: Vector2i = queue.pop_front()
		if current == end:
			return true

		for dir in directions:
			var neighbor: Vector2i = current + dir
			if visited.has(neighbor):
				continue
			# 越界格视为不可通行（出界处理）
			if not schema.is_in_bounds(neighbor.x, neighbor.y):
				continue
			if not schema.is_passable(neighbor.x, neighbor.y):
				continue
			visited[neighbor] = true
			queue.append(neighbor)

	return false


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
