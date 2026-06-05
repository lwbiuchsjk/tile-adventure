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
## 规则（L1.3a 扎营时钟与胜负模型 MVP 后）：
##   唯一胜利路径 = climax 决战胜（boss pack 清空）→ dispatch_climax_victory → _sink →
##     WorldMap._on_victory_decided(PLAYER) → VictoryUI，_finished 一局一次。
##   占敌方核心 / 消灭所有敌包 的胜负语义已移除（check_on_slot_owner_changed 退化为 no-op）；
##   周期推进出口（_cycle_victory_sink / _cycle_advancing）已于阶段 D 整体移除（cycle 范式退役）。
##   失败侧不由 VictoryJudge 触发——失败①「无据点命数耗尽」/ 失败②「climax 战败 sudden-death」
##   均由 PlayerLifecycle 走 defeat_triggered(ENEMY_1)。
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


## 核心城镇归属变更时调用（L1.3a 阶段 B：占核心胜负语义已移除 → no-op）
##
## L1.3a 设计 §4.4：扎营时钟接管胜负后，占敌方核心不再触发胜利 / 周期推进。
## 本方法保留为无害 hook（OccupationSystem.try_occupy 翻转后仍调用），不做任何分发；
## 占敌方核心的新玩法意义（资源 / 据点扩张等）留子 MVP ② / 后续重新定义。
## 原 is_last_cycle 分流 + _dispatch_victory + 周期推进出口（_cycle_victory_sink）已于阶段 B/D 整体移除。
static func check_on_slot_owner_changed(_slot: PersistentSlot) -> void:
	return


## L1.3a 阶段 B：climax 决战胜利分发（唯一通关出口）
## 阶段 C 由战斗结算路径在"boss pack 清空"时调用 → WorldMap._on_victory_decided(PLAYER) → VictoryUI。
##
## Sink 有效性检查在 _finished 置位之前（沿用原 P1 修复语义）：sink 无效时不封盘，留恢复机会 + push_error 排障。
## _finished 一局一次守卫，防重复分发。
static func dispatch_climax_victory() -> void:
	if _finished:
		return
	if not _sink.is_valid():
		push_error("VictoryJudge.dispatch_climax_victory: 通关 sink 未注册或已失效，胜利事件未分发")
		return
	_finished = true
	_sink.call(Faction.PLAYER)
