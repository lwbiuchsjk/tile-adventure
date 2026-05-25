class_name DifficultyParamResource
extends Resource

## 难度参数 Resource（MVP-D D.2 批 3：difficulty_config.csv 迁出，1 字段）
## 消费方：WorldMap 内部 _damage_increment（每轮难度递增伤害，传入战斗链）

## 每轮难度递增伤害
@export_range(0.0, 1000.0, 0.1) var damage_increment: float = 10.0
