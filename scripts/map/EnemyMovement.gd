class_name EnemyMovement
extends Node
## 敌方关卡移动子系统
## 管理移动队列、寻路、逐格动画和强制战斗触发。
## 作为 WorldMap 子节点运行以使用 Tween 动画。

## 移动阶段完成（队列清空或被中断）
signal phase_finished
## 强制战斗触发（敌方进入玩家曼哈顿距离 ≤ _forced_battle_range 范围；A 基线收束 MVP 起从硬编码"相邻格"扩展为可配置范围）
signal forced_battle_triggered(level: LevelSlot)
## 请求父节点重绘（动画帧更新）
signal redraw_requested

## 逐格动画速度（秒/格）
const MOVE_STEP_DURATION: float = 0.1
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
## 玩家单位当前位置（用于强制战斗触发；敌方进入玩家曼哈顿距离 ≤ _forced_battle_range 时触发战斗）
var _player_pos: Vector2i = Vector2i.ZERO
## M7 目标位置：敌方部队寻路目的地（玩家核心 persistent slot 位置）
## 与 _player_pos 分离：target 是战略目标，player_pos 是战术阻挡点
var _target_pos: Vector2i = Vector2i.ZERO
var _movement_points: int = 6
var _original_slot_types: Dictionary = {}
var _game_over: bool = false
## M8 扩展：追玩家阈值。pack 到玩家距离 ≤ 该值 且 d_player < d_core 时才追玩家
## 默认 10（与 battle_config.enemy_target_switch_range 同值）；start_phase 注入实际值
var _target_switch_range: int = 10
## A 基线收束 MVP：强制战斗触发距离（曼哈顿）
## pack 移动后到玩家距离 ≤ 该值 时触发战斗
## 默认 3（与 battle_config.forced_battle_range 同值）；start_phase 注入实际值
var _forced_battle_range: int = 3

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
##   target_pos —— 战略目标（玩家核心 slot 位置）；寻路目的地的一个候选
##   player_pos —— 玩家单位位置；用于强制战斗触发 + 动态目标的另一候选
##   target_switch_range —— 追玩家阈值（默认 10）；pack 到玩家 ≤ 该值才可能追玩家
##     传 -1 或 0 时退化为"永远推核心"（测试 / 调试用）
##   forced_battle_range —— 强制战斗触发距离（默认 3）；pack 到玩家 ≤ 该值时触发战斗
func start_phase(schema: MapSchema, level_slots: Dictionary,
		player_pos: Vector2i, target_pos: Vector2i, movement_points: int,
		original_slot_types: Dictionary, game_over: bool,
		target_switch_range: int = 10,
		forced_battle_range: int = 3) -> void:
	_schema = schema
	_level_slots = level_slots
	_player_pos = player_pos
	_target_pos = target_pos
	_movement_points = movement_points
	_original_slot_types = original_slot_types
	_game_over = game_over
	_target_switch_range = target_switch_range
	_forced_battle_range = forced_battle_range

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


## 获取可移动关卡列表，按距离"最近目标"从近到远排序
## 距离相同时按 y→x 稳定排序
## M7：仅 UNCHALLENGED 且归属 ENEMY_1 的 LevelSlot 参与；
##     faction == NONE 的 legacy 敌方格（M7 前的关卡）也允许，兼容过渡期
##
## 动态目标（M8 扩展）：
##   每个部队包独立评估 min(dist_to_core, dist_to_player_troop)，选近者作为自己的 target
##   排序字段为该 pack 到"最近目标"的距离；移动时也用同一个 target（见 _pick_target_for）
##   效果：玩家前出时近处敌人盯玩家、远处继续推核心，战略压力 + 战术灵活并存
func _get_sorted_movable_levels() -> Array[LevelSlot]:
	var movable: Array[LevelSlot] = []
	for pos in _level_slots:
		var lv: LevelSlot = _level_slots[pos] as LevelSlot
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


## 返回 pos 到当前选中 target 的曼哈顿距离
## 保持和 _pick_target_for 同口径：玩家在阈值外或比核心远 → min = d_core；否则 min = d_player
## 保持一致是为了排序与目标选择结果对齐（排序顺序 = 实际追击的优先级）
func _min_target_distance(pos: Vector2i) -> int:
	var d_core: int = absi(pos.x - _target_pos.x) + absi(pos.y - _target_pos.y)
	var d_player: int = absi(pos.x - _player_pos.x) + absi(pos.y - _player_pos.y)
	if d_player <= _target_switch_range and d_player < d_core:
		return d_player
	return d_core


## 为单个部队包挑选本次移动的 target
## 规则（M8 阈值扩展）：
##   1. 玩家距离 ≤ _target_switch_range（默认 10） 且
##   2. 玩家比核心更近（d_player < d_core）
##   ↑ 两个条件同时满足 → target = 玩家
##   其他情况（玩家远离 / 核心更近或相等）→ target = 核心（战略兜底）
##
## 设计意图：
##   - 默认保持"推核心"战略压力，玩家核心仍是 AI 的最终目标
##   - 玩家出击深入敌方 10 格内 + 比核心更近 → 近处 pack 切换追玩家（响应威胁）
##   - 玩家贴在自己核心附近 → d_core 反而小，所有 pack 仍集火推核心
func _pick_target_for(level: LevelSlot) -> Vector2i:
	var d_core: int = absi(level.position.x - _target_pos.x) + absi(level.position.y - _target_pos.y)
	var d_player: int = absi(level.position.x - _player_pos.x) + absi(level.position.y - _player_pos.y)
	if d_player <= _target_switch_range and d_player < d_core:
		return _player_pos
	return _target_pos


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

	# 早退路径 1（target == 玩家 且 pack 已在玩家相邻格）：
	#   Pathfinder 返回 [self, player_pos]，trim 后仅 [self]，后续 size<2 分支会跳过
	#   → pack 原地不动、forced_battle 不触发；相邻状态被错过。
	#   直接 emit forced_battle 让战斗流程接手（resume_after_battle 会处理下一个 pack）
	if pack_target == _player_pos:
		var d: int = absi(level.position.x - _player_pos.x) + absi(level.position.y - _player_pos.y)
		if d == 1:
			_moving_level = null
			forced_battle_triggered.emit(level)
			return

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
		_move_tween.tween_property(self, "_visual_pos", target_pixel, MOVE_STEP_DURATION)
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
func _on_move_finished() -> void:
	if _moving_level == null:
		_process_next_move()
		return

	var level_pos: Vector2i = _moving_level.position
	var dist: int = absi(level_pos.x - _player_pos.x) + absi(level_pos.y - _player_pos.y)
	# A 基线收束 MVP：触发距离从硬编码 1 改为参数化 _forced_battle_range（默认 3）
	# 范围内即触发，给玩家更早的"被压迫"信号；具体值在 battle_config.csv 配置
	var in_force_range: bool = dist <= _forced_battle_range

	# M4: 敌方单位停留后，若该格有持久 slot 则尝试占据（对称玩家逻辑）
	# 顺序：先占据 → 再判断是否触发强制战斗；即便后续敌方在强制战斗中被击败，
	# 占据已发生，slot 归属保持 ENEMY_1 直到玩家走过去翻转
	_try_enemy_occupy_at(level_pos)

	_moving_level = null
	redraw_requested.emit()

	if in_force_range:
		# 进入玩家强制战斗范围（曼哈顿距离 ≤ _forced_battle_range），触发战斗
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
