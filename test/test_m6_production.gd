extends SceneTree
## M6 产出结算冒烟测试
## 运行：tools/run_godot.ps1 --headless -s test/test_m6_production.gd
##
## 验证范围（对应 M6 验收标准）：
##   1. 即时 slot 采集：4 项等权 × 1/2 数量
##   2. 村庄 L0 固定 1 补给
##   3. 村庄 L1/L2/L3 随机池抽 1/2/2 项
##   4. 城镇 L0/L1/L2/L3 产出 TROOP 道具，按品质阶梯
##   5. 核心城镇套用城镇 L3
##   6. 多 slot 覆盖叠加
##   7. 敌方 faction 不产出（§2.4 MVP）
##   8. apply_production 归属映射（补给 / 石料 / 背包）

var _failed: int = 0


func _init() -> void:
	print("=== M6 产出结算冒烟测试 ===")

	# 前置：加载部队池（城镇产出依赖）
	_load_troop_pool()

	_test_immediate_slot_distribution()
	_test_village_output_by_level()
	_test_town_output_by_level()
	_test_core_town_output()
	_test_multi_slot_stacking()
	_test_enemy_faction_silent()
	_test_apply_production_routing()
	_test_empty_pool_error_entry()
	_test_bag_full_dropped()

	ProductionSystem.clear_state()

	if _failed > 0:
		printerr("✗ 共 %d 项失败" % _failed)
		quit(1)
	else:
		print("✓ 全部通过")
		quit(0)


# ─────────────────────────────────────────
# 用例
# ─────────────────────────────────────────

## 1. 即时 slot：多轮抽取覆盖 4 种资源类型 + 数量在 1/2 区间
func _test_immediate_slot_distribution() -> void:
	print("-- 即时 slot 分布")
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 42

	var types_seen: Dictionary = {}
	var amounts_seen: Dictionary = {}
	for i in range(200):
		var entry: Dictionary = ProductionSystem.collect_immediate_slot(rng)
		var res_type: int = int(entry.get("resource_type", -1))
		var amount: int = int(entry.get("amount", 0))
		types_seen[res_type] = true
		amounts_seen[amount] = true
		_assert(amount >= 1 and amount <= 2, "amount 在 [1,2]")
		# 石料走 KIND_STONE，其他走 KIND_RESOURCE
		var kind: String = entry.get("kind", "") as String
		if res_type == ResourceSlot.ResourceType.STONE:
			_assert(kind == ProductionSystem.KIND_STONE, "石料 kind == stone")
		else:
			_assert(kind == ProductionSystem.KIND_RESOURCE, "非石料 kind == resource")

	_assert(types_seen.has(ResourceSlot.ResourceType.SUPPLY),     "200 次覆盖 SUPPLY")
	_assert(types_seen.has(ResourceSlot.ResourceType.HP_RESTORE), "200 次覆盖 HP_RESTORE")
	_assert(types_seen.has(ResourceSlot.ResourceType.EXP),        "200 次覆盖 EXP")
	_assert(types_seen.has(ResourceSlot.ResourceType.STONE),      "200 次覆盖 STONE")
	_assert(amounts_seen.has(1) and amounts_seen.has(2),          "amount 两值都出现过")


## 2. 村庄各级产出：L0 固定 1 supply；L1/L2/L3 数量分别为 1/2/2
func _test_village_output_by_level() -> void:
	print("-- 村庄各级产出")
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 1

	# L0：固定 1 补给
	var l0_results: Array = _settle_single_slot(
		_make_village(0, Faction.PLAYER, Vector2i(5, 5)), rng
	)
	_assert(l0_results.size() == 1,                                           "L0 产出 1 条")
	_assert(l0_results[0]["kind"] == ProductionSystem.KIND_RESOURCE,          "L0 kind == resource")
	_assert(int(l0_results[0]["resource_type"]) == ResourceSlot.ResourceType.SUPPLY, "L0 固定补给")
	_assert(int(l0_results[0]["amount"]) == 1,                                "L0 固定 1 数量")

	# L1：1 项随机
	var l1_results: Array = _settle_single_slot(
		_make_village(1, Faction.PLAYER, Vector2i(5, 5)), rng
	)
	_assert(l1_results.size() == 1, "L1 产出 1 条")

	# L2 / L3：2 项随机
	var l2_results: Array = _settle_single_slot(
		_make_village(2, Faction.PLAYER, Vector2i(5, 5)), rng
	)
	_assert(l2_results.size() == 2, "L2 产出 2 条")

	var l3_results: Array = _settle_single_slot(
		_make_village(3, Faction.PLAYER, Vector2i(5, 5)), rng
	)
	_assert(l3_results.size() == 2, "L3 产出 2 条（max_range 抬升由 M5 负责，不加量）")


