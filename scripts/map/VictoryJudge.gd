class_name VictoryJudge
extends RefCounted
## 胜负判定系统（M8 + P0 X-A 阵营过滤）
##
## 设计原文：
##   tile-advanture-design/胜负条件重设计_MVP.md（P0 第一阶段，2026-05-08 定调）
##   tile-advanture-design/城建锚实装/M8_胜负与最小验证.md（旧）
##   tile-advanture-design/持久slot基础功能设计.md §七（旧）
##
## 规则（P0 X-A 后）：
##   玩家攻占敌方核心城镇（CORE_TOWN 且新归属为 PLAYER）→ 玩家胜利
##   X-A 后玩家方区无 CORE_TOWN（已降级为 TOWN 占位），VictoryJudge 仅会被敌方核心翻转触发
##   失败侧不再由 VictoryJudge 触发——失败仅由「队长命数耗尽」走 _trigger_coma_or_lose 末周期分支
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
## P0 X-A 阵营过滤：
##   非 CORE_TOWN / 新归属非 PLAYER / 已判定 时无操作
##   X-A 后玩家方区无 CORE_TOWN，仅敌方核心可被监听到；新归属 != PLAYER 直接 return
##   即使 owner=NONE / ENEMY_1 也都被新过滤拦截
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
	if _finished:
		return
	if not _sink.is_valid():
		push_error("VictoryJudge.check_on_slot_owner_changed: sink 未注册或已失效，胜利事件未分发")
		return
	_finished = true
	_sink.call(Faction.PLAYER)
