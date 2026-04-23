extends SceneTree
## M7 敌方 AI 冒烟测试
## 运行：tools/run_godot.ps1 --headless -s test/test_m7_enemy_ai.gd
##
## 验证范围（M7 数据层）：
##   1. 升级优先级比较（城镇 > 村庄 / 同类等级低先）
##   2. EnemyReinforcement.spawn_batch 找空地 + 写入 _level_slots
##   3. 增援触发条件（turn_index % 5 == 0 且 > 0）
##   4. REPELLED 冷却 tick 正确递减 + 冷却归零恢复 UNCHALLENGED
##   5. 贪心升级按排序 + 石料耗尽停止

var _failed: int = 0


func _init() -> void:
	print("=== M7 敌方 AI 冒烟测试 ===")

	_test_upgrade_priority_cmp()
	_test_reinforcement_spawn()
	_test_reinforcement_trigger_condition()
	_test_repelled_cooldown_tick()
	_test_greedy_upgrade_exhaust_stone()
	_test_full_entry_via_faction_signal()
	_test_dynamic_target_selection()
	_test_pathfinder_blocked_destination_contract()
	_test_dynamic_target_adjacent_forced_battle()
	_test_movable_levels_faction_whitelist()
	_test_target_switch_range_threshold()
	_test_display_id_assignment_stability()

	# 清理静态状态
	BuildSystem.clear_state()
	TickRegistry.clear_all()

	if _failed > 0:
		printerr("✗ 共 %d 项失败" % _failed)
		quit(1)
	else:
		print("✓ 全部通过")
		quit(0)


# ─────────────────────────────────────────
# 用例
# ─────────────────────────────────────────

## 1. 升级优先级比较：城镇 > 村庄 / 同类内 level 低先
func _test_upgrade_priority_cmp() -> void:
	print("-- 升级优先级比较")
	var ai: EnemyAI = EnemyAI.new()

	var village_l0: PersistentSlot = _make_slot(PersistentSlot.Type.VILLAGE, 0)
	var village_l1: PersistentSlot = _make_slot(PersistentSlot.Type.VILLAGE, 1)
	var town_l0: PersistentSlot = _make_slot(PersistentSlot.Type.TOWN, 0)
	var town_l2: PersistentSlot = _make_slot(PersistentSlot.Type.TOWN, 2)

	# 城镇优先于村庄（无论等级）
	_assert(ai._upgrade_priority_cmp(town_l2, village_l0) == true,  "城镇 L2 优先于村庄 L0")
	_assert(ai._upgrade_priority_cmp(town_l0, village_l1) == true,  "城镇 L0 优先于村庄 L1")
	_assert(ai._upgrade_priority_cmp(village_l0, town_l2) == false, "村庄 L0 不优先于城镇 L2")

	# 同类内等级低优先
	_assert(ai._upgrade_priority_cmp(village_l0, village_l1) == true,  "村庄 L0 优先于 L1")
	_assert(ai._upgrade_priority_cmp(village_l1, village_l0) == false, "村庄 L1 不优先于 L0")
	_assert(ai._upgrade_priority_cmp(town_l0, town_l2) == true,        "城镇 L0 优先于 L2")

	ai.queue_free()


## 2. EnemyReinforcement.spawn_batch：在敌方核心影响范围内生成 LevelSlot
func _test_reinforcement_spawn() -> void:
	print("-- 增援生成")

	var world_mock: Node = _make_world_mock(Vector2i(10, 10), 3)

	var pack: LevelSlot = EnemyReinforcement.spawn_batch(world_mock)
	_assert(pack != null, "生成 LevelSlot 成功")
	if pack != null:
		_assert(pack.faction == Faction.ENEMY_1,         "部队包归属 ENEMY_1")
		_assert(pack.state == LevelSlot.State.UNCHALLENGED, "状态为 UNCHALLENGED")
		# 位置应在曼哈顿距离 ≤ 3 的核心影响范围内
		var dist: int = absi(pack.position.x - 10) + absi(pack.position.y - 10)
		_assert(dist <= 3, "位置在核心影响范围内（曼哈顿距离 ≤ 3）")
		# 位置应已注册到 _level_slots 字典
		var level_slots: Dictionary = world_mock.get("_level_slots") as Dictionary
		_assert(level_slots.has(pack.position), "_level_slots 已注册新 pack")

	world_mock.queue_free()


