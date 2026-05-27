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
	if _world_map._game_finished or _world_map._is_cycle_advancing or _world_map._is_moving or _world_map._is_camping or _world_map._manage_ui.is_open or _world_map._build_panel_ui.is_open or _world_map._event_panel.is_open or _world_map._player_lifecycle.is_in_coma() or _world_map._battle_coordinator.is_in_battle():
		return
	_world_map._is_camping = true
	_world_map._camp_count += 1
	# B 重生周期 MVP：累计本周期扎营次数（C MVP 入队判定的输入）
	# 放在 _camp_count += 1 紧后；advance_cycle 时 RunState 会把这个值 push 入 milestones
	RunState.record_camp()

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
		_world_map._event_panel.push_event(_world_map._build_reward_event("扎营休整", supply_narrative))

	# M6: 持久 slot 扎营结算（玩家侧）
	# 流程：camp_pos 查 C 作用域覆盖 → 逐 slot 按类型 × 作用域覆盖 → 落地到石料 / 补给 / 背包
	_settle_persistent_camp_production()

	# C 重生周期 MVP：扎营产出事件 push 完后再做里程碑检查
	# 顺序意图：玩家心智上"扎营整顿 → 物资产出 → 新人加入"，叙事节奏自然
	# RunState.check_recruit_milestone 内部命中时调 _on_recruit_triggered → push_event
	# 入队事件因此排在扎营产出事件之后，由 EventPanelUI FIFO 依次弹出
	RunState.check_recruit_milestone(_world_map._player_lifecycle.get_team_hero_ids())

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
			_world_map._event_panel.push_event(_world_map._build_reward_event("扎营产出", narrative))
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
			_world_map._event_panel.push_event(_world_map._build_reward_event("采集所获", narrative))
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
			_world_map._event_panel.push_event(_world_map._build_reward_event(
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
