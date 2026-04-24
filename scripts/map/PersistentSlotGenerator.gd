class_name PersistentSlotGenerator
extends RefCounted
## 持久 slot 生成器（M2）
##
## 设计原文：tile-advanture-design/持久slot地图生成设计.md 全文
##   §四 三阶段 + 涌现策略
##   §五 关键参数与函数
##   §六 八阶段时序流水线
##
## 八阶段流水线：
##   1. 参数解析（GenConfig）
##   2. 核心城镇对角落点（1/8 ~ 1/4 区域）
##   3. 其余持久 slot 位置采样（泊松盘风格 + 最小间距）
##   4. 类型分配（6 镇 + 18 村 比例分配）
##   5. 下限染色（每势力 2 镇 + 6 村）
##   6. 涌现延伸（m=3 步邻域势力场染色）
##   7. 校验（数量 / 间距 / 三桶）
##   8. 回退策略（首次失败重试，连续失败放宽参数）
##
## Seed 贯穿：所有随机调用走注入的 RandomNumberGenerator 实例
##
## MVP 限制：
##   - 两方对峙（PLAYER vs ENEMY_1）；扩展到 N 方时改 §核心落点 + §轮询顺序
##   - 势力场半径全势力同 R；扩展时改为 per-faction R 表

# ─────────────────────────────────────────
# 生成参数
# ─────────────────────────────────────────

## 持久 slot 生成所需的全部参数
## 由 MapGenerator.GenerateConfig 透传过来；可独立构造便于测试
class GenConfig:
	## 地图尺寸（与 schema 一致）
	var width: int = 32
	var height: int = 32

	## 随机种子（与地形 seed 同源，保证同 seed 同地图）
	var seed: int = 0

	## 数量配比（§3.1）
	var total_count: int = 26
	var core_count: int = 2
	var town_count: int = 6
	var village_count: int = 18

	## 最小间距（§5.4，曼哈顿距离）
	var min_dist_normal: int = 3
	var min_dist_core: int = 5

	## 涌现步数（§4.4，全局配置）
	var emerge_steps: int = 3

	## 势力场半径 R（§5.1，MVP 全势力同 R）
	var field_radius: int = 20

	## 核心区域参数（§2.2，对角 1/8 ~ 1/4 区域）
	## 0.125 = 距对角顶点 1/8 边长以内；0.25 = 1/4 边长以内
	## 采样区域 = max 与 min 围出的环带（顶点处保留 min 的安全距）
	var core_zone_min: float = 0.125
	var core_zone_max: float = 0.25

	## 八阶段流水线最大重试次数（连续失败时放宽参数）
	var max_retries: int = 5

	## 每方开局归属下限（设计 §3.2 三桶下限；双方共享同一套配置）
	## 修改时注意保持总量平衡：双方 town_quota * 2 ≤ town_count，village 同理
	var faction_town_quota: int = 2
	var faction_village_quota: int = 6


# ─────────────────────────────────────────
# 公共入口
# ─────────────────────────────────────────

