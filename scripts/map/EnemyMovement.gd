class_name EnemyMovement
extends Node
## 敌方关卡移动子系统
## 管理移动队列、寻路、逐格动画；被动战斗触发由 WorldMap 在敌方阶段末尾扫描保护区。
## 作为 WorldMap 子节点运行以使用 Tween 动画。

## 移动阶段完成（队列清空或被中断）
signal phase_finished
## 请求父节点重绘（动画帧更新）
signal redraw_requested

## 逐格动画速度 → MVP-B.2 阶段 1 迁入 MAP_BASE_CFG.move_step_duration（顺手消除与 WorldMap.gd 的双源隐患）
const MAP_BASE_CFG: MapBaseConfig = preload("res://assets/config/map_base_config.tres")
## 视口跳过判定的软边界（单位：格）
## 视口可见矩形向外扩展该格数后再做"全路径在外"判定，避免边缘格"中心刚好出框"被误跳过造成视觉断层
## 0 = 严格按视口边界；1 = 留 1 格缓冲（推荐默认）
const VISIBLE_RECT_PADDING_TILES: int = 1
## Rect2 兜底用的大有限值（替代 INF 避免 has_point 在 Godot 中行为不确定）
## 大于任何合法地图像素坐标即可（参考 100×100 格 × TILE_SIZE 64 = 6400，1e9 远超任何正常地图）
const RECT_FALLBACK_LIMIT: float = 1.0e9
## 格像素尺寸（由 WorldMap 在初始化时注入，须与 WorldMap.TILE_SIZE 保持一致）
## 默认值 0 为非法值，未注入时会在 _grid_to_pixel_center 中触发断言
var tile_size: int = 0
## 摄像机引用（由 WorldMap 在 _init_subsystems 注入）
## 用于计算视口可见矩形：路径全在视口外时跳过 Tween 直接结算，避免玩家看不到的移动产生可感停顿
## 未注入（_camera == null）时退化为"永不跳过"，保守兜底
var _camera: Camera2D = null

# ─────────────────────────────────────
# 内部状态
# ─────────────────────────────────────

## 是否正在执行移动阶段
var _is_moving: bool = false

## L1.3c 回归修复：phase_finished 是否已排入延迟发出（防同帧多终止出口重复 defer/emit）
var _phase_finish_deferred: bool = false

## 待移动关卡队列
var _move_queue: Array[LevelSlot] = []

## 当前移动关卡的视觉位置（像素坐标，Tween 驱动）
var _visual_pos: Vector2 = Vector2.ZERO

## 当前正在移动的关卡引用
var _moving_level: LevelSlot = null

## Tween 引用
var _move_tween: Tween = null

# ─────────────────────────────────────
# 阶段上下文（start_phase 时传入）
# ─────────────────────────────────────

var _schema: MapSchema = null
## 世界视图 facade（MVP-δ 阶段 1 引入）—— 取代原 _level_slots 字典副本
##
## EnemyMovement 不再持有任何 WorldMap 私字段引用；所有读访问通过 facade getter，
## 所有写操作通过 facade command（commit_enemy_move / try_enemy_occupy_persistent_slot）。
## 由 start_phase 时 WorldMap 一次性注入。
var _world_view: WorldView = null
## 玩家单位当前位置（用于 _pick_target_for 追玩家分支 + 保护区中心）
var _player_pos: Vector2i = Vector2i.ZERO
## 敌方部队寻路目的地战略目标位置
##
## P0 第二阶段后已废弃：_pick_target_for 改为"附近 slot 占领 / 追玩家"二元，不再读取该字段
## 历史：X-A 前 = 玩家方 CORE_TOWN；X-A 后 = _start_pos；现保留作 start_phase 签名兼容
var _target_pos: Vector2i = Vector2i.ZERO
var _movement_points: int = 6
var _game_over: bool = false
## M8 扩展遗留字段：旧"追玩家阈值"
## P0 第二阶段后已废弃：_pick_target_for 改用 PERCEIVE_RANGE 常量（默认 3）
## 保留字段作 start_phase 签名兼容；当前 MVP 内无任何代码读取
var _target_switch_range: int = 10
## 玩家保护区半径（曼哈顿距离）
## 保护区把 dist < _forced_battle_range 的格全部 blocked，pack 永远停在 dist ≥ range 处。
## 被动战斗由 _on_enemy_phase_finished 末尾统一扫描保护区内是否有敌方包（设计 §3.2）。
## 默认 3（与 BattleParamResource.forced_battle_range 同值）；start_phase 注入实际值。
var _forced_battle_range: int = 3

