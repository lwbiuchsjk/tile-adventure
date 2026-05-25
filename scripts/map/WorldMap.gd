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
##   EnemyMovement — 敌方关卡移动（队列/寻路/动画）
##   ManageUI — 装配管理面板（角色状态/背包/操作卡片）

# ─────────────────────────────────────────
# 配置文件路径
# ─────────────────────────────────────────

const CONFIG_MAP: String = "res://assets/config/map_config.csv"
## P0 第二阶段（整局节奏重设计）：周期级配置（地图尺寸 / 持久 slot 数量 / spawn 节奏）
## 按 RunState.cycle_index() 取行；缺失时回退 map_config 字段
const CONFIG_CYCLE: String = "res://assets/config/cycle_config.csv"
const CONFIG_TERRAIN: String = "res://assets/config/terrain_config.csv"
const CONFIG_SLOT: String = "res://assets/config/slot_config.csv"
const CONFIG_PCG: String = "res://assets/config/pcg_config.csv"
const CONFIG_UNIT: String = "res://assets/config/unit_config.csv"
const CONFIG_COUNTER: String = "res://assets/config/counter_matrix.csv"
const CONFIG_ENEMY_POOL: String = "res://assets/config/enemy_troop_pool.csv"
const CONFIG_ITEM: String = "res://assets/config/item_config.csv"
const CONFIG_LEVEL_REWARD_POOL: String = "res://assets/config/level_reward_pool.csv"
const CONFIG_TURN_REWARD_POOL: String = "res://assets/config/turn_reward_pool.csv"
const CONFIG_HP_RATIO: String = "res://assets/config/hp_ratio_config.csv"
const CONFIG_ENEMY_TIER: String = "res://assets/config/enemy_tier_config.csv"
const CONFIG_ENEMY_TIER_RATIO: String = "res://assets/config/enemy_tier_ratio_config.csv"
const CONFIG_RESOURCE_SLOT: String = "res://assets/config/resource_slot_config.csv"
const CONFIG_TOWN_TROOP_POOL: String = "res://assets/config/town_troop_pool.csv"
## B 重生周期 MVP：英雄池 + 整局周期参数
const CONFIG_HERO_POOL: String = "res://assets/config/hero_pool.csv"
## 入口 2 MVP 2.3(2026-05-11):事件叙事文本随机池
const CONFIG_NARRATIVE_POOL: String = "res://assets/config/event_narrative_pool.csv"
## E 战斗就地展开 MVP：兵种战斗参数（移动 / 攻击范围）
const CONFIG_BATTLE_UNIT: String = "res://assets/config/battle_unit_config.csv"
const CONFIG_GARRISON: String = "res://assets/config/garrison_config.csv"
## 敌方援军（敌方援军_MVP / L1.4）：独立强度配置表，列结构同 garrison_config.csv
const CONFIG_ENEMY_GARRISON: String = "res://assets/config/enemy_garrison_config.csv"

# ─────────────────────────────────────────
# 渲染常量
# ─────────────────────────────────────────

## 每格像素尺寸（参见 Design/地图格子视觉规范.md）
## 入口 4 第 1 份 MVP（地格放大与镜头）：48 → 72；基线分辨率 1280×720 下单屏 17×10 格
const TILE_SIZE: int = 72

## 地形 / 槽位 / 可达性高亮渲染常量 → MVP-B.2 阶段 1 迁移到 MAP_BASE_CFG（见本文件下方 Resource preload 段）
## 设计要点（地形 Civ 风格去饱和 / 可达性"立即操作 > 长期状态"层级）保留在 map_base_config.gd schema 内

## 单位渲染 / 已挑战变暗 / 敌方层级视觉 → MVP-B.2 阶段 2 迁移到 UNIT_ENEMY_CFG（见本文件下方 Resource preload 段）
## 设计要点（圆形棋子 / 敌方红 v5 三通道 / 米字小菱形累积点亮 / 占格梯度 67%-92%）保留在 unit_enemy_config.gd schema 内

# MVP-B.2 阶段 3 scope 调整（2026-05-17）：原 RESOURCE_SUPPLY/HP/EXP/STONE_COLOR 4 个无活跃使用方
# （M6 视觉统一为盲盒态后，_draw_resource_slots 只画盲盒不区分类型色）—— 死代码清理，未迁 Resource。
# 历史背景：M1 重构后 ResourceSlot 仅承载一次性产出，持久 slot 视觉走 M4 新常量。

## 敌方动态（移动 / 光晕 / 击退冷却）→ MVP-B.2 阶段 2 迁移到 UNIT_ENEMY_CFG（见本文件下方 Resource preload 段）

## 字号 / 单位移动 / 醒目提示时长 → MVP-B.2 阶段 1 迁移到 MAP_BASE_CFG（见本文件下方 Resource preload 段）

## 入口 4 MVP（2026-05-09 跑测补丁）：探索态 HUD 底栏占用预留
## 修复：玩家贴地图底边时，HudBar 浮在地图上方 → 队长视觉被 HUD 遮挡
## 方案：Camera2D.offset.y 向下偏 OFFSET 让玩家在屏幕几何中心上方；同时扩展
##       limit_bottom，允许 camera 继续下移到地图边外（屏幕底部 RESERVE 像素正好被 HUD 遮）
## 数值：60 px = HudBar 实测 ~40px + 20px 安全间距
const EXPLORE_HUD_BOTTOM_RESERVE_PX: int = 60

## 入口 4 MVP（2026-05-10 HTML 跑测补丁）：offset.y 与 limit_top 对称偏移的共享推导值
## offset.y = +OFFSET 让画面下移；limit_top = -OFFSET 让 camera 可上越界相同距离 → 顶行不裁
## 显式抽常量避免"修一处忘一处"，并防 RESERVE 改奇数时 int 除法导致 offset/limit_top 失对称
const EXPLORE_HUD_OFFSET_PX: int = EXPLORE_HUD_BOTTOM_RESERVE_PX / 2

## 项目主字体（FontVariation = SourceHanSansSC + NotoColorEmoji fallback）
## 入口 4 MVP（2026-05-10 HTML 跑测）：preload 形式让编辑期校验路径，与项目其他 const 风格一致
## Web 端 ThemeDB.fallback_font 仅含 ASCII，无 OS 字体回退，所有 draw_string() 直绘必须显式用本字体
const MAIN_FONT: Font = preload("res://assets/font/main_font.tres")

## MVP-δ 阶段 2：夜晚视野相关常量 + FogSignalNode 内嵌类整体迁到 NightVisionLayer.gd
## 设计文档：tile-advanture-design/代码健康度回看/MVP-δ_拆分批2.md
## 原区块：入口 4 后段第 1 份（夜晚视野 MVP，2026-05-11）—— 含 11 常量 + 内嵌 FogSignalNode 类


# ─────────────────────────────────────────
# 节点引用
# ─────────────────────────────────────────

## Camera2D 节点（场景中配置，已开启 position_smoothing）
@onready var _camera: Camera2D = $Camera2D

## HUD 分区标签
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

## 装配管理面板子系统
var _manage_ui: ManageUI = null

## 建造面板子系统（M5）
var _build_panel_ui: BuildPanelUI = null

## 敌方 AI（M7）
var _enemy_ai: EnemyAI = null

## 世界视图 facade（MVP-β）—— EnemyAI / EnemyReinforcement 访问世界的唯一入口
var _world_view: WorldView = null

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
## P0 第二阶段（整局节奏重设计）：当前周期 PCG 生成的敌方 CORE_TOWN 原始位置
## 缓存到字段供 EnemyReinforcement.spawn_batch 用作 spawn 锚（不查 owner，玩家占领后仍 spawn）
## 在 _load_pcg 之后从 schema 找敌方 CORE_TOWN 位置写入；reload 后重新缓存
var _enemy_core_origin_pos: Vector2i = Vector2i(-1, -1)

## P0 第二阶段：周期级配置原始行数据（按 cycle_index 索引）
var _cycle_config_rows: Array = []

## P0 第二阶段：enemy_tier_ratio_config 原始行数据（按 cycle_index × tier 配 count 权重）
## EnemyReinforcement.spawn_batch 抽 tier 时使用
var _enemy_tier_ratio_rows: Array = []

## P0 第二阶段：缓存当前周期的 initial_enemy_pack_count（由 _apply_cycle_config 注入）
var _current_cycle_initial_pack_count: int = 5

## P0 第二阶段：缓存当前周期的 reinforcement_interval（由 _apply_cycle_config 注入）
var _current_cycle_reinforcement_interval: int = 5

## P0 第二阶段（P1-2a 修复）：缓存当前周期 has_enemy_core 标志
## 视觉绘制（CORE_TOWN 双态）用该字段替代硬编码 RunState.is_last_cycle()——配置驱动 vs 代码硬编码
## VictoryJudge cycle 过滤仍用 RunState.is_last_cycle()（static 路径不便注入；MVP 期与本字段同义）
var _current_cycle_has_enemy_core: bool = false

var _start_pos: Vector2i = Vector2i.ZERO

## 终点坐标（从 map_config 读取）
var _end_pos: Vector2i = Vector2i.ZERO

## 流程是否已结束（全部通关或部队被击败）
var _game_finished: bool = false

## L1.3 周期胜利推进过渡锁：_on_cycle_victory_triggered 触发置 true，锁住 fade-in → reload 间的输入
## 与 is_in_coma() 同语义；reload 后新场景 WorldMap 实例本字段默认 false（自然清零）
var _is_cycle_advancing: bool = false

## 单位视觉位置（像素坐标，Tween 动画驱动）
## 与逻辑位置（UnitData.position）分离，_draw 基于此渲染单位
var _unit_visual_pos: Vector2 = Vector2.ZERO

## 是否正在播放移动动画（期间锁定所有输入）
var _is_moving: bool = false

## 当前移动动画 Tween 引用（用于防止重复创建）
var _move_tween: Tween = null

## MVP-δ 阶段 2：玩家角色 / 队伍状态 / coma 字段全部迁到 PlayerLifecycle
## _characters / _total_max_hp / _leader_display_name / _is_in_coma /
## _coma_hp_threshold_ratio / _coma_duration_sec 经 _player_lifecycle 访问

## 关卡 Slot 字典 {Vector2i: LevelSlot}
var _level_slots: Dictionary = {}

## 敌方部队生成器
var _enemy_generator: EnemyTroopGenerator = null

## 背包
var _inventory: Inventory = null

## 奖励生成器
var _reward_generator: RewardGenerator = null

## 难度配置：每轮增加的 base_damage 值
var _damage_increment: float = 0.0

## 补给系统（MVP 玩家全局补给数值；HUD 显示、移动消耗、扎营恢复均读写此字段）
## 语义偏差备忘（M6 审查 P2）：设计《持久slot基础功能设计》§"部队资源通道"要求补给
## 按扎营部队隔离；MVP 仅一个玩家单位，全局字段语义成立。后续若扩展多部队 / 多单位，
## 需要重构为"按部队 / 按扎营主体"的 ledger，此处是架构债锚点
var _supply: int = 3
var _camp_restore: int = 1

## 扎营状态标记
var _is_camping: bool = false

## 入口 2 MVP 2.1 议题 1：扎营时事件队列清空后再开 ManageUI 的标记
## 由 _start_camp 在事件入队后置 true；_on_event_panel_closed 命中时打开 ManageUI 并清零
##
## codex review P1-5 修复（2026-05-10）：在 coma 触发 / 战斗启动 / 整局结束等异常路径
## 上主动重置该 flag，防止 EventPanel 被强制 hide 而非 close 时 flag 永久停留 true
## 导致下次任何 EventPanel.close 都触发意外的 ManageUI.open
var _pending_camp_manage_open: bool = false

## 单局评分追踪
var _camp_count: int = 0
var _total_hp_lost: int = 0
## _total_max_hp 字段定义迁到 PlayerLifecycle（MVP-δ 阶段 2）
## _score_config（MVP-D D.2 批 2）迁出为 const SCORE_PARAM_CFG preload

## 资源点字典 {Vector2i: ResourceSlot}
var _resource_slots: Dictionary = {}

## 资源点配置行数据（缓存）
var _resource_slot_config_rows: Array = []

## 敌方移动开关（从配置读取）
var _enemy_movement_enabled: bool = false

## 敌方移动力（从配置读取）
var _enemy_movement_points: int = 6

## 玩家手动建造/升级入口开关（A 基线收束 MVP）
## false：玩家无法通过任何 UI 路径触发自身 slot 升级（保留 BuildSystem 全部逻辑供敌方 AI 使用）
## true：开放旧入口（调试 / 未来若放开手动升级时改值即可，无需删守卫）
var _build_upgrade_enabled: bool = false

## 敌方部队进入玩家曼哈顿距离 ≤ 该值时触发强制战斗（A 基线收束 MVP）
## 默认 3；从 BattleParamResource.forced_battle_range 读（battle_param_resource.tres）
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

## 持久 slot 援军（持久slot援军_MVP / L1.2）
## _garrison_config：{ slot_type: { cycle: {count_min/max, quality_min/max} } }（ReinforcementRoster.build_config 产出）
var _garrison_config: Dictionary = {}
## 敌方援军（L1.4）：敌方独立强度表，结构同 _garrison_config；按 slot PCG 初始 owner 选表（见地图装配阶段抽样段）
var _enemy_garrison_config: Dictionary = {}
var _garrison_trigger_range: int = 2            ## 战场格到 slot 的曼哈顿触发阈值
var _garrison_total_cap: int = 99               ## 单场援军入场总数上限（默认很高，先不约束）
## 本场战斗命中（已入场援军）的 slot 列表；战后 _consume_reinforcement_rosters 扣减储备后清空
var _reinforcement_hit_slots: Array[PersistentSlot] = []

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

## 入口 4 MVP 战斗 zoom 状态
## 战斗触发时 Camera2D zoom Tween 缩小 + 居中战场；结束时 Tween 回 Vector2.ONE + 队长位置
## _battle_zoom_active = true 期间 _on_move_step 不会被触发（战斗中世界冻结），无需额外守卫
var _battle_zoom_active: bool = false
var _battle_zoom_tween: Tween = null
## 入口 4 MVP（2026-05-09 追加）：战斗中心格缓存（用于战场外压暗 overlay）
## 在 _start_battle_camera 设置；_end_battle_camera 不清——战场结束后压暗自然不画
var _battle_center_grid: Vector2i = Vector2i.ZERO

## MVP-δ 阶段 2：夜晚视野子系统（原 6 字段 + FogSignalNode 内嵌类整体迁到 NightVisionLayer.gd）
##
## NightVisionLayer 是 Node 子节点（持 CanvasLayer=5 夜晚遮罩 + CanvasLayer=6 信号浮层）
## 在 _init_subsystems 创建一次、跨周期 / 战斗复用；场景退出时 clear() 杀 Tween + 清 sink
## 战斗开始 / 结束由 _start_battle_camera / _end_battle_camera 调 set_battle_force_day_on /
##   resync_to_post_battle_state；浓雾像素判定经 WorldView.is_in_fog 转发到本节点
var _night_vision: NightVisionLayer = null

## 核心目标传达 L1.5（§2.3）：屏幕暗角 + 离屏敌方核心方向边缘箭头（CanvasLayer=7）
var _core_objective_overlay: CoreObjectiveOverlay = null

## MVP-γ 阶段 1：战斗瞬时视觉态载体（3 字典：偏移 / 渐隐 / HP 补间）
## 由 BattleAnimDirector 写、_draw_battle_* 读；跨战斗复用，战斗结束 clear()
var _battle_view: BattleViewState = null

## MVP-γ 阶段 1：战斗单位动画编排器（承接原区块 12 的 sink → Tween 适配逻辑）
## 子节点，_init_subsystems 创建、跨战斗复用，每场战斗 setup() 注入上下文
var _battle_anim_director: BattleAnimDirector = null

## 战斗单位视觉与操作改进 §2.3：结束回合"还有未移动单位"守卫弹板（首次触发时懒创建）
var _end_turn_guard_dialog: AcceptDialog = null

## MVP-γ 阶段 2：渲染层子节点（承接全部 _draw_*）
## 子 Node2D，_init_subsystems 创建；WorldMap 状态变化时调 _renderer.queue_redraw()
var _renderer: WorldMapRenderer = null

## E 战斗就地展开 MVP：探索态【攻击】按钮
## 仅在玩家回合 + 触发距离内有可交互敌方包 + 非战斗态时显示
## 点击 = _try_trigger_active_battle（与 [F] 键同语义）
## 避免玩家忽略 [F] 键提示，给"可发起攻击"一个醒目的视觉信号
var _explore_attack_btn: Button = null

## 入口 4 MVP（2026-05-09）：探索态【扎营】按钮
## 仅在玩家回合 + 补给耗尽（_supply == 0）+ 非战斗态时显示
## 与 _explore_attack_btn 用 HBoxContainer 平行排布（同时满足时两按钮并列显示，玩家自选）
## 点击 = _start_camp（与空格键同语义）
var _explore_camp_btn: Button = null

## 入口 4 MVP（2026-05-09）：探索态行动按钮容器（HBox）
## 两个按钮（攻击 / 扎营）的父容器；只挂可见按钮的位置由 HBox 自动布局
## anchor 居中屏幕底部偏上；HBox.size 自动跟随可见 child 之和
var _explore_action_bar: HBoxContainer = null

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

## 回合奖励池原始行数据
var _turn_reward_pool_rows: Array = []

## 回合奖励数量
var _turn_reward_count: int = 1

## 地图标签绘制用字体（_draw 时使用，_ready 中初始化）
var _label_font: Font = null

