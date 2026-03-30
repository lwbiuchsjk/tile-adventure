class_name WorldMap
extends Node2D
## 大地图主场景控制脚本
## 从 CSV 配置文件读取所有参数，支持两种初始化模式：
##   random_generate = true  → PCG 随机生成（支持自动/固定种子）
##   random_generate = false → 从 JSON 文件加载静态关卡
## 集成单位移动系统：可达高亮、点击寻路移动、回合管理。

# ─────────────────────────────────────────
# 配置文件路径
# ─────────────────────────────────────────

const CONFIG_MAP: String = "res://assets/config/map_config.csv"
const CONFIG_TERRAIN: String = "res://assets/config/terrain_config.csv"
const CONFIG_SLOT: String = "res://assets/config/slot_config.csv"
const CONFIG_PCG: String = "res://assets/config/pcg_config.csv"
const CONFIG_UNIT: String = "res://assets/config/unit_config.csv"

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

## 可达范围高亮色（半透明白色叠加）
const REACHABLE_COLOR: Color = Color(1.0, 1.0, 1.0, 0.25)

## 单位标记颜色（亮白色，醒目区分地形）
const UNIT_COLOR: Color = Color(1.0, 1.0, 1.0)

## 单位标记边距（像素）
const UNIT_MARGIN: int = 4

## 终点标记颜色（亮红色边框）
const END_MARKER_COLOR: Color = Color(1.0, 0.15, 0.15)

## 终点边框宽度（像素）
const END_BORDER_WIDTH: float = 2.0

## 流程结束提示颜色
const FINISH_TEXT_COLOR: Color = Color(1.0, 0.9, 0.1)

# ─────────────────────────────────────────
# 私有状态
# ─────────────────────────────────────────

## 当前加载的地图数据
var _schema: MapSchema = null

## 单位实例
var _unit: UnitData = null

## 回合管理器
var _turn_manager: TurnManager = null

## 当前可达格集合 {Vector2i: float(消耗)}
var _reachable_tiles: Dictionary = {}

## 起点坐标（从 map_config 读取）
var _start_pos: Vector2i = Vector2i.ZERO

## 终点坐标（从 map_config 读取）
var _end_pos: Vector2i = Vector2i.ZERO

## 流程是否已结束（单位抵达终点）
var _game_finished: bool = false

# ─────────────────────────────────────────
# 生命周期
# ─────────────────────────────────────────

func _ready() -> void:
	# 加载所有配置
	var map_cfg: Dictionary = ConfigLoader.load_csv_kv(CONFIG_MAP)
	var terrain_rows: Array = ConfigLoader.load_csv(CONFIG_TERRAIN)
	var slot_rows: Array = ConfigLoader.load_csv(CONFIG_SLOT)
	var unit_cfg: Dictionary = ConfigLoader.load_csv_kv(CONFIG_UNIT)

	# 构建地形消耗表和 Slot 允许表
	var terrain_costs: Dictionary = _build_terrain_costs(terrain_rows)
	var slot_allowed: Dictionary = _build_slot_allowed(slot_rows)

	# 读取起终点坐标
	_start_pos = Vector2i(
		int(map_cfg.get("start_x", "1")),
		int(map_cfg.get("start_y", "1"))
	)
	_end_pos = Vector2i(
		int(map_cfg.get("end_x", "30")),
		int(map_cfg.get("end_y", "22"))
	)

	# 根据配置选择加载模式
	var is_random: bool = map_cfg.get("random_generate", "true") == "true"
	if is_random:
		_load_pcg(map_cfg, terrain_costs)
	else:
		_load_json(map_cfg)

	# 将配置注入到 schema
	if _schema != null:
		_schema.terrain_costs = terrain_costs
		_schema.slot_allowed_terrains = slot_allowed
	else:
		push_error("WorldMap: 地图加载失败，无法渲染")
		return

	# 初始化单位
	var default_movement: int = int(unit_cfg.get("default_movement", "6"))
	_unit = UnitData.new()
	_unit.position = _start_pos
	_unit.max_movement = default_movement
	_unit.current_movement = default_movement

	# 初始化回合管理器
	_turn_manager = TurnManager.new()
	_turn_manager.register_unit(_unit)
	_turn_manager.turn_ended.connect(_on_turn_ended)

	# 计算初始可达范围
	_refresh_reachable()

