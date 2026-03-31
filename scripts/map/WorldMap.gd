class_name WorldMap
extends Node2D
## 大地图主场景控制脚本
## 从 CSV 配置文件读取所有参数，支持两种初始化模式：
##   random_generate = true  → PCG 随机生成（支持自动/固定种子）
##   random_generate = false → 从 JSON 文件加载静态关卡
## 集成单位移动系统：可达高亮、点击寻路移动、回合管理。
## Camera2D 平滑跟随单位视觉位置，HUD 通过 CanvasLayer 固定在屏幕上。
## 单位移动沿路径逐格动画，动画期间锁定输入。
## 战斗循环：关卡 Slot 触发确认弹板 → BattleResolver 结算 → 兵力损耗 → 流程判定。

# ─────────────────────────────────────────
# 配置文件路径
# ─────────────────────────────────────────

const CONFIG_MAP: String = "res://assets/config/map_config.csv"
const CONFIG_TERRAIN: String = "res://assets/config/terrain_config.csv"
const CONFIG_SLOT: String = "res://assets/config/slot_config.csv"
const CONFIG_PCG: String = "res://assets/config/pcg_config.csv"
const CONFIG_UNIT: String = "res://assets/config/unit_config.csv"
const CONFIG_BATTLE: String = "res://assets/config/battle_config.csv"

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

## 已挑战关卡变暗系数（与原 Slot 颜色混合）
const CHALLENGED_DIM: float = 0.4

## 单位逐格移动动画耗时（秒/格）
const MOVE_STEP_DURATION: float = 0.1

# ─────────────────────────────────────────
# 节点引用
# ─────────────────────────────────────────

## Camera2D 节点（场景中配置，已开启 position_smoothing）
@onready var _camera: Camera2D = $Camera2D

## HUD 状态栏 Label（CanvasLayer 下，固定在屏幕底部）
@onready var _hud_label: Label = $UILayer/HudLabel

## 流程结束提示 Label（CanvasLayer 下）
@onready var _finish_label: Label = $UILayer/FinishLabel

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

## 流程是否已结束（全部通关或部队被击败）
var _game_finished: bool = false

## 单位视觉位置（像素坐标，Tween 动画驱动）
## 与逻辑位置（UnitData.position）分离，_draw 基于此渲染单位
var _unit_visual_pos: Vector2 = Vector2.ZERO

## 是否正在播放移动动画（期间锁定所有输入）
var _is_moving: bool = false

## 当前移动动画 Tween 引用（用于防止重复创建）
var _move_tween: Tween = null

## 角色数据（包含部队槽位）
var _character: CharacterData = null

## 关卡 Slot 字典 {Vector2i: LevelSlot}
var _level_slots: Dictionary = {}

## 战斗配置（从 battle_config.csv 加载）
var _battle_config: Dictionary = {}

## 战斗确认面板引用
var _battle_panel: PanelContainer = null

## 是否正在等待战斗确认（期间锁定输入）
var _is_battle_pending: bool = false

## 当前待确认的关卡（战斗确认弹板触发时记录）
var _pending_level: LevelSlot = null

# ─────────────────────────────────────────
# 生命周期
# ─────────────────────────────────────────

