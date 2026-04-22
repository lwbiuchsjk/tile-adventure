extends SceneTree
## M2 地图生成（持久 slot 八阶段流水线）冒烟测试
## 运行：tools/run_godot.ps1 --headless -s test/test_m2_map_gen.gd
##
## 验证范围（对应 M2 验收标准）：
##   1. 26 数量 / 2+6+18 类型配比（硬性）
##   2. 普通 slot 间距 ≥ 3，核心 slot 与其他 ≥ 5
##   3. 三桶下限：每势力 ≥ 2 镇 + ≥ 6 村
##   4. 核心城镇：每势力 1 个，落在对角 1/8 ~ 1/4 区域；初始 level=3、归属已定
##   5. 普通 slot 初始 level=0
##   6. 同 seed 跑两次 → slot 位置 / 类型 / 归属完全一致
##   7. 连续 20 次随机 seed 均无 crash 且三桶下限全满足
##   8. PersistentSlotGenerator.GenConfig 透传 / 默认值正确

var _failed: int = 0


func _init() -> void:
	print("=== M2 地图生成冒烟测试 ===")

	_test_basic_generation()
	_test_type_breakdown()
	_test_min_distance()
	_test_three_bucket_quota()
	_test_core_zone_and_init_state()
	_test_seed_reproducibility()
	_test_twenty_random_seeds()
	_test_config_validation_traps()

	if _failed > 0:
		printerr("✗ 共 %d 项失败" % _failed)
		quit(1)
	else:
		print("✓ 全部通过")
		quit(0)


# ─────────────────────────────────────────
# 测试用例
# ─────────────────────────────────────────

## 1. 基础生成：在 32x32 全可通行假地图上跑通流水线，输出 26 个 slot
func _test_basic_generation() -> void:
	var schema: MapSchema = _make_test_schema(32, 32)
	var cfg: PersistentSlotGenerator.GenConfig = _make_test_config(12345)
	var slots: Array[PersistentSlot] = PersistentSlotGenerator.generate(schema, cfg)
	_assert(slots.size() == 26, "基础生成应输出 26 个 slot（实际 %d）" % slots.size())


## 2. 类型配比：恰好 2 核心 + 6 城镇 + 18 村庄
func _test_type_breakdown() -> void:
	var schema: MapSchema = _make_test_schema(32, 32)
	var cfg: PersistentSlotGenerator.GenConfig = _make_test_config(2026)
	var slots: Array[PersistentSlot] = PersistentSlotGenerator.generate(schema, cfg)

	var core: int = 0
	var town: int = 0
	var village: int = 0
	for s in slots:
		match s.type:
			PersistentSlot.Type.CORE_TOWN: core += 1
			PersistentSlot.Type.TOWN:      town += 1
			PersistentSlot.Type.VILLAGE:   village += 1
	_assert(core == 2,    "核心数 == 2（实际 %d）" % core)
	_assert(town == 6,    "城镇数 == 6（实际 %d）" % town)
	_assert(village == 18, "村庄数 == 18（实际 %d）" % village)


## 3. 最小间距：普通 ≥ 3，核心 ≥ 5
func _test_min_distance() -> void:
	var schema: MapSchema = _make_test_schema(32, 32)
	var cfg: PersistentSlotGenerator.GenConfig = _make_test_config(7777)
	var slots: Array[PersistentSlot] = PersistentSlotGenerator.generate(schema, cfg)

	var ok: bool = true
	for i in range(slots.size()):
		var a: PersistentSlot = slots[i]
		for j in range(i + 1, slots.size()):
			var b: PersistentSlot = slots[j]
			var dist: int = absi(a.position.x - b.position.x) + absi(a.position.y - b.position.y)
			var required: int = 3
			if a.type == PersistentSlot.Type.CORE_TOWN or b.type == PersistentSlot.Type.CORE_TOWN:
				required = 5
			if dist < required:
				ok = false
				printerr("  间距违规: %s-%s dist=%d req=%d" % [
					_describe(a), _describe(b), dist, required
				])
	_assert(ok, "全部 slot 间距满足约束（普通 ≥ 3，核心 ≥ 5）")


## 4. 三桶下限：每势力 ≥ 2 镇 + ≥ 6 村
func _test_three_bucket_quota() -> void:
	var schema: MapSchema = _make_test_schema(32, 32)
	var cfg: PersistentSlotGenerator.GenConfig = _make_test_config(98765)
	var slots: Array[PersistentSlot] = PersistentSlotGenerator.generate(schema, cfg)

	for fid in [Faction.PLAYER, Faction.ENEMY_1]:
		var fid_int: int = fid as int
		var t: int = 0
		var v: int = 0
		for s in slots:
			if s.owner_faction != fid_int:
				continue
			if s.type == PersistentSlot.Type.TOWN:    t += 1
			if s.type == PersistentSlot.Type.VILLAGE: v += 1
		_assert(t >= 2, "%s 城镇下限 ≥ 2（实际 %d）" % [Faction.faction_name(fid_int), t])
		_assert(v >= 6, "%s 村庄下限 ≥ 6（实际 %d）" % [Faction.faction_name(fid_int), v])