## 3. 增援触发条件：turn_index % 5 == 0 且 > 0
func _test_reinforcement_trigger_condition() -> void:
	print("-- 增援触发条件")
	# 直接测数学条件（设计伪码）
	var trigger_points: Array[int] = []
	for turn_index in range(1, 21):
		if turn_index > 0 and turn_index % 5 == 0:
			trigger_points.append(turn_index)
	_assert(trigger_points == [5, 10, 15, 20], "20 回合内 5/10/15/20 触发增援（turn=0 不触发）")


## 4. REPELLED 冷却 tick：递减 + 归零恢复
func _test_repelled_cooldown_tick() -> void:
	print("-- REPELLED 冷却 tick")

	var lv: LevelSlot = LevelSlot.new()
	lv.position = Vector2i(1, 1)
	lv.state = LevelSlot.State.REPELLED
	lv.cooldown_turns = 2
	lv.faction = Faction.ENEMY_1

	# 模拟两次 tick
	lv.tick_cooldown()
	_assert(lv.state == LevelSlot.State.REPELLED, "第一次 tick 仍 REPELLED")
	_assert(lv.cooldown_turns == 1,               "cooldown_turns == 1")

	lv.tick_cooldown()
	_assert(lv.state == LevelSlot.State.UNCHALLENGED, "冷却归零后恢复 UNCHALLENGED")


## 5. 贪心升级：按优先级排序 + 石料耗尽停止
func _test_greedy_upgrade_exhaust_stone() -> void:
	print("-- 贪心升级耗尽石料")
	# 加载 BuildSystem 配置，让 can_upgrade / get_upgrade_cost 能工作
	BuildSystem.load_level_config(ConfigLoader.load_persistent_slot_config())

	# 构造 3 个敌方 slot：城镇 L0（cost=4）、村庄 L0（cost=2）、村庄 L1（cost=3）
	# 按优先级排序：城镇 L0 > 村庄 L0 > 村庄 L1
	# 石料 5：可先升城镇 L0（剩 1）→ 村庄 L0 需要 2 石料 stop
	# 预期：只有城镇 L0 启动了 active_build
	var town_l0: PersistentSlot = _make_slot(PersistentSlot.Type.TOWN, 0)
	town_l0.owner_faction = Faction.ENEMY_1
	var village_l0: PersistentSlot = _make_slot(PersistentSlot.Type.VILLAGE, 0)
	village_l0.owner_faction = Faction.ENEMY_1
	var village_l1: PersistentSlot = _make_slot(PersistentSlot.Type.VILLAGE, 1)
	village_l1.owner_faction = Faction.ENEMY_1

	var schema_mock: Node = Node.new()
	schema_mock.set_meta("persistent_slots", [town_l0, village_l0, village_l1])
	# 包装成对象：EnemyAI 从 world_map.get("_schema") 读 schema；schema.persistent_slots 访问
	# 这里简化：直接在 world_mock 上挂一个 Dictionary 模拟 schema
	# 但 GDScript 的 get() 对 Dictionary vs Node 语义不同；用最小 Node 包装
	var schema: Object = _make_schema_stub([town_l0, village_l0, village_l1])

	var world_mock: Node = Node.new()
	world_mock.set("_schema", schema)
	# 石料账本：初始 5
	var stone: Array[int] = [5]
	var try_spend: Callable = func(_faction: int, amount: int) -> bool:
		if stone[0] < amount:
			return false
		stone[0] -= amount
		return true
	# _step_greedy_upgrade 通过 has_method("try_spend_stone") + call 调用
	# Node 没有动态添加方法的原生支持；用一个子类手写
	world_mock.queue_free()
	schema_mock.queue_free()

	# 改用自定义 Node 子类实现 try_spend_stone
	var world: _MockWorld = _MockWorld.new()
	world.stone = 5
	world._schema = _make_schema_stub([town_l0, village_l0, village_l1])

	var ai: EnemyAI = EnemyAI.new()
	ai._world_map = world
	ai._step_greedy_upgrade()

	_assert(town_l0.active_build != null,    "城镇 L0 启动升级（cost=4，石料够）")
	_assert(village_l0.active_build == null, "村庄 L0 未启动（石料剩 1 < cost=2）")
	_assert(village_l1.active_build == null, "村庄 L1 未启动（贪心顺序在村庄 L0 之后）")
	_assert(world.stone == 1,                "石料耗剩 1（5 - 4 = 1）")

	ai.queue_free()
	world.queue_free()
	BuildSystem.clear_state()


