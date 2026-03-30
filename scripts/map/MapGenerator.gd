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

# ─────────────────────────────────────────
# 公共接口
# ─────────────────────────────────────────

## 生成地图。返回通过通达性校验的 MapSchema；超出重试次数则返回 null。
static func generate(config: GenerateConfig) -> MapSchema:
	var retry_seed: int = config.seed

	for i in range(config.max_retries):
		var schema: MapSchema = _generate_once(config, retry_seed)
		if _validate_connectivity(schema, config.start, config.end):
			return schema
		# 通达性校验失败，递增种子后重试
		retry_seed += 1
		push_warning("MapGenerator: 通达性校验失败，第 %d 次重试（seed=%d）" % [i + 1, retry_seed])

	push_error("MapGenerator: 超出最大重试次数（%d），无法生成通达地图" % config.max_retries)
	return null

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