# ─────────────────────────────────────────
# 输入处理
# ─────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if _game_finished:
		return

	# 鼠标左键点击：移动单位
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_handle_click(mb.position)

	# 空格键：结束回合
	if event is InputEventKey:
		var key: InputEventKey = event as InputEventKey
		if key.pressed and not key.echo and key.keycode == KEY_SPACE:
			_turn_manager.end_turn()

# ─────────────────────────────────────────
# 交互逻辑
# ─────────────────────────────────────────

## 处理点击事件：转换坐标 → 寻路 → 移动 → 刷新
func _handle_click(screen_pos: Vector2) -> void:
	if _schema == null or _unit == null:
		return

	# 屏幕坐标转网格坐标
	var grid_x: int = int(screen_pos.x) / TILE_SIZE
	var grid_y: int = int(screen_pos.y) / TILE_SIZE
	var target: Vector2i = Vector2i(grid_x, grid_y)

	# 点击当前位置或不可达格无响应
	if target == _unit.position:
		return
	if not _reachable_tiles.has(target):
		return

	# 寻路
	var path_result: Pathfinder.PathResult = Pathfinder.find_path(_schema, _unit.position, target)
	if path_result.path.size() < 2:
		return

	# 执行移动
	MovementSystem.execute_move(_unit, path_result.path, _schema)

	# 检查是否抵达终点
	if _unit.position == _end_pos:
		_game_finished = true
		_reachable_tiles = {}
		queue_redraw()
		return

	_refresh_reachable()

## 刷新可达范围并触发重绘
func _refresh_reachable() -> void:
	if _unit != null and _schema != null and not _game_finished:
		_reachable_tiles = MovementSystem.get_reachable_tiles(
			_schema, _unit.position, float(_unit.current_movement)
		)
	else:
		_reachable_tiles = {}
	queue_redraw()

## 回合结束回调：刷新可达范围
func _on_turn_ended(_turn_number: int) -> void:
	_refresh_reachable()

# ─────────────────────────────────────────
# 配置解析
# ─────────────────────────────────────────

## 从 terrain_config 行数据构建地形消耗字典
## passable=false 的地形强制使用 INF
func _build_terrain_costs(rows: Array) -> Dictionary:
	var costs: Dictionary = {}
	for entry in rows:
		var row: Dictionary = entry as Dictionary
		var id: int = int(row.get("id", "0"))
		var passable: bool = row.get("passable", "true") == "true"
		if passable:
			costs[id] = float(row.get("cost", "1"))
		else:
			costs[id] = INF
	return costs

## 从 slot_config 行数据构建 Slot 允许地形字典
## allowed_terrain_ids 字段以 | 分隔多个地形 ID
func _build_slot_allowed(rows: Array) -> Dictionary:
	var allowed: Dictionary = {}
	for entry in rows:
		var row: Dictionary = entry as Dictionary
		var id: int = int(row.get("id", "0"))
		var terrain_str: String = row.get("allowed_terrain_ids", "") as String
		var terrains: Array = []
		if not terrain_str.is_empty():
			var parts: PackedStringArray = terrain_str.split("|")
			for p in parts:
				var stripped: String = p.strip_edges()
				if not stripped.is_empty():
					terrains.append(int(stripped))
		allowed[id] = terrains
	return allowed

# ─────────────────────────────────────────
# 地图加载
# ─────────────────────────────────────────

