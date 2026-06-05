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

## L1.1 阶段 3：视野系统单调递增回合计数器
## 设计：tile-advanture-design/无限地图实装/L1.1_视野循环与chunk底座_MVP.md §4.4
## L1.1 简化：每个 faction 回合开始各推进 1（PLAYER + ENEMY_1 各算 1，完整 round=2）
## 推进点：_on_faction_turn_started 内（在 faction 分流守卫之前）
## L1.3 会改为"扎营次数"单位
var _vision_turn: int = 0


func _init(world_map: WorldMap) -> void:
	_world_map = world_map


## 由 MapBootstrap.init_world_subsystems() 末尾调一次（在 BC.attach_sinks 之后）
##
## EC 接 TurnManager / TickRegistry / PlayerLifecycle / Inventory 等 signal
func attach_sinks() -> void:
	# 阶段 f：玩家回合开始 + 各阵营 tick 注册
	# （MapBootstrap L502 原接 _world_map._on_faction_turn_started，现 receiver 改为 EC）
	# （MapBootstrap L577 原 register _world_map._on_faction_tick，现注册 EC._on_faction_tick）
	_world_map._turn_manager.faction_turn_started.connect(_on_faction_turn_started)
	TickRegistry.register(_on_faction_tick)
	# EnemyMovement / BattleHUD / BattleAnimDirector 等 sink 由 WorldView facade 转发 / BC.attach_sinks 处理


## L1.1 阶段 2：注册玩家 VisionSource 到 VisionSystem + 触发首次 chunk aggregate
##
## 设计：tile-advanture-design/无限地图实装/L1.1_视野循环与chunk底座_MVP.md §4.1 / §5
## 调用方：MapBootstrap.finalize_startup() 末尾（_unit.position 已定 + 子系统已 ready）
##
## 包裹叠加阶段：仅启动数据流（VisionSystem.register_source 内部会 _recompute_coverage 触发
## tile_state_changed signal，ChunkManager 增量监听后自动 aggregate 受影响 chunk → ACTIVE
## 状态 → 触发 ChunkPCG.generate 生成首屏 chunk schema）。
## 本阶段不接渲染分层 / 不接移动钩子 / 不接回合钩子（阶段 3+ 增量接入）。
func init_vision_runtime() -> void:
	if _world_map._vision_system == null or _world_map._chunk_manager == null:
		push_warning("EC.init_vision_runtime: _vision_system / _chunk_manager 未就绪，跳过注册")
		return
	# 玩家队伍视野源：位置 = _unit.position（_start_pos）、半径 = vision_config.player_vision_radius
	# owner_node = _world_map（生命周期与 WorldMap 同步；reload 整片清空时自然释放）
	var radius: int = WorldMap.VISION_CFG.player_vision_radius
	_world_map._player_vision_source = VisionSource.new(
		_world_map._unit.position, radius, Faction.PLAYER, _world_map
	)
	_world_map._vision_system.register_source(_world_map._player_vision_source)
	# 首屏 ACTIVE chunk 数（验证 ChunkPCG 已被触发）
	var active_count: int = _world_map._chunk_manager.get_active_chunks().size()
	print("[L1.1] VisionSystem + ChunkManager 启动；玩家视野半径 = %d；首屏 ACTIVE chunk = %d" % [radius, active_count])

	# L1.2 Phase 2：据点 + 占领 slot 视野绑定（纯事件驱动，不做 init 扫描补登——
	# MVP 目标体验首周期玩家无占领，实现不依赖开局占领状态）
	# 据点靠 RunState.set_stronghold sink、占领靠 OccupationSystem.try_occupy 翻转 sink 增量接入
	var binding: StrongholdVisionBinding = StrongholdVisionBinding.new()
	binding.setup(_world_map._vision_system, WorldMap.VISION_CFG)
	_world_map._stronghold_vision_binding = binding
	RunState.register_stronghold_set_sink(binding.on_stronghold_set)
	OccupationSystem.register_slot_owner_changed_sink(binding.on_slot_owner_changed)
	# L1.2 Phase 3 修复：补登开局/reload 已占领 slot + 据点视野——
	# 地图生成会预染玩家归属 slot，纯事件驱动漏激活其视野；init_scan 增量补登（详见 init_scan 注释）
	binding.init_scan(_world_map._schema.persistent_slots)


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
	# 阶段 d 已迁入 EC，self 调
	try_collect_resource_at(_world_map._unit.position)

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

	# L1.1 阶段 3：同步玩家 VisionSource 位置到 VisionSystem
	# 设计：tile-advanture-design/无限地图实装/L1.1_视野循环与chunk底座_MVP.md §4.2
	# VisionSource 是 RefCounted（运行时短生命周期对象），位置由 EC 主动改写后
	# 通知 VisionSystem 重算覆盖；VisionSystem 内部走 _recompute_coverage + 退化判定
	# null 守卫：_player_vision_source 可能在 reload 早期未就绪（实际不会出现，但稳健）
	if _world_map._player_vision_source != null and _world_map._vision_system != null:
		_world_map._player_vision_source.position = _world_map._unit.position
		_world_map._vision_system.notify_source_moved()


