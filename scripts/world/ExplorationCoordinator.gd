class_name ExplorationCoordinator
extends RefCounted
## WorldMap 探索行动协调器（常驻，由 WorldMap 持有引用）
##
## 设计原文：
##   tile-advanture-design/WorldMap二次重构/批3_ExplorationCoordinator_MVP.md
##
## 职责（按设计 §范围划分，分 6 阶段逐步迁入）：
##   - 阶段 a：玩家移动动画链 + 可达性刷新
##   - 阶段 b：玩家占领 + 持久 slot 查询
##   - 阶段 c：扎营 + 持久 slot 营收
##   - 阶段 d：资源采集 + 回合结算
##   - 阶段 e：敌方移动 + 占领（最大风险段）
##   - 阶段 f：Slot 生成 + 奖励工厂 + 回合钩子 + 收口
##
## 形态：RefCounted 实例（被 WorldMap._exploration_coordinator 持有）
##
## 字段归属（沿用批 1/2 哲学）：
##   - WorldMap 字段（_unit / _is_moving / _is_camping / _supply /
##     _level_slots / _resource_slots / _original_slot_types /
##     _enemy_movement / _inventory 等）仍声明在 WorldMap.gd
##   - 本类通过 `_world_map._xxx = ...` 读写
##   - 本类自持 `_world_map` 引用 + 任何探索流程内的临时中间状态

var _world_map: WorldMap


func _init(world_map: WorldMap) -> void:
	_world_map = world_map


## 由 MapBootstrap.init_world_subsystems() 末尾调一次（在 BC.attach_sinks 之后）
##
## EC 接 EnemyMovement / PlayerLifecycle / Inventory 等 signal
## 阶段 a：先留空骨架；阶段 f 接 TurnManager.faction_turn_started + TickRegistry tick handler
func attach_sinks() -> void:
	# 阶段 a：暂无 signal 接线；EnemyMovement.commit_enemy_move 等 sink 仍由
	# MapBootstrap 通过 WorldView facade 转发（本批阶段 e 改 facade null 守卫）
	# 阶段 f 起接：TurnManager.faction_turn_started + TickRegistry tick handler
	pass


# ─────────────────────────────────────
# 阶段 a：玩家移动动画链 + 可达性刷新
# ─────────────────────────────────────

## 启动沿路径逐格移动的 Tween 动画
##
## 调用方：WorldMap._handle_click 探索态移动分流
## 注：_move_tween 是 WorldMap 字段（字段归属不变），通过 _world_map._move_tween 读写
func start_move_animation(path: Array[Vector2i]) -> void:
	_world_map._is_moving = true

	# 终止可能残留的旧 Tween
	if _world_map._move_tween != null and _world_map._move_tween.is_valid():
		_world_map._move_tween.kill()

	_world_map._move_tween = _world_map.create_tween()

	# 从路径第二个点开始（第一个是出发点），逐格插值视觉位置
	for i in range(1, path.size()):
		var target_pixel: Vector2 = _world_map._grid_to_pixel_center(path[i])
		# 每步动画：移动视觉位置到下一格中心
		# tween_property 第一参 = WorldMap 节点（因为 _unit_visual_pos 是 WM 字段）
		_world_map._move_tween.tween_property(_world_map, "_unit_visual_pos", target_pixel, _world_map.MAP_BASE_CFG.move_step_duration)
		# 每步回调：同步 Camera 位置并重绘
		_world_map._move_tween.tween_callback(_on_move_step)

	# 动画全部完成后的回调
	_world_map._move_tween.tween_callback(_on_move_finished)


## 每移动一格时的回调：同步 Camera 并重绘
func _on_move_step() -> void:
	# Camera 跟随视觉位置（平滑由 Camera2D 内置处理）
	_world_map._camera.position = _world_map._unit_visual_pos
	_world_map._renderer.queue_redraw()


