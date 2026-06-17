class_name ReinforcementRoster
extends RefCounted
## 持久 slot 援军储备抽样（无状态静态类）
##
## 设计原文：tile-advanture-design/持久slot援军_MVP.md §3.1 / §三
##
## 职责：
##   - build_config：把 garrison_config.csv 原始行解析为嵌套查表字典
##   - sample：按 slot_type × pressure_level 查表，从 town_troop_pool 加权抽兵种 + 区间随机品质，
##             产出一份"援军储备名册"（Array of {troop_type, quality} 规格条目）
##
## L1.3d-1 阶段 B：难度索引由 cycle_index 改为 pressure_level（暗影压力等级 P）——
##   garrison 强度随撒点时刻的 P 上档；开局批（MapBootstrap）按基线 P=0 抽样。
##
## 与 EnemyTroopGenerator 的一致性：
##   兵种由 town_troop_pool 各行 weight 加权决定（忽略池行的品质维度），
##   品质由 garrison_config 的 [quality_min, quality_max] 区间随机覆盖——
##   与 EnemyTroopGenerator.generate_troops_for_tier 同思路（先抽兵种、再按档位定品质）。


## 把 garrison_config.csv 原始行（Array[Dictionary]）解析为嵌套查表字典：
##   { slot_type(int): { pressure_level(int): {count_min, count_max, quality_min, quality_max} } }
## 调用方：WorldMap._ready 加载配置阶段
static func build_config(rows: Array) -> Dictionary:
	var cfg: Dictionary = {}
	for entry in rows:
		var row: Dictionary = entry as Dictionary
		if not row.has("slot_type") or not row.has("pressure_level"):
			push_warning("ReinforcementRoster.build_config: 行缺 slot_type/pressure_level，已跳过 -> " + str(row))
			continue
		var st: int = int(row["slot_type"])
		var pl: int = int(row["pressure_level"])
		if not cfg.has(st):
			cfg[st] = {}
		var by_pressure: Dictionary = cfg[st] as Dictionary
		var count_min: int = int(row.get("count_min", "0"))
		var count_max: int = int(row.get("count_max", "0"))
		var quality_min: int = int(row.get("quality_min", "0"))
		var quality_max: int = int(row.get("quality_max", "0"))
		# 轻量守卫（codex P3）：CSV 写反区间时交换 + 告警，避免 randi_range(min>max) 落到未定义行为
		if count_min > count_max:
			push_warning("ReinforcementRoster.build_config: slot_type=%d P=%d 的 count_min(%d) > count_max(%d)，已交换" % [st, pl, count_min, count_max])
			var t: int = count_min; count_min = count_max; count_max = t
		if quality_min > quality_max:
			push_warning("ReinforcementRoster.build_config: slot_type=%d P=%d 的 quality_min(%d) > quality_max(%d)，已交换" % [st, pl, quality_min, quality_max])
			var t2: int = quality_min; quality_min = quality_max; quality_max = t2
		by_pressure[pl] = {
			"count_min":   count_min,
			"count_max":   count_max,
			"quality_min": quality_min,
			"quality_max": quality_max,
		}
	return cfg


## 抽样一份援军储备名册
## slot_type / pressure：查 garrison_cfg（build_config 产出的嵌套字典）
## pool_rows：town_troop_pool.csv 行（troop_type, quality, weight）—— 仅用 troop_type + weight 定兵种分布
## rng：调用方注入（地图生成阶段用确定性 seed → 保证 seed 复现）
## 返回 Array of { "troop_type": int, "quality": int }；未配置 type×pressure / 池空 / count<=0 → 空数组
static func sample(slot_type: int, pressure: int, garrison_cfg: Dictionary, pool_rows: Array, rng: RandomNumberGenerator) -> Array:
	var roster: Array = []
	# 查表（用 has 守卫避免 .get 返回 Variant 触发类型检查）
	if not garrison_cfg.has(slot_type):
		return roster
	var by_pressure: Dictionary = garrison_cfg[slot_type] as Dictionary
	if not by_pressure.has(pressure):
		return roster
	var cfg: Dictionary = by_pressure[pressure] as Dictionary

	var count_min: int = int(cfg.get("count_min", 0))
	var count_max: int = int(cfg.get("count_max", 0))
	var quality_min: int = int(cfg.get("quality_min", 0))
	var quality_max: int = int(cfg.get("quality_max", 0))
	if count_max <= 0 or pool_rows.is_empty():
		return roster

	# 兵种权重总和（缓存，避免每条目重算）
	var total_weight: int = 0
	for entry in pool_rows:
		var row: Dictionary = entry as Dictionary
		total_weight += int(row.get("weight", "1"))
	if total_weight <= 0:
		return roster

	var count: int = rng.randi_range(count_min, count_max)
	for i in range(count):
		var troop_type: int = _pick_troop_type(pool_rows, total_weight, rng)
		var quality: int = rng.randi_range(quality_min, quality_max)
		roster.append({"troop_type": troop_type, "quality": quality})
	return roster


## 触发判定：slot 到战场 arena 的最近格曼哈顿距离是否 ≤ trigger_range
## 用"点到矩形最近距离"公式（slot 在 arena 内时距离为 0），避免逐格扫描整个 arena
## 抽成静态供 WorldMap._slot_in_battle_range 调用 + headless 测试直接验证
static func is_in_trigger_range(slot_pos: Vector2i, arena: Rect2i, trigger_range: int) -> bool:
	var min_x: int = arena.position.x
	var max_x: int = arena.end.x - 1
	var min_y: int = arena.position.y
	var max_y: int = arena.end.y - 1
	var dx: int = maxi(0, maxi(min_x - slot_pos.x, slot_pos.x - max_x))
	var dy: int = maxi(0, maxi(min_y - slot_pos.y, slot_pos.y - max_y))
	return dx + dy <= trigger_range


## 战后扣减：从 roster 原地移除每个已入场（consumed）条目（一次性消耗）
## 未入场条目（不在 consumed 内，如 cap 截断 / 找不到空格）保留
## 抽成静态供 WorldMap._consume_reinforcement_rosters 调用 + headless 测试直接验证
static func apply_consumption(roster: Array, consumed: Array) -> void:
	for entry in consumed:
		roster.erase(entry)


## 加权抽兵种（仅决定 troop_type；与 EnemyTroopGenerator._pick_random_troop_type 同算法）
static func _pick_troop_type(pool_rows: Array, total_weight: int, rng: RandomNumberGenerator) -> int:
	var roll: int = rng.randi_range(1, total_weight)
	var cumulative: int = 0
	for entry in pool_rows:
		var row: Dictionary = entry as Dictionary
		cumulative += int(row.get("weight", "1"))
		if roll <= cumulative:
			return int(row.get("troop_type", "0"))
	# 兜底：理论不可达（roll <= total_weight 必命中）
	var last: Dictionary = pool_rows[pool_rows.size() - 1] as Dictionary
	return int(last.get("troop_type", "0"))
