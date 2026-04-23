class_name ProductionSystem
extends RefCounted
## 产出结算系统（M6）
##
## 设计原文：
##   tile-advanture-design/城建锚实装/M6_产出结算.md
##   tile-advanture-design/持久slot基础功能设计.md §5 产出触发
##   tile-advanture-design/占位产出与最小验证设计.md §2 玩家侧产出（§2.3 村庄 / §2.4 城镇 / §2.5 核心 / §2.6 tick 与结算分离）
##
## 职责：
##   - 扎营结算入口 `settle_camp`：查 C 作用域 → 逐 slot 调产出构造器 → 返回产出结构列表
##   - 即时 slot 采集入口 `collect_immediate_slot`：4 项等权随机 × 1/2 等权数量
##   - 应用入口 `apply_production`：把产出结构落到玩家资源 / 背包 / 石料
##
## 解耦原则：
##   - 静态类，不持有 WorldMap / Inventory / TroopData 的直接引用
##   - `settle_camp / collect_immediate_slot` 返回纯数据（Array[Dictionary]）
##   - `apply_production` 通过回调式接口把产出落地到具体容器，避免 ProductionSystem 依赖 UI / 库存类
##
## MVP 边界（§M6 本模块覆盖）：
##   - 敌方占据的村庄 / 城镇不产出（`slots_covering` 已按 camper_faction 过滤）
##   - 即时 slot 采集忽略 slot 自身的 resource_type 配置，统一按 4 项等权随机
##     （生成时的视觉类型保留，采集时 pragma 重新抽；视觉与采集的对齐留待后续 UX 回看）
##   - 城镇产出 TROOP 类 ItemData（从"部队模板池"按品质抽），不产出经验 / 补给类


# ─────────────────────────────────────────
# 产出结构（pure data）
# ─────────────────────────────────────────
## 返回值条目 schema：
##   {
##     "kind": "resource" | "item" | "stone",
##     "resource_type": int (kind=resource 时有效；ResourceSlot.ResourceType 枚举)
##     "amount": int         (kind=resource/stone 时有效；kind=item 时等价于 item.stack_count)
##     "item": ItemData      (kind=item 时有效；产出的 ItemData 实例)
##     "source": String      (可选，调试用，标注产出来源 slot 描述)
##   }

const KIND_RESOURCE: String = "resource"
const KIND_ITEM: String = "item"
const KIND_STONE: String = "stone"
const KIND_ERROR: String = "error"     ## 产出失败（池空等）；entry["message"] 描述原因


# ─────────────────────────────────────────
# 随机池定义
# ─────────────────────────────────────────

## 村庄 L1+ 的 4 项等权池
## 顺序无意义，权重都为 1
const RANDOM_POOL: Array[int] = [
	ResourceSlot.ResourceType.SUPPLY,
	ResourceSlot.ResourceType.HP_RESTORE,
	ResourceSlot.ResourceType.EXP,
	ResourceSlot.ResourceType.STONE,
]


# ─────────────────────────────────────────
# 部队模板池（城镇产出）
# ─────────────────────────────────────────

## 部队模板池：{ quality(int) : Array[Dictionary{troop_type, weight}] }
## 从 enemy_troop_pool.csv 加载；按 quality 分桶
## 城镇产出按"允许品质集合"跨桶合并抽取
static var _troop_pool_by_quality: Dictionary = {}


## 加载部队模板池（从 enemy_troop_pool.csv 行）
## rows 字段：troop_type, quality, weight
static func load_troop_pool(rows: Array) -> void:
	_troop_pool_by_quality = {}
	for entry in rows:
		var row: Dictionary = entry as Dictionary
		var q: int = int(row.get("quality", "0"))
		var troop_type: int = int(row.get("troop_type", "0"))
		var weight: int = int(row.get("weight", "1"))
		if not _troop_pool_by_quality.has(q):
			_troop_pool_by_quality[q] = []
		var bucket: Array = _troop_pool_by_quality[q] as Array
		bucket.append({"troop_type": troop_type, "weight": weight})


## 清空部队池（测试用）
static func clear_state() -> void:
	_troop_pool_by_quality = {}


# ─────────────────────────────────────────
# 扎营结算主入口
# ─────────────────────────────────────────

