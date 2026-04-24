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
##
## 子系统拆分：
##   EnemyMovement — 敌方关卡移动（队列/寻路/动画/强制战斗触发）
##   BattleUI — 战斗确认面板（预览/按钮/信号）
##   ManageUI — 装配管理面板（角色状态/背包/操作卡片）

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
const CONFIG_HP_RATIO: String = "res://assets/config/hp_ratio_config.csv"
const CONFIG_SUPPLY: String = "res://assets/config/supply_config.csv"
const CONFIG_ENEMY_TIER: String = "res://assets/config/enemy_tier_config.csv"
const CONFIG_ENEMY_TIER_RATIO: String = "res://assets/config/enemy_tier_ratio_config.csv"
const CONFIG_SCORE: String = "res://assets/config/score_config.csv"
const CONFIG_RESOURCE_SLOT: String = "res://assets/config/resource_slot_config.csv"
const CONFIG_BUILD: String = "res://assets/config/build_config.csv"
const CONFIG_TOWN_TROOP_POOL: String = "res://assets/config/town_troop_pool.csv"

# ─────────────────────────────────────────
# 渲染常量
# ─────────────────────────────────────────

## 每格像素尺寸（参见 Design/地图格子视觉规范.md）
const TILE_SIZE: int = 48

## 各地形渲染颜色（纯色块占位）
## key 使用整数字面量对应 MapSchema.TerrainType 枚举值
const TERRAIN_COLORS: Dictionary = {
	0: Color(0.40, 0.35, 0.30),  ## MOUNTAIN：灰褐：高山  #665949
	1: Color(0.50, 0.65, 0.30),  ## HIGHLAND：黄绿：高地  #80A64D
	2: Color(0.35, 0.72, 0.40),  ## FLATLAND：绿色：平地  #59B866
	3: Color(0.30, 0.55, 0.75),  ## LOWLAND：蓝色：洼地  #4D8CBF
}

## Slot 标记颜色（小方块叠加在地形色上）
## key 使用整数字面量对应 MapSchema.SlotType 枚举值（非敌方/资源用途的兜底色）
const SLOT_COLORS: Dictionary = {
	1: Color(1.00, 0.85, 0.00),  ## RESOURCE：金色  #FFD900
	2: Color(0.80, 0.40, 1.00),  ## FUNCTION：紫色（兜底，敌方格已覆盖为 ENEMY_SLOT_COLOR）
	3: Color(1.00, 0.30, 0.30),  ## SPAWN：红色  #FF4D4D
}

## Slot 标记在格内的边距（像素）
const SLOT_MARGIN: int = 10

## 可达范围高亮色（半透明白色叠加）
const REACHABLE_COLOR: Color = Color(1.0, 1.0, 1.0, 0.25)

## 单位标记颜色（亮白色，醒目区分地形）
const UNIT_COLOR: Color = Color(1.0, 1.0, 1.0)

## UI 重构步骤 3：单位描边 + 投影
## 描边让白底在浅色地形 / 可达高亮区不漂浮；投影营造棋子感
const UNIT_OUTLINE_COLOR: Color = Color(0.15, 0.15, 0.15)    ## 深灰描边  #262626
const UNIT_OUTLINE_WIDTH: float = 1.5                         ## 描边线宽
const UNIT_SHADOW_COLOR: Color = Color(0.0, 0.0, 0.0, 0.30)   ## 投影半透黑

## 单位标记边距（像素）
const UNIT_MARGIN: int = 8

## 已挑战关卡变暗系数（同一轮内已挑战但尚未切换的关卡）
const CHALLENGED_DIM: float = 0.4

## 敌方关卡底色（暗红，文字为主要信息载体）#CC4040
const ENEMY_SLOT_COLOR: Color = Color(0.80, 0.25, 0.25)

## 敌方关卡边框颜色（亮红，增强辨识度，兜底色）
const ENEMY_BORDER_COLOR: Color = Color(1.0, 0.25, 0.20, 0.8)

## 敌方关卡强度档位边框颜色（弱=绿, 中=黄, 强=红, 超=紫）
const TIER_BORDER_COLORS: Dictionary = {
	0: Color(0.35, 0.80, 0.35, 0.8),  ## 弱：绿色  #59CC59
	1: Color(0.90, 0.80, 0.20, 0.8),  ## 中：黄色  #E6CC33
	2: Color(1.00, 0.30, 0.25, 0.8),  ## 强：红色  #FF4D40
	3: Color(0.75, 0.35, 0.90, 0.8),  ## 超：紫色  #BF59E6
}

## 一次性资源点底色（按类型区分）
const RESOURCE_SUPPLY_COLOR: Color = Color(0.80, 0.27, 0.53)   ## 补给：品红  #CC4488（规避蓝绿色地形）
const RESOURCE_HP_COLOR: Color = Color(0.88, 0.47, 0.19)       ## 兵力：橙色  #E07830（规避绿色地形）
const RESOURCE_EXP_COLOR: Color = Color(0.60, 0.40, 0.80)      ## 经验：紫色  #9966CC（规避蓝色地形）
const RESOURCE_STONE_COLOR: Color = Color(0.55, 0.55, 0.60)    ## 石料：灰岩  #8C8C99（规避资源色相冲突）
# 注：M1 重构后 ResourceSlot 仅承载一次性产出，原"持久金色 + 范围金光叠加"颜色常量已移除；
# 持久 slot 视觉 / 影响范围覆盖层现走 M4 新常量（M4_FACTION_COLORS / M4_INFLUENCE_ALPHA）。

## 敌方关卡移动时的高亮颜色（亮红橙）
const ENEMY_MOVE_COLOR: Color = Color(1.0, 0.35, 0.20)

## 敌方关卡移动时的外圈光晕颜色
const ENEMY_GLOW_COLOR: Color = Color(1.0, 0.30, 0.15, 0.35)

## 击退冷却关卡边框颜色（暗淡）
const REPELLED_BORDER_COLOR: Color = Color(0.6, 0.3, 0.3, 0.5)

## 地图标签字号（格子放大后使用 12px）
const LABEL_FONT_SIZE: int = 12

## 持久 slot 等级角标字号（右上角 L0/1/2/3，小字与主 ID 分离）
const LEVEL_BADGE_FONT_SIZE: int = 9

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
# 子系统
# ─────────────────────────────────────────

## 敌方移动子系统
var _enemy_movement: EnemyMovement = null

## 战斗确认面板子系统
var _battle_ui: BattleUI = null

## 装配管理面板子系统
var _manage_ui: ManageUI = null

## 建造面板子系统（M5）
var _build_panel_ui: BuildPanelUI = null

## 敌方 AI（M7）
var _enemy_ai: EnemyAI = null

## 胜负遮罩 UI（M8）—— 核心城镇翻转时显示胜利 / 失败 + 重开按钮
var _victory_ui: VictoryUI = null

## 两方石料库存（M5）—— { Faction 整数 ID: int 数量 }
## 玩家侧由 build_config.player_initial_stone 初始化；
## 敌方侧由 enemy_initial_stone 初始化，M7 真正消耗前只占位
var _stone_by_faction: Dictionary = {}

# ─────────────────────────────────────────
# 私有状态
# ─────────────────────────────────────────

## 当前加载的地图数据
var _schema: MapSchema = null

## 本局共享的随机数生成器（M2 P1#4 修复）
## 由 _load_pcg 在确定 seed 后创建一次，所有运行时随机调用（关卡放置 / 资源点放置等）共享
## 保证"同 seed 同地图"覆盖完整运行时
var _world_rng: RandomNumberGenerator = null

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

## 补给系统（MVP 玩家全局补给数值；HUD 显示、移动消耗、扎营恢复均读写此字段）
## 语义偏差备忘（M6 审查 P2）：设计《持久slot基础功能设计》§"部队资源通道"要求补给
## 按扎营部队隔离；MVP 仅一个玩家单位，全局字段语义成立。后续若扩展多部队 / 多单位，
## 需要重构为"按部队 / 按扎营主体"的 ledger，此处是架构债锚点
var _supply: int = 3
var _camp_restore: int = 1

## 扎营状态标记
var _is_camping: bool = false

## 单局评分追踪
var _camp_count: int = 0
var _total_hp_lost: int = 0
var _total_max_hp: int = 0
var _score_config: Dictionary = {}

## 资源点字典 {Vector2i: ResourceSlot}
var _resource_slots: Dictionary = {}

## 资源点配置行数据（缓存）
var _resource_slot_config_rows: Array = []

## 击退冷却回合数配置
var _repel_cooldown_turns: int = 3

## 敌方移动开关（从配置读取）
var _enemy_movement_enabled: bool = false

## 敌方移动力（从配置读取）
var _enemy_movement_points: int = 6

## 敌方 AI 目标切换半径（曼哈顿距离）—— M8 扩展
## dist(pack, player) <= 该值 + d_player < d_core → pack 追玩家；否则推核心
## 默认 10（约为 enemy_movement_points*1.6，给 1-2 回合反应冗余）
var _enemy_target_switch_range: int = 10

## 敌方关卡占据位置的原始 SlotType（用于移动后恢复）
var _original_slot_types: Dictionary = {}

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

