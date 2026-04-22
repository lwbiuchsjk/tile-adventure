extends SceneTree
## M4 占据归属与影响范围 冒烟测试
## 运行：tools/run_godot.ps1 --headless -s test/test_m4_occupation.gd
##
## 验证范围（对应 M4 验收标准）：
##   1. try_occupy 中立翻转 / 同势力不翻转 / 敌我对称翻转
##   2. 翻转时的原子重置（influence_range / garrison_turns / occupy_turns；level 保留）
##   3. 回合末快照：garrison 增长 / influence_range 增长 / max_range 封顶
##   4. 回合末快照：无单位时 garrison 清零、influence_range 不回落
##   5. 回合末快照：occupy_turns 累加；非自势力 slot 不受影响（过滤决策 #2）
##   6. slots_covering 距离过滤 + 势力过滤
##   7. 占据代价钩子占位

var _failed: int = 0


func _init() -> void:
	print("=== M4 占据归属冒烟测试 ===")

	_test_occupy_neutral()
	_test_occupy_same_faction()
	_test_occupy_symmetric()
	_test_atomic_reset_on_flip()
	_test_snapshot_garrison_growth()
	_test_snapshot_no_unit_clears_garrison()
	_test_snapshot_influence_cap()
	_test_snapshot_occupy_turns_accumulate()
	_test_snapshot_filter_by_faction()
	_test_slots_covering()
	_test_cost_hooks()
	_test_guard_null_slot()

	if _failed > 0:
		printerr("✗ 共 %d 项失败" % _failed)
		quit(1)
	else:
		print("✓ 全部通过")
		quit(0)


# ─────────────────────────────────────────
# 用例
# ─────────────────────────────────────────

## 1. 中立 slot 翻转
func _test_occupy_neutral() -> void:
	print("-- 中立翻转")
	var slot: PersistentSlot = _make_slot(Vector2i(5, 5), Faction.NONE, 0, 1, 3, 1)

	var flipped: bool = OccupationSystem.try_occupy(slot, Faction.PLAYER)
	_assert(flipped == true,                          "中立 slot 被占据返回 true")
	_assert(slot.owner_faction == Faction.PLAYER,     "归属切换为 PLAYER")
	_assert(slot.influence_range == slot.initial_range, "影响范围重置为 initial_range")
	_assert(slot.garrison_turns == 0,                 "garrison_turns 清零")
	_assert(slot.occupy_turns == 0,                   "occupy_turns 清零")


## 2. 同势力占据不翻转
func _test_occupy_same_faction() -> void:
	print("-- 同势力不翻转")
	var slot: PersistentSlot = _make_slot(Vector2i(3, 3), Faction.PLAYER, 2, 2, 3, 1)
	slot.garrison_turns = 5
	slot.occupy_turns = 8

	var flipped: bool = OccupationSystem.try_occupy(slot, Faction.PLAYER)
	_assert(flipped == false,                 "同势力 try_occupy 返回 false")
	_assert(slot.influence_range == 2,        "influence_range 不变")
	_assert(slot.garrison_turns == 5,         "garrison_turns 不被重置")
	_assert(slot.occupy_turns == 8,           "occupy_turns 不被重置")


## 3. 敌我对称翻转（玩家 → 敌方 slot；敌方 → 玩家 slot）
func _test_occupy_symmetric() -> void:
	print("-- 敌我对称翻转")
	var s_e: PersistentSlot = _make_slot(Vector2i(1, 1), Faction.ENEMY_1, 1, 2, 3, 1)
	_assert(OccupationSystem.try_occupy(s_e, Faction.PLAYER) == true,  "玩家占敌方 slot 返回 true")
	_assert(s_e.owner_faction == Faction.PLAYER,                        "slot 翻为 PLAYER")

	var s_p: PersistentSlot = _make_slot(Vector2i(2, 2), Faction.PLAYER, 1, 2, 3, 1)
	_assert(OccupationSystem.try_occupy(s_p, Faction.ENEMY_1) == true, "敌方占玩家 slot 返回 true")
	_assert(s_p.owner_faction == Faction.ENEMY_1,                       "slot 翻为 ENEMY_1")


