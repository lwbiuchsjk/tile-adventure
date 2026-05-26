class_name ChunkManager
extends Node
## chunk 三态生命周期管理（L1.1 §2.2 / §2.3 / §3.2）
##
## 设计原文：
##   tile-advanture-design/无限地图实装/L1.1_视野循环与chunk底座_MVP.md §2.2 / §2.3 / §3.2 / §4.2
##
## 职责：
##   - 维护 chunk 坐标 → ChunkRecord 的字典
##   - 监听 VisionSystem.tile_state_changed，按聚合规则增量更新 chunk 状态
##   - chunk 状态变化时触发对应行为（生成 schema / 丢弃 schema）
##   - 发射 chunk_state_changed 供 WorldMap 渲染层 / 实例管理层订阅
##
## 聚合规则（L1.1 §2.3，与 VisionSystem.aggregate_tiles 一致）：
##   chunk 含任何 NORMAL 格 → ACTIVE
##   chunk 含任何 FOG 格    → DORMANT
##   chunk 全部 SHADOW      → UNLOADED
##
## 增量更新策略：
##   每次 tile_state_changed 只重算该 tile 所在 chunk（O(CHUNK_SIZE²) = 256 格扫描）
##   不全图扫描，节省大量计算


const CHUNK_SIZE: int = 16


## chunk 坐标 → ChunkRecord
var _chunks: Dictionary = {}

## 配置 + 依赖
var _config: VisionConfig = null
var _vision: VisionSystem = null
var _world_seed: int = 0


## 信号：chunk 状态变化时发射，供 WorldMap 渲染层 / 实例管理层订阅
## 参数：coord（chunk 坐标）、new_state、old_state、schema（target=UNLOADED 时为 null）
signal chunk_state_changed(coord: Vector2i, new_state: int, old_state: int, schema: ChunkSchema)


# ─────────────────────────────────────
# 生命周期
# ─────────────────────────────────────

## 注入依赖（必须在使用前调用）
func setup(config: VisionConfig, vision: VisionSystem, world_seed: int) -> void:
	_config = config
	_vision = vision
	_world_seed = world_seed
	# 监听格子状态变化
	if not _vision.tile_state_changed.is_connected(_on_tile_state_changed):
		_vision.tile_state_changed.connect(_on_tile_state_changed)


# ─────────────────────────────────────
# 工具
# ─────────────────────────────────────

## 世界格坐标 → chunk 坐标
## 注意：负坐标用 floori 而非 int()，避免 int(-0.5)=0 的截断错误
static func tile_to_chunk(tile: Vector2i) -> Vector2i:
	return Vector2i(floori(float(tile.x) / CHUNK_SIZE), floori(float(tile.y) / CHUNK_SIZE))


# ─────────────────────────────────────
# 状态查询
# ─────────────────────────────────────

func get_chunk_state(coord: Vector2i) -> int:
	var rec: ChunkRecord = _chunks.get(coord, null)
	if rec == null:
		return ChunkRecord.State.UNLOADED
	return rec.state


func get_chunk_schema(coord: Vector2i) -> ChunkSchema:
	var rec: ChunkRecord = _chunks.get(coord, null)
	if rec == null:
		return null
	return rec.schema


## 取所有 ACTIVE chunk 坐标（供渲染层迭代）
func get_active_chunks() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for coord in _chunks.keys():
		var rec: ChunkRecord = _chunks[coord]
		if rec.state == ChunkRecord.State.ACTIVE:
			result.append(coord)
	return result


## 取所有保留 schema 的 chunk 坐标（ACTIVE + DORMANT）
func get_loaded_chunks() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for coord in _chunks.keys():
		var rec: ChunkRecord = _chunks[coord]
		if rec.state != ChunkRecord.State.UNLOADED:
			result.append(coord)
	return result


# ─────────────────────────────────────
# 聚合主入口
# ─────────────────────────────────────

## 重算给定 chunk 的状态（基于 VisionSystem 当前格子状态聚合）
func aggregate_chunk(coord: Vector2i) -> void:
	if _config == null or _vision == null:
		return

	# 收集 chunk 内所有格子（256 格）
	var tiles: Array[Vector2i] = []
	for local_y in range(CHUNK_SIZE):
		for local_x in range(CHUNK_SIZE):
			tiles.append(Vector2i(coord.x * CHUNK_SIZE + local_x, coord.y * CHUNK_SIZE + local_y))

	var agg: int = _vision.aggregate_tiles(tiles)
	var target_state: int = _state_from_aggregate(agg)
	_transition_to(coord, target_state)


## 聚合结果 → 目标 chunk 状态
static func _state_from_aggregate(agg: int) -> int:
	match agg:
		VisionSystem.TileState.NORMAL:
			return ChunkRecord.State.ACTIVE
		VisionSystem.TileState.FOG:
			return ChunkRecord.State.DORMANT
		_:
			return ChunkRecord.State.UNLOADED


# ─────────────────────────────────────
# 状态机
# ─────────────────────────────────────

## 把 chunk 转到目标状态
func _transition_to(coord: Vector2i, target: int) -> void:
	var rec: ChunkRecord = _chunks.get(coord, null)
	var current: int = rec.state if rec != null else ChunkRecord.State.UNLOADED

	if current == target:
		return

	# 首次访问 → 创建 record
	if rec == null:
		rec = ChunkRecord.new(coord)
		_chunks[coord] = rec

	# 按 target 状态处理 schema
	match target:
		ChunkRecord.State.ACTIVE:
			# UNLOADED → ACTIVE / DORMANT → ACTIVE：保证 schema 存在
			if rec.schema == null:
				rec.schema = ChunkPCG.generate(_world_seed, coord, _config.poi_spawn_rate_per_chunk)
			rec.state = ChunkRecord.State.ACTIVE
			rec.last_active_turn = _vision.get_current_turn()
		ChunkRecord.State.DORMANT:
			# ACTIVE → DORMANT：保留 schema，仅状态变化
			# UNLOADED → DORMANT（极少见：初始覆盖恰好到 FOG 而无 NORMAL）：也要生成 schema
			if rec.schema == null:
				rec.schema = ChunkPCG.generate(_world_seed, coord, _config.poi_spawn_rate_per_chunk)
			rec.state = ChunkRecord.State.DORMANT
		ChunkRecord.State.UNLOADED:
			# DORMANT → UNLOADED：丢弃 schema
			rec.schema = null
			rec.state = ChunkRecord.State.UNLOADED

	chunk_state_changed.emit(coord, target, current, rec.schema)


# ─────────────────────────────────────
# 信号 handler
# ─────────────────────────────────────

## tile 状态变化 → 仅聚合该格所在 chunk（增量更新）
func _on_tile_state_changed(tile: Vector2i, _new_state: int, _old_state: int) -> void:
	var coord: Vector2i = tile_to_chunk(tile)
	aggregate_chunk(coord)
