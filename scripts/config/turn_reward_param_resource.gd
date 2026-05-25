class_name TurnRewardParamResource
extends Resource
## @tunable: 部队经济

## 回合奖励参数 Resource（MVP-D D.2 批 3：turn_reward_config.csv 迁出，1 字段）
## 消费方：WorldMap 内部 _turn_reward_count（每回合奖励抽取数量）

## 每回合奖励数量
@export_range(0, 20, 1) var reward_count: int = 1