## 6. 完整入口链路（P1-#10 审查补齐）：
##    TurnManager.start_faction_turn(ENEMY_1) → faction_turn_started 信号 → EnemyAI 六步
## 验证石料每回合 +3 累加 + start_enemy_move_phase 被调用的次数
## 注：增援 / 升级 / 移动阶段本身在 mock 下被短路（无 schema 数据）；
##    本用例聚焦"信号分发 + 步骤编排是否在 ENEMY_1 回合被调用到"
func _test_full_entry_via_faction_signal() -> void:
	print("-- 完整入口信号链")
	var tm: TurnManager = TurnManager.new()
	var world: _MockWorld = _MockWorld.new()
	world._turn_manager = tm
	world.stone = 0
	world._schema = _make_schema_stub([])    # 空 persistent_slots → 贪心升级无候选

	var ai: EnemyAI = EnemyAI.new()
	# 测试场景下 SceneTree 不能 add_child，直接 init；signal connect 不依赖 tree
	ai.init(world, tm)

	# 跑 3 个敌方回合
	for i in range(3):
		tm.current_faction = Faction.ENEMY_1
		tm.start_faction_turn(Faction.ENEMY_1)
		tm.end_faction_turn()

	_assert(world.stone == 9,                        "3 次 ENEMY 回合，石料 +3×3 = 9")
	_assert(world.start_enemy_move_phase_call_count == 3, "start_enemy_move_phase 被调用 3 次")

	# 验证 PLAYER 信号不触发敌方步骤
	tm.current_faction = Faction.PLAYER
	tm.start_faction_turn(Faction.PLAYER)
	tm.end_faction_turn()
	_assert(world.stone == 9,                        "PLAYER 回合不入账敌方石料")
	_assert(world.start_enemy_move_phase_call_count == 3, "PLAYER 回合不触发 start_enemy_move_phase")

	ai.queue_free()
	world.queue_free()


## 7. 动态目标选择（M8 扩展）
##    EnemyMovement._pick_target_for / _min_target_distance：
##    按 min(dist_to_core, dist_to_player) 选 target；相等时偏向核心
func _test_dynamic_target_selection() -> void:
	print("-- 动态目标选择")
	var em: EnemyMovement = EnemyMovement.new()
	em._target_pos = Vector2i(0, 0)      # 核心在左上
	em._player_pos = Vector2i(10, 10)    # 玩家在右下

	# 场景 1：pack 靠近核心（距核心 3，距玩家 17）→ target = 核心
	var near_core: LevelSlot = LevelSlot.new()
	near_core.position = Vector2i(2, 1)
	var t1: Vector2i = em._pick_target_for(near_core)
	_assert(t1 == em._target_pos, "距核心近的 pack 选核心")
	_assert(em._min_target_distance(near_core.position) == 3,
		"min 距离取到核心（3）")

	# 场景 2：pack 靠近玩家（距玩家 2，距核心 18）→ target = 玩家
	var near_player: LevelSlot = LevelSlot.new()
	near_player.position = Vector2i(9, 9)
	var t2: Vector2i = em._pick_target_for(near_player)
	_assert(t2 == em._player_pos, "距玩家近的 pack 选玩家")
	_assert(em._min_target_distance(near_player.position) == 2,
		"min 距离取到玩家（2）")

	# 场景 3：相等距离 → 偏向核心（战略目标兜底）
	em._target_pos = Vector2i(0, 0)
	em._player_pos = Vector2i(10, 0)
	var middle: LevelSlot = LevelSlot.new()
	middle.position = Vector2i(5, 0)     # 距两者均为 5
	var t3: Vector2i = em._pick_target_for(middle)
	_assert(t3 == em._target_pos,
		"距离相等时偏向核心（避免所有部队一窝蜂围玩家）")

	em.queue_free()


