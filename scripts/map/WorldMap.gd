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
## 多轮次：每轮生成若干关卡，全部挑战后推进下一轮，末轮通关则流程胜利。
## 多角色：多个角色各持一支部队，全部参与战斗，独立计算伤害。
## 道具与背包：关卡/轮次/回合奖励发放，装配管理 UI。

# ─────────────────────────────────────────
# 配置文件路径
# ─────────────────────────────────────────

const CONFIG_MAP: String = "res://assets/config/map_config.csv"
const CONFIG_TERRAIN: String = "res://assets/config/terrain_config.csv"
const CONFIG_SLOT: String = "res://assets/config/slot_config.csv"
const CONFIG_PCG: String = "res://assets/config/pcg_config.csv"
const CONFIG_UNIT: String = "res://assets/config/unit_config.csv"
const CONFIG_BATTLE: String = "res://assets/config/battle_config.csv"
const CONFIG_ROUND: String = "res://assets/config/round_config.csv"
const CONFIG_COUNTER: String = "res://assets/config/counter_matrix.csv"
const CONFIG_ENEMY_POOL: String = "res://assets/config/enemy_troop_pool.csv"
const CONFIG_ENEMY_SPAWN: String = "res://assets/config/enemy_spawn_config.csv"
const CONFIG_PLAYER: String = "res://assets/config/player_config.csv"
const CONFIG_ITEM: String = "res://assets/config/item_config.csv"
const CONFIG_INVENTORY: String = "res://assets/config/inventory_config.csv"
const CONFIG_QUALITY_UPGRADE: String = "res://assets/config/quality_upgrade_config.csv"
const CONFIG_DIFFICULTY: String = "res://assets/config/difficulty_config.csv"
const CONFIG_LEVEL_REWARD_POOL: String = "res://assets/config/level_reward_pool.csv"
const CONFIG_LEVEL_REWARD: String = "res://assets/config/level_reward_config.csv"
const CONFIG_ROUND_REWARD_POOL: String = "res://assets/config/round_reward_pool.csv"
const CONFIG_ROUND_REWARD: String = "res://assets/config/round_reward_config.csv"
const CONFIG_TURN_REWARD_POOL: String = "res://assets/config/turn_reward_pool.csv"
const CONFIG_TURN_REWARD: String = "res://assets/config/turn_reward_config.csv"

# ─────────────────────────────────────────
# 渲染常量
# ─────────────────────────────────────────

## 每格像素尺寸
const TILE_SIZE: int = 24

## 各地形渲染颜色（纯色块占位）
## key 使用整数字面量对应 MapSchema.TerrainType 枚举值
const TERRAIN_COLORS: Dictionary = {
	0: Color(0.40, 0.35, 0.30),  ## MOUNTAIN：灰褐：高山
	1: Color(0.50, 0.65, 0.30),  ## HIGHLAND：黄绿：高地
	2: Color(0.35, 0.72, 0.40),  ## FLATLAND：绿色：平地
	3: Color(0.30, 0.55, 0.75),  ## LOWLAND：蓝色：洼地
}

## Slot 标记颜色（小方块叠加在地形色上）
## key 使用整数字面量对应 MapSchema.SlotType 枚举值
const SLOT_COLORS: Dictionary = {
	1: Color(1.00, 0.85, 0.00),  ## RESOURCE：金色：资源点
	2: Color(0.80, 0.40, 1.00),  ## FUNCTION：紫色：功能点
	3: Color(1.00, 0.30, 0.30),  ## SPAWN：红色：出生点
}

## Slot 标记在格内的边距（像素）
const SLOT_MARGIN: int = 6

## 可达范围高亮色（半透明白色叠加）
const REACHABLE_COLOR: Color = Color(1.0, 1.0, 1.0, 0.25)

## 单位标记颜色（亮白色，醒目区分地形）
const UNIT_COLOR: Color = Color(1.0, 1.0, 1.0)

## 单位标记边距（像素）
const UNIT_MARGIN: int = 4

## 已挑战关卡变暗系数（同一轮内已挑战但尚未切换的关卡）
const CHALLENGED_DIM: float = 0.4

## 单位逐格移动动画耗时（秒/格）
const MOVE_STEP_DURATION: float = 0.1

## 轮次过渡提示显示时长（秒）
const ROUND_HINT_DURATION: float = 1.5

## 醒目提示显示时长（秒）
const NOTICE_DURATION: float = 2.5

# ─────────────────────────────────────────
# 节点引用
# ─────────────────────────────────────────

## Camera2D 节点（场景中配置，已开启 position_smoothing）
@onready var _camera: Camera2D = $Camera2D

## HUD 分区标签
@onready var _hud_round: Label = $UILayer/HudBar/HBox/RoundInfo
@onready var _hud_troop: Label = $UILayer/HudBar/HBox/TroopInfo
@onready var _hud_keys: Label = $UILayer/HudBar/HBox/KeyHints

## 通知底板容器（CanvasLayer 下，HUD 栏上方居中）
@onready var _notice_bar: PanelContainer = $UILayer/NoticeBar

## 通知/流程结束提示 Label
@onready var _finish_label: Label = $UILayer/NoticeBar/NoticeLabel

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

## 角色数据列表（多角色支持）
var _characters: Array[CharacterData] = []

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

## 轮次管理器
var _round_manager: RoundManager = null

## 敌方部队生成器
var _enemy_generator: EnemyTroopGenerator = null

## 背包
var _inventory: Inventory = null

## 奖励生成器
var _reward_generator: RewardGenerator = null

## 难度配置：每轮增加的 base_damage 值
var _damage_increment: float = 0.0

## 击退倍率配置
var _repel_player_damage_rate: float = 0.6
var _repel_enemy_damage_rate: float = 0.6

## 击退冷却回合数配置
var _repel_cooldown_turns: int = 3

## 敌方移动开关（从配置读取）
var _enemy_movement_enabled: bool = false

## 敌方移动力（从配置读取）
var _enemy_movement_points: int = 6

## 敌方是否已激活移动能力（首次战斗后全局激活）
var _enemy_can_move: bool = false

## 是否正在执行敌方移动阶段
var _is_enemy_moving: bool = false

## 敌方移动队列（按距离排序的待移动关卡列表）
var _enemy_move_queue: Array[LevelSlot] = []

## 当前正在移动的敌方关卡的视觉位置（像素坐标）
var _enemy_visual_pos: Vector2 = Vector2.ZERO

## 当前正在移动的敌方关卡引用
var _moving_enemy_level: LevelSlot = null

## 是否为敌方主动触发的强制战斗（禁止取消）
var _is_forced_battle: bool = false

## 敌方关卡占据位置的原始 SlotType（用于移动后恢复）
var _original_slot_types: Dictionary = {}

## 预计算的完整战斗结果（100% 伤害，供预览和结算使用）
var _pending_full_result: BattleResolver.BattleResult = null

## 关卡奖励池原始行数据（缓存，按 round_id 过滤用）
var _level_reward_pool_rows: Array = []

## 关卡奖励数量配置
var _level_reward_count_min: int = 1
var _level_reward_count_max: int = 2

## 轮次奖励池原始行数据
var _round_reward_pool_rows: Array = []

## 轮次奖励数量
var _round_reward_count: int = 2

## 回合奖励池原始行数据
var _turn_reward_pool_rows: Array = []

## 回合奖励数量
var _turn_reward_count: int = 1

## 装配管理面板引用
var _manage_panel: PanelContainer = null