## 八阶段流水线主入口
## schema —— 已生成地形 + 已通过通达性校验的 MapSchema
## config —— 八阶段参数
## 返回 26 个 PersistentSlot 实例数组；极端失败返回空数组并 push_error
static func generate(schema: MapSchema, config: GenConfig) -> Array[PersistentSlot]:
	if schema == null:
		push_error("PersistentSlotGenerator: schema 为 null")
		var empty_null: Array[PersistentSlot] = []
		return empty_null

	# 入口配置自检：在跑流水线之前提早暴露非法参数，避免静默重试至 max_retries 才报错
	# 失败时返回空数组，调用方按"生成失败"处理（MapGenerator 会换 seed 重试整图，但
	# 配置错误重试无意义；本函数只一次 push_error，重试日志由 MapGenerator 自身打印）
	var config_error: String = _validate_config(config)
	if not config_error.is_empty():
		push_error("PersistentSlotGenerator: 配置非法 → " + config_error)
		var empty_cfg: Array[PersistentSlot] = []
		return empty_cfg

	# 创建独立 RNG，注入 seed，保证同 seed 同地图
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = config.seed

	# 阶段 8 回退：双阈值机制 —— 搜索阈值可放宽，验收阈值始终用设计硬标准
	# §5.4 硬标准：普通 ≥ 3、核心 ≥ 5；放宽搜索是为了"找到一组解"，但不让步成品质量
	var search_min_dist_normal: int = config.min_dist_normal
	var search_min_dist_core: int = config.min_dist_core

	for retry in range(config.max_retries):
		var slots: Array[PersistentSlot] = _try_generate(
			schema, config, rng, search_min_dist_normal, search_min_dist_core
		)
		if not slots.is_empty():
			# 阶段 7 校验始终用 config 的硬标准（不读 search_*），回退放宽不影响验收
			if _validate(slots, config, config.min_dist_normal, config.min_dist_core):
				return slots
			else:
				push_warning("PersistentSlotGenerator: 第 %d 次硬标准校验未通过，重试" % (retry + 1))
		else:
			push_warning("PersistentSlotGenerator: 第 %d 次生成失败，重试" % (retry + 1))

		# 第 3 次起放宽搜索阈值（§六回退策略）；验收阈值不动
		if retry >= 2:
			search_min_dist_normal = maxi(2, search_min_dist_normal - 1)
			search_min_dist_core = maxi(3, search_min_dist_core - 1)

	push_error("PersistentSlotGenerator: 超出最大重试次数（%d）" % config.max_retries)
	var empty_fail: Array[PersistentSlot] = []
	return empty_fail


# ─────────────────────────────────────────
# 单次尝试（八阶段串联）
# ─────────────────────────────────────────

## 单次完整流水线尝试；失败返回空数组
static func _try_generate(
	schema: MapSchema,
	config: GenConfig,
	rng: RandomNumberGenerator,
	min_dist_normal: int,
	min_dist_core: int
) -> Array[PersistentSlot]:
	# 阶段 2：核心城镇对角落点
	var cores: Dictionary = _place_core_towns(schema, config, rng)
	if cores.is_empty():
		var empty: Array[PersistentSlot] = []
		return empty

	# 阶段 3：其余 24 个持久 slot 位置采样
	var occupied: Array[Vector2i] = []
	for fid in cores:
		occupied.append(cores[fid] as Vector2i)
	var positions: Array[Vector2i] = _sample_positions(
		schema, config, rng,
		occupied, min_dist_normal, min_dist_core
	)
	if positions.size() < config.town_count + config.village_count:
		var empty_short: Array[PersistentSlot] = []
		return empty_short

	# 阶段 4：类型分配（6 城镇 + 18 村庄按比例分配到位置）
	# §4.2 末："位置决定后再分类型，避免类型与位置强耦合"
	# MVP 实现：注入 RNG 洗牌后前 6 当城镇，其余当村庄（不能用 Array.shuffle —— 走全局 RNG 破坏 seed）
	_shuffle_with_rng(positions, rng)
	var slots: Array[PersistentSlot] = []
	# 核心 2 个
	for fid in cores:
		var core_slot: PersistentSlot = _build_slot(
			cores[fid] as Vector2i,
			PersistentSlot.Type.CORE_TOWN,
			3,                   # 核心 MVP 初始 L3（升级建造 §6.3）
			fid as int           # 核心已定归属
		)
		slots.append(core_slot)
	# 城镇 6 个
	for i in range(config.town_count):
		var town_slot: PersistentSlot = _build_slot(
			positions[i],
			PersistentSlot.Type.TOWN,
			0,
			Faction.NONE
		)
		slots.append(town_slot)
	# 村庄 18 个
	for i in range(config.village_count):
		var village_slot: PersistentSlot = _build_slot(
			positions[config.town_count + i],
			PersistentSlot.Type.VILLAGE,
			0,
			Faction.NONE
		)
		slots.append(village_slot)

	# 阶段 5：下限染色（每势力 2 镇 + 6 村）
	_paint_minimum(slots, cores, config, rng)

	# 阶段 6：涌现延伸 m 步
	_emerge(slots, cores, config, rng)

	# 阶段 7（M8 扩展）：分配 display_id
	# 依赖最终归属已定（§5/§6 染色 + 涌现完成），故放在最后
	_assign_display_ids(slots)

	return slots