## 4. 原子重置：翻转时 influence_range / garrison / occupy 清零，level 保留
func _test_atomic_reset_on_flip() -> void:
	print("-- 翻转原子重置")
	var slot: PersistentSlot = _make_slot(Vector2i(4, 4), Faction.PLAYER, 2, 2, 3, 1)
	slot.level = 3                    # 等级应保留
	slot.influence_range = 3          # 已达 max，翻转后应重置为 initial
	slot.garrison_turns = 10
	slot.occupy_turns = 15

	var flipped: bool = OccupationSystem.try_occupy(slot, Faction.ENEMY_1)
	_assert(flipped == true,                          "敌方占据返回 true")
	_assert(slot.owner_faction == Faction.ENEMY_1,    "owner 切换")
	_assert(slot.level == 3,                          "level 保留")
	_assert(slot.influence_range == slot.initial_range, "influence_range 重置为 initial_range")
	_assert(slot.garrison_turns == 0,                 "garrison_turns 清零")
	_assert(slot.occupy_turns == 0,                   "occupy_turns 清零")


## 5. 快照：己方单位在己方 slot 上 → garrison 增长、influence +growth_rate
func _test_snapshot_garrison_growth() -> void:
	print("-- 快照 garrison 增长")
	var slot: PersistentSlot = _make_slot(Vector2i(5, 5), Faction.PLAYER, 0, 1, 3, 1)
	var all_slots: Array = [slot]
	var units: Dictionary = {Vector2i(5, 5): Faction.PLAYER}

	OccupationSystem.snapshot_turn_end(Faction.PLAYER, all_slots, units)
	_assert(slot.garrison_turns == 1,      "garrison_turns +1")
	_assert(slot.influence_range == 2,     "influence_range +growth_rate")
	_assert(slot.occupy_turns == 1,        "occupy_turns +1")

	# 再跑一次，确认持续累积
	OccupationSystem.snapshot_turn_end(Faction.PLAYER, all_slots, units)
	_assert(slot.garrison_turns == 2,      "连续快照 garrison_turns +1")
	_assert(slot.influence_range == 3,     "influence_range 再 +1")
	_assert(slot.occupy_turns == 2,        "occupy_turns 再 +1")


## 6. 快照：无单位时 garrison 清零；influence_range 未达 max 前保持（不回落）
func _test_snapshot_no_unit_clears_garrison() -> void:
	print("-- 快照 无单位清零 garrison")
	var slot: PersistentSlot = _make_slot(Vector2i(5, 5), Faction.PLAYER, 0, 1, 3, 1)
	slot.garrison_turns = 4
	slot.influence_range = 2    # 中途值，未达 max

	var all_slots: Array = [slot]
	var units: Dictionary = {}   # 空字典：无任何单位

	OccupationSystem.snapshot_turn_end(Faction.PLAYER, all_slots, units)
	_assert(slot.garrison_turns == 0,      "无单位时 garrison_turns 清零")
	_assert(slot.influence_range == 2,     "influence_range 未达 max 前不回落")
	_assert(slot.occupy_turns == 1,        "occupy_turns 仍累加（归属未变）")


## 7. 快照：influence_range 增长封顶于 max_range；且达 max 后无单位保持不回落
func _test_snapshot_influence_cap() -> void:
	print("-- 快照 influence_range 封顶")
	# initial=1, max=3, growth=2：一次 tick 应从 1 → 3（封顶），不超过
	var slot: PersistentSlot = _make_slot(Vector2i(5, 5), Faction.PLAYER, 0, 1, 3, 2)
	var all_slots: Array = [slot]
	var units: Dictionary = {Vector2i(5, 5): Faction.PLAYER}

	OccupationSystem.snapshot_turn_end(Faction.PLAYER, all_slots, units)
	_assert(slot.influence_range == 3,     "一次 tick 增长到 3 封顶")

	# 再 tick 一次：已达上限，不再增长
	OccupationSystem.snapshot_turn_end(Faction.PLAYER, all_slots, units)
	_assert(slot.influence_range == 3,     "已达 max 后不继续增长")

	# 单位离开：garrison 清零，influence_range 保持 max（达 max 后不回落）
	OccupationSystem.snapshot_turn_end(Faction.PLAYER, all_slots, {})
	_assert(slot.garrison_turns == 0,      "单位离开 garrison 清零")
	_assert(slot.influence_range == 3,     "达 max 后单位离开 influence_range 保持")


