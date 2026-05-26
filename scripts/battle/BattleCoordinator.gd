class_name BattleCoordinator
extends RefCounted
## WorldMap 战斗会话编排器（常驻，由 WorldMap 持有引用）
##
## 设计原文：
##   tile-advanture-design/WorldMap二次重构/批2_BattleCoordinator_MVP.md
##
## 职责（按设计 §范围划分，分 6 阶段逐步迁入）：
##   - 阶段 a：战斗查询工具（is_in_battle / get_packs_in_range / _is_pack_in_battle / _get_battle_unit_at_pos）
##   - 阶段 b：战斗 Camera/zoom 动画
##   - 阶段 c：战斗会话启动 + 援军注入
##   - 阶段 d：战斗会话 sink + 结算（_on_battle_session_ended 145 行）
##   - 阶段 e：战斗内推进 + 敌方阶段
##   - 阶段 f：BattleHUD sink + 守卫弹板
##
## 形态：RefCounted 实例（被 WorldMap._battle_coordinator 持有）
##
## 字段归属（沿用批 1 哲学）：
##   - WorldMap 字段（_battle_session / _battle_zoom_active / _battle_zoom_tween /
##     _battle_center_grid / _reinforcement_hit_slots 等）仍声明在 WorldMap.gd
##   - 本类通过 `_world_map._xxx = ...` 读写
##   - 本类自持 `_world_map` 引用 + 任何战斗会话内的临时中间状态

var _world_map: WorldMap


func _init(world_map: WorldMap) -> void:
	_world_map = world_map


## 由 MapBootstrap.init_world_subsystems() 末尾调一次
##
## BC 自己接 BattleHUD / BattleAnimDirector / EnemyMovement / BattleSession 的 signal
## 阶段 a：先留空骨架；阶段 e/f 迁入对应 signal 接线
func attach_sinks() -> void:
	# 阶段 a：暂无 signal 接线；阶段 e 接 EnemyMovement.phase_finished + BattleAnimDirector.anims_drained
	# 阶段 f 接 BattleHUD 4 sink。BattleSession sinks 由 _bind_battle_session_sinks 在每次战斗启动时绑定
	pass


# ─────────────────────────────────────
# 阶段 a：战斗查询工具
# ─────────────────────────────────────

## 战斗态判定：_battle_session 已创建且尚未结束
##
## 探索态守卫语义：所有面板 / 探索输入在 is_in_battle() 期间被拦截
## （参见 WorldMap._handle_click / _on_build_button_pressed / _start_camp 等）
func is_in_battle() -> bool:
	return _world_map._battle_session != null and not _world_map._battle_session.is_ended()


## 扫描指定坐标曼哈顿距离 ≤ range 内的敌方关卡（LevelSlot）
##
## 用于 [F] 主动战斗触发候选 + 后续 E4 被动战斗保护区扫描复用
##
## 命中条件：
##   - 在距离阈值内
##   - level.is_interactable() = true（UNCHALLENGED）
func get_packs_in_range(origin: Vector2i, search_range: int) -> Array[LevelSlot]:
	var result: Array[LevelSlot] = []
	for pos in _world_map._level_slots:
		var p: Vector2i = pos as Vector2i
		var dist: int = absi(p.x - origin.x) + absi(p.y - origin.y)
		if dist > search_range:
			continue
		var lv: LevelSlot = _world_map._level_slots[p] as LevelSlot
		if lv == null or not lv.is_interactable():
			continue
		result.append(lv)
	return result


## 检查指定格上是否有正在参战的敌方 LevelSlot
##
## 战斗中两个独立视觉层（探索态 LevelSlot 红菱形 + BattleUnit 红圆形）会重叠在 LevelSlot 原格，
## 看起来像"敌方分身"。此 helper 让 _draw_tile 在战斗中跳过参战 LevelSlot 的渲染，
## 让战场内视觉只剩 BattleUnit 圆形 + HP 条
##
## 战斗结束 sink 调 _level_slots.erase + 清空 _battle_session 后，本函数自然返回 false，
## _draw_tile 恢复正常渲染
func _is_pack_in_battle(pos: Vector2i) -> bool:
	if _world_map._battle_session == null:
		return false
	for pack in _world_map._battle_session.participating_packs:
		if pack != null and pack.position == pos:
			return true
	return false


## 在战场上（含玩家方 / 敌方）查找指定格上的存活单位
##
## _handle_click 战斗态分流用：点击格 → 是否敌方单位 → 攻击；否则当作移动目标
func _get_battle_unit_at_pos(pos: Vector2i) -> BattleUnit:
	if _world_map._battle_session == null:
		return null
	for u in _world_map._battle_session.player_units:
		if u != null and u.is_active and u.is_alive() and u.battle_position == pos:
			return u
	for u in _world_map._battle_session.enemy_units:
		if u != null and u.is_active and u.is_alive() and u.battle_position == pos:
			return u
	return null


# ─────────────────────────────────────
# 阶段 b：战斗 Camera / zoom
# ─────────────────────────────────────