## 按 (类型, 位置) 确定性排序，全局唯一分配人类可读 ID
## 规则（M8 v2：全局唯一）：
##   CORE_TOWN：恒为"核心"（MVP 只有 2 个，靠势力色区分，核心不翻转无歧义）
##   VILLAGE / TOWN：按 position (y→x) 排序后全地图从 1 递增
##                   示例：18 个村庄全局 "村庄1..村庄18"；玩家 / 敌方 / 中立**共享**这个序列
##
## 决策背景（v2）：
##   v1 按 (势力, 类型) 分桶独立计数。玩家占据中立/敌方 slot 后，该 slot 的 display_id 保留，
##   但可能与玩家已有同 ID slot 重名（例如玩家有"村庄2"，又占了原中立桶里的"村庄2"），反人类
##   v2 改全局唯一：ID 生成时一次定死、永不随归属翻转变化；玩家拥有的 ID 可能不连续
##   （如"村庄2, 村庄5, 村庄8"）但每个 ID 在地图上唯一指向一格，查找方便
##
## 稳定性依赖 position 排序 —— position 由 seed 唯一决定，故同 seed 两次生成 ID 一致
##
## 确定性排序注意：Array.sort_custom 不保证稳定性；此处 (type, y, x) 三键足以唯一决定顺序
## （不同 slot 不会共享 position），结果与稳定排序等价
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
# 阶段 2：核心城镇对角落点
# ─────────────────────────────────────────

## 在地图对角 1/8 ~ 1/4 区域内为双方核心采样落点
## 返回 { Faction.PLAYER: pos, Faction.ENEMY_1: pos }
## 任一方区域全不可通行 → 扩大区域后重试；仍失败返回空字典
static func _place_core_towns(
	schema: MapSchema,
	config: GenConfig,
	rng: RandomNumberGenerator
) -> Dictionary:
	var w: int = config.width
	var h: int = config.height

	# 玩家落在 (0,0) 左上角的角块；敌方落在 (w-1, h-1) 右下角的角块（对角）
	# 角块定义：从顶点向内延伸 zone_max 边长的方形区域，
	# 排除最贴边 zone_min 内的格（避免太边缘）
	var zone_min_x: int = int(float(w) * config.core_zone_min)
	var zone_max_x: int = int(float(w) * config.core_zone_max)
	var zone_min_y: int = int(float(h) * config.core_zone_min)
	var zone_max_y: int = int(float(h) * config.core_zone_max)
	# 至少留 1 格余量
	zone_max_x = maxi(zone_max_x, zone_min_x + 1)
	zone_max_y = maxi(zone_max_y, zone_min_y + 1)

	var player_pos: Vector2i = _sample_in_box(
		schema, rng,
		zone_min_x, zone_min_y,
		zone_max_x, zone_max_y
	)
	var enemy_pos: Vector2i = _sample_in_box(
		schema, rng,
		w - 1 - zone_max_x, h - 1 - zone_max_y,
		w - 1 - zone_min_x, h - 1 - zone_min_y
	)
	# 兜底：若区域内全不可通行，扩大到全图角块
	if player_pos.x < 0:
		player_pos = _sample_in_box(schema, rng, 0, 0, zone_max_x, zone_max_y)
	if enemy_pos.x < 0:
		enemy_pos = _sample_in_box(schema, rng,
			w - 1 - zone_max_x, h - 1 - zone_max_y,
			w - 1, h - 1)

	if player_pos.x < 0 or enemy_pos.x < 0:
		push_error("PersistentSlotGenerator: 核心区域全不可通行")
		return {}

	var result: Dictionary = {}
	result[Faction.PLAYER] = player_pos
	result[Faction.ENEMY_1] = enemy_pos
	return result


## 在矩形区域 [x0, x1] x [y0, y1] 内随机挑选一个可通行格
## 全不可通行返回 Vector2i(-1, -1)
static func _sample_in_box(
	schema: MapSchema,
	rng: RandomNumberGenerator,
	x0: int, y0: int,
	x1: int, y1: int
) -> Vector2i:
	var candidates: Array[Vector2i] = []
	for y in range(maxi(0, y0), mini(schema.height, y1 + 1)):
		for x in range(maxi(0, x0), mini(schema.width, x1 + 1)):
			if schema.is_passable(x, y):
				candidates.append(Vector2i(x, y))
	if candidates.is_empty():
		return Vector2i(-1, -1)
	var idx: int = rng.randi_range(0, candidates.size() - 1)
	return candidates[idx]


