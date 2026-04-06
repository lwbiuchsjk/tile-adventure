class_name EnemyTroopGenerator
extends RefCounted
## 敌方部队生成器
## 从随机池中按权重抽取部队，用于填充关卡的敌方部队列表。
## 支持强度档位生成：按档位的数量范围和品质范围生成部队。

## 随机池条目
class PoolEntry:
	var troop_type: int = 0
	var quality: int = 0
	var weight: int = 1

## 随机池
var _pool: Array[PoolEntry] = []

## 权重总和（缓存，避免每次抽取时重新计算）
var _total_weight: int = 0

## 每关卡敌方部队数量范围（兜底，优先使用档位配置）
var _count_min: int = 1
var _count_max: int = 3

## 强度档位配置：{tier_id: {count_min, count_max, quality_min, quality_max}}
var _tier_configs: Dictionary = {}

## 从配置初始化随机池
## pool_rows: enemy_troop_pool.csv 的行数据
## spawn_cfg: enemy_spawn_config.csv 的 key-value 字典
func init_from_config(pool_rows: Array, spawn_cfg: Dictionary) -> void:
	_pool = []
	_total_weight = 0
	for entry in pool_rows:
		var row: Dictionary = entry as Dictionary
		var e: PoolEntry = PoolEntry.new()
		e.troop_type = int(row.get("troop_type", "0"))
		e.quality = int(row.get("quality", "0"))
		e.weight = int(row.get("weight", "1"))
		_pool.append(e)
		_total_weight += e.weight

	_count_min = int(spawn_cfg.get("troop_count_min", "1"))
	_count_max = int(spawn_cfg.get("troop_count_max", "3"))

## 从 enemy_tier_config.csv 加载强度档位配置
func load_tier_config(rows: Array) -> void:
	_tier_configs = {}
	for entry in rows:
		var row: Dictionary = entry as Dictionary
		var tier: int = int(row.get("tier", "0"))
		_tier_configs[tier] = {
			"count_min": int(row.get("troop_count_min", "1")),
			"count_max": int(row.get("troop_count_max", "1")),
			"quality_min": int(row.get("quality_min", "0")),
			"quality_max": int(row.get("quality_max", "0")),
		}

## 按强度档位生成敌方部队列表
## tier: 强度档位（0=弱, 1=中, 2=强, 3=超）
## 兵种从随机池按权重抽取，品质在档位范围内随机
func generate_troops_for_tier(tier: int) -> Array[TroopData]:
	var troops: Array[TroopData] = []
	if _pool.is_empty() or _total_weight <= 0:
		return troops

	# 从档位配置读取参数，无配置则使用兜底值
	var cfg: Dictionary = _tier_configs.get(tier, {}) as Dictionary
	var count_min: int = int(cfg.get("count_min", _count_min))
	var count_max: int = int(cfg.get("count_max", _count_max))
	var quality_min: int = int(cfg.get("quality_min", 0))
	var quality_max: int = int(cfg.get("quality_max", 0))

	var count: int = randi_range(count_min, count_max)
	for i in range(count):
		var troop: TroopData = _pick_random_troop_type()
		if troop != null:
			# 品质在档位范围内随机
			troop.quality = randi_range(quality_min, quality_max) as TroopData.Quality
			troops.append(troop)
	return troops

## 为一个关卡生成敌方部队列表（兼容旧接口，使用默认数量范围）
## 返回生成的 TroopData 数组
func generate_troops() -> Array[TroopData]:
	var troops: Array[TroopData] = []
	if _pool.is_empty() or _total_weight <= 0:
		return troops
	var count: int = randi_range(_count_min, _count_max)
	for i in range(count):
		var troop: TroopData = _pick_random_troop_type()
		if troop != null:
			troops.append(troop)
	return troops

## 按权重从随机池中抽取一支部队（仅决定兵种，品质由调用方控制）
func _pick_random_troop_type() -> TroopData:
	var roll: int = randi_range(1, _total_weight)
	var cumulative: int = 0
	for entry in _pool:
		cumulative += entry.weight
		if roll <= cumulative:
			var troop: TroopData = TroopData.new()
			troop.troop_type = entry.troop_type as TroopData.TroopType
			troop.quality = entry.quality as TroopData.Quality
			return troop
	return null
