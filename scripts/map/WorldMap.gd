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

## 【L1.3b Bug2 修复】昏迷重生黑屏期重绘时序（秒）：
## DELAY = 传送后等这么久再 queue_redraw（让相机 reset_smoothing 在黑屏下稳定，否则帧0重绘视口仍偏）；
## HOLD  = 黑屏总 hold（> DELAY），确保延迟重绘的 _draw 在揭幕前跑完 → 揭幕即正确、无闪烁。
## 均在黑屏内，玩家不可感知。
const _RESPAWN_REDRAW_DELAY_SEC: float = 0.05
const _RESPAWN_REDRAW_HOLD_SEC: float = 0.15

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

## L1.3c 阶段 C：敌方增援 spawn 锚字段已退役——增援改从玩家视野外暗影环带采样
## （EnemyReinforcement.spawn_batch 默认分支直接以玩家位置 + 环带半径定位，不再缓存固定锚）

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

## 流程是否已结束（全部通关或部队被击败）
var _game_finished: bool = false


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

## WorldMap 二次重构 批 2：战斗会话编排器
## 由 MapBootstrap.init_world_subsystems() 末尾创建 + attach_sinks
## 设计：tile-advanture-design/WorldMap二次重构/批2_BattleCoordinator_MVP.md
var _battle_coordinator: BattleCoordinator = null

## WorldMap 二次重构 批 3：探索行动协调器
## 由 MapBootstrap.init_world_subsystems() 末尾创建 + attach_sinks（在 BC 之后）
## 设计：tile-advanture-design/WorldMap二次重构/批3_ExplorationCoordinator_MVP.md
var _exploration_coordinator: ExplorationCoordinator = null

## L1.1 阶段 2：视野循环 + chunk 三态机制（无限地图实装）
## 设计：tile-advanture-design/无限地图实装/L1.1_视野循环与chunk底座_MVP.md
## 由 MapBootstrap.init_world_subsystems() 创建 + setup（在协调器之前），
## EC.init_vision_runtime() 在 finalize_startup 末尾注册玩家 VisionSource
## 包裹叠加：本阶段子系统挂载就位但暂不接渲染/移动钩子（阶段 3+ 增量接入）
var _vision_system: VisionSystem = null
var _chunk_manager: ChunkManager = null
var _player_vision_source: VisionSource = null
## L1.3c 阶段 B：chunk 流式内容撒点（订阅 chunk_first_generated；
## 由 MapBootstrap._wire_content_spawner_internal 在 finalize_startup 内创建接线）
var _content_spawner: ContentSpawner = null
## L1.2 Phase 2：据点 + 占领 slot 视野绑定（纯事件驱动；随 reload 释放）
var _stronghold_vision_binding: StrongholdVisionBinding = null

## E 战斗就地展开 MVP：当前活跃战斗会话；null = 探索态，非 null = 战斗态
## 战斗态期间所有面板 / 输入需通过 _battle_coordinator.is_in_battle() 守卫拦截
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
## 信号接线：coma_respawn_triggered（L1.2 Phase 3 取代 coma_triggered）/ defeat_triggered / respawn_intro_ready
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
# L1.3c 阶段 C：改 static var（非 const）——entry_enemy_spawn realtime=true，增援 ring/cap 字段
# 经 EnemyReinforcement.SPAWN_CFG 实时读；本引用喂 init_from_config（troop_count 启动拷入 generator，
# 仍 init-once、改值需重启），保持 var preload 一致性以满足面板覆盖校验
static var ENEMY_SPAWN_PARAM_CFG: EnemySpawnParamResource = preload("res://assets/config/enemy_spawn_param_resource.tres")
const SCORE_PARAM_CFG: ScoreParamResource = preload("res://assets/config/score_param_resource.tres")

## 经济类数值参数（MVP-D D.2 批 3：迁自 quality_upgrade/build/level_reward/turn_reward/supply/inventory/difficulty_config.csv）
const QUALITY_UPGRADE_PARAM_CFG: QualityUpgradeParamResource = preload("res://assets/config/quality_upgrade_param_resource.tres")
const BUILD_PARAM_CFG: BuildParamResource = preload("res://assets/config/build_param_resource.tres")
const LEVEL_REWARD_PARAM_CFG: LevelRewardParamResource = preload("res://assets/config/level_reward_param_resource.tres")
const TURN_REWARD_PARAM_CFG: TurnRewardParamResource = preload("res://assets/config/turn_reward_param_resource.tres")
const SUPPLY_PARAM_CFG: SupplyParamResource = preload("res://assets/config/supply_param_resource.tres")
const INVENTORY_PARAM_CFG: InventoryParamResource = preload("res://assets/config/inventory_param_resource.tres")
const DIFFICULTY_PARAM_CFG: DifficultyParamResource = preload("res://assets/config/difficulty_param_resource.tres")

