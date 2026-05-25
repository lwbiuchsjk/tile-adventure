class_name BuildParamResource
extends Resource

## 建造经济参数 Resource（MVP-D D.2 批 3：build_config.csv 迁出，2 字段）
## 消费方：WorldMap 内部初始化 _stone_by_faction
## 注：与 ReinforcementRoster.build_config() 函数同名无关（一个 class 名，一个函数名）

## 玩家初始建造石
@export_range(0, 999, 1) var player_initial_stone: int = 20
## 敌方初始建造石（M7 真正消耗前只占位）
@export_range(0, 999, 1) var enemy_initial_stone: int = 5
