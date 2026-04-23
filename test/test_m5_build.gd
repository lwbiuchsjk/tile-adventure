extends SceneTree
## M5 升级建造系统 冒烟测试
## 运行：tools/run_godot.ps1 --headless -s test/test_m5_build.gd
##
## 验证范围（对应 M5 验收标准的数据层）：
##   1. 配置加载：has_level_config / get_level_config / is_at_cap
##   2. 前置校验：归属 / 有在建 / 等级上限 / 配置存在
##   3. 启动升级：写 active_build（不扣石料，由调用方负责）
##   4. advance_tick：推进 remaining_turns、完成时刷 level / max_range
##   5. 被敌占取消：active_build 清空（通过 OccupationSystem.try_occupy 路径）
##   6. 敌方对称：start_upgrade(ENEMY_1) 能正确启动
##   7. 核心城镇 L3 锁：is_at_cap == true，can_upgrade == false
##   8. cancel_on_takeover 兼容入口

var _failed: int = 0


func _init() -> void:
	print("=== M5 升级建造冒烟测试 ===")
	# 每轮用例前加载配置；clear_state 保证隔离
	_test_config_loading()
	BuildSystem.clear_state()

	_test_is_at_cap_village_town()
	BuildSystem.clear_state()

	_test_is_at_cap_core_town_l3()
	BuildSystem.clear_state()

	_test_can_upgrade_guards()
	BuildSystem.clear_state()

	_test_start_upgrade_basic()
	BuildSystem.clear_state()

	_test_advance_tick_to_finish()
	BuildSystem.clear_state()

	_test_finish_upgrade_refreshes_config()
	BuildSystem.clear_state()

	_test_enemy_symmetric()
	BuildSystem.clear_state()

	_test_cancel_on_takeover_inline_via_try_occupy()
	BuildSystem.clear_state()

	_test_cancel_on_takeover_helper()
	BuildSystem.clear_state()

	_test_influence_range_bottom_bound_on_upgrade()
	BuildSystem.clear_state()

	_test_tick_order_m5_before_m4()
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

## 1. 配置加载：从 CSV 读入后 (type, level) 索引可查
func _test_config_loading() -> void:
	print("-- 配置加载")
	_load_config()

	_assert(BuildSystem.has_level_config(0, 0), "村庄 L0 配置存在")
	_assert(BuildSystem.has_level_config(0, 3), "村庄 L3 配置存在")
	_assert(BuildSystem.has_level_config(1, 2), "城镇 L2 配置存在")
	_assert(BuildSystem.has_level_config(2, 3), "核心城镇 L3 配置存在")

	# 村庄 L0 / 核心 L0-L2 不在配置（core_town 只有 L3）
	_assert(not BuildSystem.has_level_config(2, 0), "核心城镇 L0 不在配置")
	_assert(not BuildSystem.has_level_config(2, 2), "核心城镇 L2 不在配置")

	var v_l1: Dictionary = BuildSystem.get_level_config(0, 1)
	_assert(int(v_l1.get("initial_range", -1)) == 1, "村庄 L1 initial_range == 1")
	_assert(int(v_l1.get("upgrade_stone_cost", -1)) == 3, "村庄 L1 → L2 消耗 3 石料")


## 2. is_at_cap：村庄 / 城镇 L3 为上限
func _test_is_at_cap_village_town() -> void:
	print("-- 村庄 / 城镇上限")
	_load_config()

	var v_l0: PersistentSlot = _make_slot(PersistentSlot.Type.VILLAGE, 0)
	var v_l3: PersistentSlot = _make_slot(PersistentSlot.Type.VILLAGE, 3)
	_assert(not BuildSystem.is_at_cap(v_l0), "村庄 L0 非上限")
	_assert(BuildSystem.is_at_cap(v_l3), "村庄 L3 已是上限")

	var t_l2: PersistentSlot = _make_slot(PersistentSlot.Type.TOWN, 2)
	var t_l3: PersistentSlot = _make_slot(PersistentSlot.Type.TOWN, 3)
	_assert(not BuildSystem.is_at_cap(t_l2), "城镇 L2 非上限")
	_assert(BuildSystem.is_at_cap(t_l3), "城镇 L3 已是上限")


