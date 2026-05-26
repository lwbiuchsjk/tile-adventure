extends SceneTree
## ChunkManager 三态生命周期冒烟测试（L1.1 §7 场景 2/3）
##
## 运行：
##   /mnt/e/Godot/.../Godot.exe --headless --path "E:\Godot\project\tile-adventure" -s test/test_chunk_manager.gd
##
## 验证范围：
##   1. tile_to_chunk 数学（含负坐标 floor 行为）
##   2. 聚合规则：NORMAL → ACTIVE / FOG → DORMANT / SHADOW → UNLOADED
##   3. 状态转换驱动 schema 生成 / 丢弃
##   4. chunk_state_changed signal 发射
##   5. 增量更新（tile 状态变化只重算该 chunk）
##   6. ChunkPCG 调用：UNLOADED → ACTIVE 时生成 schema

var _failed: int = 0
var _signal_captured: Array[Dictionary] = []


func _init() -> void:
	print("=== ChunkManager 冒烟测试 ===")

	_test_tile_to_chunk_positive()
	_test_tile_to_chunk_negative()
	_test_aggregate_normal_to_active()
	_test_aggregate_fog_to_dormant()
	_test_aggregate_shadow_to_unloaded()
	_test_active_to_dormant_keeps_schema()
	_test_dormant_to_unloaded_drops_schema()
	_test_chunk_state_changed_signal()
	_test_get_active_chunks_query()
	_test_incremental_aggregation_on_vision_change()

	if _failed > 0:
		printerr("✗ 共 %d 项失败" % _failed)
		quit(1)
	else:
		print("✓ 全部通过")
		quit(0)


# ─────────────────────────────────────
# 用例
# ─────────────────────────────────────

## 1. tile_to_chunk 正坐标
func _test_tile_to_chunk_positive() -> void:
	print("-- tile_to_chunk 正坐标")
	_assert(ChunkManager.tile_to_chunk(Vector2i(0, 0)) == Vector2i(0, 0), "(0,0) → (0,0)")
	_assert(ChunkManager.tile_to_chunk(Vector2i(15, 15)) == Vector2i(0, 0), "(15,15) → (0,0)（chunk 边内）")
	_assert(ChunkManager.tile_to_chunk(Vector2i(16, 0)) == Vector2i(1, 0), "(16,0) → (1,0)（chunk 边外）")
	_assert(ChunkManager.tile_to_chunk(Vector2i(33, 50)) == Vector2i(2, 3), "(33,50) → (2,3)")


## 2. tile_to_chunk 负坐标（floori 而非 int）
func _test_tile_to_chunk_negative() -> void:
	print("-- tile_to_chunk 负坐标")
	# -1/16 在 floori 下应为 -1（不是 0）
	_assert(ChunkManager.tile_to_chunk(Vector2i(-1, 0)) == Vector2i(-1, 0), "(-1,0) → (-1,0)")
	_assert(ChunkManager.tile_to_chunk(Vector2i(-16, 0)) == Vector2i(-1, 0), "(-16,0) → (-1,0)")
	_assert(ChunkManager.tile_to_chunk(Vector2i(-17, 0)) == Vector2i(-2, 0), "(-17,0) → (-2,0)")


## 3. NORMAL 覆盖 → chunk ACTIVE
func _test_aggregate_normal_to_active() -> void:
	print("-- NORMAL → ACTIVE")
	var ctx: Dictionary = _make_context()
	var vs: VisionSystem = ctx["vision"]
	var cm: ChunkManager = ctx["chunk"]

	# 注册视野源 → chunk(0,0) 内有 NORMAL 格
	var src: VisionSource = VisionSource.new(Vector2i(2, 2), 1)
	vs.register_source(src)

	_assert(cm.get_chunk_state(Vector2i(0, 0)) == ChunkRecord.State.ACTIVE, "chunk(0,0) ACTIVE")
	_assert(cm.get_chunk_schema(Vector2i(0, 0)) != null, "ACTIVE chunk 有 schema")


