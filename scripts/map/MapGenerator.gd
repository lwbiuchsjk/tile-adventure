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
	## 出生点首选坐标（L1.3c 阶段 A：出生居中，默认世界原点；_resolve_spawn 做局部可走校验微调）
	## 注：原"通达性校验终点 end"字段已删——L1.3b 全图 BFS 退役后即死字段
	var start: Vector2i = Vector2i(0, 0)
	## 局部出生校验失败时最大重试次数（沿用旧语义；撒点生成器确定性，不参与重试）
	var max_retries: int = 10

	# —— 噪声参数 ——
	## 【L1.3b 阶段 A】地形权威已收敛到 ChunkPCG（全局 noise 场常量），
	## 原 threshold_* / noise_frequency 字段随地形 noise 退役一并删除（codex P1-2 清死配置）；
	## 阈值重新调参化（让 ChunkPCG 接收/缓存地形参数）留议题 12「PCG 内容质量增强」MVP。

	# —— 地形配置（从 terrain_config.csv 加载）——
	## 地形移动力消耗表，BFS 通达性校验时需要此数据判断可通行性
	## 格式：{ TerrainType(int) : float }
	var terrain_costs: Dictionary = {}

	# —— 持久 slot 生成参数（L1.3c 阶段 A：网格抖动撒点，来自 content_config.tres）——
	## 是否启用持久 slot 生成；MVP 默认开
	var generate_persistent_slots: bool = true
	## 与 PersistentSlotGenerator.GenConfig 撒点参数一一对应（结构性参数：改 = 换内容分布）
	## 旧八阶段流水线参数（对角区 / 染色 / 涌现 / 三桶下限等 13 键）随生成器重写退役
	var persistent_cell_size: int = 5
	var persistent_slot_spawn_rate: float = 0.85
	var persistent_town_ratio: float = 0.27

# ─────────────────────────────────────────
# 公共接口
# ─────────────────────────────────────────

## 生成地图（L1.3b 阶段 A 无限模式 + L1.3c 阶段 A 出生居中撒点）。
## 返回 MapSchema；锚点放置失败（出生区无可走格，近乎不可能）返回 null。
##
## L1.3b 阶段 A 改动（保留）：
##   - 地形权威收敛 ChunkPCG（缺陷 4）：terrain noise 固定 = config.seed，不 reseed
##   - 全图通达 BFS 退役（缺陷 5）：换【局部出生校验】微调出生点（写 schema.spawn_pos）
## L1.3c 阶段 A 改动：
##   - 出生居中：config.start 默认世界原点，内容区域以解析后的出生点为中心
##   - 撒点确定性：网格抖动撒点是 (seed, cell) 纯函数，无"换 seed 重试"语义——
##     旧重试循环退役（生成失败仅剩配置非法 / 锚点无可走格两种 fatal，重试无意义）
static func generate(config: GenerateConfig) -> MapSchema:
	# 地形 = 固定 config.seed 的全局 noise 场（不 reseed）
	var schema: MapSchema = _generate_once(config)

	# 局部出生校验（缺陷 5）：解析可走出生点，写回 schema.spawn_pos 供 MapBootstrap 回读
	schema.spawn_pos = _resolve_spawn(schema, config.start)

	# 持久 slot：以出生点为中心的网格抖动撒点（确定性，不重试）
	if config.generate_persistent_slots:
		if not _attach_persistent_slots(schema, config):
			push_error("MapGenerator: 持久 slot 撒点失败（配置非法或出生区无可走格）")
			return null

	return schema


## 把 GenerateConfig 中的撒点参数转交给 PersistentSlotGenerator（L1.3c 阶段 A）
## 内容区域以 schema.spawn_pos 为中心（出生居中后内容围绕实际出生点对称）
## 返回 true = 成功（schema.persistent_slots 已填充）；false = fatal 失败
static func _attach_persistent_slots(
	schema: MapSchema,
	config: GenerateConfig
) -> bool:
	var pcfg: PersistentSlotGenerator.GenConfig = PersistentSlotGenerator.GenConfig.new()
	pcfg.seed = config.seed
	pcfg.region_center = schema.spawn_pos
	pcfg.region_width = config.width
	pcfg.region_height = config.height
	pcfg.cell_size = config.persistent_cell_size
	pcfg.slot_spawn_rate = config.persistent_slot_spawn_rate
	pcfg.town_ratio = config.persistent_town_ratio

	var slots: Array[PersistentSlot] = PersistentSlotGenerator.generate(schema, pcfg)
	# 失败语义：配置非法 / 锚点放置失败时返回空数组
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
	# allocate_terrain=false：无限模式不预分配全图地形数组（阶段 D 起 _slots 也改稀疏 dict 不预分配）
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
