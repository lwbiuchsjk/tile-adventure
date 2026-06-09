extends SceneTree
## L1.3b 阶段 A 地形权威收敛 冒烟测试（无限化地基）
##
## 运行：
##   /mnt/e/Godot/.../Godot.exe --headless --path "E:\Godot\project\tile-adventure" -s test/test_l13b_terrain_oracle.gd
##
## 设计原文：
##   tile-advanture-design/无限地图实装/L1.3b_无限化地基_MVP.md §五 / §七
##
## 验证范围（对应设计 §七 headless 场景）：
##   1  确定性复现：同 (seed, coord) 多次生成 + 退化再激活，terrain 完全一致
##   1b chunk 边界连续（缺陷 1 验收哨兵）：相邻 chunk 共享边界两侧 noise 值连续、无突变
##   2  无界坐标查询：远离原点的大坐标查地形不越界 / 不异常
##   3  核心区(MapSchema 无限模式) 与 流式(ChunkPCG chunk) 地形同源一致（缺陷 4）
##   4  chunk_size 消费（缺陷 3）：generate 传 chunk_size 改变 terrain 尺寸
##   5  MapSchema 双模：无限模式 get_terrain/altitude 任意坐标有效、set_terrain no-op

var _failed: int = 0


func _init() -> void:
	print("=== L1.3b 地形权威收敛 冒烟测试 ===")

	_test_determinism_and_reactivation()
	_test_chunk_boundary_continuity()
	_test_unbounded_query()
	_test_core_vs_chunk_consistency()
	_test_chunk_size_param()
	_test_mapschema_infinite_mode()

	if _failed > 0:
		printerr("✗ 共 %d 项失败" % _failed)
		quit(1)
	else:
		print("✓ 全部通过")
		quit(0)


# ─────────────────────────────────────
# 用例
# ─────────────────────────────────────

## 1. 确定性复现 + 退化再激活一致
func _test_determinism_and_reactivation() -> void:
	print("-- 确定性复现 + 退化再激活一致")
	var seed: int = 20260608
	var coord: Vector2i = Vector2i(4, -3)
	var s1: ChunkSchema = ChunkPCG.generate(seed, coord, 0.5)
	var s2: ChunkSchema = ChunkPCG.generate(seed, coord, 0.5)
	_assert(s1.terrain == s2.terrain, "同 (seed, coord) terrain 完全一致")
	# 模拟 chunk UNLOADED 后再激活：丢弃 s1，重新生成应与首次一致
	var s_reactivate: ChunkSchema = ChunkPCG.generate(seed, coord, 0.5)
	_assert(s_reactivate.terrain == s1.terrain, "退化(UNLOADED)再激活 terrain 一致")


## 1b. chunk 边界连续（缺陷 1 验收哨兵）
## 全局单一 noise 场下，相邻 chunk 共享边界两侧的世界格 noise 值应连续；
## per-chunk 子 seed（旧实现）时此断言必败 → 作回归哨兵
func _test_chunk_boundary_continuity() -> void:
	print("-- chunk 边界连续（缺陷 1 哨兵）")
	var seed: int = 555
	var noise: FastNoiseLite = ChunkPCG.make_terrain_noise(seed)
	# chunk(0,0) 与 chunk(1,0) 边界：世界列 x=15（chunk0 末）与 x=16（chunk1 首）
	var max_diff: float = 0.0
	for y in range(0, 16):
		var n_left: float = noise.get_noise_2d(15.0, float(y))
		var n_right: float = noise.get_noise_2d(16.0, float(y))
		max_diff = maxf(max_diff, absf(n_right - n_left))
	# 单步梯度阈值：freq=0.08 的 Perlin 单格变化远小于 0.5；旧 per-chunk 实现会出现 ~1.0+ 突变
	_assert(max_diff < 0.5, "边界两侧 noise 单步差 max=%.4f < 0.5（无拼接缝）" % max_diff)


## 2. 无界远坐标查询
func _test_unbounded_query() -> void:
	print("-- 无界远坐标查询")
	var noise: FastNoiseLite = ChunkPCG.make_terrain_noise(888)
	var far_points: Array[Vector2i] = [
		Vector2i(10000, -8000), Vector2i(-123456, 654321), Vector2i(0, 0), Vector2i(-1, -1),
	]
	var all_valid: bool = true
	for p in far_points:
		var t: int = ChunkPCG.terrain_at(noise, p.x, p.y)
		if t < 0 or t > 3:
			all_valid = false
			print("    意外 terrain 值 %d @ %s" % [t, str(p)])
	_assert(all_valid, "所有远坐标 terrain_at 返回 [0,3]，无越界/异常")