## L1.1 阶段 2：视野循环 + chunk 三态机制（无限地图实装）调参
## 设计：tile-advanture-design/无限地图实装/L1.1_视野循环与chunk底座_MVP.md §3.7
const VISION_CFG: VisionConfig = preload("res://assets/config/vision_config.tres")
# ─────────────────────────────────────────
# 生命周期
# ─────────────────────────────────────────

func _ready() -> void:
	# 阶段 a：配置加载（已抽离到 MapBootstrap，WorldMap二次重构 批1-a）
	# 详见 scripts/world/MapBootstrap.gd::load_configs
	# 后续阶段 b/c/d/e 会继续抽 cycle 应用 / 地图加载 / 世界状态 / 子系统实例化 / 启动末尾
	var bootstrap: MapBootstrap = MapBootstrap.new(self)
	bootstrap.load_configs()
	# 局部别名：让后续 _ready 代码访问 bootstrap 中间数据时书写不啰嗦
	# 后续阶段抽离时会逐步消除（如阶段 b 抽 _apply_cycle_config / _load_pcg 时 map_cfg / terrain_costs 别名一并消除）

	# 阶段 b：cycle 应用 + 起终点 + 地图加载 + schema 配置注入 + enemy_core 缓存（已抽离到 MapBootstrap，批1-b）
	# 详见 scripts/world/MapBootstrap.gd::load_map
	bootstrap.load_map()
	if _schema == null:
		push_error("WorldMap: 地图加载失败，无法渲染")
		return

	# 设置 Camera 边界限制（不超出地图像素范围）
	_setup_camera_limits()

	# 阶段 c：世界状态创建（_unit / _player_lifecycle / _turn_manager，已抽离到 MapBootstrap，批1-c）
	# 详见 scripts/world/MapBootstrap.gd::create_world_state
	bootstrap.create_world_state()

	# 阶段 d：子系统实例化（含建造/roster/Tick/Camera 杂项 + _init_subsystems 主体，已抽离到 MapBootstrap，批1-d）
	# 详见 scripts/world/MapBootstrap.gd::init_world_subsystems
	bootstrap.init_world_subsystems()

	# 阶段 e：启动末尾收口（_label_font / _deploy_initial / start_faction_turn / 揭幕，已抽离到 MapBootstrap，批1-e）
	# 详见 scripts/world/MapBootstrap.gd::finalize_startup
	bootstrap.finalize_startup()




## 场景退出时清理全局注册，避免 TickRegistry 残留悬空 Callable
## 重要性：TickRegistry._handlers 是 static，跨场景共享；不清理会在下次进入
## 场景时触发已释放的 handler 导致 Callable.is_valid() == false 被跳过，
## 看似无害但会堆积僵尸 handler
##
## M8 追加：VictoryJudge 同样走静态沉降 Callable，重开时必须 clear_sink
## 否则旧场景的 _on_victory_decided 会在新场景中被错误调用
func _exit_tree() -> void:
	# WorldMap 二次重构 批 3 阶段 f：_on_faction_tick 已迁到 EC，unregister 也跟着改 receiver
	if _exploration_coordinator != null:
		TickRegistry.unregister(_exploration_coordinator._on_faction_tick)
	TickRegistry.unregister(_on_build_tick)
	VictoryJudge.clear_sink()
	# L1.2 Phase 2：清 OccupationSystem owner 翻转 sink（静态类，reload 后旧 binding Callable 残留会悬空）
	OccupationSystem.clear_sink()
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
	if _game_finished or _is_moving or _manage_ui.is_open or _enemy_movement.is_moving() or _is_camping or _build_panel_ui.is_open or _event_panel.is_open or _player_lifecycle.is_in_coma():
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
			_exploration_coordinator.start_camp()

	# 回车键（视觉与操作改进 §2.3）：战斗中玩家回合 → 结束回合（带未移动守卫）
	# 放在通用锁守卫之后 + 显式 is_animating 守卫 → 动画期间 / 面板态不触发
	if event is InputEventKey:
		var key_enter: InputEventKey = event as InputEventKey
		if key_enter.pressed and not key_enter.echo \
				and (key_enter.keycode == KEY_ENTER or key_enter.keycode == KEY_KP_ENTER):
			if _battle_coordinator.is_in_battle() and _battle_session != null \
					and not _battle_session.is_ended() \
					and _battle_session.is_player_turn() \
					and not _battle_anim_director.is_animating():
				_battle_coordinator._on_battle_hud_end_turn_pressed()


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
	# WorldMap 二次重构 批 2 codex P1-1 修复：补动画守卫，与 L574 SHIFT+Enter 对齐
	# 防止 await 期间二次 skip（按钮路径已由 BattleAnimDirector.set_actions_enabled(false) 锁住，
	# 键盘路径不走按钮，原代码缺该守卫属批 2 前历史遗留）
	if _battle_coordinator.is_in_battle() and _battle_session != null \
			and not _battle_session.is_ended() \
			and _battle_session.is_player_turn() \
			and not _battle_anim_director.is_animating():
		_battle_coordinator._on_battle_hud_skip_pressed()
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


