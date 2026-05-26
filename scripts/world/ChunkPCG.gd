class_name ChunkPCG
extends RefCounted
## chunk 流式 PCG（L1.1 §2.4 / §3.4）
##
## 设计原文：
##   tile-advanture-design/无限地图实装/L1.1_视野循环与chunk底座_MVP.md §2.4
##
## 职责：
##   - 给定 (world_seed, chunk_coord) 确定性生成一份 ChunkSchema
##   - 同输入永远同输出 → "折返回旧地，地形/POI 位置原样"的工程基础
##   - L1.1 极简：地形 noise + 单类型 POI（NEUTRAL_VILLAGE）+ 占位密度
##
## 后续扩展（独立 MVP「PCG 内容质量增强」）：
##   - 完整 POI 分布规则（密度梯度 / 多类型混合 / 势力分布 / 城镇 vs 村庄）
##   - 自然地形特征（河流 / 山脉 / 平原过渡）
##   - 与 PersistentSlot.Type 枚举正式对齐
##
## 形态选择：纯静态方法 —— PCG 是无状态函数，不需要实例；
## 测试套件可独立调用，不依赖任何 Node 树。

const CHUNK_SIZE: int = 16

## L1.1 占位 POI 类型枚举（与 PersistentSlot.Type 暂未对齐）
## 0 = NONE / 1 = NEUTRAL_VILLAGE（L1.1 唯一类型）
## L1.2 据点机制接入时统一到 PersistentSlot.Type 完整枚举
const POI_TYPE_NONE: int = 0
const POI_TYPE_NEUTRAL_VILLAGE: int = 1


## 生成一个 chunk 的 schema
## world_seed: 整局 seed
## coord: chunk 坐标（chunk grid）
## poi_spawn_rate: 每 chunk POI 概率（[0,1]）
## 返回：完整填充的 ChunkSchema
static func generate(world_seed: int, coord: Vector2i, poi_spawn_rate: float = 0.3) -> ChunkSchema:
	var schema: ChunkSchema = ChunkSchema.new()
	schema.coord = coord
	schema.terrain = _generate_terrain(world_seed, coord)
	schema.pois = _generate_pois(world_seed, coord, poi_spawn_rate)
	return schema


## 地形层：FastNoiseLite + 子 seed
## 三段划分：noise < -0.5 水域 / -0.5 ~ 0.5 草地 / > 0.5 山地
## 阈值占位，PCG 内容质量批回看
static func _generate_terrain(world_seed: int, coord: Vector2i) -> PackedByteArray:
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = _hash_subseed(world_seed, coord, "terrain")
	noise.frequency = 0.08
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX

	var result: PackedByteArray = PackedByteArray()
	result.resize(CHUNK_SIZE * CHUNK_SIZE)
	for local_y in range(CHUNK_SIZE):
		for local_x in range(CHUNK_SIZE):
			var world_x: int = coord.x * CHUNK_SIZE + local_x
			var world_y: int = coord.y * CHUNK_SIZE + local_y
			var n: float = noise.get_noise_2d(world_x, world_y)
			# noise ∈ [-1,1] → 三段地形
			var terrain_type: int = 0  # 草地
			if n < -0.5:
				terrain_type = 2  # 水域
			elif n > 0.5:
				terrain_type = 1  # 山地
			result[local_y * CHUNK_SIZE + local_x] = terrain_type
	return result


## POI 层：极简（每 chunk 概率 spawn 1 个 NEUTRAL_VILLAGE）
## 避开边界 2 格，避免后续视野跨 chunk 时贴边问题
## L1.1 后期 PCG 内容质量批升级
static func _generate_pois(world_seed: int, coord: Vector2i, spawn_rate: float) -> Array[Dictionary]:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = _hash_subseed(world_seed, coord, "poi")

	var pois: Array[Dictionary] = []
	if rng.randf() < spawn_rate:
		# 在 chunk 内随机一格（避开边界 2 格）
		var local_x: int = rng.randi_range(2, CHUNK_SIZE - 3)
		var local_y: int = rng.randi_range(2, CHUNK_SIZE - 3)
		var entry: Dictionary = {
			"pos": Vector2i(coord.x * CHUNK_SIZE + local_x, coord.y * CHUNK_SIZE + local_y),
			"type": POI_TYPE_NEUTRAL_VILLAGE,
			"schema_id": 0,
		}
		pois.append(entry)
	return pois


## 子 seed 哈希：把 (world_seed, coord, tag) 哈希成 int seed
## 确定性 + 抗碰撞：同输入永远同输出，不同 tag 不同子 seed（地形与 POI 不共用 noise）
static func _hash_subseed(world_seed: int, coord: Vector2i, tag: String) -> int:
	var key: String = "%d_%d_%d_%s" % [world_seed, coord.x, coord.y, tag]
	return key.hash()