## E 战斗就地展开 MVP §2.3：玩家保护区半径（曼哈顿）
## 保护区内（dist < _protected_zone_range）格 cost = INF（不可经过 / 不可停留）
## 保护区边缘（dist == _protected_zone_range）格 cost = 1（可停留）
## 保护区外格按地形 cost；start_phase 注入；0 = 关闭保护区（向后兼容 / 调试）
var _protected_zone_range: int = 0

# ─────────────────────────────────────
# 公开接口
# ─────────────────────────────────────

## 当前是否在移动阶段
func is_moving() -> bool:
	return _is_moving


## 当前移动关卡的视觉位置
func get_visual_pos() -> Vector2:
	return _visual_pos


## 当前正在移动的关卡
func get_moving_level() -> LevelSlot:
	return _moving_level


## 启动敌方移动阶段
## 收集所有可移动关卡，按距离（到动态 target）排序后逐个处理
##
## 参数：
##   schema —— 地图 schema（纯读：Pathfinder.find_path / 地形 cost / 持久 slot 枚举）
##   world_view —— 世界视图 facade（MVP-δ 阶段 1 引入）；取代原 level_slots / original_slot_types
##     两个字典引用参数。读 level_slots 走 world_view.get_level_slots()；
##     写整组（level 位置 + slot 类型 + original_slot_types）走 world_view.commit_enemy_move()
##   target_pos —— 战略目标（P0 X-A 后 = 玩家 spawn 锚 _start_pos；X-A 前 = 玩家方 CORE_TOWN）
##     P0 第二阶段后保留仅作签名兼容，_pick_target_for 内部不再读取
##   player_pos —— 玩家单位位置；用于 _pick_target_for 追玩家分支 + 保护区中心
##   target_switch_range —— 追玩家阈值（默认 10）；pack 到玩家 ≤ 该值才可能追玩家
##     传 -1 或 0 时退化为"永远推核心"（测试 / 调试用）
##   forced_battle_range —— 保护区半径（默认 3）；保护区内格 blocked + 被动战斗扫描半径
##   protected_zone_range —— E MVP 玩家保护区半径（曼哈顿）；保护区内格 cost = INF
##     默认 0 = 关闭保护区（向后兼容 / 调试）；正常路径下 WorldMap 注入 _battle_trigger_range
func start_phase(schema: MapSchema, world_view: WorldView,
		player_pos: Vector2i, target_pos: Vector2i, movement_points: int,
		game_over: bool,
		target_switch_range: int = 10,
		forced_battle_range: int = 3,
		protected_zone_range: int = 0) -> void:
	_schema = schema
	_world_view = world_view
	_player_pos = player_pos
	_target_pos = target_pos
	_movement_points = movement_points
	_game_over = game_over
	_target_switch_range = target_switch_range
	_forced_battle_range = forced_battle_range
	_protected_zone_range = protected_zone_range

	_is_moving = true
	_phase_finish_deferred = false   # L1.3c 回归修复：新阶段开始，复位延迟结束守卫
	_move_queue = _get_sorted_movable_levels()
	_process_next_move()


## 强制战斗结算后继续处理队列
func resume_after_battle() -> void:
	_process_next_move()


## 中断并结束移动阶段（游戏结束或胜负判定时调用）
func finish_phase() -> void:
	_is_moving = false
	_moving_level = null
	_move_queue = []
	if _move_tween != null and _move_tween.is_valid():
		_move_tween.kill()
		_move_tween = null
	phase_finished.emit()


## 通知游戏已结束，使移动处理在下次检查时中断
func notify_game_over() -> void:
	_game_over = true

# ─────────────────────────────────────
# 内部逻辑
# ─────────────────────────────────────

