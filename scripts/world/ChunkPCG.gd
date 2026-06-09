class_name ChunkPCG
extends RefCounted
## chunk 流式 PCG（L1.1 §2.4 / §3.4；L1.3b 阶段 A 地形权威收敛）
##
## 设计原文：
##   tile-advanture-design/无限地图实装/L1.1_视野循环与chunk底座_MVP.md §2.4
##   tile-advanture-design/无限地图实装/L1.3b_无限化地基_MVP.md §五（缺陷 1/2/3）
##
## 职责：
##   - 给定 (world_seed, chunk_coord) 确定性生成一份 ChunkSchema
##   - 同输入永远同输出 → "折返回旧地，地形/POI 位置原样"的工程基础
##   - L1.3b 起成为地图地形的【权威生成源】：核心区（MapGenerator）与流式 chunk
##     共用本文件的 make_terrain_noise + terrain_at，杜绝双源地形冲突（缺陷 4）
##
## L1.3b 阶段 A 关键改动：
##   - 缺陷 1：地形改【全局单一 noise 场】（noise.seed = world_seed，不再 per-chunk 子 seed），
##     世界坐标采样 → 相邻 chunk 边界天然连续，无拼接缝
##   - 缺陷 2：地形 3 段（草/山/水）→ 4 级，对齐 MapSchema.TerrainType（MOUNTAIN/HIGHLAND/
##     FLATLAND/LOWLAND）；噪声 SIMPLEX→PERLIN（与核心区老地图同分布，复用其阈值才有意义）
##   - 缺陷 3：chunk_size 由调用方传入（消费 vision_config.chunk_size），不再硬编码
##
## 枚举对齐策略（L1.3b 解法 A：值约定，不符号引用）：
##   terrain_at 返回【整数值】0-3，与 MapSchema.TerrainType 数值一致，但本文件不 import
##   MapSchema，避免 MapSchema→ChunkManager→ChunkPCG→MapSchema 环依赖；一致性由测试守卫。
##
## 形态选择：纯静态方法 —— PCG 是无状态函数，不需要实例；
## 测试套件可独立调用，不依赖任何 Node 树。

## chunk 边长默认值（仅作为可选参数 fallback；运行时由 vision_config.chunk_size 传入）
const DEFAULT_CHUNK_SIZE: int = 16

## L1.1 占位 POI 类型枚举（与 PersistentSlot.Type 暂未对齐）
## 0 = NONE / 1 = NEUTRAL_VILLAGE（L1.1 唯一类型）
## L1.2 据点机制接入时统一到 PersistentSlot.Type 完整枚举
const POI_TYPE_NONE: int = 0
const POI_TYPE_NEUTRAL_VILLAGE: int = 1

# ─────────────────────────────────────
# 地形权威常量（L1.3b 阶段 A：从 pcg_config.csv 老地图值复制为内部常量）
# 阈值调参化留议题 12「PCG 内容质量增强」独立 MVP，本阶段不引入 config schema
# ─────────────────────────────────────

## 噪声频率（越低地形过渡越平滑）；沿用原 pcg_config.csv noise_frequency 老地图值（该 CSV 行已随地形退役删除）
const TERRAIN_FREQUENCY: float = 0.08
## 噪声值 > 此阈值 → MOUNTAIN（0）
const THRESHOLD_MOUNTAIN: float = 0.45
## 噪声值 > 此阈值 → HIGHLAND（1）
const THRESHOLD_HIGHLAND: float = 0.15
## 噪声值 > 此阈值 → FLATLAND（2），否则 → LOWLAND（3）
const THRESHOLD_FLATLAND: float = -0.25


# ─────────────────────────────────────
# 地形权威原语（核心区与流式 chunk 共用，保证同源一致）
# ─────────────────────────────────────

## 构造【全局单一】地形 noise 场（缺陷 1）
## 同一 world_seed 在任意坐标采样均来自同一连续噪声场 → chunk 边界无突变 + 折返一致
## 调用方：本文件 _generate_terrain（流式） + MapGenerator/MapSchema（核心区，经注入）
static func make_terrain_noise(world_seed: int) -> FastNoiseLite:
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = world_seed
	noise.frequency = TERRAIN_FREQUENCY
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	return noise


