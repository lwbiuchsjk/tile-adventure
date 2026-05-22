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
## 规则（L1.3 周期胜利目标 MVP 后）：
##   两条胜利路径（占据敌方核心 / 消灭所有敌包）统一交 _dispatch_victory，按 is_last_cycle 分两个出口：
##     末周期   → 真正通关（_sink → WorldMap._on_victory_decided → VictoryUI），_finished 一局一次
##     非末周期 → 周期推进（_cycle_victory_sink → 黑屏过渡 + reload + 保留队长），_cycle_advancing 防重入
##   （L1.3 后全周期开放敌方核心 has_enemy_core；is_last_cycle 由原「硬拦截非末周期」改为「分流开关」）
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

## 周期推进出口回调（L1.3 周期胜利目标 MVP）：非末周期占据核心 / 清场时调
## 签名 func() -> void；WorldMap._on_cycle_victory_triggered 接，构造黑屏过渡 + reload
static var _cycle_victory_sink: Callable = Callable()

## 周期推进防同帧重入守卫（L1.3）：触发推进到 reload 完成之间拦截重复触发
## 不复用 _finished——周期推进非"胜负判定"，reload 后 clear_sink 自然清
static var _cycle_advancing: bool = false


## 注册胜负回调
## 多次调用以最后一次为准；sink 签名 func(winner_faction: int) -> void
static func register_sink(sink: Callable) -> void:
	_sink = sink


## 注册周期推进回调（L1.3）；多次调用以最后一次为准；sink 签名 func() -> void
static func register_cycle_victory_sink(sink: Callable) -> void:
	_cycle_victory_sink = sink


## 清理全部状态（回调 + 已判定标记）
## 场景 _exit_tree 时调用，避免跨场景残留悬空 Callable
static func clear_sink() -> void:
	_sink = Callable()
	_finished = false
	# L1.3：周期推进出口 + 守卫一并清理，保证 reload 后干净重注册
	_cycle_victory_sink = Callable()
	_cycle_advancing = false


## 仅重置"已判定"标记，保留 sink
## 调试 / 热重载场景使用；MVP 重开走 reload_current_scene 不需要这个
static func reset_state() -> void:
	_finished = false
	_cycle_advancing = false


## 查询本局是否已判定（供 WorldMap 防御查询）
static func is_finished() -> bool:
	return _finished


## 核心城镇归属变更时调用
## 参数 slot.owner_faction 必须为翻转后的新归属（由 OccupationSystem.try_occupy 保证）
##
## P0 X-A 阵营过滤：仅玩家占据敌方核心触发
## L1.3 周期胜利目标 MVP：is_last_cycle 从「硬拦截」改为「分流开关」——
##   仅保留 slot 过滤（CORE_TOWN + owner=PLAYER），分流逻辑统一交给 _dispatch_victory
##   非末周期 → 周期推进（黑屏过渡）；末周期 → 真正通关（VictoryUI）
static func check_on_slot_owner_changed(slot: PersistentSlot) -> void:
	if slot == null:
		return
	if slot.type != PersistentSlot.Type.CORE_TOWN:
		return
	# P0 X-A 阵营过滤：仅玩家占据敌方核心触发
	if slot.owner_faction != Faction.PLAYER:
		return
	_dispatch_victory()


## 统一胜利分流（L1.3 周期胜利目标 MVP）：占据敌方核心 / 消灭所有敌包 两条路径都调它
## 按 is_last_cycle 决定出口：
##   末周期   → 真正通关（_sink → WorldMap._on_victory_decided → VictoryUI），置 _finished 一局一次
##   非末周期 → 周期推进（_cycle_victory_sink → 黑屏过渡 + reload），置 _cycle_advancing 防同帧重入
##
## Sink 有效性检查在标记置位之前（对齐原 P1 修复语义）：sink 无效时不封盘，留恢复机会 + push_error 排障
static func _dispatch_victory() -> void:
	if RunState.is_last_cycle():
		if _finished:
			return
		if not _sink.is_valid():
			push_error("VictoryJudge._dispatch_victory: 通关 sink 未注册或已失效，胜利事件未分发")
			return
		_finished = true
		_sink.call(Faction.PLAYER)
	else:
		if _cycle_advancing:
			return
		if not _cycle_victory_sink.is_valid():
			push_error("VictoryJudge._dispatch_victory: 周期推进 sink 未注册或已失效，周期推进未分发")
			return
		_cycle_advancing = true
		_cycle_victory_sink.call()


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
## L1.3：与占据核心路径统一——清场统计后交 _dispatch_victory 分流
##   非末周期清场 → 周期推进（不再误判为通关，消除"周期 0 清场=通关 vs 攻克核心=推进"语义矛盾）
##   末周期清场   → 真正通关
static func check_enemy_packs_clear(level_slots: Dictionary) -> void:
	var enemy_count: int = 0
	for entry in level_slots.values():
		var pack: LevelSlot = entry as LevelSlot
		if pack != null and pack.faction == Faction.ENEMY_1:
			enemy_count += 1
	if enemy_count > 0:
		return
	_dispatch_victory()
