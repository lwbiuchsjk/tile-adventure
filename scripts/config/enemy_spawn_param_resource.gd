class_name EnemySpawnParamResource
extends Resource
## @tunable: 玩家与敌方

## 敌方生成参数 Resource（MVP-D D.2 批 2：enemy_spawn_config.csv 迁出，2 字段）
##
## 消费方：WorldMap → EnemyTroopGenerator.init_from_config(spawn_cfg: EnemySpawnParamResource)
## 注：单关卡敌方部队数量的兜底范围；具体 pool 行可在 enemy_troop_pool.csv 各自覆盖 count_min/max

## 单关卡敌方部队数量下限
@export_range(1, 20, 1) var troop_count_min: int = 1
## 单关卡敌方部队数量上限
@export_range(1, 20, 1) var troop_count_max: int = 3

## L1.3c 阶段 C：增援间隔基数（敌方回合数）——P=0 时每 N 个敌方回合从暗影环带刷 1 批增援
## L1.3d-1 阶段 B：升级为「随暗影压力递减」的基数——实际 interval = maxi(min, 基数 - P)，P 越高刷越频
@export_range(1, 30, 1) var enemy_reinforcement_interval: int = 5
## L1.3d-1 阶段 B：增援间隔下限——P 再高 interval 也不低于此值（防高压期每回合刷怪压垮玩家）
@export_range(1, 20, 1) var enemy_reinforcement_interval_min: int = 2
## L1.3c 阶段 C：敌方 pack 全局上限——场上敌方 pack 数 ≥ 此值时常规增援停刷
## 结构性参数（参与刷怪节奏，重启生效）。注：climax boss 不受此上限约束（sudden-death 必现强敌）
@export_range(1, 50, 1) var enemy_pack_global_cap: int = 12
## L1.3c 阶段 C：暗影环带增援内半径（曼哈顿距，玩家视野半径外起算，保证敌人"从暗影中来"）
@export_range(1, 30, 1) var enemy_spawn_ring_min: int = 6
## L1.3c 阶段 C：暗影环带增援外半径（曼哈顿距上界，增援采样范围的外圈）
@export_range(2, 40, 1) var enemy_spawn_ring_max: int = 10