## 【L1.3b 阶段 B】当前相机视口覆盖的世界格矩形（渲染切 chunk 用）
## 用画布逆变换把视口四角映射到世界坐标取 AABB —— 自动正确处理相机
## 旋转（战斗 zoom 期 tilt）/ offset / zoom / 屏幕中心（codex P1 修：轴对齐估算会漏边角）。
## 复用本文件鼠标拾取同一变换（见 _process_input 的 (get_canvas_transform()*get_global_transform()).affine_inverse()）。
## 返回 Rect2i（position=左上格，size=宽高格数）；渲染层据此遍历视口而非全图 _schema。
## 相机/视口未就绪时回退 _schema 核心区范围（有限模式兜底）。
func get_visible_tile_rect(padding: int = 2) -> Rect2i:
	var viewport: Viewport = get_viewport()
	if _camera == null or viewport == null:
		var w: int = _schema.width if _schema != null else 0
		var h: int = _schema.height if _schema != null else 0
		return Rect2i(0, 0, w, h)
	# 屏幕像素 → 世界坐标 的逆变换（与鼠标拾取一致）
	var screen_to_world: Transform2D = (get_canvas_transform() * get_global_transform()).affine_inverse()
	var vp_size: Vector2 = viewport.get_visible_rect().size
	# 视口四角映射到世界坐标，取 AABB（旋转后四角范围 > 轴对齐 half）
	var c0: Vector2 = screen_to_world * Vector2(0, 0)
	var c1: Vector2 = screen_to_world * Vector2(vp_size.x, 0)
	var c2: Vector2 = screen_to_world * Vector2(0, vp_size.y)
	var c3: Vector2 = screen_to_world * Vector2(vp_size.x, vp_size.y)
	var min_w: Vector2 = c0.min(c1).min(c2).min(c3)
	var max_w: Vector2 = c0.max(c1).max(c2).max(c3)
	var min_tx: int = floori(min_w.x / TILE_SIZE) - padding
	var min_ty: int = floori(min_w.y / TILE_SIZE) - padding
	var max_tx: int = floori(max_w.x / TILE_SIZE) + padding
	var max_ty: int = floori(max_w.y / TILE_SIZE) + padding
	return Rect2i(min_tx, min_ty, max_tx - min_tx + 1, max_ty - min_ty + 1)

# ─────────────────────────────────────────
# 镜头控制
# ─────────────────────────────────────────

## 根据地图像素尺寸设置 Camera 边界
##
## L1.1 阶段 4（2026-05-28）：取消 limit_right/limit_bottom 硬绑 _schema 的约束
## 设计：tile-advanture-design/无限地图实装/L1.1_视野循环与chunk底座_MVP.md §10 阶段 4 议题 2 (2.1)
## 4 个 limit 全部设为 Godot Camera2D 默认极值（INT_MAX/MIN），camera 不再被 _schema 边界卡死
## 玩家滚动镜头到 _schema 外时，由 NightVisionLayer shader 兜底渲染黑色（议题 3 决议）
## 移动判定仍卡 _schema 边界（不在本函数范围内；玩法层包裹叠加原则）
func _setup_camera_limits() -> void:
	if _camera == null:
		return
	# Camera2D limit_* 默认值（Godot 4.6）：left/top = -10000000，right/bottom = 10000000
	# 显式设为这些值，让 camera 移动不被 _schema 边界约束（玩家移动判定仍卡边界）
	_camera.limit_left = -10000000
	_camera.limit_top = -10000000
	_camera.limit_right = 10000000
	_camera.limit_bottom = 10000000


