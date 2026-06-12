extends SceneTree
## M2 地图生成（L1.3c 阶段 A：网格抖动撒点）冒烟测试
## 运行：tools/run_godot.ps1 --headless -s test/test_m2_map_gen.gd
##
## 验证范围（对应 L1.3c §七 headless 冒烟 1-4 项的生成器局部）：
##   1. 基本生成：玩家锚点 TOWN 唯一且近出生点；无 CORE_TOWN / 无 ENEMY_1 染色；全部 level=0
##   2. 出生居中：内容覆盖负坐标象限；全部落在区域内
##   3. 撒点间距：任意两 slot 曼哈顿间距 ≥ 3（网格抖动 PAD=1 下界）
##   4. 确定性：同 seed 两次生成完全一致（位置/类型/归属/display_id）
##   5. 区域单调性（阶段 B chunk 流式复用基石）：小区域结果 ⊆ 大区域结果（cell 输出与范围无关）
##   6. 地形约束：MOUNTAIN 不可走时全部 slot 落可走格；20 随机 seed 无 crash
##   7. 配置自检：非法参数被入口拦截（返回空数组）
##   8. display_id 全局唯一

var _failed: int = 0


func _init() -> void:
	print("=== M2 地图生成（网格抖动撒点）冒烟测试 ===")

	_test_basic_generation()
	_test_centered_negative_coords()
	_test_min_distance()
	_test_seed_reproducibility()
	_test_region_monotonicity()
	_test_cell_function_properties()
	_test_terrain_constraint_and_random_seeds()
	_test_config_validation_traps()
	_test_display_id_unique()

	if _failed > 0:
		printerr("✗ 共 %d 项失败" % _failed)
		quit(1)
	else:
		print("✓ 全部通过")
		quit(0)


# ─────────────────────────────────────────
# 测试用例
# ─────────────────────────────────────────

## 1. 基本生成：锚点唯一 + 无敌方染色 + 无 CORE_TOWN + 全部 level=0
func _test_basic_generation() -> void:
	var schema: MapSchema = _make_test_schema(12345)
	var cfg: PersistentSlotGenerator.GenConfig = _make_cfg(12345)
	var slots: Array[PersistentSlot] = PersistentSlotGenerator.generate(schema, cfg)

	_assert(slots.size() > 1, "生成结果非空（锚点 + 撒点；实际 %d）" % slots.size())

	var anchor_count: int = 0
	var ok_init: bool = true
	for s in slots:
		# L1.3c 拍板：PCG 不再预置 CORE_TOWN；开局无 ENEMY_1 染色
		if s.type == PersistentSlot.Type.CORE_TOWN:
			ok_init = false
			printerr("  违规: 出现 CORE_TOWN @%s" % str(s.position))
		if s.owner_faction == Faction.ENEMY_1:
			ok_init = false
			printerr("  违规: 出现 ENEMY_1 染色 @%s" % str(s.position))
		if s.level != 0:
			ok_init = false
			printerr("  违规: 初始 level != 0 @%s" % str(s.position))
		if s.owner_faction == Faction.PLAYER:
			anchor_count += 1
			var dist: int = absi(s.position.x - cfg.region_center.x) + absi(s.position.y - cfg.region_center.y)
			_assert(s.type == PersistentSlot.Type.TOWN, "玩家锚点 type == TOWN")
			_assert(dist <= cfg.anchor_search_radius, "玩家锚点距出生点 ≤ %d（实际 %d）" % [cfg.anchor_search_radius, dist])
	_assert(anchor_count == 1, "玩家锚点 TOWN 恰好 1 个（实际 %d）" % anchor_count)
	_assert(ok_init, "无 CORE_TOWN / 无 ENEMY_1 / 全部 level=0")


