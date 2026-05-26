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
## 与现有地形系统的衔接（L1.1 占位）：
##   terrain 字节当前使用 3 类（0=草地/1=山地/2=水域），与现有 PersistentSlot 类型未完全对齐；
##   L1.2 据点机制 + 完整地形规则时再统一枚举。

const CHUNK_SIZE: int = 16


## chunk 坐标（chunk grid 单位；世界格起点 = coord * CHUNK_SIZE）
var coord: Vector2i

## 地形类型字节数组（CHUNK_SIZE * CHUNK_SIZE 个字节，本地索引 = local_y * CHUNK_SIZE + local_x）
## L1.1 占位地形枚举：0=草地 / 1=山地 / 2=水域
var terrain: PackedByteArray

## POI 静态列表
## 每条 = Dictionary{ pos: Vector2i, type: int, schema_id: int }
## L1.1 极简：仅生成 NEUTRAL_VILLAGE（type=1）；schema_id 预留扩展
var pois: Array[Dictionary]


func _init() -> void:
	coord = Vector2i.ZERO
	terrain = PackedByteArray()
	pois = []


## 给定本地格坐标 (local_x, local_y) 返回 terrain 字节
## local 范围 [0, CHUNK_SIZE)；越界返回 0（草地）
func get_terrain_local(local_x: int, local_y: int) -> int:
	if local_x < 0 or local_x >= CHUNK_SIZE or local_y < 0 or local_y >= CHUNK_SIZE:
		return 0
	var idx: int = local_y * CHUNK_SIZE + local_x
	if idx >= terrain.size():
		return 0
	return terrain[idx]


## 工具：世界格坐标 → 本地格坐标（基于 self.coord）
func world_to_local(world_pos: Vector2i) -> Vector2i:
	return Vector2i(world_pos.x - coord.x * CHUNK_SIZE, world_pos.y - coord.y * CHUNK_SIZE)