## L1.2 Phase 3：昏迷复活——把队伍传送到 target_pos 并复位视图态（不 reload）
##
## 设计：L1.2_多源视野与据点机制_MVP §2.3 / §4.3
## 与 _on_move_finished 的"位置收尾"子集对齐，但**剔除正常移动语义**：
##   - 不消耗补给（复活非移动）、不触发资源采集 / 占领判定（避免在复活落点误占领 / 误采集）
## 执行：逻辑+视觉位置 + 相机对齐 + 队伍满血 + 重置移动力 + 刷 HUD + 刷可达 + 同步玩家视野源
## 调用方：WorldMap._on_player_coma_respawn_triggered 的 midpoint 闭包（phase B 全黑期）
func teleport_party_to(target_pos: Vector2i) -> void:
	var wm: WorldMap = _world_map
	if wm._unit == null:
		return
	# 1. 逻辑位置 + 视觉位置 + 相机对齐（与 _on_move_finished 同步逻辑一致）
	wm._unit.position = target_pos
	wm._unit_visual_pos = wm._grid_to_pixel_center(target_pos)
	wm._camera.position = wm._unit_visual_pos
	# 2. 队伍满血（队长 + 全队员 troop）——HP 权威源在 PlayerLifecycle.characters() 的 troop
	for ch in wm._player_lifecycle.characters():
		if ch != null and ch.has_troop():
			ch.troop.current_hp = ch.troop.max_hp
	# 3. 重置移动力（与正常移动收尾一致，复活后可立即行动）
	wm._unit.current_movement = wm._unit.max_movement
	# 4. HUD + 可达范围刷新
	wm._update_hud()
	refresh_reachable()
	# 5. 同步玩家视野源到新位置（与 _on_move_finished L1.1 阶段 3 同逻辑）
	if wm._player_vision_source != null and wm._vision_system != null:
		wm._player_vision_source.position = target_pos
		wm._vision_system.notify_source_moved()


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


# ─────────────────────────────────────
# 阶段 c：扎营 + 持久 slot 营收
# ─────────────────────────────────────

## 扎营入口：恢复补给 → 资源点结算 → 打开养成面板
##
## 调用方：WorldMap 输入路由（空格键 / 探索按钮）
func start_camp() -> void:
	# E MVP：战斗态守卫——is_in_battle 期间不允许扎营（设计 §2.10）
	if _world_map._game_finished or _world_map._is_moving or _world_map._is_camping or _world_map._manage_ui.is_open or _world_map._build_panel_ui.is_open or _world_map._event_panel.is_open or _world_map._player_lifecycle.is_in_coma() or _world_map._battle_coordinator.is_in_battle():
		return
	_world_map._is_camping = true
	_world_map._camp_count += 1
	# B 重生周期 MVP：累计本周期扎营次数（C MVP 入队判定的输入）
	# 放在 _camp_count += 1 紧后；advance_cycle 时 RunState 会把这个值 push 入 milestones
	RunState.record_camp()

	# L1.3a 阶段 C：扎营主时钟达阈值 → 触发 climax 决战（spawn boss pack 向玩家/据点进军）
	# 放在 record_camp 紧后、补给/产出事件之前——"强敌来袭"预警事件优先入 FIFO 队列
	_check_climax_trigger()

	# D MVP：扎营按下瞬间进入夜晚（用户跑测 2026-05-06 反馈）
	# 不等到 ENEMY_1 回合切换才生效——玩家心智上扎营即入夜
	# override 由 DayNightState 在新 PLAYER 回合开始时自动清
	DayNightState.set_phase_override(DayNightState.Phase.NIGHT)

	# 扎营恢复补给
	# F MVP：作为"扎营整顿"的第一条事件呈现；放在持久 slot 产出之前 push，
	# 保证事件队列顺序与玩家心智一致（先恢复，再产出）
	#
	# 入口 2 MVP 2.3 扩展（2026-05-11）：补给恢复 event 也走 NarrativeProvider
	# 场景:camp_supply_{wild|village|town}(独立池,与产出叙事分开)
	# 占位符:leader_name / count(补给恢复量) / slot_name(村庄/城镇场景)
	_world_map._supply += _world_map._camp_restore
	if _world_map._camp_restore > 0:
		var supply_info: Dictionary = _resolve_camp_scenario()
		var supply_scenario: String = "camp_supply_" + String(supply_info.get("scenario", "camp_wild")).substr(5)
		var supply_ctx: Dictionary = {
			"leader_name": _world_map._player_lifecycle.current_leader_name(),
			"count": _world_map._camp_restore,
		}
		if supply_scenario != "camp_supply_wild":
			supply_ctx["slot_name"] = String(supply_info.get("slot_name", ""))
		var supply_narrative: String = NarrativeProvider.pick(supply_scenario, supply_ctx)
		# _build_reward_event 阶段 f 抽出后改 self 调；阶段 c 仍跨模块
		_world_map._event_panel.push_event(_build_reward_event("扎营休整", supply_narrative))

	# M6: 持久 slot 扎营结算（玩家侧）
	# 流程：camp_pos 查 C 作用域覆盖 → 逐 slot 按类型 × 作用域覆盖 → 落地到石料 / 补给 / 背包
	_settle_persistent_camp_production()

	# C 重生周期 MVP：扎营产出事件 push 完后再做里程碑检查
	# 顺序意图：玩家心智上"扎营整顿 → 物资产出 → 新人加入"，叙事节奏自然
	# RunState.check_recruit_milestone 内部命中时调 _on_recruit_triggered → push_event
	# 入队事件因此排在扎营产出事件之后，由 EventPanelUI FIFO 依次弹出
	# L1.3a 阶段 D recruit 适配：按全局扎营计数每 interval 次触发，受 max_count 硬上限约束
	# （有界 stopgap，避免无限扎营抽干英雄池；入口 6 事件系统落地后整体迁入）
	RunState.check_recruit_milestone(
		_world_map._player_lifecycle.get_team_hero_ids(),
		WorldMap.RUN_PARAM_CFG.recruit_camp_interval,
		WorldMap.RUN_PARAM_CFG.recruit_max_count
	)

	# L1.2 Phase 1：据点选定判定（在里程碑入队后、_update_hud 前）
	# 命中条件全满足 → push 据点确认 event 到 EventPanelUI 队列（与扎营产出 / 里程碑同走 FIFO）；
	# 复用现有 _pending_camp_manage_open 守卫自动延迟 ManageUI 打开（下方步骤 7）
	_resolve_stronghold_prompt()

	_world_map._update_hud()

	# 入口 2 MVP 2.1 议题 1：扎营时事件队列清空后再开 ManageUI
	# 流程拆分：
	#   - 有事件入队（_event_panel.is_open）→ 置 _pending_camp_manage_open，等 closed 信号回调
	#   - 无事件入队（产出 / 里程碑都未命中）→ 直接打开 ManageUI（保持原行为）
	# 设计意图：避免事件面板与 ManageUI 同帧叠加弹出（详见 [[事件流程与队长过渡_MVP#流程 1]]）
	if _world_map._event_panel != null and _world_map._event_panel.is_open:
		_world_map._pending_camp_manage_open = true
	else:
		_world_map._manage_ui.open(_world_map._player_lifecycle.characters(), _world_map._inventory, true)