## 将格坐标转为像素中心
func _grid_to_pixel_center(grid_pos: Vector2i) -> Vector2:
	assert(tile_size > 0, "EnemyMovement.tile_size 未注入，请在 add_child 后调用前赋值")
	return Vector2(
		grid_pos.x * tile_size + tile_size / 2,
		grid_pos.y * tile_size + tile_size / 2
	)


## 获取可移动关卡列表，按距离"最近目标"从近到远排序
## 距离相同时按 y→x 稳定排序
## M7：仅 UNCHALLENGED 且归属 ENEMY_1 的 LevelSlot 参与；
##     faction == NONE 的 legacy 敌方格（M7 前的关卡）也允许，兼容过渡期
##
## 动态目标（P0 第二阶段重设计）：
##   每个部队包独立评估 _pick_target_for：附近 PERCEIVE_RANGE 内有非己方持久 slot → 占领该 slot；
##   否则 → 追玩家
##   排序字段为该 pack 到"选中 target"的距离（_min_target_distance 同口径）
##   效果：占领优先制造"敌方扩张感"；玩家远离任何 slot 时被持续追击
func _get_sorted_movable_levels() -> Array[LevelSlot]:
	var movable: Array[LevelSlot] = []
	# MVP-δ 阶段 1：经 world_view facade 读 level_slots（不再持字典引用副本）
	var level_slots: Dictionary = _world_view.get_level_slots()
	for pos in level_slots:
		var lv: LevelSlot = level_slots[pos] as LevelSlot
		if lv.state != LevelSlot.State.UNCHALLENGED:
			continue
		# 阵营白名单：ENEMY_1（M7 正式）+ NONE（M7 前 legacy 关卡兼容）
		# 审查 P2 修复：旧实现只排除 PLAYER，会把未知扩展势力也纳入；显式白名单避免漏收紧
		if lv.faction != Faction.ENEMY_1 and lv.faction != Faction.NONE:
			continue
		movable.append(lv)

	movable.sort_custom(func(a: LevelSlot, b: LevelSlot) -> bool:
		var dist_a: int = _min_target_distance(a.position)
		var dist_b: int = _min_target_distance(b.position)
		if dist_a != dist_b:
			return dist_a < dist_b
		if a.position.y != b.position.y:
			return a.position.y < b.position.y
		return a.position.x < b.position.x
	)
	return movable


## P0 第二阶段感知半径（默认 3，跑测调参；P2 待跟踪移到 cycle_config）
## 规则：附近 PERCEIVE_RANGE 内非己方 persistent slot → 占领；否则追玩家
const PERCEIVE_RANGE: int = 3


## 返回 pos 到当前选中 target 的曼哈顿距离
## P0 第二阶段：与 _pick_target_for 同口径（先扫占领候选，无候选则追玩家）
func _min_target_distance(pos: Vector2i) -> int:
	var occupy_target: Vector2i = _find_nearest_non_own_slot(pos, PERCEIVE_RANGE)
	if occupy_target.x >= 0:
		return absi(pos.x - occupy_target.x) + absi(pos.y - occupy_target.y)
	return absi(pos.x - _player_pos.x) + absi(pos.y - _player_pos.y)


## 为单个部队包挑选本次移动的 target（P0 第二阶段重设计）
##
## 规则：
##   附近 PERCEIVE_RANGE（默认 3）步内有非 ENEMY_1 持久 slot → target = 最近可占 slot（占领行为）
##   否则 → target = 玩家当前位置（动态追击）
##
## 设计意图（整局节奏重设计 §2.6 / §4.4）：
##   - 占领优先于追击：让敌方"路过 slot 必占"，避免不自然的擦肩
##   - 玩家远离任何 slot 时 pack 朝玩家逼近 → 制造"被追"压迫感
##   - PERCEIVE_RANGE = 3（与 forced_battle_range 一致便于调参对齐）
##
## 已废弃：旧"target_pos = _start_pos 静态锚 + _target_switch_range 切换"框架
##   (_target_pos 字段保留兼容签名但 _pick_target_for 不再读取)
func _pick_target_for(level: LevelSlot) -> Vector2i:
	var occupy_target: Vector2i = _find_nearest_non_own_slot(level.position, PERCEIVE_RANGE)
	if occupy_target.x >= 0:
		return occupy_target
	return _player_pos


