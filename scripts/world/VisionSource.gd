class_name VisionSource
extends RefCounted
## 视野发出者数据类（L1.1 §2.5）
##
## 设计原文：
##   tile-advanture-design/无限地图实装/L1.1_视野循环与chunk底座_MVP.md §2.5
##
## 职责：
##   - 承载"一个视野源"的位置 / 半径 / 阵营 / 持有者
##   - 由 VisionSystem 注册/查询，多源覆盖按 Array[VisionSource] 求并集
##
## L1.1 仅实例化 1 个（玩家队伍）；架构预留多源以待 L1.2 扩展（据点 + 占领的城镇/村庄）
##
## 形态选择：RefCounted 而非 Resource —— 视野源是运行时短生命周期对象（队伍移动即 position 变），
## 不需要 .tres 落盘；用 RefCounted 避免编辑器侧 inspector 误触。


## 视野中心格坐标（世界格，跨 chunk）
var position: Vector2i

## 视野半径（格，欧氏圆形覆盖）
var radius: int

## 阵营（L1.1 全部 PLAYER=1；L1.2+ 多阵营准备）
var faction: int = 0

## 持有者节点（视野源消亡时由 owner 移除）；L1.1 暂不强制持有
var owner_node: Node = null


func _init(p_position: Vector2i = Vector2i.ZERO, p_radius: int = 5, p_faction: int = 0, p_owner: Node = null) -> void:
	position = p_position
	radius = p_radius
	faction = p_faction
	owner_node = p_owner


## 返回该源覆盖的格坐标集合（欧氏圆形 + 整数判定）
## 圆形而非方形：与夜晚视野 shader 的圆形衰减视觉一致
func get_covered_tiles() -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	var r2: int = radius * radius
	for dx in range(-radius, radius + 1):
		for dy in range(-radius, radius + 1):
			if dx * dx + dy * dy <= r2:
				tiles.append(Vector2i(position.x + dx, position.y + dy))
	return tiles
