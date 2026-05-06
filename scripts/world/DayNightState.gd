class_name DayNightState
extends RefCounted
## 昼夜状态查询 / 信号包装（D MVP）
##
## 设计原文：
##   tile-advanture-design/探索体验实装/D_昼夜状态占位_MVP.md
##
## 职责：
##   - 把"玩家阵营回合 / 敌方阵营回合"重新命名为"白天 / 夜晚"
##   - 不引入新状态机：所有查询都以 TurnManager.current_faction 为唯一真相源
##   - 提供 phase_changed sink 让未来 MVP（视野限制 / 夜晚事件 / 美术滤镜）挂接
##
## 架构选择（与 VictoryJudge 对齐）：
##   静态类 + Callable 沉降回调
##   - 避免 Autoload 污染 project.godot
##   - 对 headless 测试友好
##   - WorldMap._init_subsystems 调 attach_to_turn_manager 一次
##   - WorldMap._exit_tree 调 clear_sinks 清回调（含 listener 解绑标记）
##
## 阵营 → 阶段映射（设计文档 §2）：
##   Faction.PLAYER  → DAY（白天，玩家自由探索）
##   Faction.ENEMY_1 → NIGHT（夜晚，敌方移动 + 强制战斗）
##
## phase override（用户跑测 2026-05-06 反馈引入）：
##   设计文档原意是"以 current_faction 为唯一真相源"，但扎营按下瞬间就应该进入夜晚（玩家心智：扎营即入夜），
##   而 current_faction 真正切到 ENEMY_1 要等 ManageUI 关闭 + _on_turn_end_settlement。
##   引入 override：_start_camp 主动设 NIGHT，新 PLAYER 回合开始时自动清，弥补这段语义空窗。


## 阶段枚举
enum Phase { DAY = 0, NIGHT = 1 }

## 无 override 标记（int 而非 Phase 是因为 Phase 没有"未设置"枚举值）
const _NO_OVERRIDE: int = -1


# ─────────────────────────────────────
# 状态（静态）
# ─────────────────────────────────────

## 阶段切换回调；签名 func(phase: Phase) -> void
## MVP 单 sink，与 VictoryJudge 同模式；如未来需要多订阅者可扩展为 Array[Callable]
static var _phase_changed_sink: Callable = Callable()

## 已挂接的 TurnManager 弱引用 —— 防止 attach 重复连接同一信号
## 用普通 var 持有；reload_current_scene 时 _exit_tree → clear_sinks 释放
static var _attached_turn_manager: TurnManager = null

## phase 强制覆盖；_NO_OVERRIDE 表示无覆盖，按 current_faction 推断
## 扎营场景由 _start_camp 设为 NIGHT，PLAYER 回合开始时自动清
static var _phase_override: int = _NO_OVERRIDE


# ─────────────────────────────────────
# 状态查询接口
# ─────────────────────────────────────

## 当前阶段
## 优先级：override > current_faction 推断
## ENEMY_1 = 夜晚；其他（PLAYER 等）= 白天
## NONE / 未知 faction 默认归白天，避免空状态时显示夜晚滤镜
static func current(turn_manager: TurnManager) -> Phase:
	if _phase_override != _NO_OVERRIDE:
		return _phase_override as Phase
	return _faction_to_phase(turn_manager.current_faction if turn_manager != null else Faction.PLAYER)


## faction → phase 推断（私有 helper，复用于 current / 信号处理）
static func _faction_to_phase(faction: int) -> Phase:
	if faction == Faction.ENEMY_1:
		return Phase.NIGHT
	return Phase.DAY


## 白天判定快捷方式
static func is_day(turn_manager: TurnManager) -> bool:
	return current(turn_manager) == Phase.DAY


## 夜晚判定快捷方式（视觉滤镜 / 未来视野限制等通过此查询）
static func is_night(turn_manager: TurnManager) -> bool:
	return current(turn_manager) == Phase.NIGHT


# ─────────────────────────────────────
# 信号挂接 / 沉降回调
# ─────────────────────────────────────

