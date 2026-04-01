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
static func find_path(schema: MapSchema, start: Vector2i, end: Vector2i, unit_cost_override: Dictionary = {}, blocked_positions: Dictionary = {}) -> PathResult:
	var result: PathResult = PathResult.new()

	# 起终点合法性检查
	if not schema.is_in_bounds(start.x, start.y):
		return result
	if not schema.is_in_bounds(end.x, end.y):
		return result
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

	while open_set.size() > 0:
		# 取 f 值最小的节点（简易优先队列）
		var best_idx: int = _find_best(open_set)
		var current: Vector2i = open_set[best_idx]["pos"] as Vector2i
		open_set.remove_at(best_idx)

		# 到达终点，回溯路径
		if current == end:
			result.path = _reconstruct_path(came_from, current)
			result.total_cost = g_scores[current] as float
			return result

		# 展开四方向邻居
		for dir in directions:
			var neighbor: Vector2i = current + dir

			if not schema.is_in_bounds(neighbor.x, neighbor.y):
				continue
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