## PCG 模式：从 map_config + pcg_config 构建生成参数
func _load_pcg(map_cfg: Dictionary, terrain_costs: Dictionary) -> void:
	var pcg_cfg: Dictionary = ConfigLoader.load_csv_kv(CONFIG_PCG)

	var config: MapGenerator.GenerateConfig = MapGenerator.GenerateConfig.new()
	config.width = int(map_cfg.get("map_width", "32"))
	config.height = int(map_cfg.get("map_height", "24"))

	# 种子处理：-1 表示每次自动随机，其他值固定
	var seed_value: int = int(map_cfg.get("random_seed", "-1"))
	if seed_value == -1:
		config.seed = randi()
	else:
		config.seed = seed_value

	# 通达性校验起终点
	config.start = _start_pos
	config.end = _end_pos

	# PCG 生成参数
	config.threshold_mountain = float(pcg_cfg.get("threshold_mountain", "0.45"))
	config.threshold_highland = float(pcg_cfg.get("threshold_highland", "0.15"))
	config.threshold_flatland = float(pcg_cfg.get("threshold_flatland", "-0.25"))
	config.noise_frequency = float(pcg_cfg.get("noise_frequency", "0.08"))
	config.max_retries = int(pcg_cfg.get("max_retries", "10"))

	# 注入地形消耗配置（BFS 通达性校验需要）
	config.terrain_costs = terrain_costs

	_schema = MapGenerator.generate(config)
	if _schema == null:
		push_error("WorldMap: PCG 地图生成失败")

## JSON 模式：从配置中读取文件路径后加载
func _load_json(map_cfg: Dictionary) -> void:
	var path: String = map_cfg.get("json_path", "") as String
	if path.is_empty():
		push_error("WorldMap: map_config 中未配置 json_path")
		return
	_schema = MapLoader.load_from_file(path)
	if _schema == null:
		push_error("WorldMap: JSON 地图加载失败，路径：" + path)

# ─────────────────────────────────────────
# 渲染
# ─────────────────────────────────────────

## 主绘制入口：分层绘制地形 → 可达高亮 → 终点标记 → 单位标记 → 完成提示
func _draw() -> void:
	if _schema == null:
		return

	# 第一层：地形底色 + Slot 标记
	for y in range(_schema.height):
		for x in range(_schema.width):
			_draw_tile(x, y)

	# 第二层：可达范围高亮
	for tile_pos in _reachable_tiles:
		var pos: Vector2i = tile_pos as Vector2i
		if _unit != null and pos == _unit.position:
			continue  ## 当前位置不叠加高亮
		var rect: Rect2 = Rect2(
			pos.x * TILE_SIZE,
			pos.y * TILE_SIZE,
			TILE_SIZE - 1,
			TILE_SIZE - 1
		)
		draw_rect(rect, REACHABLE_COLOR)

	# 第三层：终点标记（红色边框）
	_draw_end_marker()

	# 第四层：单位标记
	if _unit != null:
		_draw_unit_marker()

	# 第五层：流程结束提示
	if _game_finished:
		_draw_finish_text()

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

## 绘制终点标记（红色空心边框）
func _draw_end_marker() -> void:
	var rect: Rect2 = Rect2(
		_end_pos.x * TILE_SIZE,
		_end_pos.y * TILE_SIZE,
		TILE_SIZE - 1,
		TILE_SIZE - 1
	)
	draw_rect(rect, END_MARKER_COLOR, false, END_BORDER_WIDTH)

## 绘制单位标记（白色实心方块）
func _draw_unit_marker() -> void:
	var rect: Rect2 = Rect2(
		_unit.position.x * TILE_SIZE + UNIT_MARGIN,
		_unit.position.y * TILE_SIZE + UNIT_MARGIN,
		TILE_SIZE - UNIT_MARGIN * 2 - 1,
		TILE_SIZE - UNIT_MARGIN * 2 - 1
	)
	draw_rect(rect, UNIT_COLOR)

## 绘制流程结束提示文字
func _draw_finish_text() -> void:
	var font: Font = ThemeDB.fallback_font
	var text: String = "抵达终点！流程结束（回合 %d）" % _turn_manager.current_turn
	# 在地图下方绘制提示
	var text_pos: Vector2 = Vector2(10, _schema.height * TILE_SIZE + 30)
	draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, FINISH_TEXT_COLOR)
