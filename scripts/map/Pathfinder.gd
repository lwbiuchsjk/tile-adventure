class_name Pathfinder
## A* 寻路算法
## 基于 MapSchema 的地形消耗计算最短路径。
## 支持通过 unit_cost_override 接入单位维度的地形加成/减益。

# ─────────────────────────────────────────
# 寻路结果
# ─────────────────────────────────────────

## 寻路结果数据
class PathResult:
	## 路径坐标序列（含起点和终点），无路径时为空数组
	var path: Array[Vector2i] = []
	## 路径总移动力消耗
	var total_cost: float = 0.0

# ─────────────────────────────────────────
# 公共接口
# ─────────────────────────────────────────

## 计算从 start 到 end 的最短路径。
## 返回 PathResult，无路径时 path 为空。
## unit_cost_override: 单位专属地形消耗表（可选）
## blocked_positions: 额外阻挡位置集合 {Vector2i: any}（可选，如击退关卡）
## max_explore: 最大 finalize（唯一）节点数（L1.3b 阶段 C 无界世界安全阀）——目标不可达时防
##   A* 在无界可走空间无限搜索而卡死；超限返回空路径（视作无路）。配 closed set 后只计唯一节点，
##   合法可达目标 finalize 的节点数 ≤ 其可达集大小（受 movement 预算约束），远低于此上界不触发。
##   默认 4096：给高 movement 单位的可达集留足余量，不误伤合法路径（早期 2048 + 缺 closed set
##   时重复弹出虚高计数曾误判远目标不可达 →"可达高亮却走不过去"，已随 closed set 修复）。
static func find_path(schema: MapSchema, start: Vector2i, end: Vector2i, unit_cost_override: Dictionary = {}, blocked_positions: Dictionary = {}, max_explore: int = 4096) -> PathResult:
	var result: PathResult = PathResult.new()

	# 起终点合法性检查
	# 【L1.3b 阶段 C】is_in_bounds 退役：无界世界起终点可在任意坐标，可走性由地形（noise）决定
	if not schema.is_passable(end.x, end.y):
		return result
	if start == end:
		result.path = [start]
		result.total_cost = 0.0
		return result

	# A* 数据结构
	var open_set: Array = []         ## 待探索节点 [{pos: Vector2i, f: float}]
	var g_scores: Dictionary = {}    ## 各节点的实际代价 {Vector2i: float}
	var came_from: Dictionary = {}   ## 路径回溯 {Vector2i: Vector2i}

	g_scores[start] = 0.0
	open_set.append({"pos": start, "f": _heuristic(start, end)})

	var directions: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0),
		Vector2i(0, 1), Vector2i(0, -1),
	]

	# 【L1.3b 阶段 C】closed set：标记已 finalize 的唯一节点
	# 不变量：本 closed set「首次 finalize 即最优」依赖曼哈顿启发式一致性 = 地形 cost ≥ 1（当前成立）。
	#   若未来 unit_cost_override 引入 < 1 的可通行 cost，须按最小步进 cost 缩放 heuristic，否则破坏最短路（codex P2）。
	# 本 A* 无 decrease-key，同一节点可多次入队；缺此守卫时重复弹出会被反复展开 +
	# 被安全阀按"弹出次数"虚高计数，开阔无界地形下远目标会误撞 max_explore 判不可达
	# →"可达高亮却走不过去"（与 MovementSystem.get_reachable_tiles 的 visited 守卫对齐）
	var closed: Dictionary = {}
	# 无界世界安全阀：finalize 的唯一节点数超上界视作不可达，返回空路径
	var explored: int = 0

	while open_set.size() > 0:
		# 取 f 值最小的节点（简易优先队列）
		var best_idx: int = _find_best(open_set)
		var current: Vector2i = open_set[best_idx]["pos"] as Vector2i
		open_set.remove_at(best_idx)

		# 跳过已 finalize 的重复入队项（不重复展开、不计入安全阀）
		if closed.has(current):
			continue
		closed[current] = true

		# 安全阀：每 finalize 一个唯一节点 +1，超上界判定不可达（防无界世界目标不可达时无限搜索）
		explored += 1
		if explored > max_explore:
			push_warning("Pathfinder: finalize 节点超上界 %d，判定 %s→%s 不可达" % [max_explore, str(start), str(end)])
			return result

		# 到达终点，回溯路径
		if current == end:
			result.path = _reconstruct_path(came_from, current)
			result.total_cost = g_scores[current] as float
			return result

		# 展开四方向邻居
		for dir in directions:
			var neighbor: Vector2i = current + dir

			# 【L1.3b 阶段 C】is_in_bounds 退役：邻居可在任意坐标，可走性由地形 cost 决定（下方 INF 跳过）
			# 额外阻挡位置检查（如击退状态的关卡）
			if blocked_positions.has(neighbor):
				continue

			var move_cost: float = schema.get_terrain_cost(neighbor.x, neighbor.y, unit_cost_override)
			if move_cost >= INF:
				continue

			var tentative_g: float = (g_scores[current] as float) + move_cost
			var existing_g: float = g_scores.get(neighbor, INF) as float

			if tentative_g < existing_g:
				# 发现更优路径
				came_from[neighbor] = current
				g_scores[neighbor] = tentative_g
				open_set.append({"pos": neighbor, "f": tentative_g + _heuristic(neighbor, end)})

	# 无通路
	return result

# ─────────────────────────────────────────
# 私有工具
# ─────────────────────────────────────────

## 启发式函数：曼哈顿距离（四方向移动）
static func _heuristic(a: Vector2i, b: Vector2i) -> float:
	return float(absi(a.x - b.x) + absi(a.y - b.y))

## 在 open_set 中找到 f 值最小的节点索引
static func _find_best(open_set: Array) -> int:
	var best_idx: int = 0
	var best_f: float = open_set[0]["f"] as float
	for i in range(1, open_set.size()):
		var f: float = open_set[i]["f"] as float
		if f < best_f:
			best_f = f
			best_idx = i
	return best_idx

## 从 came_from 回溯重建完整路径（含起点和终点）
static func _reconstruct_path(came_from: Dictionary, current: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = [current]
	while came_from.has(current):
		current = came_from[current] as Vector2i
		path.push_front(current)
	return path