## 移动动画全部完成后的回调
##
## 副作用（按顺序）：
##   1. 同步视觉位置精确对齐到逻辑位置
##   2. 消耗 1 补给
##   3. 尝试采集当前格资源（阶段 d 抽出后 self 调）
##   4. 全灭检查（WM method，留 WM）
##   5. 尝试占领持久 slot（阶段 b 抽出后 self 调）
##   6. 重置移动力 + 刷新 HUD + 刷新可达范围
func _on_move_finished() -> void:
	_world_map._is_moving = false

	# 确保视觉位置精确对齐到逻辑位置
	_world_map._unit_visual_pos = _world_map._grid_to_pixel_center(_world_map._unit.position)
	_world_map._camera.position = _world_map._unit_visual_pos

	# 消耗 1 补给
	_world_map._supply = maxi(0, _world_map._supply - 1)

	# 检查当前位置是否有一次性资源点并采集
	# 阶段 d 抽出后 self 自调；阶段 a 仍跨模块
	_world_map._try_collect_resource_at(_world_map._unit.position)

	# 全灭检查（战斗后部队全灭但玩家仍可移动的情况）
	if _world_map._check_defeat():
		return

	# 设计 §3.1 主动战斗只走 [F] 键：UNCHALLENGED 敌方 LevelSlot 由 _get_blocked_positions
	# 加进玩家阻挡，玩家走不到敌格；战斗入口统一由 _handle_f_key 触发，本路径不再分流战斗。

	# M4: 无战斗分支 —— 若停留格有持久 slot，尝试占据（§6.5 边界：格上无敌方单位）
	# 阶段 b 已迁入 EC，self 调
	try_player_occupy_at(_world_map._unit.position)

	# 每次移动后重置移动力，为下一次移动做准备
	_world_map._unit.current_movement = _world_map._unit.max_movement

	_world_map._update_hud()
	# 刷新可达范围（补给为 0 时会显示空集）
	refresh_reachable()


## 刷新可达范围并触发重绘
## 补给为 0 时不显示可达格；击退状态的关卡格视为不可通行
##
## 调用方（多入口）：
##   - WorldMap._handle_click 探索态点击后
##   - WorldMap._on_faction_turn_started 玩家回合开始（阶段 f 后回 self）
##   - WorldMap._on_build_panel_closed / _on_manage_ui_closed（面板关闭）
##   - BattleCoordinator._on_battle_session_ended 通用收尾末尾
##   - EC._on_move_finished 内 self 调
func refresh_reachable() -> void:
	if _world_map._unit != null and _world_map._schema != null and not _world_map._game_finished and _world_map._supply > 0:
		var blocked: Dictionary = _world_map._get_blocked_positions()
		_world_map._reachable_tiles = MovementSystem.get_reachable_tiles(
			_world_map._schema, _world_map._unit.position, float(_world_map._unit.current_movement), {}, blocked
		)
	else:
		_world_map._reachable_tiles = {}
	# E MVP：玩家移动后位置变化 → 触发距离内的候选可能变化 → 刷攻击按钮可见性
	_world_map._update_explore_action_button()
	_world_map._renderer.queue_redraw()


# ─────────────────────────────────────
# 阶段 b：玩家占领 + 持久 slot 查询
# ─────────────────────────────────────

## 按坐标查找 PersistentSlot；未命中返回 null
## MVP 总量 26，线性扫描开销可忽略
func _find_persistent_slot_at(pos: Vector2i) -> PersistentSlot:
	if _world_map._schema == null:
		return null
	for entry in _world_map._schema.persistent_slots:
		var ps: PersistentSlot = entry as PersistentSlot
		if ps.position == pos:
			return ps
	return null


## 玩家在 pos 尝试占据持久 slot（移动结束 / 战斗胜利后调用）
## 返回是否发生归属翻转；翻转后触发重绘以刷新影响范围覆盖
##
## 调用方：EC._on_move_finished 内 self 调 + WorldMap 其他路径跨模块调
func try_player_occupy_at(pos: Vector2i) -> bool:
	var ps: PersistentSlot = _find_persistent_slot_at(pos)
	if ps == null:
		return false
	var flipped: bool = OccupationSystem.try_occupy(ps, Faction.PLAYER)
	if flipped:
		_world_map._renderer.queue_redraw()
	return flipped


## 获取当前归属于 PLAYER 的所有持久 slot
##
## 调用方：WorldMap._open_build_panel / _on_upgrade_requested（建造面板）+
## BattleCoordinator._inject_reinforcements（援军注入）
func get_player_persistent_slots() -> Array[PersistentSlot]:
	return _get_persistent_slots_by_faction(Faction.PLAYER)


## 获取当前归属于 ENEMY_1 的所有持久 slot（敌方援军_MVP / L1.4）
##
## 调用方：BattleCoordinator._inject_reinforcements（敌方援军注入）
func get_enemy_persistent_slots() -> Array[PersistentSlot]:
	return _get_persistent_slots_by_faction(Faction.ENEMY_1)


## 按阵营过滤持久 slot（L1.4 抽出，玩家 / 敌方 getter 共用）
func _get_persistent_slots_by_faction(faction: int) -> Array[PersistentSlot]:
	var result: Array[PersistentSlot] = []
	if _world_map._schema == null:
		return result
	for entry in _world_map._schema.persistent_slots:
		var slot: PersistentSlot = entry as PersistentSlot
		if slot == null:
			continue
		if slot.owner_faction == faction:
			result.append(slot)
	return result