# ─────────────────────────────────────────
# 阶段 3：泊松盘风格位置采样
# ─────────────────────────────────────────

## 在地图上采样剩余 (town_count + village_count) 个位置
## 满足：避开核心 / 不可通行 / 与已采样点保持最小间距
## 失败返回小于目标数量的部分结果，由调用方判定是否重试
static func _sample_positions(
	schema: MapSchema,
	config: GenConfig,
	rng: RandomNumberGenerator,
	occupied: Array[Vector2i],
	min_dist_normal: int,
	min_dist_core: int
) -> Array[Vector2i]:
	var target_count: int = config.town_count + config.village_count
	var result: Array[Vector2i] = []
	var cores_local: Array[Vector2i] = occupied.duplicate()

	# 收集所有可通行候选
	var all_candidates: Array[Vector2i] = []
	for y in range(schema.height):
		for x in range(schema.width):
			if schema.is_passable(x, y):
				all_candidates.append(Vector2i(x, y))
	# 注入 RNG 的 Fisher-Yates 洗牌作泊松盘风格采样源
	# 不能用 Array.shuffle —— 走全局 RNG 破坏 seed 注入
	_shuffle_with_rng(all_candidates, rng)

	for pos in all_candidates:
		if result.size() >= target_count:
			break
		# 与核心保持 min_dist_core
		if _too_close_to_any(pos, cores_local, min_dist_core):
			continue
		# 与已采样保持 min_dist_normal
		if _too_close_to_any(pos, result, min_dist_normal):
			continue
		result.append(pos)

	return result


## 检查 pos 与列表中任一点的曼哈顿距离是否 < min_dist
static func _too_close_to_any(
	pos: Vector2i,
	others: Array[Vector2i],
	min_dist: int
) -> bool:
	for o in others:
		if absi(pos.x - o.x) + absi(pos.y - o.y) < min_dist:
			return true
	return false