## 地图标签绘制用字体（_draw 时使用，_ready 中初始化）
var _label_font: Font = null

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

	# 加载兵力系数分段配置
	var hp_ratio_rows: Array = ConfigLoader.load_csv(CONFIG_HP_RATIO)
	BattleResolver.load_hp_ratio_config(hp_ratio_rows)

	# 加载补给配置
	var supply_cfg: Dictionary = ConfigLoader.load_csv_kv(CONFIG_SUPPLY)
	_supply = int(supply_cfg.get("initial_supply", "3"))
	_camp_restore = int(supply_cfg.get("camp_restore", "1"))

	# 加载敌人强度配置（generator 初始化后再注入，见下方）
	var enemy_tier_rows: Array = ConfigLoader.load_csv(CONFIG_ENEMY_TIER)

	# 加载评分配置
	_score_config = ConfigLoader.load_csv_kv(CONFIG_SCORE)

	# 加载资源点配置
	_resource_slot_config_rows = ConfigLoader.load_csv(CONFIG_RESOURCE_SLOT)

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

	# 审查 P2 修复：CSV 写坏时 int() 静默变 0 会让 AI 几乎永远推核心（阈值失效）
	# 显式校验：非法值（< 1）回退到默认 10 + push_warning 便于排障
	var raw_switch_range: int = int(_battle_config.get("enemy_target_switch_range", "10"))
	if raw_switch_range < 1:
		push_warning("WorldMap: battle_config.enemy_target_switch_range 非法值 %d，回退到 10" % raw_switch_range)
		_enemy_target_switch_range = 10
	else:
		_enemy_target_switch_range = raw_switch_range

	# 初始化奖励生成器
	_reward_generator = RewardGenerator.new()
	_reward_generator.load_item_templates(item_rows)

	# 初始化背包
	_inventory = Inventory.new()
	_inventory.init_from_config(inventory_cfg)

	# 初始化敌方部队生成器
	_enemy_generator = EnemyTroopGenerator.new()
	_enemy_generator.init_from_config(enemy_pool_rows, enemy_spawn_cfg)
	_enemy_generator.load_tier_config(enemy_tier_rows)

	# M6: 产出结算——城镇部队道具池走独立 CSV（不污染敌方生成权重）
	var town_pool_rows: Array = ConfigLoader.load_csv(CONFIG_TOWN_TROOP_POOL)
	if town_pool_rows.is_empty():
		push_error("WorldMap: town_troop_pool.csv 加载失败或为空；城镇 / 核心城镇产出会静默无输出")
	ProductionSystem.load_troop_pool(town_pool_rows)

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
	# M7：迁至阵营回合流程，监听 faction_turn_started 替代 legacy turn_ended
	# 玩家侧 handler 在本 handler 中处理；敌方侧由 EnemyAI 自己 connect
	_turn_manager.faction_turn_started.connect(_on_faction_turn_started)

	# M5: 加载升级配置 + 石料库存 + 注册建造 tick
	# 顺序固定：先 BuildSystem.load_level_config（tick 依赖配置），再 register
	BuildSystem.load_level_config(ConfigLoader.load_persistent_slot_config())
	var build_cfg: Dictionary = ConfigLoader.load_csv_kv(CONFIG_BUILD)
	_stone_by_faction = {
		Faction.PLAYER: int(build_cfg.get("player_initial_stone", "0")),
		Faction.ENEMY_1: int(build_cfg.get("enemy_initial_stone", "0")),
	}

	# 地图生成后字段装配（M2/M4 遗留缺口修复）：
	#   PersistentSlotGenerator._build_slot 只填 type / level / owner_faction，
	#   initial_range / max_range / growth_rate / influence_range 全留默认 0。
	#   核心城镇 L3 永不升级 → 影响范围永远不渲染；初始归属村庄/城镇同理。
	#   此处按每个 slot 的当前 level 从配置注入，让影响范围系统在首个回合前就位。
	# 依赖 BuildSystem.load_level_config 已完成（查 apply_level_fields 走 _level_config 读）
	if _schema != null:
		for entry in _schema.persistent_slots:
			var slot: PersistentSlot = entry as PersistentSlot
			if slot == null:
				continue
			BuildSystem.apply_level_fields(slot, slot.level)

	# ⚠ Tick 注册顺序固定：M5 → M4 → M7 REPELLED（TickRegistry 按 FIFO 执行）
	# 自阵营回合开始时先跑 M5 建造完成（可能刷 max_range），
	# 再跑 M4 占据快照（用新 max_range 增长），最后跑 M7 REPELLED 冷却递减
	TickRegistry.register(_on_build_tick)

	# M4: 注册占据快照到 TickRegistry（自阵营回合开始锚点）
	# M7 迁移后：WorldMap 完全走 start_faction_turn，TickRegistry 自动分发；无需手动 run_ticks
	TickRegistry.register(_on_faction_tick)

	# M7: REPELLED 冷却 tick（仅 ENEMY_1 回合生效，内部 faction 过滤）
	TickRegistry.register(_tick_repelled_cooldowns)

	# Camera 初始位置直接设到单位位置（首帧不需要平滑）
	_camera.position = _unit_visual_pos

	# 初始化子系统
	_init_subsystems()

	# 启动第一轮（触发 _on_round_started → 生成资源点 + 预生成轮次奖励；M7 后不再生成敌方关卡）
	_round_manager.start_current_round()

	# 初始化地图标签字体（使用主题默认字体，供 _draw 中绘制文字标注）
	_label_font = ThemeDB.fallback_font

	# M7：开局预置 5 支敌方部队包（在敌方核心影响范围内随机空地）
	# 必须在 start_current_round 之后（资源点已铺好、避免位置冲突）+ 首个玩家回合开始之前
	_deploy_initial_enemy_packs()

	# M7：启动首个玩家回合（TickRegistry 跑 M4/M5 tick → emit faction_turn_started(PLAYER)
	# → _on_faction_turn_started 接管 HUD / reachable 刷新）
	_turn_manager.start_faction_turn(Faction.PLAYER)


## M7 开局预置敌方部队包（敌方 AI 设计 §3.1）
## MVP 初始 5 支；调用 EnemyReinforcement.spawn_batch 5 次，每次生成 1 支
## 若核心影响范围内空地不足 5 个，能放几支放几支（不强制）
func _deploy_initial_enemy_packs() -> void:
	var target_count: int = 5
	var placed: int = 0
	for i in range(target_count):
		var pack: LevelSlot = EnemyReinforcement.spawn_batch(self)
		if pack != null:
			placed += 1
	if placed < target_count:
		push_warning("WorldMap._deploy_initial_enemy_packs: 仅预置 %d / %d 支（核心影响范围空地不足）" % [placed, target_count])


## 场景退出时清理全局注册，避免 TickRegistry 残留悬空 Callable
## 重要性：TickRegistry._handlers 是 static，跨场景共享；不清理会在下次进入
## 场景时触发已释放的 handler 导致 Callable.is_valid() == false 被跳过，
## 看似无害但会堆积僵尸 handler
##
## M8 追加：VictoryJudge 同样走静态沉降 Callable，重开时必须 clear_sink
## 否则旧场景的 _on_victory_decided 会在新场景中被错误调用
func _exit_tree() -> void:
	TickRegistry.unregister(_on_faction_tick)
	TickRegistry.unregister(_on_build_tick)
	TickRegistry.unregister(_tick_repelled_cooldowns)
	VictoryJudge.clear_sink()


## 初始化子系统（敌方移动、战斗 UI、管理 UI）
func _init_subsystems() -> void:
	var ui_layer: CanvasLayer = $UILayer

	# 敌方移动子系统（注入格子尺寸，保证视觉位置计算与 WorldMap 一致）
	_enemy_movement = EnemyMovement.new()
	_enemy_movement.name = "EnemyMovement"
	_enemy_movement.tile_size = TILE_SIZE
	add_child(_enemy_movement)
	_enemy_movement.phase_finished.connect(_on_enemy_phase_finished)
	_enemy_movement.forced_battle_triggered.connect(_on_forced_battle_triggered)
	_enemy_movement.redraw_requested.connect(queue_redraw)

	# 战斗确认面板子系统
	_battle_ui = BattleUI.new()
	_battle_ui.name = "BattleUI"
	add_child(_battle_ui)
	_battle_ui.init_config(_repel_player_damage_rate, _repel_enemy_damage_rate)
	_battle_ui.create_ui(ui_layer)
	_battle_ui.repel_chosen.connect(_on_battle_repel_chosen)
	_battle_ui.defeat_chosen.connect(_on_battle_defeat_chosen)
	_battle_ui.cancelled.connect(_on_battle_cancelled)

	# 装配管理面板子系统
	_manage_ui = ManageUI.new()
	_manage_ui.name = "ManageUI"
	add_child(_manage_ui)
	_manage_ui.create_ui(ui_layer)
	_manage_ui.closed.connect(_on_manage_closed)
	_manage_ui.equip_requested.connect(_on_equip_troop)
	_manage_ui.use_item_requested.connect(_on_use_item)

	# 建造面板子系统（M5）
	_build_panel_ui = BuildPanelUI.new()
	_build_panel_ui.name = "BuildPanelUI"
	add_child(_build_panel_ui)
	_build_panel_ui.create_ui(ui_layer)
	_build_panel_ui.closed.connect(_on_build_panel_closed)
	_build_panel_ui.upgrade_requested.connect(_on_upgrade_requested)

	# 敌方 AI（M7）
	_enemy_ai = EnemyAI.new()
	_enemy_ai.name = "EnemyAI"
	add_child(_enemy_ai)
	_enemy_ai.init(self, _turn_manager)

	# 胜负遮罩 UI（M8）
	# 挂载顺序放在所有 UI 面板之后，保证遮罩渲染在最上层（吸收点击）
	_victory_ui = VictoryUI.new()
	_victory_ui.name = "VictoryUI"
	add_child(_victory_ui)
	_victory_ui.create_ui(ui_layer)
	_victory_ui.restart_pressed.connect(_on_restart_pressed)

	# M8：注册胜负回调；OccupationSystem.try_occupy 翻转核心城镇时触发
	# reload_current_scene 后新的 _ready 会重新注册，_exit_tree 会 clear_sink 避免悬空
	VictoryJudge.register_sink(_on_victory_decided)

# ─────────────────────────────────────────
# 输入处理
# ─────────────────────────────────────────