## 3. 城镇各级：L0 仅 R；L1 R/SR；L2/L3 R/SR/SSR
func _test_town_output_by_level() -> void:
	print("-- 城镇各级产出")
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 7

	for level in [0, 1, 2, 3]:
		var qualities_seen: Dictionary = {}
		for i in range(200):
			var results: Array = _settle_single_slot(
				_make_town(level, Faction.PLAYER, Vector2i(5, 5)), rng
			)
			_assert(results.size() == 1, "城镇 L%d 单次产出 1 条" % level)
			var entry: Dictionary = results[0] as Dictionary
			_assert(entry["kind"] == ProductionSystem.KIND_ITEM, "城镇产出 kind == item")
			var item: ItemData = entry["item"] as ItemData
			_assert(item != null, "item 非空")
			_assert(item.type == ItemData.ItemType.TROOP, "产出为 TROOP 类 ItemData")
			qualities_seen[item.quality] = true

		match level:
			0:
				_assert(qualities_seen.size() == 1 and qualities_seen.has(TroopData.Quality.R),
					"L0 仅 R")
			1:
				_assert(not qualities_seen.has(TroopData.Quality.SSR),
					"L1 无 SSR")
				_assert(qualities_seen.has(TroopData.Quality.R),
					"L1 含 R")
				_assert(qualities_seen.has(TroopData.Quality.SR),
					"L1 含 SR")
			_:
				# L2 / L3：R / SR / SSR 全覆盖（200 次够大）
				_assert(qualities_seen.has(TroopData.Quality.R),   "L%d 含 R" % level)
				_assert(qualities_seen.has(TroopData.Quality.SR),  "L%d 含 SR" % level)
				_assert(qualities_seen.has(TroopData.Quality.SSR), "L%d 含 SSR" % level)


## 4. 核心城镇：套城镇 L3（R/SR/SSR）
func _test_core_town_output() -> void:
	print("-- 核心城镇产出")
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 99

	var qualities_seen: Dictionary = {}
	for i in range(200):
		var core: PersistentSlot = _make_core_town(Faction.PLAYER, Vector2i(5, 5))
		var results: Array = _settle_single_slot(core, rng)
		_assert(results.size() == 1,                              "核心产出 1 条")
		var item: ItemData = results[0]["item"] as ItemData
		_assert(item.type == ItemData.ItemType.TROOP,             "核心产出 TROOP")
		qualities_seen[item.quality] = true

	_assert(qualities_seen.has(TroopData.Quality.R),   "核心含 R")
	_assert(qualities_seen.has(TroopData.Quality.SR),  "核心含 SR")
	_assert(qualities_seen.has(TroopData.Quality.SSR), "核心含 SSR")


## 5. 多 slot 同时覆盖：逐个产出，不合并
func _test_multi_slot_stacking() -> void:
	print("-- 多 slot 叠加")
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 3

	# 构造两个都覆盖 (5,5) 的 slot：村庄 L2（2 项） + 城镇 L0（1 项） = 3 条产出
	var v: PersistentSlot = _make_village(2, Faction.PLAYER, Vector2i(5, 5))
	v.influence_range = 3
	var t: PersistentSlot = _make_town(0, Faction.PLAYER, Vector2i(6, 5))
	t.influence_range = 3
	var all_slots: Array = [v, t]

	var results: Array = ProductionSystem.settle_camp(
		Vector2i(5, 5), Faction.PLAYER, all_slots, rng
	)
	_assert(results.size() == 3, "村庄 L2(2) + 城镇 L0(1) = 3 条叠加")


