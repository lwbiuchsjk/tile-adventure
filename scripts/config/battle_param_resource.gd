class_name BattleParamResource
extends Resource

## 战斗数值参数 Resource（MVP-D D.2 批 1：battle_config.csv 迁出）
##
## 迁移自 assets/config/battle_config.csv（KV 格式，16 行）。新增 enemy_target_switch_range
## 一字段——原 CSV 未定义但 WorldMap.gd 代码以默认 10 读取，迁移时显式补入 schema。
##
## 消费链（全链类型化，MVP-D D.2 拍板「全链类型化」）：
##   WorldMap (const BATTLE_PARAM_CFG = preload)
##     → BattleSession.start(bcfg: BattleParamResource)
##       → BattleMath.calc_attack_damage(battle_config: BattleParamResource)
##         → BattleResolver.calculate_single_attack(config: BattleParamResource)
## 字段类型化后调用方直读（cfg.base_damage），消除原 CSV 字符串的 int()/float()/get-default。
##
## 注：字段命名保持与原 CSV key 一一对应（不去前缀），便于 grep 对账与下游零认知成本迁移。

# —— 伤害公式参数 ——
@export_group("伤害公式")
## 基础伤害（含难度修正前的基数）
@export_range(0.0, 5000.0, 1.0) var base_damage: float = 500.0
## 品质修正斜率：倍率 = max(quality_min_factor, 1 + quality_k * 品质差)
@export_range(0.0, 2.0, 0.01) var quality_k: float = 0.2
## 品质修正下限倍率
@export_range(0.0, 2.0, 0.01) var quality_min_factor: float = 0.5
## 我方对敌方的阵营伤害乘子（平衡旋钮，默认 1.0 不影响公式）
@export_range(0.0, 5.0, 0.01) var battle_player_dmg_factor: float = 1.0
## 敌方对我方的阵营伤害乘子
@export_range(0.0, 5.0, 0.01) var battle_enemy_dmg_factor: float = 0.3
## 地形高度差伤害修正系数（每级高度差的伤害增减比例）
@export_range(0.0, 1.0, 0.01) var terrain_altitude_step: float = 0.10

# —— 战斗轮次与范围 ——
@export_group("战斗轮次与范围")
## 群战一次性结算的默认回合数
@export_range(1, 20, 1) var default_battle_rounds: int = 3
## 战斗就地展开的触发距离
@export_range(1, 30, 1) var battle_trigger_range: int = 3
## 战场半径（不小于触发距离）
@export_range(1, 30, 1) var battle_arena_range: int = 6
## 强制战斗触发距离（A 基线收束）
@export_range(1, 30, 1) var forced_battle_range: int = 3

# —— 敌方移动 ——
@export_group("敌方移动")
## 是否启用敌方移动 AI
@export var enemy_movement_enabled: bool = true
## 敌方单回合移动点数
@export_range(0, 30, 1) var enemy_movement_points: int = 6
## 敌方重新选定目标的距离阈值（< 1 时 WorldMap 兜底回退到 10）
@export_range(1, 50, 1) var enemy_target_switch_range: int = 10

# —— 补给消耗 ——
@export_group("补给消耗")
## 主动发起战斗的补给消耗
@export_range(0, 20, 1) var active_battle_supply_cost: int = 0
## 被动卷入战斗的补给消耗
@export_range(0, 20, 1) var passive_battle_supply_cost: int = 0

# —— 援军触发（持久 slot L1.2）——
@export_group("援军触发")
## 援军触发距离（下限 0：range=0 表示仅战场覆盖 slot 格才触发）
@export_range(0, 20, 1) var garrison_trigger_range: int = 2
## 援军总量上限
@export_range(0, 999, 1) var garrison_total_cap: int = 99
