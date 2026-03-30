class_name WorldMap
extends Node2D
## 大地图主场景控制脚本
## 支持两种初始化模式：
##   PCG  模式 —— 以种子驱动柏林噪声随机生成地图
##   JSON 模式 —— 从静态 JSON 文件加载手工设计关卡
## 渲染使用纯色块占位，不依赖美术资源。

# ─────────────────────────────────────────
# 渲染常量
# ─────────────────────────────────────────

## 每格像素尺寸
const TILE_SIZE: int = 24

## 各地形渲染颜色（纯色块占位）
const TERRAIN_COLORS: Dictionary = {
	MapSchema.TerrainType.MOUNTAIN: Color(0.40, 0.35, 0.30),  ## 灰褐：高山
	MapSchema.TerrainType.HIGHLAND: Color(0.50, 0.65, 0.30),  ## 黄绿：高地
	MapSchema.TerrainType.FLATLAND: Color(0.35, 0.72, 0.40),  ## 绿色：平地
	MapSchema.TerrainType.LOWLAND:  Color(0.30, 0.55, 0.75),  ## 蓝色：洼地
}

## Slot 标记颜色（小方块叠加在地形色上）
const SLOT_COLORS: Dictionary = {
	MapSchema.SlotType.RESOURCE: Color(1.00, 0.85, 0.00),  ## 金色：资源点
	MapSchema.SlotType.FUNCTION: Color(0.80, 0.40, 1.00),  ## 紫色：功能点
	MapSchema.SlotType.SPAWN:    Color(1.00, 0.30, 0.30),  ## 红色：出生点
}

## Slot 标记在格内的边距（像素）
const SLOT_MARGIN: int = 6

# ─────────────────────────────────────────
# 加载模式枚举
# ─────────────────────────────────────────

enum LoadMode {
	PCG,   ## 过程生成模式
	JSON,  ## 静态文件加载模式
}

# ─────────────────────────────────────────
# 导出配置（Inspector 可调）
# ─────────────────────────────────────────

## 加载模式选择
@export var load_mode: LoadMode = LoadMode.PCG

## PCG 模式：随机种子
@export var pcg_seed: int = 12345
## PCG 模式：地图宽度（列数）
@export var pcg_width: int = 32
## PCG 模式：地图高度（行数）
@export var pcg_height: int = 24
## PCG 模式：通达性校验起点
@export var pcg_start: Vector2i = Vector2i(1, 1)
## PCG 模式：通达性校验终点
@export var pcg_end: Vector2i = Vector2i(30, 22)

## JSON 模式：地图文件路径
@export var json_path: String = "res://test/maps/test_map.json"

# ─────────────────────────────────────────
# 私有状态
# ─────────────────────────────────────────

## 当前加载的地图数据
var _schema: MapSchema = null

# ─────────────────────────────────────────
# 生命周期
# ─────────────────────────────────────────

func _ready() -> void:
	_load_map()
	queue_redraw()

# ─────────────────────────────────────────
# 地图加载
# ─────────────────────────────────────────

## 根据 load_mode 调用对应加载逻辑
func _load_map() -> void:
	match load_mode:
		LoadMode.PCG:
			_load_pcg()
		LoadMode.JSON:
			_load_json()

## PCG 模式：构建配置后调用生成器
func _load_pcg() -> void:
	var config: MapGenerator.GenerateConfig = MapGenerator.GenerateConfig.new()
	config.width = pcg_width
	config.height = pcg_height
	config.seed = pcg_seed
	config.start = pcg_start
	config.end = pcg_end

	_schema = MapGenerator.generate(config)
	if _schema == null:
		push_error("WorldMap: PCG 地图生成失败")

## JSON 模式：从文件加载地图
func _load_json() -> void:
	_schema = MapLoader.load_from_file(json_path)
	if _schema == null:
		push_error("WorldMap: JSON 地图加载失败，路径：" + json_path)

# ─────────────────────────────────────────
# 渲染
# ─────────────────────────────────────────

## 使用 _draw 逐格绘制纯色块，不依赖 TileSet 资源
func _draw() -> void:
	if _schema == null:
		return

	for y in range(_schema.height):
		for x in range(_schema.width):
			_draw_tile(x, y)

## 绘制单格地形色块及 Slot 标记
func _draw_tile(x: int, y: int) -> void:
	var terrain: MapSchema.TerrainType = _schema.get_terrain(x, y)
	var base_color: Color = TERRAIN_COLORS.get(terrain, Color.MAGENTA) as Color

	# 绘制地形底色（留 1px 间隙形成网格线视觉效果）
	var tile_rect: Rect2 = Rect2(
		x * TILE_SIZE,
		y * TILE_SIZE,
		TILE_SIZE - 1,
		TILE_SIZE - 1
	)
	draw_rect(tile_rect, base_color)

	# 若有 Slot，在格中央叠加小色块标记
	var slot: MapSchema.SlotType = _schema.get_slot(x, y)
	if slot != MapSchema.SlotType.NONE:
		var slot_color: Color = SLOT_COLORS.get(slot, Color.WHITE) as Color
		var slot_rect: Rect2 = Rect2(
			x * TILE_SIZE + SLOT_MARGIN,
			y * TILE_SIZE + SLOT_MARGIN,
			TILE_SIZE - SLOT_MARGIN * 2 - 1,
			TILE_SIZE - SLOT_MARGIN * 2 - 1
		)
		draw_rect(slot_rect, slot_color)