## 5. 核心城镇：双方各 1，落在对角区域；初始 level=3 已定归属；普通 slot level=0
func _test_core_zone_and_init_state() -> void:
	var schema: MapSchema = _make_test_schema(32, 32)
	var cfg: PersistentSlotGenerator.GenConfig = _make_test_config(31415)
	var slots: Array[PersistentSlot] = PersistentSlotGenerator.generate(schema, cfg)

	var player_core: PersistentSlot = null
	var enemy_core: PersistentSlot = null
	for s in slots:
		if s.type == PersistentSlot.Type.CORE_TOWN:
			if s.owner_faction == Faction.PLAYER: player_core = s
			elif s.owner_faction == Faction.ENEMY_1: enemy_core = s
		else:
			_assert(s.level == 0, "普通 slot 初始 level == 0")

	_assert(player_core != null, "玩家核心存在")
	_assert(enemy_core != null,  "敌方核心存在")

	if player_core != null:
		_assert(player_core.level == 3, "玩家核心初始 level == 3")
		# 对角区域：玩家在左上 1/4 内
		_assert(player_core.position.x <= 32 / 4, "玩家核心 x 在左 1/4")
		_assert(player_core.position.y <= 32 / 4, "玩家核心 y 在上 1/4")
	if enemy_core != null:
		_assert(enemy_core.level == 3, "敌方核心初始 level == 3")
		_assert(enemy_core.position.x >= 32 * 3 / 4, "敌方核心 x 在右 1/4")
		_assert(enemy_core.position.y >= 32 * 3 / 4, "敌方核心 y 在下 1/4")


## 6. Seed 复现：同 seed 跑两次 → 完全一致
func _test_seed_reproducibility() -> void:
	var schema_a: MapSchema = _make_test_schema(32, 32)
	var schema_b: MapSchema = _make_test_schema(32, 32)
	var cfg_a: PersistentSlotGenerator.GenConfig = _make_test_config(424242)
	var cfg_b: PersistentSlotGenerator.GenConfig = _make_test_config(424242)
	var slots_a: Array[PersistentSlot] = PersistentSlotGenerator.generate(schema_a, cfg_a)
	var slots_b: Array[PersistentSlot] = PersistentSlotGenerator.generate(schema_b, cfg_b)

	_assert(slots_a.size() == slots_b.size(), "两次生成 slot 数量一致")
	if slots_a.size() == slots_b.size():
		var all_match: bool = true
		for i in range(slots_a.size()):
			var a: PersistentSlot = slots_a[i]
			var b: PersistentSlot = slots_b[i]
			if a.position != b.position or a.type != b.type or a.owner_faction != b.owner_faction:
				all_match = false
				break
		_assert(all_match, "同 seed 两次生成所有 slot 位置/类型/归属一致")


