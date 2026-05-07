class_name BattleAI
## 战斗内敌方 AI（E 战斗就地展开 MVP §2.6）
##
## 设计原文：tile-advanture-design/探索体验实装/E_战斗就地展开_MVP.md §2.6
##
## 极简贪婪策略：
##   1. 攻击范围内有玩家单位 → 攻击 hp 最低的一个
##   2. 否则朝最近玩家单位移动 N 格（N = 移动力，到达攻击范围即止）
##   3. 路径不通（被卡死 / 战场内无法靠近） → 跳过
##
## 与现有 EnemyAI 区别：
##   EnemyAI 是世界级回合 AI（增援 / 石料 / 升级 / 移动），颗粒度对不上战斗子回合
##   BattleAI 只服务战斗内单单位决策，无状态依赖（纯函数）


# ─────────────────────────────────────
# 决策结果结构
# ─────────────────────────────────────

## 行动类型
enum Action { SKIP = 0, MOVE = 1, ATTACK = 2 }


## 决策入口：根据当前 actor 状态返回行动方案
##
## 返回 Dictionary 结构：
##   {
##     "action": Action,
##     "move_to": Vector2i,        # action == MOVE / ATTACK 时携带（ATTACK 含先移动到该格）；SKIP 时为零
##     "target": BattleUnit,       # action == ATTACK 时为攻击目标；其他时为 null
##   }
##
## 调用方负责：
##   - 调用本函数得到方案
##   - 执行 move（更新 battle_position + actor.has_moved = true）
##   - 执行 attack（计算伤害 + 扣 hp + actor.has_attacked = true）
##
## 参数 occupied_positions 由 BattleSession 维护，含所有在场 BattleUnit 的位置（含 actor 自己）
##   结构注释（无法 typed Dictionary）：Dictionary<Vector2i, BattleUnit>
static func decide(
	actor: BattleUnit,
	enemies: Array[BattleUnit],   # 对 actor 来说的敌方（敌方 actor 的 enemies = 玩家方单位）
	arena: Rect2i,
	schema: MapSchema,
	occupied_positions: Dictionary
) -> Dictionary:
	var alive_enemies: Array[BattleUnit] = _filter_alive(enemies)
	if alive_enemies.is_empty():
		return _make_skip()

	# 1. 攻击范围内是否有目标 → 优先 hp 最低
	var in_range_target: BattleUnit = _find_lowest_hp_in_range(actor, alive_enemies)
	if in_range_target != null:
		return _make_attack(actor.battle_position, in_range_target)

	# 2. 朝最近玩家单位移动
	var nearest: BattleUnit = _find_nearest(actor, alive_enemies)
	if nearest == null:
		return _make_skip()

	var move_to: Vector2i = _plan_move_toward(
		actor, nearest, arena, schema, occupied_positions
	)
	if move_to == actor.battle_position:
		# 没法靠近 → 跳过
		return _make_skip()

	# 移动后再尝试攻击：检查移动后 attack_range 内是否有目标
	var post_move_target: BattleUnit = _find_lowest_hp_in_range_at_pos(
		move_to, actor.attack_range, alive_enemies
	)
	if post_move_target != null:
		return {
			"action": Action.ATTACK,
			"move_to": move_to,
			"target": post_move_target,
		}

	return {
		"action": Action.MOVE,
		"move_to": move_to,
		"target": null,
	}


# ─────────────────────────────────────
# 内部 helper
# ─────────────────────────────────────

## 过滤存活单位（is_active && hp > 0）
static func _filter_alive(units: Array[BattleUnit]) -> Array[BattleUnit]:
	var result: Array[BattleUnit] = []
	for unit in units:
		if unit != null and unit.is_active and unit.is_alive():
			result.append(unit)
	return result


## 当前位置攻击范围内 hp 最低的目标
static func _find_lowest_hp_in_range(actor: BattleUnit, alive_enemies: Array[BattleUnit]) -> BattleUnit:
	return _find_lowest_hp_in_range_at_pos(
		actor.battle_position, actor.attack_range, alive_enemies
	)