## L1.3a 阶段 C：climax boss spawn 锚点半径（玩家/据点附近多少格内取空地）；细化留子 MVP ②
const CLIMAX_BOSS_SPAWN_RANGE: int = 6


## L1.3a 阶段 C：climax 决战触发检查（start_camp 内 record_camp 后调用）
## 扎营主时钟 total_camp_count 达 climax_camp_threshold 且本局未触发过 → spawn 一支强 boss pack。
## 锚定玩家/据点附近（防守向·靠现有 EnemyMovement 逼近玩家），force_tier=3 最高强度（占位，细化留子 MVP ②）。
## spawn 失败（锚点附近无空地）时不置 mark，下次扎营重试。
func _check_climax_trigger() -> void:
	if RunState.is_climax_triggered():
		return
	if RunState.total_camp_count() < WorldMap.RUN_PARAM_CFG.climax_camp_threshold:
		return
	# 锚点：有据点向据点逼近，否则向玩家当前位置
	var anchor: Vector2i
	if RunState.has_stronghold():
		anchor = RunState.stronghold_pos()
	elif _world_map._unit != null:
		anchor = _world_map._unit.position
	else:
		push_warning("ExplorationCoordinator._check_climax_trigger: 无据点且 _unit 为空，无法确定 spawn 锚点，跳过")
		return
	var boss: LevelSlot = EnemyReinforcement.spawn_batch(
		_world_map._world_view, 3, anchor, CLIMAX_BOSS_SPAWN_RANGE
	)
	if boss == null:
		push_warning("ExplorationCoordinator._check_climax_trigger: boss spawn 失败（锚点附近无空地），不标记 climax 以便下次扎营重试")
		return
	boss.is_climax_boss = true
	RunState.mark_climax_triggered()
	# 最小来袭预警事件（视觉/叙事包装留设计 §8 P1）
	_world_map._event_panel.push_event(_build_reward_event("强敌来袭", "末日的钟声已经敲响——一支强敌正向你逼近，决战在即。"))


## M6 扎营结算：ProductionSystem.settle_camp + apply_production + 飘字
## RNG 使用 _world_rng 保证同 seed 运行结果可复现
## 背包满 / 池空等失败条目另行通过 format_dropped_text 提示，避免"飘字说获得实际没有"的误导
func _settle_persistent_camp_production() -> void:
	if _world_map._schema == null or _world_map._unit == null:
		return
	var results: Array = ProductionSystem.settle_camp(
		_world_map._unit.position, Faction.PLAYER, _world_map._schema.persistent_slots, _world_map._world_rng
	)
	if results.is_empty():
		return
	var wm: WorldMap = _world_map  # 闭包内便于 lambda 访问
	var add_supply: Callable = func(amount: int) -> void: wm._supply += amount
	var add_stone_cb: Callable = func(amount: int) -> void: wm.add_stone(Faction.PLAYER, amount)
	# 背包入库返回是否成功（满时返回 false 供 apply_production 归 dropped）
	var add_item_cb: Callable = func(item: ItemData) -> bool:
		var n: int = wm._inventory.add_items([item])
		return n > 0
	var outcome: Dictionary = ProductionSystem.apply_production(
		results, add_supply, add_stone_cb, add_item_cb
	)

	var applied: Array = outcome.get("applied", []) as Array
	var dropped: Array = outcome.get("dropped", []) as Array
	# F MVP：成功条目走事件面板（每条产出独立事件，符合 §3 / §7 场景 2 逐条呈现预期）
	# 失败条目（背包满 / 池空）属于错误反馈，仍走 _show_notice 飘字
	#
	# 入口 2 MVP 2.3（2026-05-11）：narrative 走 NarrativeProvider 池抽取
	# 整次扎营单一 scenario:玩家位置一次性判定,所有 entry 共用同一情境(野外/村庄/城镇)
	if not applied.is_empty():
		var camp_info: Dictionary = _resolve_camp_scenario()
		var camp_scenario: String = String(camp_info.get("scenario", "camp_wild"))
		var slot_name: String = String(camp_info.get("slot_name", ""))
		for entry in applied:
			var entry_dict: Dictionary = entry as Dictionary
			var item_count: Dictionary = _entry_to_item_count(entry_dict)
			var ctx: Dictionary = {
				"leader_name": _world_map._player_lifecycle.current_leader_name(),
				"item": item_count["item"],
				"count": item_count["count"],
			}
			if camp_scenario != "camp_wild":
				ctx["slot_name"] = slot_name
			var narrative: String = NarrativeProvider.pick(camp_scenario, ctx)
			# _build_reward_event 阶段 f 抽出后改 self 调
			_world_map._event_panel.push_event(_build_reward_event("扎营产出", narrative))
	if not dropped.is_empty():
		_world_map._show_notice("扎营产出部分失败：%s" % ProductionSystem.format_dropped_text(dropped))


