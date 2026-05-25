class_name EnemySpawnParamResource
extends Resource

## 敌方生成参数 Resource（MVP-D D.2 批 2：enemy_spawn_config.csv 迁出，2 字段）
##
## 消费方：WorldMap → EnemyTroopGenerator.init_from_config(spawn_cfg: EnemySpawnParamResource)
## 注：单关卡敌方部队数量的兜底范围；具体 pool 行可在 enemy_troop_pool.csv 各自覆盖 count_min/max

## 单关卡敌方部队数量下限
@export_range(1, 20, 1) var troop_count_min: int = 1
## 单关卡敌方部队数量上限
@export_range(1, 20, 1) var troop_count_max: int = 3
