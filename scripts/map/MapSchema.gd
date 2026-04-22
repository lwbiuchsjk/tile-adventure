class_name MapSchema
## 地图数据结构（Map Schema）
## 作为地图引擎协议核心，定义网格坐标、地形类型与交互插槽信息。
## 地形移动力消耗与插槽放置规则从外部 CSV 配置加载，不再硬编码。

# ─────────────────────────────────────────
# 枚举定义
# ─────────────────────────────────────────

## 地形类型
enum TerrainType {
	MOUNTAIN = 0,  ## 高山，不可通行
	HIGHLAND = 1,  ## 高地
	FLATLAND = 2,  ## 平地
	LOWLAND  = 3,  ## 洼地
}

## 插槽类型（交互实体占位）
enum SlotType {
	NONE     = 0,  ## 无插槽
	RESOURCE = 1,  ## 资源点（宝箱、矿点等）
	FUNCTION = 2,  ## 功能点（学习碑、小屋等）
	SPAWN    = 3,  ## 出生点
}

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

## 各地形移动力消耗（从 terrain_config.csv 加载）
## 格式：{ TerrainType(int) : float }，INF 表示不可通行
var terrain_costs: Dictionary = {}

## 各插槽类型允许放置的地形列表（从 slot_config.csv 加载）
## 格式：{ SlotType(int) : Array[TerrainType(int)] }
var slot_allowed_terrains: Dictionary = {}

## 持久 slot 列表（M2 新增）
## 与 slot_grid 解耦：slot_grid 是格子层的占位标记（NONE/RESOURCE/...），
## persistent_slots 是实体层（村庄/城镇/核心 + 归属 + 等级 + 影响范围）
## 由 PersistentSlotGenerator 在地形生成完成后填充；MVP 一局一次性生成
var persistent_slots: Array[PersistentSlot] = []

# ─────────────────────────────────────────
# 初始化
# ─────────────────────────────────────────

## 初始化空白地图，所有格默认为平地、无插槽
func init(p_width: int, p_height: int) -> void:
	width = p_width
	height = p_height
	terrain_costs = {}
	slot_allowed_terrains = {}
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
## unit_cost_override: 单位专属地形消耗表（可选），覆盖对应地形的消耗值。
## 扩展点：不同兵种/英雄可传入各自的 override 实现地形优势/劣势。
## 未配置的地形默认视为不可通行（返回 INF）。
func get_terrain_cost(x: int, y: int, unit_cost_override: Dictionary = {}) -> float:
	var terrain: TerrainType = get_terrain(x, y)
	if unit_cost_override.has(terrain):
		return float(unit_cost_override[terrain])
	if terrain_costs.has(terrain):
		return float(terrain_costs[terrain])
	return INF

## 判断坐标是否可通行（使用默认移动力规则）
func is_passable(x: int, y: int) -> bool:
	return get_terrain_cost(x, y) < INF

# ─────────────────────────────────────────
# Slot 配置查询
# ─────────────────────────────────────────

## 判断指定插槽类型是否允许放置在指定地形上
func is_slot_allowed_on(slot_type: SlotType, terrain: TerrainType) -> bool:
	var key: int = slot_type as int
	if not slot_allowed_terrains.has(key):
		return false
	var allowed: Array = slot_allowed_terrains[key] as Array
	return allowed.has(terrain as int)
