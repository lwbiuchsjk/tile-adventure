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

## 兵力系数分段配置（从 hp_ratio_config.csv 加载）
## 每条：{hp_ratio_min: float, hp_ratio_max: float, exponent: float}
static var _hp_ratio_segments: Array[Dictionary] = []

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

## 从 hp_ratio_config.csv 行数据加载兵力系数分段表
## rows: ConfigLoader.load_csv() 返回的 Array[Dictionary]
static func load_hp_ratio_config(rows: Array) -> void:
	_hp_ratio_segments = []
	for entry in rows:
		var row: Dictionary = entry as Dictionary
		var seg: Dictionary = {
			"min": float(row.get("hp_ratio_min", "0.0")),
			"max": float(row.get("hp_ratio_max", "1.0")),
			"exponent": float(row.get("exponent", "1.0")),
		}
		_hp_ratio_segments.append(seg)

## 根据兵力百分比查表计算兵力系数
## hp_ratio: 当前兵力 / 最大兵力（0.0~1.0）
## 返回兵力系数（0.0~1.0），满血时返回 1.0
static func get_hp_ratio_factor(hp_ratio: float) -> float:
	# 满血直接返回 1.0，避免浮点精度问题
	if hp_ratio >= 1.0:
		return 1.0
	if hp_ratio <= 0.0:
		return 0.0
	# 遍历分段配置，找到 hp_ratio 所在区间
	for seg in _hp_ratio_segments:
		var seg_min: float = float(seg["min"])
		var seg_max: float = float(seg["max"])
		var exponent: float = float(seg["exponent"])
		if hp_ratio >= seg_min and hp_ratio < seg_max:
			return pow(hp_ratio, exponent)
	# 未命中任何区间，使用线性衰减作为兜底
	return hp_ratio

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

	# 读取配置参数
	var base_damage: float = float(config.get("base_damage", "50"))
	var quality_k: float = float(config.get("quality_k", "0.2"))
	var quality_min: float = float(config.get("quality_min_factor", "0.5"))
	var max_rounds: int = int(config.get("default_battle_rounds", "3"))

	# 计算有效基础伤害（含难度修正）
	var effective_base: float = get_effective_base_damage(base_damage, difficulty, damage_increment)

	# 初始化累计伤害数组
	var player_count: int = player_troops.size()
	var enemy_count: int = enemy_troops.size()
	var player_total_dmg: Array[float] = []
	var enemy_total_dmg: Array[float] = []
	for i in range(player_count):
		player_total_dmg.append(0.0)
	for i in range(enemy_count):
		enemy_total_dmg.append(0.0)

	# 模拟用临时兵力（不修改原始数据）
	var player_hp: Array[int] = []
	var enemy_hp: Array[int] = []
	for t in player_troops:
		player_hp.append(t.current_hp)
	for t in enemy_troops:
		enemy_hp.append(t.current_hp)

	# ── 逐回合模拟 ──
	for _round in range(max_rounds):
		# 判断存活部队（兵力 > 0）
		var any_player_alive: bool = false
		var any_enemy_alive: bool = false
		for hp in player_hp:
			if hp > 0:
				any_player_alive = true
				break
		for hp in enemy_hp:
			if hp > 0:
				any_enemy_alive = true
				break
		# 任一方全灭则结束模拟
		if not any_player_alive or not any_enemy_alive:
			break

		# 本回合伤害（先全部算完再扣血，同时结算）
		var round_player_dmg: Array[float] = []
		var round_enemy_dmg: Array[float] = []
		for i in range(player_count):
			round_player_dmg.append(0.0)
		for i in range(enemy_count):
			round_enemy_dmg.append(0.0)

		# 敌方 → 我方伤害（仅存活部队参与，含兵力系数）
		for pi in range(player_count):
			if player_hp[pi] <= 0:
				continue
			for ei in range(enemy_count):
				if enemy_hp[ei] <= 0:
					continue
				var counter: float = get_counter_factor(
					enemy_troops[ei].troop_type as int, player_troops[pi].troop_type as int
				)
				var quality_diff: float = float(enemy_troops[ei].quality as int - player_troops[pi].quality as int)
				var quality_factor: float = maxf(quality_min, 1.0 + quality_k * quality_diff)
				# 兵力系数：攻击方（敌方）当前兵力比例影响输出
				var enemy_hp_ratio: float = float(enemy_hp[ei]) / maxf(float(enemy_troops[ei].max_hp), 1.0)
				var enemy_str_factor: float = get_hp_ratio_factor(enemy_hp_ratio)
				round_player_dmg[pi] += effective_base * counter * quality_factor * enemy_str_factor

		# 我方 → 敌方伤害（仅存活部队参与，含兵力系数）
		for ei in range(enemy_count):
			if enemy_hp[ei] <= 0:
				continue
			for pi in range(player_count):
				if player_hp[pi] <= 0:
					continue
				var counter: float = get_counter_factor(
					player_troops[pi].troop_type as int, enemy_troops[ei].troop_type as int
				)
				var quality_diff: float = float(player_troops[pi].quality as int - enemy_troops[ei].quality as int)
				var quality_factor: float = maxf(quality_min, 1.0 + quality_k * quality_diff)
				# 兵力系数：攻击方（我方）当前兵力比例影响输出
				var player_hp_ratio: float = float(player_hp[pi]) / maxf(float(player_troops[pi].max_hp), 1.0)
				var player_str_factor: float = get_hp_ratio_factor(player_hp_ratio)
				round_enemy_dmg[ei] += effective_base * counter * quality_factor * player_str_factor

		# 同时扣血并累计伤害
		for pi in range(player_count):
			var dmg: int = int(round_player_dmg[pi])
			player_total_dmg[pi] += dmg
			player_hp[pi] = maxi(0, player_hp[pi] - dmg)
		for ei in range(enemy_count):
			var dmg: int = int(round_enemy_dmg[ei])
			enemy_total_dmg[ei] += dmg
			enemy_hp[ei] = maxi(0, enemy_hp[ei] - dmg)

	# 汇总结果
	result.damages = []
	result.enemy_damages = []
	var grand_total: int = 0
	for i in range(player_count):
		var d: int = int(player_total_dmg[i])
		result.damages.append(d)
		grand_total += d
	for i in range(enemy_count):
		result.enemy_damages.append(int(enemy_total_dmg[i]))
	result.damage_taken = grand_total

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