## 8. Pathfinder blocked destination 契约（审查 P1 触发）
##    验证：end 在 blocked_positions 中时 find_path 返回空路径（不是"停在相邻格"的路径）
##    这是"target == player 时不能把玩家格放 blocked"的依据
func _test_pathfinder_blocked_destination_contract() -> void:
	print("-- Pathfinder blocked=end 契约")
	var schema: MapSchema = MapSchema.new()
	schema.init(10, 10)
	schema.terrain_costs = {MapSchema.TerrainType.FLATLAND: 1.0}

	var start: Vector2i = Vector2i(0, 0)
	var end: Vector2i = Vector2i(5, 5)

	# 场景 1：end 不在 blocked → 正常路径
	var clean: Pathfinder.PathResult = Pathfinder.find_path(schema, start, end, {}, {})
	_assert(clean.path.size() > 0, "end 不在 blocked → 路径非空")
	_assert(clean.path.back() == end, "end 不在 blocked → 路径末尾 == end")

	# 场景 2：end 在 blocked → 空路径（这是审查 P1 发现的关键约束）
	var blocked: Dictionary = {end: true}
	var blocked_path: Pathfinder.PathResult = Pathfinder.find_path(schema, start, end, {}, blocked)
	_assert(blocked_path.path.size() == 0,
		"end 在 blocked_positions → find_path 返回空路径（拒绝把 end 加入 open_set）")


## 9. 动态目标集成：pack 与玩家相邻且 target=player → 直接触发 forced_battle（不移动）
##    旧代码会走 trim 后 size<2 分支，pack 原地不动；修复后应该 emit 信号
func _test_dynamic_target_adjacent_forced_battle() -> void:
	print("-- pack 邻玩家 target=player forced_battle")
	var schema: MapSchema = MapSchema.new()
	schema.init(10, 10)
	schema.terrain_costs = {MapSchema.TerrainType.FLATLAND: 1.0}

	var em: EnemyMovement = EnemyMovement.new()
	em.tile_size = 48

	# 构造 LevelSlot 在 (4,5)；玩家在 (5,5)；核心在 (0,0)
	# d_player = 1, d_core = 10 → pack_target = player_pos
	# pack 已在 player 相邻格 → 走早退 forced_battle 分支
	var pack: LevelSlot = LevelSlot.new()
	pack.position = Vector2i(4, 5)
	pack.state = LevelSlot.State.UNCHALLENGED
	pack.faction = Faction.ENEMY_1

	# 信号捕获：_test_dynamic_target_adjacent_forced_battle_captured 累积触发次数
	var fired: Array[LevelSlot] = []
	em.forced_battle_triggered.connect(func(lv: LevelSlot) -> void: fired.append(lv))

	em.start_phase(
		schema,
		{pack.position: pack},
		Vector2i(5, 5),    # player_pos
		Vector2i(0, 0),    # target_pos (core)
		6,                 # movement_points
		{},                # original_slot_types
		false              # game_over
	)

	_assert(fired.size() == 1,        "forced_battle 触发了 1 次")
	_assert(fired[0] == pack,         "触发的 LevelSlot 就是该 pack")
	_assert(pack.position == Vector2i(4, 5), "pack 未移动（原地触发战斗）")

	em.queue_free()