## 解析当前扎营场景（优先级 TOWN > VILLAGE > WILD）
##
## 优先级:TOWN > VILLAGE > WILD(玩家位置同时在多个 slot 范围内时取最高级)
## slot_name 取该次判定命中的同类型 slot 中曼哈顿距离最近的 display_id
##
## 主会话补做（设计文档漏列）：批 3 阶段 c 顺带迁入（仅扎营相关，与扎营流程同生命周期）
func _resolve_camp_scenario() -> Dictionary:
	var result: Dictionary = {"scenario": "camp_wild", "slot_name": ""}
	if _world_map._schema == null or _world_map._unit == null:
		return result
	# OccupationSystem.slots_covering 返回无类型 Array;不能直接赋给 Array[PersistentSlot]
	# 用 Array 接收 + 循环内 cast,符合项目类型化规范(避免 LSP 报错)
	var covered: Array = OccupationSystem.slots_covering(
		_world_map._unit.position, Faction.PLAYER, _world_map._schema.persistent_slots
	)
	# 过滤玩家方 + 分类
	var towns: Array[PersistentSlot] = []
	var villages: Array[PersistentSlot] = []
	for entry in covered:
		var slot: PersistentSlot = entry as PersistentSlot
		if slot == null or slot.owner_faction != Faction.PLAYER:
			continue
		if slot.type == PersistentSlot.Type.TOWN:
			towns.append(slot)
		elif slot.type == PersistentSlot.Type.VILLAGE:
			villages.append(slot)
	# 取曼哈顿距离最近的 slot 为 slot_name 来源
	var wm: WorldMap = _world_map
	var pick_nearest: Callable = func(slots: Array[PersistentSlot]) -> PersistentSlot:
		var best: PersistentSlot = null
		var best_dist: int = 99999
		for s in slots:
			var d: int = absi(wm._unit.position.x - s.position.x) + absi(wm._unit.position.y - s.position.y)
			if d < best_dist:
				best_dist = d
				best = s
		return best
	if not towns.is_empty():
		result["scenario"] = "camp_town"
		var nearest: PersistentSlot = pick_nearest.call(towns)
		if nearest != null:
			result["slot_name"] = nearest.display_id
	elif not villages.is_empty():
		result["scenario"] = "camp_village"
		var nearest: PersistentSlot = pick_nearest.call(villages)
		if nearest != null:
			result["slot_name"] = nearest.display_id
	return result


## L1.2 Phase 1：据点选定判定 —— 命中条件全满足时 push 据点确认 event 到 EventPanelUI 队列
##
## 命中条件（设计 §4.1）：
##   ① RunState.has_stronghold() == false（MVP 一次性，已有据点不再问）
##   ② 玩家当前扎营覆盖到玩家方 TOWN / VILLAGE 持久 slot（不在野外设据点）
##   ③ 该 slot owner == PLAYER（②已隐含；_find_camp_stronghold_candidate 内兜底过滤）
##
## 命中 → push 一个带 actions=[是 / 暂不] + result_callback 的 event；选"是"回调执行升级 + set_stronghold
func _resolve_stronghold_prompt() -> void:
	# 守卫①：已有据点不再问
	if RunState.has_stronghold():
		return
	# 守卫②③：找当前扎营覆盖的最近玩家方持久 slot（无 → 野外扎营，不弹）
	var candidate: PersistentSlot = _find_camp_stronghold_candidate()
	if candidate == null:
		return

	var slot_name: String = candidate.display_id if candidate.display_id != "" else candidate.get_map_label()
	var candidate_pos: Vector2i = candidate.position
	var wm: WorldMap = _world_map
	# 选"是"回调：升级 slot → 写 RunState（触发 sink，Phase 2 视野绑定）→ 重绘据点徽记
	# 闭包捕获 candidate_pos（值类型 Vector2i，安全）；用 position 查 schema slots（避免直接持 slot 引用跨帧）
	var on_result: Callable = func(result: String, _payload: Dictionary) -> void:
		if result != "set_stronghold":
			return  # 选"暂不"：noop，下次扎营再问
		if wm._schema == null:
			return
		var ok: bool = PersistentSlotGenerator.upgrade_slot_to_stronghold(wm._schema.persistent_slots, candidate_pos)
		if not ok:
			push_warning("EC._resolve_stronghold_prompt: 升级据点失败（pos=%s 无玩家方 slot）" % str(candidate_pos))
			return
		RunState.set_stronghold(candidate_pos)
		# 据点徽记 / 金边即时可见
		if wm._renderer != null:
			wm._renderer.queue_redraw()

	var event: Dictionary = {
		"type": "stronghold_confirm",
		"title": "设为据点？",
		"narrative": "「%s」可作为你的据点。\n据点是昏迷后的复活锚点，并持续照亮周围区域。\n设为据点后，本局无法更换。" % slot_name,
		"actions": [
			{"label": "设为据点", "result": "set_stronghold"},
			{"label": "暂不", "result": "skip"},
		],
		"payload": {},
		"result_callback": on_result,
	}
	_world_map._event_panel.push_event(event)


