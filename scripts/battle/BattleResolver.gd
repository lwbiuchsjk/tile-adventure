class_name BattleResolver
extends RefCounted
## 战斗结算接口
## 公式驱动：遍历敌方部队，按兵种克制和品质差异计算我方兵力损耗。
## 后续接入战斗引擎时，替换 resolve() 内部实现即可。

## 战斗结果数据
class BattleResult extends RefCounted:
	## 是否胜利
	var victory: bool = true
	## 我方承受的总兵力损耗
	var damage_taken: int = 0

## 克制矩阵（从 counter_matrix.csv 加载）
## 格式：{ 攻击方兵种ID : { 防御方兵种ID : float } }
static var _counter_matrix: Dictionary = {}

## 兵种名称到 ID 的映射（用于解析 CSV 列名）
const TROOP_NAME_TO_ID: Dictionary = {
	"SWORD": 0,
	"BOW": 1,
	"SPEAR": 2,
	"CAVALRY": 3,
	"SHIELD": 4,
}

## 从 counter_matrix.csv 行数据加载克制矩阵
## rows: ConfigLoader.load_csv() 返回的 Array[Dictionary]
static func load_counter_matrix(rows: Array) -> void:
	_counter_matrix = {}
	for entry in rows:
		var row: Dictionary = entry as Dictionary
		var attacker_name: String = row.get("attacker", "") as String
		if not TROOP_NAME_TO_ID.has(attacker_name):
			continue
		var attacker_id: int = int(TROOP_NAME_TO_ID[attacker_name])
		var defender_map: Dictionary = {}
		for def_name in TROOP_NAME_TO_ID:
			var def_id: int = int(TROOP_NAME_TO_ID[def_name])
			var value: float = float(row.get(def_name, "1.0"))
			defender_map[def_id] = value
		_counter_matrix[attacker_id] = defender_map

## 查询克制系数
## attacker_type: 攻击方（敌方）兵种 ID
## defender_type: 防御方（我方）兵种 ID
static func get_counter_factor(attacker_type: int, defender_type: int) -> float:
	if _counter_matrix.has(attacker_type):
		var def_map: Dictionary = _counter_matrix[attacker_type] as Dictionary
		if def_map.has(defender_type):
			return float(def_map[defender_type])
	return 1.0

## 执行战斗结算（公式驱动）
## player_troop: 我方部队（单支）
## enemy_troops: 敌方部队列表
## config: 战斗配置字典（从 battle_config.csv 加载）
## 返回 BattleResult
static func resolve(player_troop: TroopData, enemy_troops: Array[TroopData], config: Dictionary) -> BattleResult:
	var result: BattleResult = BattleResult.new()
	result.victory = true

	# 读取配置参数
	var base_damage: float = float(config.get("base_damage", "50"))
	var quality_k: float = float(config.get("quality_k", "0.2"))
	var quality_min: float = float(config.get("quality_min_factor", "0.5"))
	var battle_rounds: int = int(config.get("default_battle_rounds", "3"))

	# 遍历每支敌方部队，按公式计算伤害并累加
	var total_damage: float = 0.0
	for enemy in enemy_troops:
		# 克制系数：敌方兵种 → 我方兵种
		var counter: float = get_counter_factor(
			enemy.troop_type as int, player_troop.troop_type as int
		)
		# 品质差系数：敌品质越高，对我方伤害越大
		var quality_diff: float = float(enemy.quality as int - player_troop.quality as int)
		var quality_factor: float = maxf(quality_min, 1.0 + quality_k * quality_diff)
		# 单支敌方部队伤害
		var damage: float = base_damage * counter * quality_factor * float(battle_rounds)
		total_damage += damage

	result.damage_taken = int(total_damage)
	return result