## 是否正在显示装配管理面板
var _is_manage_open: bool = false

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
	var round_rows: Array = ConfigLoader.load_csv(CONFIG_ROUND)
	var counter_rows: Array = ConfigLoader.load_csv(CONFIG_COUNTER)
	var enemy_pool_rows: Array = ConfigLoader.load_csv(CONFIG_ENEMY_POOL)
	var enemy_spawn_cfg: Dictionary = ConfigLoader.load_csv_kv(CONFIG_ENEMY_SPAWN)
	var player_cfg: Dictionary = ConfigLoader.load_csv_kv(CONFIG_PLAYER)
	var item_rows: Array = ConfigLoader.load_csv(CONFIG_ITEM)
	var inventory_cfg: Dictionary = ConfigLoader.load_csv_kv(CONFIG_INVENTORY)
	var quality_cfg: Dictionary = ConfigLoader.load_csv_kv(CONFIG_QUALITY_UPGRADE)
	var difficulty_cfg: Dictionary = ConfigLoader.load_csv_kv(CONFIG_DIFFICULTY)

	# 加载奖励池配置（缓存行数据供后续按轮次过滤）
	_level_reward_pool_rows = ConfigLoader.load_csv(CONFIG_LEVEL_REWARD_POOL)
	var level_reward_cfg: Dictionary = ConfigLoader.load_csv_kv(CONFIG_LEVEL_REWARD)
	_level_reward_count_min = int(level_reward_cfg.get("reward_count_min", "1"))
	_level_reward_count_max = int(level_reward_cfg.get("reward_count_max", "2"))

	_round_reward_pool_rows = ConfigLoader.load_csv(CONFIG_ROUND_REWARD_POOL)
	var round_reward_cfg: Dictionary = ConfigLoader.load_csv_kv(CONFIG_ROUND_REWARD)
	_round_reward_count = int(round_reward_cfg.get("reward_count", "2"))

	_turn_reward_pool_rows = ConfigLoader.load_csv(CONFIG_TURN_REWARD_POOL)
	var turn_reward_cfg: Dictionary = ConfigLoader.load_csv_kv(CONFIG_TURN_REWARD)
	_turn_reward_count = int(turn_reward_cfg.get("reward_count", "1"))

	# 构建地形消耗表和 Slot 允许表
	var terrain_costs: Dictionary = _build_terrain_costs(terrain_rows)
	var slot_allowed: Dictionary = _build_slot_allowed(slot_rows)

	# 加载克制矩阵
	BattleResolver.load_counter_matrix(counter_rows)

	# 加载品质升级配置
	TroopData.load_upgrade_config(quality_cfg)

	# 加载难度配置
	_damage_increment = float(difficulty_cfg.get("damage_increment", "10"))

	# 加载击退/击败配置
	_repel_player_damage_rate = float(_battle_config.get("repel_player_damage_rate", "0.6"))
	_repel_enemy_damage_rate = float(_battle_config.get("repel_enemy_damage_rate", "0.6"))
	_repel_cooldown_turns = int(_battle_config.get("repel_cooldown_turns", "3"))

	# 加载敌方移动配置
	_enemy_movement_enabled = int(_battle_config.get("enemy_movement_enabled", "0")) == 1
	_enemy_movement_points = int(_battle_config.get("enemy_movement_points", "6"))

	# 初始化奖励生成器
	_reward_generator = RewardGenerator.new()
	_reward_generator.load_item_templates(item_rows)

	# 初始化背包
	_inventory = Inventory.new()
	_inventory.init_from_config(inventory_cfg)

	# 初始化敌方部队生成器
	_enemy_generator = EnemyTroopGenerator.new()
	_enemy_generator.init_from_config(enemy_pool_rows, enemy_spawn_cfg)

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

	# 初始化轮次管理器
	_round_manager = RoundManager.new()
	_round_manager.init_from_config(round_rows)
	_round_manager.round_started.connect(_on_round_started)
	_round_manager.all_rounds_cleared.connect(_on_all_rounds_cleared)

	# 设置 Camera 边界限制（不超出地图像素范围）
	_setup_camera_limits()

	# 初始化单位（移动系统）
	var default_movement: int = int(unit_cfg.get("default_movement", "6"))
	_unit = UnitData.new()
	_unit.position = _start_pos
	_unit.max_movement = default_movement
	_unit.current_movement = default_movement

	# 初始化玩家角色和部队（多角色，从配置读取）
	_init_player(player_cfg)

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

	# 创建装配管理面板（隐藏状态）
	_create_manage_ui()

	# 启动第一轮（触发 _on_round_started → 生成关卡）
	_round_manager.start_current_round()

	# 更新 HUD
	_update_hud()

	# 计算初始可达范围
	_refresh_reachable()

# ─────────────────────────────────────────
# 输入处理
# ─────────────────────────────────────────

func _input(event: InputEvent) -> void:
	# 动画播放中、战斗确认中、敌方移动中、管理面板打开中或流程结束时锁定所有输入
	if _game_finished or _is_moving or _is_battle_pending or _is_manage_open or _is_enemy_moving:
		return

	# 鼠标左键点击：移动单位
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_handle_click(mb.position)

	# 空格键：结束回合（触发回合结算流程）
	if event is InputEventKey:
		var key: InputEventKey = event as InputEventKey
		if key.pressed and not key.echo and key.keycode == KEY_SPACE:
			_on_turn_end_settlement()

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

## 刷新 HUD 状态栏文字（包含轮次、关卡、多角色兵力信息）
func _update_hud() -> void:
	if _unit == null or _turn_manager == null:
		return

	# 左区：轮次 / 关卡 / 回合 / 移动力
	var round_parts: Array[String] = []
	if _round_manager != null:
		round_parts.append("轮次 %d/%d" % [
			_round_manager.get_current_round() + 1,
			_round_manager.get_total_rounds()
		])
		round_parts.append("关卡 %d/%d" % [
			_round_manager.get_cleared_count(),
			_round_manager.get_current_level_count()
		])
	round_parts.append("回合 %d" % _turn_manager.current_turn)
	round_parts.append("移动力 %d/%d" % [_unit.current_movement, _unit.max_movement])
	if _hud_round != null:
		_hud_round.text = "  ".join(round_parts)

	# 中区：部队状态
	if _hud_troop != null:
		_hud_troop.text = _get_all_troops_display()

	# 右区：快捷键提示
	if _hud_keys != null:
		_hud_keys.text = "[空格]结束回合  [M]管理  [Q]放弃"

## 获取所有角色部队的显示文本
func _get_all_troops_display() -> String:
	var parts: Array[String] = []
	for i in range(_characters.size()):
		var ch: CharacterData = _characters[i]
		if ch.has_troop():
			parts.append("%s %d/%d" % [
				ch.troop.get_display_text(),
				ch.troop.current_hp,
				ch.troop.max_hp
			])
		else:
			parts.append("角色%d:空" % (i + 1))
	return " | ".join(parts)

## 显示流程胜利提示
func _show_victory_text() -> void:
	if _finish_label == null or _turn_manager == null:
		return
	var total_rounds: int = _round_manager.get_total_rounds() if _round_manager != null else 1
	_finish_label.text = "全部 %d 轮通关！流程胜利（回合 %d）" % [total_rounds, _turn_manager.current_turn]
	if _notice_bar != null:
		_notice_bar.visible = true

## 显示流程失败提示
func _show_defeat_text() -> void:
	if _finish_label == null or _turn_manager == null:
		return
	_finish_label.text = "流程失败（回合 %d）" % _turn_manager.current_turn
	if _notice_bar != null:
		_notice_bar.visible = true

## 显示醒目提示文字（短暂显示后自动隐藏）
func _show_notice(text: String, duration: float = NOTICE_DURATION) -> void:
	if _finish_label == null:
		return
	_finish_label.text = text
	if _notice_bar != null:
		_notice_bar.visible = true
	var timer: SceneTreeTimer = get_tree().create_timer(duration)
	timer.timeout.connect(_on_notice_timeout)

## 醒目提示超时回调
func _on_notice_timeout() -> void:
	if _finish_label != null and not _game_finished:
		_finish_label.text = ""
		if _notice_bar != null:
			_notice_bar.visible = false

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

	# 寻路（传入击退关卡阻挡位置）
	var blocked: Dictionary = _get_blocked_positions()
	var path_result: Pathfinder.PathResult = Pathfinder.find_path(_schema, _unit.position, target, {}, blocked)
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

	# 全灭检查（战斗后部队全灭但玩家仍可移动的情况）
	if _check_defeat():
		return

	# 检查当前位置是否有可交互的关卡 Slot
	var level: LevelSlot = _get_level_at(_unit.position)
	if level != null and level.is_interactable():
		# 有任意角色装配了部队时弹出战斗预览
		if _has_any_troop():
			_show_battle_confirm(level)
			return

	# 刷新可达范围
	_refresh_reachable()