func _input(event: InputEvent) -> void:
	# 动画播放中、战斗确认中、敌方移动中、管理面板打开中、扎营中、建造面板打开中或流程结束时锁定所有输入
	if _game_finished or _is_moving or _battle_ui.is_pending or _manage_ui.is_open or _enemy_movement.is_moving() or _is_camping or _build_panel_ui.is_open:
		return

	# 鼠标左键点击：移动单位（需要补给 > 0）
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_handle_click(mb.position)

	# 空格键：扎营（触发扎营流程）
	if event is InputEventKey:
		var key: InputEventKey = event as InputEventKey
		if key.pressed and not key.echo and key.keycode == KEY_SPACE:
			_start_camp()

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

	# 左区：轮次 / 关卡 / 回合 / 补给
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
	round_parts.append("回合 %d" % _turn_manager.player_faction_turn_count)
	round_parts.append("补给 %d" % _supply)
	# M5: 石料数字（玩家侧）
	round_parts.append("石料 %d" % get_stone(Faction.PLAYER))
	if _hud_round != null:
		_hud_round.text = "  ".join(round_parts)

	# 中区：部队状态
	if _hud_troop != null:
		_hud_troop.text = _get_all_troops_display()

	# 右区：快捷键提示
	if _hud_keys != null:
		_hud_keys.text = "[空格]扎营  [B]建造  [M]管理  [Q]放弃"

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

## 获取评分摘要文本
func _get_score_text() -> String:
	var result: Dictionary = ScoreCalculator.calculate(
		_camp_count, _total_hp_lost, _total_max_hp, _score_config
	)
	return "评分 %d（扎营%d次 效率%.0f%% | 损兵%d 存活%.0f%%）" % [
		int(result["score"]),
		_camp_count,
		float(result["efficiency"]) * 100.0,
		_total_hp_lost,
		float(result["survival"]) * 100.0,
	]

## 显示流程胜利提示（含评分）
func _show_victory_text() -> void:
	if _finish_label == null or _turn_manager == null:
		return
	var total_rounds: int = _round_manager.get_total_rounds() if _round_manager != null else 1
	_finish_label.text = "全部 %d 轮通关！流程胜利（回合 %d）\n%s" % [
		total_rounds, _turn_manager.player_faction_turn_count, _get_score_text()
	]
	if _notice_bar != null:
		_notice_bar.visible = true

## 显示流程失败提示（含评分）
func _show_defeat_text() -> void:
	if _finish_label == null or _turn_manager == null:
		return
	_finish_label.text = "流程失败（回合 %d）\n%s" % [
		_turn_manager.player_faction_turn_count, _get_score_text()
	]
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

	# 消耗 1 补给
	_supply = maxi(0, _supply - 1)

	# 检查当前位置是否有一次性资源点并采集
	_try_collect_resource_at(_unit.position)

	# 全灭检查（战斗后部队全灭但玩家仍可移动的情况）
	if _check_defeat():
		return

	# 检查当前位置是否有可交互的关卡 Slot
	var level: LevelSlot = _get_level_at(_unit.position)
	if level != null and level.is_interactable():
		# 有任意角色装配了部队时弹出战斗预览
		# 有战斗即 return；try_occupy 由战斗胜利后 _post_battle_settlement 触发
		if _has_any_troop():
			_battle_ui.show_confirm(level, _get_active_troops(),
				_battle_config, _damage_increment, false)
			return

	# M4: 无战斗分支 —— 若停留格有持久 slot，尝试占据（§6.5 边界：格上无敌方单位）
	_try_player_occupy_at(_unit.position)

	# 每次移动后重置移动力，为下一次移动做准备
	_unit.current_movement = _unit.max_movement

	_update_hud()
	# 刷新可达范围（补给为 0 时会显示空集）
	_refresh_reachable()

## 刷新可达范围并触发重绘
## 补给为 0 时不显示可达格；击退状态的关卡格视为不可通行
func _refresh_reachable() -> void:
	if _unit != null and _schema != null and not _game_finished and _supply > 0:
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

## M7 阵营回合开始回调（玩家侧）
## 由 TurnManager.start_faction_turn(PLAYER) 触发，在 TickRegistry 跑完 M4 快照 / M5 建造 tick 后执行
## 职责：重置玩家单位移动力、刷新 HUD、刷新可达范围
##
## 敌方侧（ENEMY_1）由 EnemyAI._on_faction_turn_started 独立处理，两个 handler 按 faction 分流互不干扰
func _on_faction_turn_started(faction: int) -> void:
	if faction != Faction.PLAYER:
		return
	# 玩家回合开始：重置单位移动力
	_unit.current_movement = _unit.max_movement
	_update_hud()
	_refresh_reachable()


## M4 自阵营回合 tick 回调：快照本势力所属 slot 的 garrison / occupy / influence 状态
## 由 TickRegistry 在 TurnManager.start_faction_turn 中自动触发（M7 迁移后）
func _on_faction_tick(faction: int) -> void:
	if _schema == null:
		return
	var units_by_pos: Dictionary = _build_units_by_pos()
	OccupationSystem.snapshot_turn_end(faction, _schema.persistent_slots, units_by_pos)
	queue_redraw()


## 构建 { Vector2i: 势力 ID } 字典，用于快照的驻扎判定
## MVP 只含两类单位：玩家唯一单位 + UNCHALLENGED 敌方关卡
##
## REPELLED / DEFEATED 的敌方格**不算驻扎单位**（P1 审查项决议）：
##   REPELLED 虽仍占据物理格子（阻挡移动，见 _get_blocked_positions），
##   但该敌方部队已退场（不能战斗、不产出），语义上是"空壳占格"；
##   DEFEATED 则直接从 _level_slots 清除或标 is_defeated，更无驻扎意义。
## 故两者均不计入驻扎判定，对应格子按"无单位"参与 snapshot_turn_end 结算。
func _build_units_by_pos() -> Dictionary:
	var out: Dictionary = {}
	if _unit != null:
		out[_unit.position] = Faction.PLAYER
	for pos in _level_slots:
		var lv: LevelSlot = _level_slots[pos] as LevelSlot
		if lv.state == LevelSlot.State.UNCHALLENGED:
			out[pos] = Faction.ENEMY_1
	return out


## 按坐标查找 PersistentSlot；未命中返回 null
## MVP 总量 26，线性扫描开销可忽略
func _find_persistent_slot_at(pos: Vector2i) -> PersistentSlot:
	if _schema == null:
		return null
	for entry in _schema.persistent_slots:
		var ps: PersistentSlot = entry as PersistentSlot
		if ps.position == pos:
			return ps
	return null


## 玩家在 pos 尝试占据持久 slot（移动结束 / 战斗胜利后调用）
## 返回是否发生归属翻转；翻转后触发重绘以刷新影响范围覆盖
func _try_player_occupy_at(pos: Vector2i) -> bool:
	var ps: PersistentSlot = _find_persistent_slot_at(pos)
	if ps == null:
		return false
	var flipped: bool = OccupationSystem.try_occupy(ps, Faction.PLAYER)
	if flipped:
		queue_redraw()
	return flipped


# ─────────────────────────────────────────
# M5 石料库存 + 建造系统
# ─────────────────────────────────────────

## 查询指定势力当前石料数量
func get_stone(faction: int) -> int:
	return int(_stone_by_faction.get(faction, 0))


## 增加指定势力的石料（产出 / 奖励入账时调用；M6 产出结算会用）
func add_stone(faction: int, amount: int) -> void:
	if amount <= 0:
		return
	_stone_by_faction[faction] = get_stone(faction) + amount
	_update_hud()


## 尝试扣除指定势力的石料，返回是否成功
## 石料不足时不扣除、不修改字典
func try_spend_stone(faction: int, amount: int) -> bool:
	if amount < 0:
		return false
	var current: int = get_stone(faction)
	if current < amount:
		return false
	_stone_by_faction[faction] = current - amount
	_update_hud()
	return true


## 自阵营回合开始 tick 回调（M5）：推进所有本方 slot 的在建动作
## 注册到 TickRegistry；由 TurnManager.start_faction_turn 自动触发（双方阵营均适用）
## 注：本 handler 先于 M4 `_on_faction_tick` 执行（见 _ready 中的注册顺序锚点），
##     保证"升级完成后 max_range 抬升 → 同回合 M4 快照用新上限增长"
func _on_build_tick(faction: int) -> void:
	if _schema == null:
		return
	for entry in _schema.persistent_slots:
		var slot: PersistentSlot = entry as PersistentSlot
		if slot == null:
			continue
		# 自阵营过滤：仅推进本方 slot（和 M4 过滤同口径）
		if slot.owner_faction != faction:
			continue
		if slot.active_build == null:
			continue
		var finished: bool = BuildSystem.advance_tick(slot)
		# notice 文案带坐标，多 slot 同回合完成时可辨识
		# 敌方完成故意不提示（MVP 有意静默，M7 接入时再决策是否加侦察/情报反馈）
		if finished and faction == Faction.PLAYER:
			var id_text: String = slot.display_id if slot.display_id != "" else slot.get_type_name()
			_show_notice("%s 升级至 L%d" % [id_text, slot.level])
	queue_redraw()


## 打开建造面板
## 列表内容：所有归属于 PLAYER 的持久 slot
func _open_build_panel() -> void:
	if _game_finished or _battle_ui.is_pending or _is_moving or _manage_ui.is_open or _is_camping:
		return
	_build_panel_ui.open(_get_player_persistent_slots(), get_stone(Faction.PLAYER))


## 建造面板关闭回调
## 关闭不推进回合（和 ManageUI 非扎营模式同语义）
func _on_build_panel_closed() -> void:
	_update_hud()
	_refresh_reachable()