## 4. 仅 FOG 覆盖 → chunk DORMANT
func _test_aggregate_fog_to_dormant() -> void:
	print("-- FOG → DORMANT")
	var ctx: Dictionary = _make_context()
	var vs: VisionSystem = ctx["vision"]
	var cm: ChunkManager = ctx["chunk"]

	# 手工灌入 FOG 状态 + 触发聚合
	vs._tile_state[Vector2i(5, 5)] = VisionSystem.TileState.FOG
	cm.aggregate_chunk(Vector2i(0, 0))

	_assert(cm.get_chunk_state(Vector2i(0, 0)) == ChunkRecord.State.DORMANT, "chunk(0,0) DORMANT")
	_assert(cm.get_chunk_schema(Vector2i(0, 0)) != null, "DORMANT chunk 有 schema（保留快照）")


## 5. 全 SHADOW → chunk UNLOADED
func _test_aggregate_shadow_to_unloaded() -> void:
	print("-- 全 SHADOW → UNLOADED")
	var ctx: Dictionary = _make_context()
	var cm: ChunkManager = ctx["chunk"]

	cm.aggregate_chunk(Vector2i(0, 0))
	_assert(cm.get_chunk_state(Vector2i(0, 0)) == ChunkRecord.State.UNLOADED, "未覆盖时 UNLOADED")


## 6. ACTIVE → DORMANT 保留 schema
func _test_active_to_dormant_keeps_schema() -> void:
	print("-- ACTIVE → DORMANT 保留 schema")
	var ctx: Dictionary = _make_context()
	var vs: VisionSystem = ctx["vision"]
	var cm: ChunkManager = ctx["chunk"]

	# ACTIVE
	var src: VisionSource = VisionSource.new(Vector2i(2, 2), 1)
	vs.register_source(src)
	var schema_active: ChunkSchema = cm.get_chunk_schema(Vector2i(0, 0))
	_assert(schema_active != null, "ACTIVE schema 存在")

	# 手动转 DORMANT（模拟 FOG 覆盖）
	for key in vs._tile_state.keys():
		vs._tile_state[key] = VisionSystem.TileState.FOG
	cm.aggregate_chunk(Vector2i(0, 0))

	_assert(cm.get_chunk_state(Vector2i(0, 0)) == ChunkRecord.State.DORMANT, "已转 DORMANT")
	_assert(cm.get_chunk_schema(Vector2i(0, 0)) == schema_active, "schema 同一实例（保留）")


## 7. DORMANT → UNLOADED 丢弃 schema
func _test_dormant_to_unloaded_drops_schema() -> void:
	print("-- DORMANT → UNLOADED 丢弃 schema")
	var ctx: Dictionary = _make_context()
	var vs: VisionSystem = ctx["vision"]
	var cm: ChunkManager = ctx["chunk"]

	# 先到 DORMANT
	vs._tile_state[Vector2i(5, 5)] = VisionSystem.TileState.FOG
	cm.aggregate_chunk(Vector2i(0, 0))
	_assert(cm.get_chunk_schema(Vector2i(0, 0)) != null, "DORMANT schema 存在")

	# 清掉所有 FOG → UNLOADED
	vs._tile_state.clear()
	cm.aggregate_chunk(Vector2i(0, 0))
	_assert(cm.get_chunk_state(Vector2i(0, 0)) == ChunkRecord.State.UNLOADED, "已转 UNLOADED")
	_assert(cm.get_chunk_schema(Vector2i(0, 0)) == null, "schema 已丢弃")