## 2. 出生居中：内容覆盖负坐标 + 全部落在区域内
func _test_centered_negative_coords() -> void:
	var schema: MapSchema = _make_test_schema(2026)
	var cfg: PersistentSlotGenerator.GenConfig = _make_cfg(2026)
	var slots: Array[PersistentSlot] = PersistentSlotGenerator.generate(schema, cfg)

	var region_min: Vector2i = cfg.region_center - Vector2i(cfg.region_width / 2, cfg.region_height / 2)
	var region_max: Vector2i = region_min + Vector2i(cfg.region_width - 1, cfg.region_height - 1)
	var has_neg_x: bool = false
	var has_neg_y: bool = false
	var all_in_region: bool = true
	for s in slots:
		if s.position.x < 0: has_neg_x = true
		if s.position.y < 0: has_neg_y = true
		if s.position.x < region_min.x or s.position.x > region_max.x \
			or s.position.y < region_min.y or s.position.y > region_max.y:
			all_in_region = false
			printerr("  越界: %s 不在 [%s, %s]" % [str(s.position), str(region_min), str(region_max)])
	_assert(has_neg_x and has_neg_y, "内容覆盖负坐标象限（出生居中四方等价）")
	_assert(all_in_region, "全部 slot 落在内容区域内")


## 3. 撒点间距：任意两 slot 曼哈顿间距 ≥ 3
func _test_min_distance() -> void:
	var schema: MapSchema = _make_test_schema(7777)
	var cfg: PersistentSlotGenerator.GenConfig = _make_cfg(7777)
	var slots: Array[PersistentSlot] = PersistentSlotGenerator.generate(schema, cfg)

	var ok: bool = true
	for i in range(slots.size()):
		for j in range(i + 1, slots.size()):
			var a: PersistentSlot = slots[i]
			var b: PersistentSlot = slots[j]
			var dist: int = absi(a.position.x - b.position.x) + absi(a.position.y - b.position.y)
			if dist < 3:
				ok = false
				printerr("  间距违规: %s-%s dist=%d" % [str(a.position), str(b.position), dist])
	_assert(ok, "全部 slot 曼哈顿间距 ≥ 3（网格抖动下界）")


## 4. 确定性：同 seed 两次生成完全一致
func _test_seed_reproducibility() -> void:
	var slots_a: Array[PersistentSlot] = PersistentSlotGenerator.generate(_make_test_schema(424242), _make_cfg(424242))
	var slots_b: Array[PersistentSlot] = PersistentSlotGenerator.generate(_make_test_schema(424242), _make_cfg(424242))

	_assert(slots_a.size() == slots_b.size(), "两次生成 slot 数量一致")
	if slots_a.size() == slots_b.size():
		var all_match: bool = true
		for i in range(slots_a.size()):
			var a: PersistentSlot = slots_a[i]
			var b: PersistentSlot = slots_b[i]
			if a.position != b.position or a.type != b.type \
				or a.owner_faction != b.owner_faction or a.display_id != b.display_id:
				all_match = false
				break
		_assert(all_match, "同 seed 两次生成位置/类型/归属/display_id 完全一致")


## 5. 区域单调性：小区域结果 ⊆ 大区域结果（cell 输出与生成范围无关——阶段 B chunk 流式基石）
func _test_region_monotonicity() -> void:
	var seed: int = 31415
	var small: Array[PersistentSlot] = PersistentSlotGenerator.generate(_make_test_schema(seed), _make_cfg(seed, 32, 32))
	var large: Array[PersistentSlot] = PersistentSlotGenerator.generate(_make_test_schema(seed), _make_cfg(seed, 48, 48))

	# 大区域按 position 建索引
	var large_by_pos: Dictionary = {}
	for s in large:
		large_by_pos[s.position] = s
	var subset_ok: bool = true
	for s in small:
		if not large_by_pos.has(s.position):
			subset_ok = false
			printerr("  单调性违规: 小区域 slot %s 不在大区域结果中" % str(s.position))
			continue
		var counterpart: PersistentSlot = large_by_pos[s.position] as PersistentSlot
		if counterpart.type != s.type:
			subset_ok = false
			printerr("  单调性违规: %s 类型不一致" % str(s.position))
	_assert(subset_ok, "小区域结果 ⊆ 大区域结果（位置+类型；cell 确定性与范围无关）")
	_assert(large.size() > small.size(), "大区域 slot 更多（%d > %d）" % [large.size(), small.size()])


