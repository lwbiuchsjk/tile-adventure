class_name SupplyParamResource
extends Resource
## @tunable: 部队经济

## 补给参数 Resource（MVP-D D.2 批 3：supply_config.csv 迁出，2 字段）
## 消费方：WorldMap 内部 _supply / _camp_restore（补给初值 + 扎营恢复量）
## 注：设计文档记 1 字段，实装盘点为 2 字段（camp_restore 同源）

## 初始补给
@export_range(0, 99, 1) var initial_supply: int = 3
## 扎营恢复补给量
@export_range(0, 99, 1) var camp_restore: int = 2
