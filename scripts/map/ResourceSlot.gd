class_name ResourceSlot
extends RefCounted
## 资源点数据
## 资源点分布在地图上，为玩家提供补给和道具。
## 分为一次性（采集即消失）和持久（有效范围内扎营时自动产出）两种。

## 资源类型
enum ResourceType {
	SUPPLY     = 0,  ## 补给
	HP_RESTORE = 1,  ## 兵力恢复道具
	EXP        = 2,  ## 部队经验道具
}

## 资源类型名称映射（用于 UI 显示完整名称）
const RESOURCE_TYPE_NAMES: Dictionary = {
	ResourceType.SUPPLY:     "补给",
	ResourceType.HP_RESTORE: "恢复药",
	ResourceType.EXP:        "经验书",
}

## 地图短标签映射（用于地图格内文字标注，字数精简）
const RESOURCE_MAP_LABELS: Dictionary = {
	ResourceType.SUPPLY:     "补给",
	ResourceType.HP_RESTORE: "兵力",
	ResourceType.EXP:        "经验",
}

## 资源点在地图上的格坐标
var position: Vector2i = Vector2i.ZERO

## 资源类型
var resource_type: ResourceType = ResourceType.SUPPLY

## 是否为持久资源点（false=一次性，true=持久）
var is_persistent: bool = false

## 每次产出数量（一次性=采集量，持久=每次扎营产出量）
var output_amount: int = 1

## 持久资源点的有效范围（曼哈顿距离，仅持久资源点使用）
var effective_range: int = 2

## 一次性资源点是否已被采集
var is_collected: bool = false

## 获取资源类型显示名称（完整名，用于 UI 面板）
func get_type_name() -> String:
	return RESOURCE_TYPE_NAMES.get(resource_type, "未知") as String


## 获取地图格内短标签（精简字数，用于地图渲染文字标注）
## 持久资源点调用方自行追加「★」后缀
func get_map_label() -> String:
	return RESOURCE_MAP_LABELS.get(resource_type, "?") as String

## 获取完整显示名称（如"补给×2"或"恢复药×1"）
func get_display_name() -> String:
	if output_amount > 1:
		return "%s×%d" % [get_type_name(), output_amount]
	return get_type_name()