## L1.2 Phase 1：找当前扎营覆盖的最近玩家方持久 slot 实例（据点候选）
##
## 与 _resolve_camp_scenario 同源（slots_covering + 玩家方过滤），但返回 slot 实例本身
## （_resolve_camp_scenario 只返回 {scenario, slot_name}，不足以拿来 upgrade）。
## 取曼哈顿距离最近的玩家方 TOWN / VILLAGE；无则返回 null（野外扎营）
func _find_camp_stronghold_candidate() -> PersistentSlot:
	if _world_map._schema == null or _world_map._unit == null:
		return null
	# slots_covering 返回无类型 Array；用 Array 接收 + 循环 cast（项目类型化规范）
	var covered: Array = OccupationSystem.slots_covering(
		_world_map._unit.position, Faction.PLAYER, _world_map._schema.persistent_slots
	)
	var best: PersistentSlot = null
	var best_dist: int = 99999
	for entry in covered:
		var slot: PersistentSlot = entry as PersistentSlot
		if slot == null or slot.owner_faction != Faction.PLAYER:
			continue
		# 仅 TOWN / VILLAGE 可设据点（CORE_TOWN 已是据点 / 敌方核心；野外无 slot）
		if slot.type != PersistentSlot.Type.TOWN and slot.type != PersistentSlot.Type.VILLAGE:
			continue
		var d: int = absi(_world_map._unit.position.x - slot.position.x) + absi(_world_map._unit.position.y - slot.position.y)
		if d < best_dist:
			best_dist = d
			best = slot
	return best


## 入口 2 MVP 2.3（2026-05-11）：把 ProductionSystem entry 转为 {item, count} 字典
##
## entry 字段结构因 kind 不同:
##   KIND_RESOURCE: resource_type / amount → 取 ResourceSlot.RESOURCE_TYPE_NAMES + amount
##   KIND_STONE:    amount → "石料" + amount
##   KIND_ITEM:     item: ItemData → display_name + stack_count
##   其他:          fallback "物资" / 1
##
## 主会话补做（设计文档漏列）：批 3 阶段 c 顺带迁入（扎营 + 阶段 f 奖励工厂共用）
func _entry_to_item_count(entry: Dictionary) -> Dictionary:
	var kind: String = String(entry.get("kind", ""))
	match kind:
		ProductionSystem.KIND_RESOURCE:
			var res_type: int = int(entry.get("resource_type", 0))
			var name: String = ResourceSlot.RESOURCE_TYPE_NAMES.get(res_type, "?") as String
			return {"item": name, "count": int(entry.get("amount", 0))}
		ProductionSystem.KIND_STONE:
			return {"item": "石料", "count": int(entry.get("amount", 0))}
		ProductionSystem.KIND_ITEM:
			var item: ItemData = entry.get("item") as ItemData
			if item != null:
				return {"item": item.display_name, "count": item.stack_count}
			return {"item": "物资", "count": 1}
		_:
			return {"item": "物资", "count": 1}


# ─────────────────────────────────────
# 阶段 d：资源采集 + 回合结算
# ─────────────────────────────────────

## 尝试采集当前位置的一次性资源点（M6 改造）
## 采集走 M6 等权池：忽略 slot 自身 resource_type / output_amount 配置，
## 统一按 4 项等权随机抽 × 1/2 等权数量。视觉上 slot 仍按生成类型显示（盲盒式）
## 备忘：视觉与采集结果的对齐是后续 UX 回看项，不在 M6 范围内
##
## 调用方：EC._on_move_finished 内 self 调
func try_collect_resource_at(pos: Vector2i) -> void:
	if not _world_map._resource_slots.has(pos):
		return
	var rs: ResourceSlot = _world_map._resource_slots[pos] as ResourceSlot
	if rs.is_collected:
		return
	# M6 等权抽取（单条产出结构）；注入 _world_rng 保证同 seed 复现
	var entry: Dictionary = ProductionSystem.collect_immediate_slot(_world_map._world_rng)
	var wm: WorldMap = _world_map  # 闭包内局部别名
	var add_supply: Callable = func(amount: int) -> void: wm._supply += amount
	var add_stone_cb: Callable = func(amount: int) -> void: wm.add_stone(Faction.PLAYER, amount)
	var add_item_cb: Callable = func(item: ItemData) -> bool:
		var n: int = wm._inventory.add_items([item])
		return n > 0
	var outcome: Dictionary = ProductionSystem.apply_production(
		[entry], add_supply, add_stone_cb, add_item_cb
	)

	rs.is_collected = true
	if _world_map._schema != null:
		_world_map._schema.set_slot(pos.x, pos.y, MapSchema.SlotType.NONE)

	var applied: Array = outcome.get("applied", []) as Array
	var dropped: Array = outcome.get("dropped", []) as Array
	# F MVP：即时 slot 采集走事件面板（与扎营产出同 reward 模板，叙事前缀不同）
	# 池空 / 背包满等失败走 _show_notice，与扎营保持一致
	# 注意：本函数早前已有 var entry，这里循环变量改名避免 shadow 冲突
	# 入口 2 MVP 2.3（2026-05-11）:走 NarrativeProvider resource_slot_pickup 池
	if not applied.is_empty():
		for applied_entry in applied:
			var entry_dict: Dictionary = applied_entry as Dictionary
			# _entry_to_item_count 已在 EC 内（阶段 c 迁入），self 调
			var item_count: Dictionary = _entry_to_item_count(entry_dict)
			var ctx: Dictionary = {
				"leader_name": _world_map._player_lifecycle.current_leader_name(),
				"item": item_count["item"],
				"count": item_count["count"],
			}
			var narrative: String = NarrativeProvider.pick("resource_slot_pickup", ctx)
			# _build_reward_event 阶段 f 抽出后改 self 调
			_world_map._event_panel.push_event(_build_reward_event("采集所获", narrative))
	if not dropped.is_empty():
		_world_map._show_notice("采集失败：%s" % ProductionSystem.format_dropped_text(dropped))
	_world_map._renderer.queue_redraw()