## 8. chunk_state_changed signal 发射
func _test_chunk_state_changed_signal() -> void:
	print("-- chunk_state_changed signal")
	var ctx: Dictionary = _make_context()
	var vs: VisionSystem = ctx["vision"]
	var cm: ChunkManager = ctx["chunk"]

	_signal_captured.clear()
	cm.chunk_state_changed.connect(_on_chunk_state_changed)

	# 触发 UNLOADED → ACTIVE
	var src: VisionSource = VisionSource.new(Vector2i(2, 2), 1)
	vs.register_source(src)

	# 至少 1 次发射（chunk(0,0) UNLOADED → ACTIVE）
	_assert(_signal_captured.size() >= 1, "至少 1 次 signal 发射（实际 %d）" % _signal_captured.size())

	# 验证 signal 携带数据正确
	var first: Dictionary = _signal_captured[0]
	_assert(first["new_state"] == ChunkRecord.State.ACTIVE, "首次 signal new_state = ACTIVE")
	_assert(first["old_state"] == ChunkRecord.State.UNLOADED, "首次 signal old_state = UNLOADED")
	_assert(first["schema"] != null, "首次 signal 携带 schema")

	cm.chunk_state_changed.disconnect(_on_chunk_state_changed)


## 9. get_active_chunks 查询
func _test_get_active_chunks_query() -> void:
	print("-- get_active_chunks")
	var ctx: Dictionary = _make_context()
	var vs: VisionSystem = ctx["vision"]
	var cm: ChunkManager = ctx["chunk"]

	# 覆盖 chunk(0,0) 中心
	vs.register_source(VisionSource.new(Vector2i(8, 8), 2))
	# 覆盖 chunk(1,1) 中心
	vs.register_source(VisionSource.new(Vector2i(24, 24), 2))

	var actives: Array[Vector2i] = cm.get_active_chunks()
	_assert(actives.has(Vector2i(0, 0)), "包含 (0,0)")
	_assert(actives.has(Vector2i(1, 1)), "包含 (1,1)")


## 10. 增量更新：tile 变化只重算所在 chunk
func _test_incremental_aggregation_on_vision_change() -> void:
	print("-- 增量聚合")
	var ctx: Dictionary = _make_context()
	var vs: VisionSystem = ctx["vision"]
	var cm: ChunkManager = ctx["chunk"]

	_signal_captured.clear()
	cm.chunk_state_changed.connect(_on_chunk_state_changed)

	# 覆盖 chunk(0,0) 一格
	vs.register_source(VisionSource.new(Vector2i(5, 5), 0))
	# 0 半径 = 单格覆盖；只触发 chunk(0,0) 的聚合
	var unique_chunks: Dictionary = {}
	for entry in _signal_captured:
		unique_chunks[entry["coord"]] = true
	_assert(unique_chunks.size() == 1, "仅 1 个 chunk 触发聚合（实际 %d）" % unique_chunks.size())
	_assert(unique_chunks.has(Vector2i(0, 0)), "且为 chunk(0,0)")

	cm.chunk_state_changed.disconnect(_on_chunk_state_changed)


# ─────────────────────────────────────
# 助手
# ─────────────────────────────────────

func _on_chunk_state_changed(coord: Vector2i, new_state: int, old_state: int, schema: ChunkSchema) -> void:
	_signal_captured.append({
		"coord": coord,
		"new_state": new_state,
		"old_state": old_state,
		"schema": schema,
	})


## 构造一对 VisionSystem + ChunkManager（独立实例，互不污染）
func _make_context() -> Dictionary:
	var cfg: VisionConfig = VisionConfig.new()
	cfg.fog_delay_turns = 0
	cfg.shadow_decay_turns = 10
	cfg.poi_spawn_rate_per_chunk = 0.0  # 测试不需要 POI 干扰

	var vs: VisionSystem = VisionSystem.new()
	vs.setup(cfg)

	var cm: ChunkManager = ChunkManager.new()
	cm.setup(cfg, vs, 12345)

	return {"vision": vs, "chunk": cm, "config": cfg}


func _assert(condition: bool, msg: String) -> void:
	if condition:
		print("  ✓ %s" % msg)
	else:
		printerr("  ✗ %s" % msg)
		_failed += 1
