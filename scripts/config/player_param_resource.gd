class_name PlayerParamResource
extends Resource
## @tunable: 玩家与敌方

## 玩家参数 Resource（MVP-D D.2 批 2：player_config.csv 迁出）
##
## scope 调整：原 CSV 含 initial_character_count 但全项目无读取点（死字段），迁移时清理；
## 本期仅保留活字段 initial_troop_quality。保留作 hero_pool 行未填时的默认品质兜底。
##
## 消费方：WorldMap → PlayerLifecycle.setup(player_cfg: PlayerParamResource)

## 初始部队默认品质（hero_pool 行未填或解析失败时回退）
@export_range(0, 5, 1) var initial_troop_quality: int = 0