## 玩家回合结束结算流程（M7 迁移）
## 扎营养成确认后调用：发放奖励 → 触发敌方阵营回合（TurnManager.start_faction_turn）
##
## M7 前的 legacy 流程：直接调 _enemy_movement.start_phase 或 end_turn
## M7 新流程：end_faction_turn(PLAYER) → start_faction_turn(ENEMY_1) → EnemyAI 六步 → 回到 PLAYER
##
## 调用方：WorldMap._on_manage_closed 扎营模式分支
func _on_turn_end_settlement() -> void:
	if _world_map._game_finished or _world_map._check_defeat():
		return
	# 发放回合奖励
	if _world_map._reward_generator != null:
		var rewards: Array[ItemData] = _world_map._reward_generator.generate_rewards(
			_world_map._turn_reward_pool_rows, 1, _world_map._turn_reward_count
		)
		if not rewards.is_empty():
			_world_map._inventory.add_items(rewards)
			var reward_text: String = _world_map._format_rewards_text(rewards)
			# F MVP：回合奖励是"一次性整组"奖励，合并到一条事件呈现
			# _build_reward_event 阶段 f 抽出后改 self 调
			_world_map._event_panel.push_event(_build_reward_event(
				"回合奖励", "回合结束清点物资，获得：%s" % reward_text
			))

	# M7 敌方回合触发：end 当前（PLAYER）+ start ENEMY_1
	# start_faction_turn 内部会：TickRegistry.run_ticks（建造 tick / 占据快照）→ 计数 +1 → emit signal
	# signal 被 EnemyAI 接收，执行六步 2-5（步骤 1 已由 TickRegistry 完成）
	#
	# enemy_movement_enabled == false（调试开关）：
	#   仍必须调 start_faction_turn(ENEMY_1) 让 TickRegistry 跑敌方建造 tick / 占据快照，
	#   否则敌方状态冻结；只短路移动阶段（由 start_enemy_move_phase 内部检查开关提前 phase_finished）
	_world_map._turn_manager.end_faction_turn()
	_world_map._turn_manager.current_faction = Faction.ENEMY_1
	_world_map._turn_manager.start_faction_turn(Faction.ENEMY_1)
	# E MVP：切到敌方回合时显式隐藏【攻击】按钮
	# _on_faction_turn_started 仅在 PLAYER 回合刷 _update_hud，敌方阶段不会自动触发刷新
	_world_map._update_explore_action_button()


# ─────────────────────────────────────
# 阶段 e：敌方移动 + 占领（最大风险段）
# ─────────────────────────────────────

## 启动敌方移动阶段（由 EnemyAI 通过 WorldView.start_enemy_move_phase 转发调用）
##
## P0 第二阶段：target_pos 参数已废弃（EnemyMovement._pick_target_for 改为"附近 slot 占领 + 追玩家"双轴）
## 仍传值给保持签名兼容；实际 per-pack 决策不再读取该值（详见 EnemyMovement.gd）
## 无可移动 → 直接触发 phase_finished（走 BC._on_enemy_phase_finished → 回 PLAYER）
##
## MVP-δ 阶段 1（2026-05-15）：EnemyMovement 不再持有 _level_slots / _original_slot_types
## 字典引用，改为通过 _world_view facade 读写。签名相应缩 2 参（旧 9 参 → 新 8 参）。
func start_enemy_move_phase() -> void:
	if _world_map._game_finished or not _world_map._enemy_movement_enabled:
		_world_map._battle_coordinator._on_enemy_phase_finished()
		return
	if _world_map._schema == null:
		push_warning("ExplorationCoordinator.start_enemy_move_phase: schema 未初始化，跳过本回合敌方移动")
		_world_map._battle_coordinator._on_enemy_phase_finished()
		return
	# P0 第二阶段：target_pos 参数 deprecated（保留作签名兼容），EnemyMovement 不再读取
	# 传 _start_pos 仅作占位；per-pack target 由 EnemyMovement._pick_target_for 内部决策
	var legacy_target_pos: Vector2i = _world_map._start_pos
	# E4 注入玩家保护区半径（= _battle_trigger_range）：保护区内格 cost = INF
	# 让敌方寻路自然停在保护区边缘，等敌方阶段末尾扫描触发被动战斗
	_world_map._enemy_movement.start_phase(
		_world_map._schema, _world_map._world_view, _world_map._unit.position, legacy_target_pos,
		_world_map._enemy_movement_points, _world_map._game_finished,
		_world_map._enemy_target_switch_range,
		_world_map._forced_battle_range,
		_world_map._battle_trigger_range
	)