## P0 第二阶段：扫 schema.persistent_slots 找最近的非 ENEMY_1 slot（曼哈顿距离 ≤ range_val）
## 返回最近 slot 位置；未找到返回 (-1, -1)
##
## 设计选择：扫描所有 persistent_slots（地图 26 个量级，O(n) 每 pack 开销可接受）
## 占领候选包括：中立资源 slot / 玩家方占位 TOWN / 玩家占领后的 CORE_TOWN（所有非己方都可占）
func _find_nearest_non_own_slot(from_pos: Vector2i, range_val: int) -> Vector2i:
	if _schema == null:
		return Vector2i(-1, -1)
	var best_pos: Vector2i = Vector2i(-1, -1)
	var best_dist: int = range_val + 1
	for entry in _schema.persistent_slots:
		var slot: PersistentSlot = entry as PersistentSlot
		if slot == null:
			continue
		if slot.owner_faction == Faction.ENEMY_1:
			continue
		var d: int = absi(slot.position.x - from_pos.x) + absi(slot.position.y - from_pos.y)
		if d <= range_val and d < best_dist:
			best_dist = d
			best_pos = slot.position
	return best_pos


## 处理队列中下一个关卡
## 队列为空或游戏结束时结束阶段
func _process_next_move() -> void:
	if _game_over:
		_finish_phase_internal()
		return

	if _move_queue.is_empty():
		_finish_phase_internal()
		return

	var level: LevelSlot = _move_queue.pop_front()

	# 状态可能在前序战斗中被改变，跳过无效关卡
	if level.state != LevelSlot.State.UNCHALLENGED:
		_process_next_move()
		return

	# 寻路：目标为本部队包动态挑选的 target（核心 / 玩家部队近者）
	# blocked 规则（与 target 类型解耦）：
	#   - target == core（或其它非玩家）：_player_pos 需放入 blocked，路径绕开玩家
	#   - target == _player_pos 本身：不可把玩家格放入 blocked
	#     原因：Pathfinder 在 blocked_positions.has(end) 时拒绝 end 进 open_set，直接返回空路径，
	#     pack 原地不动 → 追玩家功能实际不工作。此时玩家格作为路径终点参与寻路，
	#     再由下方 trim 逻辑剥掉末格，自然停在玩家相邻格
	var pack_target: Vector2i = _pick_target_for(level)
	var blocked: Dictionary = _get_blocked_positions(level)
	if pack_target != _player_pos:
		blocked[_player_pos] = true

	# 保护区把 dist < _battle_trigger_range（默认 3）的格全部 blocked，
	# pack 不可能停在 dist == 1 的玩家相邻格；即使 pack 起始就在相邻格（极端时序，玩家上轮才出现）
	# 也由保护区 blocked 让寻路自然把 pack 推到边缘。
	# 被动战斗在 _on_enemy_phase_finished 末尾统一扫描

	# E4 保护区追玩家纠正：pack_target == _player_pos 时 _player_pos 已被保护区 blocked，
	# Pathfinder 终点不可达直接返回空路径 → pack 原地不动。
	# 改 target 为保护区**边缘**最近可达格，让 pack 自然停在边缘准备触发被动战斗。
	# 边缘全部不可达 → 退化为推核心，与原非追玩家分支一致。
	if pack_target == _player_pos and _protected_zone_range > 0:
		var edge_target: Vector2i = _find_protected_zone_edge_target(level.position, blocked)
		if edge_target == level.position:
			# 边缘全部不可达：退化为推核心；同时把 _player_pos 重新加进 blocked
			pack_target = _target_pos
			if _target_pos != _player_pos:
				blocked[_player_pos] = true
		else:
			pack_target = edge_target

	var path_result: Pathfinder.PathResult = Pathfinder.find_path(
		_schema, level.position, pack_target, {}, blocked
	)

	if path_result.path.size() < 2:
		_process_next_move()
		return

	# 按移动力截断路径
	var move_path: Array[Vector2i] = _truncate_path(path_result.path, _movement_points)

	# 敌方不进入玩家格，停在相邻格触发战斗
	if move_path.size() >= 2 and move_path[move_path.size() - 1] == _player_pos:
		move_path.resize(move_path.size() - 1)

	if move_path.size() < 2:
		_process_next_move()
		return

	# 更新逻辑位置
	_moving_level = level
	var old_pos: Vector2i = level.position
	var new_pos: Vector2i = move_path[move_path.size() - 1]

	# MVP-δ 阶段 1：原子写收敛到 world_view facade command
	#   - L1.3c 阶段 D：_level_slots erase/set + level.position（schema FUNCTION 双写已退役）
	#   由 EC._commit_enemy_move 在内部一次性执行
	_world_view.commit_enemy_move(level, old_pos, new_pos)

	# 播放移动动画
	_start_animation(move_path)