## 3. 核心区(MapSchema 无限模式) 与 流式(ChunkPCG chunk) 地形同源一致（缺陷 4）
func _test_core_vs_chunk_consistency() -> void:
	print("-- 核心区 vs 流式 chunk 地形同源一致（缺陷 4）")
	var seed: int = 31337
	var ms: MapSchema = MapSchema.new()
	ms.set_infinite_terrain(seed)
	var mismatches: int = 0
	# 抽样若干世界格，比对 MapSchema.get_terrain 与对应 chunk 的本地地形字节
	var samples: Array[Vector2i] = [
		Vector2i(3, 7), Vector2i(20, 5), Vector2i(-9, 12), Vector2i(48, -33), Vector2i(0, 0),
	]
	for wp in samples:
		var cc: Vector2i = ChunkManager.tile_to_chunk(wp)  # 默认 16
		var chunk: ChunkSchema = ChunkPCG.generate(seed, cc, 0.0)
		var local: Vector2i = chunk.world_to_local(wp)
		var chunk_t: int = chunk.get_terrain_local(local.x, local.y)
		var ms_t: int = int(ms.get_terrain(wp.x, wp.y))
		if chunk_t != ms_t:
			mismatches += 1
			print("    不一致 @ %s：MapSchema=%d chunk=%d" % [str(wp), ms_t, chunk_t])
	_assert(mismatches == 0, "抽样世界格 MapSchema 地形 == chunk 地形（单一权威源）")


## 4. chunk_size 消费（缺陷 3）
func _test_chunk_size_param() -> void:
	print("-- chunk_size 参数消费（缺陷 3）")
	var s8: ChunkSchema = ChunkPCG.generate(1, Vector2i.ZERO, 0.0, 8)
	_assert(s8.size == 8, "ChunkSchema.size = 8")
	_assert(s8.terrain.size() == 8 * 8, "terrain 字节数 = 64，实际 %d" % s8.terrain.size())
	var s_default: ChunkSchema = ChunkPCG.generate(1, Vector2i.ZERO, 0.0)
	_assert(s_default.size == 16, "默认 chunk_size = 16（旧调用兼容）")
	_assert(s_default.terrain.size() == 16 * 16, "默认 terrain 字节数 = 256")


## 5. MapSchema 双模：无限模式
func _test_mapschema_infinite_mode() -> void:
	print("-- MapSchema 无限模式双模")
	var ms: MapSchema = MapSchema.new()
	ms.init(32, 24, false)  # 无限模式不分配 terrain_grid
	ms.terrain_costs = {
		MapSchema.TerrainType.MOUNTAIN: INF,
		MapSchema.TerrainType.HIGHLAND: 2.0,
		MapSchema.TerrainType.FLATLAND: 1.0,
		MapSchema.TerrainType.LOWLAND: 1.0,
	}
	ms.set_infinite_terrain(2026)
	_assert(ms.is_infinite(), "is_infinite() = true")
	_assert(ms.terrain_grid.is_empty(), "无限模式 terrain_grid 为空（不预分配，病根 fix）")

	# 任意大坐标地形有效（脱离 is_in_bounds）
	var far: Vector2i = Vector2i(9999, -9999)
	var t: int = int(ms.get_terrain(far.x, far.y))
	_assert(t >= 0 and t <= 3, "远坐标 get_terrain 返回 [0,3]，实际 %d" % t)
	var alt: int = ms.get_terrain_altitude(far.x, far.y)
	_assert(alt >= 0 and alt <= 3, "远坐标 get_terrain_altitude 有效，实际 %d" % alt)

	# is_passable / get_terrain_cost 路由到 noise（任意坐标可查）
	var cost: float = ms.get_terrain_cost(far.x, far.y)
	_assert(cost > 0.0, "远坐标 get_terrain_cost 有效（>0），实际 %.2f" % cost)

	# set_terrain 无限模式 no-op：调用后地形不变
	var before: int = int(ms.get_terrain(5, 5))
	ms.set_terrain(5, 5, MapSchema.TerrainType.MOUNTAIN)
	var after: int = int(ms.get_terrain(5, 5))
	_assert(before == after, "无限模式 set_terrain no-op（地形由 noise 确定，不可就地覆写）")


# ─────────────────────────────────────
# helper
# ─────────────────────────────────────

func _assert(condition: bool, msg: String) -> void:
	if condition:
		print("  ✓ %s" % msg)
	else:
		printerr("  ✗ %s" % msg)
		_failed += 1
