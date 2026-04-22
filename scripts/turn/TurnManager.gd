class_name TurnManager
extends RefCounted
## 回合管理器
##
## ⚠ M3 重构（2026-04-22）：本类承载两套并存接口，请勿混用：
##   1. 旧"流程性回合计数"接口（保留，WorldMap 仍在用）：
##      - current_turn / register_unit / end_turn() / signal turn_ended(int)
##      - 语义：玩家手动按一次"结束回合"按钮 → current_turn += 1 → 重置移动力 → emit
##      - 这套接口与"阵营"无关，纯粹是玩家侧节奏计数
##   2. 新"阵营回合 + Tick"接口（M3 新增，M5/M7 等下游接入用）：
##      - current_faction / start_faction_turn / end_faction_turn
##      - signal faction_turn_started(faction) / faction_turn_ended(faction)
##      - 语义：双方阵营各占一个回合；start 内部先 TickRegistry.run_ticks 后 emit
##      - 这套接口与 TickRegistry 配合，作为后续所有倒计时类系统的统一挂点
##
## 与 RoundManager 的关系：
##   RoundManager 管理"轮次 = 多关卡"语义，与"阵营回合"正交，不冲突。
##   一个完整大回合 = 玩家阵营 1 轮 + 敌方阵营 1 轮；轮次跨越多个大回合。

# ─────────────────────────────────────────
# 旧"流程性回合计数"接口（保留）
# ─────────────────────────────────────────

## 回合结束信号（旧），参数为新的回合编号
signal turn_ended(turn_number: int)

## 当前回合编号（从 0 开始，首次 end_turn 后变为 1）
var current_turn: int = 0

## 已注册的单位列表（旧接口：tick 时统一重置移动力）
var _units: Array = []

## 注册单位到回合管理器，tick 时会重置其移动力
func register_unit(unit: UnitData) -> void:
	_units.append(unit)


## 结束当前回合，执行 tick 后推进回合计数（旧接口；不联动新阵营回合流程）
func end_turn() -> void:
	current_turn += 1
	_tick()
	turn_ended.emit(current_turn)


## 回合 tick：执行所有回合结算逻辑（旧）
## 扩展点：后续在此处追加资源结算、野怪刷新等逻辑
func _tick() -> void:
	# 重置所有注册单位的移动力
	for entry in _units:
		var unit: UnitData = entry as UnitData
		unit.current_movement = unit.max_movement


# ─────────────────────────────────────────
# 新"阵营回合 + Tick"接口（M3）
# ─────────────────────────────────────────

## 阵营回合开始信号（新），参数为本回合归属阵营
signal faction_turn_started(faction: int)

## 阵营回合结束信号（新），参数为刚结束的阵营
signal faction_turn_ended(faction: int)

## 当前活动阵营（默认从玩家方开始）
var current_faction: int = Faction.PLAYER

## 玩家阵营累计回合数（新接口独立计数，与 current_turn 不冲突）
var player_faction_turn_count: int = 0

## 敌方阵营累计回合数
var enemy_faction_turn_count: int = 0


## 启动指定阵营的回合
## 流程严格按 M3 §交付物：先 TickRegistry.run_ticks(faction)，后 emit faction_turn_started
## 调用方应保证不在 tick handler 内部递归调用本方法
func start_faction_turn(faction: int) -> void:
	current_faction = faction
	# 1. 优先执行所有 tick（建造 / 影响范围 / 冷却 ...）
	TickRegistry.run_ticks(faction)
	# 2. 计数推进
	if faction == Faction.PLAYER:
		player_faction_turn_count += 1
	elif faction == Faction.ENEMY_1:
		enemy_faction_turn_count += 1
	# 3. 信号广播
	faction_turn_started.emit(faction)


## 结束当前阵营回合（仅 emit 信号；不自动切换到对方）
## 切换由调用方决定：通常下一句紧跟 start_faction_turn(对方)
## 设计动机：M3 阶段不实装敌方 AI 流程；M7 接入时由 WorldMap / 战斗调度统一编排
func end_faction_turn() -> void:
	faction_turn_ended.emit(current_faction)


## 工具方法：返回与 current_faction 对立的阵营
## MVP 两方对峙时直接二元切换；扩展到 N 方时应改用势力顺序表
func get_opposite_faction() -> int:
	if current_faction == Faction.PLAYER:
		return Faction.ENEMY_1
	return Faction.PLAYER