## 8. 快照：occupy_turns 累加（归属稳定时）
func _test_snapshot_occupy_turns_accumulate() -> void:
	print("-- 快照 occupy_turns 累加")
	var slot: PersistentSlot = _make_slot(Vector2i(7, 7), Faction.PLAYER, 0, 1, 3, 1)
	var all_slots: Array = [slot]
	# 无单位，但归属稳定
	for _i in range(5):
		OccupationSystem.snapshot_turn_end(Faction.PLAYER, all_slots, {})
	_assert(slot.occupy_turns == 5,       "5 次快照 occupy_turns == 5")


## 9. 快照过滤：非自势力 slot 完全不受影响（核心决策 #2）
func _test_snapshot_filter_by_faction() -> void:
	print("-- 快照按势力过滤")
	var s_player: PersistentSlot = _make_slot(Vector2i(1, 1), Faction.PLAYER, 0, 1, 3, 1)
	var s_enemy: PersistentSlot = _make_slot(Vector2i(8, 8), Faction.ENEMY_1, 0, 1, 3, 1)
	var s_neutral: PersistentSlot = _make_slot(Vector2i(4, 4), Faction.NONE, 0, 1, 3, 1)

	var all_slots: Array = [s_player, s_enemy, s_neutral]
	var units: Dictionary = {
		Vector2i(1, 1): Faction.PLAYER,
		Vector2i(8, 8): Faction.ENEMY_1,
	}

	# PLAYER 回合 tick：只影响 s_player
	OccupationSystem.snapshot_turn_end(Faction.PLAYER, all_slots, units)
	_assert(s_player.occupy_turns == 1,   "PLAYER tick: s_player occupy +1")
	_assert(s_player.garrison_turns == 1, "PLAYER tick: s_player garrison +1")
	_assert(s_player.influence_range == 2,"PLAYER tick: s_player range +1")

	_assert(s_enemy.occupy_turns == 0,    "PLAYER tick: 敌方 slot 不受影响")
	_assert(s_enemy.garrison_turns == 0,  "PLAYER tick: 敌方 garrison 不动")
	_assert(s_enemy.influence_range == 1, "PLAYER tick: 敌方 range 不动")

	_assert(s_neutral.occupy_turns == 0,  "PLAYER tick: 中立 slot 不受影响")

	# ENEMY_1 回合 tick：只影响 s_enemy
	OccupationSystem.snapshot_turn_end(Faction.ENEMY_1, all_slots, units)
	_assert(s_enemy.occupy_turns == 1,    "ENEMY tick: s_enemy occupy +1")
	_assert(s_enemy.garrison_turns == 1,  "ENEMY tick: s_enemy garrison +1")
	_assert(s_enemy.influence_range == 2, "ENEMY tick: s_enemy range +1")

	_assert(s_player.occupy_turns == 1,   "ENEMY tick: PLAYER slot 不再累加")
	_assert(s_player.garrison_turns == 1, "ENEMY tick: PLAYER garrison 不动")