## 升级请求回调（BuildPanelUI 按钮点击）
## 流程：再校验 can_upgrade → 扣石料 → BuildSystem.start_upgrade → notice + 刷新面板
## 面板按钮 disabled 已做一层校验，这里再做是防御（避免异步状态不一致）
func _on_upgrade_requested(slot: PersistentSlot) -> void:
	if not BuildSystem.can_upgrade(slot, Faction.PLAYER):
		_show_notice("无法升级该 slot")
		return
	var cost: int = BuildSystem.get_upgrade_cost(slot)
	if not try_spend_stone(Faction.PLAYER, cost):
		_show_notice("石料不足")
		return
	if not BuildSystem.start_upgrade(slot, Faction.PLAYER):
		# 理论不可达（can_upgrade 已通过）；石料已扣，退回
		add_stone(Faction.PLAYER, cost)
		_show_notice("启动升级失败")
		return
	var start_id_text: String = slot.display_id if slot.display_id != "" else slot.get_type_name()
	_show_notice("%s 开始升级 → L%d" % [start_id_text, slot.level + 1])
	# 面板仍打开：刷新显示
	if _build_panel_ui.is_open:
		_build_panel_ui.refresh(_get_player_persistent_slots(), get_stone(Faction.PLAYER))
	queue_redraw()


## 获取当前归属于 PLAYER 的所有持久 slot
func _get_player_persistent_slots() -> Array[PersistentSlot]:
	var result: Array[PersistentSlot] = []
	if _schema == null:
		return result
	for entry in _schema.persistent_slots:
		var slot: PersistentSlot = entry as PersistentSlot
		if slot == null:
			continue
		if slot.owner_faction == Faction.PLAYER:
			result.append(slot)
	return result


## 扎营入口：恢复补给 → 资源点结算 → 打开养成面板
func _start_camp() -> void:
	if _game_finished or _is_moving or _battle_ui.is_pending or _is_camping or _manage_ui.is_open or _build_panel_ui.is_open:
		return
	_is_camping = true
	_camp_count += 1

	# 扎营恢复补给
	_supply += _camp_restore

	# M6: 持久 slot 扎营结算（玩家侧）
	# 流程：camp_pos 查 C 作用域覆盖 → 逐 slot 按类型 × 等级产出 → 落地到石料 / 补给 / 背包
	_settle_persistent_camp_production()

	_update_hud()

	# 打开养成面板（camp_mode = true，显示全部操作）
	_manage_ui.open(_characters, _inventory, true)


## M6 扎营结算：ProductionSystem.settle_camp + apply_production + 飘字
## RNG 使用 _world_rng 保证同 seed 运行结果可复现
## 背包满 / 池空等失败条目另行通过 format_dropped_text 提示，避免"飘字说获得实际没有"的误导
func _settle_persistent_camp_production() -> void:
	if _schema == null or _unit == null:
		return
	var results: Array = ProductionSystem.settle_camp(
		_unit.position, Faction.PLAYER, _schema.persistent_slots, _world_rng
	)
	if results.is_empty():
		return
	var add_supply: Callable = func(amount: int) -> void: _supply += amount
	var add_stone_cb: Callable = func(amount: int) -> void: add_stone(Faction.PLAYER, amount)
	# 背包入库返回是否成功（满时返回 false 供 apply_production 归 dropped）
	var add_item_cb: Callable = func(item: ItemData) -> bool:
		var n: int = _inventory.add_items([item])
		return n > 0
	var outcome: Dictionary = ProductionSystem.apply_production(
		results, add_supply, add_stone_cb, add_item_cb
	)

	var applied: Array = outcome.get("applied", []) as Array
	var dropped: Array = outcome.get("dropped", []) as Array
	if not applied.is_empty():
		_show_notice("扎营产出：%s" % ProductionSystem.format_results_text(applied))
	if not dropped.is_empty():
		_show_notice("扎营产出部分失败：%s" % ProductionSystem.format_dropped_text(dropped))

## 尝试采集当前位置的一次性资源点（M6 改造）
## 采集走 M6 等权池：忽略 slot 自身 resource_type / output_amount 配置，
## 统一按 4 项等权随机抽 × 1/2 等权数量。视觉上 slot 仍按生成类型显示（盲盒式）
## 备忘：视觉与采集结果的对齐是后续 UX 回看项，不在 M6 范围内
func _try_collect_resource_at(pos: Vector2i) -> void:
	if not _resource_slots.has(pos):
		return
	var rs: ResourceSlot = _resource_slots[pos] as ResourceSlot
	if rs.is_collected:
		return
	# M6 等权抽取（单条产出结构）；注入 _world_rng 保证同 seed 复现
	var entry: Dictionary = ProductionSystem.collect_immediate_slot(_world_rng)
	var add_supply: Callable = func(amount: int) -> void: _supply += amount
	var add_stone_cb: Callable = func(amount: int) -> void: add_stone(Faction.PLAYER, amount)
	var add_item_cb: Callable = func(item: ItemData) -> bool:
		var n: int = _inventory.add_items([item])
		return n > 0
	var outcome: Dictionary = ProductionSystem.apply_production(
		[entry], add_supply, add_stone_cb, add_item_cb
	)

	rs.is_collected = true
	if _schema != null:
		_schema.set_slot(pos.x, pos.y, MapSchema.SlotType.NONE)

	var applied: Array = outcome.get("applied", []) as Array
	var dropped: Array = outcome.get("dropped", []) as Array
	if not applied.is_empty():
		_show_notice("采集资源：%s" % ProductionSystem.format_results_text(applied))
	if not dropped.is_empty():
		_show_notice("采集失败：%s" % ProductionSystem.format_dropped_text(dropped))
	queue_redraw()

## 玩家回合结束结算流程（M7 迁移）
## 扎营养成确认后调用：发放奖励 → 触发敌方阵营回合（TurnManager.start_faction_turn）
##
## M7 前的 legacy 流程：直接调 _enemy_movement.start_phase 或 end_turn
## M7 新流程：end_faction_turn(PLAYER) → start_faction_turn(ENEMY_1) → EnemyAI 六步 → 回到 PLAYER
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
			_inventory.add_items(rewards)
			var reward_text: String = _format_rewards_text(rewards)
			_show_notice("回合奖励：%s" % reward_text)

	# M7 敌方回合触发：end 当前（PLAYER）+ start ENEMY_1
	# start_faction_turn 内部会：TickRegistry.run_ticks（建造 tick / REPELLED 冷却 tick）→ 计数 +1 → emit signal
	# signal 被 EnemyAI 接收，执行六步 2-5（步骤 1 已由 TickRegistry 完成）
	#
	# enemy_movement_enabled == false（调试开关）：
	#   仍必须调 start_faction_turn(ENEMY_1) 让 TickRegistry 跑敌方建造 tick / REPELLED 冷却 tick，
	#   否则敌方状态冻结；只短路移动阶段（由 start_enemy_move_phase 内部检查开关提前 phase_finished）
	_turn_manager.end_faction_turn()
	_turn_manager.current_faction = Faction.ENEMY_1
	_turn_manager.start_faction_turn(Faction.ENEMY_1)


# ─────────────────────────────────────────
# 敌方 AI 协作接口
# ─────────────────────────────────────────

## 启动敌方移动阶段（由 EnemyAI._step_move_phase 调用）
## 判定是否有可移动的敌方部队 + 玩家核心 target 是否存在
## 无可移动 / 无 target → 直接触发 phase_finished（走 _on_enemy_phase_finished → 回 PLAYER）
func start_enemy_move_phase() -> void:
	if _game_finished or not _enemy_movement_enabled:
		_on_enemy_phase_finished()
		return
	# M7 MVP：target 为玩家核心 persistent slot 位置
	var target_pos: Vector2i = _get_player_core_pos()
	if target_pos == Vector2i(-1, -1):
		# M8 接入：玩家核心已失守 → 触发失败兜底
		# 正常路径下 VictoryJudge 已在上一个敌方回合占据核心时触发 _on_victory_decided；
		# 走到这里说明状态异常（VictoryJudge 未注册 / 重开后残留 / 核心初始化失败），
		# 按失败处理 + 立刻结束 phase，避免敌方继续移动造成错乱
		#
		# 审查 P2 修复：用 push_error 而非 push_warning，明确这是异常状态下的降级处理，
		# 便于从日志识别上游 bug（理论上不应触发）
		push_error("WorldMap.start_enemy_move_phase: 玩家核心 persistent slot 未找到（异常态，降级判负）；检查 VictoryJudge 注册 / 核心生成流程")
		_on_victory_decided(Faction.ENEMY_1)
		_on_enemy_phase_finished()
		return
	_enemy_movement.start_phase(
		_schema, _level_slots, _unit.position, target_pos,
		_enemy_movement_points, _original_slot_types, _game_finished,
		_enemy_target_switch_range
	)


# ─────────────────────────────────────────
# M8 胜负判定回调
# ─────────────────────────────────────────

## 胜负判定沉降回调（由 VictoryJudge.check_on_slot_owner_changed 触发）
## winner_faction —— 胜利方势力 ID（翻转后占据核心城镇的势力）
##
## 职责：
##   - 标记 _game_finished = true 阻断后续输入 / 敌方移动 / tick
##   - 清空可达高亮（视觉冻结）
##   - 弹出 VictoryUI 全屏遮罩（带评分 / 回合数副标题）
##
## 幂等性：
##   VictoryJudge._finished 已拦截重复触发；本函数仍做 _game_finished 双保险，
##   避免未来新增触发源（如手动 debug 调用）时重入
func _on_victory_decided(winner_faction: int) -> void:
	if _game_finished:
		return
	_game_finished = true
	_reachable_tiles = {}

	# 敌方移动阶段中触发时，通知 EnemyMovement 在下一次 _process_next_move 提前收场
	# 避免后续部队包还在往玩家核心推进
	if _enemy_movement != null:
		_enemy_movement.notify_game_over()

	queue_redraw()

	var turn_count: int = 0
	if _turn_manager != null:
		turn_count = _turn_manager.player_faction_turn_count
	var subtitle: String = "回合 %d  |  %s" % [turn_count, _get_score_text()]
	if winner_faction == Faction.PLAYER:
		if _victory_ui != null:
			_victory_ui.show_victory(subtitle)
	else:
		if _victory_ui != null:
			_victory_ui.show_defeat(subtitle)


