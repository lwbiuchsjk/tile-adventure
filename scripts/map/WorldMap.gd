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
## B 重生周期 MVP：英雄池 + 整局周期参数
const CONFIG_HERO_POOL: String = "res://assets/config/hero_pool.csv"
const CONFIG_RUN: String = "res://assets/config/run_config.csv"
## E 战斗就地展开 MVP：兵种战斗参数（移动 / 攻击范围）
const CONFIG_BATTLE_UNIT: String = "res://assets/config/battle_unit_config.csv"

# ─────────────────────────────────────────
# 渲染常量
# ─────────────────────────────────────────

## 每格像素尺寸（参见 Design/地图格子视觉规范.md）
const TILE_SIZE: int = 48

## 各地形渲染颜色（纯色块占位）
## key 使用整数字面量对应 MapSchema.TerrainType 枚举值
## Civ 风格地形重构（B-α 沼泽褐）：地形整体去饱和退到背景层，把色相焦点让给势力色
##   设计原则：地形 = 安静的自然基调；势力色（蓝/红/黄）独占高饱和色相
##   MOUNTAIN 冷灰褐；HIGHLAND/FLATLAND 同绿系靠明度分层并大幅去饱和；
##   LOWLAND 改用沼泽褐，色相完全脱离玩家青蓝（根治洼地蓝 vs 玩家蓝撞色）
const TERRAIN_COLORS: Dictionary = {
	0: Color(0.29, 0.25, 0.20),  ## MOUNTAIN：冷灰褐：高山  #4A3F33（保留：本就低饱和中性）
	1: Color(0.72, 0.76, 0.61),  ## HIGHLAND：暖灰绿：高地  #B8C29B（原 #9BC262 大幅去饱和，明度保留）
	2: Color(0.58, 0.70, 0.53),  ## FLATLAND：淡草绿：平地  #93B388（原 #6EA577 去饱和，占格最多须最安静）
	3: Color(0.35, 0.30, 0.23),  ## LOWLAND：沼泽褐：洼地  #5A4D3A（原 #3C7AAC，色相 180° 旋至褐系，与玩家蓝彻底脱钩）
}

## Civ 风格地形重构：地形轻量明暗噪声（步骤 9 延续）
## 每格基于 (x, y) 哈希给地形色加 ±4% 亮度微扰，避免整齐色块的表格感
## 噪声幅度从 0.05 降到 0.04 —— 地形去饱和后相对噪声更显眼，略降以保持安静
## 同 seed 每格噪声一致，不闪烁；不引入真实贴图语义
const TERRAIN_NOISE_RANGE: float = 0.04

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
## 沿革：
##   - UI 重构步骤 7：从 alpha 0.25 降到 0.08（弱化整格铺色），由边界描边主导识别
##   - Civ 化阶段 A 后续：势力范围升级为"硬外缘 alpha 1.0 宽 3.0 + 内向渐变 0.22/0.12/0.05"
##     视觉强度颠倒——"立即操作"的可达范围被"长期状态"的势力范围压在背景层
##   - 当前：白色双通道全面加强，恢复"立即操作 > 长期状态"信息层级
##     填充 0.08 → 0.18；描边色浅蓝白 #B8D9FF → 纯白；alpha 0.70 → 1.0；宽 2.0 → 3.5（略超势力范围 3.0）
const REACHABLE_COLOR: Color = Color(1.0, 1.0, 1.0, 0.18)

## 可达范围边界描边（合集化 —— 4 邻居不在集合内的方向画外边）
## 纯白 alpha 1.0 + 宽 3.5，与势力色（青蓝 / 玫红）色相完全脱钩，强度压过势力范围一档
const REACHABLE_BORDER_COLOR: Color = Color(1.0, 1.0, 1.0, 1.0)    ## #FFFFFF alpha 1.0
const REACHABLE_BORDER_WIDTH: float = 3.5

## 单位标记内底色（白色，承载"我"字 + 在地形上保留对比度）
const UNIT_COLOR: Color = Color(1.0, 1.0, 1.0)

## UI 重构步骤 3：单位投影（圆形棋子感）
## 旧的"白主体 + 深灰描边"已被"圆形 + 玩家蓝外环 + 白心"替代——
## 形状区分（圆 vs 方/菱）+ 玩家蓝身份语义双管齐下，避免单位被白色可达边吞没、
## 也避免与同样"蓝边白心"的玩家建筑混淆（建筑是方形）
const UNIT_SHADOW_COLOR: Color = Color(0.0, 0.0, 0.0, 0.30)   ## 投影半透黑

## 单位标记边距（像素）—— 圆形半径 = (TILE_SIZE - UNIT_MARGIN*2) / 2
const UNIT_MARGIN: int = 8

## 玩家单位外环厚度（px）—— 环色复用 M4_FACTION_COLORS[Faction.PLAYER]，保证 UI 一致
## 环宽 3 略薄于建筑 4，因为单位整体小一档（半径 16 vs 建筑半边长 24）
const UNIT_PLAYER_RING_WIDTH: int = 3

## 已挑战关卡变暗系数（同一轮内已挑战但尚未切换的关卡）
const CHALLENGED_DIM: float = 0.4

## 敌方关卡底色 —— 统一为标准敌方红，与持久敌方建筑势力色同源
## 沿革：
##   v1 暗红 #CC4040 单色 + tier 跨色相边框（绿/黄/红/紫）
##   v2 饱和冷红 #FF3D4D 单色 + tier 红色家族边框 —— tier 中描边色与底色相同消失（致命 bug）
##   v3（R-Bold）底色按 tier 明度梯度（浅红粉 → 黑红）+ 主字"弱/中/强/超" —— 文字 14px 在小空间糊
##   v4（米字小菱形 + 尺寸梯度）—— 但底色 4 档梯度让"超档黑红"被白小菱形覆盖出现反语义
##   v5（当前）底色统一 #FF3D4D —— 强度完全靠 3 个独立直觉通道（尺寸 + 小菱形数 + 描边宽度）；
##              底色不再与小菱形数量"打架"，与持久敌方建筑共享"敌方"身份红
const ENEMY_SLOT_COLOR: Color = Color(1.00, 0.24, 0.30)

## 敌方菱形描边 —— 统一黑红色，宽度按 tier 梯度
## 黑红 #1A0008 与红底高对比；宽度梯度收窄到 2.0/2.5/3.0/3.5（v4 的 4.5 过粗压迫小菱形）
const TIER_BORDER_COLOR: Color = Color(0.10, 0.00, 0.03, 1.0)
const TIER_BORDER_WIDTHS: Dictionary = {
	0: 2.0,
	1: 2.5,
	2: 3.0,
	3: 3.5,
}

## 敌方关卡边框颜色（兜底，仅 level.tier 越界时使用）
const ENEMY_BORDER_COLOR: Color = Color(1.0, 0.25, 0.20, 0.8)

## 敌方强度图形化（米字 4 小菱形）
## 外菱形以"米字"线四等分，4 个小菱形（上/下/左/右）按 tier 累积点亮：
##   tier 0 弱：上 1 个（独立 tip）
##   tier 1 中：上+下 2 个（垂直对称）
##   tier 2 强：上+左+右 3 个（T 型，左右对称）
##   tier 3 超：4 个全亮（恰好组合成完整内嵌菱形）
## 小菱形配色：金色填充（无描边） —— 红+金经典威慑配色，与玩家/敌方核心金边同源（"金=重要标识"），
##             与玩家蓝白阵营形成"蓝白文明 vs 红金军阀"对位
## 小菱形尺寸：外菱形 0.3 倍居中分布
##   v5 初版 0.4 倍，4 个小菱形仍偏大、底色显示区域偏小；
##   缩到 0.3 倍后底色 70%+ 区域可见，1 个 vs 3 个的差异更直接（"少且小"vs"分散漂浮"语义不模糊）
const ENEMY_TIER_DOT_COLOR: Color = Color(1.0, 0.84, 0.0)         ## 金色 #FFD700
const ENEMY_TIER_DOT_SIZE_RATIO: float = 0.3

## 敌方外菱形按 tier 的格内边距（像素）—— 尺寸梯度通道
## 占格比例：弱 67% / 中 75% / 强 83% / 超 90%
##   弱档显著最小（67%）+ 小菱形居中（不在米字 4 方向），与其他档形成"位置 + 尺寸"双重区分
##   1 个居中小菱形 vs 3 个 T 型小菱形语义完全不同，远观一眼可辨
## margin = (TILE_SIZE - TILE_SIZE * 占比) / 2，TILE_SIZE = 48
const ENEMY_TIER_SLOT_MARGINS: Dictionary = {
	0: 8,   ## 67% 占格 —— 弱档显著最小
	1: 6,   ## 75%
	2: 4,   ## 83%
	3: 2,   ## 92%
}

## 一次性资源点底色（按类型区分）
const RESOURCE_SUPPLY_COLOR: Color = Color(0.80, 0.27, 0.53)   ## 补给：品红  #CC4488（规避蓝绿色地形）
const RESOURCE_HP_COLOR: Color = Color(0.88, 0.47, 0.19)       ## 兵力：橙色  #E07830（规避绿色地形）
const RESOURCE_EXP_COLOR: Color = Color(0.60, 0.40, 0.80)      ## 经验：紫色  #9966CC（规避蓝色地形）
const RESOURCE_STONE_COLOR: Color = Color(0.55, 0.55, 0.60)    ## 石料：灰岩  #8C8C99（规避资源色相冲突）
# 注：M1 重构后 ResourceSlot 仅承载一次性产出，原"持久金色 + 范围金光叠加"颜色常量已移除；
# 持久 slot 视觉 / 影响范围覆盖层现走 M4 新常量（M4_FACTION_COLORS / M4_INFLUENCE_ALPHA_OUTER/MID/INNER）。

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

## 事件面板 UI（探索体验·F MVP）—— 扎营产出 / 即时 slot 采集 / 入队等叙事性奖励
## 挂在 ManageUI / BuildPanelUI 之上、VictoryUI 之下（由 _init_subsystems 挂载顺序保证）
var _event_panel: EventPanelUI = null

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

## 玩家手动建造/升级入口开关（A 基线收束 MVP）
## false：玩家无法通过任何 UI 路径触发自身 slot 升级（保留 BuildSystem 全部逻辑供敌方 AI 使用）
## true：开放旧入口（调试 / 未来若放开手动升级时改值即可，无需删守卫）
var _build_upgrade_enabled: bool = false

## 敌方部队进入玩家曼哈顿距离 ≤ 该值时触发强制战斗（A 基线收束 MVP）
## 默认 3；从 battle_config.forced_battle_range 读
##
## E MVP 起新增 `_battle_trigger_range`（同义不同名，便于语义清晰过渡）；
## E3 实装时把强制战斗触发路径切到 BattleSession，本字段可与 _battle_trigger_range 合并
var _forced_battle_range: int = 3

## E 战斗就地展开 MVP：触发距离 / 战场范围 / 地形修正 / 补给消耗
## 设计原文 §4.2：tile-advanture-design/探索体验实装/E_战斗就地展开_MVP.md
var _battle_trigger_range: int = 3              ## 主动 / 被动战斗触发 + 玩家保护区半径
var _battle_arena_range: int = 6                ## 战场半径（玩家中心 ±N）
var _terrain_altitude_step: float = 0.10        ## 地形高度差伤害修正系数
var _active_battle_supply_cost: int = 1         ## 主动战斗消耗补给
var _passive_battle_supply_cost: int = 1        ## 被动战斗消耗补给（钳到 ≥ 0）

## 兵种战斗参数缓存：{ TroopType_int : {"move_range": int, "attack_range": int} }
## 由 battle_unit_config.csv 加载；E3 实装战斗触发时传给 BattleSession.start
var _battle_unit_config: Dictionary = {}

## E 战斗就地展开 MVP：当前活跃战斗会话；null = 探索态，非 null = 战斗态
## 战斗态期间所有面板 / 输入需通过 _is_in_battle() 守卫拦截
## 由 [F] 键主动战斗触发创建（E3）；战斗结束在 _on_battle_session_ended sink 中清空
var _battle_session: BattleSession = null

## E 战斗就地展开 MVP：战斗内 HUD（程序化构建 Control）
## 与 _battle_session 同生命周期：战斗开始 show / 结束 hide
## 通过 _battle_session.on_redraw_requested 接收 redraw 请求并刷新 HUD 内容
var _battle_hud: BattleHUD = null

## E 战斗就地展开 MVP：探索态【攻击】按钮
## 仅在玩家回合 + 触发距离内有可交互敌方包 + 非战斗态时显示
## 点击 = _try_trigger_active_battle（与 [F] 键同语义）
## 避免玩家忽略 [F] 键提示，给"可发起攻击"一个醒目的视觉信号
var _explore_attack_btn: Button = null

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
# B 重生周期 MVP — 整局态字段
# ─────────────────────────────────────────

## 当前队长显示名（来自 RunState.draw_new_leader 的 hero_pool 行 name 字段）
## 用于昏迷文字 / 重生介绍占位文案；HUD 显示也读这里
var _leader_display_name: String = ""

## 昏迷态守门：true 期间锁所有输入，等 SceneTreeTimer 走完后 reload 场景
var _is_in_coma: bool = false

## 队长昏迷阈值（current_hp / max_hp ≤ 该值触发昏迷）；run_config.csv 注入
var _coma_hp_threshold_ratio: float = 0.2