## 把 TurnManager.faction_turn_started 信号包装为 phase_changed
## 在 WorldMap._init_subsystems 调用一次；重复调用时检查并解绑旧 listener
## 避免 reload_current_scene 后旧 turn_manager 被 free 但 connect 残留
static func attach_to_turn_manager(turn_manager: TurnManager) -> void:
	if turn_manager == null:
		push_warning("DayNightState.attach_to_turn_manager: turn_manager 为 null")
		return
	# 同一 turn_manager 重复挂接 → 跳过（防御性）
	if _attached_turn_manager == turn_manager:
		return
	# 不同 turn_manager（场景重载等）→ 解绑旧的，挂新的
	if _attached_turn_manager != null and is_instance_valid(_attached_turn_manager):
		if _attached_turn_manager.faction_turn_started.is_connected(_on_faction_turn_started):
			_attached_turn_manager.faction_turn_started.disconnect(_on_faction_turn_started)
	_attached_turn_manager = turn_manager
	turn_manager.faction_turn_started.connect(_on_faction_turn_started)


## 注册阶段切换回调
## 多次调用以最后一次为准；sink 签名 func(phase: Phase) -> void
static func register_phase_changed_sink(sink: Callable) -> void:
	_phase_changed_sink = sink


## 主动设置 phase override（用户跑测反馈引入）
## 用例：_start_camp 按下瞬间设 NIGHT，让滤镜立即生效
## 同值不重复触发 sink，避免 redraw 抖动
static func set_phase_override(phase: Phase) -> void:
	if _phase_override == int(phase):
		return
	_phase_override = int(phase)
	if _phase_changed_sink.is_valid():
		_phase_changed_sink.call(phase)


## 清除 phase override，回到 current_faction 推断
## 通常由 _on_faction_turn_started 切到 PLAYER 时自动调用，无需 WorldMap 显式清
static func clear_phase_override() -> void:
	if _phase_override == _NO_OVERRIDE:
		return
	_phase_override = _NO_OVERRIDE
	# 触发一次 sink 让订阅者按当前 faction 重算（可能从 NIGHT 切到 DAY）
	if _phase_changed_sink.is_valid() and _attached_turn_manager != null:
		_phase_changed_sink.call(_faction_to_phase(_attached_turn_manager.current_faction))


## 清理 sink + 解绑 TurnManager listener + 复位 override
## 场景 _exit_tree 时调用，避免跨场景悬空 Callable / 残留 connect
static func clear_sinks() -> void:
	_phase_changed_sink = Callable()
	_phase_override = _NO_OVERRIDE
	if _attached_turn_manager != null and is_instance_valid(_attached_turn_manager):
		if _attached_turn_manager.faction_turn_started.is_connected(_on_faction_turn_started):
			_attached_turn_manager.faction_turn_started.disconnect(_on_faction_turn_started)
	_attached_turn_manager = null


# ─────────────────────────────────────
# 内部
# ─────────────────────────────────────

## TurnManager.faction_turn_started 信号回调 → 转发给 phase_changed sink
## 切到 PLAYER 时自动清 override（夜晚结束）
## faction != ENEMY_1 一律视为白天（PLAYER 是显式白天；其他保留为白天默认）
static func _on_faction_turn_started(faction: int) -> void:
	# PLAYER 回合到来 = 夜晚结束 → 清 override；其他切换不动 override
	if faction == Faction.PLAYER and _phase_override != _NO_OVERRIDE:
		_phase_override = _NO_OVERRIDE
	if not _phase_changed_sink.is_valid():
		return
	# 计算分发的 phase：override 仍生效则按 override，否则按 faction 推断
	var phase: Phase = (_phase_override as Phase) if _phase_override != _NO_OVERRIDE else _faction_to_phase(faction)
	_phase_changed_sink.call(phase)


# ─────────────────────────────────────
# 视野限制接口（D MVP §2 stub）
# ─────────────────────────────────────

## 视野限制 stub —— D MVP 不实装，仅保留接口
## 返回值：玩家可见格集合 {Vector2i: bool}；is_night 时调用方应裁剪渲染
## 落地时机：用户希望让"夜晚视野收缩"成为玩法变量时再展开（设计文档 §2 P2 待跟踪）
static func get_visible_tiles(turn_manager: TurnManager, player_pos: Vector2i, schema: MapSchema) -> Dictionary:
	push_warning("DayNightState.get_visible_tiles: 视野限制接口未实装")
	# 参数显式 _ 标记未使用，避免 LSP 警告
	var _tm: TurnManager = turn_manager
	var _pp: Vector2i = player_pos
	var _sc: MapSchema = schema
	return {}