## 按全局 noise 场查询世界格 (world_x, world_y) 的地形类型【整数值】
## 返回 0-3，与 MapSchema.TerrainType（MOUNTAIN=0/HIGHLAND=1/FLATLAND=2/LOWLAND=3）数值一致
## 解法 A：值约定，不符号引用 MapSchema，避免环依赖
static func terrain_at(noise: FastNoiseLite, world_x: int, world_y: int) -> int:
	var n: float = noise.get_noise_2d(float(world_x), float(world_y))
	if n > THRESHOLD_MOUNTAIN:
		return 0  # MOUNTAIN
	elif n > THRESHOLD_HIGHLAND:
		return 1  # HIGHLAND
	elif n > THRESHOLD_FLATLAND:
		return 2  # FLATLAND
	else:
		return 3  # LOWLAND


# ─────────────────────────────────────
# chunk 生成
# ─────────────────────────────────────

## 生成一个 chunk 的 schema
## world_seed: 整局 seed
## coord: chunk 坐标（chunk grid）
## poi_spawn_rate: 每 chunk POI 概率（[0,1]）
## chunk_size: chunk 边长（消费 vision_config.chunk_size；默认 16 保持旧调用/测试兼容）
## 返回：完整填充的 ChunkSchema
static func generate(
	world_seed: int,
	coord: Vector2i,
	poi_spawn_rate: float = 0.3,
	chunk_size: int = DEFAULT_CHUNK_SIZE
) -> ChunkSchema:
	var schema: ChunkSchema = ChunkSchema.new()
	schema.coord = coord
	schema.size = chunk_size
	schema.terrain = _generate_terrain(world_seed, coord, chunk_size)
	schema.pois = _generate_pois(world_seed, coord, poi_spawn_rate, chunk_size)
	return schema


## 地形层：全局单一 noise 场 + 世界坐标采样（缺陷 1）+ 4 级对齐 TerrainType（缺陷 2）
static func _generate_terrain(world_seed: int, coord: Vector2i, chunk_size: int) -> PackedByteArray:
	var noise: FastNoiseLite = make_terrain_noise(world_seed)

	var result: PackedByteArray = PackedByteArray()
	result.resize(chunk_size * chunk_size)
	for local_y in range(chunk_size):
		for local_x in range(chunk_size):
			var world_x: int = coord.x * chunk_size + local_x
			var world_y: int = coord.y * chunk_size + local_y
			result[local_y * chunk_size + local_x] = terrain_at(noise, world_x, world_y)
	return result


## POI 层：极简（每 chunk 概率 spawn 1 个 NEUTRAL_VILLAGE）
## 避开边界 2 格，避免后续视野跨 chunk 时贴边问题
## L1.1 后期 PCG 内容质量批升级
static func _generate_pois(
	world_seed: int,
	coord: Vector2i,
	spawn_rate: float,
	chunk_size: int
) -> Array[Dictionary]:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = _hash_subseed(world_seed, coord, "poi")

	var pois: Array[Dictionary] = []
	if rng.randf() < spawn_rate:
		# 在 chunk 内随机一格（避开边界 2 格）
		var local_x: int = rng.randi_range(2, chunk_size - 3)
		var local_y: int = rng.randi_range(2, chunk_size - 3)
		var entry: Dictionary = {
			"pos": Vector2i(coord.x * chunk_size + local_x, coord.y * chunk_size + local_y),
			"type": POI_TYPE_NEUTRAL_VILLAGE,
			"schema_id": 0,
		}
		pois.append(entry)
	return pois


## 子 seed 哈希：把 (world_seed, coord, tag) 哈希成 int seed
## L1.3b 起【仅 POI 层】使用（地形改全局 noise 场，不再用子 seed —— 缺陷 1）
## 确定性 + 抗碰撞：同输入永远同输出
static func _hash_subseed(world_seed: int, coord: Vector2i, tag: String) -> int:
	var key: String = "%d_%d_%d_%s" % [world_seed, coord.x, coord.y, tag]
	return key.hash()
