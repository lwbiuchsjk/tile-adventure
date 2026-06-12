class_name PersistentSlotGenerator
extends RefCounted
## 持久 slot 生成器（L1.3c 阶段 A 重写：网格抖动确定性撒点）
##
## 设计原文：tile-advanture-design/无限地图实装/L1.3c_世界内容地基_MVP.md
##   §三「跨 chunk 间距的确定性方案（网格抖动撒点）」
##   §五 阶段 A「生成器重写（世界形状）」
##
## 与旧版（八阶段流水线，城建锚 M2）的差异：
##   - 对角区落点 / 全图扫描采样 / 染色 / 涌现 / 四分区校验 全部退役
##     （对角对抗布局是有限地图遗产；L1.3c 拍板出生居中 + 四方等价 + 敌方无老家）
##   - 敌方 CORE_TOWN 不再 PCG 预置（类型与视觉资产保留给玩家据点身份）
##   - 开局除玩家锚点 TOWN 外全部中立——敌方存在改为运行期动态（阶段 C / ③ 暗影压力系统）
##
## 网格抖动（jittered grid）核心性质：
##   - 世界按 cell_size 切分为撒点单元（世界坐标 floor 除法，与 chunk_size 解耦）
##   - 每个 cell 由 (world_seed, cell_coord) 子 seed 独立决定「是否出点 + cell 内位置 + 类型」
##     → 任意 cell 的结果只依赖 seed 与 cell 坐标，与生成顺序 / 生成范围无关
##     → 阶段 B chunk 流式生成直接复用 generate_cell_slot，新旧区域天然一致
##   - cell 内抖动留 1 格 padding → 相邻 cell 两点的曼哈顿间距下界 = 3，无需查询邻 cell
##
## Seed 贯穿：所有随机调用走 per-cell 子 seed RNG，不碰全局 RNG

# ─────────────────────────────────────────
# 生成参数
# ─────────────────────────────────────────

## 持久 slot 生成所需的全部参数
## 由 MapGenerator.GenerateConfig 透传；可独立构造便于测试
class GenConfig:
	## 随机种子（与地形 world_seed 同源，保证同 seed 同世界）
	var seed: int = 0

	## 内容生成区域：以 region_center 为中心的 region_width × region_height 矩形（世界坐标，可含负数）
	## 阶段 A：region_center = 出生点，范围 = 出生区首批 chunk（规则已统一、范围未扩——阶段 B 接 chunk 钩子铺满世界）
	var region_center: Vector2i = Vector2i.ZERO
	var region_width: int = 32
	var region_height: int = 32

	## 撒点 cell 边长（≈ 持久 slot 期望间距；结构性参数：改它 = 换一局内容分布）
	var cell_size: int = 5

	## 每 cell 出点概率（[0,1]；结构性参数）
	var slot_spawn_rate: float = 0.85

	## 出点时为 TOWN 的概率（其余为 VILLAGE；结构性参数）
	var town_ratio: float = 0.27

	## 玩家锚点 TOWN 的环搜半径（从 region_center 向外找可走格）
	var anchor_search_radius: int = 8


## cell 内抖动 padding：local ∈ [PAD, cell_size-1-PAD]
## 相邻 cell 两点最小轴向距离 = 2*PAD+1 = 3（曼哈顿间距下界，与设计 §三一致）
const CELL_JITTER_PAD: int = 1

## cell 内不可走时的重抽次数（同一 cell 内换位置重试，仍不可走则该 cell 放弃）
const CELL_RETRY_COUNT: int = 3

## 玩家锚点与撒点 slot 的最小曼哈顿间距（与 cell 间距下界一致）
const ANCHOR_MIN_DIST: int = 3


# ─────────────────────────────────────────
# 公共入口
# ─────────────────────────────────────────