## 获取敌方移动阻挡位置（排除自身，包含所有其他关卡）
##
## E4 玩家保护区扩展：把 dist < _protected_zone_range 的格全部加进 blocked
## 保护区**边缘**（dist == _protected_zone_range）格不加，让 pack 可停在边缘
## 保护区中心（玩家位置）也在 dist=0 < range 内，自然被加进 blocked，无需额外特判
##
## 设计意图（§2.3）：
##   - 寻路结果：敌方包尝试停在保护区边缘最近的可达格
##   - 边缘全部不可达 / 被占据 → 敌方索性不进入保护区，停在外部最近可达格（push_warning）
##     当前 Pathfinder 的"目的地不可达时取最近可达格"行为由 _process_next_move 后续 trim 处理
func _get_blocked_positions(exclude_level: LevelSlot) -> Dictionary:
	var blocked: Dictionary = {}
	# MVP-δ 阶段 1：经 world_view facade 读 level_slots
	var level_slots: Dictionary = _world_view.get_level_slots()
	for pos in level_slots:
		var p: Vector2i = pos as Vector2i
		var lv: LevelSlot = level_slots[p] as LevelSlot
		if lv == exclude_level:
			continue
		if lv.state == LevelSlot.State.UNCHALLENGED:
			blocked[p] = true
	# E4 保护区：玩家曼哈顿距离 < range 的格全部 blocked（dist == range 边缘格不加）
	if _protected_zone_range > 0:
		for dy in range(-_protected_zone_range + 1, _protected_zone_range):
			for dx in range(-_protected_zone_range + 1, _protected_zone_range):
				if absi(dx) + absi(dy) >= _protected_zone_range:
					continue
				blocked[_player_pos + Vector2i(dx, dy)] = true
	return blocked


## 在玩家保护区**边缘**（曼哈顿 dist == _protected_zone_range）找最接近 pack_pos 的可达格
##
## 设计意图（§2.3）：pack 追玩家时把目标改为边缘格，让 Pathfinder 能正常寻路；
## 战斗将在敌方阶段末尾的保护区扫描中由 _on_enemy_phase_finished 触发
##
## 候选过滤：
##   - 任意世界坐标（L1.3b 阶段 C：is_in_bounds 退役，无界世界无地图边界），按地形 cost 判可走
##   - 地形可通行（cost < INF）
##   - 不在 blocked 字典（其它 LevelSlot 占据等）
##
## 选最近的（曼哈顿距离 pack_pos 最小）；找不到返回 pack_pos（表示原地不动 / 退化推核心）
func _find_protected_zone_edge_target(pack_pos: Vector2i, blocked: Dictionary) -> Vector2i:
	if _protected_zone_range <= 0 or _schema == null:
		return pack_pos
	var best: Vector2i = pack_pos
	var best_dist: int = -1
	# 边缘格枚举：所有 |dx| + |dy| == _protected_zone_range 的偏移
	# 三元表达式返回无类型 Array 不能直接赋给 Array[int]（GDScript 4 类型化检查）
	# 改用 if/else 分支显式构造
	for dy in range(-_protected_zone_range, _protected_zone_range + 1):
		var dx_abs: int = _protected_zone_range - absi(dy)
		var dx_candidates: Array[int] = []
		if dx_abs == 0:
			dx_candidates.append(0)
		else:
			dx_candidates.append(dx_abs)
			dx_candidates.append(-dx_abs)
		for dx in dx_candidates:
			var pos: Vector2i = _player_pos + Vector2i(dx, dy)
			# 【L1.3b 阶段 C】is_in_bounds 退役：方环按 _protected_zone_range 有界枚举，可走性由地形 cost 决定
			if _schema.get_terrain_cost(pos.x, pos.y) >= INF:
				continue
			if blocked.has(pos):
				continue
			var d: int = absi(pos.x - pack_pos.x) + absi(pos.y - pack_pos.y)
			if best_dist < 0 or d < best_dist:
				best_dist = d
				best = pos
	return best