func _ready() -> void:
	# 加载所有配置
	var map_cfg: Dictionary = ConfigLoader.load_csv_kv(CONFIG_MAP)
	var terrain_rows: Array = ConfigLoader.load_csv(CONFIG_TERRAIN)
	var slot_rows: Array = ConfigLoader.load_csv(CONFIG_SLOT)
	var unit_cfg: Dictionary = ConfigLoader.load_csv_kv(CONFIG_UNIT)
	_battle_config = ConfigLoader.load_csv_kv(CONFIG_BATTLE)

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

	# PCG 模式下随机放置关卡 Slot
	if is_random:
		var slot_max: int = int(map_cfg.get("slot_max_count", "3"))
		var exclude: Array[Vector2i] = [_start_pos, _end_pos]
		MapGenerator.place_level_slots(_schema, slot_max, exclude)

	# 初始化关卡 Slot 数据（遍历 schema 中的 FUNCTION Slot）
	_init_level_slots()

	# 设置 Camera 边界限制（不超出地图像素范围）
	_setup_camera_limits()

	# 初始化单位（移动系统）
	var default_movement: int = int(unit_cfg.get("default_movement", "6"))
	_unit = UnitData.new()
	_unit.position = _start_pos
	_unit.max_movement = default_movement
	_unit.current_movement = default_movement

	# 初始化角色数据（战斗系统）
	_character = CharacterData.new()
	_character.id = 1
	# 自动装配默认部队
	var troop: TroopData = TroopData.new()
	_character.troop = troop

	# 视觉位置初始化到起点像素中心
	_unit_visual_pos = _grid_to_pixel_center(_start_pos)

	# 初始化回合管理器
	_turn_manager = TurnManager.new()
	_turn_manager.register_unit(_unit)
	_turn_manager.turn_ended.connect(_on_turn_ended)

	# Camera 初始位置直接设到单位位置（首帧不需要平滑）
	_camera.position = _unit_visual_pos

	# 创建战斗确认弹板（隐藏状态）
	_create_battle_confirm_ui()

	# 更新 HUD
	_update_hud()

	# 计算初始可达范围
	_refresh_reachable()

# ─────────────────────────────────────────
# 输入处理
# ─────────────────────────────────────────

func _input(event: InputEvent) -> void:
	# 动画播放中、战斗确认中或流程结束时锁定所有输入
	if _game_finished or _is_moving or _is_battle_pending:
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
# 坐标工具
# ─────────────────────────────────────────

## 将格坐标转为像素中心坐标
func _grid_to_pixel_center(grid_pos: Vector2i) -> Vector2:
	return Vector2(
		grid_pos.x * TILE_SIZE + TILE_SIZE / 2,
		grid_pos.y * TILE_SIZE + TILE_SIZE / 2
	)

# ─────────────────────────────────────────
# 镜头控制
# ─────────────────────────────────────────

## 根据地图像素尺寸设置 Camera 边界
func _setup_camera_limits() -> void:
	if _schema == null or _camera == null:
		return
	_camera.limit_left = 0
	_camera.limit_top = 0
	_camera.limit_right = _schema.width * TILE_SIZE
	_camera.limit_bottom = _schema.height * TILE_SIZE

# ─────────────────────────────────────────
# HUD 更新（CanvasLayer 上的 Label 节点）
# ─────────────────────────────────────────

## 刷新 HUD 状态栏文字（包含兵力信息）
func _update_hud() -> void:
	if _hud_label == null or _unit == null or _turn_manager == null:
		return
	# 兵力显示：有部队时显示当前/最大，无部队时显示 0
	var hp_text: String = "兵力 0"
	if _character != null and _character.has_troop():
		hp_text = "兵力 %d/%d" % [_character.troop.current_hp, _character.troop.max_hp]
	_hud_label.text = "回合 %d | 移动力 %d/%d | %s | [空格] 结束回合" % [
		_turn_manager.current_turn,
		_unit.current_movement,
		_unit.max_movement,
		hp_text
	]

## 显示流程胜利提示
func _show_victory_text() -> void:
	if _finish_label == null or _turn_manager == null:
		return
	_finish_label.text = "所有关卡已通关！流程胜利（回合 %d）" % _turn_manager.current_turn

## 显示流程失败提示
func _show_defeat_text() -> void:
	if _finish_label == null or _turn_manager == null:
		return
	_finish_label.text = "部队被击败！流程失败（回合 %d）" % _turn_manager.current_turn

# ─────────────────────────────────────────
# 交互逻辑
# ─────────────────────────────────────────

