class_name EnemyTroopGenerator
extends RefCounted
## 敌方部队生成器
## 从随机池中按权重抽取部队，用于填充关卡的敌方部队列表。
## 抽象为独立类，方便后续扩展（按轮次区分随机池等）。

## 随机池条目
class PoolEntry:
	var troop_type: int = 0
	var quality: int = 0
	var weight: int = 1

## 随机池
var _pool: Array[PoolEntry] = []

## 权重总和（缓存，避免每次抽取时重新计算）
var _total_weight: int = 0

## 每关卡敌方部队数量范围
var _count_min: int = 1
var _count_max: int = 3

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

## 为一个关卡生成敌方部队列表
## 返回生成的 TroopData 数组
func generate_troops() -> Array[TroopData]:
	var troops: Array[TroopData] = []
	if _pool.is_empty() or _total_weight <= 0:
		return troops

	# 随机决定本关卡的部队数量
	var count: int = randi_range(_count_min, _count_max)

	for i in range(count):
		var troop: TroopData = _pick_random_troop()
		if troop != null:
			troops.append(troop)

	return troops

## 按权重从随机池中抽取一支部队
func _pick_random_troop() -> TroopData:
	var roll: int = randi_range(1, _total_weight)
	var cumulative: int = 0
	for entry in _pool:
		cumulative += entry.weight
		if roll <= cumulative:
			var troop: TroopData = TroopData.new()
			troop.troop_type = entry.troop_type as TroopData.TroopType
			troop.quality = entry.quality as TroopData.Quality
			# 敌方部队不需要兵力属性（仅用于结算公式的兵种和品质）
			return troop
	return null
