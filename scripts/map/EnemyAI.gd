class_name EnemyAI
extends Node
## 敌方 AI 决策器（M7）
##
## 设计原文：
##   tile-advanture-design/城建锚实装/M7_敌方AI.md
##   tile-advanture-design/敌方AI基础行为设计.md §二 目标 / §三 来源 / §五 移动 / §六 占据升级 / §七 回合流程 / §八 石料经济
##
## 职责：
##   六步敌方回合编排——
##     步骤 1 由 TickRegistry 自动执行（建造 tick / REPELLED 冷却），本类**不重复调用**
##     步骤 2 增援判定：委托 EnemyReinforcement.spawn_batch
##     步骤 3 石料入账：调用 WorldMap.add_stone(ENEMY_1, stone_per_turn)
##     步骤 4 贪心升级：候选 slot 排序（城镇 > 村庄 / 同类低级先）+ 调 BuildSystem.start_upgrade
##     步骤 5 移动阶段：委托 EnemyMovement 执行动画（target = 玩家核心位置）
##   移动阶段结束后触发 "end_faction_turn(ENEMY_1) → start_faction_turn(PLAYER)" 回到玩家
##
## 解耦方式：
##   作为 Node 挂在 WorldMap 下，通过 init(world_map) 注入 WorldMap 引用
##   选择 Node 风格（vs 静态类）的原因：需要连接 TurnManager 信号 + 持有对 EnemyMovement / WorldMap 的直接引用
##   配置类数据（stone_per_turn / reinforcement_interval）从 build_config.csv 读取
##
## MVP 边界：
##   - 敌方 AI 只对 ENEMY_1 势力生效；多敌方扩展按 Faction.ENEMY_N 顺延
##   - target = 玩家核心位置（`type == CORE_TOWN && owner_faction == PLAYER`）；无玩家核心时跳过移动阶段
##   - 升级决策仅考虑石料；不考虑战略位置（§7 MVP 简化）


## 每敌方回合石料入账（配置化，默认 3，见敌方 AI 设计 §8.2）
var stone_per_turn: int = 3

## 增援间隔（敌方回合数，默认 5，见 §3.2）
var reinforcement_interval: int = 5

## WorldMap 宿主引用（init 时注入）
## 类型为 Node 便于测试注入 mock；访问时用属性/方法直接访问替代 .get("...") 字符串
## （重命名字段时运行时错误明显，比 .get() 字符串 typo 更易排查 —— P2 审查项）
var _world_map: Node = null


# ─────────────────────────────────────────
# 初始化
# ─────────────────────────────────────────

## 注入 WorldMap 引用并连接信号
## 调用方：WorldMap._init_subsystems
func init(world_map: Node, turn_manager: TurnManager) -> void:
	_world_map = world_map
	turn_manager.faction_turn_started.connect(_on_faction_turn_started)


## 从 build_config.csv 加载数值（可选，不传则用默认值）
func load_config(build_cfg: Dictionary) -> void:
	stone_per_turn = int(build_cfg.get("enemy_stone_per_turn", str(stone_per_turn)))
	reinforcement_interval = int(build_cfg.get("enemy_reinforcement_interval", str(reinforcement_interval)))


# ─────────────────────────────────────────
# 敌方回合入口
# ─────────────────────────────────────────

## 监听 TurnManager.faction_turn_started 信号
## 只处理 ENEMY_1；PLAYER 信号由 WorldMap 自己的 handler 处理
func _on_faction_turn_started(faction: int) -> void:
	if faction != Faction.ENEMY_1:
		return
	# 步骤 1：TickRegistry 已由 start_faction_turn 先行触发（建造 tick + REPELLED 冷却 tick）
	# 本处直接进入步骤 2-5
	_step_reinforcement()
	_step_stone_income()
	_step_greedy_upgrade()
	_step_move_phase()


# ─────────────────────────────────────────
# 步骤 2：增援判定
# ─────────────────────────────────────────

## 每 reinforcement_interval 个敌方回合生成 1 批增援
## turn_index 从 TurnManager.enemy_faction_turn_count 读；注意 start_faction_turn 在触发信号前已 +1，
## 故此处读到的是"本回合计数"（首个敌方回合 = 1）
func _step_reinforcement() -> void:
	if _world_map == null or _world_map._turn_manager == null:
		return
	var count: int = _world_map._turn_manager.enemy_faction_turn_count
	if count > 0 and count % reinforcement_interval == 0:
		EnemyReinforcement.spawn_batch(_world_map)


# ─────────────────────────────────────────
# 步骤 3：石料入账
# ─────────────────────────────────────────

## 敌方全局石料库存定量入账（§8 MVP 绕过产出体系）
func _step_stone_income() -> void:
	if _world_map == null:
		return
	_world_map.add_stone(Faction.ENEMY_1, stone_per_turn)


# ─────────────────────────────────────────
# 步骤 4：贪心升级
# ─────────────────────────────────────────

## 按"城镇优先 > 同类等级低先"排序候选 slot，石料足即启动升级
## 同一回合最多对每个 slot 启动 1 次升级（BuildSystem 内部靠 active_build 防止重复）
func _step_greedy_upgrade() -> void:
	if _world_map == null or _world_map._schema == null:
		return
	var persistent_slots: Array = _world_map._schema.persistent_slots

	# 收集归属于 ENEMY_1 且可升级的 slot
	var candidates: Array[PersistentSlot] = []
	for entry in persistent_slots:
		var slot: PersistentSlot = entry as PersistentSlot
		if slot == null:
			continue
		if slot.owner_faction != Faction.ENEMY_1:
			continue
		if not BuildSystem.can_upgrade(slot, Faction.ENEMY_1):
			continue
		candidates.append(slot)

	# 排序：城镇优先（type=TOWN > VILLAGE；CORE_TOWN L3 is_at_cap 已过滤，不会进入）
	#       同类内等级低先
	candidates.sort_custom(_upgrade_priority_cmp)

	# 依次尝试启动升级，石料不足停止
	for slot in candidates:
		var cost: int = BuildSystem.get_upgrade_cost(slot)
		if cost <= 0:
			continue
		var paid: bool = _world_map.try_spend_stone(Faction.ENEMY_1, cost)
		if not paid:
			break    # 石料不足，后续同样会失败，直接 break 节省开销
		BuildSystem.start_upgrade(slot, Faction.ENEMY_1)


## 升级优先级比较：true = a 优先于 b
## 一级：城镇（TOWN=1）> 村庄（VILLAGE=0）  —— 注意枚举值恰好 TOWN > VILLAGE
## 二级：同类内 level 低优先（尽早起步效果大）
func _upgrade_priority_cmp(a: PersistentSlot, b: PersistentSlot) -> bool:
	if a.type != b.type:
		return int(a.type) > int(b.type)
	return a.level < b.level


# ─────────────────────────────────────────
# 步骤 5：移动阶段
# ─────────────────────────────────────────

## 委托 EnemyMovement 执行移动动画
## target = 玩家核心 persistent slot 的位置；无玩家核心则跳过
## 移动结束后由 EnemyMovement.phase_finished 信号 → WorldMap._on_enemy_phase_finished 接续阵营切换
func _step_move_phase() -> void:
	if _world_map == null:
		return
	_world_map.start_enemy_move_phase()