## 5b. generate_cell_slot 直接性质断言（codex P2 加固）：
##     负 cell / 对角 cell 边界间距 + 纯函数确定性（与调用次数/范围无关）
func _test_cell_function_properties() -> void:
	var seed: int = 555
	var schema: MapSchema = _make_test_schema(seed)
	var cfg: PersistentSlotGenerator.GenConfig = _make_cfg(seed)

	# 纯函数确定性：同 cell 调两次结果一致（含 null 情形）
	var pure_ok: bool = true
	# 围绕原点的 4 个象限 cell + 更远的负 cell，覆盖 floor 除法负坐标路径
	var probe_cells: Array[Vector2i] = [
		Vector2i(0, 0), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(-1, -1),
		Vector2i(-3, -2), Vector2i(2, -3),
	]
	for cell in probe_cells:
		var a: PersistentSlot = PersistentSlotGenerator.generate_cell_slot(seed, cell, cfg, schema)
		var b: PersistentSlot = PersistentSlotGenerator.generate_cell_slot(seed, cell, cfg, schema)
		if (a == null) != (b == null):
			pure_ok = false
		elif a != null and b != null and (a.position != b.position or a.type != b.type):
			pure_ok = false
		# cell 内位置约束：落点必须在该 cell 的 PAD 内缩区间（间距下界的前提）
		if a != null:
			var cs: int = cfg.cell_size
			var local: Vector2i = a.position - cell * cs
			if local.x < 1 or local.x > cs - 2 or local.y < 1 or local.y > cs - 2:
				pure_ok = false
				printerr("  cell %s 落点 %s 超出 PAD 内缩区间" % [str(cell), str(a.position)])
	_assert(pure_ok, "generate_cell_slot 纯函数确定性 + PAD 内缩约束（含负 cell）")

	# 相邻/对角 cell 间距：扫负象限 5×5 cell 块，全对断言曼哈顿间距 ≥ 3
	var produced: Array[PersistentSlot] = []
	for cy in range(-3, 2):
		for cx in range(-3, 2):
			var s: PersistentSlot = PersistentSlotGenerator.generate_cell_slot(seed, Vector2i(cx, cy), cfg, schema)
			if s != null:
				produced.append(s)
	var spacing_ok: bool = true
	for i in range(produced.size()):
		for j in range(i + 1, produced.size()):
			var dist: int = absi(produced[i].position.x - produced[j].position.x) \
				+ absi(produced[i].position.y - produced[j].position.y)
			if dist < 3:
				spacing_ok = false
				printerr("  负象限 cell 间距违规: %s-%s dist=%d" % [
					str(produced[i].position), str(produced[j].position), dist
				])
	_assert(produced.size() > 0, "负象限 cell 块有产出（实际 %d）" % produced.size())
	_assert(spacing_ok, "负象限相邻/对角 cell 全对间距 ≥ 3")


## 6. 地形约束 + 20 随机 seed：MOUNTAIN 不可走时全部落可走格，无 crash
func _test_terrain_constraint_and_random_seeds() -> void:
	var failures: int = 0
	for i in range(20):
		var seed: int = 1000 + i * 31
		var schema: MapSchema = _make_test_schema(seed, false)  # MOUNTAIN 不可走（真实规则）
		var cfg: PersistentSlotGenerator.GenConfig = _make_cfg(seed)
		var slots: Array[PersistentSlot] = PersistentSlotGenerator.generate(schema, cfg)
		if slots.is_empty():
			# 真实地形下出生点可能落山地导致锚点失败——本测试 region_center 固定原点，
			# 噪声下原点周围 8 格全山概率极低；视为失败计数
			failures += 1
			continue
		for s in slots:
			if not schema.is_passable(s.position.x, s.position.y):
				failures += 1
				printerr("  seed=%d slot %s 落在不可走格" % [seed, str(s.position)])
				break
	_assert(failures == 0, "20 次随机 seed 全部 slot 落可走格且无 crash（失败 %d 次）" % failures)


