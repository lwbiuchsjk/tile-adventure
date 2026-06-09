class_name ChunkSchema
extends RefCounted
## chunk 内容快照（L1.1 §2.4 / §3.5）
##
## 设计原文：
##   tile-advanture-design/无限地图实装/L1.1_视野循环与chunk底座_MVP.md §2.4 / §3.5
##
## 职责：
##   - 承载 16×16 格的地形数据 + POI 列表
##   - 由 ChunkPCG.generate 产出；由 ChunkRecord 持有
##   - ACTIVE/DORMANT 状态下保留；UNLOADED 后丢弃
##     （下次激活时 ChunkPCG 按 noise 重生成；地形/POI 位置一致，动态状态不保留）
##
## 与现有地形系统的衔接（L1.3b 阶段 A 起）：
##   terrain 字节使用 4 级，对齐 MapSchema.TerrainType（0=MOUNTAIN/1=HIGHLAND/2=FLATLAND/3=LOWLAND）；
##   由 ChunkPCG.terrain_at 产出（值约定，详见 ChunkPCG 枚举对齐策略）。

## chunk 边长默认值（仅作 fallback；实例 size 字段由 ChunkPCG.generate 按 vision_config.chunk_size 设置）
const DEFAULT_CHUNK_SIZE: int = 16


## chunk 坐标（chunk grid 单位；世界格起点 = coord * size）
var coord: Vector2i

## 本 chunk 的边长（格）；由 ChunkPCG.generate 设置（消费 vision_config.chunk_size，缺陷 3）
var size: int = DEFAULT_CHUNK_SIZE

## 地形类型字节数组（size * size 个字节，本地索引 = local_y * size + local_x）
## L1.3b 起 4 级地形枚举，对齐 MapSchema.TerrainType（0=MOUNTAIN/1=HIGHLAND/2=FLATLAND/3=LOWLAND）
var terrain: PackedByteArray

## POI 静态列表
## 每条 = Dictionary{ pos: Vector2i, type: int, schema_id: int }
## L1.1 极简：仅生成 NEUTRAL_VILLAGE（type=1）；schema_id 预留扩展
var pois: Array[Dictionary]


func _init() -> void:
	coord = Vector2i.ZERO
	size = DEFAULT_CHUNK_SIZE
	terrain = PackedByteArray()
	pois = []


## 给定本地格坐标 (local_x, local_y) 返回 terrain 字节
## local 范围 [0, size)；越界返回 0（MOUNTAIN，视作不可通行兜底）
func get_terrain_local(local_x: int, local_y: int) -> int:
	if local_x < 0 or local_x >= size or local_y < 0 or local_y >= size:
		return 0
	var idx: int = local_y * size + local_x
	if idx >= terrain.size():
		return 0
	return terrain[idx]


## 工具：世界格坐标 → 本地格坐标（基于 self.coord）
func world_to_local(world_pos: Vector2i) -> Vector2i:
	return Vector2i(world_pos.x - coord.x * size, world_pos.y - coord.y * size)