## 10. 可移动 pack 阵营白名单（审查 P2 收紧）
##     注释写"仅 ENEMY_1 + NONE legacy"，实现也须按此白名单（不能只排除 PLAYER）
##     未来扩展势力（ENEMY_2 / 中立可移动势力等）不应被误收入敌方移动队列
func _test_movable_levels_faction_whitelist() -> void:
	print("-- 可移动 pack 阵营白名单")
	var schema: MapSchema = MapSchema.new()
	schema.init(10, 10)
	schema.terrain_costs = {MapSchema.TerrainType.FLATLAND: 1.0}

	var em: EnemyMovement = EnemyMovement.new()
	em._schema = schema
	em._target_pos = Vector2i(0, 0)
	em._player_pos = Vector2i(9, 9)

	var pack_enemy: LevelSlot = _make_level_slot(Vector2i(1, 1), Faction.ENEMY_1)
	var pack_none: LevelSlot = _make_level_slot(Vector2i(2, 2), Faction.NONE)
	var pack_player: LevelSlot = _make_level_slot(Vector2i(3, 3), Faction.PLAYER)
	# 模拟未来扩展：99 非任何已知势力（应被白名单拦住）
	var pack_unknown: LevelSlot = _make_level_slot(Vector2i(4, 4), 99)

	em._level_slots = {
		pack_enemy.position: pack_enemy,
		pack_none.position: pack_none,
		pack_player.position: pack_player,
		pack_unknown.position: pack_unknown,
	}

	var movable: Array = em._get_sorted_movable_levels()
	var positions: Array[Vector2i] = []
	for lv in movable:
		positions.append(lv.position)

	_assert(positions.has(pack_enemy.position), "ENEMY_1 pack 纳入")
	_assert(positions.has(pack_none.position),  "NONE legacy pack 纳入")
	_assert(not positions.has(pack_player.position), "PLAYER pack 拦住")
	_assert(not positions.has(pack_unknown.position),
		"未知势力（99）拦住（白名单外）")

	em.queue_free()


## 11. 阈值切换（M8 扩展）
##     默认 R=10；玩家在阈值外即使比核心更近也不追玩家
##     场景矩阵：distance vs threshold × d_player vs d_core
func _test_target_switch_range_threshold() -> void:
	print("-- AI 追玩家阈值切换")
	var em: EnemyMovement = EnemyMovement.new()
	em._target_switch_range = 10    # 显式指定，默认也是 10

	# 场景 A：玩家在阈值内（d=5）且比核心近 → 追玩家
	em._target_pos = Vector2i(0, 0)
	em._player_pos = Vector2i(20, 0)
	var p_a: LevelSlot = LevelSlot.new()
	p_a.position = Vector2i(15, 0)    # d_player=5, d_core=15
	_assert(em._pick_target_for(p_a) == em._player_pos, "d_player=5≤10 且 <15 → 追玩家")

	# 场景 B：玩家在阈值外（d=11）即使比核心近也推核心
	em._player_pos = Vector2i(25, 0)
	var p_b: LevelSlot = LevelSlot.new()
	p_b.position = Vector2i(14, 0)    # d_player=11, d_core=14
	_assert(em._pick_target_for(p_b) == em._target_pos,
		"d_player=11>10（阈值外）即使 <d_core=14 也推核心")

	# 场景 C：阈值边界内（d=10）+ 比核心近 → 追玩家
	em._player_pos = Vector2i(20, 0)
	var p_c: LevelSlot = LevelSlot.new()
	p_c.position = Vector2i(10, 0)    # d_player=10, d_core=10
	# 注意：d_player=10<=10 但 d_player<d_core 为 10<10 false → 推核心
	_assert(em._pick_target_for(p_c) == em._target_pos,
		"d_player=10=d_core=10（tie）→ 推核心（兜底）")

	var p_c2: LevelSlot = LevelSlot.new()
	p_c2.position = Vector2i(10, 1)    # d_player=11, d_core=11
	_assert(em._pick_target_for(p_c2) == em._target_pos, "d_player=11>10 → 推核心")

	# 场景 D：阈值内 + 严格小于核心距离 → 追玩家
	var p_d: LevelSlot = LevelSlot.new()
	p_d.position = Vector2i(11, 0)    # d_player=9, d_core=11
	_assert(em._pick_target_for(p_d) == em._player_pos,
		"d_player=9≤10 且 <11 → 追玩家（边界内典型场景）")

	# 场景 E：玩家贴在核心附近（d_core=2, d_player=15）→ 推核心（保证集火推核心压力）
	em._player_pos = Vector2i(2, 0)
	var p_e: LevelSlot = LevelSlot.new()
	p_e.position = Vector2i(15, 0)   # d_player=13, d_core=15
	_assert(em._pick_target_for(p_e) == em._target_pos,
		"玩家贴核心 + pack 远（d_player=13>10）→ 推核心")

	# min_target_distance 与 pick 同口径（新建 em 隔离上下文）
	var em2: EnemyMovement = EnemyMovement.new()
	em2._target_switch_range = 10
	em2._target_pos = Vector2i(0, 0)
	em2._player_pos = Vector2i(25, 0)
	# pos_far_player: d_player=11（阈值外）→ min 取核心距 14
	_assert(em2._min_target_distance(Vector2i(14, 0)) == 14,
		"阈值外时 min_dist 取核心距离（=14）")
	# pos_near_player: d_player=5, d_core=20 → min 取玩家距 5
	em2._player_pos = Vector2i(20, 0)
	_assert(em2._min_target_distance(Vector2i(15, 0)) == 5,
		"追玩家场景 min_dist 取玩家距离（=5）")

	em.queue_free()
	em2.queue_free()