## 刷新可达范围并触发重绘
## 击退状态的关卡格视为不可通行
func _refresh_reachable() -> void:
	if _unit != null and _schema != null and not _game_finished:
		var blocked: Dictionary = _get_blocked_positions()
		_reachable_tiles = MovementSystem.get_reachable_tiles(
			_schema, _unit.position, float(_unit.current_movement), {}, blocked
		)
	else:
		_reachable_tiles = {}
	queue_redraw()

## 获取所有阻挡位置（击退状态的关卡格）
func _get_blocked_positions() -> Dictionary:
	var blocked: Dictionary = {}
	for pos in _level_slots:
		var lv: LevelSlot = _level_slots[pos] as LevelSlot
		if lv.is_repelled():
			blocked[pos] = true
	return blocked

## 回合结束回调：刷新可达范围，更新 HUD
func _on_turn_ended(_turn_number: int) -> void:
	_update_hud()
	_refresh_reachable()

## 回合结算流程（抽象为独立方法）
## 玩家按空格触发，执行回合奖励发放后结束回合
func _on_turn_end_settlement() -> void:
	if _game_finished or _check_defeat():
		return
	# 发放回合奖励
	if _reward_generator != null and _round_manager != null:
		var round_id: int = _round_manager.get_current_round() + 1
		var rewards: Array[ItemData] = _reward_generator.generate_rewards(
			_turn_reward_pool_rows, round_id, _turn_reward_count
		)
		if not rewards.is_empty():
			var added: int = _inventory.add_items(rewards)
			var reward_text: String = _format_rewards_text(rewards)
			_show_notice("回合奖励：%s" % reward_text)

	# 递减击退关卡的冷却回合数
	_tick_repelled_cooldowns()

	# 敌方移动阶段（异步，完成后再 end_turn）
	if _enemy_can_move and _enemy_movement_enabled:
		_start_enemy_move_phase()
	else:
		_turn_manager.end_turn()

# ─────────────────────────────────────────
# 敌方移动
# ─────────────────────────────────────────

## 启动敌方移动阶段
## 收集所有可移动关卡，按距离排序后逐个执行移动
func _start_enemy_move_phase() -> void:
	_is_enemy_moving = true
	_enemy_move_queue = _get_sorted_movable_levels()
	# 开始处理移动队列
	_process_next_enemy_move()

## 获取可移动关卡列表，按距离玩家从近到远排序
## 距离相同时按格坐标 y→x 排序
func _get_sorted_movable_levels() -> Array[LevelSlot]:
	var movable: Array[LevelSlot] = []
	for pos in _level_slots:
		var lv: LevelSlot = _level_slots[pos] as LevelSlot
		# 仅 UNCHALLENGED 状态的关卡参与移动
		if lv.state == LevelSlot.State.UNCHALLENGED:
			movable.append(lv)

	if _unit == null:
		return movable

	var player_pos: Vector2i = _unit.position
	# 按曼哈顿距离升序排序，距离相同按 y→x 排序
	movable.sort_custom(func(a: LevelSlot, b: LevelSlot) -> bool:
		var dist_a: int = absi(a.position.x - player_pos.x) + absi(a.position.y - player_pos.y)
		var dist_b: int = absi(b.position.x - player_pos.x) + absi(b.position.y - player_pos.y)
		if dist_a != dist_b:
			return dist_a < dist_b
		if a.position.y != b.position.y:
			return a.position.y < b.position.y
		return a.position.x < b.position.x
	)
	return movable

## 处理移动队列中的下一个敌方关卡
## 队列为空时结束敌方移动阶段
func _process_next_enemy_move() -> void:
	# 游戏结束则终止后续移动
	if _game_finished:
		_finish_enemy_move_phase()
		return

	# 队列为空，敌方移动阶段结束
	if _enemy_move_queue.is_empty():
		_finish_enemy_move_phase()
		return

	var level: LevelSlot = _enemy_move_queue.pop_front()

	# 关卡状态可能在前序战斗中被改变（如被击败），跳过无效关卡
	if level.state != LevelSlot.State.UNCHALLENGED:
		_process_next_enemy_move()
		return

	# 寻路：目标为玩家位置，阻挡位置包含其他所有关卡
	var blocked: Dictionary = _get_enemy_blocked_positions(level)
	var path_result: Pathfinder.PathResult = Pathfinder.find_path(
		_schema, level.position, _unit.position, {}, blocked
	)

	# 无通路或已在玩家位置，跳过
	if path_result.path.size() < 2:
		_process_next_enemy_move()
		return

	# 按移动力截断路径
	var move_path: Array[Vector2i] = _truncate_path_by_movement(
		path_result.path, _enemy_movement_points
	)

	# 敌方不进入玩家所在格，停在相邻格触发战斗
	# 避免击退后 REPELLED 关卡堵在玩家位置上
	if move_path.size() >= 2 and move_path[move_path.size() - 1] == _unit.position:
		move_path.resize(move_path.size() - 1)

	# 截断后无法移动，跳过
	if move_path.size() < 2:
		_process_next_enemy_move()
		return

	# 记录当前移动的关卡，更新逻辑位置
	_moving_enemy_level = level
	var old_pos: Vector2i = level.position
	var new_pos: Vector2i = move_path[move_path.size() - 1]

	# 更新 _level_slots 字典键和关卡位置
	_level_slots.erase(old_pos)
	level.position = new_pos
	_level_slots[new_pos] = level

	# 更新地图 Slot 标记（保留原始类型以便恢复）
	# 恢复旧位置的原始 Slot 类型，若无记录则置为 NONE
	var restored_type: int = _original_slot_types.get(old_pos, MapSchema.SlotType.NONE) as int
	_schema.set_slot(old_pos.x, old_pos.y, restored_type as MapSchema.SlotType)
	_original_slot_types.erase(old_pos)
	# 保存新位置的原始 Slot 类型（仅首次覆盖时记录）
	if not _original_slot_types.has(new_pos):
		_original_slot_types[new_pos] = _schema.get_slot(new_pos.x, new_pos.y)
	_schema.set_slot(new_pos.x, new_pos.y, MapSchema.SlotType.FUNCTION)

	# 播放移动动画
	_start_enemy_move_animation(move_path)

## 获取敌方关卡移动时的阻挡位置
## 排除自身，包含所有其他关卡（UNCHALLENGED + REPELLED）
func _get_enemy_blocked_positions(exclude_level: LevelSlot) -> Dictionary:
	var blocked: Dictionary = {}
	for pos in _level_slots:
		var p: Vector2i = pos as Vector2i
		var lv: LevelSlot = _level_slots[p] as LevelSlot
		if lv == exclude_level:
			continue
		# 所有其他关卡均阻挡（未挑战和击退状态）
		if lv.state == LevelSlot.State.UNCHALLENGED or lv.is_repelled():
			blocked[p] = true
	return blocked

## 按移动力和地形消耗截断路径
## 返回截断后的路径（含起点），至少包含起点
func _truncate_path_by_movement(full_path: Array[Vector2i], movement: int) -> Array[Vector2i]:
	var truncated: Array[Vector2i] = [full_path[0]]
	var remaining: float = float(movement)
	for i in range(1, full_path.size()):
		var cost: float = _schema.get_terrain_cost(full_path[i].x, full_path[i].y)
		if cost >= INF or cost > remaining:
			break
		remaining -= cost
		truncated.append(full_path[i])
	return truncated

## 播放敌方关卡移动动画
func _start_enemy_move_animation(path: Array[Vector2i]) -> void:
	_enemy_visual_pos = _grid_to_pixel_center(path[0])

	if _move_tween != null and _move_tween.is_valid():
		_move_tween.kill()

	_move_tween = create_tween()
	for i in range(1, path.size()):
		var target_pixel: Vector2 = _grid_to_pixel_center(path[i])
		_move_tween.tween_property(self, "_enemy_visual_pos", target_pixel, MOVE_STEP_DURATION)
		_move_tween.tween_callback(queue_redraw)

	_move_tween.tween_callback(_on_enemy_move_finished)