## 网格抖动撒点主入口
## schema —— 无限模式 MapSchema（地形经 ChunkPCG 全局 noise 场路由，is_passable 任意坐标可查）
## config —— 撒点参数
## 返回持久 slot 数组（玩家锚点 TOWN + 中立 TOWN/VILLAGE）；配置非法或锚点放置失败返回空数组
static func generate(schema: MapSchema, config: GenConfig) -> Array[PersistentSlot]:
	var empty: Array[PersistentSlot] = []
	if schema == null:
		push_error("PersistentSlotGenerator: schema 为 null")
		return empty

	# 入口配置自检：提早暴露非法参数
	var config_error: String = _validate_config(config)
	if not config_error.is_empty():
		push_error("PersistentSlotGenerator: 配置非法 → " + config_error)
		return empty

	var slots: Array[PersistentSlot] = []

	# 1. 玩家锚点 TOWN：出生点附近确定性环搜首个可走格
	#    （锚点是玩家初始产权 / 据点升级候选；功能层等同普通 TOWN，owner=PLAYER level=0）
	var anchor_pos: Vector2i = _find_anchor_pos(schema, config)
	if anchor_pos.x == NO_POS.x and anchor_pos.y == NO_POS.y:
		push_error("PersistentSlotGenerator: 出生点 %s 半径 %d 内无可走格，锚点放置失败" % [
			str(config.region_center), config.anchor_search_radius
		])
		return empty
	var anchor: PersistentSlot = _build_slot(anchor_pos, PersistentSlot.Type.TOWN, 0, Faction.PLAYER)
	slots.append(anchor)

	# 2. 网格抖动撒点：遍历与区域相交的全部 cell，逐 cell 确定性出点
	var region_min: Vector2i = config.region_center - Vector2i(config.region_width / 2, config.region_height / 2)
	var region_max: Vector2i = region_min + Vector2i(config.region_width - 1, config.region_height - 1)
	var cell_min: Vector2i = _cell_of(region_min, config.cell_size)
	var cell_max: Vector2i = _cell_of(region_max, config.cell_size)
	for cy in range(cell_min.y, cell_max.y + 1):
		for cx in range(cell_min.x, cell_max.x + 1):
			var candidate: PersistentSlot = generate_cell_slot(
				config.seed, Vector2i(cx, cy), config, schema
			)
			if candidate == null:
				continue
			# 区域过滤：cell 输出与区域无关（确定性），区域只是筛子——阶段 B 换成 chunk 边界筛
			if candidate.position.x < region_min.x or candidate.position.x > region_max.x \
				or candidate.position.y < region_min.y or candidate.position.y > region_max.y:
				continue
			# 锚点间距守卫：撒点不挤占玩家锚点周边
			var dist_to_anchor: int = absi(candidate.position.x - anchor_pos.x) \
				+ absi(candidate.position.y - anchor_pos.y)
			if dist_to_anchor < ANCHOR_MIN_DIST:
				continue
			slots.append(candidate)

	# 3. display_id 分配（沿用全局唯一规则；本批一次性分配，阶段 B 增量分配另行处理）
	_assign_display_ids(slots)

	return slots


## 单 cell 确定性出点（阶段 B chunk 流式生成的复用基石）
## 性质：输出只依赖 (world_seed, cell_coord, config 撒点参数, 地形)，与调用时机 / 范围无关
## 返回该 cell 的 slot（中立 TOWN/VILLAGE）；不出点 / cell 内无可走格返回 null
static func generate_cell_slot(
	world_seed: int,
	cell_coord: Vector2i,
	config: GenConfig,
	schema: MapSchema
) -> PersistentSlot:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = _cell_seed(world_seed, cell_coord)

	# 出点判定
	if rng.randf() >= config.slot_spawn_rate:
		return null
	# 类型先定后采位置：保证 RNG 消费序列固定，位置重抽不影响类型确定性
	var slot_type: PersistentSlot.Type = PersistentSlot.Type.TOWN \
		if rng.randf() < config.town_ratio else PersistentSlot.Type.VILLAGE

	# cell 内抖动采位置：留 PAD 保证跨 cell 间距下界；不可走则重抽，耗尽放弃
	var cs: int = config.cell_size
	for attempt in range(CELL_RETRY_COUNT):
		var local_x: int = rng.randi_range(CELL_JITTER_PAD, cs - 1 - CELL_JITTER_PAD)
		var local_y: int = rng.randi_range(CELL_JITTER_PAD, cs - 1 - CELL_JITTER_PAD)
		var pos: Vector2i = Vector2i(cell_coord.x * cs + local_x, cell_coord.y * cs + local_y)
		if schema.is_passable(pos.x, pos.y):
			return _build_slot(pos, slot_type, 0, Faction.NONE)
	return null


# ─────────────────────────────────────────
# 据点升级（L1.2 Phase 1，保留不动）
# ─────────────────────────────────────────

## 将指定格上的玩家方持久 slot 升级为玩家方 CORE_TOWN（据点）
##
## 前置：pos 上必须存在 owner == PLAYER 的持久 slot（调用方 EC._resolve_stronghold_prompt
## 已用扎营覆盖判定保证）；找不到返回 false（调用方据此决定是否标记 has_stronghold）
##
## 升级效果：type → CORE_TOWN、level → 3（WorldMapRenderer 视觉取最高级金边 + 徽记）。
## display_id 保留原值（村庄/城镇编号）——玩家据点视觉靠金边 + 徽记区分。
## 注：L1.3c 阶段 A 后 CORE_TOWN 类型仅服务玩家据点身份（PCG 不再预置敌方核心）
static func upgrade_slot_to_stronghold(slots: Array[PersistentSlot], pos: Vector2i) -> bool:
	for s in slots:
		if s.position == pos and s.owner_faction == Faction.PLAYER:
			s.type = PersistentSlot.Type.CORE_TOWN
			s.level = 3
			return true
	return false


# ─────────────────────────────────────────
# 玩家锚点放置
# ─────────────────────────────────────────

## 无效位置哨兵（无限世界负坐标合法，不能用 (-1,-1) 表示无效）
const NO_POS: Vector2i = Vector2i(-2147483648, -2147483648)