## 单次攻击伤害计算（E 战斗就地展开 MVP §2.5）
##
## 用于 BattleSession 战斗内单次攻击：一个 attacker 攻击一个 target，
## 应用克制 / 品质 / 兵力 / 地形高度差四个修正后返回伤害值。
##
## 参数：
##   attacker_troop / target_troop —— 战斗双方的 TroopData（hp / 兵种 / 品质）
##   altitude_diff   —— attacker 地形高度 - target 地形高度（设计 §2.5）
##   altitude_step   —— battle_config.terrain_altitude_step（默认 0.10）
##   config          —— battle_config（base_damage / quality_k / quality_min_factor）
##   difficulty      —— 关卡难度值（轮次索引），默认 0
##   damage_increment—— 每轮难度增加的伤害值，默认 0
##
## 返回伤害（int）；不修改任何原始数据。地形修正最大约 ±30%（高度差 ±3 × 0.10）。
## 与 resolve() 区别：resolve 是"群战 N 回合一次性结算"，本函数是"单单位单次攻击"
static func calculate_single_attack(
	attacker_troop: TroopData,
	target_troop: TroopData,
	altitude_diff: int,
	altitude_step: float,
	config: Dictionary,
	difficulty: int = 0,
	damage_increment: float = 0.0,
	attacker_faction: int = -1
) -> int:
	var base_damage: float = float(config.get("base_damage", "50"))
	var quality_k: float = float(config.get("quality_k", "0.2"))
	var quality_min: float = float(config.get("quality_min_factor", "0.5"))
	var effective_base: float = get_effective_base_damage(base_damage, difficulty, damage_increment)
	# 克制
	var counter: float = get_counter_factor(
		attacker_troop.troop_type as int, target_troop.troop_type as int
	)
	# 品质修正：攻击方品质 - 防御方品质 → 倍率 = max(quality_min, 1 + quality_k * diff)
	var quality_diff: float = float(attacker_troop.quality as int - target_troop.quality as int)
	var quality_factor: float = maxf(quality_min, 1.0 + quality_k * quality_diff)
	# 兵力系数：攻击方当前兵力比例影响输出
	var attacker_hp_ratio: float = float(attacker_troop.current_hp) / maxf(float(attacker_troop.max_hp), 1.0)
	var hp_factor: float = get_hp_ratio_factor(attacker_hp_ratio)
	# 地形高度修正：max(0, 1 + altitude_diff * step)；钳到 ≥ 0 防极端 step 下负伤害
	var altitude_factor: float = maxf(0.0, 1.0 + float(altitude_diff) * altitude_step)
	# 阵营双向缩放：按攻击方阵营套用对应乘子（默认 1.0 不影响平衡，可在 csv 调参）
	# 设计意图：让"我方对敌方 / 敌方对我方"两个独立倍率可在战斗外做平衡调试，
	# 不污染基础公式 effective_base × counter × quality × hp × altitude 的可解释性
	# attacker_faction == -1（默认）= 不应用阵营乘子，兼容旧调用
	var faction_factor: float = 1.0
	if attacker_faction == Faction.PLAYER:
		faction_factor = float(config.get("battle_player_dmg_factor", "1.0"))
	elif attacker_faction == Faction.ENEMY_1:
		faction_factor = float(config.get("battle_enemy_dmg_factor", "1.0"))
	var final_damage: float = effective_base * counter * quality_factor * hp_factor * altitude_factor * faction_factor
	return int(final_damage)
