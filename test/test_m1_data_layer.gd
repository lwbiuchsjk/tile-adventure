extends SceneTree
## M1 基础数据层 冒烟测试
## 运行：tools/run_godot.ps1 --headless -s test/test_m1_data_layer.gd
##
## 验证范围（对应 M1 验收标准）：
##   1. PersistentSlot 七字段 + 建造槽位 + 在建动作 可构造可读
##   2. BuildAction 三字段 + tick() / is_finished() 行为正确
##   3. Faction 常量 + get_name() / is_hostile() 行为正确
##   4. ResourceSlot 已无 is_persistent / effective_range 字段
##   5. ResourceType 含 STONE 枚举项
##   6. LevelSlot 新增字段（faction / remaining_movement / has_moved_this_turn / ai_cache）可读
##   7. ConfigLoader.load_persistent_slot_config() 返回非空字典且键值齐全
##
## 任意断言失败立即报错并以非 0 退出，便于 CI 接入

var _failed: int = 0


func _init() -> void:
	print("=== M1 数据层冒烟测试 ===")

	_test_faction()
	_test_persistent_slot()
	_test_build_action()
	_test_resource_slot_purified()
	_test_level_slot_extended()
	_test_persistent_slot_config_loader()

	if _failed > 0:
		printerr("✗ 共 %d 项失败" % _failed)
		quit(1)
	else:
		print("✓ 全部通过")
		quit(0)


# ─────────────────────────────────────────
# 测试用例
# ─────────────────────────────────────────

## 验证 Faction 常量与辅助方法
func _test_faction() -> void:
	_assert(Faction.NONE == 0,    "Faction.NONE == 0")
	_assert(Faction.PLAYER == 1,  "Faction.PLAYER == 1")
	_assert(Faction.ENEMY_1 == 2, "Faction.ENEMY_1 == 2")
	_assert(Faction.faction_name(Faction.PLAYER) == "玩家", "Faction.faction_name(PLAYER) == 玩家")
	_assert(Faction.is_hostile(Faction.PLAYER, Faction.ENEMY_1), "PLAYER vs ENEMY_1 应敌对")
	_assert(not Faction.is_hostile(Faction.NONE, Faction.PLAYER), "中立不敌对任何方")
	_assert(not Faction.is_hostile(Faction.PLAYER, Faction.PLAYER), "同方不敌对")


## 验证 PersistentSlot 字段构造与默认值
func _test_persistent_slot() -> void:
	var slot: PersistentSlot = PersistentSlot.new()
	slot.position = Vector2i(3, 5)
	slot.type = PersistentSlot.Type.TOWN
	slot.level = 1
	slot.owner_faction = Faction.PLAYER
	slot.influence_range = 2
	slot.max_range = 3

	# 设计 §三 七字段读写
	_assert(slot.position == Vector2i(3, 5),     "position 写入读出一致")
	_assert(slot.type == PersistentSlot.Type.TOWN, "type 为 TOWN")
	_assert(slot.level == 1,                     "level == 1")
	_assert(slot.owner_faction == Faction.PLAYER, "owner_faction == PLAYER")
	_assert(slot.garrison_turns == 0,            "garrison_turns 默认 0")
	_assert(slot.occupy_turns == 0,              "occupy_turns 默认 0")
	_assert(slot.influence_range == 2,           "influence_range == 2")
	_assert(slot.garrison_unit_growth == 0,      "garrison_unit_growth 默认 0")

	# 建造槽位字段
	_assert(slot.build_slot_count == 1, "build_slot_count MVP 恒为 1")
	_assert(slot.is_build_idle(),       "新建 slot 应处于建造空闲态")
	_assert(not slot.has_active_build(), "新建 slot 无在建动作")

	# 显示辅助
	_assert(slot.get_type_name() == "城镇",  "get_type_name 返回 城镇")
	_assert(slot.get_map_label() == "镇",    "get_map_label 返回 镇")
	_assert(slot.get_owner_name() == "玩家", "get_owner_name 返回 玩家")


