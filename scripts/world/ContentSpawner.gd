class_name ContentSpawner
extends RefCounted
## chunk 流式内容撒点（L1.3c 阶段 B）
##
## 设计原文：tile-advanture-design/无限地图实装/L1.3c_世界内容地基_MVP.md §三图2 / §五阶段 B
##
## 职责：订阅 ChunkManager.chunk_first_generated，在 chunk【首次】生成时：
##   1. 持久 slot：对 chunk 覆盖的撒点 cell 逐个调 PersistentSlotGenerator.generate_cell_slot
##      ——与开局初始区域同一套纯函数规则，新区内容与"假如开局范围更大"完全一致（区域单调性）
##   2. 资源 slot：按 per-chunk 配额确定性落位（类型按配置行 count_per_round 加权抽取）
##
## 静态/动态层分界（设计 §三）：本模块只管静态层（持久/资源 slot，首次一次性撒点，
## 重建不重撒）；敌方 pack 是动态层，不在此撒（阶段 C 暗影环带刷新）。
##
## 去重三道防线：
##   - chunk 级：ChunkRecord.was_ever_generated（ChunkManager 守卫，重建不发信号）
##   - 本模块 _processed_chunks（防御性幂等：信号重复/测试直调均安全；资源 slot 是
##     消耗品，被采集后位置空出，不能靠位置查重）
##   - 持久 slot 位置查重：cell 跨 chunk 边界时同一 cell 会被相邻两 chunk 各处理一次，
##     确定性保证产物相同，按现存位置去重（开局初始区域已生成的 slot 同样由此跳过）
##
## 可序列化红线（议题 13）：_processed_chunks / _display_counters 均为纯数据 dict，
## 不攥任何运行时句柄；依赖以引用注入（setup），不持有 WorldMap/Node。

## 资源 slot 单个落位的 chunk 内重抽次数（不可走/被占则重抽，耗尽放弃该个）
const RESOURCE_RETRY_PER_SLOT: int = 8

# ─────────────────────────────────────────
# 注入依赖（setup 一次性注入；不持有 WorldMap/Node，便于 headless 单测）
# ─────────────────────────────────────────

var _schema: MapSchema = null
## 撒点参数（seed / cell_size / slot_spawn_rate / town_ratio；region 字段不参与 cell 调用）
var _gen_config: PersistentSlotGenerator.GenConfig = null
## 玩家锚点位置（撒点保持 ANCHOR_MIN_DIST 间距，与开局规则一致）
var _anchor_pos: Vector2i = PersistentSlotGenerator.NO_POS
var _chunk_size: int = 16
## WorldMap._resource_slots / _level_slots 的字典引用（直接写入）
var _resource_slots: Dictionary = {}
var _level_slots: Dictionary = {}
## 资源类型配置行（resource_slot_config.csv；count_per_round 作类型权重）
var _resource_rows: Array = []
## 每 chunk 资源 slot 配额（content_config.resource_quota_per_chunk）
var _resource_quota: int = 1
## 新增持久 slot 的援军储备表 + 城镇兵池（新 slot 全中立，恒用非敌方表）
var _garrison_cfg: Dictionary = {}
var _town_pool_rows: Array = []

## L1.3d-1 阶段 B：当前暗影压力 P 的取值器（注入 Callable，懒求值）。
## 运行期撒持久 slot 时按当前 P 抽 garrison 强度——新区 slot 防御随压力上档。
## 未注入（测试 / 早期）时回退 P=0（基线强度）。
var _pressure_provider: Callable = Callable()
## 撒点后请求重绘（通常绑 WorldMapRenderer.queue_redraw；无效 Callable 则跳过）
var _redraw: Callable = Callable()

# ─────────────────────────────────────────
# 运行期状态（纯数据，可序列化）
# ─────────────────────────────────────────

## 已处理过的 chunk 集合 { Vector2i: true }
var _processed_chunks: Dictionary = {}

## display_id 增量计数 { type int: 下一个编号 }——不能重跑全局排序分配（会洗牌已有编号）
var _display_counters: Dictionary = {}


# ─────────────────────────────────────────
# 装配
# ─────────────────────────────────────────

## 注入全部依赖；display_id 计数器从现存 slot 接续（开局批已按 1..N 密集分配）
func setup(
	schema: MapSchema,
	gen_config: PersistentSlotGenerator.GenConfig,
	anchor_pos: Vector2i,
	chunk_size: int,
	resource_slots: Dictionary,
	level_slots: Dictionary,
	resource_rows: Array,
	resource_quota: int,
	garrison_cfg: Dictionary,
	town_pool_rows: Array,
	redraw: Callable,
	pressure_provider: Callable = Callable()
) -> void:
	_schema = schema
	_gen_config = gen_config
	_anchor_pos = anchor_pos
	_chunk_size = maxi(1, chunk_size)
	_resource_slots = resource_slots
	_level_slots = level_slots
	_resource_rows = resource_rows
	_resource_quota = maxi(0, resource_quota)
	_garrison_cfg = garrison_cfg
	_town_pool_rows = town_pool_rows
	_redraw = redraw
	_pressure_provider = pressure_provider
	_init_display_counters()