## 6. 敌方侧：即使覆盖到扎营格，也不产出（MVP §2.4）
func _test_enemy_faction_silent() -> void:
	print("-- 敌方静默")
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()

	# 就算覆盖存在，敌方调 settle_camp 也返回空
	var enemy_slot: PersistentSlot = _make_village(2, Faction.ENEMY_1, Vector2i(5, 5))
	enemy_slot.influence_range = 3
	var all_slots: Array = [enemy_slot]

	var results: Array = ProductionSystem.settle_camp(
		Vector2i(5, 5), Faction.ENEMY_1, all_slots, rng
	)
	_assert(results.is_empty(), "敌方 faction 调 settle_camp 返回空")

	# 反向验证：同位置用 PLAYER 但 slot 归属敌方，覆盖被 OccupationSystem.slots_covering 过滤
	var player_results: Array = ProductionSystem.settle_camp(
		Vector2i(5, 5), Faction.PLAYER, all_slots, rng
	)
	_assert(player_results.is_empty(), "玩家扎营但覆盖下只有敌方 slot 时无产出")


## 7. apply_production 归属映射（回调接口）
func _test_apply_production_routing() -> void:
	print("-- 归属映射")
	# 构造一组覆盖三类 kind 的产出
	var item: ItemData = ItemData.new()
	item.type = ItemData.ItemType.TROOP
	item.troop_type = 0
	item.quality = 0
	item.stack_count = 1
	item.display_name = "剑兵(R)"

	var results: Array = [
		{"kind": ProductionSystem.KIND_RESOURCE, "resource_type": ResourceSlot.ResourceType.SUPPLY, "amount": 3},
		{"kind": ProductionSystem.KIND_STONE,    "resource_type": ResourceSlot.ResourceType.STONE,  "amount": 5},
		{"kind": ProductionSystem.KIND_RESOURCE, "resource_type": ResourceSlot.ResourceType.HP_RESTORE, "amount": 2},
		{"kind": ProductionSystem.KIND_RESOURCE, "resource_type": ResourceSlot.ResourceType.EXP,        "amount": 1},
		{"kind": ProductionSystem.KIND_ITEM,     "item": item, "amount": 1},
	]

	var supply_total: Array[int] = [0]
	var stone_total: Array[int] = [0]
	var items_added: Array[ItemData] = []

	var add_supply: Callable = func(amount: int) -> void: supply_total[0] += amount
	var add_stone: Callable = func(amount: int) -> void: stone_total[0] += amount
	var add_item: Callable = func(it: ItemData) -> void: items_added.append(it)

	var add_item_bool: Callable = func(it: ItemData) -> bool:
		items_added.append(it)
		return true
	var outcome: Dictionary = ProductionSystem.apply_production(
		results, add_supply, add_stone, add_item_bool
	)

	_assert(supply_total[0] == 3, "SUPPLY → add_supply 累加 3")
	_assert(stone_total[0] == 5,  "STONE → add_stone 累加 5")
	_assert(items_added.size() == 3, "HP_RESTORE + EXP + TROOP → add_item 三条")
	# 返回值分类：全成功 → applied 5 条（SUPPLY/STONE/HP/EXP/TROOP）、dropped 空
	_assert((outcome.get("applied", []) as Array).size() == 5, "全成功 applied 5 条")
	_assert((outcome.get("dropped", []) as Array).is_empty(),   "全成功 dropped 空")

	# 验证 HP_RESTORE / EXP 转换为正确 ItemData
	var types: Dictionary = {}
	for it in items_added:
		types[it.type] = true
	_assert(types.has(ItemData.ItemType.HP_RESTORE), "HP_RESTORE 物品入库")
	_assert(types.has(ItemData.ItemType.EXP),        "EXP 物品入库")
	_assert(types.has(ItemData.ItemType.TROOP),      "TROOP 物品入库")