## 入口 4 MVP：战斗 Camera zoom + 战场居中（进入战斗触发）
##
## zoom 公式（设计文档 §流程）：
##   need_grids = 战场尺寸(2*range+1) + 上下各 1 格余量
##   zoom = min(viewport_width / (need_grids*TILE_SIZE),
##              (viewport_height - HUD_RESERVE) / (need_grids*TILE_SIZE))
##   Godot 4 Camera2D.zoom 语义：< 1 = 视野扩大；这里目标 zoom 必然 ≤ 1
## Tween 0.3s 平滑过渡 zoom + position；战斗中 Camera 锁定，不再被 _sync_camera_to_unit_visual 同步
func start_battle_camera(battle_center: Vector2i) -> void:
	if _world_map._camera == null:
		return
	var zoom_target: float = _compute_battle_zoom_target()
	var center_pixel: Vector2 = _world_map._grid_to_pixel_center(battle_center)
	if _world_map._battle_zoom_tween != null and _world_map._battle_zoom_tween.is_valid():
		_world_map._battle_zoom_tween.kill()
	_world_map._battle_zoom_active = true
	_world_map._battle_center_grid = battle_center  # 入口 4 MVP（追加）：缓存战场中心供 _draw_battle_dim_overlay 使用
	_world_map._battle_zoom_tween = _world_map.create_tween().set_parallel(true)
	_world_map._battle_zoom_tween.tween_property(_world_map._camera, "zoom", Vector2(zoom_target, zoom_target), _world_map.VISUAL_CFG.zoom_tween_duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_world_map._battle_zoom_tween.tween_property(_world_map._camera, "position", center_pixel, _world_map.VISUAL_CFG.zoom_tween_duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	# 入口 4 MVP（2026-05-09 补）：战斗倾斜 5° —— 营造不平衡 / 紧张感
	_world_map._battle_zoom_tween.tween_property(_world_map._camera, "rotation", _world_map.VISUAL_CFG.tilt_rad, _world_map.VISUAL_CFG.zoom_tween_duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	# MVP-δ 阶段 2：战斗强制白天 fade —— NightVisionLayer 自管理 pending_post_battle_phase
	# + force_day flag + Tween + 浮层清空，WorldMap 一行调用即可
	if _world_map._night_vision != null:
		_world_map._night_vision.set_battle_force_day_on()

	# 核心目标传达 L1.5：战斗中相机 zoom 到战场，核心指引无意义且干扰 → 隐藏整层
	if _world_map._core_objective_overlay != null:
		_world_map._core_objective_overlay.set_battle_active(true)


## 入口 4 MVP：战斗结束 Camera zoom 回归 + 镜头回到队长（_on_battle_session_ended 开头调用）
##
## 配对调用：每次 start_battle_camera 必有一次 end_battle_camera
## 注意：本函数应在 _sync_world_unit_from_battle_leader（如调用）之前/之后皆可——
##   如之后则 _unit.position 已是战斗结束最终位置；如之前则可能仍是开战时位置。
##   当前选择：在 _on_battle_session_ended 顶部调用，与 _battle_hud.hide_hud 同时机
func end_battle_camera() -> void:
	# MVP-δ 阶段 2：force-day 解除前置（codex P1-4 历史修复语义保留）—— NightVisionLayer 自管理
	# 无论后续 _battle_zoom_active=false / _camera==null 异常路径，本调用总会跑完
	if _world_map._night_vision != null:
		_world_map._night_vision.resync_to_post_battle_state()
	# 核心目标传达 L1.5：战斗结束 → 恢复暗角 + 核心指引
	if _world_map._core_objective_overlay != null:
		_world_map._core_objective_overlay.set_battle_active(false)
	if not _world_map._battle_zoom_active:
		return
	_world_map._battle_zoom_active = false
	if _world_map._battle_zoom_tween != null and _world_map._battle_zoom_tween.is_valid():
		_world_map._battle_zoom_tween.kill()
	if _world_map._camera == null:
		return
	var leader_pos: Vector2 = _world_map._camera.position
	if _world_map._unit != null:
		leader_pos = _world_map._grid_to_pixel_center(_world_map._unit.position)
	_world_map._battle_zoom_tween = _world_map.create_tween().set_parallel(true)
	_world_map._battle_zoom_tween.tween_property(_world_map._camera, "zoom", Vector2.ONE, _world_map.VISUAL_CFG.zoom_tween_duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_world_map._battle_zoom_tween.tween_property(_world_map._camera, "position", leader_pos, _world_map.VISUAL_CFG.zoom_tween_duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	# 入口 4 MVP（2026-05-09 补）：倾斜归位
	_world_map._battle_zoom_tween.tween_property(_world_map._camera, "rotation", 0.0, _world_map.VISUAL_CFG.zoom_tween_duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## 入口 4 MVP：战斗 zoom 目标值计算（设计文档公式）
## 取 viewport 实际尺寸（不依赖基线 1280×720，stretch 等比缩放在更上层处理）
## HUD 占位用 VISUAL_CFG.zoom_hud_reserve_px 估值；跑测后改 battle_visual_config.tres
func _compute_battle_zoom_target() -> float:
	var battle_size: int = _world_map._battle_arena_range * 2 + 1
	var need_grids: int = battle_size + _world_map.VISUAL_CFG.zoom_margin_grid * 2
	var need_world_px: float = float(need_grids * _world_map.TILE_SIZE)
	var vp: Vector2 = _world_map.get_viewport().get_visible_rect().size
	var usable_h: float = maxf(vp.y - float(_world_map.VISUAL_CFG.zoom_hud_reserve_px), 1.0)
	var zoom_x: float = vp.x / need_world_px
	var zoom_y: float = usable_h / need_world_px
	# zoom 取较小者（保证两轴都能装下）；上限钳到 1.0 避免在大窗口下反向放大
	return minf(minf(zoom_x, zoom_y), 1.0)