## 玩家扎营结算：给定扎营位置与势力，返回该 slot 覆盖下的全部产出
## camp_pos       —— 扎营格（通常 = 玩家单位位置）
## camper_faction —— 扎营势力（MVP 仅 PLAYER 调用；敌方侧 MVP 不产出）
## all_slots      —— 所有持久 slot（由调用方传入，通常 = MapSchema.persistent_slots）
## rng            —— 随机数生成器（便于测试注入；不传则内部 new 一个）
##
## MVP 敌方静默：若 camper_faction == ENEMY_1，OccupationSystem.slots_covering
## 只返回同势力 slot；即使有覆盖，本函数返回空（见 §2.4 "敌方占据的城镇不产出"）
## 实装上通过"camper_faction != PLAYER 提前返回"更明确
## MVP 边界约束：camper_faction != PLAYER 早返回 ——
##   敌方 AI 城镇产出（§3.3 待补）需 M7 接入时**拆掉此守卫**，
##   改为策略参数或拆分 settle_player_camp / settle_enemy_camp 两入口
static func settle_camp(
	camp_pos: Vector2i,
	camper_faction: int,
	all_slots: Array,
	rng: RandomNumberGenerator = null
) -> Array:
	var results: Array = []
	if camper_faction != Faction.PLAYER:
		# MVP：敌方扎营不产出（§2.4 + §3.3 待补）
		return results

	var rng_local: RandomNumberGenerator = rng if rng != null else RandomNumberGenerator.new()

	var covering: Array = OccupationSystem.slots_covering(camp_pos, camper_faction, all_slots)
	for entry in covering:
		var slot: PersistentSlot = entry as PersistentSlot
		if slot == null:
			continue
		var items: Array = _produce_for_slot(slot, rng_local)
		results.append_array(items)
	return results


## 单个持久 slot 的产出分发
static func _produce_for_slot(slot: PersistentSlot, rng: RandomNumberGenerator) -> Array:
	match slot.type:
		PersistentSlot.Type.VILLAGE:
			return _village_output(slot, rng)
		PersistentSlot.Type.TOWN:
			return _town_output(slot, rng)
		PersistentSlot.Type.CORE_TOWN:
			return _core_town_output(slot, rng)
	return []


# ─────────────────────────────────────────
# 村庄产出（§2.3）
# ─────────────────────────────────────────