## 验证 BuildAction 字段与 tick 行为
func _test_build_action() -> void:
	var act: BuildAction = BuildAction.new()
	act.action_type = BuildAction.ActionType.UPGRADE
	act.target_level = 2
	act.remaining_turns = 2

	_assert(act.action_type == BuildAction.ActionType.UPGRADE, "action_type 为 UPGRADE")
	_assert(act.target_level == 2,    "target_level == 2")
	_assert(act.remaining_turns == 2, "remaining_turns 初始 2")
	_assert(not act.is_finished(),    "remaining_turns > 0 时未完成")

	# tick 一次：剩 1，未完成
	var done1: bool = act.tick()
	_assert(act.remaining_turns == 1, "tick 后 remaining_turns == 1")
	_assert(not done1,                "tick 一次未完成")

	# tick 二次：剩 0，完成
	var done2: bool = act.tick()
	_assert(act.remaining_turns == 0, "tick 两次后 remaining_turns == 0")
	_assert(done2,                    "tick 两次返回完成")
	_assert(act.is_finished(),        "is_finished == true")

	# 已完成后再 tick 不再倒扣
	act.tick()
	_assert(act.remaining_turns == 0, "已完成后 tick 不变负")

	# 与 PersistentSlot 装配
	var slot: PersistentSlot = PersistentSlot.new()
	slot.active_build = act
	_assert(slot.has_active_build(), "装配后 has_active_build == true")
	_assert(not slot.is_build_idle(), "装配后 is_build_idle == false")


## 验证 ResourceSlot 已剥离持久分支
func _test_resource_slot_purified() -> void:
	var rs: ResourceSlot = ResourceSlot.new()

	# 字段层：is_persistent / effective_range 应不存在
	_assert(not (rs as Object).get_property_list().any(
		func(p: Dictionary) -> bool: return p.get("name", "") == "is_persistent"
	), "ResourceSlot 不应含 is_persistent 字段")
	_assert(not (rs as Object).get_property_list().any(
		func(p: Dictionary) -> bool: return p.get("name", "") == "effective_range"
	), "ResourceSlot 不应含 effective_range 字段")

	# ResourceType 应含 STONE
	_assert(ResourceSlot.ResourceType.STONE == 3, "ResourceType.STONE == 3")

	# 标签映射齐全
	_assert(ResourceSlot.RESOURCE_TYPE_NAMES.has(ResourceSlot.ResourceType.STONE),
		"RESOURCE_TYPE_NAMES 含 STONE")
	_assert(ResourceSlot.RESOURCE_MAP_LABELS.has(ResourceSlot.ResourceType.STONE),
		"RESOURCE_MAP_LABELS 含 STONE")


## 验证 LevelSlot 新增字段
func _test_level_slot_extended() -> void:
	var lv: LevelSlot = LevelSlot.new()
	_assert(lv.faction == Faction.NONE,      "LevelSlot.faction 默认 NONE")
	_assert(lv.remaining_movement == 0,      "LevelSlot.remaining_movement 默认 0")
	_assert(lv.has_moved_this_turn == false, "LevelSlot.has_moved_this_turn 默认 false")
	_assert(lv.ai_cache.is_empty(),          "LevelSlot.ai_cache 默认空字典")

	# 写入读出
	lv.faction = Faction.ENEMY_1
	lv.remaining_movement = 3
	lv.has_moved_this_turn = true
	lv.ai_cache["target"] = Vector2i(1, 2)
	_assert(lv.faction == Faction.ENEMY_1,   "faction 写入读出一致")
	_assert(lv.remaining_movement == 3,      "remaining_movement 写入读出一致")
	_assert(lv.has_moved_this_turn == true,  "has_moved_this_turn 写入读出一致")
	_assert(lv.ai_cache.get("target") == Vector2i(1, 2), "ai_cache 写入读出一致")


## 验证 PersistentSlot 配置加载器
func _test_persistent_slot_config_loader() -> void:
	var cfg: Dictionary = ConfigLoader.load_persistent_slot_config()
	_assert(not cfg.is_empty(), "persistent_slot_config 加载后非空")

	# 检查 VILLAGE L1 / TOWN L3 / CORE_TOWN L3 三个关键行
	var key_v1: Vector2i = Vector2i(int(PersistentSlot.Type.VILLAGE), 1)
	var key_t3: Vector2i = Vector2i(int(PersistentSlot.Type.TOWN), 3)
	var key_c3: Vector2i = Vector2i(int(PersistentSlot.Type.CORE_TOWN), 3)
	_assert(cfg.has(key_v1), "配置含 VILLAGE L1 行")
	_assert(cfg.has(key_t3), "配置含 TOWN L3 行")
	_assert(cfg.has(key_c3), "配置含 CORE_TOWN L3 行")

	# 字段齐全
	var row_v1: Dictionary = cfg[key_v1] as Dictionary
	for field in ["initial_range", "max_range", "growth_rate",
			"upgrade_stone_cost", "upgrade_turns", "output_table_key"]:
		_assert(row_v1.has(field), "VILLAGE L1 行含字段: " + field)


# ─────────────────────────────────────────
# 断言辅助
# ─────────────────────────────────────────

## 简易断言：通过打印 ✓，失败打印 ✗ 并计数
func _assert(cond: bool, msg: String) -> void:
	if cond:
		print("  ✓ " + msg)
	else:
		printerr("  ✗ " + msg)
		_failed += 1