## 从出生点向外按曼哈顿环确定性搜索玩家锚点落位
## 规则：r 从 2 起（不与出生格重叠，留 1 格缓冲），固定扫描顺序保证同 seed 同结果；
##       首个可走格即锚点。半径耗尽返回 NO_POS。
static func _find_anchor_pos(schema: MapSchema, config: GenConfig) -> Vector2i:
	var center: Vector2i = config.region_center
	for r in range(2, config.anchor_search_radius + 1):
		for dy in range(-r, r + 1):
			var dx_abs: int = r - absi(dy)
			# 曼哈顿环：|dx| + |dy| == r，固定先负后正的扫描顺序（确定性）
			for dx in ([-dx_abs, dx_abs] if dx_abs > 0 else [0]):
				var pos: Vector2i = center + Vector2i(dx, dy)
				if schema.is_passable(pos.x, pos.y):
					return pos
	return NO_POS


# ─────────────────────────────────────────
# cell 坐标与子 seed
# ─────────────────────────────────────────

## 世界坐标 → cell 坐标（floor 除法，负坐标安全——不能用整型除法的截断行为）
static func _cell_of(world_pos: Vector2i, cell_size: int) -> Vector2i:
	return Vector2i(
		floori(float(world_pos.x) / float(cell_size)),
		floori(float(world_pos.y) / float(cell_size))
	)


## per-cell 子 seed：(world_seed, cell_coord, "slot") 哈希
## 与 ChunkPCG._hash_subseed 同构（独立副本避免跨模块依赖）；确定性 + 抗碰撞
static func _cell_seed(world_seed: int, cell_coord: Vector2i) -> int:
	var key: String = "%d_%d_%d_slot" % [world_seed, cell_coord.x, cell_coord.y]
	return key.hash()


# ─────────────────────────────────────────
# display_id 分配
# ─────────────────────────────────────────

## 按 (类型, 位置) 确定性排序，全局唯一分配人类可读 ID
## 规则（M8 v2：全局唯一）：
##   CORE_TOWN：恒为"核心"（阶段 A 后初始生成不再出现，仅运行时据点升级保留语义）
##   VILLAGE / TOWN：按 position (y→x) 排序后从 1 递增；ID 一次定死、不随归属翻转变化
## 稳定性依赖 position 排序 —— position 由 seed 唯一决定，故同 seed 两次生成 ID 一致
static func _assign_display_ids(slots: Array[PersistentSlot]) -> void:
	var sorted: Array[PersistentSlot] = slots.duplicate()
	sorted.sort_custom(func(a: PersistentSlot, b: PersistentSlot) -> bool:
		if a.type != b.type:
			return int(a.type) < int(b.type)
		if a.position.y != b.position.y:
			return a.position.y < b.position.y
		return a.position.x < b.position.x
	)

	# 按类型全局计数（不分势力）
	var counters: Dictionary = {}   # { int type: int next_idx }
	for slot in sorted:
		if slot.type == PersistentSlot.Type.CORE_TOWN:
			slot.display_id = "核心"
			continue
		var key: int = int(slot.type)
		var next_idx: int = int(counters.get(key, 1))
		slot.display_id = "%s%d" % [slot.get_type_name(), next_idx]
		counters[key] = next_idx + 1


# ─────────────────────────────────────────
# 配置自检
# ─────────────────────────────────────────

## 入口配置自检：返回空字符串表示通过；非空字符串为人类可读错误描述
static func _validate_config(config: GenConfig) -> String:
	if config.region_width <= 0 or config.region_height <= 0:
		return "内容区域尺寸非法 region_width=%d / region_height=%d；期望 > 0" % [
			config.region_width, config.region_height
		]
	# cell_size ≥ 3：PAD=1 时抖动区间 [1, cell_size-2] 至少要有 1 个合法值
	if config.cell_size < 3:
		return "撒点 cell 边长 cell_size=%d 非法；期望 ≥ 3（content_config: cell_size）" % config.cell_size
	if config.slot_spawn_rate < 0.0 or config.slot_spawn_rate > 1.0:
		return "出点概率 slot_spawn_rate=%.3f 非法；期望 [0,1]（content_config: slot_spawn_rate）" % config.slot_spawn_rate
	if config.town_ratio < 0.0 or config.town_ratio > 1.0:
		return "城镇占比 town_ratio=%.3f 非法；期望 [0,1]（content_config: town_ratio）" % config.town_ratio
	if config.anchor_search_radius < 2:
		return "锚点环搜半径 anchor_search_radius=%d 非法；期望 ≥ 2" % config.anchor_search_radius
	return ""


# ─────────────────────────────────────────
# slot 构造辅助
# ─────────────────────────────────────────

## 构造一个 PersistentSlot 实例并填基础字段
## 影响范围 / 升级耗时等扩展字段由 MapBootstrap.init_world_subsystems 经 BuildSystem 注入
static func _build_slot(
	pos: Vector2i,
	type: PersistentSlot.Type,
	level: int,
	faction: int
) -> PersistentSlot:
	var s: PersistentSlot = PersistentSlot.new()
	s.position = pos
	s.type = type
	s.level = level
	s.owner_faction = faction
	return s