# ─────────────────────────────────────────
# B 重生周期 MVP — 整局态字段
# ─────────────────────────────────────────
## MVP-δ 阶段 2：原 _leader_display_name / _is_in_coma / _coma_hp_threshold_ratio
## / _coma_duration_sec 字段定义全部迁到 PlayerLifecycle.gd

## MVP-δ 阶段 2：玩家 lifecycle 子系统（_characters / 队长 / coma 状态）
## 由 _ready 在 _init_player 调用前创建 + setup（runtime_cfg 内含 coma 阈值与时长）
## 信号接线：coma_triggered / defeat_triggered / respawn_intro_ready 三个 sink
var _player_lifecycle: PlayerLifecycle = null

# ─────────────────────────────────────────
# 渲染常量（MVP-γ 阶段 2：随 _draw 区块迁回；WorldMapRenderer 经 const 别名引用）
# ─────────────────────────────────────────

## 盲盒视觉 → MVP-B.2 阶段 3 迁移到 RESOURCE_RENDER_CFG（见本文件下方 Resource preload 段）

## 势力 / 影响圈 / 持久 slot 三层结构 → MVP-B.2 阶段 4 迁移到 INFLUENCE_CFG（见本文件下方 Resource preload 段）
## 设计要点（玩家蓝 vs 洼地蓝撞色解决 v1-v3 / 敌方红 v5 三通道 / 影响圈分层渐变 / 持久 slot 三层结构）保留在 influence_config.gd schema 内
# ─────────────────────────────────────
# 调参 Resource（MVP-B 阶段 3+4 + MVP-B.2 阶段 1 迁出）
# 使用方各自 preload 同一份 .tres（独立访问无中转）
# 编辑器内双击 .tres 在 inspector 调字段
# ─────────────────────────────────────

## 战斗动画（MVP-B 阶段 3：22 字段 = 11 普通 + 4 飘字色 + 7 致命一击）
const ANIM_CFG: BattleAnimConfig = preload("res://assets/config/battle_anim_config.tres")

## 战斗视觉（MVP-B 阶段 4：31 字段 = zoom/dim/tilt 6 + arena/range 6 + actor 2 + HP 8 + troop 1 + counter 6 + 其他 2）
const VISUAL_CFG: BattleVisualConfig = preload("res://assets/config/battle_visual_config.tres")

## 地图基础（MVP-B.2 阶段 1：11 字段 = 地形 2 + 槽位 2 + 可达性 3 + 字号 2 + 时长 2）
## 跨 3 文件共享：WorldMap.gd / WorldMapRenderer.gd / EnemyMovement.gd 各自独立 preload
const MAP_BASE_CFG: MapBaseConfig = preload("res://assets/config/map_base_config.tres")

## 单位渲染 + 敌方关卡视觉（MVP-B.2 阶段 2：15 字段 = unit 4 + challenged 1 + enemy_slot/border 2 + tier 4 + enemy 动态 3）
## 跨 2 文件共享：WorldMap.gd / WorldMapRenderer.gd
const UNIT_ENEMY_CFG: UnitEnemyConfig = preload("res://assets/config/unit_enemy_config.tres")

## 一次性资源点视觉（MVP-B.2 阶段 3：3 字段，仅盲盒；scope 调整后 4 个死 RESOURCE_*_COLOR 已清理）
## 跨 2 文件共享：WorldMap.gd（_draw_resource_slot 旧路径已死） / WorldMapRenderer.gd（盲盒主使用方）
const RESOURCE_RENDER_CFG: ResourceRenderConfig = preload("res://assets/config/resource_render_config.tres")

## 势力 + 影响圈 + 持久 slot 三层结构（MVP-B.2 阶段 4：12 字段 = 势力色 1 + 影响圈 alpha 3 + 描边 2 + 核心金边 1 + 持久 slot 三层 4 + 核心徽记 1）
## 跨 2 文件共享：WorldMap.gd / WorldMapRenderer.gd（持久 slot 主使用方）
const INFLUENCE_CFG: InfluenceConfig = preload("res://assets/config/influence_config.tres")

## 战斗数值参数（MVP-D D.2 批 1：迁自 battle_config.csv，17 字段 = 伤害公式 6 + 轮次范围 4 + 敌方移动 3 + 补给 2 + 援军 2）
## 全链类型化共享：WorldMap → BattleSession → BattleMath → BattleResolver
const BATTLE_PARAM_CFG: BattleParamResource = preload("res://assets/config/battle_param_resource.tres")

## 整局 / 玩家 / 敌方生成 / 分数 数值参数（MVP-D D.2 批 2：迁自 run/player/enemy_spawn/score_config.csv）
const RUN_PARAM_CFG: RunParamResource = preload("res://assets/config/run_param_resource.tres")
const PLAYER_PARAM_CFG: PlayerParamResource = preload("res://assets/config/player_param_resource.tres")
const ENEMY_SPAWN_PARAM_CFG: EnemySpawnParamResource = preload("res://assets/config/enemy_spawn_param_resource.tres")
const SCORE_PARAM_CFG: ScoreParamResource = preload("res://assets/config/score_param_resource.tres")

## 经济类数值参数（MVP-D D.2 批 3：迁自 quality_upgrade/build/level_reward/turn_reward/supply/inventory/difficulty_config.csv）
const QUALITY_UPGRADE_PARAM_CFG: QualityUpgradeParamResource = preload("res://assets/config/quality_upgrade_param_resource.tres")
const BUILD_PARAM_CFG: BuildParamResource = preload("res://assets/config/build_param_resource.tres")
const LEVEL_REWARD_PARAM_CFG: LevelRewardParamResource = preload("res://assets/config/level_reward_param_resource.tres")
const TURN_REWARD_PARAM_CFG: TurnRewardParamResource = preload("res://assets/config/turn_reward_param_resource.tres")
const SUPPLY_PARAM_CFG: SupplyParamResource = preload("res://assets/config/supply_param_resource.tres")
const INVENTORY_PARAM_CFG: InventoryParamResource = preload("res://assets/config/inventory_param_resource.tres")
const DIFFICULTY_PARAM_CFG: DifficultyParamResource = preload("res://assets/config/difficulty_param_resource.tres")
# ─────────────────────────────────────────
# 生命周期
# ─────────────────────────────────────────

func _ready() -> void:
	# 加载所有配置
	var map_cfg: Dictionary = ConfigLoader.load_csv_kv(CONFIG_MAP)
	var terrain_rows: Array = ConfigLoader.load_csv(CONFIG_TERRAIN)
	var slot_rows: Array = ConfigLoader.load_csv(CONFIG_SLOT)
	var unit_cfg: Dictionary = ConfigLoader.load_csv_kv(CONFIG_UNIT)
	var counter_rows: Array = ConfigLoader.load_csv(CONFIG_COUNTER)
	var enemy_pool_rows: Array = ConfigLoader.load_csv(CONFIG_ENEMY_POOL)
	var item_rows: Array = ConfigLoader.load_csv(CONFIG_ITEM)

	# 加载奖励池配置（缓存行数据供后续按轮次过滤）
	_level_reward_pool_rows = ConfigLoader.load_csv(CONFIG_LEVEL_REWARD_POOL)
	_level_reward_count_min = LEVEL_REWARD_PARAM_CFG.reward_count_min
	_level_reward_count_max = LEVEL_REWARD_PARAM_CFG.reward_count_max

	_turn_reward_pool_rows = ConfigLoader.load_csv(CONFIG_TURN_REWARD_POOL)
	_turn_reward_count = TURN_REWARD_PARAM_CFG.reward_count

	# 构建地形消耗表和 Slot 允许表
	var terrain_costs: Dictionary = _build_terrain_costs(terrain_rows)
	var slot_allowed: Dictionary = _build_slot_allowed(slot_rows)

	# 加载克制矩阵
	BattleResolver.load_counter_matrix(counter_rows)

	# 加载兵力系数分段配置
	var hp_ratio_rows: Array = ConfigLoader.load_csv(CONFIG_HP_RATIO)
	BattleResolver.load_hp_ratio_config(hp_ratio_rows)

	# 加载补给配置
	_supply = SUPPLY_PARAM_CFG.initial_supply
	_camp_restore = SUPPLY_PARAM_CFG.camp_restore

	# 加载敌人强度配置（generator 初始化后再注入，见下方）
	var enemy_tier_rows: Array = ConfigLoader.load_csv(CONFIG_ENEMY_TIER)

	# P0 第二阶段：加载 enemy_tier_ratio_config（按 cycle 抽 tier 用，EnemyReinforcement.spawn_batch 消费）
	_enemy_tier_ratio_rows = ConfigLoader.load_csv(CONFIG_ENEMY_TIER_RATIO)

	# B 重生周期 MVP：英雄池 + 整局周期参数
	# RunState.ensure_initialized 幂等：首次进入写入；重生场景 reload 时
	# _initialized=true，沿用上一周期累积的 _cycle_index / _used_hero_ids 等
	var hero_pool_rows: Array = ConfigLoader.load_csv(CONFIG_HERO_POOL)
	# 入口 2 MVP 2.3(2026-05-11):加载事件叙事池(NarrativeProvider 静态工具类内部 _initialized 防重复加载)
	var narrative_rows: Array = ConfigLoader.load_csv(CONFIG_NARRATIVE_POOL)
	NarrativeProvider.ensure_loaded(narrative_rows)
	var max_cycles_v: int = RUN_PARAM_CFG.max_cycles
	# MVP-δ 阶段 2：coma_duration_sec / coma_hp_threshold_ratio 从 run_cfg 注入移到
	# PlayerLifecycle.setup 内（_player_lifecycle 在 _init_player 调用点创建）
	# rng 传 null：RunState 内部 randomize 一个独立 RNG，不被地图 PCG seed 干扰
	# （重生抽队长应与地图 PCG 解耦，否则同 seed 重开会抽到同一队长序列）
	RunState.ensure_initialized(max_cycles_v, hero_pool_rows, null)

	# 加载资源点配置
	_resource_slot_config_rows = ConfigLoader.load_csv(CONFIG_RESOURCE_SLOT)

	# 加载品质升级配置
	TroopData.load_upgrade_config(QUALITY_UPGRADE_PARAM_CFG)

	# 加载难度配置
	_damage_increment = DIFFICULTY_PARAM_CFG.damage_increment

	# 加载敌方移动配置（MVP-D D.2：类型化 Resource 直读，bool/int 字段无需转换）
	_enemy_movement_enabled = BATTLE_PARAM_CFG.enemy_movement_enabled
	_enemy_movement_points = BATTLE_PARAM_CFG.enemy_movement_points

	# 审查 P2 修复：阈值失效会让 AI 几乎永远推核心
	# 校验保留：.tres 被设为非法值（< 1）时回退到默认 10 + push_warning 便于排障
	var raw_switch_range: int = BATTLE_PARAM_CFG.enemy_target_switch_range
	if raw_switch_range < 1:
		push_warning("WorldMap: battle_param.enemy_target_switch_range 非法值 %d，回退到 10" % raw_switch_range)
		_enemy_target_switch_range = 10
	else:
		_enemy_target_switch_range = raw_switch_range

	# 强制战斗触发距离（A 基线收束 MVP）
	# 默认 3；.tres 写坏（≤ 0）时回退到默认 + push_warning，参考上面 enemy_target_switch_range 的兜底
	var raw_force_range: int = BATTLE_PARAM_CFG.forced_battle_range
	if raw_force_range < 1:
		push_warning("WorldMap: battle_param.forced_battle_range 非法值 %d，回退到 3" % raw_force_range)
		_forced_battle_range = 3
	else:
		_forced_battle_range = raw_force_range

	# E 战斗就地展开 MVP 配置（E1 仅加载到字段，E3 实装时由 BattleSession 消费）
	# battle_trigger_range 下限 1（maxi 钳制，防 .tres 设为 0）
	var raw_trigger: int = BATTLE_PARAM_CFG.battle_trigger_range
	_battle_trigger_range = maxi(1, raw_trigger)
	var raw_arena: int = BATTLE_PARAM_CFG.battle_arena_range
	_battle_arena_range = maxi(_battle_trigger_range, raw_arena)  # 战场至少不小于触发距离
	_terrain_altitude_step = BATTLE_PARAM_CFG.terrain_altitude_step
	_active_battle_supply_cost = maxi(0, BATTLE_PARAM_CFG.active_battle_supply_cost)
	_passive_battle_supply_cost = maxi(0, BATTLE_PARAM_CFG.passive_battle_supply_cost)

	# 持久 slot 援军（L1.2）触发参数
	# 下限 0（不同于 _battle_trigger_range 的下限 1）：range=0 表示"仅战场覆盖 slot 格才触发"，是有效旋钮
	_garrison_trigger_range = maxi(0, BATTLE_PARAM_CFG.garrison_trigger_range)
	_garrison_total_cap = maxi(0, BATTLE_PARAM_CFG.garrison_total_cap)

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
	_inventory.init_from_config(INVENTORY_PARAM_CFG)

	# 初始化敌方部队生成器
	_enemy_generator = EnemyTroopGenerator.new()
	_enemy_generator.init_from_config(enemy_pool_rows, ENEMY_SPAWN_PARAM_CFG)
	_enemy_generator.load_tier_config(enemy_tier_rows)

	# M6: 产出结算——城镇部队道具池走独立 CSV（不污染敌方生成权重）
	var town_pool_rows: Array = ConfigLoader.load_csv(CONFIG_TOWN_TROOP_POOL)
	if town_pool_rows.is_empty():
		push_error("WorldMap: town_troop_pool.csv 加载失败或为空；城镇 / 核心城镇产出会静默无输出")
	ProductionSystem.load_troop_pool(town_pool_rows)

	# 持久 slot 援军（L1.2）：加载 garrison_config 并解析为嵌套查表字典（slot_type → cycle → cfg）
	# 储备名册抽样在下方地图装配阶段（owner 染色完成后）逐 slot 执行
	_garrison_config = ReinforcementRoster.build_config(ConfigLoader.load_csv(CONFIG_GARRISON))
	# 敌方援军（L1.4）：加载敌方独立强度表（结构同上），抽样时按 slot 初始 owner 选用
	_enemy_garrison_config = ReinforcementRoster.build_config(ConfigLoader.load_csv(CONFIG_ENEMY_GARRISON))

	# P0 第二阶段：用 cycle_config 覆盖 map_cfg 的周期级字段（地图尺寸 / 起终点 / 持久 slot 数量 / spawn 节奏）
	# 必须在读取 start/end + _load_pcg 前调用；cycle_config 缺该周期则保留 map_cfg 原值作兜底
	_apply_cycle_config(map_cfg)

	# 读取起终点坐标（经 _apply_cycle_config 注入后，map_cfg 已包含本周期值）
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

	# P0 第二阶段：PCG 完成后缓存敌方 CORE_TOWN 原始位置
	# 供 EnemyReinforcement.spawn_batch 用作 spawn 锚（不查 owner，避免玩家占领后失效）
	_cache_enemy_core_origin_pos()

	# 设置 Camera 边界限制（不超出地图像素范围）
	_setup_camera_limits()

	# 初始化单位（移动系统）
	var default_movement: int = int(unit_cfg.get("default_movement", "6"))
	_unit = UnitData.new()
	_unit.position = _start_pos
	_unit.max_movement = default_movement
	_unit.current_movement = default_movement

	# MVP-δ 阶段 2：玩家 lifecycle 子系统创建 + setup（原 _init_player 主体迁入）
	# 必须在 _turn_manager 创建之前——setup 内 emit respawn_intro_ready / coma_triggered 等
	# 信号目前不立即触发，但 sink 接线要在 setup 之前完成，否则首次 emit 会丢
	_player_lifecycle = PlayerLifecycle.new()
	_player_lifecycle.name = "PlayerLifecycle"
	add_child(_player_lifecycle)
	# Sink 接线：3 个信号让 PlayerLifecycle 不直接依赖 OverlayTransitionUI / VictoryJudge
	_player_lifecycle.coma_triggered.connect(_on_player_coma_triggered)
	_player_lifecycle.defeat_triggered.connect(_on_player_defeat_triggered)
	_player_lifecycle.respawn_intro_ready.connect(_on_player_respawn_intro_ready)
	_player_lifecycle.cycle_victory_intro_ready.connect(_on_player_cycle_victory_intro_ready)
	_player_lifecycle.setup(PLAYER_PARAM_CFG, RUN_PARAM_CFG)

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
	_stone_by_faction = {
		Faction.PLAYER: BUILD_PARAM_CFG.player_initial_stone,
		Faction.ENEMY_1: BUILD_PARAM_CFG.enemy_initial_stone,
	}

	# 地图生成后字段装配（M2/M4 遗留缺口修复）：
	#   PersistentSlotGenerator._build_slot 只填 type / level / owner_faction，
	#   initial_range / max_range / growth_rate / influence_range 全留默认 0。
	#   核心城镇 L3 永不升级 → 影响范围永远不渲染；初始归属村庄/城镇同理。
	#   此处按每个 slot 的当前 level 从配置注入，让影响范围系统在首个回合前就位。
	# 依赖 BuildSystem.load_level_config 已完成（查 apply_level_fields 走 _level_config 读）
	# 持久 slot 援军（L1.2）：抽样 rng 优先复用 _world_rng（保证同 seed 复现）；
	# JSON 加载路径下 _world_rng 为 null，回退到 randomize 的独立 rng
	var roster_rng: RandomNumberGenerator = _world_rng
	if roster_rng == null:
		roster_rng = RandomNumberGenerator.new()
		roster_rng.randomize()
	if _schema != null:
		for entry in _schema.persistent_slots:
			var slot: PersistentSlot = entry as PersistentSlot
			if slot == null:
				continue
			BuildSystem.apply_level_fields(slot, slot.level)
			# 持久 slot 援军（L1.2）：按 type × 当前周期抽样储备名册（此时 owner 染色已完成）
			# 对所有 slot 抽样——玩家方直接用；中立 / 敌方 slot 被玩家占据后也能提供援军。
			# 敌方援军（L1.4）：按 slot PCG 初始 owner 选表——初始敌方 owned 用独立强度表 _enemy_garrison_config，
			#   初始中立 / 玩家用 _garrison_config。储备一旦快照即固定（归属透明），后续切阵营不重抽。
			var roster_cfg: Dictionary = _enemy_garrison_config if slot.owner_faction == Faction.ENEMY_1 else _garrison_config
			slot.reinforcement_roster = ReinforcementRoster.sample(
				slot.type as int, RunState.cycle_index(),
				roster_cfg, town_pool_rows, roster_rng
			)

	# ⚠ Tick 注册顺序固定：M5 → M4（TickRegistry 按 FIFO 执行）
	# 自阵营回合开始时先跑 M5 建造完成（可能刷 max_range），
	# 再跑 M4 占据快照（用新 max_range 增长）
	TickRegistry.register(_on_build_tick)

	# M4: 注册占据快照到 TickRegistry（自阵营回合开始锚点）
	# M7 迁移后：WorldMap 完全走 start_faction_turn，TickRegistry 自动分发；无需手动 run_ticks
	TickRegistry.register(_on_faction_tick)

	# Camera 初始位置直接设到单位位置（首帧不需要平滑）
	_camera.position = _unit_visual_pos
	# 入口 4 MVP（2026-05-09 跑测补丁）：Camera offset 向下偏 RESERVE/2
	# 让玩家在屏幕几何中心上方 OFFSET → 远离底部 HudBar；战斗 zoom 期间 offset 仍生效
	# 视觉效果：地图渲染区中心从屏幕几何中心上移，HUD 在玩家下方独立条带不重叠
	_camera.offset = Vector2(0, float(EXPLORE_HUD_OFFSET_PX))

	# 初始化子系统
	# MVP-δ 阶段 2：NightVisionLayer 创建 + setup 已迁到 _init_subsystems 末尾
	#   原 _setup_night_overlay / _setup_fog_signal_layer / set_process 调用整体移除
	_init_subsystems()

	# 初始化地图标签字体：使用顶部 const MAIN_FONT（preload 形式，编辑期校验路径）
	_label_font = MAIN_FONT

	# M7：开局预置 5 支敌方部队包（在敌方核心影响范围内随机空地）
	# 必须在资源点铺好之后、首个玩家回合开始之前，避免位置冲突。
	_deploy_initial_enemy_packs()

	# M7：启动首个玩家回合（TickRegistry 跑 M4/M5 tick → emit faction_turn_started(PLAYER)
	# → _on_faction_turn_started 接管 HUD / reachable 刷新）
	_turn_manager.start_faction_turn(Faction.PLAYER)

	# 入口 2 MVP 2.1 议题 5（2026-05-10）：游戏首次启动 → 黑屏揭幕过渡
	# 分流：
	#   - 应用首次启动：is_initial_play_done() == false → play_with_blackout_start 单句揭幕
	#   - reload 触发的新场景：_init_player 内已调 notify_world_ready 推进过渡，本路径跳过
	# OverlayTransitionUI _ready 时已黑屏 alpha=1，掩盖应用启动到此处的全部加载耗时
	if not OverlayTransitionUI.is_initial_play_done():
		var line: String = _player_lifecycle.format_respawn_line_for_current_leader()
		var lines: PackedStringArray = PackedStringArray([line])
		# 火苗团数 = 过渡完成后的玩家总命数；游戏开始无消耗 → 当前 respawns_left + 1（含当前队长）
		# 例：max_cycles=3, _cycle_index=0 → respawns_left=2 → 显示 3 团火苗
		var icon_data: Dictionary = {"icon": "🔥", "count": RunState.respawns_left() + 1}
		OverlayTransitionUI.play_with_blackout_start(lines, icon_data)


