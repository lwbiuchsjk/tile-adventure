class_name EnemyMovement
extends Node
## 敌方关卡移动子系统
## 管理移动队列、寻路、逐格动画和强制战斗触发。
## 作为 WorldMap 子节点运行以使用 Tween 动画。

## 移动阶段完成（队列清空或被中断）
signal phase_finished
## 强制战斗触发（敌方到达玩家相邻格）
signal forced_battle_triggered(level: LevelSlot)
## 请求父节点重绘（动画帧更新）
signal redraw_requested

## 逐格动画速度（秒/格）
const MOVE_STEP_DURATION: float = 0.1
## 格像素尺寸（由 WorldMap 在初始化时注入，须与 WorldMap.TILE_SIZE 保持一致）
## 默认值 0 为非法值，未注入时会在 _grid_to_pixel_center 中触发断言
var tile_size: int = 0

# ─────────────────────────────────────
# 内部状态
# ─────────────────────────────────────

## 是否正在执行移动阶段
var _is_moving: bool = false

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
var _level_slots: Dictionary = {}
## 玩家单位当前位置（用于强制战斗触发；敌方靠近玩家单位相邻格时触发战斗）
var _player_pos: Vector2i = Vector2i.ZERO
## M7 目标位置：敌方部队寻路目的地（玩家核心 persistent slot 位置）
## 与 _player_pos 分离：target 是战略目标，player_pos 是战术阻挡点
var _target_pos: Vector2i = Vector2i.ZERO
var _movement_points: int = 6
var _original_slot_types: Dictionary = {}
var _game_over: bool = false

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
## 收集所有可移动关卡，按距离（到 target_pos）排序后逐个处理
##
## M7 新增 target_pos 参数（§五 AI 移动策略）：
##   target_pos —— 战略目标（玩家核心 slot 位置）；寻路目的地
##   player_pos —— 玩家单位位置；用于强制战斗触发（到达其相邻格）
##   两者通常不同：核心是固定战略点，单位是移动战术点
func start_phase(schema: MapSchema, level_slots: Dictionary,
		player_pos: Vector2i, target_pos: Vector2i, movement_points: int,
		original_slot_types: Dictionary, game_over: bool) -> void:
	_schema = schema
	_level_slots = level_slots
	_player_pos = player_pos
	_target_pos = target_pos
	_movement_points = movement_points
	_original_slot_types = original_slot_types
	_game_over = game_over

	_is_moving = true
	_move_queue = _get_sorted_movable_levels()
	_process_next_move()


## 强制战斗结算后继续处理队列
func resume_after_battle() -> void:
	_process_next_move()


## 中断并结束移动阶段（游戏结束或轮次通关时调用）
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