## MVP-δ 阶段 1：敌方关卡移动的原子写提交
##
## 由 WorldView.commit_enemy_move 转发；EnemyMovement._process_next_move 在选定新位置后调用。
## 7 行原子写（原 EnemyMovement.gd L329-L339 整组迁过来）：
##   - _level_slots erase(old) / set(new, level)
##   - level.position = new_pos（mutate LevelSlot 字段）
##   - _schema.set_slot(old, restored_original_type)：恢复 old_pos 原始地形
##   - _original_slot_types erase(old)
##   - 条件 set _original_slot_types[new] = 当前 schema 类型（首次踩到该格才记录）
##   - _schema.set_slot(new, FUNCTION)：把 new_pos 标为 FUNCTION（敌方占用语义）
func _commit_enemy_move(level: LevelSlot, old_pos: Vector2i, new_pos: Vector2i) -> void:
	_world_map._level_slots.erase(old_pos)
	level.position = new_pos
	_world_map._level_slots[new_pos] = level
	# 恢复 old_pos 的原始地形类型（敌方占用时记录的 FUNCTION 标记还原）
	var restored_type: int = _world_map._original_slot_types.get(old_pos, MapSchema.SlotType.NONE) as int
	_world_map._schema.set_slot(old_pos.x, old_pos.y, restored_type as MapSchema.SlotType)
	_world_map._original_slot_types.erase(old_pos)
	if not _world_map._original_slot_types.has(new_pos):
		_world_map._original_slot_types[new_pos] = _world_map._schema.get_slot(new_pos.x, new_pos.y)
	_world_map._schema.set_slot(new_pos.x, new_pos.y, MapSchema.SlotType.FUNCTION)


## MVP-δ 阶段 1：敌方对持久 slot 的占据尝试
##
## 由 WorldView.try_enemy_occupy_persistent_slot 转发；EnemyMovement._try_enemy_occupy_at
## 在移动动画末尾调用。
##
## 流程（原 EnemyMovement.gd L537-L546 迁过来）：
##   - 扫 _schema.persistent_slots 找匹配 pos 的 PersistentSlot
##   - 调 OccupationSystem.try_occupy(ps, faction)
##   - 成功翻转 → _renderer.queue_redraw() 触发重绘（原 EnemyMovement 用 redraw_requested.emit
##     往 WorldMap 转一道；现在直接在 EC 内 redraw，少一次信号往返）
func _try_enemy_occupy_persistent_slot(pos: Vector2i, faction: int) -> void:
	if _world_map._schema == null:
		return
	for entry in _world_map._schema.persistent_slots:
		var ps: PersistentSlot = entry as PersistentSlot
		if ps.position != pos:
			continue
		if OccupationSystem.try_occupy(ps, faction):
			_world_map._renderer.queue_redraw()
		return


# ─────────────────────────────────────
# 阶段 f：Slot 生成 + 奖励工厂 + 回合钩子（批 3 收口）
# ─────────────────────────────────────

## M7 阵营回合开始回调（玩家侧）
## 由 TurnManager.start_faction_turn(PLAYER) 触发，在 TickRegistry 跑完 M4 快照 / M5 建造 tick 后执行
## 职责：重置玩家单位移动力、刷新 HUD、刷新可达范围
##
## 敌方侧（ENEMY_1）由 EnemyAI._on_faction_turn_started 独立处理，两个 handler 按 faction 分流互不干扰
func _on_faction_turn_started(faction: int) -> void:
	# L1.1 阶段 3：视野系统时钟推进（每个 faction 回合开始各 +1）
	# 必须在 PLAYER 分流守卫之前，确保 ENEMY_1 回合也推进时钟
	# 设计：L1.1_视野循环与chunk底座_MVP.md §4.4 "时钟单位是回合（玩家回合 + 敌方回合各算 1）"
	# null 守卫：_vision_system 早期启动 / _MockWorld 测试时跳过
	if _world_map._vision_system != null:
		_vision_turn += 1
		_world_map._vision_system.advance_turn(_vision_turn)

	if faction != Faction.PLAYER:
		return
	# 玩家回合开始：重置单位移动力
	_world_map._unit.current_movement = _world_map._unit.max_movement
	_world_map._update_hud()
	refresh_reachable()


## M4 自阵营回合 tick 回调：快照本势力所属 slot 的 garrison / occupy / influence 状态
## 由 TickRegistry 在 TurnManager.start_faction_turn 中自动触发（M7 迁移后）
func _on_faction_tick(faction: int) -> void:
	if _world_map._schema == null:
		return
	# _build_units_by_pos 留 WM（涉及多字段读，与战斗状态等耦合），跨模块调
	var units_by_pos: Dictionary = _world_map._build_units_by_pos()
	OccupationSystem.snapshot_turn_end(faction, _world_map._schema.persistent_slots, units_by_pos)
	_world_map._renderer.queue_redraw()


## 构造 reward 事件 payload（F MVP §4 reward 模板）
## title / narrative 由调用方组装；本函数只负责套通用结构
## 入库统一在调用方完成，事件仅作叙事呈现，result_callback 留空
func _build_reward_event(title: String, narrative: String) -> Dictionary:
	return {
		"type": "reward",
		"title": title,
		"narrative": narrative,
		"actions": [{"label": "确认", "result": "confirm"}],
		"payload": {},
	}