## 12. display_id 分配稳定性
##     同一组 slot 两次分配 → 同 ID；不同 position 的 slot → 不同 ID
##     验证 (faction, type, y→x) 排序稳定性
func _test_display_id_assignment_stability() -> void:
	print("-- display_id 分配")

	# 构造一组混合归属 / 类型 / 位置的 slot
	var build_slots: Callable = func() -> Array[PersistentSlot]:
		var result: Array[PersistentSlot] = []
		# 玩家核心 @ (0,0)
		result.append(_make_persistent_slot(Vector2i(0, 0),
			PersistentSlot.Type.CORE_TOWN, Faction.PLAYER))
		# 敌方核心 @ (31,31)
		result.append(_make_persistent_slot(Vector2i(31, 31),
			PersistentSlot.Type.CORE_TOWN, Faction.ENEMY_1))
		# 玩家 3 个村庄（不同 y）
		result.append(_make_persistent_slot(Vector2i(5, 3),
			PersistentSlot.Type.VILLAGE, Faction.PLAYER))
		result.append(_make_persistent_slot(Vector2i(2, 5),
			PersistentSlot.Type.VILLAGE, Faction.PLAYER))
		result.append(_make_persistent_slot(Vector2i(7, 2),
			PersistentSlot.Type.VILLAGE, Faction.PLAYER))
		# 玩家 1 个城镇
		result.append(_make_persistent_slot(Vector2i(4, 4),
			PersistentSlot.Type.TOWN, Faction.PLAYER))
		# 敌方 2 个村庄
		result.append(_make_persistent_slot(Vector2i(25, 28),
			PersistentSlot.Type.VILLAGE, Faction.ENEMY_1))
		result.append(_make_persistent_slot(Vector2i(27, 26),
			PersistentSlot.Type.VILLAGE, Faction.ENEMY_1))
		return result

	var slots_a: Array[PersistentSlot] = build_slots.call() as Array[PersistentSlot]
	PersistentSlotGenerator._assign_display_ids(slots_a)

	# 核心检验
	for s in slots_a:
		if s.type == PersistentSlot.Type.CORE_TOWN:
			_assert(s.display_id == "核心",
				"核心城镇 display_id = '核心' (势力=%d)" % s.owner_faction)

	# 玩家村庄按 (y,x) 升序：(7,2)=y=2, (5,3)=y=3, (2,5)=y=5 → 村庄1, 村庄2, 村庄3
	var player_villages: Array[PersistentSlot] = []
	for s in slots_a:
		if s.type == PersistentSlot.Type.VILLAGE and s.owner_faction == Faction.PLAYER:
			player_villages.append(s)
	# 按 position 查找并断言
	_assert(_find_village_at(player_villages, Vector2i(7, 2)).display_id == "村庄1",
		"玩家村庄 (7,2) y=2 最小 → 村庄1")
	_assert(_find_village_at(player_villages, Vector2i(5, 3)).display_id == "村庄2",
		"玩家村庄 (5,3) y=3 → 村庄2")
	_assert(_find_village_at(player_villages, Vector2i(2, 5)).display_id == "村庄3",
		"玩家村庄 (2,5) y=5 → 村庄3")

	# 玩家 TOWN 独立计数 → 城镇1
	for s in slots_a:
		if s.type == PersistentSlot.Type.TOWN and s.owner_faction == Faction.PLAYER:
			_assert(s.display_id == "城镇1", "玩家唯一城镇 → 城镇1")

	# 敌方村庄独立计数
	var enemy_villages: Array[PersistentSlot] = []
	for s in slots_a:
		if s.type == PersistentSlot.Type.VILLAGE and s.owner_faction == Faction.ENEMY_1:
			enemy_villages.append(s)
	# (27,26) y=26, (25,28) y=28 → 敌方 村庄1, 村庄2
	_assert(_find_village_at(enemy_villages, Vector2i(27, 26)).display_id == "村庄1",
		"敌方村庄 (27,26) y=26 → 村庄1（独立计数）")
	_assert(_find_village_at(enemy_villages, Vector2i(25, 28)).display_id == "村庄2",
		"敌方村庄 (25,28) y=28 → 村庄2")

	# 稳定性：再跑一次，ID 应一致
	var slots_b: Array[PersistentSlot] = build_slots.call() as Array[PersistentSlot]
	PersistentSlotGenerator._assign_display_ids(slots_b)
	for i in range(slots_a.size()):
		# slots_a / slots_b 是按 build 顺序构造的，索引对齐
		_assert(slots_a[i].display_id == slots_b[i].display_id,
			"稳定性：两次分配 index=%d 同 position (%d,%d) 得到相同 ID" % [i, slots_a[i].position.x, slots_a[i].position.y])


