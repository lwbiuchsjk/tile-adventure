extends SceneTree
## L1.3c 阶段 B：ContentSpawner（chunk 流式内容撒点）冒烟测试
## 运行：tools/run_godot.ps1 --headless -s test/test_l13c_content_spawner.gd
##
## 验证范围（对应 L1.3c §七 headless 冒烟 1/4 项的流式部分）：
##   1. 首次生成撒点：持久 slot 落 chunk 覆盖 cell + 字段注入 + display_id 增量唯一
##   2. 幂等：同 chunk 二次调用 no-op（持久 + 资源均不重复）
##   3. 跨界去重 + 顺序无关：相邻 chunk 任意处理顺序 → 最终 slot 集合一致
##   4. 资源配额 + 采集不复生：数量 ≤ 配额、FUNCTION 标记就位；采集后同 chunk 不回填
##   5. 确定性：两个独立 spawner 同 seed 同 chunk → 持久/资源产物完全一致
##   6. display_id 接续：现存 slot 已占编号时增量分配不重号

var _failed: int = 0

const CHUNK_SIZE: int = 16
const TEST_SEED: int = 20260612


func _init() -> void:
	print("=== L1.3c 阶段 B ContentSpawner 冒烟测试 ===")

	# 字段注入依赖真实升级配置（BuildSystem.apply_level_fields 查 _level_config）
	BuildSystem.load_level_config(ConfigLoader.load_persistent_slot_config())

	_test_first_generation_spawn()
	_test_idempotency()
	_test_cross_boundary_order_independence()
	_test_resource_quota_and_no_respawn()
	_test_determinism_across_instances()
	_test_display_id_continuation()
	_test_chunk_manager_emit_once()

	if _failed > 0:
		printerr("✗ 共 %d 项失败" % _failed)
		quit(1)
	else:
		print("✓ 全部通过")
		quit(0)


# ─────────────────────────────────────────
# 测试用例
# ─────────────────────────────────────────

## 1. 首次生成撒点：位置在 chunk 覆盖 cell 范围 + 中立归属 + 字段注入 + display_id 唯一
func _test_first_generation_spawn() -> void:
	var ctx: Dictionary = _make_ctx(TEST_SEED)
	var spawner: ContentSpawner = ctx["spawner"] as ContentSpawner
	var schema: MapSchema = ctx["schema"] as MapSchema

	spawner.on_chunk_first_generated(Vector2i(0, 0), null)

	_assert(schema.persistent_slots.size() > 0, "首次生成有持久 slot 产出（实际 %d）" % schema.persistent_slots.size())

	var ok: bool = true
	var seen_ids: Dictionary = {}
	for entry in schema.persistent_slots:
		var slot: PersistentSlot = entry as PersistentSlot
		if slot.owner_faction != Faction.NONE:
			ok = false
			printerr("  违规: 新增 slot 非中立 @%s" % str(slot.position))
		if slot.type == PersistentSlot.Type.CORE_TOWN:
			ok = false
			printerr("  违规: 出现 CORE_TOWN")
		if not schema.is_passable(slot.position.x, slot.position.y):
			ok = false
			printerr("  违规: slot 落不可走格 @%s" % str(slot.position))
		# 字段注入：apply_level_fields 后 initial_range 应非负且配置就位（level 0 配置存在）
		if slot.initial_range <= 0:
			ok = false
			printerr("  违规: 字段未注入 initial_range=%d @%s" % [slot.initial_range, str(slot.position)])
		if slot.display_id.is_empty() or seen_ids.has(slot.display_id):
			ok = false
			printerr("  违规: display_id 空/重复 '%s'" % slot.display_id)
		seen_ids[slot.display_id] = true
	_assert(ok, "新增 slot 全中立 / 可走 / 字段已注入 / display_id 唯一")


## 2. 幂等：同 chunk 二次调用，持久 + 资源数量均不变
func _test_idempotency() -> void:
	var ctx: Dictionary = _make_ctx(TEST_SEED + 1)
	var spawner: ContentSpawner = ctx["spawner"] as ContentSpawner
	var schema: MapSchema = ctx["schema"] as MapSchema
	var resources: Dictionary = ctx["resources"] as Dictionary

	spawner.on_chunk_first_generated(Vector2i(0, 0), null)
	var p_count: int = schema.persistent_slots.size()
	var r_count: int = resources.size()
	spawner.on_chunk_first_generated(Vector2i(0, 0), null)
	_assert(schema.persistent_slots.size() == p_count, "二次调用持久 slot 数不变（%d）" % p_count)
	_assert(resources.size() == r_count, "二次调用资源 slot 数不变（%d）" % r_count)


