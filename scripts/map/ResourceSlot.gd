class_name ResourceSlot
extends RefCounted
## 资源点数据（一次性资源点）
## 资源点散布在地图上，部队走到所在格上即可采集，采集后消失。
##
## ⚠ M1 重构（2026-04-22）：
##   原 is_persistent / effective_range 字段已迁移到 PersistentSlot 类，
##   ResourceSlot 回归一次性语义，只保留即时型资源点逻辑。
##   持久型产出 / 影响范围统一由 PersistentSlot + M6 产出结算实装。
##
## 设计原文：
##   tile-advanture-design/占位产出与最小验证设计.md §二 即时 slot 池

## 资源类型
## 双通道分工（升级建造设计 §二）：
##   部队通道（按部队隔离） —— SUPPLY / HP_RESTORE / EXP
##   建造通道（势力全局）   —— STONE
## ResourceSlot 用于即时产出场景，可承载任意通道；
## STONE 入账时累加到势力全局石料池（具体接入由 M6 实装）
enum ResourceType {
	SUPPLY     = 0,  ## 补给（部队通道：移动力 / 物品资源）
	HP_RESTORE = 1,  ## 兵力恢复道具（部队通道）
	EXP        = 2,  ## 部队经验道具（部队通道）
	STONE      = 3,  ## 石料（建造通道：势力全局，独立于部队补给）
}

## 资源类型名称映射（用于 UI 显示完整名称）
const RESOURCE_TYPE_NAMES: Dictionary = {
	ResourceType.SUPPLY:     "补给",
	ResourceType.HP_RESTORE: "恢复药",
	ResourceType.EXP:        "经验书",
	ResourceType.STONE:      "石料",
}

## 地图短标签映射（用于地图格内文字标注，字数精简）
const RESOURCE_MAP_LABELS: Dictionary = {
	ResourceType.SUPPLY:     "补给",
	ResourceType.HP_RESTORE: "兵力",
	ResourceType.EXP:        "经验",
	ResourceType.STONE:      "石料",
}

## 资源点在地图上的格坐标
var position: Vector2i = Vector2i.ZERO

## 资源类型
var resource_type: ResourceType = ResourceType.SUPPLY

## 每次产出数量（采集量）
var output_amount: int = 1

## 是否已被采集（采集后该 slot 应从地图移除）
var is_collected: bool = false

## 获取资源类型显示名称（完整名，用于 UI 面板）
func get_type_name() -> String:
	return RESOURCE_TYPE_NAMES.get(resource_type, "未知") as String


## 获取地图格内短标签（精简字数，用于地图渲染文字标注）
func get_map_label() -> String:
	return RESOURCE_MAP_LABELS.get(resource_type, "?") as String

## 获取完整显示名称（如"补给×2"或"恢复药×1"）
func get_display_name() -> String:
	if output_amount > 1:
		return "%s×%d" % [get_type_name(), output_amount]
	return get_type_name()