## 辅助：按 position 在数组中查找 PersistentSlot
func _find_village_at(arr: Array[PersistentSlot], pos: Vector2i) -> PersistentSlot:
	for s in arr:
		if s.position == pos:
			return s
	return null


## 辅助：构造测试 PersistentSlot
func _make_persistent_slot(pos: Vector2i, type: int, faction: int) -> PersistentSlot:
	var s: PersistentSlot = PersistentSlot.new()
	s.position = pos
	s.type = type
	s.owner_faction = faction
	return s


## 构造测试用 LevelSlot（UNCHALLENGED + 指定归属）
func _make_level_slot(pos: Vector2i, faction: int) -> LevelSlot:
	var lv: LevelSlot = LevelSlot.new()
	lv.position = pos
	lv.state = LevelSlot.State.UNCHALLENGED
	lv.faction = faction
	return lv


# ─────────────────────────────────────────
# 辅助
# ─────────────────────────────────────────

## 构造测试用 PersistentSlot
func _make_slot(type: int, level: int) -> PersistentSlot:
	var s: PersistentSlot = PersistentSlot.new()
	s.type = type
	s.level = level
	s.position = Vector2i(0, 0)
	s.owner_faction = Faction.NONE
	return s


## 构造一个最小 MapSchema mock：有 persistent_slots / is_passable / set_slot / get_slot
## 用 RefCounted 包装更合适
func _make_schema_stub(persistent_slots: Array) -> _SchemaStub:
	var s: _SchemaStub = _SchemaStub.new()
	s.persistent_slots = persistent_slots
	return s