## 战斗 Camera/zoom 三函数（start_battle_camera / end_battle_camera /
## _compute_battle_zoom_target）已迁出至 BattleCoordinator（批 2 阶段 b）
## 调用方改走 _battle_coordinator.start_battle_camera() / end_battle_camera()


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
	# 【L1.3b 阶段 C】负世界坐标必须用 floori 而非 int()/TILE_SIZE 截断：
	# int(-50)/72=0（向零截断）会把世界格 [-72,0) 误算成 0；floori(-50.0/72)=-1 正确。
	# 阶段 C 玩家可走到负坐标后此潜伏 bug 暴露（与 ChunkManager.tile_to_chunk 同因，那里早用 floori）
	var grid_x: int = floori(world_pos.x / TILE_SIZE)
	var grid_y: int = floori(world_pos.y / TILE_SIZE)
	var target: Vector2i = Vector2i(grid_x, grid_y)

	# E 战斗就地展开 MVP：战斗态点击分流
	# 战斗中不走探索态寻路移动；点击 → 攻击范围内敌方 = 攻击；可达格 = 移动；其他无响应
	if _battle_coordinator.is_in_battle():
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
	_exploration_coordinator.start_move_animation(path_result.path)


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

	var hit_unit: BattleUnit = _battle_coordinator._get_battle_unit_at_pos(grid_pos)

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
				_battle_coordinator._post_player_action_check()
		# 不在攻击范围内的敌方单位 → 静默（不当作"移动失败"提示）
		return

	# 优先级 2：点击可达格 → 移动
	var reachable: Array[Vector2i] = _battle_session.get_reachable_for_current()
	if reachable.has(grid_pos):
		if _battle_session.try_player_move(grid_pos):
			_battle_coordinator._post_player_action_check()
		return

	# 其他点击无响应（避免误操作直接结束当前单位）


## 玩家移动动画链 + 可达性（_start_move_animation / _on_move_step /
## _on_move_finished / _refresh_reachable）已迁出至 ExplorationCoordinator（批 3 阶段 a）
## 调用方改走 _exploration_coordinator.xxx —— 见上方字段声明

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

## 回合钩子（_on_faction_turn_started / _on_faction_tick）已迁出至
## ExplorationCoordinator（批 3 阶段 f）
## attach_sinks() 内接 TurnManager.faction_turn_started + TickRegistry.register


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


## 玩家占领 + 持久 slot 查询（_find_persistent_slot_at / try_player_occupy_at）
## 已迁出至 ExplorationCoordinator（批 3 阶段 b）
## 调用方改走 _exploration_coordinator.try_player_occupy_at()


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
	if _game_finished or _is_moving or _manage_ui.is_open or _is_camping or _event_panel.is_open or _player_lifecycle.is_in_coma() or _battle_coordinator.is_in_battle():
		return
	if not _build_upgrade_enabled:
		_show_notice("当前阶段不可手动升级")
		return
	_build_panel_ui.open(_exploration_coordinator.get_player_persistent_slots(), get_stone(Faction.PLAYER))


## 建造面板关闭回调
## 关闭不推进回合（和 ManageUI 非扎营模式同语义）
func _on_build_panel_closed() -> void:
	_update_hud()
	_exploration_coordinator.refresh_reachable()


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
		_build_panel_ui.refresh(_exploration_coordinator.get_player_persistent_slots(), get_stone(Faction.PLAYER))
	_renderer.queue_redraw()


## 持久 slot 查询（get_player/_enemy_persistent_slots / _get_persistent_slots_by_faction）
## 已迁出至 ExplorationCoordinator（批 3 阶段 b）
## 调用方改走 _exploration_coordinator.get_xxx_persistent_slots()


## 扎营 + 持久 slot 营收（start_camp / _settle_persistent_camp_production）已迁出至
## ExplorationCoordinator（批 3 阶段 c）
## 调用方改走 _exploration_coordinator.start_camp()


## 事件 helper（_build_reward_event / _push_battle_victory_event）已迁出至
## ExplorationCoordinator（批 3 阶段 f）
## 调用方改走 _exploration_coordinator._build_reward_event / push_battle_victory_event


## 资源采集 + 回合结算（try_collect_resource_at / _on_turn_end_settlement）已迁出至
## ExplorationCoordinator（批 3 阶段 d）
## 调用方改走 _exploration_coordinator.xxx —— EC 内 _on_move_finished 已 self 调


# ─────────────────────────────────────────
# 敌方 AI 协作接口（start_enemy_move_phase / _commit_enemy_move /
# _try_enemy_occupy_persistent_slot）已迁出至 ExplorationCoordinator（批 3 阶段 e）
# WorldView facade 3 处转发改 EC + fallback 兼容 _MockWorld
# ─────────────────────────────────────────


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

# ─────────────────────────────────────────
# 敌方移动信号处理（_on_enemy_phase_finished 已迁出至 BattleCoordinator 批 2 阶段 e）
# attach_sinks() 内接 EnemyMovement.phase_finished → BC._on_enemy_phase_finished
# ─────────────────────────────────────────

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
# 守卫语义：_battle_coordinator.is_in_battle() = true 期间锁定所有面板 / 输入分流；_battle_session sink 退出后清空


## 战斗查询工具（is_in_battle / get_packs_in_range / _is_pack_in_battle /
## _get_battle_unit_at_pos）已迁出至 BattleCoordinator（批 2 阶段 a）
## 调用方改走 _battle_coordinator.xxx —— 见上方字段声明


