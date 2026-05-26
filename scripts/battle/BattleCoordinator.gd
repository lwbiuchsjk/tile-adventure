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


# ─────────────────────────────────────
# 阶段 c：战斗会话启动 + 援军注入
# ─────────────────────────────────────

## 启动主动战斗（玩家按 [F] 命中候选包后调用）
##
## 流程（设计 §3.1）：
##   1. _supply -= _active_battle_supply_cost
##   2. 创建 BattleSession + 注入 sink
##   3. session.start(...) 完成展开
##   4. 显示 BattleHUD + 触发 redraw（让战场叠加渲染出来）
##
## 调用前由 try_trigger_active_battle 完成候选 + 补给守卫
func start_battle_session(packs: Array[LevelSlot]) -> void:
	if packs.is_empty():
		return
	# 补给扣除钳到 ≥0；调用前由 try_trigger_active_battle 已校验充足
	# 钳位防御 _active_battle_supply_cost > _supply 时不进入负数（被动战斗 E4 路径同样适用）
	_world_map._supply = maxi(0, _world_map._supply - _world_map._active_battle_supply_cost)
	_world_map._battle_session = BattleSession.new()
	# MVP-γ 阶段 2 修复：redraw_target 传 _renderer（非 self）—— _draw 已迁到
	# WorldMapRenderer，动画 tween 每帧须重绘 _renderer，重绘空的 WorldMap 无效；
	# BattleFloatText 也挂到 _renderer（同坐标空间的 Node2D）
	_world_map._battle_anim_director.setup(_world_map._renderer, _world_map._battle_hud, _world_map._battle_view, _world_map._terrain_altitude_step)
	# _bind_battle_session_sinks 阶段 d 抽出后，本调用改为 self；当前阶段仍在 WorldMap
	_world_map._bind_battle_session_sinks()
	_world_map._battle_session.start(
		_world_map._player_lifecycle.characters(),
		_world_map._unit.position,
		packs,
		_world_map._schema,
		_world_map._battle_arena_range,
		_world_map._battle_unit_config,
		_world_map.BATTLE_PARAM_CFG,
		_world_map._terrain_altitude_step,
		_world_map._player_lifecycle.coma_hp_threshold_ratio(),
		0,
		_world_map._damage_increment
	)
	# 入口 2 MVP 2.1 codex review P0-1 修复（2026-05-10）：
	# BattleSession.start 末尾的防御性 _check_battle_end_after_action 可能立即触发 COMA →
	# on_battle_ended sink 同步进入 _on_battle_session_ended → await 处 yield 出来,start() 返回
	# 此时 is_ended() == true,不应再启动战场镜头 / 显示 HUD（否则会闪现一帧 zoom + HUD 然后黑屏）
	# sink 的 await 完成后会自然进入 _player_lifecycle.trigger_coma_or_lose 启动黑屏过渡
	if _world_map._battle_session.is_ended():
		return
	# 持久 slot 援军（L1.2）：战斗存活态下注入命中 slot 的援军
	# 置于 HUD show + redraw 之前 → 援军单位随后续 queue_redraw 自然渲染
	_inject_reinforcements()
	# 战斗中清掉探索态可达高亮（避免视觉与战场叠加层干扰）
	_world_map._reachable_tiles = {}
	# 入口 4 MVP：战斗 Camera zoom + 战场居中（队长位置 = 战场中心）
	start_battle_camera(_world_map._unit.position)
	# HUD 先显示（refresh 内部读 session 状态）
	if _world_map._battle_hud != null:
		_world_map._battle_hud.show_hud(_world_map._battle_session)
	_world_map._update_hud()
	_world_map._renderer.queue_redraw()


## E4 被动战斗启动入口
##
## 流程（设计 §3.2 / §2.2）：
##   1. _supply -= _passive_battle_supply_cost 钳到 ≥0（被动是被迫卷入，不阻止触发）
##   2. 全部保护区内 packs 入战（与主动战斗"仅选定包"区别：被动是敌方主动逼近的全部）
##   3. 创建 BattleSession + 注入 sink + start
##   4. 显示 BattleHUD + 触发 redraw
##
## 战斗结束后 sink 通用收尾分支检测 current_faction == ENEMY_1，切回 PLAYER 回合
##（_turn_manager 在战斗中保持 ENEMY_1 不变，与"战斗中世界冻结"§2.9 一致）
func start_passive_battle(packs: Array[LevelSlot]) -> void:
	if packs.is_empty():
		return
	_world_map._supply = maxi(0, _world_map._supply - _world_map._passive_battle_supply_cost)
	_world_map._battle_session = BattleSession.new()
	# MVP-γ 阶段 2 修复：redraw_target 传 _renderer（非 self）—— _draw 已迁到
	# WorldMapRenderer，动画 tween 每帧须重绘 _renderer，重绘空的 WorldMap 无效；
	# BattleFloatText 也挂到 _renderer（同坐标空间的 Node2D）
	_world_map._battle_anim_director.setup(_world_map._renderer, _world_map._battle_hud, _world_map._battle_view, _world_map._terrain_altitude_step)
	_world_map._bind_battle_session_sinks()
	_world_map._battle_session.start(
		_world_map._player_lifecycle.characters(),
		_world_map._unit.position,
		packs,
		_world_map._schema,
		_world_map._battle_arena_range,
		_world_map._battle_unit_config,
		_world_map.BATTLE_PARAM_CFG,
		_world_map._terrain_altitude_step,
		_world_map._player_lifecycle.coma_hp_threshold_ratio(),
		0,
		_world_map._damage_increment
	)
	# 入口 2 MVP 2.1 codex review P0-1 修复（2026-05-10）：与 start_battle_session 同因
	# 详见上方 start_battle_session 内同段注释
	if _world_map._battle_session.is_ended():
		return
	# 持久 slot 援军（L1.2）：被动战斗同样注入命中 slot 的援军
	_inject_reinforcements()
	_world_map._reachable_tiles = {}
	# 入口 4 MVP：被动战斗同样触发战场镜头 zoom（战场中心 = 队长位置）
	start_battle_camera(_world_map._unit.position)
	if _world_map._battle_hud != null:
		_world_map._battle_hud.show_hud(_world_map._battle_session)
	_world_map._update_hud()
	_world_map._renderer.queue_redraw()