## 按移动力和地形消耗截断路径
## 返回截断后的路径（含起点）
func _truncate_path(full_path: Array[Vector2i], movement: int) -> Array[Vector2i]:
	var truncated: Array[Vector2i] = [full_path[0]]
	var remaining: float = float(movement)
	for i in range(1, full_path.size()):
		var cost: float = _schema.get_terrain_cost(full_path[i].x, full_path[i].y)
		if cost >= INF or cost > remaining:
			break
		remaining -= cost
		truncated.append(full_path[i])
	return truncated


## 播放逐格移动动画
## 视口外路径优化：若 path 上每一格的像素中心都不在摄像机可见矩形内，
## 跳过 Tween 直接把视觉位置 set 到终点 + 通过 deferred 调用 _on_move_finished
## 串接现有占据 / 强制战斗 / 队列推进流程，避免敌方回合在屏幕外产生可感停顿
func _start_animation(path: Array[Vector2i]) -> void:
	_visual_pos = _grid_to_pixel_center(path[0])

	if _move_tween != null and _move_tween.is_valid():
		_move_tween.kill()
		_move_tween = null

	# 视口外跳过分支：仅当摄像机已注入且整条路径全部在可见矩形之外时触发
	# 用 call_deferred 而非直接调用，避免在同一栈帧内深递归
	# (_process_next_move → _start_animation → _on_move_finished → _process_next_move)
	# 与原 tween_callback 的"下一帧触发"语义保持一致
	if _camera != null and _is_path_entirely_off_screen(path, _compute_visible_rect()):
		_visual_pos = _grid_to_pixel_center(path[path.size() - 1])
		redraw_requested.emit()
		call_deferred("_on_move_finished")
		return

	_move_tween = create_tween()
	for i in range(1, path.size()):
		var target_pixel: Vector2 = _grid_to_pixel_center(path[i])
		_move_tween.tween_property(self, "_visual_pos", target_pixel, MAP_BASE_CFG.move_step_duration)
		_move_tween.tween_callback(func() -> void: redraw_requested.emit())

	_move_tween.tween_callback(_on_move_finished)


## 计算摄像机当前可见矩形（世界坐标），并按 VISIBLE_RECT_PADDING_TILES 向外扩边
## 推导：center = _camera.get_screen_center_position()
##      half = (viewport_size / zoom) * 0.5
##      最终 rect = Rect2(center - half, half * 2).grow(padding_tiles * tile_size)
## _camera == null 或 zoom 异常（接近 0）时返回一个大但有限的 Rect2 兜底，
## 让 _is_path_entirely_off_screen 永远返回 false（即"永远不跳过"）
## 不用 INF：Godot 中 Rect2.has_point 对 INF/NaN 边界的行为缺乏官方明确说明，
## 改用 RECT_FALLBACK_LIMIT 这种大有限值，含义清晰且 has_point 行为确定
func _compute_visible_rect() -> Rect2:
	if _camera == null:
		return _fallback_rect()
	var viewport: Viewport = _camera.get_viewport()
	if viewport == null:
		return _fallback_rect()
	var view_size: Vector2 = viewport.get_visible_rect().size
	var zoom: Vector2 = _camera.zoom
	# zoom 任一分量过小时退化为永远可见，避免除零或矩形爆炸
	if zoom.x < 0.0001 or zoom.y < 0.0001:
		return _fallback_rect()
	var half: Vector2 = Vector2(view_size.x / zoom.x, view_size.y / zoom.y) * 0.5
	var center: Vector2 = _camera.get_screen_center_position()
	var rect: Rect2 = Rect2(center - half, half * 2.0)
	# 向外扩 padding 格作为软边界，避免边缘格"中心刚好出框"被误跳过
	if VISIBLE_RECT_PADDING_TILES > 0 and tile_size > 0:
		rect = rect.grow(float(VISIBLE_RECT_PADDING_TILES * tile_size))
	return rect