## 战斗会话启动 + 援军注入（start_battle_session / start_passive_battle /
## try_trigger_active_battle + 援军 4 个 helper）已迁出至 BattleCoordinator（批 2 阶段 c）
## 调用方改走 _battle_coordinator.xxx —— 见上方字段声明


## 战斗会话 sink + 结算 5 函数（_on_battle_redraw_requested / _bind_battle_session_sinks /
## _try_schedule_next_enemy_step / _sync_world_unit_from_battle_leader /
## _on_battle_session_ended）已迁出至 BattleCoordinator（批 2 阶段 d）
## attach_sinks() 内接 BattleAnimDirector.anims_drained → _try_schedule_next_enemy_step


## 战斗内推进（_post_player_action_check / _run_enemy_turn_async）已迁出至
## BattleCoordinator（批 2 阶段 e）
## 调用方改走 _battle_coordinator._xxx —— 见上方字段声明


## BattleHUD 4 sink + 守卫弹板（_on_battle_hud_attack_pressed / _skip_pressed /
## _end_turn_pressed / _exit_pressed + _show_end_turn_guard_dialog）已迁出至
## BattleCoordinator（批 2 阶段 f，批 2 收口）
## attach_sinks() 内接 BattleHUD 4 signal → BC._on_battle_hud_*


# ─────────────────────────────────────────
# 关卡 Slot 管理（M7 重构）
# ─────────────────────────────────────────
#
# M7 前：轮次切换时整批清理敌方关卡 + 整批生成新关卡
# M7 后：敌方生成走 EnemyReinforcement（初始预置 + 每 5 回合增援）；
#        击败的敌方部队包在 _on_battle_session_ended VICTORY 分支就地从 _level_slots 删除 + 恢复 schema slot
#
# 原 _clear_level_slots / _generate_level_slots / _get_tier_plan_for_round 已无调用方，M7 重构时删除


## Slot 生成（clear_onetime_resource_slots；generate_resource_slots 已退役删除）已迁出至
## ExplorationCoordinator（批 3 阶段 f）
## 当前无调用方（cycle 推进重设计时废弃），保留作 P3 候选

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

## 奖励工厂（_grant_troop_reward / _grant_level_rewards_for）已迁出至
## ExplorationCoordinator（批 3 阶段 f）
## 调用方改走 _exploration_coordinator.grant_xxx()

# ─────────────────────────────────────────
# 装配管理信号处理
# ─────────────────────────────────────────

## 打开装配管理面板（非扎营模式，仅允许替换）
func _open_manage_panel() -> void:
	# E MVP：战斗态守卫——_is_in_battle 期间不允许装配 / 用道具（设计 §2.10）
	if _game_finished or _is_moving or _is_camping or _event_panel.is_open or _player_lifecycle.is_in_coma() or _battle_coordinator.is_in_battle():
		return
	_manage_ui.open(_player_lifecycle.characters(), _inventory, false)

## 管理面板关闭回调
## 扎营模式下关闭面板 → 触发完整回合结算流程
func _on_manage_closed() -> void:
	_update_hud()
	if _is_camping:
		_is_camping = false
		_exploration_coordinator._on_turn_end_settlement()
	else:
		_exploration_coordinator.refresh_reachable()

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

## 扎营 helper（_resolve_camp_scenario / _entry_to_item_count）已迁出至
## ExplorationCoordinator（批 3 阶段 c 主会话补做 —— 设计文档漏列）
## 调用方改走 _exploration_coordinator._xxx（阶段 d/f 抽出后 EC 内 self 调）



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
# MVP-δ 阶段 2 / L1.2 Phase 3：PlayerLifecycle 信号 sink（coma_respawn_triggered /
# defeat_triggered / respawn_intro_ready 让 PlayerLifecycle 不直接依赖 UI 系统 / 持久 slot 表）
# ─────────────────────────────────────────