## 重开按钮回调（VictoryUI.restart_pressed）
## MVP 策略：直接重载当前场景 —— 最干净的 reset，
## TickRegistry / BuildSystem / VictoryJudge 的静态态由 _exit_tree + 新 _ready 的 load_config 覆盖
func _on_restart_pressed() -> void:
	get_tree().reload_current_scene()


# ─────────────────────────────────────────
# 敌方 AI 协作辅助
# ─────────────────────────────────────────

## 查找玩家核心 persistent slot 的位置
## 返回 (-1, -1) 表示未找到（场景初始化未完成或核心已被敌方占据）
func _get_player_core_pos() -> Vector2i:
	if _schema == null:
		return Vector2i(-1, -1)
	for entry in _schema.persistent_slots:
		var slot: PersistentSlot = entry as PersistentSlot
		if slot == null:
			continue
		if slot.type == PersistentSlot.Type.CORE_TOWN and slot.owner_faction == Faction.PLAYER:
			return slot.position
	return Vector2i(-1, -1)


# ─────────────────────────────────────────
# 敌方移动信号处理（M7 改造）
# ─────────────────────────────────────────

## 敌方移动阶段完成回调
## M7 迁移：end_faction_turn(ENEMY_1) → start_faction_turn(PLAYER)
## start_faction_turn(PLAYER) 内部会跑 PLAYER tick，然后 emit signal → _on_faction_turn_started 继续玩家侧
##
## 防御（P2 审查）：仅在 current_faction == ENEMY_1 时切换；若被误调在玩家回合中，直接返回避免错误双 start
func _on_enemy_phase_finished() -> void:
	if _game_finished:
		return
	if _turn_manager.current_faction != Faction.ENEMY_1:
		push_warning("WorldMap._on_enemy_phase_finished: current_faction != ENEMY_1，忽略该次回调")
		return
	_turn_manager.end_faction_turn()
	_turn_manager.current_faction = Faction.PLAYER
	_turn_manager.start_faction_turn(Faction.PLAYER)

## 强制战斗触发回调（敌方到达玩家相邻格）
func _on_forced_battle_triggered(level: LevelSlot) -> void:
	if level != null and level.is_interactable() and _has_any_troop():
		_battle_ui.show_confirm(level, _get_active_troops(),
			_battle_config, _damage_increment, true)
	else:
		# 无法战斗，继续处理移动队列
		_enemy_movement.resume_after_battle()

# ─────────────────────────────────────────
# 关卡 Slot 管理（M7 重构）
# ─────────────────────────────────────────
#
# M7 前：轮次切换时整批清理敌方关卡 + 整批生成新关卡
# M7 后：敌方生成走 EnemyReinforcement（初始预置 + 每 5 回合增援）；
#        击败的敌方部队包在 _post_battle_settlement 就地从 _level_slots 删除 + 恢复 schema slot
#
# 原 _clear_level_slots / _generate_level_slots / _get_tier_plan_for_round 已无调用方，M7 重构时删除


## 清除所有资源点（每轮次刷新前调用）
## M1 重构：ResourceSlot 已无持久分支，全部清空并恢复 MapSchema slot 为 NONE；
## 持久 slot 由 PersistentSlot 独立通道维护，不在此处处理
func _clear_onetime_resource_slots() -> void:
	for pos in _resource_slots:
		var p: Vector2i = pos as Vector2i
		if _schema != null:
			_schema.set_slot(p.x, p.y, MapSchema.SlotType.NONE)
	_resource_slots = {}

## 从配置生成本轮资源点
func _generate_resource_slots() -> void:
	if _schema == null or _resource_slot_config_rows.is_empty():
		return
	# 构建排除列表
	var exclude: Array[Vector2i] = [_start_pos, _end_pos]
	if _unit != null and not exclude.has(_unit.position):
		exclude.append(_unit.position)
	# M2：排除持久 slot 占据的格子，避免一次性资源与城建锚 slot 重叠
	for ps in _schema.persistent_slots:
		if not exclude.has(ps.position):
			exclude.append(ps.position)
	# 排除本轮已存在的资源点（M1 重构后无持久分支，本循环仍保留以防多次调用复用）
	for pos in _resource_slots:
		var p: Vector2i = pos as Vector2i
		if not exclude.has(p):
			exclude.append(p)
	# 排除已有关卡位置
	for pos in _level_slots:
		var p: Vector2i = pos as Vector2i
		if not exclude.has(p):
			exclude.append(p)

	# 按权重从配置中抽取资源点并放置
	# 先计算总数量
	var total_count: int = 0
	for entry in _resource_slot_config_rows:
		var row: Dictionary = entry as Dictionary
		total_count += int(row.get("count_per_round", "1"))

	# 放置位置（M2 P1#4：注入 _world_rng 保证 seed 复现）
	var placed: Array[Vector2i] = MapGenerator.place_level_slots(_schema, total_count, exclude, _world_rng)

	# 按配置行顺序分配位置
	var place_idx: int = 0
	for entry in _resource_slot_config_rows:
		var row: Dictionary = entry as Dictionary
		var count: int = int(row.get("count_per_round", "1"))
		for i in range(count):
			if place_idx >= placed.size():
				break
			var rs: ResourceSlot = ResourceSlot.new()
			rs.position = placed[place_idx]
			rs.resource_type = int(row.get("resource_type", "0")) as ResourceSlot.ResourceType
			rs.output_amount = int(row.get("output_amount", "1"))
			# M1 重构：is_persistent / effective_range 移除，CSV 同步删列
			_resource_slots[placed[place_idx]] = rs
			place_idx += 1

## 获取指定坐标的关卡 Slot，不存在时返回 null
func _get_level_at(pos: Vector2i) -> LevelSlot:
	if _level_slots.has(pos):
		return _level_slots[pos] as LevelSlot
	return null

# ─────────────────────────────────────────
# 轮次管理
# ─────────────────────────────────────────

## 轮次开始回调（M7 重构）
## M7 前：每轮生成若干敌方关卡（按 _enemy_tier_ratio_rows 档位比例）+ 资源点
## M7 后：敌方生成迁到"开局预置 + 每 5 敌方回合增援"（见 _deploy_initial_enemy_packs / EnemyReinforcement）；
##        本函数只保留资源点的轮次刷新 + 轮次奖励预生成
##
## 轮次概念保留做玩家通关进度标记（多轮次通关可扩展为胜利条件之一）；
## 当前 RoundManager.current_level_count 继承 round_config.csv 配置，击败敌方部队包时仍会触发 on_level_cleared
func _on_round_started(round_index: int) -> void:
	# 清除上一轮的一次性资源点（保留持久资源点）
	_clear_onetime_resource_slots()

	# 生成本轮资源点
	_generate_resource_slots()

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
# 战斗结算（BattleUI 信号处理）
# ─────────────────────────────────────────

## 击退选择回调
func _on_battle_repel_chosen() -> void:
	var level: LevelSlot = _battle_ui.pending_level
	var full_result: BattleResolver.BattleResult = _battle_ui.pending_full_result
	var was_forced: bool = _battle_ui.is_forced
	_battle_ui.hide()

	# 按击退倍率缩放伤害
	var result: BattleResolver.BattleResult = full_result.apply_damage_rate(
		_repel_player_damage_rate, _repel_enemy_damage_rate
	)

	# 保存敌方部队快照（扣血前），用于抽取部队奖励
	var troop_snapshot: Array[TroopData] = level.troops.duplicate()

	# 我方扣血
	_apply_player_damages(result)

	# 敌方扣血
	level.apply_enemy_damages(result.enemy_damages)
	var all_wiped: bool = level.remove_defeated_troops()

	if all_wiped:
		# 击退但全灭 → 转为击败，发放奖励
		level.mark_defeated()
		_grant_level_rewards_for(level)
		_grant_troop_reward(troop_snapshot)
	else:
		# 标记为击退，设置冷却
		level.mark_repelled(_repel_cooldown_turns)

	# 后处理
	_post_battle_settlement(level, was_forced)

## 击败选择回调
## 击退即可全灭时按击退倍率结算（低损耗全灭），否则按 100% 结算
func _on_battle_defeat_chosen() -> void:
	var level: LevelSlot = _battle_ui.pending_level
	var full_result: BattleResolver.BattleResult = _battle_ui.pending_full_result
	var was_forced: bool = _battle_ui.is_forced
	_battle_ui.hide()

	# 判断是否击退即可全灭，决定使用哪套倍率
	var repel_result: BattleResolver.BattleResult = full_result.apply_damage_rate(
		_repel_player_damage_rate, _repel_enemy_damage_rate
	)
	var repel_wipes: bool = BattleResolver.would_wipe_enemies(
		level.troops, repel_result.enemy_damages
	)
	var result: BattleResolver.BattleResult = repel_result if repel_wipes else full_result

	# 保存敌方部队快照（扣血前），用于抽取部队奖励
	var troop_snapshot: Array[TroopData] = level.troops.duplicate()

	# 我方扣血
	_apply_player_damages(result)

	# 敌方扣血
	level.apply_enemy_damages(result.enemy_damages)
	level.remove_defeated_troops()

	# 标记为击败
	level.mark_defeated()

	# 发放关卡胜利奖励
	_grant_level_rewards_for(level)

	# 从敌方部队中随机抽取 1 支作为部队道具奖励
	_grant_troop_reward(troop_snapshot)

	# 后处理
	_post_battle_settlement(level, was_forced)

## 战斗取消回调：关闭弹板，恢复输入
func _on_battle_cancelled() -> void:
	_battle_ui.hide()
	_refresh_reachable()

## 为我方部队应用伤害（从 BattleResult 中提取 damages），同时追踪累计损兵
func _apply_player_damages(result: BattleResolver.BattleResult) -> void:
	var troop_index: int = 0
	for ch in _characters:
		if ch.has_troop():
			if troop_index < result.damages.size():
				# 追踪实际损失（不超过剩余兵力）
				var actual_dmg: int = mini(result.damages[troop_index], ch.troop.current_hp)
				_total_hp_lost += actual_dmg
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