## 敌方关卡移动动画完成回调
func _on_enemy_move_finished() -> void:
	if _moving_enemy_level == null:
		_process_next_enemy_move()
		return

	var level_pos: Vector2i = _moving_enemy_level.position
	var player_pos: Vector2i = _unit.position
	# 判断是否与玩家相邻（曼哈顿距离 = 1）
	var dist: int = absi(level_pos.x - player_pos.x) + absi(level_pos.y - player_pos.y)
	var adjacent_to_player: bool = dist == 1

	_moving_enemy_level = null
	queue_redraw()

	if adjacent_to_player:
		# 敌方到达玩家相邻格，触发强制战斗
		var level: LevelSlot = _get_level_at(level_pos)
		if level != null and level.is_interactable() and _has_any_troop():
			_is_forced_battle = true
			_show_battle_confirm(level)
			return
	# 继续处理下一个关卡
	_process_next_enemy_move()

## 结束敌方移动阶段，执行回合结束
func _finish_enemy_move_phase() -> void:
	_is_enemy_moving = false
	_moving_enemy_level = null
	_enemy_move_queue = []
	if not _game_finished:
		_turn_manager.end_turn()

# ─────────────────────────────────────────
# 关卡 Slot 管理
# ─────────────────────────────────────────

## 清除地图上已击败的关卡 Slot（FUNCTION → NONE），保留击退状态的关卡
func _clear_level_slots() -> void:
	if _schema == null:
		return
	var keep: Dictionary = {}
	for pos in _level_slots:
		var p: Vector2i = pos as Vector2i
		var lv: LevelSlot = _level_slots[p] as LevelSlot
		if lv.is_repelled():
			# 保留击退关卡
			keep[p] = lv
		else:
			# 清除已击败/已挑战的关卡 Slot，恢复原始类型
			var orig_type: int = _original_slot_types.get(p, MapSchema.SlotType.NONE) as int
			_schema.set_slot(p.x, p.y, orig_type as MapSchema.SlotType)
			_original_slot_types.erase(p)
	_level_slots = keep

## 生成关卡并初始化 LevelSlot 数据
## count: 本轮关卡数量
## 保留击退状态的旧关卡，新关卡避开已占格子
func _generate_level_slots(count: int) -> void:
	if _schema == null:
		return
	# 构建排除列表：起点、终点、玩家当前位置 + 已有击退关卡的格子
	var exclude: Array[Vector2i] = [_start_pos, _end_pos]
	if _unit != null and not exclude.has(_unit.position):
		exclude.append(_unit.position)
	# 保留击退关卡，排除其占据的格子
	for pos in _level_slots:
		var p: Vector2i = pos as Vector2i
		var lv: LevelSlot = _level_slots[p] as LevelSlot
		if lv.is_repelled():
			if not exclude.has(p):
				exclude.append(p)

	# 在地图上随机放置关卡 Slot
	var placed: Array[Vector2i] = MapGenerator.place_level_slots(_schema, count, exclude)

	# 当前轮次索引（用于难度和奖励）
	var round_index: int = _round_manager.get_current_round() if _round_manager != null else 0
	var round_id: int = round_index + 1

	# 构建新关卡字典（保留击退关卡 + 新增本轮关卡）
	var new_slots: Dictionary = {}
	# 先保留击退状态的旧关卡
	for pos in _level_slots:
		var p: Vector2i = pos as Vector2i
		var lv: LevelSlot = _level_slots[p] as LevelSlot
		if lv.is_repelled():
			new_slots[p] = lv
	# 新增本轮关卡
	for pos in placed:
		var level: LevelSlot = LevelSlot.new()
		level.position = pos
		# 设置关卡难度（等于轮次索引）
		level.difficulty = round_index
		# 为关卡生成敌方部队
		if _enemy_generator != null:
			level.troops = _enemy_generator.generate_troops()
		# 为关卡预生成胜利奖励
		if _reward_generator != null:
			level.rewards = _reward_generator.generate_rewards_range(
				_level_reward_pool_rows, round_id,
				_level_reward_count_min, _level_reward_count_max
			)
		new_slots[pos] = level
	_level_slots = new_slots


## 获取指定坐标的关卡 Slot，不存在时返回 null
func _get_level_at(pos: Vector2i) -> LevelSlot:
	if _level_slots.has(pos):
		return _level_slots[pos] as LevelSlot
	return null

# ─────────────────────────────────────────
# 轮次管理
# ─────────────────────────────────────────

## 轮次开始回调：清除旧关卡，生成本轮新关卡，预生成轮次奖励
func _on_round_started(round_index: int) -> void:
	# 清除上一轮的关卡 Slot
	_clear_level_slots()

	# 生成本轮关卡
	var level_count: int = _round_manager.get_current_level_count()
	_generate_level_slots(level_count)

	# 预生成轮次胜利奖励
	var round_id: int = round_index + 1
	if _reward_generator != null:
		var round_rewards: Array[ItemData] = _reward_generator.generate_rewards(
			_round_reward_pool_rows, round_id, _round_reward_count
		)
		_round_manager.set_round_rewards(round_rewards)

	queue_redraw()

## 所有轮次通关回调：流程胜利
func _on_all_rounds_cleared() -> void:
	_game_finished = true
	_reachable_tiles = {}
	_show_victory_text()
	queue_redraw()

## 显示轮次过渡提示（短暂显示后自动隐藏）
func _show_round_hint() -> void:
	if _finish_label == null or _round_manager == null:
		return
	_finish_label.text = "第 %d 轮开始！" % (_round_manager.get_current_round() + 1)
	if _notice_bar != null:
		_notice_bar.visible = true
	# 延时隐藏提示文字
	var timer: SceneTreeTimer = get_tree().create_timer(ROUND_HINT_DURATION)
	timer.timeout.connect(_on_round_hint_timeout)

## 轮次提示超时回调：清除提示文字，刷新可达范围
func _on_round_hint_timeout() -> void:
	if _finish_label != null:
		_finish_label.text = ""
		if _notice_bar != null:
			_notice_bar.visible = false
	_update_hud()
	_refresh_reachable()

# ─────────────────────────────────────────
# 战斗确认 UI
# ─────────────────────────────────────────