## 3. 核心城镇 L3 锁：is_at_cap == true
func _test_is_at_cap_core_town_l3() -> void:
	print("-- 核心城镇 L3 锁")
	_load_config()

	var core: PersistentSlot = _make_slot(PersistentSlot.Type.CORE_TOWN, 3)
	_assert(BuildSystem.is_at_cap(core), "核心城镇 L3 is_at_cap == true")
	_assert(not BuildSystem.can_upgrade(core, Faction.PLAYER), "核心城镇 L3 can_upgrade == false")


## 4. can_upgrade 前置校验：归属 / 在建 / 上限
func _test_can_upgrade_guards() -> void:
	print("-- can_upgrade 前置")
	_load_config()

	# 非我方归属
	var s_neutral: PersistentSlot = _make_slot(PersistentSlot.Type.VILLAGE, 1)
	s_neutral.owner_faction = Faction.NONE
	_assert(not BuildSystem.can_upgrade(s_neutral, Faction.PLAYER), "中立 slot 不可升级")

	# 敌方归属
	var s_enemy: PersistentSlot = _make_slot(PersistentSlot.Type.VILLAGE, 1)
	s_enemy.owner_faction = Faction.ENEMY_1
	_assert(not BuildSystem.can_upgrade(s_enemy, Faction.PLAYER), "敌方 slot 不可被玩家升级")

	# 有在建
	var s_building: PersistentSlot = _make_slot(PersistentSlot.Type.VILLAGE, 1)
	s_building.owner_faction = Faction.PLAYER
	s_building.active_build = BuildAction.new()
	_assert(not BuildSystem.can_upgrade(s_building, Faction.PLAYER), "有在建不可再升级")

	# 正常可升级
	var s_ok: PersistentSlot = _make_slot(PersistentSlot.Type.VILLAGE, 1)
	s_ok.owner_faction = Faction.PLAYER
	_assert(BuildSystem.can_upgrade(s_ok, Faction.PLAYER), "归属 + 空闲 + 非上限 可升级")


## 5. 启动升级：写 active_build（不扣石料）
func _test_start_upgrade_basic() -> void:
	print("-- 启动升级")
	_load_config()

	var slot: PersistentSlot = _make_slot(PersistentSlot.Type.VILLAGE, 1)
	slot.owner_faction = Faction.PLAYER

	var ok: bool = BuildSystem.start_upgrade(slot, Faction.PLAYER)
	_assert(ok == true, "启动成功返回 true")
	_assert(slot.active_build != null, "active_build 已写入")
	_assert(slot.active_build.target_level == 2, "target_level == 2")
	_assert(slot.active_build.remaining_turns == 1, "remaining_turns == 1（配置）")
	_assert(slot.active_build.action_type == BuildAction.ActionType.UPGRADE, "action_type == UPGRADE")

	# 再启动一次应失败（已在建）
	var ok2: bool = BuildSystem.start_upgrade(slot, Faction.PLAYER)
	_assert(ok2 == false, "在建中启动返回 false")


## 6. advance_tick：推进到完成
func _test_advance_tick_to_finish() -> void:
	print("-- tick 推进到完成")
	_load_config()

	var slot: PersistentSlot = _make_slot(PersistentSlot.Type.VILLAGE, 1)
	slot.owner_faction = Faction.PLAYER
	BuildSystem.start_upgrade(slot, Faction.PLAYER)

	# MVP upgrade_turns=1：一次 tick 即完成
	var finished: bool = BuildSystem.advance_tick(slot)
	_assert(finished == true, "一次 tick 完成")
	_assert(slot.level == 2, "level 升至 2")
	_assert(slot.active_build == null, "active_build 清空")

	# 再 tick 无动作：返回 false
	var noop: bool = BuildSystem.advance_tick(slot)
	_assert(noop == false, "空转 tick 返回 false")


