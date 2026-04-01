class_name BattleResolver
extends RefCounted
## 战斗结算接口
## 公式驱动：双向伤害计算，敌方对我方 + 我方对敌方。
## 支持击退/击败倍率缩放。
## 后续接入战斗引擎时，替换 resolve() 内部实现即可。

## 战斗结果数据
class BattleResult extends RefCounted:
	## 是否胜利
	var victory: bool = true
	## 每支我方部队承受的兵力损耗列表（与输入的 player_troops 一一对应）
	var damages: Array[int] = []
	## 每支敌方部队承受的兵力损耗列表（与输入的 enemy_troops 一一对应）
	var enemy_damages: Array[int] = []
	## 我方承受的总兵力损耗（兼容旧接口）
	var damage_taken: int = 0

	## 应用伤害倍率，返回新的 BattleResult（不修改原始结果）
	## player_rate: 我方伤害倍率
	## enemy_rate: 敌方伤害倍率
	func apply_damage_rate(player_rate: float, enemy_rate: float) -> BattleResult:
		var scaled: BattleResult = BattleResult.new()
		scaled.victory = victory
		scaled.damages = []
		for d in damages:
			scaled.damages.append(int(float(d) * player_rate))
		scaled.enemy_damages = []
		for d in enemy_damages:
			scaled.enemy_damages.append(int(float(d) * enemy_rate))
		var total: int = 0
		for d in scaled.damages:
			total += d
		scaled.damage_taken = total
		return scaled

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
## attacker_type: 攻击方兵种 ID
## defender_type: 防御方兵种 ID
static func get_counter_factor(attacker_type: int, defender_type: int) -> float:
	if _counter_matrix.has(attacker_type):
		var def_map: Dictionary = _counter_matrix[attacker_type] as Dictionary
		if def_map.has(defender_type):
			return float(def_map[defender_type])
	return 1.0

## 获取难度修正后的有效基础伤害
## 抽象为独立方法，方便后续扩展难度影响更多维度
static func get_effective_base_damage(base_damage: float, difficulty: int, damage_increment: float) -> float:
	return base_damage + float(difficulty) * damage_increment

## 执行战斗结算（公式驱动，双向伤害计算）
## player_troops: 我方部队列表
## enemy_troops: 敌方部队列表
## config: 战斗配置字典（从 battle_config.csv 加载）
## difficulty: 关卡难度值（轮次索引，默认 0）
## damage_increment: 每轮难度增加的伤害值（默认 0）
## 返回 BattleResult，damages 与 player_troops 一一对应，enemy_damages 与 enemy_troops 一一对应
static func resolve(player_troops: Array[TroopData], enemy_troops: Array[TroopData], config: Dictionary, difficulty: int = 0, damage_increment: float = 0.0) -> BattleResult:
	var result: BattleResult = BattleResult.new()
	result.victory = true
	result.damages = []
	result.enemy_damages = []

	# 读取配置参数
	var base_damage: float = float(config.get("base_damage", "50"))
	var quality_k: float = float(config.get("quality_k", "0.2"))
	var quality_min: float = float(config.get("quality_min_factor", "0.5"))
	var battle_rounds: int = int(config.get("default_battle_rounds", "3"))

	# 计算有效基础伤害（含难度修正）
	var effective_base: float = get_effective_base_damage(base_damage, difficulty, damage_increment)

	# ── 敌方 → 我方伤害 ──
	var grand_total: int = 0
	for player_troop in player_troops:
		var troop_damage: float = 0.0
		for enemy in enemy_troops:
			# 克制系数：敌方兵种 → 我方兵种
			var counter: float = get_counter_factor(
				enemy.troop_type as int, player_troop.troop_type as int
			)
			# 品质差系数：敌品质越高，对我方伤害越大
			var quality_diff: float = float(enemy.quality as int - player_troop.quality as int)
			var quality_factor: float = maxf(quality_min, 1.0 + quality_k * quality_diff)
			var damage: float = effective_base * counter * quality_factor * float(battle_rounds)
			troop_damage += damage
		var int_damage: int = int(troop_damage)
		result.damages.append(int_damage)
		grand_total += int_damage
	result.damage_taken = grand_total

	# ── 我方 → 敌方伤害（反向计算：攻防方向互换） ──
	for enemy in enemy_troops:
		var enemy_dmg: float = 0.0
		for player_troop in player_troops:
			# 克制系数：我方兵种 → 敌方兵种（方向互换）
			var counter: float = get_counter_factor(
				player_troop.troop_type as int, enemy.troop_type as int
			)
			# 品质差系数：我方品质越高，对敌方伤害越大（方向互换）
			var quality_diff: float = float(player_troop.quality as int - enemy.quality as int)
			var quality_factor: float = maxf(quality_min, 1.0 + quality_k * quality_diff)
			var damage: float = effective_base * counter * quality_factor * float(battle_rounds)
			enemy_dmg += damage
		result.enemy_damages.append(int(enemy_dmg))

	return result

## 判断在指定倍率下是否能全灭敌方所有部队
## enemy_troops: 敌方部队列表
## enemy_damages: 缩放后的敌方伤害列表
## 返回 true 表示所有敌方部队兵力都会归零
static func would_wipe_enemies(enemy_troops: Array[TroopData], enemy_damages: Array[int]) -> bool:
	for i in range(enemy_troops.size()):
		if i >= enemy_damages.size():
			return false
		if enemy_troops[i].current_hp > enemy_damages[i]:
			return false
	return true