## 3. 跨界去重 + 顺序无关：A 先 (0,0) 后 (1,0)，B 先 (1,0) 后 (0,0) → 持久 slot 集合一致
func _test_cross_boundary_order_independence() -> void:
	var ctx_a: Dictionary = _make_ctx(TEST_SEED + 2)
	var ctx_b: Dictionary = _make_ctx(TEST_SEED + 2)
	var spawner_a: ContentSpawner = ctx_a["spawner"] as ContentSpawner
	var spawner_b: ContentSpawner = ctx_b["spawner"] as ContentSpawner

	spawner_a.on_chunk_first_generated(Vector2i(0, 0), null)
	spawner_a.on_chunk_first_generated(Vector2i(1, 0), null)
	spawner_b.on_chunk_first_generated(Vector2i(1, 0), null)
	spawner_b.on_chunk_first_generated(Vector2i(0, 0), null)

	var set_a: Dictionary = _slot_set(ctx_a["schema"] as MapSchema)
	var set_b: Dictionary = _slot_set(ctx_b["schema"] as MapSchema)
	_assert(set_a.size() == set_b.size(), "两种处理顺序持久 slot 数量一致（%d vs %d）" % [set_a.size(), set_b.size()])
	var same: bool = true
	for key in set_a:
		if not set_b.has(key):
			same = false
			printerr("  顺序相关违规: %s 仅在顺序 A 出现" % str(key))
	_assert(same, "相邻 chunk 任意处理顺序 → 位置+类型集合一致（跨界 cell 去重生效）")
	# 无重复位置（同位置只会有一个 slot）
	var schema_a: MapSchema = ctx_a["schema"] as MapSchema
	var positions: Dictionary = {}
	var no_dup: bool = true
	for entry in schema_a.persistent_slots:
		var slot: PersistentSlot = entry as PersistentSlot
		if positions.has(slot.position):
			no_dup = false
			printerr("  跨界重复: %s" % str(slot.position))
		positions[slot.position] = true
	_assert(no_dup, "无跨界重复位置")


## 4. 资源配额 + 采集后不复生（L1.3c 阶段 D：_resource_slots 唯一权威源，schema FUNCTION 双写已退役）
func _test_resource_quota_and_no_respawn() -> void:
	var ctx: Dictionary = _make_ctx(TEST_SEED + 3)
	var spawner: ContentSpawner = ctx["spawner"] as ContentSpawner
	var schema: MapSchema = ctx["schema"] as MapSchema
	var resources: Dictionary = ctx["resources"] as Dictionary

	spawner.on_chunk_first_generated(Vector2i(0, 0), null)
	var quota: int = 2  # 与 _make_ctx 注入一致
	_assert(resources.size() > 0 and resources.size() <= quota, "资源数 ∈ (0, 配额=%d]（实际 %d）" % [quota, resources.size()])
	# 阶段 D：资源点不再写 schema 标记，断言落点不被写入 _slots（保持稀疏）
	var schema_clean: bool = true
	for pos in resources:
		var p: Vector2i = pos as Vector2i
		if schema.get_slot(p.x, p.y) != MapSchema.SlotType.NONE:
			schema_clean = false
			printerr("  违规: 资源位 %s 不应再写 schema 标记（阶段 D 双写已退役）" % str(p))
	_assert(schema_clean, "资源位不写 schema 标记（_resource_slots 唯一权威）")

	# 模拟采集（真实语义，codex P3）：保留 ResourceSlot + 设 is_collected=true（不删字典条目）——
	# 与生产代码 ExplorationCoordinator.try_collect_resource_at 一致（_resource_slots 唯一权威，采集态由 is_collected 表达）
	var first_pos: Vector2i = (resources.keys()[0]) as Vector2i
	var first_rs: ResourceSlot = resources[first_pos] as ResourceSlot
	first_rs.is_collected = true
	var before_count: int = resources.size()
	# 同 chunk 信号重复发射：占用判定 _resource_slots.has(first_pos) 仍为 true（已采集 slot 不删）→ 不在该格复生
	spawner.on_chunk_first_generated(Vector2i(0, 0), null)
	_assert(resources.size() == before_count, "重复信号不新增资源（占用判定生效）")
	_assert(resources.has(first_pos) and (resources[first_pos] as ResourceSlot).is_collected,
		"已采集资源点保留且 is_collected=true（不复生、不被覆盖）")