## 昏迷遮罩 / 文字停留秒数；run_config.csv 注入
var _coma_duration_sec: float = 1.5

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

	# B 重生周期 MVP：英雄池 + 整局周期参数
	# RunState.ensure_initialized 幂等：首次进入写入；重生场景 reload 时
	# _initialized=true，沿用上一周期累积的 _cycle_index / _used_hero_ids 等
	var hero_pool_rows: Array = ConfigLoader.load_csv(CONFIG_HERO_POOL)
	var run_cfg: Dictionary = ConfigLoader.load_csv_kv(CONFIG_RUN)
	var max_cycles_v: int = int(run_cfg.get("max_cycles", "3"))
	_coma_duration_sec = float(run_cfg.get("coma_duration_sec", "1.5"))
	_coma_hp_threshold_ratio = float(run_cfg.get("coma_hp_threshold_ratio", "0.2"))
	# rng 传 null：RunState 内部 randomize 一个独立 RNG，不被地图 PCG seed 干扰
	# （重生抽队长应与地图 PCG 解耦，否则同 seed 重开会抽到同一队长序列）
	RunState.ensure_initialized(max_cycles_v, hero_pool_rows, null)

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

	# 强制战斗触发距离（A 基线收束 MVP）
	# 默认 3；CSV 写坏（≤ 0）时回退到默认 + push_warning，参考上面 enemy_target_switch_range 的兜底
	var raw_force_range: int = int(_battle_config.get("forced_battle_range", "3"))
	if raw_force_range < 1:
		push_warning("WorldMap: battle_config.forced_battle_range 非法值 %d，回退到 3" % raw_force_range)
		_forced_battle_range = 3
	else:
		_forced_battle_range = raw_force_range

	# E 战斗就地展开 MVP 配置（E1 仅加载到字段，E3 实装时由 BattleSession 消费）
	# battle_trigger_range 缺失时回退到 forced_battle_range（兼容 A MVP 跑测路径）
	var raw_trigger: int = int(_battle_config.get("battle_trigger_range", str(_forced_battle_range)))
	_battle_trigger_range = maxi(1, raw_trigger)
	var raw_arena: int = int(_battle_config.get("battle_arena_range", "6"))
	_battle_arena_range = maxi(_battle_trigger_range, raw_arena)  # 战场至少不小于触发距离
	_terrain_altitude_step = float(_battle_config.get("terrain_altitude_step", "0.10"))
	_active_battle_supply_cost = maxi(0, int(_battle_config.get("active_battle_supply_cost", "1")))
	_passive_battle_supply_cost = maxi(0, int(_battle_config.get("passive_battle_supply_cost", "1")))

	# E MVP：兵种战斗参数（移动 / 攻击范围）解析为 { TroopType_int : Dictionary }
	# 兵种名 → ID 复用 BattleResolver.TROOP_NAME_TO_ID
	# 配置下限：move_range >= 1（移动力不能为 0，否则单位被卡住）
	#         attack_range >= 1（攻击范围不能为 0，否则单位无法攻击）
	# 非法值回退到 SWORD 默认（3/1）+ push_warning
	var battle_unit_rows: Array = ConfigLoader.load_csv(CONFIG_BATTLE_UNIT)
	_battle_unit_config = {}
	for entry in battle_unit_rows:
		var row: Dictionary = entry as Dictionary
		var name: String = String(row.get("troop_type", ""))
		if not BattleResolver.TROOP_NAME_TO_ID.has(name):
			push_warning("WorldMap: battle_unit_config 未知兵种 '%s'，跳过" % name)
			continue
		var key: int = int(BattleResolver.TROOP_NAME_TO_ID[name])
		var raw_move: int = int(row.get("move_range", "3"))
		var raw_attack: int = int(row.get("attack_range", "1"))
		var move_v: int = raw_move
		var attack_v: int = raw_attack
		if raw_move < 1:
			push_warning("WorldMap: battle_unit_config[%s].move_range 非法值 %d，回退到 3" % [name, raw_move])
			move_v = 3
		if raw_attack < 1:
			push_warning("WorldMap: battle_unit_config[%s].attack_range 非法值 %d，回退到 1" % [name, raw_attack])
			attack_v = 1
		_battle_unit_config[key] = {
			"move_range": move_v,
			"attack_range": attack_v,
		}

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
	# D MVP：清理昼夜监听 + sink，避免跨场景残留 connect / 悬空 Callable
	DayNightState.clear_sinks()
	# B 重生周期 MVP：清理周期推进 sink；不清整局态（_cycle_index / _used_hero_ids 跨场景持久）
	# 整局态 reset 由 _on_restart_pressed 显式触发
	RunState.clear_sinks()
	# E 战斗就地展开 MVP：清空战斗会话防悬空 sink
	# 即使 BattleSession 仍持有 self 的 Callable，场景退出后这里置 null
	# RefCounted 自然回收；on_redraw_requested 在 RefCounted 销毁前不会再被调用
	_battle_session = null


## 初始化子系统（敌方移动、战斗 UI、管理 UI）
func _init_subsystems() -> void:
	var ui_layer: CanvasLayer = $UILayer

	# 敌方移动子系统（注入格子尺寸，保证视觉位置计算与 WorldMap 一致）
	# 同时注入摄像机引用：EnemyMovement 用其计算视口可见矩形，
	# 路径全在视口外时跳过 Tween 直接结算（详见 EnemyMovement._start_animation）
	_enemy_movement = EnemyMovement.new()
	_enemy_movement.name = "EnemyMovement"
	_enemy_movement.tile_size = TILE_SIZE
	_enemy_movement._camera = _camera
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

	# 事件面板 UI（探索体验·F MVP）
	# 挂载位置：所有交互面板之后、VictoryUI 之前——
	#   层级覆盖 ManageUI / BuildPanelUI（玩家先确认事件再操作其他面板），
	#   但低于 VictoryUI（胜负遮罩可覆盖未确认的事件）
	_event_panel = EventPanelUI.new()
	_event_panel.name = "EventPanelUI"
	add_child(_event_panel)
	_event_panel.create_ui(ui_layer)

	# E 战斗就地展开 MVP：战斗内 HUD
	# 挂载位置：EventPanelUI 之后、VictoryUI 之前
	#   战斗态时高于 EventPanelUI（战斗中事件面板被冻结，理论不会同时弹出）
	#   低于 VictoryUI（极端时序下战斗失败 + 末周期失败可能并发，胜负遮罩压顶）
	# 与 _battle_session 同生命周期；HUD 节点常驻但只在战斗态可见
	_battle_hud = BattleHUD.new()
	_battle_hud.name = "BattleHUD"
	add_child(_battle_hud)
	_battle_hud.create_ui(ui_layer)
	_battle_hud.attack_pressed.connect(_on_battle_hud_attack_pressed)
	_battle_hud.skip_pressed.connect(_on_battle_hud_skip_pressed)
	_battle_hud.exit_pressed.connect(_on_battle_hud_exit_pressed)

	# E MVP 探索态【攻击】按钮：玩家回合且触发距离内有敌方包时显示，醒目红色
	# 屏幕中央偏下浮动；与 BattleHUD 行动栏不会同时显示（战斗态时本按钮隐藏）
	_explore_attack_btn = Button.new()
	_explore_attack_btn.name = "ExploreAttackBtn"
	_explore_attack_btn.text = "⚔ 攻击 [F]"
	_explore_attack_btn.visible = false
	_explore_attack_btn.custom_minimum_size = Vector2(160, 44)
	_explore_attack_btn.add_theme_font_size_override("font_size", 18)
	_explore_attack_btn.add_theme_color_override("font_color", Color(1.0, 0.95, 0.85, 1.0))
	# 醒目红色背景 + 金边
	var btn_normal: StyleBoxFlat = StyleBoxFlat.new()
	btn_normal.bg_color = Color(0.78, 0.18, 0.20, 0.95)
	btn_normal.border_width_left = 2
	btn_normal.border_width_right = 2
	btn_normal.border_width_top = 2
	btn_normal.border_width_bottom = 2
	btn_normal.border_color = Color(1.0, 0.84, 0.0, 1.0)
	btn_normal.content_margin_left = 16
	btn_normal.content_margin_right = 16
	btn_normal.content_margin_top = 8
	btn_normal.content_margin_bottom = 8
	_explore_attack_btn.add_theme_stylebox_override("normal", btn_normal)
	var btn_hover: StyleBoxFlat = btn_normal.duplicate() as StyleBoxFlat
	btn_hover.bg_color = Color(0.92, 0.25, 0.27, 0.98)
	_explore_attack_btn.add_theme_stylebox_override("hover", btn_hover)
	var btn_pressed: StyleBoxFlat = btn_normal.duplicate() as StyleBoxFlat
	btn_pressed.bg_color = Color(0.62, 0.12, 0.14, 1.0)
	_explore_attack_btn.add_theme_stylebox_override("pressed", btn_pressed)
	# 屏幕底部偏上居中（避免遮挡 HudBar 顶部 + 与 BattleHUD 错位）
	_explore_attack_btn.anchor_left = 0.5
	_explore_attack_btn.anchor_right = 0.5
	_explore_attack_btn.anchor_top = 1.0
	_explore_attack_btn.anchor_bottom = 1.0
	_explore_attack_btn.offset_bottom = -64
	_explore_attack_btn.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_explore_attack_btn.grow_vertical = Control.GROW_DIRECTION_BEGIN
	ui_layer.add_child(_explore_attack_btn)
	_explore_attack_btn.pressed.connect(_on_explore_attack_pressed)

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

	# D MVP：把 TurnManager.faction_turn_started 包装为 phase_changed
	# attach 内部对同一 turn_manager 重复挂接是幂等的；reload 后旧 turn_manager
	# 会先被 clear_sinks 解绑（_exit_tree 中处理），新场景再 attach 新实例
	DayNightState.attach_to_turn_manager(_turn_manager)
	# 阶段切换时立即触发 redraw，保证夜晚滤镜在 faction 切换瞬间出现
	# （否则要等 EnemyMovement 第一次 redraw_requested 才更新视觉）
	DayNightState.register_phase_changed_sink(_on_day_night_phase_changed)

	# C MVP：扎营里程碑入队 sink 注册——RunState 命中里程碑时回调 _on_recruit_triggered
	# 解绑由 RunState.clear_sinks 在 _exit_tree 处理，与其他 sink 同生命周期
	RunState.register_recruit_sink(_on_recruit_triggered)

# ─────────────────────────────────────────
# 输入处理
# ─────────────────────────────────────────

func _input(event: InputEvent) -> void:
	# 动画播放中、战斗确认中、敌方移动中、管理 / 建造 / 事件面板打开中、扎营中、昏迷过渡中或流程结束时锁定所有输入
	# 事件面板（F MVP）：玩家未确认事件前禁止地图点击 / 空格扎营，避免叠加触发
	# 昏迷过渡（B MVP）：_is_in_coma=true 期间 reload 场景已排队，不允许任何操作
	if _game_finished or _is_moving or _battle_ui.is_pending or _manage_ui.is_open or _enemy_movement.is_moving() or _is_camping or _build_panel_ui.is_open or _event_panel.is_open or _is_in_coma:
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

	# E MVP：探索态【攻击】按钮的可见性紧跟 HUD 刷新
	# 玩家位置 / faction / 各面板状态变化都会调 _update_hud，集中刷新避免遗漏
	_update_explore_action_button()

## 获取所有角色部队的显示文本
## B 重生周期 MVP：首角色（队长）前加 _leader_display_name 前缀，对齐 §7 场景 1
## 验收（HUD 显示当前重生周期的队长名 = hero_pool.csv 中某个英雄）
func _get_all_troops_display() -> String:
	var parts: Array[String] = []
	for i in range(_characters.size()):
		var ch: CharacterData = _characters[i]
		# 队长（[0]）拼名字前缀；其他队员保持原格式（C MVP 入队后再扩展）
		var prefix: String = ""
		if i == 0 and not _leader_display_name.is_empty():
			prefix = "%s · " % _leader_display_name
		if ch.has_troop():
			parts.append("%s%s %d/%d" % [
				prefix,
				ch.troop.get_display_text(),
				ch.troop.current_hp,
				ch.troop.max_hp
			])
		else:
			parts.append("%s角色%d:空" % [prefix, i + 1])
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

	# E 战斗就地展开 MVP：战斗态点击分流
	# 战斗中不走探索态寻路移动；点击 → 攻击范围内敌方 = 攻击；可达格 = 移动；其他无响应
	if _is_in_battle():
		_handle_battle_click(target)
		return

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


## E 战斗就地展开 MVP：战斗态点击分流
##
## 处理顺序（设计 §2.5 / §2.7）：
##   1. 玩家回合 + 当前 actor 存在
##   2. 点击格 = 攻击范围内的敌方单位 → try_player_attack（has_attacked = true → advance）
##   3. 点击格 = 当前 actor 可达格 → try_player_move（has_moved = true，仍可攻击）
##   4. 其他 → 无响应
##
## 攻击 / 移动后调 _post_player_action_check：
##   - has_attacked = true → advance_to_next_player_unit
##   - 否则保留当前 actor 让玩家继续操作（先移动后攻击）
func _handle_battle_click(grid_pos: Vector2i) -> void:
	if _battle_session == null or _battle_session.is_ended():
		return
	if not _battle_session.is_player_turn():
		return
	var actor: BattleUnit = _battle_session.current_actor()
	if actor == null:
		return

	# 优先级 1：点击敌方单位且在攻击范围内 → 攻击
	var hit_unit: BattleUnit = _get_battle_unit_at_pos(grid_pos)
	if hit_unit != null and hit_unit.owner_faction != actor.owner_faction:
		var targets: Array[BattleUnit] = _battle_session.get_attackable_targets()
		if targets.has(hit_unit):
			var result: Dictionary = _battle_session.try_player_attack(hit_unit)
			if result.get("success", false):
				_post_player_action_check()
		# 不在攻击范围内的敌方单位 → 静默（不当作"移动失败"提示）
		return

	# 优先级 2：点击可达格 → 移动
	var reachable: Array[Vector2i] = _battle_session.get_reachable_for_current()
	if reachable.has(grid_pos):
		if _battle_session.try_player_move(grid_pos):
			_post_player_action_check()
		return

	# 其他点击无响应（避免误操作直接结束当前单位）


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

	# E5 旧路径退化：玩家走到敌格触发 BattleUI 弹板的逻辑已移除
	# 设计 §3.1 主动战斗只走 [F] 键；玩家在敌格相邻格（dist ≤ _battle_trigger_range）按 F 进战
	# UNCHALLENGED 敌方 LevelSlot 已被 _get_blocked_positions 加进阻挡，玩家走不到敌格上，
	# 这里不再需要 BattleUI 触发分支。极端时序下若玩家仍意外停在敌格上：
	#   - level.is_interactable() 仍 true，但下方 _try_player_occupy_at 是 noop（LevelSlot 不是 PersistentSlot）
	#   - 玩家可主动按 F 入战（dist == 0 ≤ trigger_range）
	# 无需在此触发 BattleUI

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
	# E MVP：玩家移动后位置变化 → 触发距离内的候选可能变化 → 刷攻击按钮可见性
	_update_explore_action_button()
	queue_redraw()