## 8. 配置自检：每类非法输入都被入口拦截（返回空数组）
## 验证 _validate_config 真正提前暴露问题，避免 max_retries 后才报错
func _test_config_validation_traps() -> void:
	var schema: MapSchema = _make_test_schema(32, 32)

	# 8.1 配比与总数不一致
	var cfg_a: PersistentSlotGenerator.GenConfig = _make_test_config(1)
	cfg_a.town_count = 10  # 2 + 10 + 18 = 30 ≠ total_count(26)
	_assert(PersistentSlotGenerator.generate(schema, cfg_a).is_empty(), "配比与总数不一致 → 拦截")

	# 8.2 双方城镇下限超出总量
	var cfg_b: PersistentSlotGenerator.GenConfig = _make_test_config(2)
	cfg_b.faction_town_quota = 4  # 4 * 2 = 8 > town_count(6)
	_assert(PersistentSlotGenerator.generate(schema, cfg_b).is_empty(), "城镇下限超量 → 拦截")

	# 8.3 双方村庄下限超出总量
	var cfg_c: PersistentSlotGenerator.GenConfig = _make_test_config(3)
	cfg_c.faction_village_quota = 10  # 10 * 2 = 20 > village_count(18)
	_assert(PersistentSlotGenerator.generate(schema, cfg_c).is_empty(), "村庄下限超量 → 拦截")

	# 8.4 核心数非 2（MVP 限制）
	var cfg_d: PersistentSlotGenerator.GenConfig = _make_test_config(4)
	cfg_d.core_count = 3
	cfg_d.total_count = 27  # 让配比一致避免被前一个检查拦截
	_assert(PersistentSlotGenerator.generate(schema, cfg_d).is_empty(), "核心数非 2 → 拦截")

	# 8.5 势力场半径为 0
	var cfg_e: PersistentSlotGenerator.GenConfig = _make_test_config(5)
	cfg_e.field_radius = 0
	_assert(PersistentSlotGenerator.generate(schema, cfg_e).is_empty(), "势力场半径 0 → 拦截")

	# 8.6 核心采样区间反转
	var cfg_f: PersistentSlotGenerator.GenConfig = _make_test_config(6)
	cfg_f.core_zone_min = 0.3
	cfg_f.core_zone_max = 0.2
	_assert(PersistentSlotGenerator.generate(schema, cfg_f).is_empty(), "核心区间反转 → 拦截")

	# 8.7 地图尺寸为 0
	var cfg_g: PersistentSlotGenerator.GenConfig = _make_test_config(7)
	cfg_g.width = 0
	_assert(PersistentSlotGenerator.generate(schema, cfg_g).is_empty(), "地图宽度 0 → 拦截")

	# 8.8 下限合计 > 总数
	var cfg_h: PersistentSlotGenerator.GenConfig = _make_test_config(8)
	# core(2) + town_quota*2(2*2=4) + village_quota*2(11*2=22) = 28 > 26
	cfg_h.faction_village_quota = 11
	# 但单类 11*2=22 ≤ village_count(18)? 不，22 > 18 所以会被村庄下限超量先拦截
	# 改成下限合计 > 总数但单类不超：core(2) + 3*2 + 9*2 = 26，需要 = 27 才触发合计超
	cfg_h.faction_town_quota = 3   # 3*2=6 == town_count(6) 边界 OK
	cfg_h.faction_village_quota = 9  # 9*2=18 == village_count(18) 边界 OK
	# 总锁定 = 2 + 6 + 18 = 26，恰等于 total_count → 触发 push_warning 但 return ""，
	# 应能成功生成（中立桶为 0，涌现染色无候选）
	# 此 case 不验证拦截，仅验证不被 fatal
	_assert(not PersistentSlotGenerator.generate(schema, cfg_h).is_empty(), "锁定 == 总数边界 → 仍可生成（中立桶 0）")

	# 8.9 合法基线仍能通过
	var cfg_ok: PersistentSlotGenerator.GenConfig = _make_test_config(9)
	_assert(not PersistentSlotGenerator.generate(schema, cfg_ok).is_empty(), "默认配置 → 正常生成")


## 7. 连续 20 次随机 seed：无 crash + 三桶下限全满足
func _test_twenty_random_seeds() -> void:
	var failures: int = 0
	for i in range(20):
		var schema: MapSchema = _make_test_schema(32, 32)
		var cfg: PersistentSlotGenerator.GenConfig = _make_test_config(1000 + i * 31)
		var slots: Array[PersistentSlot] = PersistentSlotGenerator.generate(schema, cfg)
		if slots.size() != 26:
			failures += 1
			continue
		# 三桶下限抽查
		for fid in [Faction.PLAYER, Faction.ENEMY_1]:
			var t: int = 0
			var v: int = 0
			for s in slots:
				if s.owner_faction != fid: continue
				if s.type == PersistentSlot.Type.TOWN:    t += 1
				if s.type == PersistentSlot.Type.VILLAGE: v += 1
			if t < 2 or v < 6:
				failures += 1
				break
	_assert(failures == 0, "20 次随机 seed 均通过（失败 %d 次）" % failures)


# ─────────────────────────────────────────
# 测试辅助
# ─────────────────────────────────────────

## 构造一张全平地的测试 schema（隔离 PCG 噪声影响，专测 slot 算法）
func _make_test_schema(w: int, h: int) -> MapSchema:
	var schema: MapSchema = MapSchema.new()
	schema.init(w, h)
	# 注入"平地可通行 1.0"地形消耗，让 is_passable 全 true
	schema.terrain_costs[MapSchema.TerrainType.FLATLAND as int] = 1.0
	return schema


## 构造默认参数 GenConfig
func _make_test_config(seed: int) -> PersistentSlotGenerator.GenConfig:
	var cfg: PersistentSlotGenerator.GenConfig = PersistentSlotGenerator.GenConfig.new()
	cfg.seed = seed
	# 其余字段使用 GenConfig 默认值（与 map_config.csv 一致）
	return cfg


## 描述 slot 用于错误信息
func _describe(s: PersistentSlot) -> String:
	return "%s@%s/F%d" % [s.get_map_label(), str(s.position), s.owner_faction]


## 简易断言
func _assert(cond: bool, msg: String) -> void:
	if cond:
		print("  ✓ " + msg)
	else:
		printerr("  ✗ " + msg)
		_failed += 1