## M7 开局预置敌方部队包（敌方 AI 设计 §3.1）
## P0 第二阶段：数量从 cycle_config 当前周期 initial_enemy_pack_count 读
## 若核心影响范围内空地不足时，能放几支放几支（不强制）
##
## P1-1a 修复：has_enemy_core 周期（末周期）强制第 1 个 pack tier=3（最强敌人）
## 实现"末周期必有强敌"设计承诺（整局节奏重设计_MVP §2.5）；其余 pack 走权重抽
func _deploy_initial_enemy_packs() -> void:
	var target_count: int = _current_cycle_initial_pack_count
	var placed: int = 0
	# has_enemy_core 周期：第 1 个 pack 强制 tier=3；其余按权重抽
	# 通过 force_tier 参数（仅本路径使用）覆盖 EnemyReinforcement 内部权重抽样
	for i in range(target_count):
		var force_tier: int = -1
		if _current_cycle_has_enemy_core and i == 0:
			force_tier = 3
		var pack: LevelSlot = EnemyReinforcement.spawn_batch(_world_view, force_tier)
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
	VictoryJudge.clear_sink()
	# MVP-δ 阶段 2：NightVisionLayer.clear 内部清 DayNightState sinks + 杀 _phase_alpha_tween
	# WorldMap 自己注册的 phase_changed sink（_on_day_night_phase_changed）也一并被
	# DayNightState.clear_sinks() 清掉（静态全局清理）
	if _night_vision != null:
		_night_vision.clear()
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

	# MVP-γ 阶段 2：渲染层子节点（承接全部 _draw_*）—— 先于一切创建，
	# 使后续 redraw_requested 连接 / queue_redraw 转发都有非空目标；
	# setup() 注入 WorldView / BattleViewState 在本函数末尾（届时两者已就绪）
	_renderer = WorldMapRenderer.new()
	_renderer.name = "WorldMapRenderer"
	add_child(_renderer)

	# 世界视图 facade（MVP-β）—— MVP-δ 阶段 1 提前到 EnemyMovement 创建之前，
	# 让 start_enemy_move_phase 注入 _world_view 时引用已就绪
	_world_view = WorldView.new()
	_world_view.init(self)

	# 敌方移动子系统（注入格子尺寸，保证视觉位置计算与 WorldMap 一致）
	# 同时注入摄像机引用：EnemyMovement 用其计算视口可见矩形，
	# 路径全在视口外时跳过 Tween 直接结算（详见 EnemyMovement._start_animation）
	_enemy_movement = EnemyMovement.new()
	_enemy_movement.name = "EnemyMovement"
	_enemy_movement.tile_size = TILE_SIZE
	_enemy_movement._camera = _camera
	add_child(_enemy_movement)
	_enemy_movement.phase_finished.connect(_on_enemy_phase_finished)
	_enemy_movement.redraw_requested.connect(_renderer.queue_redraw)

	# 装配管理面板子系统 —— MVP-α.5：切预制件实例化
	_manage_ui = preload("res://scenes/ui/ManageUI.tscn").instantiate()
	_manage_ui.name = "ManageUI"
	ui_layer.add_child(_manage_ui)
	_manage_ui.closed.connect(_on_manage_closed)
	_manage_ui.equip_requested.connect(_on_equip_troop)
	_manage_ui.use_item_requested.connect(_on_use_item)

	# 建造面板子系统（M5）—— MVP-α.5：切预制件实例化
	_build_panel_ui = preload("res://scenes/ui/BuildPanelUI.tscn").instantiate()
	_build_panel_ui.name = "BuildPanelUI"
	ui_layer.add_child(_build_panel_ui)
	_build_panel_ui.closed.connect(_on_build_panel_closed)
	_build_panel_ui.upgrade_requested.connect(_on_upgrade_requested)

	# 敌方 AI（M7）—— _world_view 已在 _renderer 之后提前创建（MVP-δ 阶段 1）
	_enemy_ai = EnemyAI.new()
	_enemy_ai.name = "EnemyAI"
	add_child(_enemy_ai)
	_enemy_ai.init(_world_view, _turn_manager)
	# P0 第二阶段：从 cycle_config 注入当前周期的 reinforcement_interval（覆盖 EnemyAI 默认值）
	# 早期曾由 build_config 提供 enemy_reinforcement_interval，现已废弃（cycle 级配置优先）
	_enemy_ai.reinforcement_interval = _current_cycle_reinforcement_interval

	# 事件面板 UI（探索体验·F MVP）—— MVP-α.5：切预制件实例化
	# 挂载位置：所有交互面板之后、VictoryUI 之前——
	#   层级覆盖 ManageUI / BuildPanelUI（玩家先确认事件再操作其他面板），
	#   但低于 VictoryUI（胜负遮罩可覆盖未确认的事件）
	_event_panel = preload("res://scenes/ui/EventPanelUI.tscn").instantiate()
	_event_panel.name = "EventPanelUI"
	ui_layer.add_child(_event_panel)
	# 入口 4 MVP（2026-05-09 BUG 修复）：事件面板关闭时刷新探索态行动按钮
	# 修复 BUG：补给 0 时踩即时 slot 触发事件，关闭事件面板后扎营按钮未显示
	_event_panel.closed.connect(_on_event_panel_closed)

	# E 战斗就地展开 MVP：战斗内 HUD —— MVP-α.5：切预制件实例化
	# 挂载位置：EventPanelUI 之后、VictoryUI 之前
	#   战斗态时高于 EventPanelUI（战斗中事件面板被冻结，理论不会同时弹出）
	#   低于 VictoryUI（极端时序下战斗失败 + 末周期失败可能并发，胜负遮罩压顶）
	# 与 _battle_session 同生命周期；HUD 节点常驻但只在战斗态可见
	_battle_hud = preload("res://scenes/ui/BattleHUD.tscn").instantiate()
	_battle_hud.name = "BattleHUD"
	ui_layer.add_child(_battle_hud)
	_battle_hud.attack_pressed.connect(_on_battle_hud_attack_pressed)
	_battle_hud.skip_pressed.connect(_on_battle_hud_skip_pressed)
	_battle_hud.end_turn_pressed.connect(_on_battle_hud_end_turn_pressed)
	_battle_hud.exit_pressed.connect(_on_battle_hud_exit_pressed)

	# MVP-γ 阶段 1：战斗瞬时视觉态 + 动画编排器（跨战斗复用，每场战斗 setup 注入上下文）
	_battle_view = BattleViewState.new()
	_battle_anim_director = BattleAnimDirector.new()
	_battle_anim_director.name = "BattleAnimDirector"
	add_child(_battle_anim_director)
	_battle_anim_director.anims_drained.connect(_try_schedule_next_enemy_step)

	# MVP-γ 阶段 2：渲染层注入 —— WorldView（探索态只读入口）+ BattleViewState（战斗态）
	# 均已在本函数前文创建（_world_view / _battle_view），此处一次性注入，跨战斗复用
	_renderer.setup(_world_view, _battle_view)

	# MVP-δ 阶段 2：夜晚视野子系统（NightVisionLayer）—— 子 Node，持 CanvasLayer=5 / =6 浮层
	# 注入 turn_manager / camera / world_view / tile_size + 浓雾外信号颜色（敌方 slot / 移动色）
	# setup 只挂 CanvasLayer + 初始化 shader uniform；DayNightState phase_changed sink 由
	# WorldMap 在下方注册组合派发（DayNightState 单 sink 模型，注册覆盖语义）
	_night_vision = NightVisionLayer.new()
	_night_vision.name = "NightVisionLayer"
	add_child(_night_vision)
	_night_vision.setup(_turn_manager, _camera, _world_view, TILE_SIZE,
		UNIT_ENEMY_CFG.enemy_slot_color, UNIT_ENEMY_CFG.enemy_move_color)

	# 核心目标传达 L1.5（§2.3）：暗角 + 离屏核心方向箭头（CanvasLayer=7，居夜晚遮罩之上、UILayer 之下）
	_core_objective_overlay = CoreObjectiveOverlay.new()
	_core_objective_overlay.name = "CoreObjectiveOverlay"
	add_child(_core_objective_overlay)
	# 传底部 HudBar 引用：边框下边界跟随其实际顶沿（布局自然，替代 bottom_reserve 手调）
	_core_objective_overlay.setup(_camera, _world_view, TILE_SIZE, get_node_or_null("UILayer/HudBar"))

	# 入口 4 MVP（2026-05-09）：探索态行动栏 HBoxContainer（攻击 + 扎营平行排布）
	# 居中屏幕底部偏上；child 数 0 / 1 / 2 都自然布局
	_explore_action_bar = HBoxContainer.new()
	_explore_action_bar.name = "ExploreActionBar"
	_explore_action_bar.add_theme_constant_override("separation", 12)
	_explore_action_bar.anchor_left = 0.5
	_explore_action_bar.anchor_right = 0.5
	_explore_action_bar.anchor_top = 1.0
	_explore_action_bar.anchor_bottom = 1.0
	_explore_action_bar.offset_bottom = -64
	_explore_action_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_explore_action_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	ui_layer.add_child(_explore_action_bar)

	# E MVP 探索态【攻击】按钮：玩家回合且触发距离内有敌方包时显示，醒目红色
	# 屏幕中央偏下浮动；与 BattleHUD 行动栏不会同时显示（战斗态时本按钮隐藏）
	_explore_attack_btn = Button.new()
	_explore_attack_btn.name = "ExploreAttackBtn"
	# 入口 4 MVP（2026-05-10）：emoji 前缀通过 main_font.tres 的 NotoColorEmoji fallback 渲染
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
	# 入口 4 MVP（2026-05-09）：挂到 HBox（位置由容器管理，不再单独设 anchor）
	_explore_action_bar.add_child(_explore_attack_btn)
	_explore_attack_btn.pressed.connect(_on_explore_attack_pressed)

	# 入口 4 MVP（2026-05-09）：探索态【扎营】按钮（与攻击按钮同位置 / 互斥）
	# 配色：泥土棕 + 米色描边 —— 与攻击按钮的"红 + 金边"形成色相区分（紧迫 vs 安静）
	_explore_camp_btn = Button.new()
	_explore_camp_btn.name = "ExploreCampBtn"
	# 入口 4 MVP（2026-05-10）：emoji 前缀通过 main_font.tres 的 NotoColorEmoji fallback 渲染
	_explore_camp_btn.text = "⛺ 扎营 [Space]"
	_explore_camp_btn.visible = false
	_explore_camp_btn.custom_minimum_size = Vector2(160, 44)
	_explore_camp_btn.add_theme_font_size_override("font_size", 18)
	_explore_camp_btn.add_theme_color_override("font_color", Color(1.0, 0.95, 0.85, 1.0))
	var camp_normal: StyleBoxFlat = StyleBoxFlat.new()
	camp_normal.bg_color = Color(0.42, 0.30, 0.18, 0.95)
	camp_normal.border_width_left = 2
	camp_normal.border_width_right = 2
	camp_normal.border_width_top = 2
	camp_normal.border_width_bottom = 2
	camp_normal.border_color = Color(0.92, 0.82, 0.62, 1.0)
	camp_normal.content_margin_left = 16
	camp_normal.content_margin_right = 16
	camp_normal.content_margin_top = 8
	camp_normal.content_margin_bottom = 8
	_explore_camp_btn.add_theme_stylebox_override("normal", camp_normal)
	var camp_hover: StyleBoxFlat = camp_normal.duplicate() as StyleBoxFlat
	camp_hover.bg_color = Color(0.55, 0.40, 0.25, 0.98)
	_explore_camp_btn.add_theme_stylebox_override("hover", camp_hover)
	var camp_pressed: StyleBoxFlat = camp_normal.duplicate() as StyleBoxFlat
	camp_pressed.bg_color = Color(0.32, 0.22, 0.12, 1.0)
	_explore_camp_btn.add_theme_stylebox_override("pressed", camp_pressed)
	# 挂到同一 HBox（与攻击按钮平行排布）
	_explore_action_bar.add_child(_explore_camp_btn)
	_explore_camp_btn.pressed.connect(_on_explore_camp_pressed)

	# 胜负遮罩 UI（M8）—— MVP-α.5：从 .new() + create_ui() 改为预制件实例化
	# 挂载顺序放在所有 UI 面板之后，保证遮罩渲染在最上层（吸收点击）
	# 父节点从 self(Node2D) 调整为 ui_layer(CanvasLayer)：因根类型已改 extends Control，
	# Control 锚定到 CanvasLayer 的视口；逻辑等价，节点结构扁平
	_victory_ui = preload("res://scenes/ui/VictoryUI.tscn").instantiate()
	_victory_ui.name = "VictoryUI"
	ui_layer.add_child(_victory_ui)
	_victory_ui.restart_pressed.connect(_on_restart_pressed)

	# M8：注册胜负回调；OccupationSystem.try_occupy 翻转核心城镇时触发
	# reload_current_scene 后新的 _ready 会重新注册，_exit_tree 会 clear_sink 避免悬空
	VictoryJudge.register_sink(_on_victory_decided)
	# L1.3：周期推进出口（非末周期占据敌方核心 / 清场）→ 黑屏过渡 + reload + 保留队长
	VictoryJudge.register_cycle_victory_sink(_on_cycle_victory_triggered)

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