## 发放指定关卡的胜利奖励
func _grant_level_rewards_for(level: LevelSlot) -> void:
	if level == null:
		return
	if not level.rewards.is_empty():
		_inventory.add_items(level.rewards)
		var reward_text: String = _format_rewards_text(level.rewards)
		_show_notice("战斗胜利！获得奖励：%s" % reward_text)

## 战斗后共用处理：更新 HUD、失败判定、轮次推进
## 若处于敌方移动阶段的强制战斗，结算后继续处理移动队列
## M7 迁移：原"首次战斗后激活敌方"逻辑移除，敌方 AI 开局即活跃（初始预置 5 支 + 每 5 回合增援）
func _post_battle_settlement(level: LevelSlot, was_forced: bool) -> void:

	_update_hud()
	queue_redraw()

	# 判定失败条件：所有部队被击败即为游戏结束
	if _check_defeat():
		if was_forced:
			_enemy_movement.finish_phase()
		return

	# 击败时才通知轮次管理器（击退不算通关进度）
	var defeated: bool = level != null and level.is_defeated()

	# M4: 战斗胜利后玩家原地尝试占据持久 slot
	# was_forced 场景：敌方走到玩家相邻格触发战斗，玩家未移动，不触发占据
	# 非 forced 场景：玩家主动进入敌格战斗，victory 后单位停留在敌格位置
	if defeated and not was_forced:
		_try_player_occupy_at(_unit.position)

	# M7: 击败的敌方部队包从 _level_slots 字典移除 + 恢复 MapSchema slot 标记
	# M7 前由 _on_round_started → _clear_level_slots 整批清理；M7 后逐个即时清理
	# 注意：REPELLED 状态保留，冷却递减由 _tick_repelled_cooldowns 管理
	if defeated and level != null:
		var lvpos: Vector2i = level.position
		if _level_slots.has(lvpos):
			_level_slots.erase(lvpos)
		if _schema != null:
			var orig_type: int = _original_slot_types.get(lvpos, MapSchema.SlotType.NONE) as int
			_schema.set_slot(lvpos.x, lvpos.y, orig_type as MapSchema.SlotType)
			_original_slot_types.erase(lvpos)
	if defeated and _round_manager != null:
		var round_cleared: bool = _round_manager.on_level_cleared()
		_update_hud()
		if round_cleared:
			_grant_round_rewards()
			if not _round_manager.advance_round():
				# 全部轮次通关，即使在敌方移动阶段也直接结束
				if was_forced:
					_enemy_movement.finish_phase()
				return
			_show_round_hint()
			if was_forced:
				_enemy_movement.resume_after_battle()
			return

	# 敌方移动阶段中，继续处理下一个关卡
	if was_forced:
		_enemy_movement.resume_after_battle()
	else:
		# 战斗结束后重置移动力，允许继续移动（消耗补给）
		_unit.current_movement = _unit.max_movement
		_refresh_reachable()

# ─────────────────────────────────────────
# 装配管理信号处理
# ─────────────────────────────────────────

## 打开装配管理面板（非扎营模式，仅允许替换）
func _open_manage_panel() -> void:
	if _game_finished or _battle_ui.is_pending or _is_moving or _is_camping:
		return
	_manage_ui.open(_characters, _inventory, false)

## 管理面板关闭回调
## 扎营模式下关闭面板 → 触发完整回合结算流程
func _on_manage_closed() -> void:
	_update_hud()
	if _is_camping:
		_is_camping = false
		_on_turn_end_settlement()
	else:
		_refresh_reachable()

## 装配部队操作回调
## 旧部队转为 TROOP 道具放回背包（保留兵力和经验状态）
func _on_equip_troop(character: CharacterData, item: ItemData) -> void:
	# 旧部队回收到背包（保留完整状态）
	if character.has_troop():
		var old_troop: TroopData = character.troop
		var old_item: ItemData = ItemData.new()
		old_item.type = ItemData.ItemType.TROOP
		old_item.troop_type = int(old_troop.troop_type)
		old_item.quality = int(old_troop.quality)
		old_item.troop_current_hp = old_troop.current_hp
		old_item.troop_max_hp = old_troop.max_hp
		old_item.troop_exp = old_troop.exp
		old_item.display_name = old_troop.get_display_text()
		old_item.stack_count = 1
		_inventory.add_items([old_item])
	# 创建新部队（从道具中恢复状态）
	var troop: TroopData = TroopData.new()
	troop.troop_type = item.troop_type as TroopData.TroopType
	troop.quality = item.quality as TroopData.Quality
	# 如果道具保存了兵力状态，恢复；否则满血
	if item.troop_current_hp >= 0:
		troop.current_hp = item.troop_current_hp
		troop.max_hp = item.troop_max_hp
		troop.exp = item.troop_exp
	character.troop = troop
	# 从背包移除道具
	_inventory.remove_item(item)
	# 刷新面板
	_manage_ui.refresh()

## 使用道具操作回调（经验道具、兵力恢复道具）
func _on_use_item(character: CharacterData, item: ItemData) -> void:
	if not character.has_troop():
		return
	if item.type == ItemData.ItemType.EXP:
		character.troop.add_exp(item.value)
	elif item.type == ItemData.ItemType.HP_RESTORE:
		character.troop.current_hp = mini(
			character.troop.current_hp + item.value,
			character.troop.max_hp
		)
	# 从背包移除（可堆叠道具减少 1 个）
	_inventory.remove_item(item, 1)
	# 刷新面板
	_manage_ui.refresh()

# ─────────────────────────────────────────
# 击退冷却管理
# ─────────────────────────────────────────

## REPELLED 冷却 tick（M7 迁移为 TickRegistry handler）
## 由 TurnManager.start_faction_turn(ENEMY_1) 自动触发
## 只在敌方自阵营回合开始时递减冷却（§7.1 步骤 1）
## 语义：击退的敌方部队包在自己阵营下一回合开始时冷却 -1，归零恢复 UNCHALLENGED
func _tick_repelled_cooldowns(faction: int) -> void:
	if faction != Faction.ENEMY_1:
		return
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
	_total_max_hp = 0
	for i in range(char_count):
		var ch: CharacterData = CharacterData.new()
		ch.id = i + 1
		# 随机抽取兵种（0~4，可重复）
		var troop: TroopData = TroopData.new()
		troop.troop_type = randi_range(0, 4) as TroopData.TroopType
		troop.quality = init_quality as TroopData.Quality
		ch.troop = troop
		_characters.append(ch)
		_total_max_hp += troop.max_hp


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
	_inventory.add_items(rewards)
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
	if _game_finished or _battle_ui.is_pending or _is_moving or _manage_ui.is_open or _is_camping or _build_panel_ui.is_open:
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
	if _enemy_movement.is_moving():
		return
	if event is InputEventKey:
		var key: InputEventKey = event as InputEventKey
		if key.pressed and not key.echo:
			# M 键：打开/关闭装配管理面板
			if key.keycode == KEY_M:
				if _manage_ui.is_open:
					_manage_ui.close()
				else:
					_open_manage_panel()
			# B 键：打开/关闭建造面板（M5）
			elif key.keycode == KEY_B:
				if _build_panel_ui.is_open:
					_build_panel_ui.close()
				else:
					_open_build_panel()
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
	# M2 P1#4：自动随机走 Time 派生而非全局 randi()，并显式打印实际 seed 便于复现
	var seed_value: int = int(map_cfg.get("random_seed", "-1"))
	if seed_value == -1:
		config.seed = int(Time.get_ticks_usec())
		print("[WorldMap] 自动 seed = %d（如需复现把 map_config.csv random_seed 改为该值）" % config.seed)
	else:
		config.seed = seed_value
	# 创建本局共享 RNG，注入 seed
	_world_rng = RandomNumberGenerator.new()
	_world_rng.seed = config.seed

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

	# M2：从 map_config 加载持久 slot 八阶段参数
	config.persistent_total_count = int(map_cfg.get("persistent_total_count", "26"))
	config.persistent_core_count = int(map_cfg.get("persistent_core_count", "2"))
	config.persistent_town_count = int(map_cfg.get("persistent_town_count", "6"))
	config.persistent_village_count = int(map_cfg.get("persistent_village_count", "18"))
	config.persistent_min_dist_normal = int(map_cfg.get("persistent_min_dist_normal", "3"))
	config.persistent_min_dist_core = int(map_cfg.get("persistent_min_dist_core", "5"))
	config.persistent_emerge_steps = int(map_cfg.get("persistent_emerge_steps", "3"))
	config.persistent_field_radius = int(map_cfg.get("persistent_field_radius", "20"))
	config.persistent_core_zone_min = float(map_cfg.get("persistent_core_zone_min", "0.125"))
	config.persistent_core_zone_max = float(map_cfg.get("persistent_core_zone_max", "0.25"))
	config.persistent_max_retries = int(map_cfg.get("persistent_max_retries", "5"))
	config.persistent_faction_town_quota = int(map_cfg.get("persistent_faction_town_quota", "2"))
	config.persistent_faction_village_quota = int(map_cfg.get("persistent_faction_village_quota", "6"))

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

	# 第 1.6 层：资源点标记 + 文字
	_draw_resource_slots()

	# 第 1.7 层：持久 slot 影响范围覆盖层（M4；半透明势力色）
	_draw_persistent_influence_ranges()

	# 第 1.8 层：持久 slot 本体标记（M4；外框色块 + 核心城镇金边 + 类型等级文字）
	_draw_persistent_slots()

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
	if _enemy_movement.get_moving_level() != null:
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

	# 若有 Slot，在格中央叠加色块标记 + 文字
	var slot: MapSchema.SlotType = _schema.get_slot(x, y)
	if slot != MapSchema.SlotType.NONE:
		var pos: Vector2i = Vector2i(x, y)
		var level: LevelSlot = _get_level_at(pos)
		var is_enemy: bool = false
		var is_repelled: bool = false

		# 敌方格使用专用暗红底色；其他 slot 使用 SLOT_COLORS 兜底色
		var slot_color: Color
		if level != null:
			# 正在移动的关卡跳过静态渲染（由 _draw_enemy_move_marker 负责）
			if level == _enemy_movement.get_moving_level():
				return
			is_enemy = true
			slot_color = ENEMY_SLOT_COLOR
			if level.is_defeated():
				# 已击败：变暗显示，不再叠加文字
				slot_color = slot_color.darkened(CHALLENGED_DIM)
			elif level.is_repelled():
				# 已击退冷却中：半透明显示，不再叠加文字
				is_repelled = true
				slot_color = Color(slot_color.r, slot_color.g, slot_color.b, 0.4)
		else:
			slot_color = SLOT_COLORS.get(slot, Color.WHITE) as Color

		var slot_rect: Rect2 = Rect2(
			x * TILE_SIZE + SLOT_MARGIN,
			y * TILE_SIZE + SLOT_MARGIN,
			TILE_SIZE - SLOT_MARGIN * 2 - 1,
			TILE_SIZE - SLOT_MARGIN * 2 - 1
		)
		# 敌方关卡用菱形绘制，其他 Slot 保持矩形
		if is_enemy:
			_draw_diamond(slot_rect, slot_color)
		else:
			draw_rect(slot_rect, slot_color)

		# 敌方关卡：加菱形描边 + 文字（仅活跃状态显示文字）
		if is_enemy:
			var border_color: Color = REPELLED_BORDER_COLOR
			if not is_repelled and not level.is_defeated():
				border_color = TIER_BORDER_COLORS.get(level.tier, ENEMY_BORDER_COLOR) as Color
			_draw_diamond(slot_rect, border_color, false, 1.5)
			# 活跃状态叠加强度文字标注（敌·弱 / 敌·中 / 敌·强 / 敌·超）
			if _label_font != null and not level.is_defeated() and not is_repelled:
				var tier_labels: Array[String] = ["敌·弱", "敌·中", "敌·强", "敌·超"]
				var tier_text: String = tier_labels[level.tier] if level.tier < tier_labels.size() else "敌?"
				_draw_slot_label(
					Vector2(x * TILE_SIZE + TILE_SIZE / 2.0, y * TILE_SIZE + TILE_SIZE / 2.0),
					tier_text,
					Color.WHITE
				)