## 村庄各级产出：
##   L0 = 补给 × 1（固定）
##   L1 = 随机池 × 1
##   L2 = 随机池 × 2
##   L3 = 随机池 × 2（L3 差异在 max_range 抬升，由 M5 完成）
static func _village_output(slot: PersistentSlot, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	if slot.level == 0:
		out.append(_make_resource_entry(ResourceSlot.ResourceType.SUPPLY, 1, slot))
		return out
	# L1 = 1 项 / L2 = 2 项 / L3 = 2 项
	var pick_count: int = 1 if slot.level == 1 else 2
	for i in range(pick_count):
		out.append(_random_pool_entry(rng, slot))
	return out


# ─────────────────────────────────────────
# 城镇产出（§2.4）
# ─────────────────────────────────────────

## 城镇各级产出：按品质阶梯抽 TROOP 道具
##   L0 = R × 1
##   L1 = R / SR × 1
##   L2 = R / SR / SSR × 1
##   L3 = 同 L2（max_range 抬升由 M5 完成）
## 池空时返回 error 条目（供 format_results_text / notice 显式提示），避免静默失效
static func _town_output(slot: PersistentSlot, rng: RandomNumberGenerator) -> Array:
	var allowed_qualities: Array[int] = _town_qualities_for_level(slot.level)
	var item: ItemData = _pick_troop_item(allowed_qualities, rng)
	var out: Array = []
	if item != null:
		out.append(_make_item_entry(item, slot))
	else:
		out.append(_make_error_entry("城镇产出池缺品质 %s" % _format_qualities(allowed_qualities), slot))
	return out


## 根据城镇等级返回允许的品质列表
static func _town_qualities_for_level(level: int) -> Array[int]:
	match level:
		0:
			return [TroopData.Quality.R]
		1:
			return [TroopData.Quality.R, TroopData.Quality.SR]
		_:
			# L2 / L3 均为全品质（§2.4）
			return [TroopData.Quality.R, TroopData.Quality.SR, TroopData.Quality.SSR]


## 核心城镇产出（§2.5）：MVP 直接套用城镇 L3 行
## 池空时返回 error 条目（同 _town_output 语义）
static func _core_town_output(slot: PersistentSlot, rng: RandomNumberGenerator) -> Array:
	# 构造一个临时 L3 影子参数传入 _town_qualities_for_level，不修改原 slot
	var allowed_qualities: Array[int] = [TroopData.Quality.R, TroopData.Quality.SR, TroopData.Quality.SSR]
	var item: ItemData = _pick_troop_item(allowed_qualities, rng)
	var out: Array = []
	if item != null:
		out.append(_make_item_entry(item, slot))
	else:
		out.append(_make_error_entry("核心产出池缺品质 %s" % _format_qualities(allowed_qualities), slot))
	return out


# ─────────────────────────────────────────
# 即时 slot 采集（§2.2 / §M6 §即时 slot）
# ─────────────────────────────────────────

## 玩家走到即时 slot 时的采集结果
## 4 项等权随机 × 1/2 等权数量
## 注意：忽略 ResourceSlot 自身的 resource_type / output_amount 配置，
## 统一按 M6 等权规则重新抽取（视觉上保留 slot 原类型，采集时随机）
static func collect_immediate_slot(rng: RandomNumberGenerator = null) -> Dictionary:
	var rng_local: RandomNumberGenerator = rng if rng != null else RandomNumberGenerator.new()
	var res_type: int = RANDOM_POOL[rng_local.randi_range(0, RANDOM_POOL.size() - 1)]
	var amount: int = rng_local.randi_range(1, 2)
	return {
		"kind": KIND_STONE if res_type == ResourceSlot.ResourceType.STONE else KIND_RESOURCE,
		"resource_type": res_type,
		"amount": amount,
		"source": "即时资源点",
	}


# ─────────────────────────────────────────
# 构造条目工具
# ─────────────────────────────────────────

## 从 4 项等权池抽一项，按 1/2 等权给数量，构造为资源 / 石料条目
static func _random_pool_entry(rng: RandomNumberGenerator, slot: PersistentSlot) -> Dictionary:
	var res_type: int = RANDOM_POOL[rng.randi_range(0, RANDOM_POOL.size() - 1)]
	var amount: int = rng.randi_range(1, 2)
	if res_type == ResourceSlot.ResourceType.STONE:
		return _make_stone_entry(amount, slot)
	return _make_resource_entry(res_type, amount, slot)


## 构造资源类条目（补给 / 恢复药 / 经验书 → 进背包或加补给值）
static func _make_resource_entry(res_type: int, amount: int, slot: PersistentSlot) -> Dictionary:
	return {
		"kind": KIND_RESOURCE,
		"resource_type": res_type,
		"amount": amount,
		"source": _slot_source_text(slot),
	}


## 构造石料条目（直接入势力全局石料库）
static func _make_stone_entry(amount: int, slot: PersistentSlot) -> Dictionary:
	return {
		"kind": KIND_STONE,
		"resource_type": ResourceSlot.ResourceType.STONE,
		"amount": amount,
		"source": _slot_source_text(slot),
	}


## 构造 ItemData 条目（TROOP 类 / HP_RESTORE 类 / EXP 类 → 入背包）
static func _make_item_entry(item: ItemData, slot: PersistentSlot) -> Dictionary:
	return {
		"kind": KIND_ITEM,
		"item": item,
		"amount": item.stack_count,
		"source": _slot_source_text(slot),
	}


## 构造失败条目（池空 / 配置异常等）
## message 用于 format_results_text 输出给玩家的可读原因
static func _make_error_entry(message: String, slot: PersistentSlot) -> Dictionary:
	return {
		"kind": KIND_ERROR,
		"message": message,
		"source": _slot_source_text(slot),
	}


## 品质集合人类可读格式化
static func _format_qualities(qualities: Array[int]) -> String:
	var parts: Array[String] = []
	for q in qualities:
		parts.append(TroopData.QUALITY_NAMES.get(q, "?") as String)
	return "/".join(parts)


## slot 来源描述（用于飘字 / 日志 / 调试）
static func _slot_source_text(slot: PersistentSlot) -> String:
	if slot == null:
		return ""
	return "%s L%d (%d,%d)" % [
		slot.get_type_name(), slot.level, slot.position.x, slot.position.y
	]


# ─────────────────────────────────────────
# 部队道具抽取
# ─────────────────────────────────────────

## 从"部队模板池"按允许品质集合抽一个 TROOP 类 ItemData
## 跨允许品质合并后按 weight 加权抽取
## 池为空返回 null；调用方应判空
static func _pick_troop_item(allowed_qualities: Array[int], rng: RandomNumberGenerator) -> ItemData:
	var candidates: Array[Dictionary] = []
	var total_weight: int = 0
	for q in allowed_qualities:
		if not _troop_pool_by_quality.has(q):
			continue
		var bucket: Array = _troop_pool_by_quality[q] as Array
		for e in bucket:
			var row: Dictionary = e as Dictionary
			var entry: Dictionary = {
				"troop_type": int(row.get("troop_type", 0)),
				"quality": q,
				"weight": int(row.get("weight", 1)),
			}
			candidates.append(entry)
			total_weight += entry["weight"]
	if candidates.is_empty() or total_weight <= 0:
		push_warning("ProductionSystem._pick_troop_item: 部队池为空或 quality 无匹配 → %s" % str(allowed_qualities))
		return null

	var roll: int = rng.randi_range(1, total_weight)
	var cumulative: int = 0
	for entry in candidates:
		cumulative += int(entry["weight"])
		if roll <= cumulative:
			return _make_troop_item(int(entry["troop_type"]), int(entry["quality"]))
	# 兜底：理论不可达（roll <= total_weight 必命中）
	var last: Dictionary = candidates[candidates.size() - 1]
	return _make_troop_item(int(last["troop_type"]), int(last["quality"]))


## 构造一个 TROOP 类 ItemData（参考 WorldMap._grant_troop_reward 的风格）
static func _make_troop_item(troop_type: int, quality: int) -> ItemData:
	var item: ItemData = ItemData.new()
	item.type = ItemData.ItemType.TROOP
	item.troop_type = troop_type
	item.quality = quality
	item.stack_count = 1
	# display_name 复用 TroopData 的命名（类型 + 品质）
	var type_name: String = TroopData.TROOP_TYPE_NAMES.get(troop_type, "未知") as String
	var quality_name: String = TroopData.QUALITY_NAMES.get(quality, "?") as String
	item.display_name = "%s(%s)" % [type_name, quality_name]
	return item


# ─────────────────────────────────────────
# 产出应用（Apply）
# ─────────────────────────────────────────

## 应用产出结构列表到具体容器
## 通过 Callable 回调接口注入，保持 ProductionSystem 不依赖 WorldMap / Inventory 等具体类
##
## add_supply_cb(amount: int) -> void                —— 补给通道入账（MVP 为 WorldMap._supply += amount）
## add_stone_cb(amount: int) -> void                 —— 石料通道入账（MVP 为 add_stone(PLAYER, amount)）
## add_item_cb(item: ItemData) -> bool               —— 背包入库；返回是否成功（背包满返回 false）
##
## 返回 {
##   "applied": Array      —— 实际入账成功的条目（子集）
##   "dropped": Array      —— 入账失败的条目（背包满 / 池空 / 其他）
## }
## 调用方（通常 WorldMap）用返回值分类展示 notice
static func apply_production(
	results: Array,
	add_supply_cb: Callable,
	add_stone_cb: Callable,
	add_item_cb: Callable
) -> Dictionary:
	var applied: Array = []
	var dropped: Array = []
	for entry in results:
		var r: Dictionary = entry as Dictionary
		var kind: String = r.get("kind", "") as String
		match kind:
			KIND_RESOURCE:
				var res_type: int = int(r.get("resource_type", 0))
				var amount: int = int(r.get("amount", 0))
				var ok: bool = _apply_resource(res_type, amount, add_supply_cb, add_item_cb)
				if ok:
					applied.append(r)
				else:
					dropped.append(r)
			KIND_STONE:
				var amount_stone: int = int(r.get("amount", 0))
				if add_stone_cb.is_valid():
					add_stone_cb.call(amount_stone)
					applied.append(r)
				else:
					dropped.append(r)
			KIND_ITEM:
				var item: ItemData = r.get("item") as ItemData
				if item != null and add_item_cb.is_valid():
					var ok_item: bool = bool(add_item_cb.call(item))
					if ok_item:
						applied.append(r)
					else:
						# 背包满等原因：标为 dropped，调用方可展示"N 个道具丢失"
						dropped.append(r)
				else:
					dropped.append(r)
			KIND_ERROR:
				# 池空 / 配置异常：直接归 dropped，message 字段给玩家看
				dropped.append(r)
			_:
				dropped.append(r)
	return {"applied": applied, "dropped": dropped}


## 非石料类资源的归属分发：
##   SUPPLY → add_supply_cb（+= 数值）
##   HP_RESTORE → 构造恢复药 ItemData（复用 WorldMap 现有命名）→ add_item_cb
##   EXP → 构造经验书 ItemData → add_item_cb
## 返回是否入账成功（背包满 / 回调无效 → false）
static func _apply_resource(
	res_type: int, amount: int,
	add_supply_cb: Callable,
	add_item_cb: Callable
) -> bool:
	if amount <= 0:
		return false
	if res_type == ResourceSlot.ResourceType.SUPPLY:
		if add_supply_cb.is_valid():
			add_supply_cb.call(amount)
			return true
		return false
	# HP_RESTORE / EXP → ItemData
	var item: ItemData = _make_consumable_item(res_type, amount)
	if item == null or not add_item_cb.is_valid():
		return false
	return bool(add_item_cb.call(item))


## 构造 HP_RESTORE / EXP 的 ItemData
## 字段沿用 WorldMap._collect_resource 既有风格（item_id 9001/9002，value = amount × 每单位值）
static func _make_consumable_item(res_type: int, amount: int) -> ItemData:
	var item: ItemData = ItemData.new()
	item.stack_count = 1
	match res_type:
		ResourceSlot.ResourceType.HP_RESTORE:
			item.type = ItemData.ItemType.HP_RESTORE
			item.display_name = "兵力恢复药"
			item.value = amount * 100
			item.item_id = 9001
		ResourceSlot.ResourceType.EXP:
			item.type = ItemData.ItemType.EXP
			item.display_name = "经验书"
			item.value = amount * 50
			item.item_id = 9002
		_:
			push_warning("ProductionSystem._make_consumable_item: 未知 resource_type=%d" % res_type)
			return null
	return item


# ─────────────────────────────────────────
# 展示辅助（可选，用于飘字）
# ─────────────────────────────────────────

## 把产出结构列表格式化为人类可读字符串（用于 _show_notice）
## 通常展示"入账成功"的条目；KIND_ERROR 条目在这里跳过，由 format_dropped_text 另行展示
static func format_results_text(results: Array) -> String:
	if results.is_empty():
		return "无产出"
	var parts: Array[String] = []
	for entry in results:
		var r: Dictionary = entry as Dictionary
		var kind: String = r.get("kind", "") as String
		match kind:
			KIND_RESOURCE:
				var res_type: int = int(r.get("resource_type", 0))
				var amount: int = int(r.get("amount", 0))
				var name: String = ResourceSlot.RESOURCE_TYPE_NAMES.get(res_type, "?") as String
				parts.append("%s×%d" % [name, amount])
			KIND_STONE:
				parts.append("石料×%d" % int(r.get("amount", 0)))
			KIND_ITEM:
				var item: ItemData = r.get("item") as ItemData
				if item != null:
					parts.append(item.display_name)
			# KIND_ERROR 跳过（未入账，不显示在"获得"里）
	if parts.is_empty():
		return "无产出"
	return " / ".join(parts)


## 把 dropped 条目格式化为失败提示（用于第二条 notice）
## 不同失败原因：背包满的物品 / 池空的 error 条目
static func format_dropped_text(dropped: Array) -> String:
	if dropped.is_empty():
		return ""
	var parts: Array[String] = []
	for entry in dropped:
		var r: Dictionary = entry as Dictionary
		var kind: String = r.get("kind", "") as String
		match kind:
			KIND_ITEM:
				var item: ItemData = r.get("item") as ItemData
				if item != null:
					parts.append("%s（背包满丢弃）" % item.display_name)
			KIND_RESOURCE:
				var res_type: int = int(r.get("resource_type", 0))
				var amount: int = int(r.get("amount", 0))
				var name: String = ResourceSlot.RESOURCE_TYPE_NAMES.get(res_type, "?") as String
				parts.append("%s×%d（背包满丢弃）" % [name, amount])
			KIND_ERROR:
				parts.append(r.get("message", "产出异常") as String)
	return " / ".join(parts)