## 入口 4 MVP BUG 修复（2026-05-09）：_input → _unhandled_input
## 根因：Godot 4 输入流 _input 在 Viewport GUI 之前；点击 _explore_attack_btn 时 _input 先吞下
##       MOUSE_BUTTON_LEFT 触发 _handle_click(移动)，然后按钮才 emit pressed → 行为冲突
## 修复：改用 _unhandled_input，GUI 先消费按钮点击，地图点击才到这里
##       空格键扎营仍正常（按钮不消费空格，未被 GUI 处理的事件流到 _unhandled_input）
##
## 入口 4 MVP（2026-05-09 v2）：SPACE 上下文路由——按状态分流到不同确认 / 扎营
## 优先级：胜负遮罩 > 事件面板 > ManageUI 扎营态 > 探索态扎营兜底
func _unhandled_input(event: InputEvent) -> void:
	# SPACE 路由前置：在通用守卫 return 之前判断面板态确认（让 SPACE 可在面板打开时确认）
	# 入口 2 MVP 2.1 议题 4（2026-05-10）：扩展 SHIFT+SPACE = 批量确认所有单按钮事件
	if event is InputEventKey:
		var key0: InputEventKey = event as InputEventKey
		if key0.pressed and not key0.echo and key0.keycode == KEY_SPACE:
			if key0.shift_pressed:
				# SHIFT+SPACE：仅对事件面板单按钮事件批量确认；面板未开时空响应（消费输入避免误触发扎营）
				if _event_panel != null and _event_panel.is_open:
					_event_panel.confirm_all_single_action()
				get_viewport().set_input_as_handled()
				return
			elif _route_space_confirm():
				get_viewport().set_input_as_handled()
				return

	# 动画播放中、战斗确认中、敌方移动中、管理 / 建造 / 事件面板打开中、扎营中、昏迷过渡中或流程结束时锁定所有输入
	# 事件面板（F MVP）：玩家未确认事件前禁止地图点击 / 空格扎营，避免叠加触发
	# 昏迷过渡（B MVP）：_player_lifecycle.is_in_coma()=true 期间 reload 场景已排队，不允许任何操作
	if _game_finished or _is_cycle_advancing or _is_moving or _manage_ui.is_open or _enemy_movement.is_moving() or _is_camping or _build_panel_ui.is_open or _event_panel.is_open or _player_lifecycle.is_in_coma():
		return

	# 鼠标左键点击：移动单位（需要补给 > 0）
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_handle_click(mb.position)

	# 空格键：扎营（探索态兜底——_route_space_confirm 前置已处理面板态）
	if event is InputEventKey:
		var key: InputEventKey = event as InputEventKey
		if key.pressed and not key.echo and key.keycode == KEY_SPACE:
			_start_camp()

	# 回车键（视觉与操作改进 §2.3）：战斗中玩家回合 → 结束回合（带未移动守卫）
	# 放在通用锁守卫之后 + 显式 is_animating 守卫 → 动画期间 / 面板态不触发
	if event is InputEventKey:
		var key_enter: InputEventKey = event as InputEventKey
		if key_enter.pressed and not key_enter.echo \
				and (key_enter.keycode == KEY_ENTER or key_enter.keycode == KEY_KP_ENTER):
			if _is_in_battle() and _battle_session != null \
					and not _battle_session.is_ended() \
					and _battle_session.is_player_turn() \
					and not _battle_anim_director.is_animating():
				_on_battle_hud_end_turn_pressed()


## 入口 4 MVP（2026-05-09）：SPACE 上下文确认路由
##
## 路由清单（按优先级）：
##   1. 胜负遮罩可见 → 重开（_victory_ui.confirm_restart）
##   2. 事件面板打开 → 触发首个 action（_event_panel.confirm_first_action）
##   3. ManageUI 扎营态打开 → 关闭（_manage_ui.close —— 即"确认结束"）
##   4. 战斗中玩家回合 → 结束当前 actor 行动（_on_battle_hud_skip_pressed —— 即"结束行动"）
##
## 返回值：true = SPACE 已被消费，调用方 return；false = 继续走兜底（探索态扎营）
##
## 优先级理由：
##   - 胜负遮罩压顶（无视其他状态）
##   - 事件面板优先于 ManageUI（事件面板挡住所有面板交互）
##   - ManageUI 扎营态：玩家在养成完成后按 SPACE 一键收尾
##   - 战斗态结束行动：高频操作（每回合可能用），_on_battle_hud_skip_pressed 内部已有 session/turn 守卫
func _route_space_confirm() -> bool:
	if _victory_ui != null and _victory_ui.is_open:
		_victory_ui.confirm_restart()
		return true
	if _event_panel != null and _event_panel.is_open:
		_event_panel.confirm_first_action()
		return true
	if _manage_ui != null and _manage_ui.is_open and _manage_ui.is_camp_mode():
		_manage_ui.close()
		return true
	# 入口 4 MVP（2026-05-09 追加）：战斗态结束行动
	# 内部守卫（session 存在 / 未结束 / 玩家回合）由 _on_battle_hud_skip_pressed 处理
	if _is_in_battle() and _battle_session != null \
			and not _battle_session.is_ended() \
			and _battle_session.is_player_turn():
		_on_battle_hud_skip_pressed()
		return true
	return false

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
	# 入口 4 MVP（2026-05-10 HTML 跑测补丁）：limit_top 反向偏移补偿 camera.offset
	# Godot 4 Camera2D.limit_* 计算时不计入 offset；offset.y=+OFFSET 让画面下移
	# 若 limit_top=0，玩家贴顶时顶行只剩 (TILE_SIZE-OFFSET)/TILE_SIZE 比例（实测约 0.58 行）
	# 设 limit_top=-OFFSET 让 camera 可上越界，使顶行完整呈现
	_camera.limit_top = -EXPLORE_HUD_OFFSET_PX
	_camera.limit_right = _schema.width * TILE_SIZE
	# 入口 4 MVP（2026-05-09 跑测补丁）：limit_bottom 扩 RESERVE 让 camera 能下移到地图外
	# 配合 _camera.offset.y = +RESERVE/2，玩家贴底时屏幕底部 RESERVE 像素是地图外虚空（被 HUD 遮挡）
	_camera.limit_bottom = _schema.height * TILE_SIZE + EXPLORE_HUD_BOTTOM_RESERVE_PX