## 队长昏迷复活触发（PlayerLifecycle.coma_respawn_triggered sink）—— L1.2 Phase 3
##
## 设计：L1.2_多源视野与据点机制_MVP §2.3 / §5 改动 4·6
## 取代原 _on_player_coma_triggered 的 reload 范式：昏迷不重置地图，改为 OverlayTransitionUI 黑屏下原地传送。
##
## 三路（由 PlayerLifecycle.trigger_coma_or_lose 决策，本处只执行过渡 + 传送）：
##   - is_stronghold：简版黑屏（无火苗）+ 传送据点，midpoint 不扣命数
##   - 非 stronghold ：火苗黑屏（count = 当前命数）+ 传送 fallback，midpoint 调 consume_respawn_life 扣命数
##
## 关键时序（L1.3b Bug2 修复后）：midpoint 在 phase B 全黑期执行传送 + 相机吸附 + 延迟重绘，
## 并【返回 Signal】（hold 计时器）→ play 在全黑期 await 它，让落点视野在黑屏下刷新完再揭幕（消除闪烁）；
## 过渡播完后显式 clear_coma 解锁（传送路径不 reload，同一 PlayerLifecycle 实例不会自动清 _is_in_coma）
##
## 视图态副作用（_reachable_tiles / _pending_camp_manage_open / queue_redraw）与原 coma 一致清理
func _on_player_coma_respawn_triggered(target_pos: Vector2i, deduct_life: bool, is_stronghold: bool) -> void:
	_reachable_tiles = {}
	# codex review P1-5 修复（2026-05-10）：coma 触发即重置 flag
	# 防 EventPanel 在战斗中被 hide 而非 close → flag 永久 true → 下次 EventPanel close 误开 ManageUI
	_pending_camp_manage_open = false
	_renderer.queue_redraw()

	var coma_line: String = _player_lifecycle.format_coma_line(_player_lifecycle.current_leader_name())
	var lines: PackedStringArray
	var icon_data: Dictionary
	if is_stronghold:
		# 简版黑屏：无火苗（count=0），据点回归双句
		lines = PackedStringArray([coma_line, "回到了据点"])
		icon_data = {"icon": "🏰", "count": 0}
	else:
		# 无据点：火苗 count = 当前剩余命数（midpoint 扣减前读取，语义 = 复活后玩家总命数）
		lines = PackedStringArray([coma_line])
		icon_data = {"icon": "🔥", "count": RunState.respawns_left()}

	# 【L1.3b Bug2 修复】midpoint 返回 Signal → OverlayTransitionUI 在【全黑期】await 它（见 play Phase B）。
	# 利用这点把"传送 + 视野/相机就绪 + 强制重绘 + 等渲染落定"全部塞进黑屏内：
	# 非战斗态渲染器不每帧重绘，teleport 的 queue_redraw 需配 reset_smoothing 后的相机；
	# 黑屏下多 hold 一小段让 _draw 用新状态/吸附相机跑完，揭幕即正确 → 消除"黑屏结束→旧帧→刷新"的闪烁。
	var midpoint: Callable = func() -> Signal:
		if deduct_life:
			RunState.consume_respawn_life()
		_exploration_coordinator.teleport_party_to(target_pos)
		# 黑屏下延迟重绘：等相机 reset_smoothing 稳定（约 DELAY 秒）后再 queue_redraw，
		# 否则帧 0 重绘时相机变换未稳、视口偏 → 仍卡旧帧（与之前回退现象一致）
		get_tree().create_timer(_RESPAWN_REDRAW_DELAY_SEC).timeout.connect(
			_renderer.queue_redraw, CONNECT_ONE_SHOT)
		# 黑屏总 hold > DELAY，确保延迟重绘的 _draw 在揭幕前跑完
		return get_tree().create_timer(_RESPAWN_REDRAW_HOLD_SEC).timeout
	# play 内含 await（fade in → midpoint → 字幕 → fade out）；await 等整段过渡播完
	# codex P1-1 修复：play 被并发拒绝（已有过渡进行中）时不执行 midpoint → 复活逻辑被吞 → soft-lock。
	# 此时直接兜底执行 midpoint（无 fade；拒绝意味着已有别的过渡在覆盖屏幕，瞬移不可见），保证传送/扣命数落地。
	var accepted: bool = await OverlayTransitionUI.play(lines, icon_data, midpoint)
	if not accepted:
		# 并发拒绝兜底：midpoint 现返回 Signal（内含传送 + 延迟重绘 + hold）；直接 call 不 await
		# 会让重绘 hold 时序失效 → 仍可能露旧帧。取返回 Signal 并 await，保证落地后再解锁（codex P1）
		var ret: Variant = midpoint.call()
		if ret is Signal:
			await ret
	# 传送路径不 reload → 须显式解除昏迷锁
	_player_lifecycle.clear_coma()


## L1.2 Phase 3：昏迷复活目标解析（注入 PlayerLifecycle.register_coma_respawn_resolver）
##
## 返回 {has_stronghold, stronghold_pos, fallback_pos}：
##   - has_stronghold：RunState 已标记据点 + 据点 tile 上 slot 仍为 CORE_TOWN/PLAYER
##     （Phase 1 codex 修复：据点可被敌方攻占 → owner 翻 ENEMY，此时校验失败自动降级走 fallback）
##   - fallback_pos：最近的玩家占领持久 slot；一个都没有则 _start_pos（spawn 起点）
func _resolve_coma_respawn() -> Dictionary:
	var has_valid_stronghold: bool = false
	var stronghold_pos: Vector2i = Vector2i.ZERO
	if RunState.has_stronghold():
		stronghold_pos = RunState.stronghold_pos()
		var slot: PersistentSlot = _exploration_coordinator._find_persistent_slot_at(stronghold_pos)
		if slot != null and slot.type == PersistentSlot.Type.CORE_TOWN and slot.owner_faction == Faction.PLAYER:
			has_valid_stronghold = true
	return {
		"has_stronghold": has_valid_stronghold,
		"stronghold_pos": stronghold_pos,
		"fallback_pos": _resolve_nearest_occupied_or_spawn(),
	}