## 即时资源点盲盒色（M6 视觉统一：采集前不显示具体类型，避免与"等权采集"规则冲突）
const RESOURCE_BLIND_BOX_COLOR: Color = Color(0.55, 0.55, 0.60)

## 绘制资源点标记方块 + 文字
## M6 P1 修复：即时 slot 采集走 4 项等权池（忽略 slot 自身 resource_type），
## 视觉上若按类型着色会误导玩家（以为是定向资源），故统一为盲盒灰色 + "?"
## 原按类型着色的 RESOURCE_*_COLOR 常量保留以备他处引用，但本函数不再使用
func _draw_resource_slots() -> void:
	for pos in _resource_slots:
		var rs: ResourceSlot = _resource_slots[pos] as ResourceSlot
		# 已采集的资源点不渲染
		if rs.is_collected:
			continue
		var p: Vector2i = pos as Vector2i

		# 盲盒渲染：所有即时 slot 统一色块 + "?" 标签
		var rs_rect: Rect2 = Rect2(
			p.x * TILE_SIZE + SLOT_MARGIN,
			p.y * TILE_SIZE + SLOT_MARGIN,
			TILE_SIZE - SLOT_MARGIN * 2 - 1,
			TILE_SIZE - SLOT_MARGIN * 2 - 1
		)
		draw_rect(rs_rect, RESOURCE_BLIND_BOX_COLOR)

		if _label_font != null:
			_draw_slot_label(
				Vector2(p.x * TILE_SIZE + TILE_SIZE / 2.0, p.y * TILE_SIZE + TILE_SIZE / 2.0),
				"?",
				Color(0.05, 0.05, 0.05)
			)

# ─────────────────────────────────────────
# 持久 slot 渲染（M4）
# ─────────────────────────────────────────

## 势力归属色：持久 slot 外框 + 影响范围覆盖层共用
## UI 重构步骤 2：PLAYER 色相从 #4D8CF2 调整为 #3D6FE0（偏冷蓝），
##   避免与 LOWLAND 洼地蓝 #4D8CBF 低对比度；保持和 ENEMY_1 红的二元对立
const M4_FACTION_COLORS: Dictionary = {
	0: Color(0.55, 0.55, 0.55),   ## NONE 中立 — 灰  #8C8C8C
	1: Color(0.24, 0.44, 0.88),   ## PLAYER — 冷蓝  #3D70E0（原 #4D8CF2 调冷以区别洼地）
	2: Color(0.90, 0.35, 0.35),   ## ENEMY_1 — 红  #E65959
}

## 影响范围覆盖层 alpha（半透明，避免遮挡地形 / 单位 / 可达高亮）
## UI 重构步骤 4：从 0.15 降到 0.08，势力范围明确退为辅助层，
## 不再主导画面；识别靠描边（M4_INFLUENCE_BORDER_ALPHA=0.55）承担
const M4_INFLUENCE_ALPHA: float = 0.08

## 影响范围菱形外边界描边 alpha + 线宽
## 决策背景：填充统一色会让相邻同势力 slot 的菱形融成一片、分不清各自边界；
## 追加描边后每个 slot 一条独立轮廓，相邻 slot 重叠处形成双线，视觉可辨
const M4_INFLUENCE_BORDER_ALPHA: float = 0.55
const M4_INFLUENCE_BORDER_WIDTH: float = 2.0

## 核心城镇金色描边（凸显势力首都）
const M4_CORE_TOWN_BORDER: Color = Color(1.0, 0.85, 0.0)

## 持久 slot 双层结构（UI 重构步骤 1）
## 外环 = 势力色（归属识别）；内底 = 中性米白（文字承载，对比度最高）
## 核心城镇额外金色中心徽记强化"首都"仪式感
const M4_PERSISTENT_RING_WIDTH: int = 4        ## 外环厚度 px（占格 48 × 8%）
const M4_PERSISTENT_INNER_BG: Color = Color(0.90, 0.88, 0.83)  ## 内底米白  #E6E0D4
const M4_CORE_TOWN_EMBLEM_SIZE: int = 8        ## 核心城镇下方徽记（金色小菱形）边长 px


## 绘制所有已占据持久 slot 的影响范围覆盖层（曼哈顿菱形内所有格）
## 中立 slot / influence_range <= 0 不渲染
## 覆盖层先于 slot 本体绘制，保证本体图案可见；相邻 slot 覆盖区域色彩叠加属预期
##
## 描边策略：对菱形内每格，检查 4 个正交邻居是否仍在菱形内；
## 越界邻居对应的那条边即为菱形外边界 → 用势力色实线画出。
## 效果：每个 slot 一条独立菱形轮廓；相邻同势力 slot 范围重叠处自然出现"内外双线"示意交集
func _draw_persistent_influence_ranges() -> void:
	if _schema == null:
		return
	for entry in _schema.persistent_slots:
		var slot: PersistentSlot = entry as PersistentSlot
		if slot == null:
			continue
		if slot.owner_faction == Faction.NONE:
			continue
		if slot.influence_range <= 0:
			continue
		var base: Color = M4_FACTION_COLORS.get(slot.owner_faction, Color.MAGENTA) as Color
		var overlay: Color = Color(base.r, base.g, base.b, M4_INFLUENCE_ALPHA)
		var border: Color = Color(base.r, base.g, base.b, M4_INFLUENCE_BORDER_ALPHA)
		var r: int = slot.influence_range
		var cx: int = slot.position.x
		var cy: int = slot.position.y
		# 曼哈顿菱形：|dx| + |dy| <= r
		for dy in range(-r, r + 1):
			var y: int = cy + dy
			if y < 0 or y >= _schema.height:
				continue
			var dx_max: int = r - absi(dy)
			for dx in range(-dx_max, dx_max + 1):
				var x: int = cx + dx
				if x < 0 or x >= _schema.width:
					continue
				var rect: Rect2 = Rect2(
					x * TILE_SIZE,
					y * TILE_SIZE,
					TILE_SIZE - 1,
					TILE_SIZE - 1
				)
				draw_rect(rect, overlay)

				# 描边：对 4 个正交邻居逐个检查，越界邻居对应的边即为菱形外缘
				# 注意是菱形 ± 邻居关系，不是矩形边界——用 |dx'|+|dy'| > r 判定
				var px: float = float(x * TILE_SIZE)
				var py: float = float(y * TILE_SIZE)
				var pw: float = float(TILE_SIZE)
				# 上（dy-1）
				if absi(dx) + absi(dy - 1) > r:
					draw_line(Vector2(px, py), Vector2(px + pw, py),
						border, M4_INFLUENCE_BORDER_WIDTH)
				# 下（dy+1）
				if absi(dx) + absi(dy + 1) > r:
					draw_line(Vector2(px, py + pw), Vector2(px + pw, py + pw),
						border, M4_INFLUENCE_BORDER_WIDTH)
				# 左（dx-1）
				if absi(dx - 1) + absi(dy) > r:
					draw_line(Vector2(px, py), Vector2(px, py + pw),
						border, M4_INFLUENCE_BORDER_WIDTH)
				# 右（dx+1）
				if absi(dx + 1) + absi(dy) > r:
					draw_line(Vector2(px + pw, py), Vector2(px + pw, py + pw),
						border, M4_INFLUENCE_BORDER_WIDTH)