## 处理点击事件：屏幕坐标 → Camera 逆变换 → 世界坐标 → 格坐标
func _handle_click(screen_pos: Vector2) -> void:
	if _schema == null or _unit == null:
		return

	# 屏幕坐标经 Canvas + 全局变换逆变换，转为世界坐标
	var world_pos: Vector2 = (get_canvas_transform() * get_global_transform()).affine_inverse() * screen_pos
	var grid_x: int = int(world_pos.x) / TILE_SIZE
	var grid_y: int = int(world_pos.y) / TILE_SIZE
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

	# 执行逻辑移动（立即更新逻辑位置和移动力）
	MovementSystem.execute_move(_unit, path_result.path, _schema)

	# 更新 HUD（移动力已扣除）
	_update_hud()

	# 清空可达高亮（动画期间不显示）
	_reachable_tiles = {}
	queue_redraw()

	# 启动视觉移动动画
	_start_move_animation(path_result.path)

## 启动沿路径逐格移动的 Tween 动画
func _start_move_animation(path: Array[Vector2i]) -> void:
	_is_moving = true

	# 终止可能残留的旧 Tween
	if _move_tween != null and _move_tween.is_valid():
		_move_tween.kill()

	_move_tween = create_tween()

	# 从路径第二个点开始（第一个是出发点），逐格插值视觉位置
	for i in range(1, path.size()):
		var target_pixel: Vector2 = _grid_to_pixel_center(path[i])
		# 每步动画：移动视觉位置到下一格中心
		_move_tween.tween_property(self, "_unit_visual_pos", target_pixel, MOVE_STEP_DURATION)
		# 每步回调：同步 Camera 位置并重绘
		_move_tween.tween_callback(_on_move_step)

	# 动画全部完成后的回调
	_move_tween.tween_callback(_on_move_finished)

## 每移动一格时的回调：同步 Camera 并重绘
func _on_move_step() -> void:
	# Camera 跟随视觉位置（平滑由 Camera2D 内置处理）
	_camera.position = _unit_visual_pos
	queue_redraw()

## 移动动画全部完成后的回调
func _on_move_finished() -> void:
	_is_moving = false

	# 确保视觉位置精确对齐到逻辑位置
	_unit_visual_pos = _grid_to_pixel_center(_unit.position)
	_camera.position = _unit_visual_pos

	# 检查当前位置是否有未挑战的关卡 Slot
	var level: LevelSlot = _get_level_at(_unit.position)
	if level != null and not level.is_challenged():
		# 角色有部队时弹出战斗确认
		if _character != null and _character.has_troop():
			_show_battle_confirm(level)
			return

	# 刷新可达范围
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

## 回合结束回调：刷新可达范围，更新 HUD
func _on_turn_ended(_turn_number: int) -> void:
	_update_hud()
	_refresh_reachable()

# ─────────────────────────────────────────
# 关卡 Slot 管理
# ─────────────────────────────────────────

## 遍历 schema 中所有 FUNCTION Slot，创建对应的 LevelSlot 数据
func _init_level_slots() -> void:
	_level_slots = {}
	if _schema == null:
		return
	for y in range(_schema.height):
		for x in range(_schema.width):
			if _schema.get_slot(x, y) == MapSchema.SlotType.FUNCTION:
				var level: LevelSlot = LevelSlot.new()
				level.position = Vector2i(x, y)
				_level_slots[Vector2i(x, y)] = level
	# 调试输出：确认关卡放置位置
	print("WorldMap: 已放置 %d 个关卡 Slot" % _level_slots.size())
	for pos in _level_slots:
		print("  关卡位置: (%d, %d)" % [pos.x, pos.y])

## 获取指定坐标的关卡 Slot，不存在时返回 null
func _get_level_at(pos: Vector2i) -> LevelSlot:
	if _level_slots.has(pos):
		return _level_slots[pos] as LevelSlot
	return null

## 检查是否所有关卡均已挑战
func _check_all_levels_cleared() -> bool:
	for level in _level_slots.values():
		var lv: LevelSlot = level as LevelSlot
		if not lv.is_challenged():
			return false
	return true

# ─────────────────────────────────────────
# 战斗确认 UI
# ─────────────────────────────────────────