## 7. 完成升级刷新 initial / max / growth 字段
func _test_finish_upgrade_refreshes_config() -> void:
	print("-- 完成升级刷新配置字段")
	_load_config()

	# 村庄 L2 → L3：按 CSV，L3 的 max_range=3（L2 为 2），growth_rate=1
	var slot: PersistentSlot = _make_slot(PersistentSlot.Type.VILLAGE, 2)
	slot.owner_faction = Faction.PLAYER
	slot.max_range = 2
	slot.initial_range = 2
	slot.growth_rate = 1
	# 模拟玩家已驻扎、influence_range 已长到 2（= max）
	slot.influence_range = 2

	BuildSystem.start_upgrade(slot, Faction.PLAYER)
	BuildSystem.advance_tick(slot)

	_assert(slot.level == 3, "level 升至 3")
	_assert(slot.max_range == 3, "max_range 刷为 L3 配置值 3")
	# influence_range 保持不变（§六 MVP 边界）
	_assert(slot.influence_range == 2, "influence_range 升级瞬间保持不变（不瞬间跃升）")


## 8. 敌方对称：start_upgrade(ENEMY_1) 能正确启动
func _test_enemy_symmetric() -> void:
	print("-- 敌方对称")
	_load_config()

	var slot: PersistentSlot = _make_slot(PersistentSlot.Type.TOWN, 1)
	slot.owner_faction = Faction.ENEMY_1

	var ok: bool = BuildSystem.start_upgrade(slot, Faction.ENEMY_1)
	_assert(ok == true, "敌方启动升级返回 true")
	_assert(slot.active_build.target_level == 2, "target_level == 2")

	# 敌方自阵营 tick 推进
	var finished: bool = BuildSystem.advance_tick(slot)
	_assert(finished == true, "一次 tick 完成")
	_assert(slot.level == 2, "敌方 slot level == 2")


## 9. 被敌占取消（inline 路径）：通过 OccupationSystem.try_occupy
func _test_cancel_on_takeover_inline_via_try_occupy() -> void:
	print("-- 被敌占取消（inline）")
	_load_config()

	var slot: PersistentSlot = _make_slot(PersistentSlot.Type.VILLAGE, 1)
	slot.owner_faction = Faction.PLAYER
	BuildSystem.start_upgrade(slot, Faction.PLAYER)
	_assert(slot.active_build != null, "升级已启动")

	# 敌方占据该 slot
	var flipped: bool = OccupationSystem.try_occupy(slot, Faction.ENEMY_1)
	_assert(flipped == true, "归属翻转成功")
	_assert(slot.owner_faction == Faction.ENEMY_1, "归属切换为 ENEMY_1")
	_assert(slot.active_build == null, "active_build 已清空（M4 inline 处理）")


## 11. influence_range 兜底：升级后若新 initial_range > 当前 influence，兜底到新 initial
##     （P1-2 审查修复）
func _test_influence_range_bottom_bound_on_upgrade() -> void:
	print("-- 升级后 influence_range 兜底")
	_load_config()

	# 场景：村庄 L1 刚被占回，influence=1（old initial），未驻扎；启动升级 L1→L2
	# 新配置 L2: initial=2. 若不兜底，升级后 influence=1 < initial=2 会出现字段矛盾
	var slot: PersistentSlot = _make_slot(PersistentSlot.Type.VILLAGE, 1)
	slot.owner_faction = Faction.PLAYER
	slot.influence_range = 1    # 模拟"刚占回"，未经任何快照增长

	BuildSystem.start_upgrade(slot, Faction.PLAYER)
	BuildSystem.advance_tick(slot)

	_assert(slot.level == 2,               "level 升至 2")
	_assert(slot.initial_range == 2,       "initial_range 刷为新值 2")
	_assert(slot.influence_range == 2,     "influence_range 兜底到新 initial（2）")
	_assert(slot.influence_range >= slot.initial_range, "字段一致性：influence >= initial")

	# 反向场景：当前 influence 已高于新 initial，不应被拉低
	var slot2: PersistentSlot = _make_slot(PersistentSlot.Type.VILLAGE, 2)
	slot2.owner_faction = Faction.PLAYER
	slot2.influence_range = 2    # L2 max，升级到 L3 new initial=2
	BuildSystem.start_upgrade(slot2, Faction.PLAYER)
	BuildSystem.advance_tick(slot2)
	_assert(slot2.influence_range == 2, "influence 已 >= new initial 时保持不变（不回退也不跃升）")