## 持久 slot 援军（L1.2 玩家 / L1.4 敌方）：战斗启动后注入命中 slot 的援军
##
## 设计原文：tile-advanture-design/持久slot援军_MVP.md §3.2 / §3.3；敌方援军_MVP.md §3.3
##
## 流程（双阵营对称，玩家先注入、敌方后注入）：
##   - 玩家方援军 → player_units（PLAYER 阵营，玩家控制）
##   - 敌方援军   → enemy_units（ENEMY_1 阵营，BattleAI 驱动；source_level=null 不进 _level_slots）
##   occupied 跨阵营续用（玩家先落位、敌方避让）；injected_total 跨阵营累加，_garrison_total_cap 对总数兜底
##
## 前置：_battle_session.start() 已完成且未 is_ended()（追加到 player/enemy_units 即被回合流程自然纳入）
func _inject_reinforcements() -> void:
	_world_map._reinforcement_hit_slots = []
	if _world_map._battle_session == null or _world_map._schema == null:
		return
	var arena: Rect2i = _world_map._battle_session.arena
	# 重建 occupied 续用（避免与本队 / 敌包 / 已入场援军重叠）；玩家先落位、敌方接着避让
	var occupied: Dictionary = BattleDeploy.build_occupied(_world_map._battle_session.player_units, _world_map._battle_session.enemy_units)
	var injected_total: int = 0
	# 玩家方援军 → player_units
	injected_total = _inject_side(
		_world_map._get_player_persistent_slots(), _world_map._battle_session.player_units, Faction.PLAYER, arena, occupied, injected_total)
	# 敌方援军（L1.4）→ enemy_units（AI 控制）
	injected_total = _inject_side(
		_world_map._get_enemy_persistent_slots(), _world_map._battle_session.enemy_units, Faction.ENEMY_1, arena, occupied, injected_total)


## 单阵营援军注入（敌方援军_MVP / L1.4 抽出）：命中判定 + 排序 + 逐条入场 + consumed 暂存 + 命中 slot 并入回收列表
##
## slots          —— 待扫描的同阵营持久 slot（_get_player/_enemy_persistent_slots 产出）
## target_units   —— 入场单位追加目标（player_units / enemy_units，按引用传入直接 append）
## faction        —— 援军阵营（PLAYER 玩家控制 / ENEMY_1 AI 驱动）
## arena          —— 战场矩形（命中判定 + 落位边界）
## occupied       —— 跨阵营续用的占位字典（玩家先落、敌方避让）
## injected_total —— 跨阵营累加的入场总数（_garrison_total_cap 对总数兜底）
## 返回：更新后的 injected_total（供下一阵营续算 cap）
func _inject_side(slots: Array[PersistentSlot], target_units: Array[BattleUnit], faction: int,
		arena: Rect2i, occupied: Dictionary, injected_total: int) -> int:
	# 1-2. 命中判定
	var hit_slots: Array[PersistentSlot] = []
	for slot in slots:
		if slot.reinforcement_roster.is_empty():
			continue
		if _slot_in_battle_range(slot, arena):
			hit_slots.append(slot)
	if hit_slots.is_empty():
		return injected_total
	# 3. 排序：type 降序（核心 2 > 城镇 1 > 村庄 0）；同 type 按 position（y 优先、x 次之）稳定序
	hit_slots.sort_custom(func(a: PersistentSlot, b: PersistentSlot) -> bool:
		if a.type != b.type:
			return (a.type as int) > (b.type as int)
		if a.position.y != b.position.y:
			return a.position.y < b.position.y
		return a.position.x < b.position.x
	)
	# 4-5. 入场填充
	for slot in hit_slots:
		var consumed: Array = []
		for entry_v in slot.reinforcement_roster:
			if injected_total >= _world_map._garrison_total_cap:
				break
			var entry: Dictionary = entry_v as Dictionary
			# 以 slot.position 为锚点找空格（slot 自身格被 can_deploy_at 排除，不能直接用 slot.position）
			var cell: Vector2i = BattleDeploy.find_deploy_slot(slot.position, occupied, 4, arena, _world_map._schema)
			if not BattleDeploy.is_valid_slot(cell, occupied, arena, _world_map._schema):
				continue  # 找不到空格 → 跳过该单位，条目保留在 roster（不计入 consumed）
			# 新建 TroopData（只用规格，hp 用默认满血，与 EnemyTroopGenerator 一致）
			var troop: TroopData = TroopData.new()
			troop.troop_type = int(entry.get("troop_type", 0)) as TroopData.TroopType
			troop.quality = int(entry.get("quality", 0)) as TroopData.Quality
			var unit: BattleUnit = BattleDeploy.make_reinforcement_unit(troop, cell, _world_map._battle_unit_config, faction)
			occupied[cell] = unit
			target_units.append(unit)
			consumed.append(entry)
			injected_total += 1
		slot._consumed_this_battle = consumed
		if not consumed.is_empty():
			_world_map._reinforcement_hit_slots.append(slot)
	return injected_total