## 程序化创建战斗确认弹板（PanelContainer），挂载到 UILayer 下
## 弹板展示击退/击败两种结果的双方伤害预览
func _create_battle_confirm_ui() -> void:
	var ui_layer: CanvasLayer = $UILayer

	_battle_panel = PanelContainer.new()
	_battle_panel.visible = false
	_battle_panel.set_anchors_and_offsets_preset(
		Control.PRESET_CENTER, Control.PRESET_MODE_KEEP_SIZE
	)
	_battle_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_battle_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_battle_panel.custom_minimum_size = Vector2(360, 0)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 6)

	# 标题
	var title: Label = Label.new()
	title.name = "BattleTitleLabel"
	title.text = "遭遇战斗"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(1.0, 0.92, 0.30))
	vbox.add_child(title)

	# 分隔线
	var sep1: HSeparator = HSeparator.new()
	sep1.add_theme_constant_override("separation", 8)
	vbox.add_child(sep1)

	# 战斗信息标签（敌方部队 + 奖励）
	var battle_label: Label = Label.new()
	battle_label.name = "BattleInfoLabel"
	battle_label.text = ""
	battle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(battle_label)

	# 分隔线
	var sep2: HSeparator = HSeparator.new()
	sep2.add_theme_constant_override("separation", 6)
	vbox.add_child(sep2)

	# 击退预览标签（蓝色调表示保守选项）
	var repel_label: Label = Label.new()
	repel_label.name = "RepelPreviewLabel"
	repel_label.text = ""
	repel_label.add_theme_color_override("font_color", Color(0.65, 0.80, 0.95))
	vbox.add_child(repel_label)

	# 击败预览标签（橙色调表示激进选项）
	var defeat_label: Label = Label.new()
	defeat_label.name = "DefeatPreviewLabel"
	defeat_label.text = ""
	defeat_label.add_theme_color_override("font_color", Color(0.95, 0.75, 0.45))
	vbox.add_child(defeat_label)

	# 分隔线
	var sep3: HSeparator = HSeparator.new()
	sep3.add_theme_constant_override("separation", 6)
	vbox.add_child(sep3)

	# 按钮区域
	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.name = "BattleButtonArea"
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 12)

	# 击退按钮（蓝色调）
	var btn_repel: Button = Button.new()
	btn_repel.name = "BtnRepel"
	btn_repel.text = "击退"
	btn_repel.custom_minimum_size = Vector2(80, 32)
	btn_repel.add_theme_color_override("font_color", Color(0.65, 0.80, 0.95))
	btn_repel.add_theme_color_override("font_hover_color", Color(0.80, 0.92, 1.0))
	btn_repel.pressed.connect(_on_battle_repel)
	hbox.add_child(btn_repel)

	# 击败按钮（橙色调）
	var btn_defeat: Button = Button.new()
	btn_defeat.name = "BtnDefeat"
	btn_defeat.text = "击败"
	btn_defeat.custom_minimum_size = Vector2(80, 32)
	btn_defeat.add_theme_color_override("font_color", Color(0.95, 0.75, 0.45))
	btn_defeat.add_theme_color_override("font_hover_color", Color(1.0, 0.85, 0.55))
	btn_defeat.pressed.connect(_on_battle_defeat)
	hbox.add_child(btn_defeat)

	# 取消按钮（灰色调）
	var btn_cancel: Button = Button.new()
	btn_cancel.name = "BtnCancel"
	btn_cancel.text = "取消"
	btn_cancel.custom_minimum_size = Vector2(80, 32)
	btn_cancel.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	btn_cancel.add_theme_color_override("font_hover_color", Color(0.75, 0.75, 0.75))
	btn_cancel.pressed.connect(_on_battle_cancelled)
	hbox.add_child(btn_cancel)

	vbox.add_child(hbox)
	_battle_panel.add_child(vbox)
	ui_layer.add_child(_battle_panel)

## 显示战斗预览弹板（展示击退和击败两种结果的双方伤害预览）
func _show_battle_confirm(level: LevelSlot) -> void:
	_is_battle_pending = true
	_pending_level = level
	if _battle_panel == null:
		return

	# 预计算完整战斗结果（100% 伤害）
	var player_troops: Array[TroopData] = _get_active_troops()
	_pending_full_result = BattleResolver.resolve(
		player_troops, level.troops, _battle_config,
		level.difficulty, _damage_increment
	)

	# 计算击退和击败两套结果
	var repel_result: BattleResolver.BattleResult = _pending_full_result.apply_damage_rate(
		_repel_player_damage_rate, _repel_enemy_damage_rate
	)
	var defeat_result: BattleResolver.BattleResult = _pending_full_result

	# 判断击退倍率下是否已能全灭敌方
	var repel_wipes: bool = BattleResolver.would_wipe_enemies(level.troops, repel_result.enemy_damages)
	# 判断击败（100%伤害）是否能全灭敌方
	var defeat_wipes: bool = BattleResolver.would_wipe_enemies(level.troops, defeat_result.enemy_damages)

	# 更新标题（区分主动/被动战斗）
	var title_label: Label = _battle_panel.find_child("BattleTitleLabel", true, false) as Label
	if title_label != null:
		title_label.text = "敌方来袭！" if _is_forced_battle else "遭遇战斗"

	# 更新战斗信息标签
	var info_label: Label = _battle_panel.find_child("BattleInfoLabel", true, false) as Label
	if info_label != null:
		var text: String = "敌方：%s" % level.get_troops_detail_display()
		if not level.rewards.is_empty():
			text += "\n击败奖励：%s" % level.get_rewards_display()
		info_label.text = text

	# 更新击退预览（击退全灭时不显示单独的击退栏）
	var repel_label: Label = _battle_panel.find_child("RepelPreviewLabel", true, false) as Label
	if repel_label != null:
		if repel_wipes:
			repel_label.text = ""
			repel_label.visible = false
		else:
			repel_label.text = "── 击退（不获得奖励）──\n%s" % _format_battle_preview(
				player_troops, repel_result, level.troops
			)
			repel_label.visible = true

	# 更新击败预览
	var defeat_label: Label = _battle_panel.find_child("DefeatPreviewLabel", true, false) as Label
	if defeat_label != null:
		if repel_wipes:
			# 击退即可全灭：按击退倍率结算，显示击退倍率的伤害预览
			defeat_label.text = "── 击败（低损耗全灭）──\n%s" % _format_battle_preview(
				player_troops, repel_result, level.troops
			)
			defeat_label.visible = true
		elif defeat_wipes:
			# 需要全力才能击败
			defeat_label.text = "── 击败 ──\n%s" % _format_battle_preview(
				player_troops, defeat_result, level.troops
			)
			defeat_label.visible = true
		else:
			# 100% 伤害也无法全灭
			defeat_label.text = ""
			defeat_label.visible = false

	# 控制按钮显示
	var btn_repel: Button = _battle_panel.find_child("BtnRepel", true, false) as Button
	if btn_repel != null:
		btn_repel.visible = not repel_wipes
	var btn_defeat: Button = _battle_panel.find_child("BtnDefeat", true, false) as Button
	if btn_defeat != null:
		# 击退全灭或击败全灭时都显示击败按钮
		btn_defeat.visible = repel_wipes or defeat_wipes

	# 强制战斗时隐藏取消按钮（敌方主动触发，玩家必须完成选择）
	var btn_cancel: Button = _battle_panel.find_child("BtnCancel", true, false) as Button
	if btn_cancel != null:
		btn_cancel.visible = not _is_forced_battle

	_battle_panel.visible = true

## 格式化战斗预览文本（展示双方各部队的预计伤害）
func _format_battle_preview(player_troops: Array[TroopData], result: BattleResolver.BattleResult, enemy_troops: Array[TroopData]) -> String:
	var lines: Array[String] = []
	# 我方伤害预览
	lines.append("  我方损耗：")
	for i in range(player_troops.size()):
		var t: TroopData = player_troops[i]
		var dmg: int = result.damages[i] if i < result.damages.size() else 0
		var remaining: int = maxi(0, t.current_hp - dmg)
		lines.append("    %s: -%d (%d→%d)" % [t.get_display_text(), dmg, t.current_hp, remaining])
	# 敌方伤害预览
	lines.append("  敌方损耗：")
	for i in range(enemy_troops.size()):
		var e: TroopData = enemy_troops[i]
		var dmg: int = result.enemy_damages[i] if i < result.enemy_damages.size() else 0
		var remaining: int = maxi(0, e.current_hp - dmg)
		lines.append("    %s: -%d (%d→%d)" % [e.get_display_text(), dmg, e.current_hp, remaining])
	return "\n".join(lines)

## 击退按钮回调
func _on_battle_repel() -> void:
	if _pending_level == null or _pending_full_result == null:
		return
	_battle_panel.visible = false
	_is_battle_pending = false

	# 按击退倍率缩放伤害
	var result: BattleResolver.BattleResult = _pending_full_result.apply_damage_rate(
		_repel_player_damage_rate, _repel_enemy_damage_rate
	)

	# 保存敌方部队快照（扣血前），用于抽取部队奖励
	var troop_snapshot: Array[TroopData] = _pending_level.troops.duplicate()

	# 我方扣血
	_apply_player_damages(result)

	# 敌方扣血
	_pending_level.apply_enemy_damages(result.enemy_damages)
	# 移除被消灭的敌方部队
	var all_wiped: bool = _pending_level.remove_defeated_troops()

	if all_wiped:
		# 击退但全灭 → 转为击败，发放奖励
		_pending_level.mark_defeated()
		_grant_level_rewards()
		# 从敌方部队中随机抽取 1 支作为部队道具奖励
		_grant_troop_reward(troop_snapshot)
	else:
		# 标记为击退，设置冷却
		_pending_level.mark_repelled(_repel_cooldown_turns)

	# 后处理（共用逻辑）
	_post_battle_settlement()