## L1.2 Phase 3：无据点 fallback 位置——最近的玩家占领持久 slot（曼哈顿距离），无则 spawn 起点
func _resolve_nearest_occupied_or_spawn() -> Vector2i:
	var best: Vector2i = _start_pos
	var best_dist: int = 0x7FFFFFFF
	for slot in _exploration_coordinator.get_player_persistent_slots():
		var d: int = absi(_unit.position.x - slot.position.x) + absi(_unit.position.y - slot.position.y)
		if d < best_dist:
			best_dist = d
			best = slot.position
	return best


## 末周期失败触发（PlayerLifecycle.defeat_triggered sink）
## 原 _trigger_coma_or_lose 内 _on_victory_decided(ENEMY_1) 直调迁过来
func _on_player_defeat_triggered(faction: int) -> void:
	_on_victory_decided(faction)


## 新场景启动重生文案就绪（PlayerLifecycle.respawn_intro_ready sink）
## 原 _init_player 内 OverlayTransitionUI.notify_world_ready 直调迁过来
func _on_player_respawn_intro_ready(respawn_line: String) -> void:
	OverlayTransitionUI.notify_world_ready(1, respawn_line)


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
	if _game_finished or _is_moving or _manage_ui.is_open or _is_camping or _build_panel_ui.is_open or _player_lifecycle.is_in_coma() or _battle_coordinator.is_in_battle():
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
			# ── L1.2 Phase 3 跑测便利：调试快捷键（仅 OS.is_debug_build()；release 编译不进入）──
			# Ctrl + 组合键构造昏迷/命数/占领/据点前置态，免去真实战斗。详见 _handle_debug_key
			if OS.is_debug_build() and key.ctrl_pressed:
				if _handle_debug_key(key.keycode):
					return
			# E MVP [F] 键独立处理：探索态触发主动战斗 / 战斗态尝试手动退出
			# 放在战斗态守卫之前，[F] 在两态语义不同
			if key.keycode == KEY_F:
				_handle_f_key()
				return
			# E MVP 战斗态：禁用 [M] / [B] / [Q] 等其他面板键
			# 战斗中不能装配 / 建造 / 放弃（设计 §2.10）
			if _battle_coordinator.is_in_battle():
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
	_exploration_coordinator.start_camp()


# ─────────────────────────────────────────
# L1.2 Phase 3 调试快捷键（仅 OS.is_debug_build()；release 不编入）
#
# 用途：构造昏迷复活各场景前置态，免去打输真实战斗。键位均用 Ctrl + 字母避免与 M/B/Q/F 冲突。
#   Ctrl+K 强制昏迷（场景 3/4/5/8/10 触发入口）
#   Ctrl+J 清空玩家占领 + 据点（场景 5：零占领 → spawn fallback）
#   Ctrl+L 耗尽命数到 0（场景 8：再 Ctrl+K → 末周期真失败）
#   Ctrl+H 敌方夺取据点（场景 10：据点失守 → 再 Ctrl+K → 自动降级）
#   Ctrl+P 强制周期胜利推进（场景 7：reload + 据点/占领跨周期 re-light）
#   Ctrl+U 传送到最近敌方关卡格（场景 9：验证"队伍与敌方同格"良性 —— 战斗仅 [F] 触发不自动）
# ─────────────────────────────────────────

## 调试键调度：命中返回 true（消费事件）。仅在干净探索态执行，避免在战斗/移动/面板态构造脏前置
func _handle_debug_key(keycode: int) -> bool:
	if _battle_coordinator.is_in_battle() or _is_moving or _is_camping or _manage_ui.is_open or _build_panel_ui.is_open:
		_show_notice("[调试] 请在干净探索态使用调试键")
		return true
	match keycode:
		KEY_K:
			_show_notice("[调试] 强制昏迷")
			_player_lifecycle.trigger_coma_or_lose()
			return true
		KEY_J:
			_debug_clear_occupation_and_stronghold()
			return true
		KEY_L:
			_debug_exhaust_lives()
			return true
		KEY_H:
			_debug_enemy_capture_stronghold()
			return true
		KEY_U:
			_debug_teleport_onto_enemy()
			return true
	return false