## 获取所有阻挡位置（击退状态的关卡格）
func _get_blocked_positions() -> Dictionary:
	var blocked: Dictionary = {}
	for pos in _level_slots:
		var lv: LevelSlot = _level_slots[pos] as LevelSlot
		# E5 旧路径退化：UNCHALLENGED 敌方 LevelSlot 也加进玩家阻挡
		# 设计 §3.1 主动战斗只走 [F]，玩家不能再"走到敌格上"触发旧 BattleUI 弹板
		# REPELLED 保留阻挡（击退冷却中不可通行）
		if lv.state == LevelSlot.State.UNCHALLENGED or lv.is_repelled():
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
##
## A 基线收束 MVP：_build_upgrade_enabled 守卫在玩家手动升级入口前置；
## 默认 false 即"按 [B] 不弹板"，给一行 notice 说明，避免玩家不知道键失效。
func _open_build_panel() -> void:
	# E MVP：战斗态守卫——_is_in_battle 期间不允许打开建造面板（设计 §2.10）
	if _game_finished or _battle_ui.is_pending or _is_moving or _manage_ui.is_open or _is_camping or _event_panel.is_open or _is_in_coma or _is_in_battle():
		return
	if not _build_upgrade_enabled:
		_show_notice("当前阶段不可手动升级")
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
	# E MVP：战斗态守卫——_is_in_battle 期间不允许扎营（设计 §2.10）
	if _game_finished or _is_moving or _battle_ui.is_pending or _is_camping or _manage_ui.is_open or _build_panel_ui.is_open or _event_panel.is_open or _is_in_coma or _is_in_battle():
		return
	_is_camping = true
	_camp_count += 1
	# B 重生周期 MVP：累计本周期扎营次数（C MVP 入队判定的输入）
	# 放在 _camp_count += 1 紧后；advance_cycle 时 RunState 会把这个值 push 入 milestones
	RunState.record_camp()

	# D MVP：扎营按下瞬间进入夜晚（用户跑测 2026-05-06 反馈）
	# 不等到 ENEMY_1 回合切换才生效——玩家心智上扎营即入夜
	# override 由 DayNightState 在新 PLAYER 回合开始时自动清
	DayNightState.set_phase_override(DayNightState.Phase.NIGHT)

	# 扎营恢复补给
	# F MVP：作为"扎营整顿"的第一条事件呈现；放在持久 slot 产出之前 push，
	# 保证事件队列顺序与玩家心智一致（先恢复，再产出）
	_supply += _camp_restore
	if _camp_restore > 0:
		_event_panel.push_event(_build_reward_event(
			"扎营休整", "扎营整顿队伍，恢复补给×%d" % _camp_restore
		))

	# M6: 持久 slot 扎营结算（玩家侧）
	# 流程：camp_pos 查 C 作用域覆盖 → 逐 slot 按类型 × 作用域覆盖 → 落地到石料 / 补给 / 背包
	_settle_persistent_camp_production()

	# C 重生周期 MVP：扎营产出事件 push 完后再做里程碑检查
	# 顺序意图：玩家心智上"扎营整顿 → 物资产出 → 新人加入"，叙事节奏自然
	# RunState.check_recruit_milestone 内部命中时调 _on_recruit_triggered → push_event
	# 入队事件因此排在扎营产出事件之后，由 EventPanelUI FIFO 依次弹出
	RunState.check_recruit_milestone(_get_team_hero_ids())

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
	# F MVP：成功条目走事件面板（每条产出独立事件，符合 §3 / §7 场景 2 逐条呈现预期）
	# 失败条目（背包满 / 池空）属于错误反馈，仍走 _show_notice 飘字
	if not applied.is_empty():
		for entry in applied:
			var entry_dict: Dictionary = entry as Dictionary
			var entry_text: String = ProductionSystem.format_results_text([entry_dict])
			_event_panel.push_event(_build_reward_event(
				"扎营产出", "扎营时整顿物资，获得：%s" % entry_text
			))
	if not dropped.is_empty():
		_show_notice("扎营产出部分失败：%s" % ProductionSystem.format_dropped_text(dropped))


## 构造 reward 事件 payload（F MVP §4 reward 模板）
## title / narrative 由调用方组装；本函数只负责套通用结构
## 入库统一在调用方完成，事件仅作叙事呈现，result_callback 留空
func _build_reward_event(title: String, narrative: String) -> Dictionary:
	return {
		"type": "reward",
		"title": title,
		"narrative": narrative,
		"actions": [{"label": "确认", "result": "confirm"}],
		"payload": {},
	}