## 12. Tick 注册顺序：M5 先于 M4，保证"升级完成本回合即生效"
##     （P1-1 审查修复：反向顺序会导致新 max_range 延迟 1 回合才参与增长）
func _test_tick_order_m5_before_m4() -> void:
	print("-- Tick 顺序 M5 → M4")
	_load_config()
	TickRegistry.clear_all()

	# 场景：村庄 L2，玩家驻扎，influence 已达 old max=2，本回合启动升级到 L3
	# 预期：本次 run_ticks 期间先完成升级（max_range: 2→3），再做快照（influence: 2→3 命中新 max）
	var slot: PersistentSlot = _make_slot(PersistentSlot.Type.VILLAGE, 2)
	slot.owner_faction = Faction.PLAYER
	slot.influence_range = 2
	slot.garrison_turns = 0
	slot.occupy_turns = 0

	# 假设升级在本回合开始前 1 回合就已启动（remaining=1）
	var action: BuildAction = BuildAction.new()
	action.action_type = BuildAction.ActionType.UPGRADE
	action.target_level = 3
	action.remaining_turns = 1
	slot.active_build = action

	# 模拟 WorldMap._ready 的注册顺序：M5 先，M4 后
	var slots: Array = [slot]
	var units: Dictionary = {Vector2i(0, 0): Faction.PLAYER}

	var build_handler: Callable = func(faction: int) -> void:
		if slot.owner_faction == faction and slot.active_build != null:
			BuildSystem.advance_tick(slot)

	var snapshot_handler: Callable = func(faction: int) -> void:
		OccupationSystem.snapshot_turn_end(faction, slots, units)

	TickRegistry.register(build_handler)       # M5 先注册
	TickRegistry.register(snapshot_handler)    # M4 后注册
	TickRegistry.run_ticks(Faction.PLAYER)

	_assert(slot.level == 3,              "升级完成：level == 3")
	_assert(slot.max_range == 3,          "升级完成：max_range 刷为 3")
	# 关键：影响范围从 2 → 3（用新 max）。若顺序相反，会停在 2
	_assert(slot.influence_range == 3,    "同回合 influence_range 用新 max 增长到 3")
	_assert(slot.garrison_turns == 1,     "快照后 garrison_turns == 1")

	TickRegistry.clear_all()


## 10. cancel_on_takeover 兼容入口
func _test_cancel_on_takeover_helper() -> void:
	print("-- cancel_on_takeover 兼容入口")
	_load_config()

	var slot: PersistentSlot = _make_slot(PersistentSlot.Type.VILLAGE, 1)
	slot.owner_faction = Faction.PLAYER
	BuildSystem.start_upgrade(slot, Faction.PLAYER)
	_assert(slot.active_build != null, "启动后 active_build 非空")

	BuildSystem.cancel_on_takeover(slot)
	_assert(slot.active_build == null, "cancel_on_takeover 后 active_build == null")

	# null 守卫：不抛错
	BuildSystem.cancel_on_takeover(null)
	_assert(true, "null 入参不抛错")


# ─────────────────────────────────────────
# 辅助
# ─────────────────────────────────────────

## 加载 CSV 配置到 BuildSystem
func _load_config() -> void:
	BuildSystem.load_level_config(ConfigLoader.load_persistent_slot_config())


## 构造测试 PersistentSlot，按 (type, level) 回填 initial/max/growth
func _make_slot(type: int, level: int) -> PersistentSlot:
	var s: PersistentSlot = PersistentSlot.new()
	s.type = type
	s.level = level
	s.position = Vector2i(0, 0)
	s.owner_faction = Faction.NONE
	var cfg: Dictionary = BuildSystem.get_level_config(type, level)
	if not cfg.is_empty():
		s.initial_range = int(cfg.get("initial_range", 0))
		s.max_range = int(cfg.get("max_range", 0))
		s.growth_rate = int(cfg.get("growth_rate", 0))
		s.influence_range = s.initial_range
	return s


func _assert(cond: bool, msg: String) -> void:
	if cond:
		print("  ✓ " + msg)
	else:
		printerr("  ✗ " + msg)
		_failed += 1