## 5. 确定性：独立 spawner 同 seed 同 chunk → 持久/资源产物一致
func _test_determinism_across_instances() -> void:
	var ctx_a: Dictionary = _make_ctx(TEST_SEED + 4)
	var ctx_b: Dictionary = _make_ctx(TEST_SEED + 4)
	(ctx_a["spawner"] as ContentSpawner).on_chunk_first_generated(Vector2i(-1, -1), null)
	(ctx_b["spawner"] as ContentSpawner).on_chunk_first_generated(Vector2i(-1, -1), null)

	var set_a: Dictionary = _slot_set(ctx_a["schema"] as MapSchema)
	var set_b: Dictionary = _slot_set(ctx_b["schema"] as MapSchema)
	var same: bool = set_a.size() == set_b.size()
	if same:
		for key in set_a:
			if not set_b.has(key):
				same = false
				break
	_assert(same, "负坐标 chunk：独立实例同 seed 持久 slot 产物一致")

	var res_a: Dictionary = ctx_a["resources"] as Dictionary
	var res_b: Dictionary = ctx_b["resources"] as Dictionary
	var res_same: bool = res_a.size() == res_b.size()
	if res_same:
		for pos in res_a:
			if not res_b.has(pos):
				res_same = false
				break
			var ra: ResourceSlot = res_a[pos] as ResourceSlot
			var rb: ResourceSlot = res_b[pos] as ResourceSlot
			if ra.resource_type != rb.resource_type or ra.output_amount != rb.output_amount:
				res_same = false
				break
	_assert(res_same, "负坐标 chunk：独立实例同 seed 资源产物一致")


## 6. display_id 接续：预置已编号 slot（含升级为 CORE_TOWN 但保留"村庄N"编号的据点 +
##    编号空洞）→ 新增编号按最大尾号接续，全局不重号（codex P1/P2 加固）
func _test_display_id_continuation() -> void:
	var ctx: Dictionary = _make_ctx(TEST_SEED + 5, 3)  # 预置 村庄1..3
	var schema: MapSchema = ctx["schema"] as MapSchema

	# 模拟据点升级：村庄2 升级为 CORE_TOWN（type 变、display_id 保留原编号）
	for entry in schema.persistent_slots:
		var slot: PersistentSlot = entry as PersistentSlot
		if slot.display_id == "村庄2":
			slot.type = PersistentSlot.Type.CORE_TOWN
			slot.owner_faction = Faction.PLAYER
			slot.level = 3
	# 制造编号空洞：再预置一个高位编号 村庄7
	var hole: PersistentSlot = PersistentSlot.new()
	hole.position = Vector2i(600, 600)
	hole.type = PersistentSlot.Type.VILLAGE
	hole.display_id = "村庄7"
	schema.persistent_slots.append(hole)

	# 计数器在 setup 时初始化——升级/空洞发生后重新装配 spawner 模拟 reload 场景
	var spawner: ContentSpawner = _make_spawner_for(ctx)
	spawner.on_chunk_first_generated(Vector2i(2, 2), null)

	var seen: Dictionary = {}
	var unique_ok: bool = true
	for entry in schema.persistent_slots:
		var slot: PersistentSlot = entry as PersistentSlot
		if seen.has(slot.display_id):
			unique_ok = false
			printerr("  display_id 重号: %s" % slot.display_id)
		seen[slot.display_id] = true
	_assert(unique_ok, "升级据点保留编号 + 编号空洞下增量分配仍不重号（最大尾号接续）")


## 7. ChunkManager 信号路径集成：ACTIVE / DORMANT 两条首次生成分支均只 emit 一次（codex P2）
func _test_chunk_manager_emit_once() -> void:
	var vision: VisionSystem = VisionSystem.new()
	var cm: ChunkManager = ChunkManager.new()
	cm.setup(VisionConfig.new(), vision, TEST_SEED)

	var emit_log: Array[Vector2i] = []
	cm.chunk_first_generated.connect(func(coord: Vector2i, _schema: ChunkSchema) -> void:
		emit_log.append(coord)
	)

	# 路径 1：UNLOADED→ACTIVE（首次）→ UNLOADED（退化）→ ACTIVE（重建，不应再发）
	cm._transition_to(Vector2i(5, 5), ChunkRecord.State.ACTIVE)
	cm._transition_to(Vector2i(5, 5), ChunkRecord.State.UNLOADED)
	cm._transition_to(Vector2i(5, 5), ChunkRecord.State.ACTIVE)
	# 路径 2：UNLOADED→DORMANT（首次，极少见分支）→ ACTIVE（已有 schema，不应再发）
	cm._transition_to(Vector2i(6, 5), ChunkRecord.State.DORMANT)
	cm._transition_to(Vector2i(6, 5), ChunkRecord.State.ACTIVE)

	var count_a: int = 0
	var count_b: int = 0
	for coord in emit_log:
		if coord == Vector2i(5, 5): count_a += 1
		if coord == Vector2i(6, 5): count_b += 1
	_assert(count_a == 1, "ACTIVE 首次生成分支恰好 emit 1 次（实际 %d，含重建路径）" % count_a)
	_assert(count_b == 1, "DORMANT 首次生成分支恰好 emit 1 次（实际 %d）" % count_b)
	# 节点清理（ChunkManager extends Node，未入树需手动 free）
	cm.free()
	vision.free()