## 程序化创建战斗确认弹板（PanelContainer），挂载到 UILayer 下
func _create_battle_confirm_ui() -> void:
	var ui_layer: CanvasLayer = $UILayer

	_battle_panel = PanelContainer.new()
	_battle_panel.visible = false
	# 居中显示：锚点设为屏幕中心，grow 双向展开
	_battle_panel.set_anchors_and_offsets_preset(
		Control.PRESET_CENTER, Control.PRESET_MODE_KEEP_SIZE
	)
	_battle_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_battle_panel.grow_vertical = Control.GROW_DIRECTION_BOTH

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER

	var label: Label = Label.new()
	label.text = "发现关卡！是否进入战斗？"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(label)

	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER

	var btn_confirm: Button = Button.new()
	btn_confirm.text = "确认战斗"
	btn_confirm.pressed.connect(_on_battle_confirmed)
	hbox.add_child(btn_confirm)

	var btn_cancel: Button = Button.new()
	btn_cancel.text = "取消"
	btn_cancel.pressed.connect(_on_battle_cancelled)
	hbox.add_child(btn_cancel)

	vbox.add_child(hbox)
	_battle_panel.add_child(vbox)
	ui_layer.add_child(_battle_panel)

## 显示战斗确认弹板
func _show_battle_confirm(level: LevelSlot) -> void:
	_is_battle_pending = true
	_pending_level = level
	if _battle_panel != null:
		_battle_panel.visible = true

## 战斗确认按钮回调
func _on_battle_confirmed() -> void:
	if _pending_level == null or _character == null:
		return

	# 隐藏弹板
	_battle_panel.visible = false
	_is_battle_pending = false

	# 执行战斗结算
	var result: BattleResolver.BattleResult = BattleResolver.resolve(
		_character, _pending_level, _battle_config
	)

	# 扣除兵力
	if _character.has_troop():
		_character.troop.take_damage(result.damage_taken)

		# 判定部队是否被击败
		if _character.troop.is_defeated():
			_character.clear_troop()

	# 标记关卡为已挑战
	_pending_level.mark_challenged()
	_pending_level = null

	# 更新 HUD
	_update_hud()

	# 判定流程终止条件
	if not _character.has_troop():
		# 部队被击败 → 流程失败
		_game_finished = true
		_reachable_tiles = {}
		_show_defeat_text()
		queue_redraw()
		return

	if _check_all_levels_cleared():
		# 所有关卡已通关 → 流程胜利
		_game_finished = true
		_reachable_tiles = {}
		_show_victory_text()
		queue_redraw()
		return

	# 继续游戏，刷新可达范围
	_refresh_reachable()

## 战斗取消按钮回调：关闭弹板，恢复输入
func _on_battle_cancelled() -> void:
	_battle_panel.visible = false
	_is_battle_pending = false
	_pending_level = null
	# 取消后刷新可达范围，玩家可继续移动
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

## 主绘制入口：分层绘制地形 → 可达高亮 → 单位标记
## HUD 和完成提示已迁移至 CanvasLayer Label 节点，不在此绘制
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

	# 第三层：单位标记（基于视觉位置）
	if _unit != null:
		_draw_unit_marker()

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
		# 已挑战的关卡 Slot 变暗显示
		var pos: Vector2i = Vector2i(x, y)
		var level: LevelSlot = _get_level_at(pos)
		if level != null and level.is_challenged():
			slot_color = slot_color.darkened(CHALLENGED_DIM)
		var slot_rect: Rect2 = Rect2(
			x * TILE_SIZE + SLOT_MARGIN,
			y * TILE_SIZE + SLOT_MARGIN,
			TILE_SIZE - SLOT_MARGIN * 2 - 1,
			TILE_SIZE - SLOT_MARGIN * 2 - 1
		)
		draw_rect(slot_rect, slot_color)

## 绘制单位标记（基于视觉位置，支持动画中的平滑移动）
func _draw_unit_marker() -> void:
	var rect: Rect2 = Rect2(
		_unit_visual_pos.x - TILE_SIZE / 2 + UNIT_MARGIN,
		_unit_visual_pos.y - TILE_SIZE / 2 + UNIT_MARGIN,
		TILE_SIZE - UNIT_MARGIN * 2 - 1,
		TILE_SIZE - UNIT_MARGIN * 2 - 1
	)
	draw_rect(rect, UNIT_COLOR)