## 战斗胜利事件 helper：把关卡奖励 + 部队奖励合并到单条事件
## 用户跑测反馈：战斗一次性获得多个奖励应合并展示，避免连点 N 次确认
## rewards 为空（背包满全丢 / 关卡无奖励）则跳过，不弹空事件
func _push_battle_victory_event(rewards: Array[ItemData]) -> void:
	if rewards.is_empty():
		return
	var reward_text: String = _format_rewards_text(rewards)
	_event_panel.push_event(_build_reward_event(
		"战斗胜利", "击败敌方部队，获得：%s" % reward_text
	))


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
	# F MVP：即时 slot 采集走事件面板（与扎营产出同 reward 模板，叙事前缀不同）
	# 池空 / 背包满等失败走 _show_notice，与扎营保持一致
	# 注意：本函数早前已有 var entry，这里循环变量改名避免 shadow 冲突
	if not applied.is_empty():
		for applied_entry in applied:
			var entry_dict: Dictionary = applied_entry as Dictionary
			var entry_text: String = ProductionSystem.format_results_text([entry_dict])
			_event_panel.push_event(_build_reward_event(
				"采集所获", "途经采集所获，获得：%s" % entry_text
			))
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
			# F MVP：回合奖励是"一次性整组"奖励，合并到一条事件呈现
			_event_panel.push_event(_build_reward_event(
				"回合奖励", "回合结束清点物资，获得：%s" % reward_text
			))

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
	# E MVP：切到敌方回合时显式隐藏【攻击】按钮
	# _on_faction_turn_started 仅在 PLAYER 回合刷 _update_hud，敌方阶段不会自动触发刷新
	_update_explore_action_button()


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
	# E4 注入玩家保护区半径（= _battle_trigger_range）：保护区内格 cost = INF
	# 让敌方寻路自然停在保护区边缘，等敌方阶段末尾扫描触发被动战斗
	_enemy_movement.start_phase(
		_schema, _level_slots, _unit.position, target_pos,
		_enemy_movement_points, _original_slot_types, _game_finished,
		_enemy_target_switch_range,
		_forced_battle_range,
		_battle_trigger_range
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
##
## B 重生周期 MVP：reload 前先调 RunState.reset() 清整局态（_cycle_index / _used_hero_ids / _camp_milestones）；
## 否则重开会沿用上一局的周期编号和已用英雄列表，违反"主动重开 = 整局重置"语义
func _on_restart_pressed() -> void:
	RunState.reset()
	get_tree().reload_current_scene()


## D MVP：昼夜阶段切换回调
## 仅作 redraw 触发——保证 faction 切换瞬间夜晚滤镜立刻出现 / 消失
## 未来美术接入时可在此加淡入淡出 Tween；视野限制接入时可在此重算可见格集
func _on_day_night_phase_changed(_phase: int) -> void:
	queue_redraw()


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
##
## B 重生周期 MVP：昏迷过渡期间（_is_in_coma=true）也直接 return——
## 强制战斗触发昏迷时 _post_battle_settlement 会调 _enemy_movement.finish_phase()
## 让 phase_finished 信号发出，但本回调若切回 PLAYER 回合会跑额外 tick / HUD 刷新，
## 1.5s 后 reload 时这些状态被覆盖，但中间存在时序风险（如 tick 触发新增建造）
func _on_enemy_phase_finished() -> void:
	if _game_finished:
		return
	if _is_in_coma:
		return
	if _turn_manager.current_faction != Faction.ENEMY_1:
		push_warning("WorldMap._on_enemy_phase_finished: current_faction != ENEMY_1，忽略该次回调")
		return

	# E4 被动战斗（用户拍板 2026-05-08 与主动战斗语义统一）：
	#   触发判断 = 玩家保护区内（dist ≤ _battle_trigger_range）有敌方包 → 才触发被动战斗
	#   入战范围 = 战场范围（dist ≤ _battle_arena_range）内全部敌方包入战
	#   早前只收集 trigger_range 内会让 dist 4-6 的包游离在战场视觉但不参战
	if not _is_in_battle() and _unit != null:
		var trigger_zone: Array[LevelSlot] = _get_packs_in_range(_unit.position, _battle_trigger_range)
		if not trigger_zone.is_empty():
			var packs_in_arena: Array[LevelSlot] = _get_packs_in_range(_unit.position, _battle_arena_range)
			if packs_in_arena.is_empty():
				packs_in_arena = trigger_zone
			_start_passive_battle(packs_in_arena)
			return

	_turn_manager.end_faction_turn()
	_turn_manager.current_faction = Faction.PLAYER
	_turn_manager.start_faction_turn(Faction.PLAYER)

## 强制战斗触发回调（敌方到达玩家相邻格）
##
## E5 旧路径退化：被动战斗已切到 _on_enemy_phase_finished 末尾扫描保护区机制（设计 §3.2）
## EnemyMovement 自 E4 起不再 emit forced_battle_triggered；此回调理论不应触发
##
## 仍保留连接以防：
##   - EnemyMovement 极端时序下从绕道路径走出 emit（保护区机制兜底失败）
##   - 未清理的旧 connect 仍触达本回调
##
## 走到这里属于异常态：push_warning 标记 + 调 resume_after_battle 让队列继续，
## 不调用旧 BattleUI 弹板（避免新旧战斗系统并发卡死）
func _on_forced_battle_triggered(level: LevelSlot) -> void:
	push_warning("WorldMap._on_forced_battle_triggered: E5 后旧强制战斗路径理论不应触发，level=%s；恢复敌方移动队列" % [level.position if level != null else Vector2i(-1, -1)])
	if _enemy_movement != null:
		_enemy_movement.resume_after_battle()


# ─────────────────────────────────────────
# E 战斗就地展开 MVP — 战斗会话 helper / sink
# ─────────────────────────────────────────
#
# 设计原文：tile-advanture-design/探索体验实装/E_战斗就地展开_MVP.md §3 / §5
#
# 当前实装范围（E2 + E3）：
#   - 主动战斗触发（[F] 键 + dist ≤ _battle_trigger_range 候选包扫描）
#   - 战斗内玩家点击分流（点击敌方 → 攻击；点击可达格 → 移动）
#   - 战斗结束三分支处理（VICTORY 收奖励 + 清理 / MANUAL_EXIT 残余保留 / COMA 走 B MVP 重生）
#
# 不在 E2/E3 范围（留 E4 / E5）：
#   - 被动战斗（_on_enemy_phase_finished 改造留 E4）
#   - 旧强制战斗路径清理（_on_forced_battle_triggered 仍走旧 BattleUI 弹板，E5 才清理）
#
# 守卫语义：_is_in_battle() = true 期间锁定所有面板 / 输入分流；_battle_session sink 退出后清空


## 战斗态守门：_battle_session 非空且未结束
## 沿用 _is_in_coma / _event_panel.is_open 同样的守门模式
## 各守卫函数（_input / _unhandled_key_input / _open_*_panel / _on_abandon / _start_camp）追加该判定
func _is_in_battle() -> bool:
	return _battle_session != null and not _battle_session.is_ended()


## 扫描指定坐标曼哈顿距离 ≤ range 内的敌方关卡（LevelSlot）
## 用于 [F] 主动战斗触发候选 + 后续 E4 被动战斗保护区扫描复用
##
## 命中条件（与 _on_forced_battle_triggered 旧路径语义一致）：
##   - 在距离阈值内
##   - level.is_interactable() = true（UNCHALLENGED 且非冷却）
func _get_packs_in_range(origin: Vector2i, search_range: int) -> Array[LevelSlot]:
	var result: Array[LevelSlot] = []
	for pos in _level_slots:
		var p: Vector2i = pos as Vector2i
		var dist: int = absi(p.x - origin.x) + absi(p.y - origin.y)
		if dist > search_range:
			continue
		var lv: LevelSlot = _level_slots[p] as LevelSlot
		if lv == null or not lv.is_interactable():
			continue
		result.append(lv)
	return result


## 检查指定格上是否有正在参战的敌方 LevelSlot
##
## 战斗中两个独立视觉层（探索态 LevelSlot 红菱形 + BattleUnit 红圆形）会重叠在 LevelSlot 原格，
## 看起来像"敌方分身"。此 helper 让 _draw_tile 在战斗中跳过参战 LevelSlot 的渲染，
## 让战场内视觉只剩 BattleUnit 圆形 + HP 条
##
## 战斗结束 sink 调 _level_slots.erase + 清空 _battle_session 后，本函数自然返回 false，
## _draw_tile 恢复正常渲染
func _is_pack_in_battle(pos: Vector2i) -> bool:
	if _battle_session == null:
		return false
	for pack in _battle_session.participating_packs:
		if pack != null and pack.position == pos:
			return true
	return false


## 在战场上（含玩家方 / 敌方）查找指定格上的存活单位
## _handle_click 战斗态分流用：点击格 → 是否敌方单位 → 攻击；否则当作移动目标
func _get_battle_unit_at_pos(pos: Vector2i) -> BattleUnit:
	if _battle_session == null:
		return null
	for u in _battle_session.player_units:
		if u != null and u.is_active and u.is_alive() and u.battle_position == pos:
			return u
	for u in _battle_session.enemy_units:
		if u != null and u.is_active and u.is_alive() and u.battle_position == pos:
			return u
	return null


## 启动主动战斗（玩家按 [F] 命中候选包后调用）
##
## 流程（设计 §3.1）：
##   1. _supply -= _active_battle_supply_cost
##   2. 创建 BattleSession + 注入 sink
##   3. session.start(...) 完成展开
##   4. 显示 BattleHUD + 触发 redraw（让战场叠加渲染出来）
##
## 调用前由 _try_trigger_active_battle 完成候选 + 补给守卫
func _start_battle_session(packs: Array[LevelSlot]) -> void:
	if packs.is_empty():
		return
	# 补给扣除钳到 ≥0；调用前由 _try_trigger_active_battle 已校验充足
	# 钳位防御 _active_battle_supply_cost > _supply 时不进入负数（被动战斗 E4 路径同样适用）
	_supply = maxi(0, _supply - _active_battle_supply_cost)
	_battle_session = BattleSession.new()
	_battle_session.on_battle_ended = _on_battle_session_ended
	_battle_session.on_redraw_requested = _on_battle_redraw_requested
	_battle_session.start(
		_characters,
		_unit.position,
		packs,
		_schema,
		_battle_arena_range,
		_battle_unit_config,
		_battle_config,
		_terrain_altitude_step,
		_coma_hp_threshold_ratio,
		_round_manager.get_current_round() if _round_manager != null else 0,
		_damage_increment
	)
	# 战斗中清掉探索态可达高亮（避免视觉与战场叠加层干扰）
	_reachable_tiles = {}
	# HUD 先显示（refresh 内部读 session 状态）
	if _battle_hud != null:
		_battle_hud.show_hud(_battle_session)
	_update_hud()
	queue_redraw()
	_debug_report_battle_start("主动", packs)


## E4 被动战斗启动入口
##
## 流程（设计 §3.2 / §2.2）：
##   1. _supply -= _passive_battle_supply_cost 钳到 ≥0（被动是被迫卷入，不阻止触发）
##   2. 全部保护区内 packs 入战（与主动战斗"仅选定包"区别：被动是敌方主动逼近的全部）
##   3. 创建 BattleSession + 注入 sink + start
##   4. 显示 BattleHUD + 触发 redraw
##
## 战斗结束后 sink 通用收尾分支检测 current_faction == ENEMY_1，切回 PLAYER 回合
##（_turn_manager 在战斗中保持 ENEMY_1 不变，与"战斗中世界冻结"§2.9 一致）
func _start_passive_battle(packs: Array[LevelSlot]) -> void:
	if packs.is_empty():
		return
	_supply = maxi(0, _supply - _passive_battle_supply_cost)
	_battle_session = BattleSession.new()
	_battle_session.on_battle_ended = _on_battle_session_ended
	_battle_session.on_redraw_requested = _on_battle_redraw_requested
	_battle_session.start(
		_characters,
		_unit.position,
		packs,
		_schema,
		_battle_arena_range,
		_battle_unit_config,
		_battle_config,
		_terrain_altitude_step,
		_coma_hp_threshold_ratio,
		_round_manager.get_current_round() if _round_manager != null else 0,
		_damage_increment
	)
	_reachable_tiles = {}
	if _battle_hud != null:
		_battle_hud.show_hud(_battle_session)
	_update_hud()
	queue_redraw()
	_debug_report_battle_start("被动", packs)


## 临时诊断：战斗启动时输出参战包数 / 展开 enemy_units 数 / 位置信息
## 跑测验证主动战斗参战范围扩到 _battle_arena_range 后是否真的卷入多个包
## 定位问题后会被清理（commit 历史可追溯）
func _debug_report_battle_start(kind: String, packs: Array[LevelSlot]) -> void:
	if _battle_session == null:
		return
	var pack_positions: Array[String] = []
	for pack in packs:
		if pack != null:
			var d: int = absi(pack.position.x - _unit.position.x) + absi(pack.position.y - _unit.position.y)
			pack_positions.append("%s(d=%d,t=%d)" % [pack.position, d, pack.troops.size()])
	var enemy_count: int = _battle_session.enemy_units.size()
	var inactive_count: int = 0
	for arr in _battle_session.inactive_enemy_troops.values():
		inactive_count += (arr as Array).size()
	var msg: String = "[DEBUG][%s战斗] 玩家=%s | 参战包 %d %s | 上场敌方单位 %d | 未上场 %d" % [
		kind, _unit.position, packs.size(),
		"[" + ", ".join(pack_positions) + "]",
		enemy_count, inactive_count
	]
	push_warning(msg)
	_show_notice(msg, 6.0)


## 玩家按 [F] 主动战斗触发入口
##
## 候选检查 + 多包退化（MVP 简化）：
##   - 候选 == 0 → 无响应
##   - _supply == 0 → notice 提示，不入战
##   - 候选 == 1 → 直接确认
##   - 候选 > 1 → MVP 简化：选最近的包（曼哈顿距离最小）；
##                P1 待跟踪：用 BattleUI 退化为"目标选择"列表
##
## 不放在 _start_battle_session 内是因为被动战斗（E4）会有不同的候选取舍逻辑
func _try_trigger_active_battle() -> void:
	if _unit == null:
		return
	# 队长无部队 → 不能入战；走兜底队伍状态评估（理论上 _evaluate_party_state 此时应已触发昏迷 / 失败）
	# 防御性检查避免 BattleSession._deploy_player_side 落到无 actor 的卡死战斗态
	if _characters.is_empty() or _characters[0] == null or not _characters[0].has_troop():
		_evaluate_party_state()
		return
	# 触发判断：dist ≤ _battle_trigger_range 内有候选 → 才能按 [F]
	var trigger_candidates: Array[LevelSlot] = _get_packs_in_range(_unit.position, _battle_trigger_range)
	if trigger_candidates.is_empty():
		return
	# 补给检查对照 _active_battle_supply_cost（可配置）；当前默认 0 = 不消耗，分支不会拦截
	if _supply < _active_battle_supply_cost:
		_show_notice("补给不足，无法主动进入战斗")
		return
	# 入战范围（用户拍板 2026-05-08）：所有 dist ≤ _battle_arena_range（=6）战场范围内的敌方包都参战
	# 替代原 §3.1 "仅选定包入战" 设计——避免战斗中战场内还有敌方但没参战的尴尬
	# 触发判断仍用 _battle_trigger_range（=3），玩家必须靠近才能触发
	var packs_in_arena: Array[LevelSlot] = _get_packs_in_range(_unit.position, _battle_arena_range)
	if packs_in_arena.is_empty():
		# 边缘情况：触发判断通过但 arena 范围扫描却空（理论不可能，trigger_range ≤ arena_range）
		# 兜底走 trigger_candidates 不至于触发后无人参战
		packs_in_arena = trigger_candidates
	_start_battle_session(packs_in_arena)


## BattleSession 状态变化 sink：刷新战场叠加 + HUD
## 注入到 BattleSession.on_redraw_requested
func _on_battle_redraw_requested() -> void:
	queue_redraw()
	if _battle_hud != null and _battle_session != null:
		_battle_hud.refresh(_battle_session)


## 战斗结束时把战斗内队长位置同步回探索态（设计 §2.8 / §3.4 "玩家位置保持队长当前格"）
##
## 玩家可能在战斗中移动队长几格；战斗结束后探索态单位应停在队长当前 battle_position
## 不同步会导致 _draw_unit_marker / Camera 用旧的开战前位置，玩家观感断裂
##
## 调用时机：sink 处理 VICTORY / MANUAL_EXIT 之前；COMA 走 reload 场景，无需同步
func _sync_world_unit_from_battle_leader() -> void:
	if _battle_session == null or _unit == null:
		return
	if _battle_session.player_units.is_empty():
		return
	var leader_unit: BattleUnit = _battle_session.player_units[0]
	if leader_unit == null or not leader_unit.is_alive():
		return
	_unit.position = leader_unit.battle_position
	_unit_visual_pos = _grid_to_pixel_center(_unit.position)
	if _camera != null:
		_camera.position = _unit_visual_pos


## 战斗结束 sink（设计 §3.4 / §2.8）
##
## 三分支处理：
##   VICTORY     —— 收集每个 defeated_pack 的关卡 / 部队奖励 → 合并 _push_battle_victory_event
##                  → 清理 _level_slots / 恢复 schema slot
##                  → _round_manager.on_level_cleared 推进
##                  → _evaluate_party_state 兜底队员阵亡（队长不会跌阈值，否则走 COMA）
##   MANUAL_EXIT —— 不发奖励，敌方残余保留；_evaluate_party_state 兜底
##   COMA        —— 走 B MVP 重生分支（_trigger_coma_or_lose）
##
## 收尾通用：清空 _battle_session / 隐藏 HUD / 重置移动力 / 刷新可达
func _on_battle_session_ended(reason: int, defeated_packs: Array) -> void:
	# 隐藏 HUD（提前；防止 sink 中 push_event / notice 时 HUD 仍可见干扰）
	if _battle_hud != null:
		_battle_hud.hide_hud()

	if reason == BattleSession.EndReason.COMA:
		# B MVP 重生分支：_trigger_coma_or_lose 内部会处理 _is_in_coma 守卫
		# _battle_session 在 reload 场景后由新 _ready 重新初始化（默认 null），无需手动清
		_battle_session = null
		_trigger_coma_or_lose()
		return

	# E MVP §2.8 / §3.4：胜利 / 手动退出 → 玩家位置保持队长当前格
	# 同步战斗内队长 battle_position 回 _unit.position + 视觉位置 + 摄像机；
	# 不调用会让探索态单位回到开战前位置，违背设计约束
	_sync_world_unit_from_battle_leader()

	if reason == BattleSession.EndReason.VICTORY:
		# 1. 收集合并奖励
		var combined: Array[ItemData] = []
		for pack_v in defeated_packs:
			var pack: LevelSlot = pack_v as LevelSlot
			if pack == null:
				continue
			combined.append_array(_grant_level_rewards_for(pack))
			# 部队抽样奖励：含未上场 troops 一并视作消灭，从 pack.troops 抽样
			combined.append_array(_grant_troop_reward(pack.troops))
		_push_battle_victory_event(combined)

		# 2. 清理 _level_slots + 恢复 schema slot 标记（与 _post_battle_settlement 对齐）
		# 显式 mark_defeated + remove_defeated_troops：保证仍持引用的旁路系统看到一致状态
		for pack_v in defeated_packs:
			var pack: LevelSlot = pack_v as LevelSlot
			if pack == null:
				continue
			pack.remove_defeated_troops()
			pack.mark_defeated()
			var lvpos: Vector2i = pack.position
			if _level_slots.has(lvpos):
				_level_slots.erase(lvpos)
			if _schema != null:
				var orig_type: int = _original_slot_types.get(lvpos, MapSchema.SlotType.NONE) as int
				_schema.set_slot(lvpos.x, lvpos.y, orig_type as MapSchema.SlotType)
				_original_slot_types.erase(lvpos)

		# 3. 轮次推进：每消灭一个包调一次 on_level_cleared
		# advance_round 失败（全部轮次通关）时跳出循环，让下方通用收尾仍然走
		# 旧版直接 return 会绕过"切回 PLAYER 回合"，被动战斗清完末轮时 current_faction
		# 卡在 ENEMY_1（_on_all_rounds_cleared 已弱化为提示，不再 _game_finished = true）
		if _round_manager != null:
			var rounds_finished: bool = false
			for pack_v in defeated_packs:
				var pack: LevelSlot = pack_v as LevelSlot
				if pack == null:
					continue
				# pack.is_defeated() 由前面 mark_defeated() 保证 true；BattleSession 数据自洽
				var round_cleared: bool = _round_manager.on_level_cleared()
				if round_cleared:
					_grant_round_rewards()
					if not _round_manager.advance_round():
						# 全部轮次通关；不再走 advance_round / round_hint，但仍走通用收尾
						rounds_finished = true
						break
					_show_round_hint()
			if rounds_finished:
				# 全部轮次通关 → _on_all_rounds_cleared 已 push notice；流程不需要 _game_finished
				# 通用收尾继续执行，保证 current_faction 正确切回 PLAYER
				pass

	# MANUAL_EXIT：不发奖励，敌方残余保留；走通用收尾

	# 4. 兜底队员阵亡评估（队长跌阈值的极端情况已在战斗中走 COMA 路径，不走到此处）
	# _evaluate_party_state 返回 true 表示已触发昏迷 / 失败遮罩，无需再走收尾流程
	if _evaluate_party_state():
		_battle_session = null
		return

	# 5. 通用收尾：清状态 + 重置移动力 + 刷新可达
	_battle_session = null
	if _unit != null:
		_unit.current_movement = _unit.max_movement

	# E4 被动战斗收尾：current_faction == ENEMY_1 表示战斗在敌方阶段末尾触发
	# 这里替代 _on_enemy_phase_finished 末尾的"切 PLAYER"逻辑（被动战斗时跳过了那一段）
	# 走 end_faction_turn + start_faction_turn 让 TickRegistry / EnemyAI / DayNightState 正常运转
	if _turn_manager != null and _turn_manager.current_faction == Faction.ENEMY_1 and not _game_finished:
		_turn_manager.end_faction_turn()
		_turn_manager.current_faction = Faction.PLAYER
		_turn_manager.start_faction_turn(Faction.PLAYER)

	_refresh_reachable()
	_update_hud()
	queue_redraw()


## 玩家行动后判断：当前单位回合结束（has_attacked = true）→ 自动切下一玩家单位
## try_player_attack 已置 has_attacked = true；try_player_move 仅 has_moved，不切
##
## 切到下一单位 / 切敌方回合都由 BattleSession.advance_to_next_player_unit 处理
## 敌方回合启动后由 _step_enemy_turn_loop 串行驱动
func _post_player_action_check() -> void:
	if _battle_session == null or _battle_session.is_ended():
		return
	if not _battle_session.is_player_turn():
		return
	var actor: BattleUnit = _battle_session.current_actor()
	if actor == null or actor.has_attacked:
		_battle_session.advance_to_next_player_unit()
		# 切到敌方回合 → 串行驱动敌方单位行动
		if _battle_session.is_enemy_turn():
			_run_enemy_turn_async()


## 敌方回合串行驱动（异步推进 + 帧间插入避免一次性吞行动）
##
## 用 SceneTreeTimer 短暂间隔（0.18s/单位）让玩家能看清每个敌方单位的行动
## 间隔内 BattleSession.on_redraw_requested 触发 HUD / 战场叠加刷新
##
## 战斗结束（_check_battle_end_after_action 命中胜利 / 昏迷）时 step_enemy_turn 返回 false
## sink 已在 BattleSession.end 中触发；这里只需停止串行
func _run_enemy_turn_async() -> void:
	if _battle_session == null or _battle_session.is_ended():
		return
	if not _battle_session.is_enemy_turn():
		return
	var has_more: bool = _battle_session.step_enemy_turn()
	if _battle_session == null or _battle_session.is_ended():
		return
	if has_more:
		var t: SceneTreeTimer = get_tree().create_timer(0.18)
		t.timeout.connect(_run_enemy_turn_async)
	# has_more = false 时 step_enemy_turn 内部已切回玩家回合，HUD 自动通过 redraw_requested 刷新


# ─── BattleHUD 按钮 sink ───

## [攻击] 按钮：MVP 简化 = 攻击范围内 hp 最低的目标
## 玩家若想换目标，直接点击地图敌人触发 _handle_click 战斗态分流
func _on_battle_hud_attack_pressed() -> void:
	if _battle_session == null or _battle_session.is_ended():
		return
	if not _battle_session.is_player_turn():
		return
	var targets: Array[BattleUnit] = _battle_session.get_attackable_targets()
	if targets.is_empty():
		return
	# hp 最低的（与 BattleAI 决策一致）
	var picked: BattleUnit = targets[0]
	for i in range(1, targets.size()):
		if targets[i].troop.current_hp < picked.troop.current_hp:
			picked = targets[i]
	var result: Dictionary = _battle_session.try_player_attack(picked)
	if not result.get("success", false):
		return
	_post_player_action_check()


## [跳过] 按钮：当前单位本回合行动结束（先移动后攻击都不做 / 移动后不攻击）
func _on_battle_hud_skip_pressed() -> void:
	if _battle_session == null or _battle_session.is_ended():
		return
	if not _battle_session.is_player_turn():
		return
	_battle_session.skip_current_unit()
	_post_player_action_check()


## [退出战斗] 按钮：try_manual_exit 内部检查战场内是否仍有敌方
## 失败 → 提示玩家；成功时 BattleSession.end 自动调 sink 完成收尾
func _on_battle_hud_exit_pressed() -> void:
	if _battle_session == null or _battle_session.is_ended():
		return
	if not _battle_session.try_manual_exit():
		_show_notice("战场内仍有敌人，无法退出")


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

## 所有轮次通关回调
## B 重生周期 MVP：原"流程胜利"语义降级——单轮配置下"所有关卡通关"只是周期内里程碑，
## 不再触发整局胜利。整局胜利仅由 VictoryJudge（攻占敌方核心）触发。
## 这里只显示一条"本周期关卡全部清完"提示，不切 _game_finished、不弹遮罩。
func _on_all_rounds_cleared() -> void:
	_show_notice("本周期关卡全部清完")

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

	# 我方扣血；命中昏迷 / 失败时立即中断，避免在过渡期间发战斗胜利事件 / 推奖励
	# 强制战斗路径需要主动结束敌方阶段；非强制场景直接 return 等场景 reload
	if _apply_player_damages(result):
		if was_forced:
			_enemy_movement.finish_phase()
		return

	# 敌方扣血
	level.apply_enemy_damages(result.enemy_damages)
	var all_wiped: bool = level.remove_defeated_troops()

	if all_wiped:
		# 击退但全灭 → 转为击败，发放奖励
		# F MVP：关卡奖励 + 部队奖励合并到一条战斗胜利事件中展示
		level.mark_defeated()
		var battle_rewards: Array[ItemData] = []
		battle_rewards.append_array(_grant_level_rewards_for(level))
		battle_rewards.append_array(_grant_troop_reward(troop_snapshot))
		_push_battle_victory_event(battle_rewards)
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

	# 我方扣血；命中昏迷 / 失败时立即中断（同 _on_battle_repel_chosen 处理）
	if _apply_player_damages(result):
		if was_forced:
			_enemy_movement.finish_phase()
		return

	# 敌方扣血
	level.apply_enemy_damages(result.enemy_damages)
	level.remove_defeated_troops()

	# 标记为击败
	level.mark_defeated()

	# F MVP：发放关卡奖励 + 部队奖励，合并到一条战斗胜利事件中展示
	var battle_rewards: Array[ItemData] = []
	battle_rewards.append_array(_grant_level_rewards_for(level))
	battle_rewards.append_array(_grant_troop_reward(troop_snapshot))
	_push_battle_victory_event(battle_rewards)

	# 后处理
	_post_battle_settlement(level, was_forced)

## 战斗取消回调：关闭弹板，恢复输入
func _on_battle_cancelled() -> void:
	_battle_ui.hide()
	_refresh_reachable()

## 为我方部队应用伤害（从 BattleResult 中提取 damages），同时追踪累计损兵
##
## B 重生周期 MVP：返回 _evaluate_party_state() 的结果
##   - true → 已触发昏迷过渡 / 末周期失败遮罩；调用方应立即中断奖励发放 / 事件推送 / 后处理
##   - false → 战斗流程继续
##
## 战斗 / 强制战斗均经过本函数，是玩家方 hp 变化的最主要入口
func _apply_player_damages(result: BattleResolver.BattleResult) -> bool:
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
	return _evaluate_party_state()

## 从敌方部队快照中随机抽取 1 支，转为 TROOP 道具加入背包
## 背包已满时直接丢弃
## F MVP 重构：返回入库成功的 items，由调用方汇总到战斗胜利事件中合并展示
func _grant_troop_reward(troop_snapshot: Array[TroopData]) -> Array[ItemData]:
	if troop_snapshot.is_empty():
		return [] as Array[ItemData]
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
		return [item] as Array[ItemData]
	return [] as Array[ItemData]

## 发放指定关卡的胜利奖励
## F MVP 重构：返回入库成功的 items，由调用方汇总到战斗胜利事件中合并展示
## MVP 简化：暂不区分 dropped（背包满），与重构前的 _show_notice 行为一致
func _grant_level_rewards_for(level: LevelSlot) -> Array[ItemData]:
	if level == null or level.rewards.is_empty():
		return [] as Array[ItemData]
	_inventory.add_items(level.rewards)
	return level.rewards.duplicate()

## 战斗后共用处理：更新 HUD、失败判定、轮次推进
## 若处于敌方移动阶段的强制战斗，结算后继续处理移动队列
## M7 迁移：原"首次战斗后激活敌方"逻辑移除，敌方 AI 开局即活跃（初始预置 5 支 + 每 5 回合增援）
func _post_battle_settlement(level: LevelSlot, was_forced: bool) -> void:

	_update_hud()
	queue_redraw()

	# B 重生周期 MVP：先评估队伍状态（队员阵亡移除 / 队长昏迷阈值）
	# 返回 true 表示已进入昏迷过渡或失败遮罩，中断后续流程；强制战斗时通知敌方阶段收场
	if _evaluate_party_state():
		if was_forced:
			_enemy_movement.finish_phase()
		return
	# 兜底：极端态下队伍数组完全空（理论已被 _evaluate_party_state 接管）
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
	# E MVP：战斗态守卫——_is_in_battle 期间不允许装配 / 用道具（设计 §2.10）
	if _game_finished or _battle_ui.is_pending or _is_moving or _is_camping or _event_panel.is_open or _is_in_coma or _is_in_battle():
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
	# B 重生周期 MVP：装配换部队后队长 max_hp / current_hp 比例可能跌到阈值（如把高 hp 旧部队换成低 hp 新部队）
	_evaluate_party_state()

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
	# B 重生周期 MVP：道具使用后队长状态可能改变（HP_RESTORE 仅会脱离阈值，不会触发昏迷；
	# 但 EXP 升级品质后 max_hp 会刷新，理论上有跨阈值可能。统一调用以保持入口对齐）
	_evaluate_party_state()

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

## 从 RunState 抽队长 + 装配初始部队（B 重生周期 MVP）
##
## A MVP 起 `_characters` 只构造一个角色（队长）；后续队员由 [[C_扎营里程碑入队_MVP]] 追加。
## B MVP 起兵种 / 品质来源切换：从 player_config 的 initial_troop_quality 改为 hero_pool.csv 行字段。
##   - troop_type / troop_quality 字段名按 TroopData.TroopType / Quality 枚举名（"SWORD"/"R" 等）
##   - 兵种枚举不在 hero_pool 中预设时回退到 SWORD，品质回退到 R
##
## 重生事件占位：函数末尾消费 RunState._pending_respawn_intro
##   - true → _play_respawn_intro_anim() + 文字 "新指挥官 X 接过指挥权……"
##   - false → 跳过（首次进入不显示介绍）
##
## 参数 player_cfg 暂保留：留作未来 hero_pool 缺省时的兜底字段来源；本期不再读 character_count
func _init_player(player_cfg: Dictionary) -> void:
	# 默认品质：hero_pool 行未填或解析失败时回退
	var default_quality: int = int(player_cfg.get("initial_troop_quality", "0"))

	_characters = []
	_total_max_hp = 0

	# 从 RunState 抽未使用的英雄；返回的 leader_row 浅拷贝
	# RunState.ensure_initialized 已在 _ready 早期调用过；此处直接 draw
	var leader_row: Dictionary = RunState.draw_new_leader()
	_leader_display_name = String(leader_row.get("name", "队长"))

	# 单角色：队长占据 _characters[0]，其余空位由 C MVP 入队事件追加
	var ch: CharacterData = CharacterData.new()
	ch.id = 1
	# C MVP：写入 hero_id，让 draw_recruit 能正确排除当前在队英雄
	ch.hero_id = int(leader_row.get("id", "-1"))
	var troop: TroopData = TroopData.new()
	troop.troop_type = _parse_troop_type(String(leader_row.get("troop_type", "SWORD")))
	troop.quality = _parse_troop_quality(String(leader_row.get("troop_quality", "")), default_quality)
	# 重新按品质设置 max_hp（TroopData 默认构造未走品质表，这里保守按 R 兜底；
	#   若未来 TroopData 引入按品质 max_hp 表，删除这段即可）
	ch.troop = troop
	_total_max_hp += troop.max_hp
	_characters.append(ch)

	# 重生事件占位（B MVP）
	# RunState.advance_cycle 时置 _pending_respawn_intro=true；
	# 新场景 _ready → _init_player 末尾消费一次后清零
	if RunState.consume_pending_respawn_intro():
		_play_respawn_intro_anim()
		_show_notice("新指挥官 %s 接过指挥权……" % _leader_display_name)


## 兵种枚举字符串 → TroopData.TroopType
## 解析失败回退到 SWORD（hero_pool.csv 写错字段时不至于崩）
func _parse_troop_type(name: String) -> TroopData.TroopType:
	match name.to_upper():
		"SWORD":   return TroopData.TroopType.SWORD
		"BOW":     return TroopData.TroopType.BOW
		"SPEAR":   return TroopData.TroopType.SPEAR
		"CAVALRY": return TroopData.TroopType.CAVALRY
		"SHIELD":  return TroopData.TroopType.SHIELD
		_:
			push_warning("WorldMap._parse_troop_type: 未知兵种 '%s'，回退 SWORD" % name)
			return TroopData.TroopType.SWORD


## 品质字符串 → TroopData.Quality；空字符串走 default
func _parse_troop_quality(name: String, default_quality: int) -> TroopData.Quality:
	if name.is_empty():
		return default_quality as TroopData.Quality
	match name.to_upper():
		"R":   return TroopData.Quality.R
		"SR":  return TroopData.Quality.SR
		"SSR": return TroopData.Quality.SSR
		_:
			push_warning("WorldMap._parse_troop_quality: 未知品质 '%s'，回退 R" % name)
			return TroopData.Quality.R


## 重生介绍美术接口（B MVP §2 占位 / P1 待跟踪扩展挂点）
## MVP 阶段空实现；完整版升级为 [[F_事件面板基础_MVP]] 的 respawn 事件类型 + 立绘 + 过场动画
func _play_respawn_intro_anim() -> void:
	pass


## 昏迷态美术接口（B MVP §2 占位 / P1 待跟踪扩展挂点）
## MVP 阶段空实现；完整版升级为独立面板 + 立绘 + 过场动画
func _play_coma_anim() -> void:
	pass


# ─────────────────────────────────────────
# C MVP — 扎营里程碑入队
# ─────────────────────────────────────────

## 收集当前队伍中所有有 hero_id 的成员 ID（用于 RunState.draw_recruit 排除）
## hero_id == -1 的角色（老路径 / 测试构造）跳过——不会影响"未在队伍中"判定
func _get_team_hero_ids() -> Array[int]:
	var ids: Array[int] = []
	for ch in _characters:
		if ch == null:
			continue
		if ch.hero_id >= 0:
			ids.append(ch.hero_id)
	return ids


## RunState.check_recruit_milestone 命中时回调
## hero_dict 来自 hero_pool 行；milestone 是触发的扎营次数
##
## 构造 recruit 事件 payload，把 hero_id 通过 payload 传给确认回调
## EventPanelUI 已支持 result_callback；玩家点确认 → 调 _on_recruit_confirmed 装配新队员
func _on_recruit_triggered(hero_dict: Dictionary, milestone: int) -> void:
	if _event_panel == null:
		push_warning("WorldMap._on_recruit_triggered: EventPanelUI 未就绪，事件丢弃")
		return
	var hero_name: String = String(hero_dict.get("name", "新成员"))
	var event: Dictionary = {
		"type": "recruit",
		"title": "新成员加入",
		"narrative": "扎营第 %d 次时，%s 闻讯前来加入队伍。" % [milestone, hero_name],
		"actions": [{"label": "确认", "result": "confirm"}],
		# payload 里塞整个 hero_dict —— 确认时不依赖闭包，避免重新查 hero_pool
		"payload": hero_dict,
		"result_callback": Callable(self, "_on_recruit_confirmed"),
	}
	_event_panel.push_event(event)


## 玩家点确认入队事件后回调
## payload 即 hero_dict（_on_recruit_triggered 中塞入）
##
## 流程：构造 CharacterData + 装配初始部队（troop_type / troop_quality）→ append → HUD
## 不去重：MVP 不检查兵种重复——_get_team_hero_ids 已保证不抽到当前在队成员
func _on_recruit_confirmed(_action_result: String, payload: Dictionary) -> void:
	if payload.is_empty():
		push_warning("WorldMap._on_recruit_confirmed: payload 为空，入队跳过")
		return
	var hero_id: int = int(payload.get("id", "-1"))
	if hero_id < 0:
		push_warning("WorldMap._on_recruit_confirmed: hero_id 非法，入队跳过")
		return
	# 防御：极端时序下 _on_recruit_confirmed 触发时该英雄已被其他途径加入
	for ch_existing in _characters:
		if ch_existing != null and ch_existing.hero_id == hero_id:
			push_warning("WorldMap._on_recruit_confirmed: hero_id=%d 已在队，跳过重复入队" % hero_id)
			return
	# 构造 CharacterData
	var member: CharacterData = CharacterData.new()
	# id 在队伍中按 size+1 递增；与队长保持简单序号语义
	member.id = _characters.size() + 1
	member.hero_id = hero_id
	var troop: TroopData = TroopData.new()
	troop.troop_type = _parse_troop_type(String(payload.get("troop_type", "SWORD")))
	# 入队队员品质：hero_pool 行未填时回退 R（队员相对队长更平均）
	troop.quality = _parse_troop_quality(String(payload.get("troop_quality", "")), TroopData.Quality.R)
	member.troop = troop
	_total_max_hp += troop.max_hp
	_characters.append(member)
	_update_hud()
	# C MVP P1 修复：扎营流程在 push 入队事件后立刻 _manage_ui.open(...)，确认入队事件时
	# 装配面板已打开且按旧 _characters 渲染过 refresh；这里补一次 refresh 让新队员
	# 在本次扎营内立即可见 / 可装配（设计文档 §6 数据驱动语义 + §7 场景 2 验收）
	if _manage_ui != null and _manage_ui.is_open:
		_manage_ui.refresh()


# ─────────────────────────────────────────
# 多角色辅助方法
# ─────────────────────────────────────────

## 判断是否有任意角色已装配部队
func _has_any_troop() -> bool:
	for ch in _characters:
		if ch.has_troop():
			return true
	return false

## B 重生周期 MVP：评估队伍状态（队员阵亡移除 + 队长昏迷阈值判定）
##
## 流程：
##   1. 倒序遍历 _characters[1..]：troop == null 或 current_hp <= 0 → 移除（队员阵亡不复活）
##   2. 检查 _characters[0] 队长：troop == null 或 current_hp / max_hp ≤ _coma_hp_threshold_ratio
##      → 调 _trigger_coma_or_lose
##
## 返回 true 表示已触发昏迷态或失败遮罩，调用方应中断后续流程。
##
## 触发挂点：_apply_player_damages / _post_battle_settlement / _on_use_item / _on_equip_troop 末尾。
## 守卫：_is_in_coma / _game_finished 时直接返回 true，避免重入。
func _evaluate_party_state() -> bool:
	if _game_finished or _is_in_coma:
		return true
	# 1. 队员阵亡 → 从队伍移除（倒序避免索引漂移）
	for i in range(_characters.size() - 1, 0, -1):
		var ch_member: CharacterData = _characters[i]
		if ch_member == null:
			_characters.remove_at(i)
			continue
		if not ch_member.has_troop():
			_characters.remove_at(i)
			continue
		if ch_member.troop.current_hp <= 0:
			_characters.remove_at(i)
	# 2. 队长检查
	if _characters.is_empty():
		# 极端态：连队长都没了 → 走兜底重生 / 失败分支
		_trigger_coma_or_lose()
		return true
	var leader: CharacterData = _characters[0]
	if leader == null or not leader.has_troop():
		_trigger_coma_or_lose()
		return true
	var troop: TroopData = leader.troop
	if troop.max_hp <= 0:
		# 数据异常；不强制触发昏迷以免误判，写日志
		push_warning("WorldMap._evaluate_party_state: 队长 max_hp <= 0，跳过阈值判定")
		return false
	var ratio: float = float(troop.current_hp) / float(troop.max_hp)
	if ratio <= _coma_hp_threshold_ratio:
		_trigger_coma_or_lose()
		return true
	return false


## B 重生周期 MVP：队长昏迷或末周期失败分支
##
## 路径：
##   - RunState.respawns_left() > 0 → 进入昏迷态：锁输入 + 文字占位 + 美术接口（空实现）
##                                    → SceneTreeTimer 走完后 advance_cycle + reload_current_scene
##   - 否则                          → 末周期失败 → _on_victory_decided(ENEMY_1) 走 VictoryUI 失败遮罩
##
## 幂等：_is_in_coma / _game_finished 守卫，重复调用不重复触发
func _trigger_coma_or_lose() -> void:
	if _is_in_coma or _game_finished:
		return
	if RunState.respawns_left() > 0:
		_is_in_coma = true
		_reachable_tiles = {}
		# 重生事件占位（B MVP §2 / §8）
		# 文字 _show_notice + 美术接口 _play_coma_anim（空实现）；P1 完整版升级为 F MVP respawn 事件
		_show_notice("队长 %s 倒下了……" % _leader_display_name, _coma_duration_sec)
		_play_coma_anim()
		queue_redraw()
		# 计时结束 → 推进周期 + reload；新场景 _ready 走 ensure_initialized 时
		# _initialized=true 直接 return，沿用 _used_hero_ids / _cycle_index
		var coma_timer: SceneTreeTimer = get_tree().create_timer(_coma_duration_sec)
		coma_timer.timeout.connect(_on_coma_timer_finished)
	else:
		# 末周期无保护 → 整局失败（沿用现有 VictoryUI 失败遮罩）
		_on_victory_decided(Faction.ENEMY_1)


## 昏迷计时结束回调：推进 RunState + reload 场景
## reload 前再校验一次 _game_finished，避免极端时序下的重入（如 reload 期间被外部触发）
func _on_coma_timer_finished() -> void:
	if _game_finished:
		return
	RunState.advance_cycle()
	get_tree().reload_current_scene()


## 全灭兜底（B MVP 退化）：仅在 _characters 为空时触发；正常昏迷 / 失败路径已被 _evaluate_party_state 接管
##
## 仍保留是因为：极端时序（外部代码清空 _characters）或老调用点未迁到 _evaluate_party_state 时
## 不至于"无人则永久卡死"。返回 true 表示游戏已结束，调用方应中断后续流程。
func _check_defeat() -> bool:
	if _game_finished:
		return true
	if _is_in_coma:
		# 已进入昏迷过渡，等 timer 走完即可
		return true
	if _characters.is_empty():
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
## F MVP：轮次通关奖励合并展示在一条事件中
func _grant_round_rewards() -> void:
	if _round_manager == null:
		return
	var rewards: Array[ItemData] = _round_manager.get_round_rewards()
	if rewards.is_empty():
		return
	_inventory.add_items(rewards)
	var reward_text: String = _format_rewards_text(rewards)
	_event_panel.push_event(_build_reward_event(
		"轮次通关", "通关本轮，获得：%s" % reward_text
	))


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
	# B 重生周期 MVP：昏迷过渡期间锁 Q 键放弃，否则会让 _on_coma_timer_finished 提前 return 截断重生流程
	# E MVP：战斗态期间锁 Q 键放弃（设计 §2.10）；战斗结束才允许整局放弃
	if _game_finished or _battle_ui.is_pending or _is_moving or _manage_ui.is_open or _is_camping or _build_panel_ui.is_open or _is_in_coma or _is_in_battle():
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
	# F MVP：事件面板打开时锁定 M / B / Q 等快捷键，避免绕过事件面板的"阻塞玩家操作"语义
	if _event_panel != null and _event_panel.is_open:
		return
	# B MVP：昏迷过渡期间锁所有快捷键，等 reload_current_scene 走完
	if _is_in_coma:
		return
	if event is InputEventKey:
		var key: InputEventKey = event as InputEventKey
		if key.pressed and not key.echo:
			# E MVP [F] 键独立处理：探索态触发主动战斗 / 战斗态尝试手动退出
			# 放在战斗态守卫之前，[F] 在两态语义不同
			if key.keycode == KEY_F:
				_handle_f_key()
				return
			# E MVP 战斗态：禁用 [M] / [B] / [Q] 等其他面板键
			# 战斗中不能装配 / 建造 / 放弃（设计 §2.10）
			if _is_in_battle():
				return
			# M 键：打开/关闭装配管理面板
			if key.keycode == KEY_M:
				if _manage_ui.is_open:
					_manage_ui.close()
				else:
					_open_manage_panel()
			# B 键：打开/关闭建造面板（M5）
			# A 基线收束 MVP：玩家手动升级入口默认关；按下直接给 notice 不打开面板。
			# 真正的守卫已在 _open_build_panel 内完成；这里前置 return 是显式语义层防御
			# （未来若放开手动升级，仅改 _build_upgrade_enabled 即可，无需删守卫）。
			elif key.keycode == KEY_B:
				if not _build_upgrade_enabled and not _build_panel_ui.is_open:
					_show_notice("当前阶段不可手动升级")
					return
				if _build_panel_ui.is_open:
					_build_panel_ui.close()
				else:
					_open_build_panel()
			# Q 键：放弃流程
			elif key.keycode == KEY_Q:
				_on_abandon()


## 探索态【攻击】按钮点击 sink：等价于按 [F]
## 同样守卫由 _handle_f_key 内部处理（保持单一入口避免守卫漂移）
func _on_explore_attack_pressed() -> void:
	_handle_f_key()


## 刷新探索态【攻击】按钮可见性
##
## 显示条件（全部满足）：
##   - 不在战斗中
##   - 不在游戏结束 / 移动动画 / 昏迷过渡 / 各面板打开
##   - 当前是 PLAYER 回合
##   - 敌方移动阶段未在执行
##   - 玩家位置 dist ≤ _battle_trigger_range 内有可交互敌方包
##
## 调用时机：_update_hud / _refresh_reachable / sink 末尾 / faction 切换 / 战斗结束
## 这些点覆盖了所有可能让条件变化的场景
func _update_explore_action_button() -> void:
	if _explore_attack_btn == null:
		return
	var should_show: bool = _can_show_explore_attack()
	_explore_attack_btn.visible = should_show


## 探索态【攻击】按钮可见性条件评估
## 抽出独立函数避免在 _update_explore_action_button 里堆守卫表达式
func _can_show_explore_attack() -> bool:
	if _is_in_battle():
		return false
	if _game_finished or _is_moving or _is_in_coma or _is_camping:
		return false
	if _battle_ui != null and _battle_ui.is_pending:
		return false
	if _manage_ui != null and _manage_ui.is_open:
		return false
	if _build_panel_ui != null and _build_panel_ui.is_open:
		return false
	if _event_panel != null and _event_panel.is_open:
		return false
	if _enemy_movement != null and _enemy_movement.is_moving():
		return false
	if _turn_manager == null or _turn_manager.current_faction != Faction.PLAYER:
		return false
	if _unit == null:
		return false
	if _characters.is_empty() or _characters[0] == null or not _characters[0].has_troop():
		return false
	var candidates: Array[LevelSlot] = _get_packs_in_range(_unit.position, _battle_trigger_range)
	return not candidates.is_empty()


## E MVP [F] 键 sink：探索态触发主动战斗 / 战斗态尝试手动退出
##
## 探索态守卫覆盖（防止在错位时序入战）：
##   _is_moving / _battle_ui.is_pending / _manage_ui.is_open / _is_camping / _build_panel_ui.is_open
##   _is_in_coma（昏迷过渡，B MVP）/ _enemy_movement.is_moving（敌方移动阶段）
##   非 PLAYER 回合（敌方阶段不可主动入战）
##
## 战斗态：BattleHUD 退出按钮按下也走 _on_battle_hud_exit_pressed，与 [F] 同语义
func _handle_f_key() -> void:
	if _is_in_battle():
		if not _battle_session.try_manual_exit():
			_show_notice("战场内仍有敌人，无法退出")
		return
	# 探索态：补给 / 候选 / 触发由 _try_trigger_active_battle 内部判定
	if _game_finished or _is_in_coma or _is_moving or _battle_ui.is_pending or _manage_ui.is_open or _is_camping or _build_panel_ui.is_open:
		return
	if _enemy_movement != null and _enemy_movement.is_moving():
		return
	if _turn_manager != null and _turn_manager.current_faction != Faction.PLAYER:
		return
	_try_trigger_active_battle()

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
	# UI 重构步骤 7：可达范围双通道渲染
	#   - 整格铺 REACHABLE_COLOR（alpha 0.08，轻量背景提示）
	#   - 外边界描边（只画邻居不在集合内的那条边），蓝白冷调
	# 视觉效果：弱铺色提供"整体可达感"，描边提供"清晰边界"
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

		# 边界描边：4 邻居中不在集合内的方向画一条边
		var px: float = float(pos.x * TILE_SIZE)
		var py: float = float(pos.y * TILE_SIZE)
		var pw: float = float(TILE_SIZE)
		# 上邻
		if not _reachable_tiles.has(Vector2i(pos.x, pos.y - 1)):
			draw_line(Vector2(px, py), Vector2(px + pw, py),
				REACHABLE_BORDER_COLOR, REACHABLE_BORDER_WIDTH)
		# 下邻
		if not _reachable_tiles.has(Vector2i(pos.x, pos.y + 1)):
			draw_line(Vector2(px, py + pw), Vector2(px + pw, py + pw),
				REACHABLE_BORDER_COLOR, REACHABLE_BORDER_WIDTH)
		# 左邻
		if not _reachable_tiles.has(Vector2i(pos.x - 1, pos.y)):
			draw_line(Vector2(px, py), Vector2(px, py + pw),
				REACHABLE_BORDER_COLOR, REACHABLE_BORDER_WIDTH)
		# 右邻
		if not _reachable_tiles.has(Vector2i(pos.x + 1, pos.y)):
			draw_line(Vector2(px + pw, py), Vector2(px + pw, py + pw),
				REACHABLE_BORDER_COLOR, REACHABLE_BORDER_WIDTH)

	# 第三层：敌方关卡移动动画标记
	if _enemy_movement.get_moving_level() != null:
		_draw_enemy_move_marker()

	# 第四层：单位标记（基于视觉位置）
	# E MVP：战斗态由 _draw_battle_overlay 渲染战场上的队长（按 battle_position），
	# 跳过探索态单位 marker，避免与战场队长重叠
	if _unit != null and not _is_in_battle():
		_draw_unit_marker()

	# 第五层：D MVP 夜晚滤镜占位
	# 仅在 is_night 时叠加深蓝半透明覆盖整个地图区域；HUD 在独立 CanvasLayer 不受影响
	# 后续接美术时替换为渐变 / shader（见 D MVP §8 备注）
	if DayNightState.is_night(_turn_manager):
		var night_rect: Rect2 = Rect2(
			Vector2.ZERO,
			Vector2(_schema.width, _schema.height) * TILE_SIZE
		)
		draw_rect(night_rect, Color(0.5, 0.5, 0.7, 0.35), true)

	# 第六层：E MVP 战场叠加（战斗态时渲染战场边框 / 单位 / 移动+攻击高亮 / HP 条）
	# 渲染顺序在夜晚滤镜之后：让战场单位 / 高亮不被夜晚色调遮罩，保证战斗操作的可见性
	if _is_in_battle():
		_draw_battle_overlay()

## 绘制单格地形色块及 Slot 标记
func _draw_tile(x: int, y: int) -> void:
	var terrain: MapSchema.TerrainType = _schema.get_terrain(x, y)
	var base_color: Color = TERRAIN_COLORS.get(terrain, Color.MAGENTA) as Color

	# UI 重构步骤 9：基于 (x, y) 哈希给地形加轻量亮度噪声 ±5%
	# 同 seed 结果一致（不闪烁），只为打破整齐色块的"表格感"
	var noise: float = _terrain_brightness_noise(x, y)
	base_color = Color(
		clampf(base_color.r + noise, 0.0, 1.0),
		clampf(base_color.g + noise, 0.0, 1.0),
		clampf(base_color.b + noise, 0.0, 1.0),
		base_color.a
	)

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

		# 敌方格统一标准敌方红底色；其他 slot 使用 SLOT_COLORS 兜底色
		var slot_color: Color
		if level != null:
			# 正在移动的关卡跳过静态渲染（由 _draw_enemy_move_marker 负责）
			if level == _enemy_movement.get_moving_level():
				return
			# E MVP 战斗态：参战 LevelSlot 跳过敌方关卡视觉，让 BattleUnit 圆形独占视觉
			# 避免 LevelSlot 红菱形 + BattleUnit 红圆形重叠"敌方分身"观感
			# 战斗结束 sink 清理 _level_slots 后本格自然不再走入这个分支
			if _is_pack_in_battle(pos):
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

		# 敌方菱形按 tier 取尺寸梯度（弱 75% → 超 90%）；其他 slot 仍用统一 SLOT_MARGIN
		var rect_margin: int = SLOT_MARGIN
		if is_enemy and not is_repelled and not level.is_defeated() and ENEMY_TIER_SLOT_MARGINS.has(level.tier):
			rect_margin = ENEMY_TIER_SLOT_MARGINS[level.tier]
		var slot_rect: Rect2 = Rect2(
			x * TILE_SIZE + rect_margin,
			y * TILE_SIZE + rect_margin,
			TILE_SIZE - rect_margin * 2 - 1,
			TILE_SIZE - rect_margin * 2 - 1
		)
		# 敌方关卡用菱形绘制，其他 Slot 保持矩形
		if is_enemy:
			_draw_diamond(slot_rect, slot_color)
		else:
			draw_rect(slot_rect, slot_color)

		# 敌方关卡：菱形描边 + 米字小菱形图形（仅活跃状态）
		# 视觉栈简化为 3 层：底色（统一红） → 外描边（黑红 + 宽度梯度） → 金色小菱形（米字累积）
		if is_enemy:
			var border_color: Color = REPELLED_BORDER_COLOR
			var border_width: float = TIER_BORDER_WIDTHS.get(1, 2.5)  ## 兜底用中档宽度
			if not is_repelled and not level.is_defeated():
				border_color = TIER_BORDER_COLOR
				border_width = TIER_BORDER_WIDTHS.get(level.tier, 2.5)
			_draw_diamond(slot_rect, border_color, false, border_width)
			# 米字 4 小菱形：按 tier 累积点亮（活跃状态）
			if not is_repelled and not level.is_defeated():
				_draw_enemy_tier_pattern(slot_rect, level.tier)

## 即时资源点盲盒色（M6 视觉统一：采集前不显示具体类型，避免与"等权采集"规则冲突）
## UI 重构步骤 5：从冷灰 #8C8C99 改为暖浅灰 #B8B8B0（接近木箱感）+ 白描边，
## 让资源点更像"可拾取对象"而非占位符
const RESOURCE_BLIND_BOX_COLOR: Color = Color(0.72, 0.72, 0.69)        ## 暖浅灰  #B8B8B0
const RESOURCE_BLIND_BOX_OUTLINE: Color = Color(1.0, 1.0, 1.0, 0.85)   ## 白描边 alpha 0.85
const RESOURCE_BLIND_BOX_OUTLINE_WIDTH: float = 2.0

## 绘制资源点标记方块 + 文字
## M6 P1 修复：即时 slot 采集走 4 项等权池（忽略 slot 自身 resource_type），
## 视觉上若按类型着色会误导玩家（以为是定向资源），故统一为盲盒灰色 + "?"
## 原按类型着色的 RESOURCE_*_COLOR 常量保留以备他处引用，但本函数不再使用
##
## UI 重构步骤 5：箱体感 —— 浅灰底 + 白描边 + "?"
## 形状保持方块（不改菱形，避免和敌方混淆）；语义上仍是盲盒不泄露类型
func _draw_resource_slots() -> void:
	for pos in _resource_slots:
		var rs: ResourceSlot = _resource_slots[pos] as ResourceSlot
		# 已采集的资源点不渲染
		if rs.is_collected:
			continue
		var p: Vector2i = pos as Vector2i

		var rs_rect: Rect2 = Rect2(
			p.x * TILE_SIZE + SLOT_MARGIN,
			p.y * TILE_SIZE + SLOT_MARGIN,
			TILE_SIZE - SLOT_MARGIN * 2 - 1,
			TILE_SIZE - SLOT_MARGIN * 2 - 1
		)
		# 箱体：浅灰底 + 白描边 + 内部 "?"
		draw_rect(rs_rect, RESOURCE_BLIND_BOX_COLOR)
		draw_rect(rs_rect, RESOURCE_BLIND_BOX_OUTLINE, false, RESOURCE_BLIND_BOX_OUTLINE_WIDTH)

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
## UI 重构步骤 2 + 调色迭代：
##   v1 `#4D8CF2` 和 LOWLAND `#4D8CBF` 几乎同色，冲突严重
##   v2 `#3D70E0` 调冷但 R 分量和洼地完全一致，只在 B 差 0.21，仍低对比度
##   v3 饱和青蓝 `#1A8FE6`：R 大幅降 (0.10)，G 提高 (0.56)，
##        明度约 170 vs 洼地 110，差距 60 拉开；保留蓝色身份
## ENEMY 调色（Civ 风格地形重构后续）：
##   地形改沼泽褐 / 暖灰绿后整体推到暖色家族，原 ENEMY_1 `#E65959`（饱和 0.62）
##   与暖地形色相距离仅 ~35°，且饱和度低于玩家蓝（0.89），"势力色独占高饱和"被破坏；
##   现升至 `#FF3D4D`：H=355° 略偏冷红脱开暖橙，S=0.76 与玩家蓝同档，V=1.0 最亮
const M4_FACTION_COLORS: Dictionary = {
	0: Color(0.55, 0.55, 0.55),   ## NONE 中立 — 灰  #8C8C8C
	1: Color(0.10, 0.56, 0.90),   ## PLAYER — 饱和青蓝  #1A8FE6
	2: Color(1.00, 0.24, 0.30),   ## ENEMY_1 — 饱和冷红  #FF3D4D（饱和 0.76 与玩家蓝同档）
}

## 影响范围覆盖层 alpha（半透明，避免遮挡地形 / 单位 / 可达高亮）
## 沿革：
##   - UI 重构步骤 4：从 0.15 降到 0.08，势力范围明确退为辅助层
##   - Civ 化阶段 A：分层渐变 —— 外圈高、内圈低，营造"势力辐射"感
##     d_to_edge = r - (|dx| + |dy|)：菱形最外圈 d=0、向内逐层 +1
##     外圈格（d=0）= OUTER，次外（d=1）= MID，再内（d≥2）= INNER
const M4_INFLUENCE_ALPHA_OUTER: float = 0.22  ## 最外圈格：辐射感"亮边"
const M4_INFLUENCE_ALPHA_MID: float = 0.12    ## 次外圈格：过渡
const M4_INFLUENCE_ALPHA_INNER: float = 0.05  ## 内圈格：极淡，让据点本体居于中心

## 影响范围菱形外边界描边参数
## 决策背景：填充统一色会让相邻同势力 slot 的菱形融成一片、分不清各自边界；
## 追加描边后每个 slot 一条独立轮廓，相邻 slot 重叠处形成双线，视觉可辨
##
## 调色沿革：
##   v1 纯势力色 alpha 0.55 → v2 势力色暗化 × 0.4 + alpha 0.70（BDE 阶段，对抗洼地蓝撞色）
##   v3（Civ 化阶段 A）势力色原色 alpha 1.0 + 宽 3.0：
##     地形改沼泽褐 / 暖灰绿且整体去饱和后，势力色原色站在地形上反而最跳，
##     无须再暗化；加宽到 3.0 让外缘锐利识别归属
const M4_INFLUENCE_BORDER_ALPHA: float = 1.0
const M4_INFLUENCE_BORDER_WIDTH: float = 3.0

## 核心城镇金色描边（凸显势力首都）
const M4_CORE_TOWN_BORDER: Color = Color(1.0, 0.85, 0.0)

## 持久 slot 三层结构（UI 重构步骤 1 + 调色迭代）
## 外环势力色（归属识别）→ 白色分离线（几何分离，即使色相冲突也能识别）→ 内底米白（文字承载）
## 核心城镇额外金色中心徽记强化"首都"仪式感
##
## 三层而非双层的理由：当玩家蓝 / 敌方红与地形色相近时（如玩家蓝 vs 洼地蓝），
## 仅靠势力色 + 米白内底仍可能低对比度；加一条白色分离线确保几何边界清晰
const M4_PERSISTENT_RING_WIDTH: int = 4                           ## 外环厚度 px（占格 48 × 8%）
const M4_PERSISTENT_SEPARATOR_COLOR: Color = Color(1.0, 1.0, 1.0) ## 分离线纯白
const M4_PERSISTENT_SEPARATOR_WIDTH: int = 1                      ## 分离线厚度 px
const M4_PERSISTENT_INNER_BG: Color = Color(0.90, 0.88, 0.83)     ## 内底米白  #E6E0D4
const M4_CORE_TOWN_EMBLEM_SIZE: int = 8                           ## 核心城镇下方徽记（金色小菱形）边长 px


## 绘制所有已占据持久 slot 的影响范围覆盖层（曼哈顿菱形内所有格）
## 中立 slot / influence_range <= 0 不渲染
## 覆盖层先于 slot 本体绘制，保证本体图案可见；相邻 slot 覆盖区域色彩叠加属预期
##
## Civ 化阶段 A：硬外缘 + 内向渐变
##   填充：每格按"距菱形边界距离 d_to_edge = r - (|dx|+|dy|)"分层 alpha
##         外圈（d=0）OUTER 0.22 → 次外（d=1）MID 0.12 → 内层（d≥2）INNER 0.05
##         视觉：势力辐射从据点向外扩散，外圈最亮形成菱形"光环"
##         同势力 slot 重叠区填充 alpha 自然叠加变亮，语义即"势力辐射加成"
##   描边：势力合集化 —— 先构建每势力的全格 Dictionary 集合，
##         再对菱形内每格检查 4 邻居是否仍在该势力合集中；
##         不在 → 该边为合集外缘，用势力色原色 alpha 1.0 实线画出
##         效果：同势力相邻 / 重叠 slot 自动合并为单一外轮廓，无内部双线
##         跨势力相邻仍各画各的外缘 → 形成敌我双线，分清势力区
func _draw_persistent_influence_ranges() -> void:
	if _schema == null:
		return

	# 第一遍：按势力构建影响范围全格合集（Dictionary[Vector2i, bool] 去重）
	# 用于第二遍判定"邻居是否仍在该势力影响范围内"
	var faction_cells: Dictionary = {}
	for entry in _schema.persistent_slots:
		var slot: PersistentSlot = entry as PersistentSlot
		if slot == null:
			continue
		if slot.owner_faction == Faction.NONE:
			continue
		if slot.influence_range <= 0:
			continue
		var faction_id: int = slot.owner_faction
		if not faction_cells.has(faction_id):
			faction_cells[faction_id] = {}
		var cells: Dictionary = faction_cells[faction_id] as Dictionary
		var r0: int = slot.influence_range
		var cx0: int = slot.position.x
		var cy0: int = slot.position.y
		for dy0 in range(-r0, r0 + 1):
			var y0: int = cy0 + dy0
			if y0 < 0 or y0 >= _schema.height:
				continue
			var dx0_max: int = r0 - absi(dy0)
			for dx0 in range(-dx0_max, dx0_max + 1):
				var x0: int = cx0 + dx0
				if x0 < 0 or x0 >= _schema.width:
					continue
				cells[Vector2i(x0, y0)] = true

	# 第二遍：每个 slot 独立画填充（按距自己菱形边界分层），描边查询势力合集
	for entry in _schema.persistent_slots:
		var slot: PersistentSlot = entry as PersistentSlot
		if slot == null:
			continue
		if slot.owner_faction == Faction.NONE:
			continue
		if slot.influence_range <= 0:
			continue
		var base: Color = M4_FACTION_COLORS.get(slot.owner_faction, Color.MAGENTA) as Color
		# 描边色：势力色原色 + alpha 1.0，地形已去饱和，原色最跳
		var border: Color = Color(base.r, base.g, base.b, M4_INFLUENCE_BORDER_ALPHA)
		var cells: Dictionary = faction_cells[slot.owner_faction] as Dictionary
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
				# 距菱形外边界的曼哈顿距离：r 圈最外为 0、向内逐层递增
				var d_to_edge: int = r - (absi(dx) + absi(dy))
				var fill_alpha: float
				if d_to_edge == 0:
					fill_alpha = M4_INFLUENCE_ALPHA_OUTER
				elif d_to_edge == 1:
					fill_alpha = M4_INFLUENCE_ALPHA_MID
				else:
					fill_alpha = M4_INFLUENCE_ALPHA_INNER
				var overlay: Color = Color(base.r, base.g, base.b, fill_alpha)
				var rect: Rect2 = Rect2(
					x * TILE_SIZE,
					y * TILE_SIZE,
					TILE_SIZE - 1,
					TILE_SIZE - 1
				)
				draw_rect(rect, overlay)

				# 描边：合集化判定 —— 邻居不在该势力影响合集 → 该边为合集外缘
				# 同势力相邻 / 重叠 slot 自动合并为单一外轮廓
				# 跨势力或地图边界保持外缘画线
				var px: float = float(x * TILE_SIZE)
				var py: float = float(y * TILE_SIZE)
				var pw: float = float(TILE_SIZE)
				# 上邻
				if not cells.has(Vector2i(x, y - 1)):
					draw_line(Vector2(px, py), Vector2(px + pw, py),
						border, M4_INFLUENCE_BORDER_WIDTH)
				# 下邻
				if not cells.has(Vector2i(x, y + 1)):
					draw_line(Vector2(px, py + pw), Vector2(px + pw, py + pw),
						border, M4_INFLUENCE_BORDER_WIDTH)
				# 左邻
				if not cells.has(Vector2i(x - 1, y)):
					draw_line(Vector2(px, py), Vector2(px, py + pw),
						border, M4_INFLUENCE_BORDER_WIDTH)
				# 右邻
				if not cells.has(Vector2i(x + 1, y)):
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

		# 三层结构：外环势力色 → 白分离线 → 内底米白
		# 即使势力色和地形色相近（如玩家蓝 ↔ 洼地蓝），白分离线也能清晰勾出据点边界
		draw_rect(outer, color)
		var ring: int = M4_PERSISTENT_RING_WIDTH
		var separator_rect: Rect2 = Rect2(
			outer.position + Vector2(ring, ring),
			outer.size - Vector2(ring * 2, ring * 2)
		)
		if separator_rect.size.x > 0 and separator_rect.size.y > 0:
			draw_rect(separator_rect, M4_PERSISTENT_SEPARATOR_COLOR)
			# 内底再内缩 separator_width，米白承载文字
			var sep: int = M4_PERSISTENT_SEPARATOR_WIDTH
			var inner: Rect2 = Rect2(
				separator_rect.position + Vector2(sep, sep),
				separator_rect.size - Vector2(sep * 2, sep * 2)
			)
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


## 绘制敌方 tier 米字小菱形图形（按 tier 累积点亮）
## 弱档（tier 0）特殊处理：单菱形**居外菱形正中**，与外菱形已显著缩小（67% 占格）共同强化"弱"语义
## 中/强/超档：按米字 4 方向（上/下/左/右）累积点亮，每个小菱形为外菱形 ENEMY_TIER_DOT_SIZE_RATIO 倍尺寸
##
## 点亮策略：
##   tier 0 弱：1 个**居中**小菱形 —— "小且单点居中"语义
##   tier 1 中：上 + 下 2 个（垂直对称，米字方向）
##   tier 2 强：上 + 左 + 右 3 个（T 型，米字方向）
##   tier 3 超：4 个全亮（米字阵列）
##
## 弱档单独居中而非"上"的理由：1 个 vs 3 个的位置完全不同（中央 vs 米字外缘），
##                            视觉语义不会模糊（中点单兵 vs 外缘环绕）
##
## 颜色：金色填充（无描边）—— 与红底高对比，不喧宾夺主
func _draw_enemy_tier_pattern(outer_rect: Rect2, tier: int) -> void:
	var px: float = outer_rect.position.x
	var py: float = outer_rect.position.y
	var w: float = outer_rect.size.x
	var h: float = outer_rect.size.y
	# 小菱形尺寸 + 半边距
	var dot_size: Vector2 = Vector2(w, h) * ENEMY_TIER_DOT_SIZE_RATIO
	var dot_half: Vector2 = dot_size * 0.5
	# 弱档：居外菱形正中
	if tier == 0:
		var center_pt: Vector2 = Vector2(px + w / 2.0, py + h / 2.0)
		var center_rect: Rect2 = Rect2(center_pt - dot_half, dot_size)
		_draw_diamond(center_rect, ENEMY_TIER_DOT_COLOR)
		return
	# 中/强/超：米字 4 方向中心点（上/下偏移 h/4，左/右偏移 w/4）
	var top_center: Vector2 = Vector2(px + w / 2.0, py + h / 4.0)
	var bottom_center: Vector2 = Vector2(px + w / 2.0, py + h * 3.0 / 4.0)
	var left_center: Vector2 = Vector2(px + w / 4.0, py + h / 2.0)
	var right_center: Vector2 = Vector2(px + w * 3.0 / 4.0, py + h / 2.0)
	# 4 个小菱形 rect
	var top_rect: Rect2 = Rect2(top_center - dot_half, dot_size)
	var bottom_rect: Rect2 = Rect2(bottom_center - dot_half, dot_size)
	var left_rect: Rect2 = Rect2(left_center - dot_half, dot_size)
	var right_rect: Rect2 = Rect2(right_center - dot_half, dot_size)
	# 按 tier 收集要点亮的小菱形
	var lit: Array[Rect2] = []
	if tier == 1:
		lit.append(top_rect)
		lit.append(bottom_rect)
	elif tier == 2:
		lit.append(top_rect)
		lit.append(left_rect)
		lit.append(right_rect)
	elif tier == 3:
		lit.append(top_rect)
		lit.append(bottom_rect)
		lit.append(left_rect)
		lit.append(right_rect)
	else:
		return
	# 每个小菱形：金色实心填充，无描边
	for r in lit:
		_draw_diamond(r, ENEMY_TIER_DOT_COLOR)


## UI 重构步骤 9：地形亮度噪声辅助函数
## 基于 (x, y) 的确定性哈希返回 ±TERRAIN_NOISE_RANGE 范围内的亮度偏移
## 同 seed 结果一致，不闪烁；目的只为打破"整齐表格感"
func _terrain_brightness_noise(x: int, y: int) -> float:
	# 素数混合 → [0, 100) 整数 → 归一化到 [-1, 1]
	var h: int = (x * 73856093) ^ (y * 19349663)
	var bucket: int = absi(h) % 100
	var normalized: float = (float(bucket) / 50.0) - 1.0    # [-1, 1]
	return normalized * TERRAIN_NOISE_RANGE


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
##   1. 投影：圆形右下偏移 +2px 的半透明黑
##   2. 玩家蓝外环：实色大圆，承担"我方"身份识别
##   3. 白色内圆：内底，承载"我"字 + 与地形保持对比度
##   4. 文字：居中"我"字
##
## 形状选择圆而非方：
##   - 与玩家建筑（方/菱）形成"形状即语义"区分，避免远观混淆
##   - 与可达范围白色硬边（矩形格 4 邻接拼成的矩形轮廓）形态不同，不被吞没
##   - 圆形契合"棋子"语义
func _draw_unit_marker() -> void:
	var center: Vector2 = Vector2(_unit_visual_pos.x, _unit_visual_pos.y)
	var radius: float = float(TILE_SIZE - UNIT_MARGIN * 2) * 0.5

	# 投影：右下偏移 2px、半透明黑；圆形棋子感
	draw_circle(center + Vector2(2, 2), radius, UNIT_SHADOW_COLOR)

	# 玩家蓝外环（实色大圆）—— 与玩家建筑外环同色，统一"我方"语义
	var ring_color: Color = M4_FACTION_COLORS[Faction.PLAYER] as Color
	draw_circle(center, radius, ring_color)

	# 白色内圆（半径减环宽）—— 在地形上保留对比度，并承载文字
	draw_circle(center, radius - UNIT_PLAYER_RING_WIDTH, UNIT_COLOR)

	# "我"字居中
	if _label_font != null:
		_draw_slot_label(_unit_visual_pos, "我", Color(0.15, 0.15, 0.15))


# ─────────────────────────────────────────
# E 战斗就地展开 MVP — 战场叠加渲染
# ─────────────────────────────────────────
#
# 设计原文：tile-advanture-design/探索体验实装/E_战斗就地展开_MVP.md §5 改动 2 / §2.5
#
# 渲染顺序（_draw 末尾追加）：
#   1. 战场范围内填充 + 边框（黄色 alpha 0.6 / 宽 2px）
#   2. 当前玩家单位的可达格（白色 alpha 0.15）
#   3. 当前玩家单位的可攻击目标格（红色 alpha 0.22）
#   4. 玩家方 / 敌方所有上场单位（圆形 + 阵营色 + 当前 actor 加粗白环）
#   5. 单位下方 HP 条（绿/黄/红按 hp_ratio）

const BATTLE_ARENA_BORDER_COLOR: Color = Color(1.0, 0.85, 0.0, 0.65)
const BATTLE_ARENA_BORDER_WIDTH: float = 2.0
const BATTLE_REACHABLE_COLOR: Color = Color(1.0, 1.0, 1.0, 0.16)
const BATTLE_ATTACKABLE_COLOR: Color = Color(1.0, 0.20, 0.20, 0.28)
const BATTLE_CURRENT_ACTOR_RING: Color = Color(1.0, 1.0, 1.0, 1.0)
const BATTLE_CURRENT_ACTOR_RING_WIDTH: float = 3.0
const BATTLE_HP_BAR_WIDTH: int = 24
const BATTLE_HP_BAR_HEIGHT: int = 4
const BATTLE_HP_COLOR_FULL: Color = Color(0.20, 0.85, 0.30, 1.0)
const BATTLE_HP_COLOR_MID: Color = Color(0.95, 0.85, 0.20, 1.0)
const BATTLE_HP_COLOR_LOW: Color = Color(0.90, 0.25, 0.25, 1.0)
const BATTLE_HP_BAR_BG: Color = Color(0.0, 0.0, 0.0, 0.55)


## 战场叠加主入口：按层渲染战斗内的所有视觉元素
func _draw_battle_overlay() -> void:
	if _battle_session == null:
		return
	var arena: Rect2i = _battle_session.arena
	if arena.size.x <= 0 or arena.size.y <= 0:
		return

	# 1. 战场边框（黄色描边）
	var arena_px: Rect2 = Rect2(
		Vector2(arena.position.x * TILE_SIZE, arena.position.y * TILE_SIZE),
		Vector2(arena.size.x * TILE_SIZE, arena.size.y * TILE_SIZE)
	)
	draw_rect(arena_px, BATTLE_ARENA_BORDER_COLOR, false, BATTLE_ARENA_BORDER_WIDTH)

	# 2/3. 当前玩家单位的可达 / 可攻击高亮（仅玩家回合）
	if _battle_session.is_player_turn():
		# 可达格（白色 alpha 0.16）
		var reachable: Array[Vector2i] = _battle_session.get_reachable_for_current()
		for pos in reachable:
			var rect: Rect2 = Rect2(
				pos.x * TILE_SIZE + 2, pos.y * TILE_SIZE + 2,
				TILE_SIZE - 4, TILE_SIZE - 4
			)
			draw_rect(rect, BATTLE_REACHABLE_COLOR)
		# 可攻击目标格（红色 alpha 0.28）
		var targets: Array[BattleUnit] = _battle_session.get_attackable_targets()
		for tgt in targets:
			var p: Vector2i = tgt.battle_position
			var rect: Rect2 = Rect2(
				p.x * TILE_SIZE + 2, p.y * TILE_SIZE + 2,
				TILE_SIZE - 4, TILE_SIZE - 4
			)
			draw_rect(rect, BATTLE_ATTACKABLE_COLOR)

	# 4/5. 单位渲染 + HP 条（玩家方 → 敌方顺序，确保当前 actor 高亮在最上）
	var current_actor: BattleUnit = _battle_session.current_actor()
	for u in _battle_session.player_units:
		_draw_battle_unit(u, current_actor)
	for u in _battle_session.enemy_units:
		_draw_battle_unit(u, current_actor)


## 渲染单个战场单位：圆形阵营色 + 当前 actor 白环 + HP 条
##
## 未上场（is_active = false）/ 已死（is_alive = false）单位不渲染
## 当前 actor（is current）加粗白外环 3px，提示玩家"轮到此单位"
func _draw_battle_unit(u: BattleUnit, current_actor: BattleUnit) -> void:
	if u == null or not u.is_active or not u.is_alive():
		return
	var center: Vector2 = Vector2(
		u.battle_position.x * TILE_SIZE + TILE_SIZE * 0.5,
		u.battle_position.y * TILE_SIZE + TILE_SIZE * 0.5
	)
	var radius: float = float(TILE_SIZE - UNIT_MARGIN * 2) * 0.5
	# 投影
	draw_circle(center + Vector2(2, 2), radius, UNIT_SHADOW_COLOR)
	# 阵营色填充
	var fill: Color = M4_FACTION_COLORS.get(u.owner_faction, Color.MAGENTA) as Color
	draw_circle(center, radius, fill)
	# 当前 actor 加粗白环
	if u == current_actor and not _battle_session.is_ended():
		draw_arc(
			center, radius + 1.5,
			0.0, TAU,
			32, BATTLE_CURRENT_ACTOR_RING, BATTLE_CURRENT_ACTOR_RING_WIDTH
		)
	# HP 条（单位下方）
	_draw_battle_hp_bar(center, radius, u.troop)


## HP 条：背景黑底 + 前景按 hp_ratio 三段配色
##   ≥ 0.66 绿；0.33 ~ 0.66 黄；< 0.33 红
func _draw_battle_hp_bar(center: Vector2, radius: float, troop: TroopData) -> void:
	if troop == null or troop.max_hp <= 0:
		return
	var ratio: float = clampf(float(troop.current_hp) / float(troop.max_hp), 0.0, 1.0)
	var bar_w: float = float(BATTLE_HP_BAR_WIDTH)
	var bar_h: float = float(BATTLE_HP_BAR_HEIGHT)
	var bar_x: float = center.x - bar_w * 0.5
	var bar_y: float = center.y + radius + 4.0
	# 背景
	draw_rect(Rect2(bar_x, bar_y, bar_w, bar_h), BATTLE_HP_BAR_BG, true)
	# 前景按 hp_ratio
	var fg: Color = BATTLE_HP_COLOR_LOW
	if ratio >= 0.66:
		fg = BATTLE_HP_COLOR_FULL
	elif ratio >= 0.33:
		fg = BATTLE_HP_COLOR_MID
	if ratio > 0.0:
		draw_rect(Rect2(bar_x, bar_y, bar_w * ratio, bar_h), fg, true)