## 在指定坐标 + 攻击范围内 hp 最低的目标
static func _find_lowest_hp_in_range_at_pos(
	pos: Vector2i, attack_range: int, alive_enemies: Array[BattleUnit]
) -> BattleUnit:
	var best: BattleUnit = null
	var best_hp: int = -1
	for enemy in alive_enemies:
		var dist: int = _manhattan(pos, enemy.battle_position)
		if dist > attack_range:
			continue
		if best == null or enemy.troop.current_hp < best_hp:
			best = enemy
			best_hp = enemy.troop.current_hp
	return best


## 找最近的目标（曼哈顿距离）
static func _find_nearest(actor: BattleUnit, alive_enemies: Array[BattleUnit]) -> BattleUnit:
	var best: BattleUnit = null
	var best_dist: int = -1
	for enemy in alive_enemies:
		var d: int = _manhattan(actor.battle_position, enemy.battle_position)
		if best == null or d < best_dist:
			best = enemy
			best_dist = d
	return best


## 规划朝目标移动（贪婪 BFS / 简化）
##
## 返回 actor 应该移动到的格坐标。如果无法靠近（路径全被卡），返回 actor 当前位置。
##
## 简化策略：以 actor 为起点 BFS，扩展 ≤ move_range 步；每个可达格记距离 nearest 的曼哈顿距离；
## 取"距 nearest 最近"的可达格作为目标。
##
## occupied_positions 含所有在场 BattleUnit；不能停在被占格（含 actor 自己时跳过自检）
static func _plan_move_toward(
	actor: BattleUnit,
	nearest: BattleUnit,
	arena: Rect2i,
	schema: MapSchema,
	occupied_positions: Dictionary
) -> Vector2i:
	var start: Vector2i = actor.battle_position
	var move_budget: int = actor.move_range
	# BFS：visited[pos] = 已用移动力
	var visited: Dictionary = {}
	visited[start] = 0
	var frontier: Array[Vector2i] = [start]

	while not frontier.is_empty():
		var current: Vector2i = frontier.pop_front()
		var current_cost: int = int(visited[current])
		if current_cost >= move_budget:
			continue
		for offset in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
			var next_pos: Vector2i = current + offset
			if visited.has(next_pos):
				continue
			if not arena.has_point(next_pos):
				continue
			if not schema.is_in_bounds(next_pos.x, next_pos.y):
				continue
			var terrain_cost: float = schema.get_terrain_cost(next_pos.x, next_pos.y)
			if terrain_cost >= INF:
				continue
			# 被占格：除起点（actor 自己）外都不能停
			if occupied_positions.has(next_pos) and next_pos != start:
				continue
			# 移动 cost 复用 MapSchema.terrain_costs（设计 §2.5）；与 BattleSession._bfs_reachable 一致
			var step_cost: int = maxi(1, int(terrain_cost))
			var next_cost: int = current_cost + step_cost
			if next_cost > move_budget:
				continue
			visited[next_pos] = next_cost
			frontier.append(next_pos)

	# 在 visited 中找距 nearest 最近的（且非 start）
	var best_pos: Vector2i = start
	var best_dist: int = _manhattan(start, nearest.battle_position)
	for pos in visited:
		var p: Vector2i = pos as Vector2i
		var d: int = _manhattan(p, nearest.battle_position)
		if d < best_dist:
			best_dist = d
			best_pos = p
	return best_pos


# ─────────────────────────────────────
# 工具
# ─────────────────────────────────────

static func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


static func _make_skip() -> Dictionary:
	return {
		"action": Action.SKIP,
		"move_to": Vector2i.ZERO,
		"target": null,
	}


static func _make_attack(move_to: Vector2i, target: BattleUnit) -> Dictionary:
	return {
		"action": Action.ATTACK,
		"move_to": move_to,
		"target": target,
	}