## 击败按钮回调
## 击退即可全灭时按击退倍率结算（低损耗全灭），否则按 100% 结算
func _on_battle_defeat() -> void:
	if _pending_level == null or _pending_full_result == null:
		return
	_battle_panel.visible = false
	_is_battle_pending = false

	# 判断是否击退即可全灭，决定使用哪套倍率
	var repel_result: BattleResolver.BattleResult = _pending_full_result.apply_damage_rate(
		_repel_player_damage_rate, _repel_enemy_damage_rate
	)
	var repel_wipes: bool = BattleResolver.would_wipe_enemies(
		_pending_level.troops, repel_result.enemy_damages
	)
	var result: BattleResolver.BattleResult = repel_result if repel_wipes else _pending_full_result

	# 保存敌方部队快照（扣血前），用于抽取部队奖励
	var troop_snapshot: Array[TroopData] = _pending_level.troops.duplicate()

	# 我方扣血
	_apply_player_damages(result)

	# 敌方扣血
	_pending_level.apply_enemy_damages(result.enemy_damages)
	_pending_level.remove_defeated_troops()

	# 标记为击败
	_pending_level.mark_defeated()

	# 发放关卡胜利奖励
	_grant_level_rewards()

	# 从敌方部队中随机抽取 1 支作为部队道具奖励
	_grant_troop_reward(troop_snapshot)

	# 后处理
	_post_battle_settlement()

## 为我方部队应用伤害（从 BattleResult 中提取 damages）
func _apply_player_damages(result: BattleResolver.BattleResult) -> void:
	var troop_index: int = 0
	for ch in _characters:
		if ch.has_troop():
			if troop_index < result.damages.size():
				ch.troop.take_damage(result.damages[troop_index])
				if ch.troop.is_defeated():
					ch.clear_troop()
			troop_index += 1

## 从敌方部队快照中随机抽取 1 支，转为 TROOP 道具加入背包
## 背包已满时直接丢弃
func _grant_troop_reward(troop_snapshot: Array[TroopData]) -> void:
	if troop_snapshot.is_empty():
		return
	# 随机抽取 1 支敌方部队
	var picked: TroopData = troop_snapshot[randi_range(0, troop_snapshot.size() - 1)]
	# 转为 TROOP 道具
	var item: ItemData = ItemData.new()
	item.type = ItemData.ItemType.TROOP
	item.troop_type = int(picked.troop_type)
	item.quality = int(picked.quality)
	item.display_name = picked.get_display_text()
	item.stack_count = 1
	# 尝试加入背包（满则丢弃）
	var added: int = _inventory.add_items([item])
	if added > 0:
		_show_notice("获得部队奖励：%s" % item.get_display_text())

## 发放当前待确认关卡的胜利奖励
func _grant_level_rewards() -> void:
	if _pending_level == null:
		return
	if not _pending_level.rewards.is_empty():
		var added: int = _inventory.add_items(_pending_level.rewards)
		var reward_text: String = _format_rewards_text(_pending_level.rewards)
		_show_notice("战斗胜利！获得奖励：%s" % reward_text)

## 战斗后共用处理：更新 HUD、失败判定、轮次推进
## 若处于敌方移动阶段的强制战斗，结算后继续处理移动队列
func _post_battle_settlement() -> void:
	_pending_full_result = null
	var defeated_level: bool = _pending_level != null and _pending_level.is_defeated()
	var was_forced: bool = _is_forced_battle
	_pending_level = null
	_is_forced_battle = false

	# 首次战斗完成后激活敌方移动能力
	if not _enemy_can_move and _enemy_movement_enabled:
		_enemy_can_move = true

	_update_hud()
	queue_redraw()

	# 判定失败条件：所有部队被击败即为游戏结束
	if _check_defeat():
		if was_forced:
			_finish_enemy_move_phase()
		return

	# 击败时才通知轮次管理器（击退不算通关进度）
	if defeated_level and _round_manager != null:
		var round_cleared: bool = _round_manager.on_level_cleared()
		_update_hud()
		if round_cleared:
			_grant_round_rewards()
			if not _round_manager.advance_round():
				# 全部轮次通关，即使在敌方移动阶段也直接结束
				if was_forced:
					_finish_enemy_move_phase()
				return
			_show_round_hint()
			if was_forced:
				_process_next_enemy_move()
			return

	# 敌方移动阶段中，继续处理下一个关卡
	if was_forced:
		_process_next_enemy_move()
	else:
		_refresh_reachable()

## 战斗取消按钮回调：关闭弹板，恢复输入
func _on_battle_cancelled() -> void:
	_battle_panel.visible = false
	_is_battle_pending = false
	_pending_level = null
	_pending_full_result = null
	_refresh_reachable()

# ─────────────────────────────────────────
# 装配管理 UI
# ─────────────────────────────────────────

## 程序化创建装配管理面板
func _create_manage_ui() -> void:
	var ui_layer: CanvasLayer = $UILayer

	_manage_panel = PanelContainer.new()
	_manage_panel.name = "ManagePanel"
	_manage_panel.visible = false
	# 固定尺寸居中显示
	_manage_panel.set_anchors_and_offsets_preset(
		Control.PRESET_CENTER, Control.PRESET_MODE_KEEP_SIZE
	)
	_manage_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_manage_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_manage_panel.custom_minimum_size = Vector2(420, 480)

	# 外层 VBox：标题 + 滚动区域 + 关闭按钮
	var outer_vbox: VBoxContainer = VBoxContainer.new()
	outer_vbox.add_theme_constant_override("separation", 8)

	# 标题
	var title: Label = Label.new()
	title.text = "装配管理"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(1.0, 0.92, 0.30))
	outer_vbox.add_child(title)

	var sep_top: HSeparator = HSeparator.new()
	sep_top.add_theme_constant_override("separation", 4)
	outer_vbox.add_child(sep_top)

	# 滚动容器（包裹所有内容，确保长列表可滚动）
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = "ManageScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 360)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.name = "ManageVBox"
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 6)

	# 角色状态区域
	var char_title: Label = Label.new()
	char_title.name = "CharTitleLabel"
	char_title.text = "部队状态"
	char_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	char_title.add_theme_color_override("font_color", Color(0.75, 0.85, 0.95))
	vbox.add_child(char_title)

	var char_label: Label = Label.new()
	char_label.name = "CharStatusLabel"
	char_label.text = ""
	vbox.add_child(char_label)

	var sep_char: HSeparator = HSeparator.new()
	sep_char.add_theme_constant_override("separation", 6)
	vbox.add_child(sep_char)

	# 背包区域
	var inv_title: Label = Label.new()
	inv_title.name = "InvTitleLabel"
	inv_title.text = "背包"
	inv_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inv_title.add_theme_color_override("font_color", Color(0.75, 0.85, 0.95))
	vbox.add_child(inv_title)

	var inv_label: Label = Label.new()
	inv_label.name = "InventoryLabel"
	inv_label.text = ""
	vbox.add_child(inv_label)

	var sep_inv: HSeparator = HSeparator.new()
	sep_inv.add_theme_constant_override("separation", 6)
	vbox.add_child(sep_inv)

	# 操作区域标题
	var op_title: Label = Label.new()
	op_title.name = "OpTitleLabel"
	op_title.text = "可用操作"
	op_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	op_title.add_theme_color_override("font_color", Color(0.75, 0.85, 0.95))
	vbox.add_child(op_title)

	# 操作按钮区域
	var op_vbox: VBoxContainer = VBoxContainer.new()
	op_vbox.name = "OperationArea"
	op_vbox.add_theme_constant_override("separation", 4)
	vbox.add_child(op_vbox)

	scroll.add_child(vbox)
	outer_vbox.add_child(scroll)

	# 底部分隔线 + 关闭按钮
	var sep_bottom: HSeparator = HSeparator.new()
	sep_bottom.add_theme_constant_override("separation", 4)
	outer_vbox.add_child(sep_bottom)

	var btn_close: Button = Button.new()
	btn_close.text = "关闭 [M]"
	btn_close.custom_minimum_size = Vector2(0, 32)
	btn_close.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	btn_close.add_theme_color_override("font_hover_color", Color(0.75, 0.75, 0.75))
	btn_close.pressed.connect(_on_manage_closed)
	outer_vbox.add_child(btn_close)

	_manage_panel.add_child(outer_vbox)
	ui_layer.add_child(_manage_panel)