## 订阅 chunk 首次生成信号（幂等）
func attach(chunk_manager: ChunkManager) -> void:
	if chunk_manager == null:
		push_warning("ContentSpawner.attach: chunk_manager 为 null，跳过订阅")
		return
	if not chunk_manager.chunk_first_generated.is_connected(on_chunk_first_generated):
		chunk_manager.chunk_first_generated.connect(on_chunk_first_generated)


# ─────────────────────────────────────────
# 钩子入口
# ─────────────────────────────────────────

## chunk 首次生成 → 撒静态内容（持久 slot + 资源 slot）
## 信号 handler；测试可直调。幂等：同 chunk 二次调用 no-op
func on_chunk_first_generated(coord: Vector2i, _chunk_schema: ChunkSchema) -> void:
	if _schema == null or _gen_config == null:
		return
	if _processed_chunks.has(coord):
		return
	_processed_chunks[coord] = true

	var added_persistent: bool = _spawn_persistent_for_chunk(coord)
	var added_resource: bool = _spawn_resources_for_chunk(coord)

	# 撒点产生可见变化时请求重绘（非战斗态不每帧重绘，需显式 queue_redraw）
	if (added_persistent or added_resource) and _redraw.is_valid():
		_redraw.call()


# ─────────────────────────────────────────
# 持久 slot：cell 规则流式兑现
# ─────────────────────────────────────────

## 对 chunk 覆盖的全部撒点 cell 跑 generate_cell_slot，新产物入 schema.persistent_slots
## 返回是否有新增
func _spawn_persistent_for_chunk(coord: Vector2i) -> bool:
	var chunk_min: Vector2i = coord * _chunk_size
	var chunk_max: Vector2i = chunk_min + Vector2i(_chunk_size - 1, _chunk_size - 1)
	var cs: int = _gen_config.cell_size
	# cell 网格与 chunk 网格不对齐：取覆盖 chunk 矩形的 cell 范围（floor 除法，负坐标安全）
	var cell_min: Vector2i = Vector2i(floori(float(chunk_min.x) / cs), floori(float(chunk_min.y) / cs))
	var cell_max: Vector2i = Vector2i(floori(float(chunk_max.x) / cs), floori(float(chunk_max.y) / cs))

	var occupied: Dictionary = _persistent_occupied()
	# 援军储备抽样 rng：per-chunk 子 seed → 同 seed 同 chunk 的新 slot 储备也确定性复现
	var roster_rng: RandomNumberGenerator = _chunk_rng(coord, "roster")

	var added: bool = false
	for cy in range(cell_min.y, cell_max.y + 1):
		for cx in range(cell_min.x, cell_max.x + 1):
			var cand: PersistentSlot = PersistentSlotGenerator.generate_cell_slot(
				_gen_config.seed, Vector2i(cx, cy), _gen_config, _schema
			)
			if cand == null:
				continue
			# 位置查重：开局批已生成 / 跨界 cell 已由邻 chunk 处理 → 跳过（确定性保证产物相同）
			if occupied.has(cand.position):
				continue
			# 锚点间距守卫（与开局 generate() 同规则）
			var dist_to_anchor: int = absi(cand.position.x - _anchor_pos.x) \
				+ absi(cand.position.y - _anchor_pos.y)
			if dist_to_anchor < PersistentSlotGenerator.ANCHOR_MIN_DIST:
				continue
			# 增量接线：display_id 增量分配 + 字段注入 + 援军储备（开局批在
			# init_world_subsystems 一次性做，运行期新增 slot 在此对齐同一套）
			cand.display_id = _next_display_id(cand.type)
			BuildSystem.apply_level_fields(cand, cand.level)
			# L1.3d-1 阶段 B：garrison 强度按当前暗影压力 P 抽（取代冻结 cycle_index）；
			# 未注入 provider（测试 / 早期）回退 P=0 基线
			var pressure: int = int(_pressure_provider.call()) if _pressure_provider.is_valid() else 0
			cand.reinforcement_roster = ReinforcementRoster.sample(
				cand.type as int, pressure,
				_garrison_cfg, _town_pool_rows, roster_rng
			)
			_schema.persistent_slots.append(cand)
			occupied[cand.position] = true
			added = true
	return added


## 现存持久 slot 位置集合（位置查重用）
func _persistent_occupied() -> Dictionary:
	var occupied: Dictionary = {}
	for entry in _schema.persistent_slots:
		var slot: PersistentSlot = entry as PersistentSlot
		if slot != null:
			occupied[slot.position] = true
	return occupied


## display_id 增量分配：接续现存编号继续递增（同类型全局唯一）
func _next_display_id(type: int) -> String:
	var next_idx: int = int(_display_counters.get(type, 1))
	_display_counters[type] = next_idx + 1
	# 借 PersistentSlot 实例取类型名（与 _assign_display_ids 的命名规则一致）
	var probe: PersistentSlot = PersistentSlot.new()
	probe.type = type as PersistentSlot.Type
	return "%s%d" % [probe.get_type_name(), next_idx]