## 10. slots_covering 距离过滤 + 势力过滤
func _test_slots_covering() -> void:
	print("-- slots_covering 查询")
	var s1: PersistentSlot = _make_slot(Vector2i(5, 5), Faction.PLAYER, 0, 2, 3, 1)
	s1.influence_range = 2    # 覆盖曼哈顿 <= 2 范围
	var s2: PersistentSlot = _make_slot(Vector2i(10, 5), Faction.PLAYER, 0, 1, 3, 1)
	s2.influence_range = 1
	var s_enemy: PersistentSlot = _make_slot(Vector2i(5, 7), Faction.ENEMY_1, 0, 5, 5, 1)
	s_enemy.influence_range = 5   # 敌方范围覆盖到 (5,5)，应被过滤掉

	var all_slots: Array = [s1, s2, s_enemy]

	# 查询 (5, 5)：应命中 s1（距离 0，自己覆盖自己）；敌方 s_enemy 虽也覆盖但过滤掉
	var r1: Array = OccupationSystem.slots_covering(Vector2i(5, 5), Faction.PLAYER, all_slots)
	_assert(r1.size() == 1 and r1[0] == s1, "(5,5) 被 s1 覆盖，敌方 slot 被过滤")

	# 查询 (5, 7)：距离 s1 为 2 命中，距离 s2 为 5+2=7 未命中
	var r2: Array = OccupationSystem.slots_covering(Vector2i(5, 7), Faction.PLAYER, all_slots)
	_assert(r2.size() == 1 and r2[0] == s1, "(5,7) 仅 s1 覆盖")

	# 查询 (10, 5)：命中 s2（距离 0）；s1 距离 5 未命中
	var r3: Array = OccupationSystem.slots_covering(Vector2i(10, 5), Faction.PLAYER, all_slots)
	_assert(r3.size() == 1 and r3[0] == s2, "(10,5) 仅 s2 覆盖")

	# 查询 (0, 0)：远离所有 slot，空数组
	var r4: Array = OccupationSystem.slots_covering(Vector2i(0, 0), Faction.PLAYER, all_slots)
	_assert(r4.is_empty(), "远距离查询返回空")


## 11. 代价钩子：MVP 占位
func _test_cost_hooks() -> void:
	print("-- 代价钩子占位")
	var slot: PersistentSlot = _make_slot(Vector2i(0, 0), Faction.NONE, 0, 1, 3, 1)
	_assert(OccupationSystem.can_pay_occupation_cost(slot, Faction.PLAYER) == true,
		"can_pay_occupation_cost MVP 恒 true")
	# pay_occupation_cost 无返回值，只验证不抛错
	OccupationSystem.pay_occupation_cost(slot, Faction.PLAYER)
	_assert(true, "pay_occupation_cost 空实现不抛错")


## 12. 防御性：slot == null / faction == NONE 不崩溃
func _test_guard_null_slot() -> void:
	print("-- 防御性守卫")
	# slot == null：push_warning 但不 crash，返回 false
	_assert(OccupationSystem.try_occupy(null, Faction.PLAYER) == false,
		"slot 为 null 返回 false")

	# unit_faction == NONE：中立单位不发起占据
	var slot: PersistentSlot = _make_slot(Vector2i(0, 0), Faction.NONE, 0, 1, 3, 1)
	_assert(OccupationSystem.try_occupy(slot, Faction.NONE) == false,
		"unit_faction == NONE 返回 false")
	_assert(slot.owner_faction == Faction.NONE, "slot 保持中立")

	# snapshot with faction=NONE：直接返回，不遍历
	var s1: PersistentSlot = _make_slot(Vector2i(1, 1), Faction.PLAYER, 0, 1, 3, 1)
	s1.occupy_turns = 3
	OccupationSystem.snapshot_turn_end(Faction.NONE, [s1], {})
	_assert(s1.occupy_turns == 3, "faction=NONE 快照不改变任何 slot")


# ─────────────────────────────────────────
# 辅助
# ─────────────────────────────────────────

## 构造测试用 PersistentSlot
## level_val 独立于 initial/max，便于验证 level 保留
func _make_slot(pos: Vector2i, owner: int, level_val: int,
		initial: int, max_val: int, growth: int) -> PersistentSlot:
	var s: PersistentSlot = PersistentSlot.new()
	s.position = pos
	s.owner_faction = owner
	s.level = level_val
	s.initial_range = initial
	s.max_range = max_val
	s.growth_rate = growth
	s.influence_range = initial
	s.garrison_turns = 0
	s.occupy_turns = 0
	return s


## 简易断言
func _assert(cond: bool, msg: String) -> void:
	if cond:
		print("  ✓ " + msg)
	else:
		printerr("  ✗ " + msg)
		_failed += 1