## 7. 配置自检：非法参数被入口拦截
func _test_config_validation_traps() -> void:
	var schema: MapSchema = _make_test_schema(1)

	var cfg_a: PersistentSlotGenerator.GenConfig = _make_cfg(1)
	cfg_a.cell_size = 2
	_assert(PersistentSlotGenerator.generate(schema, cfg_a).is_empty(), "cell_size < 3 → 拦截")

	var cfg_b: PersistentSlotGenerator.GenConfig = _make_cfg(2)
	cfg_b.slot_spawn_rate = 1.5
	_assert(PersistentSlotGenerator.generate(schema, cfg_b).is_empty(), "出点概率 > 1 → 拦截")

	var cfg_c: PersistentSlotGenerator.GenConfig = _make_cfg(3)
	cfg_c.town_ratio = -0.1
	_assert(PersistentSlotGenerator.generate(schema, cfg_c).is_empty(), "城镇占比 < 0 → 拦截")

	var cfg_d: PersistentSlotGenerator.GenConfig = _make_cfg(4)
	cfg_d.region_width = 0
	_assert(PersistentSlotGenerator.generate(schema, cfg_d).is_empty(), "区域宽度 0 → 拦截")

	var cfg_e: PersistentSlotGenerator.GenConfig = _make_cfg(5)
	cfg_e.anchor_search_radius = 1
	_assert(PersistentSlotGenerator.generate(schema, cfg_e).is_empty(), "锚搜半径 < 2 → 拦截")

	var cfg_ok: PersistentSlotGenerator.GenConfig = _make_cfg(6)
	_assert(not PersistentSlotGenerator.generate(schema, cfg_ok).is_empty(), "默认配置 → 正常生成")


## 8. display_id 全局唯一
func _test_display_id_unique() -> void:
	var schema: MapSchema = _make_test_schema(98765)
	var cfg: PersistentSlotGenerator.GenConfig = _make_cfg(98765)
	var slots: Array[PersistentSlot] = PersistentSlotGenerator.generate(schema, cfg)

	var seen: Dictionary = {}
	var unique_ok: bool = true
	for s in slots:
		if seen.has(s.display_id):
			unique_ok = false
			printerr("  display_id 重复: %s" % s.display_id)
		seen[s.display_id] = true
		if s.display_id.is_empty():
			unique_ok = false
			printerr("  display_id 为空 @%s" % str(s.position))
	_assert(unique_ok, "display_id 全局唯一且非空")


# ─────────────────────────────────────────
# 测试辅助
# ─────────────────────────────────────────

## 构造无限模式测试 schema（L1.3b 后地形经 set_infinite_terrain 路由 ChunkPCG，任意坐标可查）
## all_passable=true：4 级地形全可走（隔离地形影响专测撒点算法）
## all_passable=false：MOUNTAIN 不可走（真实规则，测地形约束）
func _make_test_schema(world_seed: int, all_passable: bool = true) -> MapSchema:
	var schema: MapSchema = MapSchema.new()
	schema.init(32, 32, false)
	schema.set_infinite_terrain(world_seed)
	schema.terrain_costs[MapSchema.TerrainType.HIGHLAND as int] = 2.0
	schema.terrain_costs[MapSchema.TerrainType.FLATLAND as int] = 1.0
	schema.terrain_costs[MapSchema.TerrainType.LOWLAND as int] = 1.0
	if all_passable:
		schema.terrain_costs[MapSchema.TerrainType.MOUNTAIN as int] = 3.0
	return schema


## 构造默认撒点 GenConfig（区域以世界原点为中心）
func _make_cfg(seed: int, w: int = 32, h: int = 32) -> PersistentSlotGenerator.GenConfig:
	var cfg: PersistentSlotGenerator.GenConfig = PersistentSlotGenerator.GenConfig.new()
	cfg.seed = seed
	cfg.region_center = Vector2i.ZERO
	cfg.region_width = w
	cfg.region_height = h
	cfg.cell_size = 5
	cfg.slot_spawn_rate = 0.85
	cfg.town_ratio = 0.27
	cfg.anchor_search_radius = 8
	return cfg


## 简易断言
func _assert(cond: bool, msg: String) -> void:
	if cond:
		print("  ✓ " + msg)
	else:
		printerr("  ✗ " + msg)
		_failed += 1