## 获取可移动关卡列表，按距离 target_pos（玩家核心）从近到远排序
## 距离相同时按 y→x 稳定排序
## M7：仅 UNCHALLENGED 且归属 ENEMY_1 的 LevelSlot 参与；
##     faction == NONE 的 legacy 敌方格（M7 前的关卡）也允许，兼容过渡期
func _get_sorted_movable_levels() -> Array[LevelSlot]:
	var movable: Array[LevelSlot] = []
	for pos in _level_slots:
		var lv: LevelSlot = _level_slots[pos] as LevelSlot
		if lv.state != LevelSlot.State.UNCHALLENGED:
			continue
		# 排除玩家归属的 LevelSlot（如果未来出现此场景）
		if lv.faction == Faction.PLAYER:
			continue
		movable.append(lv)

	var t_pos: Vector2i = _target_pos
	movable.sort_custom(func(a: LevelSlot, b: LevelSlot) -> bool:
		var dist_a: int = absi(a.position.x - t_pos.x) + absi(a.position.y - t_pos.y)
		var dist_b: int = absi(b.position.x - t_pos.x) + absi(b.position.y - t_pos.y)
		if dist_a != dist_b:
			return dist_a < dist_b
		if a.position.y != b.position.y:
			return a.position.y < b.position.y
		return a.position.x < b.position.x
	)
	return movable


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

	# 寻路：目标为玩家核心（_target_pos），阻挡其他所有关卡 + 玩家单位
	# 玩家单位位置视为阻挡，路径自然停在相邻格触发 forced battle
	var blocked: Dictionary = _get_blocked_positions(level)
	blocked[_player_pos] = true
	var path_result: Pathfinder.PathResult = Pathfinder.find_path(
		_schema, level.position, _target_pos, {}, blocked
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

	_level_slots.erase(old_pos)
	level.position = new_pos
	_level_slots[new_pos] = level

	# 更新 Slot 标记（保留原始类型以便恢复）
	var restored_type: int = _original_slot_types.get(old_pos, MapSchema.SlotType.NONE) as int
	_schema.set_slot(old_pos.x, old_pos.y, restored_type as MapSchema.SlotType)
	_original_slot_types.erase(old_pos)
	if not _original_slot_types.has(new_pos):
		_original_slot_types[new_pos] = _schema.get_slot(new_pos.x, new_pos.y)
	_schema.set_slot(new_pos.x, new_pos.y, MapSchema.SlotType.FUNCTION)

	# 播放移动动画
	_start_animation(move_path)


## 获取敌方移动阻挡位置（排除自身，包含所有其他关卡）
func _get_blocked_positions(exclude_level: LevelSlot) -> Dictionary:
	var blocked: Dictionary = {}
	for pos in _level_slots:
		var p: Vector2i = pos as Vector2i
		var lv: LevelSlot = _level_slots[p] as LevelSlot
		if lv == exclude_level:
			continue
		if lv.state == LevelSlot.State.UNCHALLENGED or lv.is_repelled():
			blocked[p] = true
	return blocked


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
func _start_animation(path: Array[Vector2i]) -> void:
	_visual_pos = _grid_to_pixel_center(path[0])

	if _move_tween != null and _move_tween.is_valid():
		_move_tween.kill()

	_move_tween = create_tween()
	for i in range(1, path.size()):
		var target_pixel: Vector2 = _grid_to_pixel_center(path[i])
		_move_tween.tween_property(self, "_visual_pos", target_pixel, MOVE_STEP_DURATION)
		_move_tween.tween_callback(func() -> void: redraw_requested.emit())

	_move_tween.tween_callback(_on_move_finished)


## 移动动画完成回调
func _on_move_finished() -> void:
	if _moving_level == null:
		_process_next_move()
		return

	var level_pos: Vector2i = _moving_level.position
	var dist: int = absi(level_pos.x - _player_pos.x) + absi(level_pos.y - _player_pos.y)
	var adjacent: bool = dist == 1

	# M4: 敌方单位停留后，若该格有持久 slot 则尝试占据（对称玩家逻辑）
	# 顺序：先占据 → 再判断是否触发强制战斗；即便后续敌方在强制战斗中被击败，
	# 占据已发生，slot 归属保持 ENEMY_1 直到玩家走过去翻转
	_try_enemy_occupy_at(level_pos)

	_moving_level = null
	redraw_requested.emit()

	if adjacent:
		# 到达玩家相邻格，触发强制战斗
		var level: LevelSlot = null
		if _level_slots.has(level_pos):
			level = _level_slots[level_pos] as LevelSlot
		if level != null and level.state == LevelSlot.State.UNCHALLENGED:
			forced_battle_triggered.emit(level)
			return

	_process_next_move()


## 内部结束移动阶段（不对外发信号前的状态清理由 finish_phase 负责）
func _finish_phase_internal() -> void:
	_is_moving = false
	_moving_level = null
	_move_queue = []
	phase_finished.emit()


## M4: 敌方单位在 pos 尝试占据持久 slot
## 成功翻转则触发重绘（影响范围覆盖即时刷新）
## 注：_schema.persistent_slots 由 WorldMap 初始化时填充；_schema 在 start_phase 时注入
func _try_enemy_occupy_at(pos: Vector2i) -> void:
	if _schema == null:
		return
	for entry in _schema.persistent_slots:
		var ps: PersistentSlot = entry as PersistentSlot
		if ps.position != pos:
			continue
		if OccupationSystem.try_occupy(ps, Faction.ENEMY_1):
			redraw_requested.emit()
		return
