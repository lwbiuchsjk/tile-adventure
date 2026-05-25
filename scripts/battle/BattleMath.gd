class_name BattleMath
## 战斗几何 + 数值（无状态静态类，从 BattleSession 抽出，MVP-ε G2-6）
##
## 设计原文：tile-advanture-design/代码健康度回看/MVP-ε_规范扫尾批.md §核心概念 / 2
##
## 职责：BFS 可达格 / 攻击伤害 / 曼哈顿距离这组纯函数的静态化


## BFS 计算当前 actor 的可达格
##
## 移动 cost 规则（设计 E MVP §2.5）：复用 `MapSchema.terrain_costs`
##   - MOUNTAIN cost = INF（不可通行 / 已被 can_deploy_at 类似逻辑过滤）
##   - HIGHLAND / LOWLAND cost = 2（高地、洼地两倍消耗）
##   - FLATLAND cost = 1
##   move_range 视为整数 budget，BFS 累加 int(get_terrain_cost) 比较
##   注：BattleAI._plan_move_toward 同样按这套规则计算，保持玩家高亮 / AI 决策一致
##
## 参数：
##   actor    —— 当前行动单位
##   arena    —— 战场 Rect2i
##   schema   —— 地图 schema（查地形 cost / 边界）
##   occupied —— 全局占位字典（actor 自身位置允许出现在内）
##
## 返回除起点外的所有可达格
static func bfs_reachable(
	actor: BattleUnit, arena: Rect2i, schema: MapSchema, occupied: Dictionary
) -> Array[Vector2i]:
	var visited: Dictionary = {}
	visited[actor.battle_position] = 0
	var frontier: Array[Vector2i] = [actor.battle_position]
	var move_budget: int = actor.move_range
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
			if occupied.has(next_pos) and next_pos != actor.battle_position:
				continue
			# 累加地形 cost（int 化避免浮点累积误差）
			var step_cost: int = maxi(1, int(terrain_cost))
			var next_cost: int = current_cost + step_cost
			if next_cost > move_budget:
				continue
			visited[next_pos] = next_cost
			frontier.append(next_pos)
	# 返回除起点外的所有可达格（actor 可以"留在原位"由 skip / 不点击表达，不需要列入可达）
	var result: Array[Vector2i] = []
	for pos in visited:
		var p: Vector2i = pos as Vector2i
		if p != actor.battle_position:
			result.append(p)
	return result


## 攻击伤害计算：地形高度差 + BattleResolver 复用
##
## 参数：
##   attacker / target  —— 攻击双方 BattleUnit
##   schema             —— 地图 schema（查地形高度）
##   altitude_step      —— 地形高度差伤害修正系数
##   battle_config      —— 伤害公式参数
##   difficulty         —— 关卡难度（与 BattleResolver.resolve 同语义）
##   damage_increment   —— 难度递增伤害
static func calc_attack_damage(
	attacker: BattleUnit, target: BattleUnit,
	schema: MapSchema, altitude_step: float,
	battle_config: BattleParamResource, difficulty: int, damage_increment: float
) -> int:
	var attacker_alt: int = schema.get_terrain_altitude(
		attacker.battle_position.x, attacker.battle_position.y
	)
	var target_alt: int = schema.get_terrain_altitude(
		target.battle_position.x, target.battle_position.y
	)
	var altitude_diff: int = attacker_alt - target_alt
	return BattleResolver.calculate_single_attack(
		attacker.troop, target.troop,
		altitude_diff, altitude_step,
		battle_config, difficulty, damage_increment,
		attacker.owner_faction
	)


## 曼哈顿距离
static func manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)
