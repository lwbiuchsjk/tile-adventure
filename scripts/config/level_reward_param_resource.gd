class_name LevelRewardParamResource
extends Resource

## 关卡奖励参数 Resource（MVP-D D.2 批 3：level_reward_config.csv 迁出，2 字段）
## 消费方：WorldMap 内部 _level_reward_count_min / _max（关卡通关奖励抽取数量范围）

## 关卡奖励数量下限
@export_range(0, 20, 1) var reward_count_min: int = 1
## 关卡奖励数量上限
@export_range(0, 20, 1) var reward_count_max: int = 2
