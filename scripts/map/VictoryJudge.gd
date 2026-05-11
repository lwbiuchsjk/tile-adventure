class_name VictoryJudge
extends RefCounted
## 胜负判定系统（M8 + P0 X-A 阵营过滤 + P0 第二阶段 cycle 过滤 + 兜底胜利）
##
## 设计原文：
##   tile-advanture-design/整局节奏重设计_MVP.md（P0 第二阶段，2026-05-11 定调）
##   tile-advanture-design/胜负条件重设计_MVP.md（P0 第一阶段，2026-05-08）
##   tile-advanture-design/城建锚实装/M8_胜负与最小验证.md（旧）
##   tile-advanture-design/持久slot基础功能设计.md §七（旧）
##
## 规则（P0 第二阶段后）：
##   主胜利路径：仅末周期 + 玩家攻占敌方核心城镇 → 玩家胜利
##     （前两周期玩家可占领 CORE_TOWN 但不触发胜利——cycle 过滤拦截；视觉上 CORE_TOWN 仅末周期激活）
##   兜底胜利路径：所有周期 + 地图上 owner=ENEMY_1 的 pack 数 = 0 → 玩家胜利
##     （reinforcement 离散 spawn 让通常不可达；玩家"消灭速度 > spawn 速度"时触发）
##   失败侧不由 VictoryJudge 触发——失败仅由「队长命数耗尽」走 _trigger_coma_or_lose 末周期分支
##
## 架构选择：
##   静态类 + Callable 沉降回调（对齐 TickRegistry 模式）
##   - 避免 Autoload 污染 project.godot
##   - 对 headless 测试友好（无需 SceneTree 即可触发）
##   - WorldMap._ready 注册 sink，_exit_tree 清理
##
## 触发链：
##   OccupationSystem.try_occupy 翻转成功 → check_on_slot_owner_changed(slot)
##   → 若 slot 是 CORE_TOWN + 新归属是 PLAYER + 本局未判定 → 调用 _sink(PLAYER)
##   → WorldMap._on_victory_decided 挂载胜利遮罩 UI


## 胜负回调 Callable(winner_faction: int) -> void
## WorldMap._ready 注入；reload_current_scene 后新的 _ready 会重新注册
static var _sink: Callable = Callable()

## 本局已判定标记：避免同一局内重复触发（如先触发失败信号后其他翻转再触发）
## MVP 约定：一局游戏只允许触发一次胜负
static var _finished: bool = false


## 注册胜负回调
## 多次调用以最后一次为准；sink 签名 func(winner_faction: int) -> void
static func register_sink(sink: Callable) -> void:
	_sink = sink


## 清理全部状态（回调 + 已判定标记）
## 场景 _exit_tree 时调用，避免跨场景残留悬空 Callable
static func clear_sink() -> void:
	_sink = Callable()
	_finished = false


## 仅重置"已判定"标记，保留 sink
## 调试 / 热重载场景使用；MVP 重开走 reload_current_scene 不需要这个
static func reset_state() -> void:
	_finished = false


## 查询本局是否已判定（供 WorldMap 防御查询）
static func is_finished() -> bool:
	return _finished


## 核心城镇归属变更时调用
## 参数 slot.owner_faction 必须为翻转后的新归属（由 OccupationSystem.try_occupy 保证）
##
## P0 X-A 阵营过滤：仅玩家占据敌方核心触发胜利
## P0 第二阶段 cycle 过滤：仅末周期触发主胜利路径
##   前两周期玩家也可占领 CORE_TOWN（视觉上是普通 TOWN），但 cycle 过滤拦截不触发胜利
##
## Sink 有效性检查在 _finished 置位之前（审查 P1 修复）：
##   若 sink 无效（未注册 / 目标被 free 后未 clear_sink），旧实现会"先封盘再失败分发"，
##   导致本局永不再触发胜负 UI；修复后留出恢复机会（修复 sink 后下一次翻转可正常触发）。
##   同时 push_error 暴露该异常态，便于排障
static func check_on_slot_owner_changed(slot: PersistentSlot) -> void:
	if slot == null:
		return
	if slot.type != PersistentSlot.Type.CORE_TOWN:
		return
	# P0 X-A 阵营过滤：仅玩家占据敌方核心触发胜利
	if slot.owner_faction != Faction.PLAYER:
		return
	# P0 第二阶段 cycle 过滤：仅末周期触发主胜利
	# 前两周期 CORE_TOWN 视觉未激活；玩家占领该 slot 不构成"决战胜利"
	if not RunState.is_last_cycle():
		return
	if _finished:
		return
	if not _sink.is_valid():
		push_error("VictoryJudge.check_on_slot_owner_changed: sink 未注册或已失效，胜利事件未分发")
		return
	_finished = true
	_sink.call(Faction.PLAYER)


## P0 第二阶段：兜底胜利监听 —— 地图上 owner=ENEMY_1 的 pack 数 = 0 → 玩家胜利
##
## 触发时机（WorldMap 调用）：
##   - BattleSession.end(WIN) 后（敌方 pack 被消灭路径）
##   - OccupationSystem.try_occupy 翻转敌方 pack 后（如有此路径；当前 MVP pack 不可被占领，仅消灭）
##
## 判定逻辑：
##   遍历 _level_slots，统计 faction == ENEMY_1 的 pack 数；为 0 即触发胜利
##   reinforcement 离散 spawn（每 reinforcement_interval 敌方回合 spawn 1 个）
##   → 通常玩家清场速度跟不上 spawn，兜底不可达；小概率达成时功能正常
##
## 与主胜利路径关系：
##   主胜利仅末周期触发；兜底所有周期生效——前两周期理论上也可通过兜底胜利
##   两条路径共享 _finished 标志：任一触发即封盘
static func check_enemy_packs_clear(level_slots: Dictionary) -> void:
	if _finished:
		return
	if not _sink.is_valid():
		# 注：本路径不 push_error——sink 失效时主胜利路径会报错，此处避免重复噪音
		return
	var enemy_count: int = 0
	for entry in level_slots.values():
		var pack: LevelSlot = entry as LevelSlot
		if pack != null and pack.faction == Faction.ENEMY_1:
			enemy_count += 1
	if enemy_count > 0:
		return
	_finished = true
	_sink.call(Faction.PLAYER)