## 8. 池空时 _town_output / _core_town_output 返回 KIND_ERROR 条目，apply 归 dropped
func _test_empty_pool_error_entry() -> void:
	print("-- 池空 error 条目")
	# 清空部队池，模拟"配置未加载 / 加载失败"
	ProductionSystem.clear_state()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()

	var slot: PersistentSlot = _make_town(2, Faction.PLAYER, Vector2i(5, 5))
	var results: Array = _settle_single_slot(slot, rng)
	_assert(results.size() == 1,                                "池空仍返回 1 条（error 条目）")
	_assert(results[0]["kind"] == ProductionSystem.KIND_ERROR,   "kind == error")
	_assert((results[0]["message"] as String).contains("产出池缺"), "message 含池空原因")

	# apply_production 把 error 归 dropped
	var dummy_supply: Callable = func(_a: int) -> void: pass
	var dummy_stone: Callable = func(_a: int) -> void: pass
	var dummy_item: Callable = func(_it: ItemData) -> bool: return true
	var outcome: Dictionary = ProductionSystem.apply_production(
		results, dummy_supply, dummy_stone, dummy_item
	)
	_assert((outcome.get("applied", []) as Array).is_empty(), "error 条目不进 applied")
	_assert((outcome.get("dropped", []) as Array).size() == 1, "error 条目进 dropped")

	# 恢复池，后续测试正常
	_load_troop_pool()


## 9. 背包满时 add_item_cb 返回 false，条目归 dropped
func _test_bag_full_dropped() -> void:
	print("-- 背包满 dropped")
	var item: ItemData = ItemData.new()
	item.type = ItemData.ItemType.TROOP
	item.troop_type = 0
	item.quality = 0
	item.stack_count = 1
	item.display_name = "剑兵(R)"

	var results: Array = [
		{"kind": ProductionSystem.KIND_ITEM, "item": item, "amount": 1},
	]
	var dummy_supply: Callable = func(_a: int) -> void: pass
	var dummy_stone: Callable = func(_a: int) -> void: pass
	# 模拟背包满：add_item_cb 始终返回 false
	var full_item_cb: Callable = func(_it: ItemData) -> bool: return false

	var outcome: Dictionary = ProductionSystem.apply_production(
		results, dummy_supply, dummy_stone, full_item_cb
	)
	_assert((outcome.get("applied", []) as Array).is_empty(),   "背包满时 applied 空")
	_assert((outcome.get("dropped", []) as Array).size() == 1,  "背包满时 dropped 1 条")

	var dropped_text: String = ProductionSystem.format_dropped_text(outcome["dropped"])
	_assert(dropped_text.contains("背包满丢弃"), "dropped 文案含\"背包满丢弃\"")


# ─────────────────────────────────────────
# 辅助
# ─────────────────────────────────────────

## 加载城镇部队道具池（独立 CSV，与敌方生成池分离避免权重污染）
func _load_troop_pool() -> void:
	var rows: Array = ConfigLoader.load_csv("res://assets/config/town_troop_pool.csv")
	ProductionSystem.load_troop_pool(rows)


## 构造单 slot 覆盖 camp_pos 的产出
## slot.influence_range 设为足够大以确保覆盖
func _settle_single_slot(slot: PersistentSlot, rng: RandomNumberGenerator) -> Array:
	slot.influence_range = 10    # 足够大确保 (5,5) 被覆盖
	return ProductionSystem.settle_camp(
		Vector2i(5, 5), Faction.PLAYER, [slot], rng
	)


## 构造村庄测试 slot；influence_range 默认大值确保 camp_pos (5,5) 在覆盖内
func _make_village(level: int, faction: int, pos: Vector2i) -> PersistentSlot:
	var s: PersistentSlot = PersistentSlot.new()
	s.type = PersistentSlot.Type.VILLAGE
	s.level = level
	s.owner_faction = faction
	s.position = pos
	s.influence_range = 10
	return s


## 构造城镇测试 slot
func _make_town(level: int, faction: int, pos: Vector2i) -> PersistentSlot:
	var s: PersistentSlot = PersistentSlot.new()
	s.type = PersistentSlot.Type.TOWN
	s.level = level
	s.owner_faction = faction
	s.position = pos
	s.influence_range = 10
	return s


## 构造核心城镇测试 slot（MVP 初始 L3，复用城镇 L3 产出规则）
func _make_core_town(faction: int, pos: Vector2i) -> PersistentSlot:
	var s: PersistentSlot = PersistentSlot.new()
	s.type = PersistentSlot.Type.CORE_TOWN
	s.level = 3
	s.owner_faction = faction
	s.position = pos
	s.influence_range = 10
	return s


## 简易断言：通过打印 ✓，失败打印 ✗ 并计数
func _assert(cond: bool, msg: String) -> void:
	if cond:
		print("  ✓ " + msg)
	else:
		printerr("  ✗ " + msg)
		_failed += 1