## 调试：清空所有玩家占领 + 据点格归属（构造场景 5 零占领态）
## 翻 owner→NONE 并经 binding 卸载视野源；据点格 owner→NONE 经 P1-3 修复后的 on_slot_owner_changed 注销据点源（无残留）
func _debug_clear_occupation_and_stronghold() -> void:
	var count: int = 0
	for slot in _exploration_coordinator.get_player_persistent_slots():
		slot.owner_faction = Faction.NONE
		if _stronghold_vision_binding != null:
			_stronghold_vision_binding.on_slot_owner_changed(slot)
		count += 1
	_exploration_coordinator.refresh_reachable()
	_renderer.queue_redraw()
	_show_notice("[调试] 清空 %d 个玩家占领（含据点格 owner）" % count)


## 调试：把命数推到 0（场景 8 前置）
func _debug_exhaust_lives() -> void:
	var n: int = 0
	while RunState.respawns_left() > 0:
		RunState.consume_respawn_life()
		n += 1
	_update_hud()
	_show_notice("[调试] 命数耗尽（推进 %d 周期，respawns_left=0）" % n)


## 调试：敌方夺取据点（场景 10 前置——据点 owner 翻 ENEMY，昏迷复活校验将失效自动降级）
##
## 必须走 OccupationSystem.try_occupy（与敌方真实占领同一路径），而非直接改 owner——
## try_occupy 内部触发 slot_owner_changed sink → StrongholdVisionBinding 注销据点视野源（P1-3）。
## 直接赋 owner 会绕过 sink 导致视野圈残留（codex P1-3 桌面验证暴露的调试键缺陷）。
## VictoryJudge.check_on_slot_owner_changed 对 owner→ENEMY 安全返回（仅玩家夺回 CORE_TOWN 才判定）。
func _debug_enemy_capture_stronghold() -> void:
	if not RunState.has_stronghold():
		_show_notice("[调试] 当前无据点，无法模拟失守")
		return
	var spos: Vector2i = RunState.stronghold_pos()
	var slot: PersistentSlot = _exploration_coordinator._find_persistent_slot_at(spos)
	if slot == null:
		_show_notice("[调试] 据点格无 slot（已遗失）")
		return
	if OccupationSystem.try_occupy(slot, Faction.ENEMY_1):
		_renderer.queue_redraw()
		_show_notice("[调试] 据点被敌方夺取（owner→ENEMY，视野撤除）；下次昏迷将自动降级走 fallback")
	else:
		_show_notice("[调试] try_occupy 拒绝（据点已非玩家方？）")


## 调试：传送队伍到最近敌方关卡格（场景 9 前置——构造"队伍与敌方同格"态）
##
## 验证目的：战斗仅 [F] 触发、从不自动，故此态应为良性——玩家可 [F] 应战或走开，
## 无设计场景 9 担忧的"瞬间触发战斗 → 连环 COMA"（该担忧基于"碰撞即战斗"的错误假设）。
func _debug_teleport_onto_enemy() -> void:
	var nearest: Vector2i = _unit.position
	var best_dist: int = 0x7FFFFFFF
	var found: bool = false
	for pos in _level_slots:
		var p: Vector2i = pos as Vector2i
		var lv: LevelSlot = _level_slots[p] as LevelSlot
		if lv == null or not lv.is_interactable():
			continue
		var d: int = absi(_unit.position.x - p.x) + absi(_unit.position.y - p.y)
		if d < best_dist:
			best_dist = d
			nearest = p
			found = true
	if not found:
		_show_notice("[调试] 地图上无可交互敌方关卡")
		return
	_exploration_coordinator.teleport_party_to(nearest)
	_show_notice("[调试] 传送到最近敌方关卡 %s；按 [F] 应战可验证无卡死/连环" % str(nearest))


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
	var candidates: Array[LevelSlot] = _battle_coordinator.get_packs_in_range(_unit.position, _battle_trigger_range)
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
	if _battle_coordinator.is_in_battle():
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
	# WorldMap 二次重构 批 2 codex P1-2 修复：补动画守卫，与 L574 SHIFT+Enter 对齐
	# 防止动画期间重复 attack（按钮路径已由 BattleAnimDirector.set_actions_enabled(false) 锁住，
	# 键盘路径不走按钮，原代码缺该守卫属批 2 前历史遗留）
	# 动画期间 F 键被战斗态吞掉（不走探索态分支），与按钮锁定语义对齐
	if _battle_coordinator.is_in_battle():
		if not _battle_anim_director.is_animating():
			_battle_coordinator._on_battle_hud_attack_pressed()
		return
	# 探索态：补给 / 候选 / 触发由 _try_trigger_active_battle 内部判定
	if _game_finished or _player_lifecycle.is_in_coma() or _is_moving or _manage_ui.is_open or _is_camping or _build_panel_ui.is_open:
		return
	if _enemy_movement != null and _enemy_movement.is_moving():
		return
	if _turn_manager != null and _turn_manager.current_faction != Faction.PLAYER:
		return
	_battle_coordinator.try_trigger_active_battle()

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