## 打开装配管理面板
func _open_manage_panel() -> void:
	if _game_finished or _is_battle_pending or _is_moving:
		return
	_is_manage_open = true
	_refresh_manage_ui()
	_manage_panel.visible = true

## 关闭装配管理面板
func _on_manage_closed() -> void:
	_manage_panel.visible = false
	_is_manage_open = false
	_update_hud()
	_refresh_reachable()

## 刷新装配管理面板内容
func _refresh_manage_ui() -> void:
	if _manage_panel == null:
		return

	# 更新角色状态
	var char_label: Label = _manage_panel.find_child("CharStatusLabel", true, false) as Label
	if char_label != null:
		var lines: Array[String] = []
		for i in range(_characters.size()):
			var ch: CharacterData = _characters[i]
			if ch.has_troop():
				var t: TroopData = ch.troop
				var exp_info: String = ""
				var threshold: int = t.get_upgrade_threshold()
				if threshold > 0:
					exp_info = "  经验 %d/%d" % [t.exp, threshold]
				lines.append("  角色%d: %s  兵力 %d/%d%s" % [
					i + 1, t.get_display_text(), t.current_hp, t.max_hp, exp_info
				])
			else:
				lines.append("  角色%d: 空" % (i + 1))
		char_label.text = "\n".join(lines)

	# 更新背包标题（含容量）
	var inv_title: Label = _manage_panel.find_child("InvTitleLabel", true, false) as Label
	if inv_title != null:
		inv_title.text = "背包 (%d/%d)" % [_inventory.get_used_slots(), _inventory.max_capacity]

	# 更新背包内容
	var inv_label: Label = _manage_panel.find_child("InventoryLabel", true, false) as Label
	if inv_label != null:
		if _inventory.get_used_slots() == 0:
			inv_label.text = "  背包为空"
		else:
			var item_lines: Array[String] = []
			for item in _inventory.get_items():
				if item.stack_count > 1:
					item_lines.append("  · %s ×%d" % [item.get_display_text(), item.stack_count])
				else:
					item_lines.append("  · %s" % item.get_display_text())
			inv_label.text = "\n".join(item_lines)

	# 重建操作按钮区域（移除旧容器，创建新容器，避免 queue_free 延迟问题）
	var old_op_area: VBoxContainer = _manage_panel.find_child("OperationArea", true, false) as VBoxContainer
	if old_op_area != null:
		var parent_vbox: VBoxContainer = old_op_area.get_parent() as VBoxContainer
		var op_index: int = old_op_area.get_index()
		parent_vbox.remove_child(old_op_area)
		old_op_area.queue_free()

		var op_area: VBoxContainer = VBoxContainer.new()
		op_area.name = "OperationArea"
		parent_vbox.add_child(op_area)
		# 将操作区域移到原来的位置
		parent_vbox.move_child(op_area, op_index)

		var button_count: int = 0

		# 为每个角色生成可用操作
		for i in range(_characters.size()):
			var ch: CharacterData = _characters[i]

			# 角色标识
			var ch_name: String = "角色%d" % (i + 1)
			var ch_troop_text: String = ch.troop.get_display_text() if ch.has_troop() else "空"

			# 空槽位 + 背包有部队道具 → 显示装配按钮
			if not ch.has_troop():
				var troop_items: Array[ItemData] = _inventory.get_items_by_type(ItemData.ItemType.TROOP)
				for item in troop_items:
					var card: VBoxContainer = _create_op_card(
						ch_name, "", "空槽位",
						"装配 %s" % item.get_display_text(),
						Color(0.45, 0.80, 0.50)
					)
					var btn: Button = card.get_child(1) as Button
					btn.pressed.connect(_on_equip_troop.bind(ch, item))
					op_area.add_child(card)
					button_count += 1
			else:
				var t: TroopData = ch.troop
				# 已装配 → 显示替换按钮
				var troop_items: Array[ItemData] = _inventory.get_items_by_type(ItemData.ItemType.TROOP)
				for item in troop_items:
					var card: VBoxContainer = _create_op_card(
						ch_name, ch_troop_text, "兵力 %d/%d" % [t.current_hp, t.max_hp],
						"替换为 %s（丢弃当前）" % item.get_display_text(),
						Color(0.95, 0.75, 0.45)
					)
					var btn: Button = card.get_child(1) as Button
					btn.pressed.connect(_on_equip_troop.bind(ch, item))
					op_area.add_child(card)
					button_count += 1

				# 经验道具
				var exp_threshold: int = t.get_upgrade_threshold()
				var exp_status: String = "经验 %d/%d" % [t.exp, exp_threshold] if exp_threshold > 0 else "已满级"
				var exp_items: Array[ItemData] = _inventory.get_items_by_type(ItemData.ItemType.EXP)
				for item in exp_items:
					if item.can_use_on(t):
						var card: VBoxContainer = _create_op_card(
							ch_name, ch_troop_text, exp_status,
							"使用 %s" % item.get_display_text(),
							Color(0.65, 0.80, 0.95)
						)
						var btn: Button = card.get_child(1) as Button
						btn.pressed.connect(_on_use_item.bind(ch, item))
						op_area.add_child(card)
						button_count += 1

				# 兵力恢复道具
				var hp_items: Array[ItemData] = _inventory.get_items_by_type(ItemData.ItemType.HP_RESTORE)
				for item in hp_items:
					if item.can_use_on(t):
						var card: VBoxContainer = _create_op_card(
							ch_name, ch_troop_text, "兵力 %d/%d" % [t.current_hp, t.max_hp],
							"使用 %s" % item.get_display_text(),
							Color(0.50, 0.85, 0.50)
						)
						var btn: Button = card.get_child(1) as Button
						btn.pressed.connect(_on_use_item.bind(ch, item))
						op_area.add_child(card)
						button_count += 1

		# 无可用操作时显示提示
		if button_count == 0:
			var hint: Label = Label.new()
			hint.text = "（当前无可用操作）"
			hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			hint.add_theme_color_override("font_color", Color(0.50, 0.50, 0.50))
			op_area.add_child(hint)


## 创建操作卡片（上方角色/兵种/状态信息 + 下方操作按钮）
## char_name: 角色名称（如 "角色1"）
## troop_name: 兵种显示名（如 "剑兵(R)"），空槽位传空字符串
## status: 数值状态（如 "兵力 15/20"）
## action: 操作描述文字
## color: 按钮颜色
func _create_op_card(char_name: String, troop_name: String, status: String, action: String, color: Color) -> VBoxContainer:
	var card: VBoxContainer = VBoxContainer.new()
	card.add_theme_constant_override("separation", 1)
	# 角色 + 兵种 + 状态信息行
	var info_hbox: HBoxContainer = HBoxContainer.new()
	info_hbox.add_theme_constant_override("separation", 4)
	# 角色名称（暖白醒目）
	var name_label: Label = Label.new()
	name_label.text = char_name
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.add_theme_color_override("font_color", Color(0.85, 0.82, 0.75))
	info_hbox.add_child(name_label)
	# 兵种名（金色凸显）
	if troop_name != "":
		var troop_label: Label = Label.new()
		troop_label.text = troop_name
		troop_label.add_theme_font_size_override("font_size", 13)
		troop_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.45))
		info_hbox.add_child(troop_label)
	# 数值状态（灰色辅助）
	if status != "":
		var status_label: Label = Label.new()
		status_label.text = status
		status_label.add_theme_font_size_override("font_size", 13)
		status_label.add_theme_color_override("font_color", Color(0.55, 0.58, 0.55))
		info_hbox.add_child(status_label)
	card.add_child(info_hbox)
	# 操作按钮
	var btn: Button = Button.new()
	btn.text = "  %s" % action
	btn.custom_minimum_size = Vector2(0, 28)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.add_theme_color_override("font_color", color)
	btn.add_theme_color_override("font_hover_color", color.lightened(0.3))
	card.add_child(btn)
	return card