## 绘制所有持久 slot 的本体标记
## UI 重构步骤 1：双层结构 —— 外环势力色 + 内底中性米白 + 核心城镇金边 + 中心徽记
##
## 设计理由（[[地图视觉表现优化方案]] §三）：
##   原整块势力色会让文字对比度随势力色变化，且远看只有"颜色块"；
##   双层后外环负责归属识别，内底承载文字高对比度，据点升级为"结构化地图对象"
##
## 归属翻转时势力色立即反映（由 try_occupy 触发 queue_redraw）
func _draw_persistent_slots() -> void:
	if _schema == null:
		return
	for entry in _schema.persistent_slots:
		var slot: PersistentSlot = entry as PersistentSlot
		if slot == null:
			continue
		var p: Vector2i = slot.position
		var outer: Rect2 = Rect2(
			p.x * TILE_SIZE + 1,
			p.y * TILE_SIZE + 1,
			TILE_SIZE - 3,
			TILE_SIZE - 3
		)
		var color: Color = M4_FACTION_COLORS.get(slot.owner_faction, Color.MAGENTA) as Color

		# 步骤 1 双层：外环（势力色填满）+ 内底（中性米白，内缩 ring_width）
		draw_rect(outer, color)
		var ring: int = M4_PERSISTENT_RING_WIDTH
		var inner: Rect2 = Rect2(
			outer.position + Vector2(ring, ring),
			outer.size - Vector2(ring * 2, ring * 2)
		)
		# 极端情况：格子变小 → ring*2 可能溢出，防御
		if inner.size.x > 0 and inner.size.y > 0:
			draw_rect(inner, M4_PERSISTENT_INNER_BG)

		# 核心城镇第二识别特征：金色外描边 + 下方小金菱形徽记
		# 徽记偏下（主字居中占主视觉），避免被文字压住
		if slot.type == PersistentSlot.Type.CORE_TOWN:
			draw_rect(outer, M4_CORE_TOWN_BORDER, false, 2.0)
			var emblem_pos: Vector2 = outer.get_center() + Vector2(0, 12)
			_draw_core_town_emblem(emblem_pos)

		# 主字（display_id）+ 等级角标
		# display_id 落在内底米白上（任何势力色下对比度都最优）
		# legacy fallback（未分配 display_id）保留旧行为 main_text 含 level
		if _label_font != null:
			var center_px: Vector2 = outer.get_center()
			var main_text: String = slot.display_id if slot.display_id != "" else (slot.get_map_label() + str(slot.level))
			_draw_slot_label(center_px, main_text, Color(0.05, 0.05, 0.05))

			if slot.display_id != "":
				_draw_level_badge(p, slot.level)


## 绘制核心城镇中心金色菱形徽记（UI 重构步骤 1 · 核心第二识别特征）
## 叠加在主字"核心"之下作为装饰层；靠形状 + 金色拉开和普通据点的区别
## center_px: 格子像素中心
func _draw_core_town_emblem(center_px: Vector2) -> void:
	var s: float = float(M4_CORE_TOWN_EMBLEM_SIZE)
	var half: float = s / 2.0
	# 菱形 4 顶点（上 / 右 / 下 / 左）
	var pts: PackedVector2Array = PackedVector2Array([
		Vector2(center_px.x, center_px.y - half),
		Vector2(center_px.x + half, center_px.y),
		Vector2(center_px.x, center_px.y + half),
		Vector2(center_px.x - half, center_px.y),
	])
	draw_colored_polygon(pts, M4_CORE_TOWN_BORDER)

## 绘制正在移动的敌方关卡标记（基于动画位置）
## 使用更大标记 + 外圈光晕 + 亮红橙色，突出移动中的敌方
func _draw_enemy_move_marker() -> void:
	var enemy_vis_pos: Vector2 = _enemy_movement.get_visual_pos()
	# 外圈光晕菱形（比标记更大，半透明）
	var glow_margin: int = 2
	var glow_rect: Rect2 = Rect2(
		enemy_vis_pos.x - TILE_SIZE / 2 + glow_margin,
		enemy_vis_pos.y - TILE_SIZE / 2 + glow_margin,
		TILE_SIZE - glow_margin * 2 - 1,
		TILE_SIZE - glow_margin * 2 - 1
	)
	_draw_diamond(glow_rect, ENEMY_GLOW_COLOR)
	# 核心菱形标记（标准大小，亮红橙色）
	var rect: Rect2 = Rect2(
		enemy_vis_pos.x - TILE_SIZE / 2 + SLOT_MARGIN,
		enemy_vis_pos.y - TILE_SIZE / 2 + SLOT_MARGIN,
		TILE_SIZE - SLOT_MARGIN * 2 - 1,
		TILE_SIZE - SLOT_MARGIN * 2 - 1
	)
	_draw_diamond(rect, ENEMY_MOVE_COLOR)
	# 菱形边框描边
	_draw_diamond(rect, ENEMY_BORDER_COLOR, false, 1.0)

## 绘制菱形（以 Rect2 区域的中心为菱形中心，四个顶点取矩形边中点）
## filled=true 时填充，filled=false 时仅描边
func _draw_diamond(rect: Rect2, color: Color, filled: bool = true, width: float = 1.0) -> void:
	# 防御退化矩形：尺寸为零时菱形顶点重合，跳过绘制
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var cx: float = rect.position.x + rect.size.x / 2.0
	var cy: float = rect.position.y + rect.size.y / 2.0
	var hw: float = rect.size.x / 2.0  # 水平半宽
	var hh: float = rect.size.y / 2.0  # 垂直半高
	# 四个顶点：上、右、下、左
	var points: PackedVector2Array = PackedVector2Array([
		Vector2(cx, cy - hh),       # 上
		Vector2(cx + hw, cy),       # 右
		Vector2(cx, cy + hh),       # 下
		Vector2(cx - hw, cy),       # 左
	])
	if filled:
		draw_colored_polygon(points, color)
	else:
		# 描边：绘制闭合折线
		var outline: PackedVector2Array = points
		outline.append(points[0])
		draw_polyline(outline, color, width)

## 绘制持久 slot 等级角标（格子右上角小字 "L0/1/2/3"）
## grid_pos —— 该 slot 的格坐标，函数内自行算像素偏移
## 字体使用 LEVEL_BADGE_FONT_SIZE（9px）；颜色与主字同深色以保持一致
## 位置：格子右上距边 2-3px，不覆盖势力金边 / 外框
func _draw_level_badge(grid_pos: Vector2i, level: int) -> void:
	if _label_font == null:
		return
	var text: String = "L%d" % level
	# 角标宽度估算（英文+数字约为字号 × 字符数 × 0.5）；右上靠边距 3px
	var badge_px: Vector2 = Vector2(
		grid_pos.x * TILE_SIZE + TILE_SIZE - 3,
		grid_pos.y * TILE_SIZE + 3 + LEVEL_BADGE_FONT_SIZE
	)
	# 右对齐：draw_string 的起点是 baseline-left；向左偏移一个字串宽度
	# 无需精确文本宽度测量——用负 offset 让 CENTER 区域右对齐到 badge_px
	draw_string(
		_label_font,
		Vector2(badge_px.x - 16, badge_px.y),    # 16px 宽度区域，右对齐到 badge_px.x
		text,
		HORIZONTAL_ALIGNMENT_RIGHT,
		16,
		LEVEL_BADGE_FONT_SIZE,
		Color(0.05, 0.05, 0.05)
	)


## 在指定像素中心绘制居中文字标签
## center_px: 格的像素中心坐标；使用字体 ascent/descent 精确计算垂直基线位置
func _draw_slot_label(center_px: Vector2, text: String, color: Color) -> void:
	if _label_font == null:
		return
	var ascent: float = _label_font.get_ascent(LABEL_FONT_SIZE)
	var descent: float = _label_font.get_descent(LABEL_FONT_SIZE)
	# 基线 = 中心点 + (ascent - descent) / 2，使文字视觉上精确居中
	var baseline_y: float = center_px.y + (ascent - descent) / 2.0
	# 文字区域从中心点左侧半格开始，宽度一格，CENTER 对齐实现水平居中
	var left_x: float = center_px.x - TILE_SIZE / 2.0
	draw_string(
		_label_font,
		Vector2(left_x, baseline_y),
		text,
		HORIZONTAL_ALIGNMENT_CENTER,
		TILE_SIZE,
		LABEL_FONT_SIZE,
		color
	)


## 绘制单位标记（基于视觉位置，支持动画中的平滑移动）
## UI 重构步骤 3：加深色描边 + 投影，消除"漂浮感"，让单位稳定为第一视觉锚点
##
## 绘制顺序（自底向上）：
##   1. 投影：右下偏移 +2px 的半透明黑矩形
##   2. 主体：白色方块
##   3. 描边：深色 1.5 px 外边
##   4. 文字：居中"我"字
func _draw_unit_marker() -> void:
	var rect: Rect2 = Rect2(
		_unit_visual_pos.x - TILE_SIZE / 2 + UNIT_MARGIN,
		_unit_visual_pos.y - TILE_SIZE / 2 + UNIT_MARGIN,
		TILE_SIZE - UNIT_MARGIN * 2 - 1,
		TILE_SIZE - UNIT_MARGIN * 2 - 1
	)

	# 投影：右下偏移 2px、半透明黑；营造棋子感而非平面 sticker
	var shadow_rect: Rect2 = Rect2(rect.position + Vector2(2, 2), rect.size)
	draw_rect(shadow_rect, UNIT_SHADOW_COLOR)

	# 主体白色方块
	draw_rect(rect, UNIT_COLOR)

	# 深色描边：在浅色地形 / 高亮区防漂浮
	draw_rect(rect, UNIT_OUTLINE_COLOR, false, UNIT_OUTLINE_WIDTH)

	# "我"字居中
	if _label_font != null:
		_draw_slot_label(_unit_visual_pos, "我", Color(0.15, 0.15, 0.15))
