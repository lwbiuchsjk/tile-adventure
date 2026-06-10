class_name BattleDeploy
## 战斗部署 + 几何辅助（无状态静态类，从 BattleSession 抽出，MVP-ε G2-6）
##
## 设计原文：tile-advanture-design/代码健康度回看/MVP-ε_规范扫尾批.md §核心概念 / 2
##
## 职责：把"部署位查找 / 队员展开 / 敌方展开 / 占位字典构造"这组纯函数从
##       BattleSession 抽出，BattleSession 仅保留状态机 + 主流程编排
##
## 调用约定：
##   - 所有函数都是 static，无内部状态
##   - deploy_* 系列接收 occupied 字典作引用并 mutate（与原代码语义一致）
##   - 返回值为 Dictionary：{ "units": Array[BattleUnit], "inactive": Array }


## 哨兵值：表示"找不到展开位"（旧 BattleSession._NO_DEPLOY_SLOT，G2-6 迁入时去 `_` 前缀）
const NO_DEPLOY_SLOT: Vector2i = Vector2i(-9999, -9999)


## 计算战场 Rect2i：玩家中心 ±arena_range（E MVP §2.1 / L1.3b 阶段 E）
## 【L1.3b 阶段 E】无限模式：无世界边界，arena = 原始 ±range 矩形不裁剪（缺陷6）；
## 有限模式（JSON）：仍与地图矩形做交集，保 JSON 地图战场行为不变
static func compute_arena(center: Vector2i, arena_range: int, schema: MapSchema) -> Rect2i:
	var raw: Rect2i = Rect2i(
		center.x - arena_range, center.y - arena_range,
		arena_range * 2 + 1, arena_range * 2 + 1
	)
	if schema != null and schema.is_infinite():
		return raw
	var map_rect: Rect2i = Rect2i(0, 0, schema.width, schema.height)
	# Rect2i.intersection 在 Godot 4 中可用，返回交集
	return raw.intersection(map_rect)


## 玩家方展开：队长留原位，队员按 4邻 → 8邻 找空位
##
## 副作用：mutate occupied 字典（写入新部署单位的位置）
##
## 返回 { "units": Array[BattleUnit], "inactive": Array[CharacterData] }
##   units    —— 成功展开的玩家方单位（队长 [0] + 找到位置的队员）
##   inactive —— 找不到展开位的队员（CharacterData 保留待后续）
static func deploy_player_side(
	characters: Array[CharacterData],
	player_pos: Vector2i,
	arena: Rect2i,
	schema: MapSchema,
	unit_config: Dictionary,
	occupied: Dictionary
) -> Dictionary:
	var units: Array[BattleUnit] = []
	var inactive: Array[CharacterData] = []
	if characters.is_empty():
		return {"units": units, "inactive": inactive}

	# 队长（[0]）
	var leader_char: CharacterData = characters[0]
	if leader_char != null and leader_char.has_troop():
		var leader_unit: BattleUnit = make_player_unit(leader_char, player_pos, unit_config)
		units.append(leader_unit)
		occupied[player_pos] = leader_unit
	else:
		push_warning("BattleDeploy.deploy_player_side: 队长无部队，玩家方未展开任何单位")
		return {"units": units, "inactive": inactive}

	# 队员（[1..]）
	for i in range(1, characters.size()):
		var ch: CharacterData = characters[i]
		if ch == null or not ch.has_troop():
			continue
		var slot: Vector2i = find_deploy_slot(player_pos, occupied, 2, arena, schema)
		if not is_valid_slot(slot, occupied, arena, schema):
			push_warning("BattleDeploy: 队员 %s 找不到展开位，标记未上场" % ch.id)
			inactive.append(ch)
			continue
		var unit: BattleUnit = make_player_unit(ch, slot, unit_config)
		unit.is_active = true
		units.append(unit)
		occupied[slot] = unit

	return {"units": units, "inactive": inactive}