## 装配部队操作回调
func _on_equip_troop(character: CharacterData, item: ItemData) -> void:
	# 旧部队消失（不回收）
	# 创建新部队
	var troop: TroopData = TroopData.new()
	troop.troop_type = item.troop_type as TroopData.TroopType
	troop.quality = item.quality as TroopData.Quality
	# 兵力重置为最大值
	character.troop = troop
	# 从背包移除道具
	_inventory.remove_item(item)
	# 刷新面板
	_refresh_manage_ui()

## 使用道具操作回调（经验道具、兵力恢复道具）
func _on_use_item(character: CharacterData, item: ItemData) -> void:
	if not character.has_troop():
		return
	if item.type == ItemData.ItemType.EXP:
		var upgraded: bool = character.troop.add_exp(item.value)
	elif item.type == ItemData.ItemType.HP_RESTORE:
		var old_hp: int = character.troop.current_hp
		character.troop.current_hp = mini(
			character.troop.current_hp + item.value,
			character.troop.max_hp
		)
	# 从背包移除（可堆叠道具减少 1 个）
	_inventory.remove_item(item, 1)
	# 刷新面板
	_refresh_manage_ui()

# ─────────────────────────────────────────
# 击退冷却管理
# ─────────────────────────────────────────

## 递减所有击退关卡的冷却回合数，冷却结束则恢复为可交互
func _tick_repelled_cooldowns() -> void:
	for pos in _level_slots:
		var lv: LevelSlot = _level_slots[pos] as LevelSlot
		if lv.is_repelled():
			lv.tick_cooldown()
	queue_redraw()

# ─────────────────────────────────────────
# 玩家初始化
# ─────────────────────────────────────────

## 从 player_config 初始化多角色和部队
## 每个角色自动装配一支随机兵种、配置品质的部队
## 后续扩展接口：支持从角色池抽取、手动装配
func _init_player(player_cfg: Dictionary) -> void:
	var char_count: int = int(player_cfg.get("character_count", "3"))
	var init_quality: int = int(player_cfg.get("initial_troop_quality", "0"))

	_characters = []
	for i in range(char_count):
		var ch: CharacterData = CharacterData.new()
		ch.id = i + 1
		# 随机抽取兵种（0~4，可重复）
		var troop: TroopData = TroopData.new()
		troop.troop_type = randi_range(0, 4) as TroopData.TroopType
		troop.quality = init_quality as TroopData.Quality
		ch.troop = troop
		_characters.append(ch)


# ─────────────────────────────────────────
# 多角色辅助方法
# ─────────────────────────────────────────

## 判断是否有任意角色已装配部队
func _has_any_troop() -> bool:
	for ch in _characters:
		if ch.has_troop():
			return true
	return false

## 全灭检查：所有部队被击败时触发失败结算
## MVP 阶段强制收束，后续可扩展支持中途装配恢复
## 返回 true 表示已触发失败，调用方应中断后续流程
func _check_defeat() -> bool:
	if _game_finished:
		return true
	if not _has_any_troop():
		_game_finished = true
		_reachable_tiles = {}
		_show_defeat_text()
		queue_redraw()
		return true
	return false

## 获取所有已装配部队的部队列表（用于战斗结算）
func _get_active_troops() -> Array[TroopData]:
	var troops: Array[TroopData] = []
	for ch in _characters:
		if ch.has_troop():
			troops.append(ch.troop)
	return troops

# ─────────────────────────────────────────
# 奖励辅助方法
# ─────────────────────────────────────────

## 发放轮次胜利奖励
func _grant_round_rewards() -> void:
	if _round_manager == null:
		return
	var rewards: Array[ItemData] = _round_manager.get_round_rewards()
	if rewards.is_empty():
		return
	var added: int = _inventory.add_items(rewards)
	var reward_text: String = _format_rewards_text(rewards)
	_show_notice("轮次通关奖励：%s" % reward_text)


## 格式化奖励列表为显示文本
func _format_rewards_text(rewards: Array[ItemData]) -> String:
	var parts: Array[String] = []
	for item in rewards:
		if item.stack_count > 1:
			parts.append("%s×%d" % [item.get_display_text(), item.stack_count])
		else:
			parts.append(item.get_display_text())
	return ", ".join(parts)

# ─────────────────────────────────────────
# 放弃流程
# ─────────────────────────────────────────

## 放弃流程：直接结束，记为失败（无二次确认）
func _on_abandon() -> void:
	if _game_finished or _is_battle_pending or _is_moving or _is_manage_open:
		return
	_game_finished = true
	_reachable_tiles = {}
	_show_defeat_text()
	queue_redraw()


# ─────────────────────────────────────────
# 键盘快捷键处理（管理面板和放弃）
# ─────────────────────────────────────────

func _unhandled_key_input(event: InputEvent) -> void:
	# 敌方移动阶段锁定所有快捷键输入
	if _is_enemy_moving:
		return
	if event is InputEventKey:
		var key: InputEventKey = event as InputEventKey
		if key.pressed and not key.echo:
			# M 键：打开/关闭装配管理面板
			if key.keycode == KEY_M:
				if _is_manage_open:
					_on_manage_closed()
				else:
					_open_manage_panel()
			# Q 键：放弃流程
			elif key.keycode == KEY_Q:
				_on_abandon()

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

	# 第三层：敌方关卡移动动画标记
	if _moving_enemy_level != null:
		_draw_enemy_move_marker()

	# 第四层：单位标记（基于视觉位置）
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
		var pos: Vector2i = Vector2i(x, y)
		var level: LevelSlot = _get_level_at(pos)
		if level != null:
			# 正在移动的关卡跳过静态渲染（由 _draw_enemy_move_marker 负责）
			if level == _moving_enemy_level:
				return
			if level.is_defeated():
				# 已击败：变暗显示
				slot_color = slot_color.darkened(CHALLENGED_DIM)
			elif level.is_repelled():
				# 已击退冷却中：半透明显示
				slot_color = Color(slot_color.r, slot_color.g, slot_color.b, 0.4)
		var slot_rect: Rect2 = Rect2(
			x * TILE_SIZE + SLOT_MARGIN,
			y * TILE_SIZE + SLOT_MARGIN,
			TILE_SIZE - SLOT_MARGIN * 2 - 1,
			TILE_SIZE - SLOT_MARGIN * 2 - 1
		)
		draw_rect(slot_rect, slot_color)

## 绘制正在移动的敌方关卡标记（基于 _enemy_visual_pos 的动画位置）
func _draw_enemy_move_marker() -> void:
	var slot_color: Color = SLOT_COLORS.get(2, Color.WHITE) as Color  # FUNCTION 类型颜色
	var rect: Rect2 = Rect2(
		_enemy_visual_pos.x - TILE_SIZE / 2 + SLOT_MARGIN,
		_enemy_visual_pos.y - TILE_SIZE / 2 + SLOT_MARGIN,
		TILE_SIZE - SLOT_MARGIN * 2 - 1,
		TILE_SIZE - SLOT_MARGIN * 2 - 1
	)
	draw_rect(rect, slot_color)

## 绘制单位标记（基于视觉位置，支持动画中的平滑移动）
func _draw_unit_marker() -> void:
	var rect: Rect2 = Rect2(
		_unit_visual_pos.x - TILE_SIZE / 2 + UNIT_MARGIN,
		_unit_visual_pos.y - TILE_SIZE / 2 + UNIT_MARGIN,
		TILE_SIZE - UNIT_MARGIN * 2 - 1,
		TILE_SIZE - UNIT_MARGIN * 2 - 1
	)
	draw_rect(rect, UNIT_COLOR)
