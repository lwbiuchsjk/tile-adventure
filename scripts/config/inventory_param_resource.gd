class_name InventoryParamResource
extends Resource

## 背包参数 Resource（MVP-D D.2 批 3：inventory_config.csv 迁出，1 字段）
## 消费方：WorldMap → Inventory.init_from_config(cfg: InventoryParamResource)

## 背包最大容量
@export_range(1, 999, 1) var max_capacity: int = 20