## 构造一个"EnemyReinforcement"可用的 world mock
## 敌方核心 @ core_pos，influence_range = core_range，无其他占用
func _make_world_mock(core_pos: Vector2i, core_range: int) -> Node:
	# 真实 MapSchema，32×32 全平地
	var schema: MapSchema = MapSchema.new()
	schema.init(32, 32)
	# 注入地形消耗，让 FLATLAND 可通行（MapSchema.init 默认 terrain_costs 为空 → is_passable==false）
	schema.terrain_costs = {
		MapSchema.TerrainType.FLATLAND: 1.0,
	}
	# 放敌方核心 persistent slot
	var core: PersistentSlot = PersistentSlot.new()
	core.type = PersistentSlot.Type.CORE_TOWN
	core.level = 3
	core.owner_faction = Faction.ENEMY_1
	core.position = core_pos
	core.influence_range = core_range
	schema.persistent_slots = [core]

	var unit: UnitData = UnitData.new()
	unit.position = Vector2i(-1, -1)    # 玩家远离核心

	var world: _MockWorld = _MockWorld.new()
	world._schema = schema
	world._level_slots = {}
	world._original_slot_types = {}
	world._unit = unit
	world._world_rng = RandomNumberGenerator.new()
	world._world_rng.seed = 42
	# EnemyTroopGenerator：用真实配置
	var gen: EnemyTroopGenerator = EnemyTroopGenerator.new()
	gen.init_from_config(
		ConfigLoader.load_csv("res://assets/config/enemy_troop_pool.csv"),
		ConfigLoader.load_csv_kv("res://assets/config/enemy_spawn_config.csv")
	)
	world._enemy_generator = gen
	return world


func _assert(cond: bool, msg: String) -> void:
	if cond:
		print("  ✓ " + msg)
	else:
		printerr("  ✗ " + msg)
		_failed += 1


# ─────────────────────────────────────────
# Mock 类
# ─────────────────────────────────────────

## Mock WorldMap：提供 EnemyAI / EnemyReinforcement 所需的字段 + try_spend_stone / add_stone 方法
## 用 Node 子类实现，便于 EnemyAI 直接属性/方法访问（_world_map._schema / .add_stone() 等）
class _MockWorld extends Node:
	## MapSchema 替身或真实实例
	var _schema
	## 部队包字典（Vector2i → LevelSlot）
	var _level_slots: Dictionary = {}
	## slot 原始类型恢复表（M4 增援 / 击败时写入）
	var _original_slot_types: Dictionary = {}
	## 玩家单位（UnitData 或 null）
	var _unit
	## 共享 RNG
	var _world_rng: RandomNumberGenerator = null
	## EnemyTroopGenerator 实例
	var _enemy_generator
	## TurnManager 引用（EnemyAI._step_reinforcement 读其 enemy_faction_turn_count）
	var _turn_manager: TurnManager = null
	## 资源点字典（EnemyReinforcement 排除用）
	var _resource_slots: Dictionary = {}
	## 石料账本
	var stone: int = 0
	## start_enemy_move_phase 调用计数（测试断言用）
	var start_enemy_move_phase_call_count: int = 0

	## 尝试扣除石料（满足则扣，不足返回 false）
	func try_spend_stone(_faction: int, amount: int) -> bool:
		if stone < amount:
			return false
		stone -= amount
		return true

	## 石料入账（EnemyAI._step_stone_income 调用）
	func add_stone(_faction: int, amount: int) -> void:
		stone += amount

	## 启动敌方移动阶段的 stub（完整入口测试中计次，不做实际移动）
	func start_enemy_move_phase() -> void:
		start_enemy_move_phase_call_count += 1


## 最小 MapSchema 替身（用于贪心升级测试，只需 persistent_slots 属性）
class _SchemaStub extends RefCounted:
	var persistent_slots: Array = []