## 战斗胜利事件 helper：把关卡奖励 + 部队奖励合并到单条事件
## 用户跑测反馈：战斗一次性获得多个奖励应合并展示，避免连点 N 次确认
## rewards 为空（背包满全丢 / 关卡无奖励）则跳过，不弹空事件
##
## 入口 2 MVP 2.3（2026-05-11）：narrative 走 NarrativeProvider battle_victory 池抽取
## item 占位符 = 合并奖励文本(已含数量,如"草药×2, 盾×1"),不需要 count
##
## 调用方：BattleCoordinator._on_battle_session_ended VICTORY 分支
func push_battle_victory_event(rewards: Array[ItemData]) -> void:
	if rewards.is_empty():
		return
	# _format_rewards_text 留 WM（与 ItemData 显示格式紧），跨模块调
	var reward_text: String = _world_map._format_rewards_text(rewards)
	var ctx: Dictionary = {
		"leader_name": _world_map._player_lifecycle.current_leader_name(),
		"item": reward_text,
	}
	var narrative: String = NarrativeProvider.pick("battle_victory", ctx)
	_world_map._event_panel.push_event(_build_reward_event("战斗胜利", narrative))


## 清除所有资源点（每轮次刷新前调用）
## M1 重构：ResourceSlot 已无持久分支，全部清空并恢复 MapSchema slot 为 NONE；
## 持久 slot 由 PersistentSlot 独立通道维护，不在此处处理
##
## 当前无调用方（可能 cycle 推进重设计时废弃），保留作 P3 候选
func clear_onetime_resource_slots() -> void:
	for pos in _world_map._resource_slots:
		var p: Vector2i = pos as Vector2i
		if _world_map._schema != null:
			_world_map._schema.set_slot(p.x, p.y, MapSchema.SlotType.NONE)
	_world_map._resource_slots = {}


## 从配置生成本轮资源点
##
## 当前无调用方（可能 cycle 推进重设计时废弃），保留作 P3 候选
func generate_resource_slots() -> void:
	if _world_map._schema == null or _world_map._resource_slot_config_rows.is_empty():
		return
	# 构建排除列表
	var exclude: Array[Vector2i] = [_world_map._start_pos, _world_map._end_pos]
	if _world_map._unit != null and not exclude.has(_world_map._unit.position):
		exclude.append(_world_map._unit.position)
	# M2：排除持久 slot 占据的格子，避免一次性资源与城建锚 slot 重叠
	for ps in _world_map._schema.persistent_slots:
		if not exclude.has(ps.position):
			exclude.append(ps.position)
	# 排除本轮已存在的资源点（M1 重构后无持久分支，本循环仍保留以防多次调用复用）
	for pos in _world_map._resource_slots:
		var p: Vector2i = pos as Vector2i
		if not exclude.has(p):
			exclude.append(p)
	# 排除已有关卡位置
	for pos in _world_map._level_slots:
		var p: Vector2i = pos as Vector2i
		if not exclude.has(p):
			exclude.append(p)

	# 按权重从配置中抽取资源点并放置
	# 先计算总数量
	var total_count: int = 0
	for entry in _world_map._resource_slot_config_rows:
		var row: Dictionary = entry as Dictionary
		total_count += int(row.get("count_per_round", "1"))

	# 放置位置（M2 P1#4：注入 _world_rng 保证 seed 复现）
	var placed: Array[Vector2i] = MapGenerator.place_level_slots(_world_map._schema, total_count, exclude, _world_map._world_rng)

	# 按配置行顺序分配位置
	var place_idx: int = 0
	for entry in _world_map._resource_slot_config_rows:
		var row: Dictionary = entry as Dictionary
		var count: int = int(row.get("count_per_round", "1"))
		for i in range(count):
			if place_idx >= placed.size():
				break
			var rs: ResourceSlot = ResourceSlot.new()
			rs.position = placed[place_idx]
			rs.resource_type = int(row.get("resource_type", "0")) as ResourceSlot.ResourceType
			rs.output_amount = int(row.get("output_amount", "1"))
			# M1 重构：is_persistent / effective_range 移除，CSV 同步删列
			_world_map._resource_slots[placed[place_idx]] = rs
			place_idx += 1


## 从敌方部队快照中随机抽取 1 支，转为 TROOP 道具加入背包
## 背包已满时直接丢弃
## F MVP 重构：返回入库成功的 items，由调用方汇总到战斗胜利事件中合并展示
##
## 调用方：BattleCoordinator._on_battle_session_ended VICTORY 分支
func grant_troop_reward(troop_snapshot: Array[TroopData]) -> Array[ItemData]:
	if troop_snapshot.is_empty():
		return [] as Array[ItemData]
	# 随机抽取 1 支敌方部队
	var picked: TroopData = troop_snapshot[randi_range(0, troop_snapshot.size() - 1)]
	# 转为 TROOP 道具
	var item: ItemData = ItemData.new()
	item.type = ItemData.ItemType.TROOP
	item.troop_type = int(picked.troop_type)
	item.quality = int(picked.quality)
	item.display_name = picked.get_display_text()
	item.stack_count = 1
	# 尝试加入背包（满则丢弃）
	var added: int = _world_map._inventory.add_items([item])
	if added > 0:
		return [item] as Array[ItemData]
	return [] as Array[ItemData]


## 发放指定关卡的胜利奖励
## F MVP 重构：返回入库成功的 items，由调用方汇总到战斗胜利事件中合并展示
## MVP 简化：暂不区分 dropped（背包满），与重构前的 _show_notice 行为一致
##
## 调用方：BattleCoordinator._on_battle_session_ended VICTORY 分支
func grant_level_rewards_for(level: LevelSlot) -> Array[ItemData]:
	if level == null or level.rewards.is_empty():
		return [] as Array[ItemData]
	_world_map._inventory.add_items(level.rewards)
	return level.rewards.duplicate()