## 敌方 LevelSlot 展开：首 troop 留原格 + 其余 4邻→8邻→16邻 找空位
##
## 副作用：mutate occupied 字典
##
## 返回 { "units": Array[BattleUnit], "inactive": Array[TroopData] }
##   units    —— 成功展开的敌方单位
##   inactive —— 找不到展开位的 TroopData
static func deploy_enemy_pack(
	pack: LevelSlot,
	arena: Rect2i,
	schema: MapSchema,
	unit_config: Dictionary,
	occupied: Dictionary
) -> Dictionary:
	var units: Array[BattleUnit] = []
	var inactive: Array[TroopData] = []
	if pack == null or pack.troops.is_empty():
		return {"units": units, "inactive": inactive}

	var pack_pos: Vector2i = pack.position

	# 首 troop
	var first_troop: TroopData = pack.troops[0]
	var first_pos: Vector2i = pack_pos
	if not can_deploy_at(first_pos, occupied, arena, schema):
		# 极端：原格已被占（例如另一 LevelSlot 同位 / 玩家展开占了 —— 理论极少）
		first_pos = find_deploy_slot(pack_pos, occupied, 2, arena, schema)
	if is_valid_slot(first_pos, occupied, arena, schema):
		var first_unit: BattleUnit = make_enemy_unit(first_troop, pack, first_pos, unit_config)
		units.append(first_unit)
		occupied[first_pos] = first_unit
	else:
		push_warning("BattleDeploy: pack %s 首 troop 找不到展开位，标记未上场" % pack_pos)
		inactive.append(first_troop)

	# 其余 troops
	for i in range(1, pack.troops.size()):
		var troop: TroopData = pack.troops[i]
		var slot: Vector2i = find_deploy_slot(pack_pos, occupied, 4, arena, schema)
		if not is_valid_slot(slot, occupied, arena, schema):
			push_warning("BattleDeploy: pack %s 第 %d 个 troop 找不到展开位，标记未上场" % [pack_pos, i])
			inactive.append(troop)
			continue
		var unit: BattleUnit = make_enemy_unit(troop, pack, slot, unit_config)
		units.append(unit)
		occupied[slot] = unit

	return {"units": units, "inactive": inactive}


## 构造玩家方 BattleUnit：装配 troop_type 对应的 move_range / attack_range
static func make_player_unit(ch: CharacterData, grid_pos: Vector2i, unit_config: Dictionary) -> BattleUnit:
	var unit: BattleUnit = BattleUnit.new()
	unit.owner_faction = Faction.PLAYER
	unit.troop = ch.troop
	unit.character = ch
	unit.battle_position = grid_pos
	_apply_unit_config(unit, unit_config)
	return unit


## 构造援军 BattleUnit（持久slot援军_MVP / L1.2；敌方援军_MVP / L1.4 阵营化）
## character=null（非角色单位）、source_level=null（不挂 pack）；troop 为入场新建实例（满血）
## 与 make_player_unit 的区别：无 CharacterData，由 troop 直接驱动 move/attack 范围装配
## faction：玩家援军传 PLAYER（默认，不破坏 L1.2 调用）；敌方援军传 ENEMY_1（注入 enemy_units，由 BattleAI 驱动）
static func make_reinforcement_unit(troop: TroopData, grid_pos: Vector2i, unit_config: Dictionary,
		faction: int = Faction.PLAYER) -> BattleUnit:
	var unit: BattleUnit = BattleUnit.new()
	unit.owner_faction = faction
	unit.troop = troop
	unit.character = null
	unit.source_level = null          # 援军不挂 pack（双方一致；敌方援军不进 _level_slots，不计周期/兜底胜利口径）
	unit.battle_position = grid_pos
	unit.is_active = true
	_apply_unit_config(unit, unit_config)
	return unit


## 构造敌方 BattleUnit
static func make_enemy_unit(troop: TroopData, pack: LevelSlot, grid_pos: Vector2i, unit_config: Dictionary) -> BattleUnit:
	var unit: BattleUnit = BattleUnit.new()
	unit.owner_faction = Faction.ENEMY_1
	unit.troop = troop
	unit.source_level = pack
	unit.battle_position = grid_pos
	_apply_unit_config(unit, unit_config)
	return unit