## 兜底矩形：覆盖所有合法地图坐标的大有限矩形
## 用于 _camera / viewport / zoom 异常时让 _is_path_entirely_off_screen 永远返回 false
func _fallback_rect() -> Rect2:
	var limit: float = RECT_FALLBACK_LIMIT
	return Rect2(Vector2(-limit, -limit), Vector2(limit * 2.0, limit * 2.0))


## 判定路径是否完全位于视口可见矩形之外
## 粒度：路径上每一格的像素中心都不在 rect 内 → true
## 选用"全路径在外"而非"起点+终点在外"，避免敌人从视口一侧"瞬移穿过"视口的视觉断层
func _is_path_entirely_off_screen(path: Array[Vector2i], rect: Rect2) -> bool:
	for pos in path:
		if rect.has_point(_grid_to_pixel_center(pos)):
			return false
	return true


## 移动动画完成回调
##
## 被动战斗触发由 _on_enemy_phase_finished 末尾统一扫描保护区内是否有敌方包；
## 保护区机制保证 pack 不可能停在 dist < _forced_battle_range 内（被 blocked），
## 但允许停在 dist == _forced_battle_range 边缘（设计 §3.2）。
func _on_move_finished() -> void:
	if _moving_level == null:
		_process_next_move()
		return

	var level_pos: Vector2i = _moving_level.position

	# M4: 敌方单位停留后，若该格有持久 slot 则尝试占据（对称玩家逻辑）
	_try_enemy_occupy_at(level_pos)

	_moving_level = null
	redraw_requested.emit()

	_process_next_move()


## 内部结束移动阶段（不对外发信号前的状态清理由 finish_phase 负责）
func _finish_phase_internal() -> void:
	_is_moving = false
	_moving_level = null
	_move_queue = []
	# L1.3c 阶段 C 回归修复（首夜滤镜卡夜，codex P1 补全）：phase_finished 延迟一帧发出。
	# 病因：start_phase 由 faction_turn_started(ENEMY_1) 信号的 EnemyAI 处理器同步调用；当敌方阶段
	#   在该调用栈内同步结束（空队列 / 全队路径<2 无法移动 / 全 invalid 等不产生动画的路径），立即
	#   phase_finished → 同步嵌套 start_faction_turn(PLAYER) → 而 DayNightState 的 faction_turn_started
	#   处理器（连接顺序在 EnemyAI 之后）最后才跑、用 ENEMY=夜 覆盖了已切到 PLAYER 的昼 → 滤镜卡夜。
	#   动画路径走 Tween 回调（已在信号 emit 返回后），本就安全；延迟发出统一两类路径、彻底消除重入。
	# once-guard：_process_next_move 递归 + 多终止出口可能多次进入，防同帧重复 defer / 重复 emit。
	if _phase_finish_deferred:
		return
	_phase_finish_deferred = true
	call_deferred("_emit_phase_finished")


## L1.3c 回归修复：延迟一帧后真正发出 phase_finished（脱离 faction_turn_started 信号调用栈）
func _emit_phase_finished() -> void:
	_phase_finish_deferred = false
	phase_finished.emit()


## M4: 敌方单位在 pos 尝试占据持久 slot
##
## MVP-δ 阶段 1（2026-05-15）：占据写操作收敛到 world_view facade。
## 占据成功时的重绘由 WorldMap._try_enemy_occupy_persistent_slot 内部直接调
## _renderer.queue_redraw()，EnemyMovement 不再发 redraw_requested（少一次信号往返）。
## redraw_requested 信号保留供动画帧 redraw 使用（_start_animation Tween 帧回调）。
func _try_enemy_occupy_at(pos: Vector2i) -> void:
	if _world_view == null:
		return
	_world_view.try_enemy_occupy_persistent_slot(pos, Faction.ENEMY_1)