## 判断 slot 到战场 arena 的最近格曼哈顿距离是否 ≤ _garrison_trigger_range
## 委托 ReinforcementRoster.is_in_trigger_range（静态、可 headless 测）
func _slot_in_battle_range(slot: PersistentSlot, arena: Rect2i) -> bool:
	return ReinforcementRoster.is_in_trigger_range(slot.position, arena, _world_map._garrison_trigger_range)


## 持久 slot 援军（L1.2）：战后回收——本场已入场援军条目从对应 slot 储备永久扣减
##
## 设计原文：tile-advanture-design/持久slot援军_MVP.md §3.4
##
## 语义：一次性消耗——已入场的条目（无论存活 / 阵亡）整体从 roster 移除；
##       未入场的条目（cap 截断 / 找不到空格）保留在 roster。
## 数据无关战斗会话本身，只读 _reinforcement_hit_slots + slot._consumed_this_battle，
## 故可在 _on_battle_session_ended 任何 _battle_session = null 之前安全调用。
func _consume_reinforcement_rosters() -> void:
	for slot in _world_map._reinforcement_hit_slots:
		if slot == null:
			continue
		ReinforcementRoster.apply_consumption(slot.reinforcement_roster, slot._consumed_this_battle)
		slot._consumed_this_battle = []
	_world_map._reinforcement_hit_slots = []


## 玩家按 [F] 主动战斗触发入口
##
## 候选检查 + 多包退化（MVP 简化）：
##   - 候选 == 0 → 无响应
##   - _supply == 0 → notice 提示，不入战
##   - 候选 == 1 → 直接确认
##   - 候选 > 1 → MVP 简化：选最近的包（曼哈顿距离最小）
##
## 不放在 start_battle_session 内是因为被动战斗（E4）会有不同的候选取舍逻辑
func try_trigger_active_battle() -> void:
	if _world_map._unit == null:
		return
	# 队长无部队 → 不能入战；走兜底队伍状态评估（理论上 _player_lifecycle.evaluate_party_state 此时应已触发昏迷 / 失败）
	# 防御性检查避免 BattleSession._deploy_player_side 落到无 actor 的卡死战斗态
	if _world_map._player_lifecycle.characters().is_empty() or _world_map._player_lifecycle.characters()[0] == null or not _world_map._player_lifecycle.characters()[0].has_troop():
		_world_map._player_lifecycle.evaluate_party_state(_world_map._game_finished)
		return
	# 触发判断：dist ≤ _battle_trigger_range 内有候选 → 才能按 [F]
	var trigger_candidates: Array[LevelSlot] = get_packs_in_range(_world_map._unit.position, _world_map._battle_trigger_range)
	if trigger_candidates.is_empty():
		return
	# 补给检查对照 _active_battle_supply_cost（可配置）；当前默认 0 = 不消耗，分支不会拦截
	if _world_map._supply < _world_map._active_battle_supply_cost:
		_world_map._show_notice("补给不足，无法主动进入战斗")
		return
	# 入战范围（用户拍板 2026-05-08）：所有 dist ≤ _battle_arena_range（=6）战场范围内的敌方包都参战
	# 替代原 §3.1 "仅选定包入战" 设计——避免战斗中战场内还有敌方但没参战的尴尬
	# 触发判断仍用 _battle_trigger_range（=3），玩家必须靠近才能触发
	var packs_in_arena: Array[LevelSlot] = get_packs_in_range(_world_map._unit.position, _world_map._battle_arena_range)
	if packs_in_arena.is_empty():
		# 边缘情况：触发判断通过但 arena 范围扫描却空（理论不可能，trigger_range ≤ arena_range）
		# 兜底走 trigger_candidates 不至于触发后无人参战
		packs_in_arena = trigger_candidates
	start_battle_session(packs_in_arena)