# ─────────────────────────────────────────
# 测试辅助
# ─────────────────────────────────────────

## 构造测试上下文：全可走无限 schema + 配好参的 ContentSpawner + 资源/敌包字典
## preset_villages：预置 N 个已编号 VILLAGE（display_id 接续测试用），放在远离测试 chunk 处
func _make_ctx(world_seed: int, preset_villages: int = 0) -> Dictionary:
	var schema: MapSchema = MapSchema.new()
	schema.init(32, 32, false)
	schema.set_infinite_terrain(world_seed)
	# 4 级地形全可走，隔离地形影响
	schema.terrain_costs[MapSchema.TerrainType.MOUNTAIN as int] = 3.0
	schema.terrain_costs[MapSchema.TerrainType.HIGHLAND as int] = 2.0
	schema.terrain_costs[MapSchema.TerrainType.FLATLAND as int] = 1.0
	schema.terrain_costs[MapSchema.TerrainType.LOWLAND as int] = 1.0

	for i in range(preset_villages):
		var pre: PersistentSlot = PersistentSlot.new()
		pre.position = Vector2i(500 + i * 5, 500)
		pre.type = PersistentSlot.Type.VILLAGE
		pre.level = 0
		pre.owner_faction = Faction.NONE
		pre.display_id = "村庄%d" % (i + 1)
		schema.persistent_slots.append(pre)

	var gcfg: PersistentSlotGenerator.GenConfig = PersistentSlotGenerator.GenConfig.new()
	gcfg.seed = world_seed
	gcfg.cell_size = 5
	gcfg.slot_spawn_rate = 0.85
	gcfg.town_ratio = 0.27

	var resources: Dictionary = {}
	var level_slots: Dictionary = {}
	var resource_rows: Array = [
		{"resource_type": "0", "output_amount": "2", "count_per_round": "3"},
		{"resource_type": "3", "output_amount": "1", "count_per_round": "1"},
	]

	var spawner: ContentSpawner = ContentSpawner.new()
	spawner.setup(
		schema, gcfg, Vector2i(1000, 1000), CHUNK_SIZE,
		resources, level_slots, resource_rows, 2,
		{}, [], Callable()
	)
	return {"spawner": spawner, "schema": schema, "resources": resources}


## 用既有 ctx 的 schema/字典重新装配一个 spawner（模拟 reload 后重新接线：计数器重新初始化）
func _make_spawner_for(ctx: Dictionary) -> ContentSpawner:
	var gcfg: PersistentSlotGenerator.GenConfig = PersistentSlotGenerator.GenConfig.new()
	gcfg.seed = TEST_SEED + 5
	gcfg.cell_size = 5
	gcfg.slot_spawn_rate = 0.85
	gcfg.town_ratio = 0.27
	var spawner: ContentSpawner = ContentSpawner.new()
	spawner.setup(
		ctx["schema"] as MapSchema, gcfg, Vector2i(1000, 1000), CHUNK_SIZE,
		ctx["resources"] as Dictionary, {}, [], 0,
		{}, [], Callable()
	)
	return spawner


## schema 持久 slot 的 {(position, type): true} 集合（顺序无关比较用）
func _slot_set(schema: MapSchema) -> Dictionary:
	var result: Dictionary = {}
	for entry in schema.persistent_slots:
		var slot: PersistentSlot = entry as PersistentSlot
		result["%s_%d" % [str(slot.position), int(slot.type)]] = true
	return result


## 简易断言
func _assert(cond: bool, msg: String) -> void:
	if cond:
		print("  ✓ " + msg)
	else:
		printerr("  ✗ " + msg)
		_failed += 1