## 从 unit_config 装配 move_range / attack_range（私有 helper）
static func _apply_unit_config(unit: BattleUnit, unit_config: Dictionary) -> void:
	var key: int = unit.troop.troop_type as int
	if unit_config.has(key):
		var entry: Dictionary = unit_config[key] as Dictionary
		unit.move_range = int(entry.get("move_range", 3))
		unit.attack_range = int(entry.get("attack_range", 1))
	else:
		# 兜底：未配置兵种默认 SWORD 数值
		unit.move_range = 3
		unit.attack_range = 1


## 在 anchor 周围找空位：先 4 邻、再 8 邻、可选扩到 max_radius 圈
##
## anchor      —— 锚点（玩家位置 / LevelSlot 位置）
## occupied    —— 全局占位字典
## max_radius  —— 搜索半径（默认 2 即覆盖 8 邻；4 = 16 格内）
## arena       —— 战场 Rect2i
## schema      —— 地图 schema（查地形 cost / 持久 slot）
##
## 返回找到的空格坐标；找不到返回 NO_DEPLOY_SLOT
static func find_deploy_slot(
	anchor: Vector2i, occupied: Dictionary, max_radius: int,
	arena: Rect2i, schema: MapSchema
) -> Vector2i:
	# 4 邻优先（与设计 §2.4 一致）
	var four_neighbors: Array[Vector2i] = [
		anchor + Vector2i(0, -1), anchor + Vector2i(0, 1),
		anchor + Vector2i(-1, 0), anchor + Vector2i(1, 0),
	]
	for pos in four_neighbors:
		if can_deploy_at(pos, occupied, arena, schema):
			return pos
	# 8 邻（含对角）
	if max_radius >= 2:
		var eight_corners: Array[Vector2i] = [
			anchor + Vector2i(-1, -1), anchor + Vector2i(1, -1),
			anchor + Vector2i(-1, 1),  anchor + Vector2i(1, 1),
		]
		for pos in eight_corners:
			if can_deploy_at(pos, occupied, arena, schema):
				return pos
	# 扩展圈（敌方多 troops 兜底）
	for radius in range(2, max_radius + 1):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if absi(dx) + absi(dy) > radius:
					continue
				if absi(dx) + absi(dy) < radius:
					continue
				var pos: Vector2i = anchor + Vector2i(dx, dy)
				if can_deploy_at(pos, occupied, arena, schema):
					return pos
	return NO_DEPLOY_SLOT


## 可占位条件（E MVP §2.4 is_valid_deploy_pos）
##   - 战场内（arena.has_point）/ 地形可通行（阶段 E：去世界边界 is_in_bounds 依赖）
##   - 地形可通行（不是 MOUNTAIN 等）
##   - 不在持久 slot 占据格
##   - 不在 occupied 字典
static func can_deploy_at(grid_pos: Vector2i, occupied: Dictionary, arena: Rect2i, schema: MapSchema) -> bool:
	if not arena.has_point(grid_pos):
		return false
	# 【L1.3b 阶段 E】去 is_in_bounds 冗余：arena.has_point + 地形 cost 才是真边界（无限模式 arena 可超核心区）
	if schema.get_terrain_cost(grid_pos.x, grid_pos.y) >= INF:
		return false
	if occupied.has(grid_pos):
		return false
	# 持久 slot 占据格不可放
	for ps in schema.persistent_slots:
		if ps != null and ps.position == grid_pos:
			return false
	return true


## 判断 find_deploy_slot 返回的坐标是否合法（区分哨兵）
static func is_valid_slot(slot: Vector2i, occupied: Dictionary, arena: Rect2i, schema: MapSchema) -> bool:
	if slot == NO_DEPLOY_SLOT:
		return false
	return can_deploy_at(slot, occupied, arena, schema)


## 构建 occupied 字典：所有存活上场单位的位置 → BattleUnit
static func build_occupied(player_units: Array[BattleUnit], enemy_units: Array[BattleUnit]) -> Dictionary:
	var d: Dictionary = {}
	for u in player_units:
		if u.is_active and u.is_alive():
			d[u.battle_position] = u
	for u in enemy_units:
		if u.is_active and u.is_alive():
			d[u.battle_position] = u
	return d
