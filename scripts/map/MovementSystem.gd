class_name MovementSystem
## 移动系统
## 提供两个核心能力：
##   1. 可达范围查询（Dijkstra 扩散）：给定位置和剩余移动力，算出所有可达格
##   2. 执行移动：沿路径逐格扣除移动力，移动力不足时截断

# ─────────────────────────────────────────
# 公共接口
# ─────────────────────────────────────────

## 计算从 position 出发、在 movement 移动力预算内可到达的所有格子。
## 返回字典 {Vector2i: float}，值为到达该格的最小消耗。
## unit_cost_override: 单位专属地形消耗表（可选）
static func get_reachable_tiles(schema: MapSchema, position: Vector2i, movement: float, unit_cost_override: Dictionary = {}) -> Dictionary:
	var reachable: Dictionary = {}
	var visited: Dictionary = {}
	# 简易优先队列：[{pos: Vector2i, cost: float}]
	var queue: Array = [{"pos": position, "cost": 0.0}]
	reachable[position] = 0.0

	var directions: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0),
		Vector2i(0, 1), Vector2i(0, -1),
	]

	while queue.size() > 0:
		# 取消耗最小的节点
		var best_idx: int = _find_min_cost(queue)
		var current: Vector2i = queue[best_idx]["pos"] as Vector2i
		var current_cost: float = queue[best_idx]["cost"] as float
		queue.remove_at(best_idx)

		# 已访问则跳过（可能存在重复入队）
		if visited.has(current):
			continue
		visited[current] = true

		# 展开四方向邻居
		for dir in directions:
			var neighbor: Vector2i = current + dir

			if visited.has(neighbor):
				continue
			if not schema.is_in_bounds(neighbor.x, neighbor.y):
				continue

			var move_cost: float = schema.get_terrain_cost(neighbor.x, neighbor.y, unit_cost_override)
			if move_cost >= INF:
				continue

			var new_cost: float = current_cost + move_cost
			# 超出移动力预算，不可达
			if new_cost > movement:
				continue

			# 更新更优消耗
			var existing_cost: float = reachable.get(neighbor, INF) as float
			if new_cost < existing_cost:
				reachable[neighbor] = new_cost
				queue.append({"pos": neighbor, "cost": new_cost})

	return reachable

## 沿路径执行移动，逐格扣除移动力。
## 移动力不足时在当前格停止（不会透支）。
## 返回单位实际到达的位置。
static func execute_move(unit: UnitData, path: Array[Vector2i], schema: MapSchema) -> Vector2i:
	if path.size() < 2:
		return unit.position

	# path[0] 为当前位置，从 path[1] 开始逐格移动
	for i in range(1, path.size()):
		var next: Vector2i = path[i]
		var cost: int = int(schema.get_terrain_cost(next.x, next.y))

		# 剩余移动力不足以进入下一格
		if cost > unit.current_movement:
			break

		unit.current_movement -= cost
		unit.position = next

	return unit.position

# ─────────────────────────────────────────
# 私有工具
# ─────────────────────────────────────────

## 在队列中找到消耗最小的节点索引
static func _find_min_cost(queue: Array) -> int:
	var best_idx: int = 0
	var best_cost: float = queue[0]["cost"] as float
	for i in range(1, queue.size()):
		var cost: float = queue[i]["cost"] as float
		if cost < best_cost:
			best_cost = cost
			best_idx = i
	return best_idx
