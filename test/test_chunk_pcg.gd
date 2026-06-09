extends SceneTree
## ChunkPCG 确定性 + 内容验证（L1.1 §7 场景 3 / §5 改动 6）
##
## 运行：
##   /mnt/e/Godot/.../Godot.exe --headless --path "E:\Godot\project\tile-adventure" -s test/test_chunk_pcg.gd
##
## 验证范围：
##   1. 同 (seed, coord) → 同 schema（折返一致性的工程基础）
##   2. 不同 coord → 不同 schema（无碰撞）
##   3. terrain 字节长度 = CHUNK_SIZE²
##   4. POI 概率边界：spawn_rate=0 必无 POI；spawn_rate=1 必生成
##   5. POI 类型仅 NEUTRAL_VILLAGE（L1.1 占位）
##   6. POI 位置避开边界 2 格

var _failed: int = 0


func _init() -> void:
	print("=== ChunkPCG 冒烟测试 ===")

	_test_determinism_same_input()
	_test_different_coord_different_schema()
	_test_terrain_byte_length()
	_test_terrain_values_in_range()
	_test_poi_spawn_rate_zero()
	_test_poi_spawn_rate_one()
	_test_poi_type_is_neutral_village()
	_test_poi_position_avoids_edges()
	_test_subseed_tag_isolation()

	if _failed > 0:
		printerr("✗ 共 %d 项失败" % _failed)
		quit(1)
	else:
		print("✓ 全部通过")
		quit(0)


# ─────────────────────────────────────
# 用例
# ─────────────────────────────────────

## 1. 同 (seed, coord) → 同 schema
func _test_determinism_same_input() -> void:
	print("-- 同 (seed, coord) 生成同 schema")
	var s1: ChunkSchema = ChunkPCG.generate(12345, Vector2i(3, 5), 0.5)
	var s2: ChunkSchema = ChunkPCG.generate(12345, Vector2i(3, 5), 0.5)
	_assert(s1.terrain == s2.terrain, "terrain 字节数组完全一致")
	_assert(s1.pois.size() == s2.pois.size(), "POI 数量一致 (%d vs %d)" % [s1.pois.size(), s2.pois.size()])
	if s1.pois.size() > 0 and s2.pois.size() > 0:
		_assert(s1.pois[0]["pos"] == s2.pois[0]["pos"], "POI 位置一致")


## 2. 不同 coord → 不同 schema（无明显碰撞）
func _test_different_coord_different_schema() -> void:
	print("-- 不同 coord 生成不同 schema")
	var s1: ChunkSchema = ChunkPCG.generate(12345, Vector2i(0, 0), 0.5)
	var s2: ChunkSchema = ChunkPCG.generate(12345, Vector2i(100, 100), 0.5)
	# terrain 不可能完全一致（noise 在不同位置不同）
	_assert(s1.terrain != s2.terrain, "不同 coord 的 terrain 不同")


## 3. terrain 字节长度 = CHUNK_SIZE²
func _test_terrain_byte_length() -> void:
	print("-- terrain 字节长度 = CHUNK_SIZE²")
	var s: ChunkSchema = ChunkPCG.generate(1, Vector2i.ZERO, 0.5)
	_assert(s.terrain.size() == 16 * 16, "terrain.size() = 256，实际 %d" % s.terrain.size())


## 4. terrain 取值范围 [0, 3]（L1.3b 阶段 A：4 级对齐 MapSchema.TerrainType）
func _test_terrain_values_in_range() -> void:
	print("-- terrain 取值范围 [0, 3]")
	var s: ChunkSchema = ChunkPCG.generate(42, Vector2i(7, 11), 0.0)
	var has_out_of_range: bool = false
	for i in range(s.terrain.size()):
		if s.terrain[i] < 0 or s.terrain[i] > 3:
			has_out_of_range = true
			break
	_assert(not has_out_of_range, "所有 terrain 字节在 [0, 3] 内")


## 5. spawn_rate = 0 必无 POI
func _test_poi_spawn_rate_zero() -> void:
	print("-- spawn_rate=0 必无 POI")
	var has_any: bool = false
	for i in range(20):
		var s: ChunkSchema = ChunkPCG.generate(i * 7919, Vector2i(i, i), 0.0)
		if s.pois.size() > 0:
			has_any = true
			break
	_assert(not has_any, "20 次随机 coord 均无 POI")


## 6. spawn_rate = 1 必生成
func _test_poi_spawn_rate_one() -> void:
	print("-- spawn_rate=1 必生成")
	var miss_count: int = 0
	for i in range(20):
		var s: ChunkSchema = ChunkPCG.generate(i * 7919, Vector2i(i, i), 1.0)
		if s.pois.size() == 0:
			miss_count += 1
	_assert(miss_count == 0, "20 次随机 coord 全部生成 POI（miss = %d）" % miss_count)


## 7. POI 类型仅 NEUTRAL_VILLAGE
func _test_poi_type_is_neutral_village() -> void:
	print("-- POI 类型为 NEUTRAL_VILLAGE")
	var s: ChunkSchema = ChunkPCG.generate(99, Vector2i.ZERO, 1.0)
	_assert(s.pois.size() > 0, "spawn_rate=1 应至少 1 个 POI")
	if s.pois.size() > 0:
		_assert(int(s.pois[0]["type"]) == ChunkPCG.POI_TYPE_NEUTRAL_VILLAGE, "POI type = NEUTRAL_VILLAGE")


## 8. POI 位置避开 chunk 边界 2 格
func _test_poi_position_avoids_edges() -> void:
	print("-- POI 位置避开边界 2 格")
	var out_of_safe: bool = false
	for i in range(50):
		var coord: Vector2i = Vector2i(i, i * 2)
		var s: ChunkSchema = ChunkPCG.generate(i * 31, coord, 1.0)
		if s.pois.size() > 0:
			var local: Vector2i = s.world_to_local(s.pois[0]["pos"])
			if local.x < 2 or local.x > 13 or local.y < 2 or local.y > 13:
				out_of_safe = true
				print("    意外 POI 位置：world=%s local=%s" % [str(s.pois[0]["pos"]), str(local)])
				break
	_assert(not out_of_safe, "50 次生成的 POI 全部在 [2, 13] 安全区")


## 9. 子 seed tag 隔离：地形 noise 和 POI rng 用不同子 seed
##     不直接测试内部哈希，但保证同 (seed, coord) 下 terrain 和 POI 位置不强相关
func _test_subseed_tag_isolation() -> void:
	print("-- 子 seed tag 隔离")
	# 不同 spawn_rate 仅影响 POI，不影响 terrain
	var s1: ChunkSchema = ChunkPCG.generate(2026, Vector2i(1, 1), 0.0)
	var s2: ChunkSchema = ChunkPCG.generate(2026, Vector2i(1, 1), 1.0)
	_assert(s1.terrain == s2.terrain, "spawn_rate 不影响 terrain")


# ─────────────────────────────────────
# 助手
# ─────────────────────────────────────

func _assert(condition: bool, msg: String) -> void:
	if condition:
		print("  ✓ %s" % msg)
	else:
		printerr("  ✗ %s" % msg)
		_failed += 1