## 用注入 RNG 做 Fisher-Yates 洗牌（替代 Array.shuffle 的全局 RNG）
static func _shuffle_with_rng(arr: Array[Vector2i], rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		if j != i:
			var tmp: Vector2i = arr[i]
			arr[i] = arr[j]
			arr[j] = tmp


# ─────────────────────────────────────────
# 阶段 5：下限染色
# ─────────────────────────────────────────

## 按势力轮询给城镇 / 村庄染色，每势力达 2 镇 + 6 村
## 染色独占；候选不足时放宽势力场门槛
static func _paint_minimum(
	slots: Array[PersistentSlot],
	cores: Dictionary,
	config: GenConfig,
	rng: RandomNumberGenerator
) -> void:
	# 势力轮询顺序（接口可改；MVP 玩家先手）
	var faction_order: Array[int] = [Faction.PLAYER, Faction.ENEMY_1]
	# 每势力每类型下限（由 config 注入，双方共享同一套；设计 §3.2）
	var town_quota_per_faction: int = config.faction_town_quota
	var village_quota_per_faction: int = config.faction_village_quota
	# 势力 → {TOWN: 已染数, VILLAGE: 已染数}
	var painted: Dictionary = {}
	for fid in faction_order:
		painted[fid] = {
			PersistentSlot.Type.TOWN: 0,
			PersistentSlot.Type.VILLAGE: 0,
		}

	# 轮询直到全势力全类型达标 or 候选耗尽
	var any_progress: bool = true
	while any_progress:
		any_progress = false
		for fid in faction_order:
			# 城镇优先填，再填村庄；同势力两类型独立
			for slot_type in [PersistentSlot.Type.TOWN, PersistentSlot.Type.VILLAGE]:
				var quota: int = town_quota_per_faction \
					if slot_type == PersistentSlot.Type.TOWN \
					else village_quota_per_faction
				if int(painted[fid][slot_type]) >= quota:
					continue
				# 收集本势力本类型的候选（中立 + 该类型）
				var candidates: Array[Vector2i] = []
				for s in slots:
					if s.owner_faction != Faction.NONE:
						continue
					if s.type != slot_type:
						continue
					candidates.append(s.position)
				if candidates.is_empty():
					continue

				# 第一轮：势力场加权随机
				var picked: Vector2i = FactionField.weighted_pick(
					fid, cores, config.field_radius, candidates, rng
				)
				# 兜底：场强全 0 时退化为均匀随机（放宽门槛，§4.3 兜底规则）
				if picked.x < 0:
					var idx: int = rng.randi_range(0, candidates.size() - 1)
					picked = candidates[idx]

				_assign_owner(slots, picked, fid)
				painted[fid][slot_type] = int(painted[fid][slot_type]) + 1
				any_progress = true


## 给指定坐标的 slot 设归属
static func _assign_owner(
	slots: Array[PersistentSlot],
	pos: Vector2i,
	faction_id: int
) -> void:
	for s in slots:
		if s.position == pos:
			s.owner_faction = faction_id
			return


# ─────────────────────────────────────────
# 阶段 6：涌现延伸 m 步
# ─────────────────────────────────────────

## 涌现延伸：m 步内每步每势力最多新染 1 个邻域内 slot
## 邻域定义 §5.3：被本势力某已染色 slot 的 initial_range 覆盖
## MVP 简化：initial_range 取统一值（与势力场半径分离），后续 M4 可改用配置驱动
##
## 染色判定：成功率 = 该 slot 在本势力势力场中的强度
static func _emerge(
	slots: Array[PersistentSlot],
	cores: Dictionary,
	config: GenConfig,
	rng: RandomNumberGenerator
) -> void:
	var faction_order: Array[int] = [Faction.PLAYER, Faction.ENEMY_1]

	# 邻域半径：MVP 取核心 L3 的 initial_range（约 3-4），让涌现有合理范围
	# 严格按 §5.3 应查 PersistentSlot 自己的 initial_range；
	# M4 接入完整配置后改为按 slot 自身查
	var emerge_radius: int = 3

	for step in range(config.emerge_steps):
		for fid in faction_order:
			# 收集本势力已染色 slot 集合
			var owned_positions: Array[Vector2i] = []
			for s in slots:
				if s.owner_faction == fid:
					owned_positions.append(s.position)
			if owned_positions.is_empty():
				continue

			# 收集本势力邻域中的中立候选
			var candidates: Array[Vector2i] = []
			for s in slots:
				if s.owner_faction != Faction.NONE:
					continue
				if _too_close_to_any(s.position, owned_positions, emerge_radius + 1):
					# 注：_too_close_to_any 用 < min_dist 判定，
					# 邻域为"距离 ≤ emerge_radius"，对应 min_dist = emerge_radius + 1
					candidates.append(s.position)
			if candidates.is_empty():
				continue

			# 加权挑选
			var picked: Vector2i = FactionField.weighted_pick(
				fid, cores, config.field_radius, candidates, rng
			)
			if picked.x < 0:
				continue

			# 染色判定：成功率 = picked 在本势力势力场中的强度
			var core_pos: Vector2i = cores[fid] as Vector2i
			var success_rate: float = FactionField.strength_at(
				core_pos, config.field_radius, picked
			)
			if rng.randf() <= success_rate:
				_assign_owner(slots, picked, fid)


# ─────────────────────────────────────────
# 阶段 7：校验
# ─────────────────────────────────────────

## 校验生成结果是否符合硬性约束（§验收标准）
##   - 总数 = total_count
##   - 类型配比 = core_count + town_count + village_count
##   - 普通 slot 间距 ≥ min_dist_normal
##   - 核心 slot 与其他间距 ≥ min_dist_core
##   - 三桶下限：每势力 2 镇 + 6 村
##   - P2#6 补完：核心 level=3 + owner 已定（PLAYER/ENEMY_1 各 1）；普通 slot level=0；核心落在对角区域
static func _validate(
	slots: Array[PersistentSlot],
	config: GenConfig,
	min_dist_normal: int,
	min_dist_core: int
) -> bool:
	# 总数
	if slots.size() != config.total_count:
		return false

	# 类型配比
	var core_actual: int = 0
	var town_actual: int = 0
	var village_actual: int = 0
	for s in slots:
		match s.type:
			PersistentSlot.Type.CORE_TOWN: core_actual += 1
			PersistentSlot.Type.TOWN:      town_actual += 1
			PersistentSlot.Type.VILLAGE:   village_actual += 1
	if core_actual != config.core_count: return false
	if town_actual != config.town_count: return false
	if village_actual != config.village_count: return false

	# 核心 / 普通 slot 初始状态校验（P2#6）
	# 核心：level=3 + 归属已定；双方各 1
	# 普通：level=0
	var player_core_count: int = 0
	var enemy_core_count: int = 0
	var player_core_pos: Vector2i = Vector2i(-1, -1)
	var enemy_core_pos: Vector2i = Vector2i(-1, -1)
	for s in slots:
		if s.type == PersistentSlot.Type.CORE_TOWN:
			if s.level != 3: return false
			if s.owner_faction == Faction.PLAYER:
				player_core_count += 1
				player_core_pos = s.position
			elif s.owner_faction == Faction.ENEMY_1:
				enemy_core_count += 1
				enemy_core_pos = s.position
			else:
				# 核心必须有归属（非中立）
				return false
		else:
			if s.level != 0: return false
	if player_core_count != 1 or enemy_core_count != 1:
		return false
	# 核心对角落区校验：玩家在左上 1/4 内，敌方在右下 1/4 内
	# 阈值放宽到 1/4 边长（容许采样区 zone_max 边界）；防御性检查
	var quarter_w: int = config.width / 4
	var quarter_h: int = config.height / 4
	if player_core_pos.x > quarter_w or player_core_pos.y > quarter_h:
		return false
	if enemy_core_pos.x < (config.width - 1 - quarter_w) or enemy_core_pos.y < (config.height - 1 - quarter_h):
		return false

	# 三桶下限（双方共享 config.faction_*_quota）
	for fid in [Faction.PLAYER, Faction.ENEMY_1]:
		var fid_int: int = fid as int
		var town_owned: int = 0
		var village_owned: int = 0
		for s in slots:
			if s.owner_faction != fid_int:
				continue
			match s.type:
				PersistentSlot.Type.TOWN:    town_owned += 1
				PersistentSlot.Type.VILLAGE: village_owned += 1
		if town_owned < config.faction_town_quota: return false
		if village_owned < config.faction_village_quota: return false

	# 间距校验
	for i in range(slots.size()):
		var a: PersistentSlot = slots[i]
		var min_dist_a: int = min_dist_core \
			if a.type == PersistentSlot.Type.CORE_TOWN \
			else min_dist_normal
		for j in range(i + 1, slots.size()):
			var b: PersistentSlot = slots[j]
			var min_dist_b: int = min_dist_core \
				if b.type == PersistentSlot.Type.CORE_TOWN \
				else min_dist_normal
			# 任一端是核心则用核心间距
			var required: int = maxi(min_dist_a, min_dist_b)
			var actual: int = absi(a.position.x - b.position.x) + absi(a.position.y - b.position.y)
			if actual < required:
				return false

	return true


# ─────────────────────────────────────────
# 配置自检（入口提早暴露非法参数）
# ─────────────────────────────────────────

## 入口配置自检：返回空字符串表示通过；返回非空字符串作为人类可读的错误描述
##
## 检查项分四类：
##   1. 基础几何：地图尺寸 / 总数 / 类型计数为正
##   2. 配比一致：core + town + village == total
##   3. 容量约束：双方下限 ≤ 各类型总数（否则染色阶段必然耗尽候选）
##   4. 算法参数：min_dist / field_radius / core_zone / emerge_steps 处于合法范围
##
## 错误信息格式：「字段名=当前值」+ 期望条件 + 修复建议（指出 map_config.csv 对应键）
static func _validate_config(config: GenConfig) -> String:
	# 1. 基础几何
	if config.width <= 0 or config.height <= 0:
		return "地图尺寸非法 width=%d / height=%d；期望 > 0（map_config: map_width / map_height）" % [
			config.width, config.height
		]
	if config.total_count <= 0:
		return "持久 slot 总数非法 total_count=%d；期望 > 0（map_config: persistent_total_count）" % config.total_count
	if config.core_count < 0 or config.town_count < 0 or config.village_count < 0:
		return "持久 slot 类型计数不能为负 core=%d town=%d village=%d（map_config: persistent_core_count / persistent_town_count / persistent_village_count）" % [
			config.core_count, config.town_count, config.village_count
		]

	# 2. 配比一致性
	var sum_by_type: int = config.core_count + config.town_count + config.village_count
	if sum_by_type != config.total_count:
		return "类型配比与总数不一致：core(%d)+town(%d)+village(%d)=%d ≠ total_count(%d)；请改 map_config.csv 让二者相等" % [
			config.core_count, config.town_count, config.village_count,
			sum_by_type, config.total_count
		]

	# 3. 容量约束（双方下限 * 2 ≤ 各类型总数）
	# 核心：MVP 两方对峙写死要求 core_count == 2（每方 1 个）
	if config.core_count != 2:
		return "核心数 core_count=%d；MVP 两方对峙仅支持 core_count=2（map_config: persistent_core_count）；扩展 N 方需同步改 _place_core_towns" % config.core_count
	# 城镇下限
	var min_required_towns: int = config.faction_town_quota * 2
	if min_required_towns > config.town_count:
		return "城镇下限超出总量：双方各 %d = %d > town_count(%d)；改小 persistent_faction_town_quota 或加大 persistent_town_count" % [
			config.faction_town_quota, min_required_towns, config.town_count
		]
	# 村庄下限
	var min_required_villages: int = config.faction_village_quota * 2
	if min_required_villages > config.village_count:
		return "村庄下限超出总量：双方各 %d = %d > village_count(%d)；改小 persistent_faction_village_quota 或加大 persistent_village_count" % [
			config.faction_village_quota, min_required_villages, config.village_count
		]
	# 下限不能为负（0 表示该类型不强制染色，合法）
	if config.faction_town_quota < 0 or config.faction_village_quota < 0:
		return "下限不能为负：persistent_faction_town_quota=%d / persistent_faction_village_quota=%d" % [
			config.faction_town_quota, config.faction_village_quota
		]

	# 4. 算法参数
	if config.min_dist_normal < 1:
		return "普通 slot 最小间距 min_dist_normal=%d 非法；期望 ≥ 1（map_config: persistent_min_dist_normal）" % config.min_dist_normal
	if config.min_dist_core < 1:
		return "核心 slot 最小间距 min_dist_core=%d 非法；期望 ≥ 1（map_config: persistent_min_dist_core）" % config.min_dist_core
	if config.field_radius <= 0:
		return "势力场半径 field_radius=%d 非法；期望 > 0（map_config: persistent_field_radius）" % config.field_radius
	if config.emerge_steps < 0:
		return "涌现步数 emerge_steps=%d 非法；期望 ≥ 0（map_config: persistent_emerge_steps）" % config.emerge_steps
	if config.core_zone_min < 0.0 or config.core_zone_max <= 0.0 or config.core_zone_min >= config.core_zone_max:
		return "核心采样区间非法 core_zone_min=%.3f / core_zone_max=%.3f；期望 0 ≤ min < max ≤ 0.5（map_config: persistent_core_zone_min / persistent_core_zone_max）" % [
			config.core_zone_min, config.core_zone_max
		]
	if config.max_retries < 1:
		return "最大重试次数 max_retries=%d 非法；期望 ≥ 1（map_config: persistent_max_retries）" % config.max_retries

	# 容量软警告：核心 + 双方下限合计接近 total_count → 中立桶被挤压，涌现染色无空间
	# 不视为 fatal，仅 push_warning 提示
	var total_locked: int = config.core_count + min_required_towns + min_required_villages
	if total_locked > config.total_count:
		return "下限与核心合计 %d > total_count(%d)；中立桶为负，染色无解" % [total_locked, config.total_count]
	if total_locked == config.total_count:
		push_warning("PersistentSlotGenerator: 下限与核心合计 %d == total_count；中立桶为 0，涌现染色无候选可用" % total_locked)

	return ""


# ─────────────────────────────────────────
# slot 构造辅助
# ─────────────────────────────────────────

## 构造一个 PersistentSlot 实例并填基础字段
## 影响范围 / 升级耗时等扩展字段由后续模块从 persistent_slot_config.csv 加载
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
	# initial_range / max_range / growth_rate 由 M4 在使用前从配置注入
	# M2 阶段不预填，避免与 M4 配置加载逻辑产生重复责任
	return s