## 计数器初始化：解析现存 display_id 尾号，按每类型最大尾号 +1 接续
## codex P1 修复：不能按数量清点——据点升级会把 VILLAGE/TOWN 变为 CORE_TOWN 但保留
## 原 display_id（如"村庄2"），数量清点会少计一个、重新发出已占用编号；
## 按尾号最大值接续对编号空洞 / 类型已变的 slot 都稳健
func _init_display_counters() -> void:
	_display_counters = {}
	if _schema == null:
		return
	# 类型名前缀 → 类型 key（"村庄"/"城镇" 互不为前缀，begins_with 判定安全）
	var prefix_to_type: Dictionary = {}
	for t in [PersistentSlot.Type.TOWN, PersistentSlot.Type.VILLAGE]:
		var probe: PersistentSlot = PersistentSlot.new()
		probe.type = t as PersistentSlot.Type
		prefix_to_type[probe.get_type_name()] = int(t)
	for entry in _schema.persistent_slots:
		var slot: PersistentSlot = entry as PersistentSlot
		if slot == null or slot.display_id.is_empty():
			continue
		# 不按 slot.type 分桶而按 display_id 前缀分桶：升级后的 CORE_TOWN 仍占用原类型编号
		for prefix in prefix_to_type:
			var p: String = prefix as String
			if not slot.display_id.begins_with(p):
				continue
			var suffix: String = slot.display_id.substr(p.length())
			if suffix.is_valid_int():
				var key: int = int(prefix_to_type[p])
				var next_candidate: int = int(suffix) + 1
				if next_candidate > int(_display_counters.get(key, 1)):
					_display_counters[key] = next_candidate
			break


# ─────────────────────────────────────────
# 资源 slot：per-chunk 配额落位
# ─────────────────────────────────────────

## 按配额在 chunk 内确定性落资源 slot；返回是否有新增
## 占位避让：地形可走 + 无持久 slot / 敌方 pack / 既有资源 / FUNCTION 标记
## 注：不避让玩家当前格（开局首批 chunk 可能含玩家位置；落在脚下仅延后到再次踏入采集，无害）
func _spawn_resources_for_chunk(coord: Vector2i) -> bool:
	if _resource_rows.is_empty() or _resource_quota <= 0:
		return false
	var rng: RandomNumberGenerator = _chunk_rng(coord, "res")
	var chunk_min: Vector2i = coord * _chunk_size
	var occupied: Dictionary = _persistent_occupied()

	# 类型权重 = count_per_round（沿用 resource_slot_config.csv 行语义）
	var total_weight: int = 0
	for entry in _resource_rows:
		var row: Dictionary = entry as Dictionary
		if row != null:
			total_weight += maxi(0, int(row.get("count_per_round", "1")))
	if total_weight <= 0:
		return false

	var added: bool = false
	for i in range(_resource_quota):
		# 1) 类型加权抽取（先抽类型再采位置，RNG 消费序列固定）
		var roll: int = rng.randi_range(1, total_weight)
		var picked_row: Dictionary = {}
		var acc: int = 0
		for entry in _resource_rows:
			var row: Dictionary = entry as Dictionary
			if row == null:
				continue
			acc += maxi(0, int(row.get("count_per_round", "1")))
			if roll <= acc:
				picked_row = row
				break
		if picked_row.is_empty():
			continue
		# 2) chunk 内随机落位，重抽至可用
		for attempt in range(RESOURCE_RETRY_PER_SLOT):
			var pos: Vector2i = chunk_min + Vector2i(
				rng.randi_range(0, _chunk_size - 1), rng.randi_range(0, _chunk_size - 1)
			)
			if not _schema.is_passable(pos.x, pos.y):
				continue
			# L1.3c 阶段 D：占用判定直查实体 dict 单一权威源（_resource_slots/_level_slots/持久 slot）；
			# 原 schema get_slot != NONE 守卫是被上一行完全覆盖的死代码，随 FUNCTION 双写退役一并删
			if occupied.has(pos) or _resource_slots.has(pos) or _level_slots.has(pos):
				continue
			var rs: ResourceSlot = ResourceSlot.new()
			rs.position = pos
			rs.resource_type = int(picked_row.get("resource_type", "0")) as ResourceSlot.ResourceType
			rs.output_amount = int(picked_row.get("output_amount", "1"))
			# _resource_slots 为资源点唯一权威源（schema RESOURCE/FUNCTION 双写已退役）
			_resource_slots[pos] = rs
			added = true
			break
	return added


# ─────────────────────────────────────────
# per-chunk 子 seed
# ─────────────────────────────────────────

## (world_seed, chunk_coord, tag) → 确定性 RNG（与 ChunkPCG._hash_subseed 同构）
func _chunk_rng(coord: Vector2i, tag: String) -> RandomNumberGenerator:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	var key: String = "%d_%d_%d_%s" % [_gen_config.seed, coord.x, coord.y, tag]
	rng.seed = key.hash()
	return rng