## 入口 4 MVP：战斗 Camera zoom + 战场居中（进入战斗触发）
##
## zoom 公式（设计文档 §流程）：
##   need_grids = 战场尺寸(2*range+1) + 上下各 1 格余量
##   zoom = min(viewport_width / (need_grids*TILE_SIZE),
##              (viewport_height - HUD_RESERVE) / (need_grids*TILE_SIZE))
##   Godot 4 Camera2D.zoom 语义：< 1 = 视野扩大；这里目标 zoom 必然 ≤ 1
## Tween 0.3s 平滑过渡 zoom + position；战斗中 Camera 锁定，不再被 _sync_camera_to_unit_visual 同步
func _start_battle_camera(battle_center: Vector2i) -> void:
	if _camera == null:
		return
	var zoom_target: float = _compute_battle_zoom_target()
	var center_pixel: Vector2 = _grid_to_pixel_center(battle_center)
	if _battle_zoom_tween != null and _battle_zoom_tween.is_valid():
		_battle_zoom_tween.kill()
	_battle_zoom_active = true
	_battle_center_grid = battle_center  # 入口 4 MVP（追加）：缓存战场中心供 _draw_battle_dim_overlay 使用
	_battle_zoom_tween = create_tween().set_parallel(true)
	_battle_zoom_tween.tween_property(_camera, "zoom", Vector2(zoom_target, zoom_target), VISUAL_CFG.zoom_tween_duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_battle_zoom_tween.tween_property(_camera, "position", center_pixel, VISUAL_CFG.zoom_tween_duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	# 入口 4 MVP（2026-05-09 补）：战斗倾斜 5° —— 营造不平衡 / 紧张感
	_battle_zoom_tween.tween_property(_camera, "rotation", VISUAL_CFG.tilt_rad, VISUAL_CFG.zoom_tween_duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	# MVP-δ 阶段 2：战斗强制白天 fade —— NightVisionLayer 自管理 pending_post_battle_phase
	# + force_day flag + Tween + 浮层清空，WorldMap 一行调用即可
	if _night_vision != null:
		_night_vision.set_battle_force_day_on()

	# 核心目标传达 L1.5：战斗中相机 zoom 到战场，核心指引无意义且干扰 → 隐藏整层
	if _core_objective_overlay != null:
		_core_objective_overlay.set_battle_active(true)


## 入口 4 MVP：战斗结束 Camera zoom 回归 + 镜头回到队长（_on_battle_session_ended 开头调用）
##
## 配对调用：每次 _start_battle_camera 必有一次 _end_battle_camera
## 注意：本函数应在 _sync_world_unit_from_battle_leader（如调用）之前/之后皆可——
##   如之后则 _unit.position 已是战斗结束最终位置；如之前则可能仍是开战时位置。
##   当前选择：在 _on_battle_session_ended 顶部调用，与 _battle_hud.hide_hud 同时机
func _end_battle_camera() -> void:
	# MVP-δ 阶段 2：force-day 解除前置（codex P1-4 历史修复语义保留）—— NightVisionLayer 自管理
	# 无论后续 _battle_zoom_active=false / _camera==null 异常路径，本调用总会跑完
	if _night_vision != null:
		_night_vision.resync_to_post_battle_state()
	# 核心目标传达 L1.5：战斗结束 → 恢复暗角 + 核心指引
	if _core_objective_overlay != null:
		_core_objective_overlay.set_battle_active(false)
	if not _battle_zoom_active:
		return
	_battle_zoom_active = false
	if _battle_zoom_tween != null and _battle_zoom_tween.is_valid():
		_battle_zoom_tween.kill()
	if _camera == null:
		return
	var leader_pos: Vector2 = _camera.position
	if _unit != null:
		leader_pos = _grid_to_pixel_center(_unit.position)
	_battle_zoom_tween = create_tween().set_parallel(true)
	_battle_zoom_tween.tween_property(_camera, "zoom", Vector2.ONE, VISUAL_CFG.zoom_tween_duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_battle_zoom_tween.tween_property(_camera, "position", leader_pos, VISUAL_CFG.zoom_tween_duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	# 入口 4 MVP（2026-05-09 补）：倾斜归位
	_battle_zoom_tween.tween_property(_camera, "rotation", 0.0, VISUAL_CFG.zoom_tween_duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## MVP-δ 阶段 2：以下 17 个夜晚视野相关函数 + FogSignalNode 内嵌类整体迁到 NightVisionLayer.gd
##
## 迁入清单（设计原文：tile-advanture-design/代码健康度回看/MVP-δ_拆分批2.md §阶段 2）：
##   _resync_night_overlay_to_post_battle_state → NightVisionLayer.resync_to_post_battle_state
##   _setup_night_overlay / _setup_fog_signal_layer → NightVisionLayer.setup 内联实装
##   collect_fog_signals / _process / _update_night_shader_uniforms / _player_light_world_center
##   _world_to_screen / _apply_phase_alpha_to_shader / _fade_phase_alpha / _set_phase_alpha_value
##   _is_phase_alpha_tween_active / _compute_blink_alpha / _is_in_fog / _need_blinking_redraw
##
## 顺带清理：_apply_blink_modulate（grep 验证全项目无调用者，γ 阶段抽 Renderer 后留下的死代码）


## 入口 4 MVP：战斗 zoom 目标值计算（设计文档公式）
## 取 viewport 实际尺寸（不依赖基线 1280×720，stretch 等比缩放在更上层处理）
## HUD 占位用 VISUAL_CFG.zoom_hud_reserve_px 估值；跑测后改 battle_visual_config.tres
func _compute_battle_zoom_target() -> float:
	var battle_size: int = _battle_arena_range * 2 + 1
	var need_grids: int = battle_size + VISUAL_CFG.zoom_margin_grid * 2
	var need_world_px: float = float(need_grids * TILE_SIZE)
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var usable_h: float = maxf(vp.y - float(VISUAL_CFG.zoom_hud_reserve_px), 1.0)
	var zoom_x: float = vp.x / need_world_px
	var zoom_y: float = usable_h / need_world_px
	# zoom 取较小者（保证两轴都能装下）；上限钳到 1.0 避免在大窗口下反向放大
	return minf(minf(zoom_x, zoom_y), 1.0)

# ─────────────────────────────────────────
# HUD 更新（CanvasLayer 上的 Label 节点）
# ─────────────────────────────────────────

## 刷新 HUD 状态栏文字（包含轮次、关卡、多角色兵力信息）
func _update_hud() -> void:
	if _unit == null or _turn_manager == null:
		return

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
## B 重生周期 MVP：首角色（队长）前加 _player_lifecycle.current_leader_name() 前缀，对齐 §7 场景 1
## 验收（HUD 显示当前重生周期的队长名 = hero_pool.csv 中某个英雄）
func _get_all_troops_display() -> String:
	var parts: Array[String] = []
	for i in range(_player_lifecycle.characters().size()):
		var ch: CharacterData = _player_lifecycle.characters()[i]
		# 队长（[0]）拼名字前缀；其他队员保持原格式（C MVP 入队后再扩展）
		var prefix: String = ""
		if i == 0 and not _player_lifecycle.current_leader_name().is_empty():
			prefix = "%s · " % _player_lifecycle.current_leader_name()
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
		_camp_count, _total_hp_lost, _player_lifecycle.total_max_hp(), SCORE_PARAM_CFG
	)
	return "评分 %d（扎营%d次 效率%.0f%% | 损兵%d 存活%.0f%%）" % [
		int(result["score"]),
		_camp_count,
		float(result["efficiency"]) * 100.0,
		_total_hp_lost,
		float(result["survival"]) * 100.0,
	]

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
## MVP-B.2 阶段 1：default 改 sentinel -1.0 = 用 MAP_BASE_CFG.notice_duration
## （GDScript default 参数不能是 Resource 属性访问，必须编译期常量）
func _show_notice(text: String, duration: float = -1.0) -> void:
	if _finish_label == null:
		return
	_finish_label.text = text
	if _notice_bar != null:
		_notice_bar.visible = true
	var effective_duration: float = MAP_BASE_CFG.notice_duration if duration < 0.0 else duration
	var timer: SceneTreeTimer = get_tree().create_timer(effective_duration)
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
	_renderer.queue_redraw()

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
	# 入口 1.2 P1-3 修复：动画期间锁玩家点击（HUD 按钮已锁，但玩家可能直接点地图触发行动）
	# 等所有 anim Tween 完成后再放行；防止时序错乱（移动 Tween 中又触发新移动 / 攻击）
	if _battle_anim_director.is_animating():
		return
	if _battle_session == null or _battle_session.is_ended():
		return
	if not _battle_session.is_player_turn():
		return
	var actor: BattleUnit = _battle_session.current_actor()
	if actor == null:
		return

	var hit_unit: BattleUnit = _get_battle_unit_at_pos(grid_pos)

	# 入口 1.2 补充需求 1：优先级 0 —— 点击我方未行动单位 → 切换为当前 actor
	# 条件：同阵营 + 非自身 + 未行动；切换后 HUD 刷新让按钮可用性 / 状态文本同步
	if hit_unit != null \
			and hit_unit.owner_faction == actor.owner_faction \
			and hit_unit != actor \
			and not hit_unit.has_attacked:
		if _battle_session.try_select_player_unit(hit_unit):
			_renderer.queue_redraw()
			if _battle_hud != null:
				_battle_hud.refresh(_battle_session)
		return

	# 优先级 1：点击敌方单位且在攻击范围内 → 攻击
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
		_move_tween.tween_property(self, "_unit_visual_pos", target_pixel, MAP_BASE_CFG.move_step_duration)
		# 每步回调：同步 Camera 位置并重绘
		_move_tween.tween_callback(_on_move_step)

	# 动画全部完成后的回调
	_move_tween.tween_callback(_on_move_finished)

## 每移动一格时的回调：同步 Camera 并重绘
func _on_move_step() -> void:
	# Camera 跟随视觉位置（平滑由 Camera2D 内置处理）
	_camera.position = _unit_visual_pos
	_renderer.queue_redraw()

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

	# 设计 §3.1 主动战斗只走 [F] 键：UNCHALLENGED 敌方 LevelSlot 由 _get_blocked_positions
	# 加进玩家阻挡，玩家走不到敌格；战斗入口统一由 _handle_f_key 触发，本路径不再分流战斗。

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
	_renderer.queue_redraw()

## 获取所有阻挡位置（未挑战敌方格阻挡玩家通行）
func _get_blocked_positions() -> Dictionary:
	var blocked: Dictionary = {}
	for pos in _level_slots:
		var lv: LevelSlot = _level_slots[pos] as LevelSlot
		# 设计 §3.1 主动战斗只走 [F]：UNCHALLENGED 敌方 LevelSlot 加进玩家阻挡，
		# 玩家不能"走到敌格上"
		if lv.state == LevelSlot.State.UNCHALLENGED:
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
	_renderer.queue_redraw()


## 构建 { Vector2i: 势力 ID } 字典，用于快照的驻扎判定
## MVP 只含两类单位：玩家唯一单位 + UNCHALLENGED 敌方关卡
##
## DEFEATED 的敌方格**不算驻扎单位**（P1 审查项决议）：
##   已击败 slot 从 _level_slots 清除或标 is_defeated，无驻扎意义；
##   对应格子按"无单位"参与 snapshot_turn_end 结算。
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
		_renderer.queue_redraw()
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
	_renderer.queue_redraw()


## 打开建造面板
## 列表内容：所有归属于 PLAYER 的持久 slot
##
## A 基线收束 MVP：_build_upgrade_enabled 守卫在玩家手动升级入口前置；
## 默认 false 即"按 [B] 不弹板"，给一行 notice 说明，避免玩家不知道键失效。
func _open_build_panel() -> void:
	# E MVP：战斗态守卫——_is_in_battle 期间不允许打开建造面板（设计 §2.10）
	if _game_finished or _is_cycle_advancing or _is_moving or _manage_ui.is_open or _is_camping or _event_panel.is_open or _player_lifecycle.is_in_coma() or _is_in_battle():
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
	_renderer.queue_redraw()


## 获取当前归属于 PLAYER 的所有持久 slot
func _get_player_persistent_slots() -> Array[PersistentSlot]:
	return _get_persistent_slots_by_faction(Faction.PLAYER)


## 获取当前归属于 ENEMY_1 的所有持久 slot（敌方援军_MVP / L1.4）
func _get_enemy_persistent_slots() -> Array[PersistentSlot]:
	return _get_persistent_slots_by_faction(Faction.ENEMY_1)


## 按阵营过滤持久 slot（L1.4 抽出，玩家 / 敌方 getter 共用）
func _get_persistent_slots_by_faction(faction: int) -> Array[PersistentSlot]:
	var result: Array[PersistentSlot] = []
	if _schema == null:
		return result
	for entry in _schema.persistent_slots:
		var slot: PersistentSlot = entry as PersistentSlot
		if slot == null:
			continue
		if slot.owner_faction == faction:
			result.append(slot)
	return result


## 扎营入口：恢复补给 → 资源点结算 → 打开养成面板
func _start_camp() -> void:
	# E MVP：战斗态守卫——_is_in_battle 期间不允许扎营（设计 §2.10）
	if _game_finished or _is_cycle_advancing or _is_moving or _is_camping or _manage_ui.is_open or _build_panel_ui.is_open or _event_panel.is_open or _player_lifecycle.is_in_coma() or _is_in_battle():
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
	#
	# 入口 2 MVP 2.3 扩展（2026-05-11）：补给恢复 event 也走 NarrativeProvider
	# 场景:camp_supply_{wild|village|town}(独立池,与产出叙事分开)
	# 占位符:leader_name / count(补给恢复量) / slot_name(村庄/城镇场景)
	_supply += _camp_restore
	if _camp_restore > 0:
		var supply_info: Dictionary = _resolve_camp_scenario()
		var supply_scenario: String = "camp_supply_" + String(supply_info.get("scenario", "camp_wild")).substr(5)
		var supply_ctx: Dictionary = {
			"leader_name": _player_lifecycle.current_leader_name(),
			"count": _camp_restore,
		}
		if supply_scenario != "camp_supply_wild":
			supply_ctx["slot_name"] = String(supply_info.get("slot_name", ""))
		var supply_narrative: String = NarrativeProvider.pick(supply_scenario, supply_ctx)
		_event_panel.push_event(_build_reward_event("扎营休整", supply_narrative))

	# M6: 持久 slot 扎营结算（玩家侧）
	# 流程：camp_pos 查 C 作用域覆盖 → 逐 slot 按类型 × 作用域覆盖 → 落地到石料 / 补给 / 背包
	_settle_persistent_camp_production()

	# C 重生周期 MVP：扎营产出事件 push 完后再做里程碑检查
	# 顺序意图：玩家心智上"扎营整顿 → 物资产出 → 新人加入"，叙事节奏自然
	# RunState.check_recruit_milestone 内部命中时调 _on_recruit_triggered → push_event
	# 入队事件因此排在扎营产出事件之后，由 EventPanelUI FIFO 依次弹出
	RunState.check_recruit_milestone(_player_lifecycle.get_team_hero_ids())

	_update_hud()

	# 入口 2 MVP 2.1 议题 1：扎营时事件队列清空后再开 ManageUI
	# 流程拆分：
	#   - 有事件入队（_event_panel.is_open）→ 置 _pending_camp_manage_open，等 closed 信号回调
	#   - 无事件入队（产出 / 里程碑都未命中）→ 直接打开 ManageUI（保持原行为）
	# 设计意图：避免事件面板与 ManageUI 同帧叠加弹出（详见 [[事件流程与队长过渡_MVP#流程 1]]）
	if _event_panel != null and _event_panel.is_open:
		_pending_camp_manage_open = true
	else:
		_manage_ui.open(_player_lifecycle.characters(), _inventory, true)


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
	#
	# 入口 2 MVP 2.3（2026-05-11）：narrative 走 NarrativeProvider 池抽取
	# 整次扎营单一 scenario:玩家位置一次性判定,所有 entry 共用同一情境(野外/村庄/城镇)
	if not applied.is_empty():
		var camp_info: Dictionary = _resolve_camp_scenario()
		var camp_scenario: String = String(camp_info.get("scenario", "camp_wild"))
		var slot_name: String = String(camp_info.get("slot_name", ""))
		for entry in applied:
			var entry_dict: Dictionary = entry as Dictionary
			var item_count: Dictionary = _entry_to_item_count(entry_dict)
			var ctx: Dictionary = {
				"leader_name": _player_lifecycle.current_leader_name(),
				"item": item_count["item"],
				"count": item_count["count"],
			}
			if camp_scenario != "camp_wild":
				ctx["slot_name"] = slot_name
			var narrative: String = NarrativeProvider.pick(camp_scenario, ctx)
			_event_panel.push_event(_build_reward_event("扎营产出", narrative))
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
##
## 入口 2 MVP 2.3（2026-05-11）：narrative 走 NarrativeProvider battle_victory 池抽取
## item 占位符 = 合并奖励文本(已含数量,如"草药×2, 盾×1"),不需要 count
func _push_battle_victory_event(rewards: Array[ItemData]) -> void:
	if rewards.is_empty():
		return
	var reward_text: String = _format_rewards_text(rewards)
	var ctx: Dictionary = {
		"leader_name": _player_lifecycle.current_leader_name(),
		"item": reward_text,
	}
	var narrative: String = NarrativeProvider.pick("battle_victory", ctx)
	_event_panel.push_event(_build_reward_event("战斗胜利", narrative))


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
	# 入口 2 MVP 2.3（2026-05-11）:走 NarrativeProvider resource_slot_pickup 池
	if not applied.is_empty():
		for applied_entry in applied:
			var entry_dict: Dictionary = applied_entry as Dictionary
			var item_count: Dictionary = _entry_to_item_count(entry_dict)
			var ctx: Dictionary = {
				"leader_name": _player_lifecycle.current_leader_name(),
				"item": item_count["item"],
				"count": item_count["count"],
			}
			var narrative: String = NarrativeProvider.pick("resource_slot_pickup", ctx)
			_event_panel.push_event(_build_reward_event("采集所获", narrative))
	if not dropped.is_empty():
		_show_notice("采集失败：%s" % ProductionSystem.format_dropped_text(dropped))
	_renderer.queue_redraw()

## 玩家回合结束结算流程（M7 迁移）
## 扎营养成确认后调用：发放奖励 → 触发敌方阵营回合（TurnManager.start_faction_turn）
##
## M7 前的 legacy 流程：直接调 _enemy_movement.start_phase 或 end_turn
## M7 新流程：end_faction_turn(PLAYER) → start_faction_turn(ENEMY_1) → EnemyAI 六步 → 回到 PLAYER
func _on_turn_end_settlement() -> void:
	if _game_finished or _check_defeat():
		return
	# 发放回合奖励
	if _reward_generator != null:
		var rewards: Array[ItemData] = _reward_generator.generate_rewards(
			_turn_reward_pool_rows, 1, _turn_reward_count
		)
		if not rewards.is_empty():
			_inventory.add_items(rewards)
			var reward_text: String = _format_rewards_text(rewards)
			# F MVP：回合奖励是"一次性整组"奖励，合并到一条事件呈现
			_event_panel.push_event(_build_reward_event(
				"回合奖励", "回合结束清点物资，获得：%s" % reward_text
			))

	# M7 敌方回合触发：end 当前（PLAYER）+ start ENEMY_1
	# start_faction_turn 内部会：TickRegistry.run_ticks（建造 tick / 占据快照）→ 计数 +1 → emit signal
	# signal 被 EnemyAI 接收，执行六步 2-5（步骤 1 已由 TickRegistry 完成）
	#
	# enemy_movement_enabled == false（调试开关）：
	#   仍必须调 start_faction_turn(ENEMY_1) 让 TickRegistry 跑敌方建造 tick / 占据快照，
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
##
## P0 第二阶段：target_pos 参数已废弃（EnemyMovement._pick_target_for 改为"附近 slot 占领 + 追玩家"双轴）
## 仍传值给保持签名兼容；实际 per-pack 决策不再读取该值（详见 EnemyMovement.gd）
## 无可移动 → 直接触发 phase_finished（走 _on_enemy_phase_finished → 回 PLAYER）
##
## MVP-δ 阶段 1（2026-05-15）：EnemyMovement 不再持有 _level_slots / _original_slot_types
## 字典引用，改为通过 _world_view facade 读写。签名相应缩 2 参（旧 9 参 → 新 8 参）。
func start_enemy_move_phase() -> void:
	if _game_finished or not _enemy_movement_enabled:
		_on_enemy_phase_finished()
		return
	if _schema == null:
		push_warning("WorldMap.start_enemy_move_phase: schema 未初始化，跳过本回合敌方移动")
		_on_enemy_phase_finished()
		return
	# P0 第二阶段：target_pos 参数 deprecated（保留作签名兼容），EnemyMovement 不再读取
	# 传 _start_pos 仅作占位；per-pack target 由 EnemyMovement._pick_target_for 内部决策
	var legacy_target_pos: Vector2i = _start_pos
	# E4 注入玩家保护区半径（= _battle_trigger_range）：保护区内格 cost = INF
	# 让敌方寻路自然停在保护区边缘，等敌方阶段末尾扫描触发被动战斗
	_enemy_movement.start_phase(
		_schema, _world_view, _unit.position, legacy_target_pos,
		_enemy_movement_points, _game_finished,
		_enemy_target_switch_range,
		_forced_battle_range,
		_battle_trigger_range
	)


## MVP-δ 阶段 1：敌方关卡移动的原子写提交
##
## 由 WorldView.commit_enemy_move 转发；EnemyMovement._process_next_move 在选定新位置后调用。
## 7 行原子写（原 EnemyMovement.gd L329-L339 整组迁过来）：
##   - _level_slots erase(old) / set(new, level)
##   - level.position = new_pos（mutate LevelSlot 字段）
##   - _schema.set_slot(old, restored_original_type)：恢复 old_pos 原始地形
##   - _original_slot_types erase(old)
##   - 条件 set _original_slot_types[new] = 当前 schema 类型（首次踩到该格才记录）
##   - _schema.set_slot(new, FUNCTION)：把 new_pos 标为 FUNCTION（敌方占用语义）
func _commit_enemy_move(level: LevelSlot, old_pos: Vector2i, new_pos: Vector2i) -> void:
	_level_slots.erase(old_pos)
	level.position = new_pos
	_level_slots[new_pos] = level
	# 恢复 old_pos 的原始地形类型（敌方占用时记录的 FUNCTION 标记还原）
	var restored_type: int = _original_slot_types.get(old_pos, MapSchema.SlotType.NONE) as int
	_schema.set_slot(old_pos.x, old_pos.y, restored_type as MapSchema.SlotType)
	_original_slot_types.erase(old_pos)
	if not _original_slot_types.has(new_pos):
		_original_slot_types[new_pos] = _schema.get_slot(new_pos.x, new_pos.y)
	_schema.set_slot(new_pos.x, new_pos.y, MapSchema.SlotType.FUNCTION)


## MVP-δ 阶段 1：敌方对持久 slot 的占据尝试
##
## 由 WorldView.try_enemy_occupy_persistent_slot 转发；EnemyMovement._try_enemy_occupy_at
## 在移动动画末尾调用。
##
## 流程（原 EnemyMovement.gd L537-L546 迁过来）：
##   - 扫 _schema.persistent_slots 找匹配 pos 的 PersistentSlot
##   - 调 OccupationSystem.try_occupy(ps, faction)
##   - 成功翻转 → _renderer.queue_redraw() 触发重绘（原 EnemyMovement 用 redraw_requested.emit
##     往 WorldMap 转一道；现在直接在 WorldMap 内 redraw，少一次信号往返）
func _try_enemy_occupy_persistent_slot(pos: Vector2i, faction: int) -> void:
	if _schema == null:
		return
	for entry in _schema.persistent_slots:
		var ps: PersistentSlot = entry as PersistentSlot
		if ps.position != pos:
			continue
		if OccupationSystem.try_occupy(ps, faction):
			_renderer.queue_redraw()
		return


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

	_renderer.queue_redraw()

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
##
## MVP-δ 桌面跑测后续（2026-05-15）：reload 走 call_deferred，避免在 _unhandled_input 同步信号链中
## 调用导致当前节点脱离树后 _unhandled_input 继续访问 get_viewport() 触发 null crash。
## 复现路径：VictoryUI 失败遮罩开启 → SPACE → _route_space_confirm → confirm_restart → 同步 emit
## restart_pressed → 本函数 → reload_current_scene → 节点脱树 → 回到 _unhandled_input L1231 调
## get_viewport() 返回 null → "Cannot call method 'set_input_as_handled' on a null value"
func _on_restart_pressed() -> void:
	RunState.reset()
	get_tree().reload_current_scene.call_deferred()


## D MVP + 入口 4 后段第 1 份（夜晚视野 MVP）：昼夜阶段切换回调
##
## MVP-δ 阶段 2 重构为组合派发 sink：
##   DayNightState 是单 sink 模型（register 覆盖前者），WorldMap 注册一个 sink 同时驱动：
##   1. _renderer.queue_redraw() —— 让闪烁敌人 / 战场外压暗等 _draw_* 分支立即响应
##   2. _night_vision.on_phase_changed(phase) —— 浮层 redraw / fade Tween / force-day 守卫
##      全部由 NightVisionLayer 内部处理
func _on_day_night_phase_changed(phase: int) -> void:
	_renderer.queue_redraw()
	if _night_vision != null:
		_night_vision.on_phase_changed(phase)


# ─────────────────────────────────────────
# 敌方 AI 协作辅助
# ─────────────────────────────────────────

## 敌方 AI 进军 target 位置（P0 第二阶段后已废弃）
##
## 历史：
##   X-A 前：扫 schema 找 CORE_TOWN owner=PLAYER（玩家方核心位置）
##   X-A 后：返回 _start_pos 作静态锚
##   P0 第二阶段：EnemyMovement._pick_target_for 改为"附近 slot 占领 + 追玩家"二元，
##                 不再依赖任何全局战略锚；本函数无被调用方。
##
## 保留函数体为占位（返回 _start_pos）以防其他历史代码引用；新代码不应调用
func _get_enemy_target_pos() -> Vector2i:
	if _schema == null:
		return Vector2i(-1, -1)
	return _start_pos


# ─────────────────────────────────────────
# 敌方移动信号处理（M7 改造）
# ─────────────────────────────────────────

## 敌方移动阶段完成回调
## M7 迁移：end_faction_turn(ENEMY_1) → start_faction_turn(PLAYER)
## start_faction_turn(PLAYER) 内部会跑 PLAYER tick，然后 emit signal → _on_faction_turn_started 继续玩家侧
##
## 防御（P2 审查）：仅在 current_faction == ENEMY_1 时切换；若被误调在玩家回合中，直接返回避免错误双 start
##
## B 重生周期 MVP：昏迷过渡期间（_player_lifecycle.is_in_coma()=true）也直接 return——
## 战斗结算时若触发昏迷，BattleSession 走 COMA 退出，由 _on_battle_session_ended
## 处理 _enemy_movement.finish_phase()。让 phase_finished 信号发出后本回调若切回
## PLAYER 回合会跑额外 tick / HUD 刷新，
## 1.5s 后 reload 时这些状态被覆盖，但中间存在时序风险（如 tick 触发新增建造）
func _on_enemy_phase_finished() -> void:
	if _game_finished:
		return
	if _player_lifecycle.is_in_coma():
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
# 守卫语义：_is_in_battle() = true 期间锁定所有面板 / 输入分流；_battle_session sink 退出后清空


## 战斗态守门：_battle_session 非空且未结束
## 沿用 _player_lifecycle.is_in_coma() / _event_panel.is_open 同样的守门模式
## 各守卫函数（_input / _unhandled_key_input / _open_*_panel / _on_abandon / _start_camp）追加该判定
func _is_in_battle() -> bool:
	return _battle_session != null and not _battle_session.is_ended()


## 扫描指定坐标曼哈顿距离 ≤ range 内的敌方关卡（LevelSlot）
## 用于 [F] 主动战斗触发候选 + 后续 E4 被动战斗保护区扫描复用
##
## 命中条件：
##   - 在距离阈值内
##   - level.is_interactable() = true（UNCHALLENGED）
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
	# MVP-γ 阶段 2 修复：redraw_target 传 _renderer（非 self）—— _draw 已迁到
	# WorldMapRenderer，动画 tween 每帧须重绘 _renderer，重绘空的 WorldMap 无效；
	# BattleFloatText 也挂到 _renderer（同坐标空间的 Node2D）
	_battle_anim_director.setup(_renderer, _battle_hud, _battle_view, _terrain_altitude_step)
	_bind_battle_session_sinks()
	_battle_session.start(
		_player_lifecycle.characters(),
		_unit.position,
		packs,
		_schema,
		_battle_arena_range,
		_battle_unit_config,
		BATTLE_PARAM_CFG,
		_terrain_altitude_step,
		_player_lifecycle.coma_hp_threshold_ratio(),
		0,
		_damage_increment
	)
	# 入口 2 MVP 2.1 codex review P0-1 修复（2026-05-10）：
	# BattleSession.start 末尾的防御性 _check_battle_end_after_action 可能立即触发 COMA →
	# on_battle_ended sink 同步进入 _on_battle_session_ended → await 处 yield 出来,start() 返回
	# 此时 is_ended() == true,不应再启动战场镜头 / 显示 HUD（否则会闪现一帧 zoom + HUD 然后黑屏）
	# sink 的 await 完成后会自然进入 _player_lifecycle.trigger_coma_or_lose 启动黑屏过渡
	if _battle_session.is_ended():
		return
	# 持久 slot 援军（L1.2）：战斗存活态下注入命中 slot 的援军
	# 置于 HUD show + redraw 之前 → 援军单位随后续 queue_redraw 自然渲染
	_inject_reinforcements()
	# 战斗中清掉探索态可达高亮（避免视觉与战场叠加层干扰）
	_reachable_tiles = {}
	# 入口 4 MVP：战斗 Camera zoom + 战场居中（队长位置 = 战场中心）
	_start_battle_camera(_unit.position)
	# HUD 先显示（refresh 内部读 session 状态）
	if _battle_hud != null:
		_battle_hud.show_hud(_battle_session)
	_update_hud()
	_renderer.queue_redraw()


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
	# MVP-γ 阶段 2 修复：redraw_target 传 _renderer（非 self）—— _draw 已迁到
	# WorldMapRenderer，动画 tween 每帧须重绘 _renderer，重绘空的 WorldMap 无效；
	# BattleFloatText 也挂到 _renderer（同坐标空间的 Node2D）
	_battle_anim_director.setup(_renderer, _battle_hud, _battle_view, _terrain_altitude_step)
	_bind_battle_session_sinks()
	_battle_session.start(
		_player_lifecycle.characters(),
		_unit.position,
		packs,
		_schema,
		_battle_arena_range,
		_battle_unit_config,
		BATTLE_PARAM_CFG,
		_terrain_altitude_step,
		_player_lifecycle.coma_hp_threshold_ratio(),
		0,
		_damage_increment
	)
	# 入口 2 MVP 2.1 codex review P0-1 修复（2026-05-10）：与 _start_battle_session 同因
	# 详见上方 _start_battle_session 内同段注释
	if _battle_session.is_ended():
		return
	# 持久 slot 援军（L1.2）：被动战斗同样注入命中 slot 的援军
	_inject_reinforcements()
	_reachable_tiles = {}
	# 入口 4 MVP：被动战斗同样触发战场镜头 zoom（战场中心 = 队长位置）
	_start_battle_camera(_unit.position)
	if _battle_hud != null:
		_battle_hud.show_hud(_battle_session)
	_update_hud()
	_renderer.queue_redraw()


## 持久 slot 援军（L1.2 玩家 / L1.4 敌方）：战斗启动后注入命中 slot 的援军
##
## 设计原文：tile-advanture-design/持久slot援军_MVP.md §3.2 / §3.3；敌方援军_MVP.md §3.3
##
## 流程（双阵营对称，玩家先注入、敌方后注入）：
##   - 玩家方援军 → player_units（PLAYER 阵营，玩家控制）
##   - 敌方援军   → enemy_units（ENEMY_1 阵营，BattleAI 驱动；source_level=null 不进 _level_slots）
##   occupied 跨阵营续用（玩家先落位、敌方避让）；injected_total 跨阵营累加，_garrison_total_cap 对总数兜底
##
## 前置：_battle_session.start() 已完成且未 is_ended()（追加到 player/enemy_units 即被回合流程自然纳入）
func _inject_reinforcements() -> void:
	_reinforcement_hit_slots = []
	if _battle_session == null or _schema == null:
		return
	var arena: Rect2i = _battle_session.arena
	# 重建 occupied 续用（避免与本队 / 敌包 / 已入场援军重叠）；玩家先落位、敌方接着避让
	var occupied: Dictionary = BattleDeploy.build_occupied(_battle_session.player_units, _battle_session.enemy_units)
	var injected_total: int = 0
	# 玩家方援军 → player_units
	injected_total = _inject_side(
		_get_player_persistent_slots(), _battle_session.player_units, Faction.PLAYER, arena, occupied, injected_total)
	# 敌方援军（L1.4）→ enemy_units（AI 控制）
	injected_total = _inject_side(
		_get_enemy_persistent_slots(), _battle_session.enemy_units, Faction.ENEMY_1, arena, occupied, injected_total)


## 单阵营援军注入（敌方援军_MVP / L1.4 抽出）：命中判定 + 排序 + 逐条入场 + consumed 暂存 + 命中 slot 并入回收列表
##
## slots          —— 待扫描的同阵营持久 slot（_get_player/_enemy_persistent_slots 产出）
## target_units   —— 入场单位追加目标（player_units / enemy_units，按引用传入直接 append）
## faction        —— 援军阵营（PLAYER 玩家控制 / ENEMY_1 AI 驱动）
## arena          —— 战场矩形（命中判定 + 落位边界）
## occupied       —— 跨阵营续用的占位字典（玩家先落、敌方避让）
## injected_total —— 跨阵营累加的入场总数（_garrison_total_cap 对总数兜底）
## 返回：更新后的 injected_total（供下一阵营续算 cap）
func _inject_side(slots: Array[PersistentSlot], target_units: Array[BattleUnit], faction: int,
		arena: Rect2i, occupied: Dictionary, injected_total: int) -> int:
	# 1-2. 命中判定
	var hit_slots: Array[PersistentSlot] = []
	for slot in slots:
		if slot.reinforcement_roster.is_empty():
			continue
		if _slot_in_battle_range(slot, arena):
			hit_slots.append(slot)
	if hit_slots.is_empty():
		return injected_total
	# 3. 排序：type 降序（核心 2 > 城镇 1 > 村庄 0）；同 type 按 position（y 优先、x 次之）稳定序
	hit_slots.sort_custom(func(a: PersistentSlot, b: PersistentSlot) -> bool:
		if a.type != b.type:
			return (a.type as int) > (b.type as int)
		if a.position.y != b.position.y:
			return a.position.y < b.position.y
		return a.position.x < b.position.x
	)
	# 4-5. 入场填充
	for slot in hit_slots:
		var consumed: Array = []
		for entry_v in slot.reinforcement_roster:
			if injected_total >= _garrison_total_cap:
				break
			var entry: Dictionary = entry_v as Dictionary
			# 以 slot.position 为锚点找空格（slot 自身格被 can_deploy_at 排除，不能直接用 slot.position）
			var cell: Vector2i = BattleDeploy.find_deploy_slot(slot.position, occupied, 4, arena, _schema)
			if not BattleDeploy.is_valid_slot(cell, occupied, arena, _schema):
				continue  # 找不到空格 → 跳过该单位，条目保留在 roster（不计入 consumed）
			# 新建 TroopData（只用规格，hp 用默认满血，与 EnemyTroopGenerator 一致）
			var troop: TroopData = TroopData.new()
			troop.troop_type = int(entry.get("troop_type", 0)) as TroopData.TroopType
			troop.quality = int(entry.get("quality", 0)) as TroopData.Quality
			var unit: BattleUnit = BattleDeploy.make_reinforcement_unit(troop, cell, _battle_unit_config, faction)
			occupied[cell] = unit
			target_units.append(unit)
			consumed.append(entry)
			injected_total += 1
		slot._consumed_this_battle = consumed
		if not consumed.is_empty():
			_reinforcement_hit_slots.append(slot)
	return injected_total


## 判断 slot 到战场 arena 的最近格曼哈顿距离是否 ≤ _garrison_trigger_range
## 委托 ReinforcementRoster.is_in_trigger_range（静态、可 headless 测）
func _slot_in_battle_range(slot: PersistentSlot, arena: Rect2i) -> bool:
	return ReinforcementRoster.is_in_trigger_range(slot.position, arena, _garrison_trigger_range)


## 持久 slot 援军（L1.2）：战后回收——本场已入场援军条目从对应 slot 储备永久扣减
##
## 设计原文：tile-advanture-design/持久slot援军_MVP.md §3.4
##
## 语义：一次性消耗——已入场的条目（无论存活 / 阵亡）整体从 roster 移除；
##       未入场的条目（cap 截断 / 找不到空格）保留在 roster。
## 数据无关战斗会话本身，只读 _reinforcement_hit_slots + slot._consumed_this_battle，
## 故可在 _on_battle_session_ended 任何 _battle_session = null 之前安全调用。
func _consume_reinforcement_rosters() -> void:
	for slot in _reinforcement_hit_slots:
		if slot == null:
			continue
		ReinforcementRoster.apply_consumption(slot.reinforcement_roster, slot._consumed_this_battle)
		slot._consumed_this_battle = []
	_reinforcement_hit_slots = []


## 玩家按 [F] 主动战斗触发入口
##
## 候选检查 + 多包退化（MVP 简化）：
##   - 候选 == 0 → 无响应
##   - _supply == 0 → notice 提示，不入战
##   - 候选 == 1 → 直接确认
##   - 候选 > 1 → MVP 简化：选最近的包（曼哈顿距离最小）
##
## 不放在 _start_battle_session 内是因为被动战斗（E4）会有不同的候选取舍逻辑
func _try_trigger_active_battle() -> void:
	if _unit == null:
		return
	# 队长无部队 → 不能入战；走兜底队伍状态评估（理论上 _player_lifecycle.evaluate_party_state 此时应已触发昏迷 / 失败）
	# 防御性检查避免 BattleSession._deploy_player_side 落到无 actor 的卡死战斗态
	if _player_lifecycle.characters().is_empty() or _player_lifecycle.characters()[0] == null or not _player_lifecycle.characters()[0].has_troop():
		_player_lifecycle.evaluate_party_state(_game_finished)
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
	_renderer.queue_redraw()
	if _battle_hud != null and _battle_session != null:
		_battle_hud.refresh(_battle_session)


## 注入 BattleSession 所有 sink（入口 1.2 信号粒度扩展后集中管理）
## 主动战斗 / 被动战斗两路径都通过本 helper 绑定，避免重复维护两份字段赋值
func _bind_battle_session_sinks() -> void:
	if _battle_session == null:
		return
	_battle_session.on_battle_ended = _on_battle_session_ended
	_battle_session.on_redraw_requested = _on_battle_redraw_requested
	# MVP-γ 阶段 1：6 个单位动画 sink 委派 BattleAnimDirector
	_battle_anim_director.bind_unit_sinks(_battle_session)


## 调度下一个敌方 step：仅在 anim 完成 + queue 空 + 仍敌方回合时启动 0.18s 间隔 timer
## 由 BattleAnimDirector 动画清空时 emit anims_drained 触发，或 _run_enemy_turn_async 在 step 无 anim 时兜底
func _try_schedule_next_enemy_step() -> void:
	if _battle_session == null or _battle_session.is_ended():
		return
	if not _battle_session.is_enemy_turn():
		return
	if _battle_anim_director.is_animating():
		return
	var t: SceneTreeTimer = get_tree().create_timer(ANIM_CFG.enemy_step_gap)
	t.timeout.connect(_run_enemy_turn_async)


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
	# 入口 4 MVP（codex 审查 P1 修复 2026-05-09）：不再直接瞬移 _camera.position
	# 原因：调用顺序是 sync → _end_battle_camera()，sync 把 camera 瞬移到队长位置后，
	#       _end_battle_camera 的 position tween 起点 = 终点 = 队长位置 → tween 没有视觉变化（瞬移而非平滑）
	# 修复：让 camera 暂时停在战场中心（_battle_zoom_active 期间的位置），
	#       由 _end_battle_camera 从战场中心 tween 平滑过渡到队长位置


## 战斗结束 sink（设计 §3.4 / §2.8）
##
## 三分支处理：
##   VICTORY     —— 收集每个 defeated_pack 的关卡 / 部队奖励 → 合并 _push_battle_victory_event
##                  → 清理 _level_slots / 恢复 schema slot
##                  → _player_lifecycle.evaluate_party_state 兜底队员阵亡（队长不会跌阈值，否则走 COMA）
##   MANUAL_EXIT —— 不发奖励，敌方残余保留；_player_lifecycle.evaluate_party_state 兜底
##   COMA        —— 走 B MVP 重生分支（_player_lifecycle.trigger_coma_or_lose）
##
## 收尾通用：清空 _battle_session / 隐藏 HUD / 重置移动力 / 刷新可达
func _on_battle_session_ended(reason: int, defeated_packs: Array) -> void:
	# 持久 slot 援军（L1.2）：战后回收——本场入场援军条目从储备永久扣减（一次性消耗）
	# 与结束原因无关（VICTORY / RETREAT / COMA / MANUAL_EXIT 一致），置于任何 _battle_session = null 之前
	_consume_reinforcement_rosters()
	# 入口 2 MVP 2.1 议题 5（2026-05-10 跑测调整）：COMA 分支与其他分支的动画清理时机不同
	#
	# COMA 分支：先 await 致命一击的攻击 / 死亡动画跑完，玩家能看到完整因果，再清理 + 黑屏
	#   不这么做的体验问题：致命一击的 anim runner 还在队列中就被 clear，玩家"敌人没动作就黑屏"
	# VICTORY / MANUAL_EXIT 分支：保持原行为（立即清理 + 进入收尾流程）
	if reason == BattleSession.EndReason.COMA:
		# 隐藏 HUD（提前；防止 await 期间玩家点按钮）
		if _battle_hud != null:
			_battle_hud.hide_hud()
		# 等致命一击的攻击 / 死亡动画完整播放（队列空 + 没在跑）
		await _battle_anim_director.await_anims_finished()
		# 此时动画已自然跑完；清理瞬时视觉态 + 动画并发状态（理论应已空，防御性归零）
		_battle_view.clear()
		_battle_anim_director.reset()
		# B MVP 重生分支：_player_lifecycle.trigger_coma_or_lose 内部会处理 _player_lifecycle.is_in_coma() 守卫
		# _battle_session 在 reload 场景后由新 _ready 重新初始化（默认 null），无需手动清
		_battle_session = null
		# 入口 4 MVP：先 zoom 回归（用开战时 _unit.position 作 tween 终点）
		# 重生分支由 _player_lifecycle.trigger_coma_or_lose 内部处理 _unit.position 重置 + camera 同步（瞬移到 spawn）
		_end_battle_camera()
		_player_lifecycle.trigger_coma_or_lose()
		return

	# VICTORY / MANUAL_EXIT：原入口 1.2 P1-4 修复路径（立即清理）
	# Tween 完成回调可能在战斗结束后异步触发，但回调内的 erase / count -= 都对清空后的状态安全
	# 不主动 kill Tween：让 Tween 自然跑完，回调即 noop（BattleViewState 已空 + Director 计数已 0）
	_battle_view.clear()
	_battle_anim_director.reset()
	if _battle_hud != null:
		_battle_hud.hide_hud()

	# E MVP §2.8 / §3.4：胜利 / 手动退出 → 玩家位置保持队长当前格
	# 同步战斗内队长 battle_position 回 _unit.position + 视觉位置 + 摄像机；
	# 不调用会让探索态单位回到开战前位置，违背设计约束
	_sync_world_unit_from_battle_leader()
	# 入口 4 MVP：sync 之后再 zoom 回归 —— _end_battle_camera 内取 _unit.position 已是最终队长格
	# Tween 起点 = sync 设的 camera.position（=队长最终位置），终点 = 同位置；只 zoom 在变（视觉自然）
	_end_battle_camera()

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

		# 2. 清理 _level_slots + 恢复 schema slot 标记
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

		# 核心目标传达 L1.5（H1）：移除兜底清场胜利——占领敌方核心为唯一胜利路径
		# （清场后核心仍在地图上，玩家需走到核心占领；能清场必能占核心、分叉无意义）
	elif reason == BattleSession.EndReason.RETREAT:
		# 持久 slot 战场参与设计 L1.1：撤离分支
		# defeated_packs 实际是 BattleSession.participating_packs（全部参战敌包）
		# 对每个 pack 区分两种处置：
		#   1. troops 全死（current_hp<=0 全部移除后空了）→ 与 VICTORY 同处置（erase + schema 恢复），但不发奖励
		#   2. troops 部分残余 → 敌包保留在 _level_slots 原位置，HP / 剩余 troop 已在战斗中实时写入
		for pack_v in defeated_packs:
			var pack: LevelSlot = pack_v as LevelSlot
			if pack == null:
				continue
			pack.remove_defeated_troops()
			if pack.troops.is_empty():
				# 全灭路径（与 VICTORY 同步处置 _level_slots / _schema）
				pack.mark_defeated()
				var lvpos: Vector2i = pack.position
				if _level_slots.has(lvpos):
					_level_slots.erase(lvpos)
				if _schema != null:
					var orig_type: int = _original_slot_types.get(lvpos, MapSchema.SlotType.NONE) as int
					_schema.set_slot(lvpos.x, lvpos.y, orig_type as MapSchema.SlotType)
					_original_slot_types.erase(lvpos)
			# 否则：敌包部分残余,保留在 _level_slots,troops HP 已是战斗结果

		# 核心目标传达 L1.5（H1）：兜底清场胜利已移除——撤离即便清空全部 pack 也不胜利，需占核心

	# MANUAL_EXIT：不发奖励，敌方残余保留；走通用收尾

	# 4. 队员阵亡评估
	#    VICTORY / MANUAL_EXIT：完整 evaluate（含队长跌阈值昏迷判定）；返回 true 表示已触发昏迷 / 失败遮罩，中断后续收尾
	#      （队长跌阈值的极端情况通常已在战斗中走 COMA 路径，不走到此处）
	#    RETREAT：撤离 ≠ 昏迷（持久 slot 战场参与设计 L1.1）—— 只清理阵亡队员、保留低 HP 队长，继续走通用收尾
	#      不复用 evaluate_party_state，避免低 HP 队长撤离后被误判昏迷（codex 审查 P1）
	if reason == BattleSession.EndReason.RETREAT:
		_player_lifecycle.cleanup_dead_members()
	elif _player_lifecycle.evaluate_party_state(_game_finished):
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
	_renderer.queue_redraw()


## 玩家行动后判断：当前单位回合结束（has_attacked = true）→ 自动切下一玩家单位
## try_player_attack 已置 has_attacked = true；try_player_move 仅 has_moved，不切
##
## 切到下一单位 / 切敌方回合都由 BattleSession.advance_to_next_player_unit 处理
## 敌方回合启动后由 _step_enemy_turn_loop 串行驱动
##
## 时序修复 B（2026-05-11）：玩家攻击 / 跳过 anim 还在跑时，
## 直接 advance → 敌方 step 会让"敌方逻辑判定 + COMA 检测"先于玩家攻击动画完成
## 玩家观感：攻击完毕立刻 COMA 黑屏，看不到敌方反击的因果
##
## 修复：在 advance 前 await 当前 anim 队列空（含玩家攻击三段 anim + 死亡 anim）
## 效果：玩家攻击动画完整播完 → 敌方 step → 敌方攻击动画 → COMA 黑屏（如果命中）
##
## 调用方（_handle_battle_click / _on_battle_hud_attack_pressed / _on_battle_hud_skip_pressed）
## fire-and-forget 即可，不必 await 本函数；
## await 期间玩家点击被 _handle_battle_click 内 _battle_anim_director.is_animating() 守卫拦截，
## 按钮被 BattleAnimDirector 在动画期间 set_actions_enabled(false) 锁住，无并发风险
func _post_player_action_check() -> void:
	if _battle_session == null or _battle_session.is_ended():
		return
	if not _battle_session.is_player_turn():
		return
	var actor: BattleUnit = _battle_session.current_actor()
	if actor == null or actor.has_attacked:
		# 关键 await：等当前 anim 队列空，让玩家攻击 anim 完整播完
		await _battle_anim_director.await_anims_finished()
		# await 期间状态可能变化（理论 VICTORY 由 try_player_attack 内同步触发；
		# 此处仍做防御性校验，避免 await 期间被外部代码意外结束 session）
		if _battle_session == null or _battle_session.is_ended():
			return
		if not _battle_session.is_player_turn():
			return
		var actor2: BattleUnit = _battle_session.current_actor()
		if actor2 == null or actor2.has_attacked:
			_battle_session.advance_to_next_player_unit()
			# 切到敌方回合 → 串行驱动敌方单位行动
			if _battle_session.is_enemy_turn():
				_run_enemy_turn_async()


## 敌方回合串行驱动（异步推进 + 等动画完成才推下一个）
##
## 入口 1.2 P1-1 修复：
##   - 不再 step 后立即用固定 0.18s timer 推下一个 step（会与 0.35s 移动 / 0.30s 攻击 Tween 重叠）
##   - 改为：本次 step 触发 emit → sink 入队 anim runner → BattleAnimDirector 动画清空时
##     emit anims_drained → _try_schedule_next_enemy_step（带 ANIM_CFG.enemy_step_gap=0.18s 间隔）
##   - 兜底：若本次 step 没产生任何 anim（BattleAI 极端短路），Director 不在动画态，主动调度
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
	if not has_more:
		return
	# 推下一个 step：若本次 step 启动了 anim（队列非空 / count > 0），等 _end_battle_anim 触发；
	# 否则（极端：step 无 emit）兜底立即调度
	_try_schedule_next_enemy_step()


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


## [结束回合] 按钮 / Enter 路由（战斗单位视觉与操作改进_MVP §2.3）
##
## 处理顺序（关键，G5 拍板）：
##   1. 先批量结束所有"已移动未攻击"（Moved）单位 —— 解决多单位逐个收尾的操作负担
##   2. 再扫剩余未结束单位（此时必为"未移动"Idle 单位，因 Moved 已在步骤 1 结束）
##   3. 有 Idle → 守卫：选中第一个 Idle 单位 + 弹板提示「还有 N 个单位未移动」，不结束回合
##      无 Idle → 全员已结束 → _post_player_action_check 推进切敌方回合
func _on_battle_hud_end_turn_pressed() -> void:
	if _battle_session == null or _battle_session.is_ended():
		return
	if not _battle_session.is_player_turn():
		return
	# 1. 先批量结束所有"已移动未攻击"单位（走 skip_units_batch → 飘字并行 spawn，避免 N 个串行阻塞）
	var to_skip: Array[BattleUnit] = []
	for u in _battle_session.player_units:
		if u != null and u.is_active and u.is_alive() and u.has_moved and not u.has_attacked:
			to_skip.append(u)
	if not to_skip.is_empty():
		_battle_session.skip_units_batch(to_skip)
	# 2. 扫剩余未结束单位（必为"未移动"Idle）
	var idle_units: Array[BattleUnit] = []
	for u in _battle_session.player_units:
		if u != null and u.is_active and u.is_alive() and not u.has_attacked:
			idle_units.append(u)
	# 3. 分支
	if not idle_units.is_empty():
		# 守卫：选中第一个未移动单位（地格呼吸角标即定位过去）+ 弹板提示，不结束回合
		_battle_session.try_select_player_unit(idle_units[0])
		_show_end_turn_guard_dialog(idle_units.size())
	else:
		# 全员已结束 → 推进 / 切敌方回合（_post_player_action_check 内部 await 动画 + advance）
		_post_player_action_check()


## 结束回合守卫弹板（§2.3）：提示玩家还有未移动单位，确定关闭（不结束回合）
## 弹板用 Godot AcceptDialog（MVP；样式后续可 .tscn 化，见待跟踪 P2）
func _show_end_turn_guard_dialog(unmoved_count: int) -> void:
	if _end_turn_guard_dialog == null:
		_end_turn_guard_dialog = AcceptDialog.new()
		_end_turn_guard_dialog.title = "结束回合"
		_end_turn_guard_dialog.ok_button_text = "确定"
		var ui_layer: CanvasLayer = $UILayer
		ui_layer.add_child(_end_turn_guard_dialog)
	_end_turn_guard_dialog.dialog_text = "还有 %d 个单位未移动，请继续行动。" % unmoved_count
	_end_turn_guard_dialog.popup_centered()


## [退出战斗] / [撤离] 按钮路由（持久 slot 战场参与设计 L1.1：信号扩展为携带 mode）
##
## mode == "exit"    —— 战场内无敌，走 try_manual_exit；失败时给 notice（理论上 HUD 已只在无敌时显示"退出战斗"，但仍兜底）
## mode == "retreat" —— 队长在战场边界，走 try_retreat；失败时表示前置不满足（防御性兜底，正常不应触发）
func _on_battle_hud_exit_pressed(mode: String) -> void:
	if _battle_session == null or _battle_session.is_ended():
		return
	match mode:
		"exit":
			if not _battle_session.try_manual_exit():
				_show_notice("战场内仍有敌人，无法退出")
		"retreat":
			if not _battle_session.try_retreat():
				_show_notice("队长不在战场边界，无法撤离")
		_:
			push_error("[WorldMap] _on_battle_hud_exit_pressed 收到未知 mode：%s" % mode)


# ─────────────────────────────────────────
# 关卡 Slot 管理（M7 重构）
# ─────────────────────────────────────────
#
# M7 前：轮次切换时整批清理敌方关卡 + 整批生成新关卡
# M7 后：敌方生成走 EnemyReinforcement（初始预置 + 每 5 回合增援）；
#        击败的敌方部队包在 _on_battle_session_ended VICTORY 分支就地从 _level_slots 删除 + 恢复 schema slot
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

## 为我方部队应用伤害（从 BattleResult 中提取 damages），同时追踪累计损兵
##
## B 重生周期 MVP：返回 _player_lifecycle.evaluate_party_state(_game_finished) 的结果
##   - true → 已触发昏迷过渡 / 末周期失败遮罩；调用方应立即中断奖励发放 / 事件推送 / 后处理
##   - false → 战斗流程继续
##
## 战斗 / 强制战斗均经过本函数，是玩家方 hp 变化的最主要入口
func _apply_player_damages(result: BattleResolver.BattleResult) -> bool:
	var troop_index: int = 0
	for ch in _player_lifecycle.characters():
		if ch.has_troop():
			if troop_index < result.damages.size():
				# 追踪实际损失（不超过剩余兵力）
				var actual_dmg: int = mini(result.damages[troop_index], ch.troop.current_hp)
				_total_hp_lost += actual_dmg
				ch.troop.take_damage(result.damages[troop_index])
				if ch.troop.is_defeated():
					ch.clear_troop()
			troop_index += 1
	return _player_lifecycle.evaluate_party_state(_game_finished)

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

# ─────────────────────────────────────────
# 装配管理信号处理
# ─────────────────────────────────────────

## 打开装配管理面板（非扎营模式，仅允许替换）
func _open_manage_panel() -> void:
	# E MVP：战斗态守卫——_is_in_battle 期间不允许装配 / 用道具（设计 §2.10）
	if _game_finished or _is_moving or _is_camping or _event_panel.is_open or _player_lifecycle.is_in_coma() or _is_in_battle():
		return
	_manage_ui.open(_player_lifecycle.characters(), _inventory, false)

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
	_player_lifecycle.evaluate_party_state(_game_finished)

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
	_player_lifecycle.evaluate_party_state(_game_finished)

## 入口 2 MVP 2.3（2026-05-11）：扎营场景判定
##
## 返回 Dictionary:
##   {"scenario": "camp_wild" | "camp_village" | "camp_town", "slot_name": String}
##   wild 场景 slot_name 为空字符串
##
## 优先级:TOWN > VILLAGE > WILD(玩家位置同时在多个 slot 范围内时取最高级)
## slot_name 取该次判定命中的同类型 slot 中曼哈顿距离最近的 display_id
func _resolve_camp_scenario() -> Dictionary:
	var result: Dictionary = {"scenario": "camp_wild", "slot_name": ""}
	if _schema == null or _unit == null:
		return result
	# OccupationSystem.slots_covering 返回无类型 Array;不能直接赋给 Array[PersistentSlot]
	# 用 Array 接收 + 循环内 cast,符合项目类型化规范(避免 LSP 报错)
	var covered: Array = OccupationSystem.slots_covering(
		_unit.position, Faction.PLAYER, _schema.persistent_slots
	)
	# 过滤玩家方 + 分类
	var towns: Array[PersistentSlot] = []
	var villages: Array[PersistentSlot] = []
	for entry in covered:
		var slot: PersistentSlot = entry as PersistentSlot
		if slot == null or slot.owner_faction != Faction.PLAYER:
			continue
		if slot.type == PersistentSlot.Type.TOWN:
			towns.append(slot)
		elif slot.type == PersistentSlot.Type.VILLAGE:
			villages.append(slot)
	# 取曼哈顿距离最近的 slot 为 slot_name 来源
	var pick_nearest: Callable = func(slots: Array[PersistentSlot]) -> PersistentSlot:
		var best: PersistentSlot = null
		var best_dist: int = 99999
		for s in slots:
			var d: int = absi(_unit.position.x - s.position.x) + absi(_unit.position.y - s.position.y)
			if d < best_dist:
				best_dist = d
				best = s
		return best
	if not towns.is_empty():
		result["scenario"] = "camp_town"
		var nearest: PersistentSlot = pick_nearest.call(towns)
		if nearest != null:
			result["slot_name"] = nearest.display_id
	elif not villages.is_empty():
		result["scenario"] = "camp_village"
		var nearest: PersistentSlot = pick_nearest.call(villages)
		if nearest != null:
			result["slot_name"] = nearest.display_id
	return result


## 入口 2 MVP 2.3（2026-05-11）：把 ProductionSystem entry 转为 {item, count} 字典
##
## entry 字段结构因 kind 不同:
##   KIND_RESOURCE: resource_type / amount → 取 ResourceSlot.RESOURCE_TYPE_NAMES + amount
##   KIND_STONE:    amount → "石料" + amount
##   KIND_ITEM:     item: ItemData → display_name + stack_count
##   其他:          fallback "物资" / 1
func _entry_to_item_count(entry: Dictionary) -> Dictionary:
	var kind: String = String(entry.get("kind", ""))
	match kind:
		ProductionSystem.KIND_RESOURCE:
			var res_type: int = int(entry.get("resource_type", 0))
			var name: String = ResourceSlot.RESOURCE_TYPE_NAMES.get(res_type, "?") as String
			return {"item": name, "count": int(entry.get("amount", 0))}
		ProductionSystem.KIND_STONE:
			return {"item": "石料", "count": int(entry.get("amount", 0))}
		ProductionSystem.KIND_ITEM:
			var item: ItemData = entry.get("item") as ItemData
			if item != null:
				return {"item": item.display_name, "count": item.stack_count}
			return {"item": "物资", "count": 1}
		_:
			return {"item": "物资", "count": 1}



## sink: PartyRecruitment.recruit_triggered — 接英雄招募事件并推入 EventPanel
func _on_recruit_triggered(hero_dict: Dictionary, milestone: int) -> void:
	if _event_panel == null:
		push_warning("WorldMap._on_recruit_triggered: EventPanelUI 未就绪，事件丢弃")
		return
	var hero_name: String = String(hero_dict.get("name", "新成员"))
	# 入口 2 MVP 2.3（2026-05-11）:走 NarrativeProvider recruit_event 池
	var ctx: Dictionary = {
		"leader_name": _player_lifecycle.current_leader_name(),
		"recruit_name": hero_name,
		"milestone": milestone,
	}
	var narrative: String = NarrativeProvider.pick("recruit_event", ctx)
	var event: Dictionary = {
		"type": "recruit",
		"title": "新成员加入",
		"narrative": narrative,
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
## 不去重：MVP 不检查兵种重复——_player_lifecycle.get_team_hero_ids 已保证不抽到当前在队成员
func _on_recruit_confirmed(_action_result: String, payload: Dictionary) -> void:
	if payload.is_empty():
		push_warning("WorldMap._on_recruit_confirmed: payload 为空，入队跳过")
		return
	var hero_id: int = int(payload.get("id", "-1"))
	if hero_id < 0:
		push_warning("WorldMap._on_recruit_confirmed: hero_id 非法，入队跳过")
		return
	# 防御：极端时序下 _on_recruit_confirmed 触发时该英雄已被其他途径加入
	for ch_existing in _player_lifecycle.characters():
		if ch_existing != null and ch_existing.hero_id == hero_id:
			push_warning("WorldMap._on_recruit_confirmed: hero_id=%d 已在队，跳过重复入队" % hero_id)
			return
	# 构造 CharacterData
	var member: CharacterData = CharacterData.new()
	# id 在队伍中按 size+1 递增；与队长保持简单序号语义
	member.id = _player_lifecycle.characters().size() + 1
	member.hero_id = hero_id
	var troop: TroopData = TroopData.new()
	troop.troop_type = _player_lifecycle.parse_troop_type(String(payload.get("troop_type", "SWORD")))
	# 入队队员品质：hero_pool 行未填时回退 R（队员相对队长更平均）
	troop.quality = _player_lifecycle.parse_troop_quality(String(payload.get("troop_quality", "")), TroopData.Quality.R)
	member.troop = troop
	# MVP-δ 阶段 2：入队 → PlayerLifecycle.add_character 内同步 _total_max_hp + append
	_player_lifecycle.add_character(member)
	_update_hud()
	# C MVP P1 修复：扎营流程在 push 入队事件后立刻 _manage_ui.open(...)，确认入队事件时
	# 装配面板已打开且按旧 _player_lifecycle.characters() 渲染过 refresh；这里补一次 refresh 让新队员
	# 在本次扎营内立即可见 / 可装配（设计文档 §6 数据驱动语义 + §7 场景 2 验收）
	if _manage_ui != null and _manage_ui.is_open:
		_manage_ui.refresh()


# ─────────────────────────────────────────
# 多角色辅助方法
# ─────────────────────────────────────────

## 全灭兜底（B MVP 退化）：仅在 _player_lifecycle.characters() 为空时触发；正常昏迷 / 失败路径已被 _player_lifecycle.evaluate_party_state 接管
##
## 仍保留是因为：极端时序（外部代码清空 _player_lifecycle.characters()）或老调用点未迁到 _player_lifecycle.evaluate_party_state 时
## 不至于"无人则永久卡死"。返回 true 表示游戏已结束，调用方应中断后续流程。
func _check_defeat() -> bool:
	if _game_finished:
		return true
	if _player_lifecycle.is_in_coma():
		# 已进入昏迷过渡，等 timer 走完即可
		return true
	if _player_lifecycle.characters().is_empty():
		_game_finished = true
		_reachable_tiles = {}
		_show_defeat_text()
		_renderer.queue_redraw()
		return true
	return false

## 获取所有已装配部队的部队列表（用于战斗结算）
func _get_active_troops() -> Array[TroopData]:
	var troops: Array[TroopData] = []
	for ch in _player_lifecycle.characters():
		if ch.has_troop():
			troops.append(ch.troop)
	return troops

# ─────────────────────────────────────────
# MVP-δ 阶段 2：PlayerLifecycle 信号 sink（_player_lifecycle.coma_triggered /
# defeat_triggered / respawn_intro_ready 三个信号让 PlayerLifecycle 不直接依赖 UI 系统）
# ─────────────────────────────────────────

## 队长昏迷过渡触发（PlayerLifecycle.coma_triggered sink）
##
## 原 _trigger_coma_or_lose 内 OverlayTransitionUI.play 直调迁过来；
## 状态副作用（_reachable_tiles = {} / _pending_camp_manage_open = false / _renderer.queue_redraw）
## 仍在 WorldMap 内执行——这些是 WorldMap 自己的视图态
##
## MVP-δ codex review P1 修复：midpoint 闭包整体迁到本处构造（原在 PlayerLifecycle.trigger_coma_or_lose 内）
## 闭包负责：advance_cycle（RunState 周期推进）+ reload_current_scene（场景重启）+ 返回 world_ready
##   让 OverlayTransitionUI 在 phase B 内调用 + await，等新场景 _ready 触发 notify_world_ready 后继续 phase C
## 由 WorldMap 持有这段时序逻辑：PlayerLifecycle 彻底独立于 OverlayTransitionUI / SceneTree
func _on_player_coma_triggered(lines: PackedStringArray, icon_data: Dictionary) -> void:
	_reachable_tiles = {}
	# codex review P1-5 修复（2026-05-10）：coma 触发即重置 flag
	# 防 EventPanel 在战斗中被 hide 而非 close → flag 永久 true → 下次 EventPanel close 误开 ManageUI
	_pending_camp_manage_open = false
	_renderer.queue_redraw()
	var midpoint: Callable = func() -> Signal:
		RunState.advance_cycle()
		get_tree().reload_current_scene()
		return OverlayTransitionUI.world_ready
	OverlayTransitionUI.play(lines, icon_data, midpoint)


## 末周期失败触发（PlayerLifecycle.defeat_triggered sink）
## 原 _trigger_coma_or_lose 内 _on_victory_decided(ENEMY_1) 直调迁过来
func _on_player_defeat_triggered(faction: int) -> void:
	_on_victory_decided(faction)


## 新场景启动重生文案就绪（PlayerLifecycle.respawn_intro_ready sink）
## 原 _init_player 内 OverlayTransitionUI.notify_world_ready 直调迁过来
func _on_player_respawn_intro_ready(respawn_line: String) -> void:
	OverlayTransitionUI.notify_world_ready(1, respawn_line)


## L1.3 周期胜利目标 MVP：非末周期占据敌方核心 / 清场 → 周期推进过渡（VictoryJudge.cycle_victory sink）
##
## 与 _on_player_coma_triggered 同形（黑屏过渡 midpoint 模式），差别：
##   - 推进走 RunState.advance_cycle_on_victory（保留队长 + 部队满血 + quality+1），非 advance_cycle（抽新队长）
##   - 文案走 event_narrative_pool cycle_victory 场景池（队长跨周期不变，单句即可）
## 视图态副作用（_reachable_tiles / _pending_camp_manage_open / queue_redraw）与 coma 一致清理
func _on_cycle_victory_triggered() -> void:
	# P1-1（codex）：锁住 fade-in → reload 间的输入，避免旧场景在过渡窗口响应移动/扎营/建造
	# reload 后新场景 WorldMap 实例本字段默认 false，自然清零
	_is_cycle_advancing = true
	_reachable_tiles = {}
	_pending_camp_manage_open = false
	_renderer.queue_redraw()
	# 周期胜利文案（reload 前构造：此时旧队长仍在，名字 = reload 后保留的同一队长）
	var leader_name: String = _player_lifecycle.current_leader_name()
	var victory_line: String = NarrativeProvider.pick("cycle_victory", {"leader_name": leader_name})
	var lines: PackedStringArray = PackedStringArray([victory_line])
	# 占位 icon（L1.3 待验收调）
	var icon_data: Dictionary = {"icon": "🏰", "count": 1}
	# 当前队长 CharacterData：midpoint 在 reload 前执行，旧 PlayerLifecycle 仍在，引用有效
	var leader_chars: Array[CharacterData] = _player_lifecycle.characters()
	var leader_char: CharacterData = leader_chars[0] if not leader_chars.is_empty() else null
	var midpoint: Callable = func() -> Signal:
		RunState.advance_cycle_on_victory(leader_char)
		get_tree().reload_current_scene()
		return OverlayTransitionUI.world_ready
	OverlayTransitionUI.play(lines, icon_data, midpoint)


## L1.3：新场景启动周期胜利推进就绪（PlayerLifecycle.cycle_victory_intro_ready sink）
## 队长跨周期不变 → 无需替换文案行，仅 emit world_ready 解除 phase B await
func _on_player_cycle_victory_intro_ready() -> void:
	OverlayTransitionUI.notify_world_ready()


# ─────────────────────────────────────────
# 奖励辅助方法
# ─────────────────────────────────────────

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
	# B 重生周期 MVP：昏迷过渡期间锁 Q 键放弃，避免在 OverlayTransitionUI 黑屏过渡中触发整局失败
	# E MVP：战斗态期间锁 Q 键放弃（设计 §2.10）；战斗结束才允许整局放弃
	if _game_finished or _is_moving or _manage_ui.is_open or _is_camping or _build_panel_ui.is_open or _player_lifecycle.is_in_coma() or _is_in_battle():
		return
	_game_finished = true
	_reachable_tiles = {}
	_show_defeat_text()
	_renderer.queue_redraw()


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
	if _player_lifecycle.is_in_coma():
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


## 入口 4 MVP（2026-05-09）：探索态【扎营】按钮点击 handler
## 守卫由 _start_camp 内部处理（与空格键路径共用单一入口）
func _on_explore_camp_pressed() -> void:
	_start_camp()


## 入口 4 MVP（2026-05-09 BUG 修复）：事件面板关闭后刷新探索态行动按钮
## 触发：EventPanelUI.closed signal
## 必要性：事件面板关闭时 _supply / 触发距离内敌包 等条件可能已变（事件 callback 改了 _supply）
##         不刷新 → 扎营 / 攻击按钮 visible 状态滞后
##
## 入口 2 MVP 2.1 议题 1（2026-05-10）：扎营路径事件队列清空 → 打开 ManageUI
## _pending_camp_manage_open 由 _start_camp 内事件入队分支置 true
func _on_event_panel_closed() -> void:
	_update_explore_action_button()
	_renderer.queue_redraw()
	# 议题 1：扎营路径上的事件全部确认完毕后才打开养成面板
	if _pending_camp_manage_open:
		_pending_camp_manage_open = false
		if _manage_ui != null:
			_manage_ui.open(_player_lifecycle.characters(), _inventory, true)


## 刷新探索态【攻击】/【扎营】按钮可见性
##
## 入口 4 MVP（2026-05-09 v2）：两按钮独立判断 + HBox 平行排布
## 显示规则（独立，可同时为 true）：
##   - 攻击按钮：通用守卫通过 + 补给 > 0 + 触发距离内有可交互敌方包
##   - 扎营按钮：通用守卫通过 + 补给耗尽（_supply == 0）
##   - 同时满足时两按钮并列展示，玩家自选
##
## 调用时机：_update_hud / _refresh_reachable / sink 末尾 / faction 切换 / 战斗结束
func _update_explore_action_button() -> void:
	if _explore_attack_btn == null:
		return
	_explore_attack_btn.visible = _can_show_explore_attack()
	if _explore_camp_btn != null:
		_explore_camp_btn.visible = _can_show_explore_camp()


## 探索态【攻击】按钮可见性条件评估
## 抽出独立函数避免在 _update_explore_action_button 里堆守卫表达式
## 入口 4 MVP（v3 2026-05-09）：去掉 _supply <= 0 短路 —— 补给耗尽 + 敌包在范围时按钮仍显示
##                              点击会走 _try_trigger_active_battle 内的 supply==0 notice 分支
##                              这样"补给 0 + 敌包在范围"才能同时显示攻击 + 扎营两按钮供玩家选
func _can_show_explore_attack() -> bool:
	if not _passes_explore_action_guards():
		return false
	var candidates: Array[LevelSlot] = _get_packs_in_range(_unit.position, _battle_trigger_range)
	return not candidates.is_empty()


## 探索态【扎营】按钮可见性条件评估（入口 4 MVP）
## 显示条件：通用守卫通过 + 补给 == 0
## 不要求"敌包不在范围"——补给 0 时即使有敌包也无法主动战斗，仍优先提示扎营
func _can_show_explore_camp() -> bool:
	if not _passes_explore_action_guards():
		return false
	return _supply <= 0


## 探索态行动按钮共通守卫（入口 4 MVP 抽取）
## 攻击 / 扎营按钮共用的"能不能现在弹按钮"基础检查
func _passes_explore_action_guards() -> bool:
	if _is_in_battle():
		return false
	if _game_finished or _is_moving or _player_lifecycle.is_in_coma() or _is_camping:
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
	if _player_lifecycle.characters().is_empty() or _player_lifecycle.characters()[0] == null or not _player_lifecycle.characters()[0].has_troop():
		return false
	return true


## E MVP [F] 键 sink：探索态触发主动战斗 / 战斗态尝试手动退出
##
## 探索态守卫覆盖（防止在错位时序入战）：
##   _is_moving / _manage_ui.is_open / _is_camping / _build_panel_ui.is_open
##   _player_lifecycle.is_in_coma()（昏迷过渡，B MVP）/ _enemy_movement.is_moving（敌方移动阶段）
##   非 PLAYER 回合（敌方阶段不可主动入战）
##
## 战斗态：BattleHUD 退出按钮按下也走 _on_battle_hud_exit_pressed，与 [F] 同语义
func _handle_f_key() -> void:
	# 入口 4 MVP（2026-05-09）：战斗态 F 语义改为「攻击」（与按钮等价）
	# 原语义「退出战斗」（try_manual_exit）极低频，仅保留按钮入口
	# 设计意图：F 在两态语义统一为"进攻 / 推进战斗"——探索态主动战斗 + 战斗态选最弱目标攻击
	# 内部守卫（session 存在 / 玩家回合 / 有可攻击目标）由 _on_battle_hud_attack_pressed 处理
	if _is_in_battle():
		_on_battle_hud_attack_pressed()
		return
	# 探索态：补给 / 候选 / 触发由 _try_trigger_active_battle 内部判定
	if _game_finished or _player_lifecycle.is_in_coma() or _is_moving or _manage_ui.is_open or _is_camping or _build_panel_ui.is_open:
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
	# P0 X-A 后默认 1 敌方核心 + 7 城镇（含玩家方占位）；CSV 通常会覆盖此处默认
	config.persistent_core_count = int(map_cfg.get("persistent_core_count", "1"))
	config.persistent_town_count = int(map_cfg.get("persistent_town_count", "7"))
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

## P0 第二阶段（整局节奏重设计）：用 cycle_config.csv 覆盖 map_cfg 中的周期级字段
##
## 处理流程：
##   1. 加载 cycle_config.csv → _cycle_config_rows
##   2. 按 RunState.cycle_index() 找对应行
##   3. 找到则把 map_width / map_height / start_x/y / end_x/y / persistent_total_count
##      / persistent_town_count / persistent_village_count 字段覆盖到 map_cfg 字典；
##      has_enemy_core 推导 persistent_core_count = "1"（始终生成 1 个敌方 CORE_TOWN）
##   4. 缓存 initial_enemy_pack_count / reinforcement_interval 到 WorldMap 字段
##   5. 找不到则 push_warning，map_cfg 字段保留原值（map_config 兜底）；spawn 节奏字段用默认
##
## 设计意图：把"按 cycle 切配置"对调用方透明——后续 _load_pcg 读 map_cfg 时拿到的是本周期值
func _apply_cycle_config(map_cfg: Dictionary) -> void:
	_cycle_config_rows = ConfigLoader.load_csv(CONFIG_CYCLE)
	var current_cycle: int = RunState.cycle_index()
	var cycle_row: Dictionary = {}
	for entry in _cycle_config_rows:
		var row: Dictionary = entry as Dictionary
		if row == null:
			continue
		if int(row.get("cycle_index", "-1")) == current_cycle:
			cycle_row = row
			break

	if cycle_row.is_empty():
		push_warning("WorldMap: cycle_config 未找到 cycle_index=%d 对应行，使用 map_config 兜底" % current_cycle)
		# 兜底：spawn 节奏字段用默认值（initial pack 5 / interval 5）
		_current_cycle_initial_pack_count = 5
		_current_cycle_reinforcement_interval = 5
		_current_cycle_has_enemy_core = false
		return

	# 用 cycle row 覆盖 map_cfg 中对应字段（后续 _load_pcg 读 map_cfg 拿到本周期值）
	# persistent_total_count 不在此列表 —— 由 core(1) + town + village 自动推导避免配置错位
	var override_keys: Array[String] = [
		"map_width", "map_height", "start_x", "start_y", "end_x", "end_y",
		"persistent_town_count", "persistent_village_count",
	]
	for key in override_keys:
		if cycle_row.has(key):
			map_cfg[key] = str(cycle_row[key])

	# has_enemy_core 推导 persistent_core_count（数据层始终生成 1 个，视觉 / 判定由 has_enemy_core 控制）
	# 当前 MVP：始终 1（has_enemy_core=false 时仅视觉走普通 TOWN + VictoryJudge cycle 过滤拦截胜利）
	map_cfg["persistent_core_count"] = "1"

	# P0 第二阶段（跑测 BUG 修复 2026-05-11）：persistent_total_count 由 1 + town + village 自动推导
	# 原因：csv 中 total 与 town/village 是冗余双写，用户手动调整时极易错位（如 cycle_config
	# 调整地图大小时改了 total 忘改 town/village），导致 PCG 校验失败
	# cycle_config.csv 中 persistent_total_count 字段保留作"目标参考"（编辑时可见目标总数），
	# 但 PCG 实际用推导值；字段值与推导值不一致时 push_warning 提示
	var derived_town: int = int(map_cfg.get("persistent_town_count", "7"))
	var derived_village: int = int(map_cfg.get("persistent_village_count", "18"))
	var derived_total: int = 1 + derived_town + derived_village
	if cycle_row.has("persistent_total_count"):
		var declared_total: int = int(cycle_row.get("persistent_total_count", "0"))
		if declared_total != derived_total:
			push_warning("WorldMap: cycle_config[%d].persistent_total_count=%d 与 1+town(%d)+village(%d)=%d 不一致；以推导值 %d 为准" % [
				current_cycle, declared_total, derived_town, derived_village, derived_total, derived_total
			])
	map_cfg["persistent_total_count"] = str(derived_total)

	# 缓存周期级字段
	# initial_enemy_pack_count: 钳制 ≥ 0（0 = 本周期不预置初始 pack，合理边界）
	# reinforcement_interval: 钳制 ≥ 1（避免 EnemyAI._step_reinforcement 的 count % interval 除零崩溃）
	var raw_pack: int = int(cycle_row.get("initial_enemy_pack_count", "5"))
	var raw_interval: int = int(cycle_row.get("reinforcement_interval", "5"))
	if raw_pack < 0:
		push_warning("WorldMap: cycle_config[%d].initial_enemy_pack_count 非法 %d，钳制为 0" % [current_cycle, raw_pack])
	if raw_interval < 1:
		push_warning("WorldMap: cycle_config[%d].reinforcement_interval 非法 %d，钳制为 1 防除零" % [current_cycle, raw_interval])
	_current_cycle_initial_pack_count = maxi(0, raw_pack)
	_current_cycle_reinforcement_interval = maxi(1, raw_interval)

	# P0 第二阶段 P1-2a 修复：缓存 has_enemy_core，视觉绘制改用该字段（替代硬编码 is_last_cycle()）
	# VictoryJudge.check_on_slot_owner_changed 仍用 RunState.is_last_cycle()——static 路径不便注入
	# MVP 期 has_enemy_core 与 is_last_cycle() 同义；若未来配置错位需 VictoryJudge 也切到该字段
	_current_cycle_has_enemy_core = str(cycle_row.get("has_enemy_core", "false")).to_lower() == "true"


## P0 第二阶段：PCG 生成后从 schema 找敌方 CORE_TOWN 位置缓存到 _enemy_core_origin_pos
##
## 设计原因：EnemyReinforcement.spawn_batch 当前查 owner=ENEMY_1 的 CORE_TOWN 作 spawn 锚，
##           前两周期玩家占领后 owner 翻转 → reinforcement 失效。改为缓存"PCG 生成时的原始位置"，
##           不查 owner——玩家占领后敌方仍从该位置周围 spawn。
func _cache_enemy_core_origin_pos() -> void:
	if _schema == null:
		_enemy_core_origin_pos = Vector2i(-1, -1)
		return
	for entry in _schema.persistent_slots:
		var slot: PersistentSlot = entry as PersistentSlot
		if slot == null:
			continue
		if slot.type == PersistentSlot.Type.CORE_TOWN and slot.owner_faction == Faction.ENEMY_1:
			_enemy_core_origin_pos = slot.position
			return
	push_warning("WorldMap: PCG 后未找到敌方 CORE_TOWN，_enemy_core_origin_pos 保持 (-1,-1)；reinforcement 将跳过")
	_enemy_core_origin_pos = Vector2i(-1, -1)


## JSON 模式：从配置中读取文件路径后加载
func _load_json(map_cfg: Dictionary) -> void:
	var path: String = map_cfg.get("json_path", "") as String
	if path.is_empty():
		push_error("WorldMap: map_config 中未配置 json_path")
		return
	_schema = MapLoader.load_from_file(path)
	if _schema == null:
		push_error("WorldMap: JSON 地图加载失败，路径：" + path)
