class_name MapSchema
## 地图数据结构（Map Schema）
## 作为地图引擎协议核心，定义网格坐标、地形类型与交互插槽信息。
## PCG 生成器与 JSON 加载器均向此结构输出，表现层从此结构读取。

# ─────────────────────────────────────────
# 枚举定义
# ─────────────────────────────────────────

## 地形类型
enum TerrainType {
	MOUNTAIN = 0,  ## 高山，不可通行（移动力消耗 INF）
	HIGHLAND = 1,  ## 高地，移动力消耗 2
	FLATLAND = 2,  ## 平地，移动力消耗 1
	LOWLAND  = 3,  ## 洼地，移动力消耗 2
}

## 插槽类型（交互实体占位）
enum SlotType {
	NONE     = 0,  ## 无插槽
	RESOURCE = 1,  ## 资源点（宝箱、矿点等）
	FUNCTION = 2,  ## 功能点（学习碑、小屋等）
	SPAWN    = 3,  ## 出生点
}

# ─────────────────────────────────────────
# 常量：默认配置
# ─────────────────────────────────────────

## 各地形默认移动力消耗。float，INF 表示不可通行。
## 扩展点：单位可传入 unit_cost_override 覆盖对应地形的消耗值。
const DEFAULT_TERRAIN_COST: Dictionary = {
	TerrainType.MOUNTAIN: INF,
	TerrainType.HIGHLAND: 2.0,
	TerrainType.FLATLAND: 1.0,
	TerrainType.LOWLAND:  2.0,
}

## Slot 默认允许放置的地形列表（仅平地）
const DEFAULT_SLOT_ALLOWED_TERRAINS: Array = [TerrainType.FLATLAND]

# ─────────────────────────────────────────
# 字段
# ─────────────────────────────────────────

## 地图宽度（列数）
var width: int = 0
## 地图高度（行数）
var height: int = 0

## 地形网格，行优先二维数组：terrain_grid[y][x] -> TerrainType
var terrain_grid: Array = []
## 插槽网格，行优先二维数组：slot_grid[y][x] -> SlotType
var slot_grid: Array = []

## 允许放置 Slot 的地形列表，支持外部配置覆盖
var slot_allowed_terrains: Array = []

# ─────────────────────────────────────────
# 初始化
# ─────────────────────────────────────────

## 初始化空白地图，所有格默认为平地、无插槽
func init(p_width: int, p_height: int) -> void:
	width = p_width
	height = p_height
	slot_allowed_terrains = DEFAULT_SLOT_ALLOWED_TERRAINS.duplicate()
	terrain_grid = []
	slot_grid = []
	for y in range(height):
		var terrain_row: Array = []
		var slot_row: Array = []
		for x in range(width):
			terrain_row.append(TerrainType.FLATLAND)
			slot_row.append(SlotType.NONE)
		terrain_grid.append(terrain_row)
		slot_grid.append(slot_row)

# ─────────────────────────────────────────
# 边界检查
# ─────────────────────────────────────────

## 判断坐标是否在地图范围内
func is_in_bounds(x: int, y: int) -> bool:
	return x >= 0 and x < width and y >= 0 and y < height

# ─────────────────────────────────────────
# 地形读写
# ─────────────────────────────────────────

## 获取指定坐标地形类型。越界时返回 MOUNTAIN（视为不可通行的出界处理）。
func get_terrain(x: int, y: int) -> TerrainType:
	if not is_in_bounds(x, y):
		return TerrainType.MOUNTAIN
	return terrain_grid[y][x] as TerrainType

## 设置指定坐标地形类型，越界时静默忽略
func set_terrain(x: int, y: int, terrain: TerrainType) -> void:
	if not is_in_bounds(x, y):
		return
	terrain_grid[y][x] = terrain

# ─────────────────────────────────────────
# 插槽读写
# ─────────────────────────────────────────

## 获取指定坐标插槽类型，越界返回 NONE
func get_slot(x: int, y: int) -> SlotType:
	if not is_in_bounds(x, y):
		return SlotType.NONE
	return slot_grid[y][x] as SlotType

## 设置指定坐标插槽类型，越界时静默忽略
func set_slot(x: int, y: int, slot: SlotType) -> void:
	if not is_in_bounds(x, y):
		return
	slot_grid[y][x] = slot

# ─────────────────────────────────────────
# 移动力查询
# ─────────────────────────────────────────

## 获取指定坐标的移动力消耗。
## unit_cost_override: 单位专属地形消耗表（可选），覆盖对应地形的默认消耗值。
## 扩展点：不同兵种/英雄可传入各自的 override 实现地形优势/劣势。
func get_terrain_cost(x: int, y: int, unit_cost_override: Dictionary = {}) -> float:
	var terrain: TerrainType = get_terrain(x, y)
	if unit_cost_override.has(terrain):
		return float(unit_cost_override[terrain])
	return float(DEFAULT_TERRAIN_COST[terrain])

## 判断坐标是否可通行（使用默认移动力规则）
func is_passable(x: int, y: int) -> bool:
	return get_terrain_cost(x, y) < INF

# ─────────────────────────────────────────
# Slot 配置查询
# ─────────────────────────────────────────

## 判断指定地形是否允许放置 Slot
func is_slot_allowed_on(terrain: TerrainType) -> bool:
	return slot_allowed_terrains.has(terrain)
