extends SceneTree
## 胜负判定冒烟测试（L1.3a 阶段 B 口径改写）
## 运行：tools/run_godot.ps1 --headless -s test/test_m8_victory_judge.gd
##
## L1.3a 设计 §4.4：扎营时钟接管胜负后——
##   - 占敌方核心 / 消灭所有敌包 的胜负语义已移除（check_on_slot_owner_changed → no-op）
##   - 唯一胜利出口 = dispatch_climax_victory（climax 决战胜，阶段 C 由 boss 战清空触发）
##   - 周期推进出口（_cycle_victory_sink）休眠待阶段 D 清理，本套件不再覆盖
##
## 验证范围：
##   1. check_on_slot_owner_changed 退化为 no-op（核心 / 非核心翻转均不触发胜负）
##   2. dispatch_climax_victory：sink PLAYER + _finished 一局一次 gate
##   3. sink 注册 / 清理（clear_sink / 重复注册以最后一次为准 / 无效 sink 不封盘）
##   4. OccupationSystem.try_occupy 仍翻转归属，但不再触发任何胜负 sink（占领与胜负解耦）

var _failed: int = 0

## sink 捕获：被调时记录 winner 列表
var _captured: Array[int] = []


func _init() -> void:
	print("=== 胜负判定冒烟测试（L1.3a 阶段 B 口径）===")

	_test_occupy_core_no_longer_triggers()
	_test_occupy_non_core_no_trigger()
	_test_climax_victory_dispatch()
	_test_climax_victory_finished_gate()
	_test_clear_sink()
	_test_sink_last_write_wins()
	_test_invalid_sink_does_not_lock_finished()
	_test_occupation_integration_flip_no_victory()
	_test_occupation_same_faction_no_flip()
	_test_occupation_village_flip_no_victory()

	if _failed > 0:
		printerr("✗ 共 %d 项失败" % _failed)
		quit(1)
	else:
		print("✓ 全部通过")
		quit(0)


# ─────────────────────────────────────────
# 用例：check_on_slot_owner_changed 退化为 no-op
# ─────────────────────────────────────────

## 1. 占敌方核心不再触发胜负（占核心胜负语义已移除）
func _test_occupy_core_no_longer_triggers() -> void:
	print("-- 占敌方核心不再触发胜负（no-op）")
	_reset()
	var core: PersistentSlot = _make_slot(PersistentSlot.Type.CORE_TOWN, Faction.PLAYER)
	VictoryJudge.check_on_slot_owner_changed(core)
	_assert(_captured.is_empty(), "占核心不触发 sink（语义已移除）")
	_assert(not VictoryJudge.is_finished(), "_finished 保持 false")


## 2. 非核心 slot 翻转同样不触发（no-op 对一切 slot）
func _test_occupy_non_core_no_trigger() -> void:
	print("-- 非核心 slot 翻转不触发")
	_reset()
	VictoryJudge.check_on_slot_owner_changed(_make_slot(PersistentSlot.Type.VILLAGE, Faction.PLAYER))
	VictoryJudge.check_on_slot_owner_changed(_make_slot(PersistentSlot.Type.TOWN, Faction.PLAYER))
	_assert(_captured.is_empty(), "村庄 / 城镇翻转均不触发 sink")


# ─────────────────────────────────────────
# 用例：dispatch_climax_victory（唯一胜利出口）
# ─────────────────────────────────────────

## 3. dispatch_climax_victory → sink 收到 PLAYER + _finished 置 true
func _test_climax_victory_dispatch() -> void:
	print("-- dispatch_climax_victory 通关")
	_reset()
	VictoryJudge.dispatch_climax_victory()
	_assert(_captured.size() == 1, "sink 被调用一次")
	_assert(_captured[0] == Faction.PLAYER, "winner 为 PLAYER")
	_assert(VictoryJudge.is_finished(), "_finished 置 true")


## 4. _finished gate：同一局内第二次 dispatch 不重复触发
func _test_climax_victory_finished_gate() -> void:
	print("-- _finished gate 一局一次")
	_reset()
	VictoryJudge.dispatch_climax_victory()
	_assert(_captured.size() == 1, "第一次触发")
	VictoryJudge.dispatch_climax_victory()
	_assert(_captured.size() == 1, "第二次被 gate 拦截，sink 仍只 1 次")


## 5. clear_sink 后 sink 与 _finished 都被清理，重注册可再次触发
func _test_clear_sink() -> void:
	print("-- clear_sink 清理")
	_reset()
	VictoryJudge.dispatch_climax_victory()
	_assert(VictoryJudge.is_finished(), "触发后 _finished = true")

	VictoryJudge.clear_sink()
	_assert(not VictoryJudge.is_finished(), "clear_sink 后 _finished = false")

	# 重新注册后应能再次触发（模拟重开场景）
	_captured = []
	VictoryJudge.register_sink(_on_sink)
	VictoryJudge.dispatch_climax_victory()
	_assert(_captured.size() == 1 and _captured[0] == Faction.PLAYER, "重注册后可再次触发")


## 6. sink 多次注册以最后一次为准
func _test_sink_last_write_wins() -> void:
	print("-- sink 最后一次注册为准")
	_reset()
	var first_captured: Array[int] = []
	var first_sink: Callable = func(w: int) -> void: first_captured.append(w)
	VictoryJudge.register_sink(first_sink)
	VictoryJudge.register_sink(_on_sink)  # 覆盖第一个

	VictoryJudge.dispatch_climax_victory()
	_assert(first_captured.is_empty(), "旧 sink 不再收到")
	_assert(_captured.size() == 1, "新 sink 收到")


## 7. sink 未注册 / 无效时，_finished 不应被置位（审查 P1 修复回归）
## 理由：旧实现"先置 _finished=true 再 call sink"，sink 失效会导致本局永远不再触发胜负
func _test_invalid_sink_does_not_lock_finished() -> void:
	print("-- sink 无效不封盘（P1 修复回归）")
	VictoryJudge.clear_sink()  # 清空 sink，_finished 同时置 false
	_assert(not VictoryJudge.is_finished(), "起点 _finished = false")

	# 不重新 register_sink，直接 dispatch
	VictoryJudge.dispatch_climax_victory()
	_assert(not VictoryJudge.is_finished(), "sink 无效时 _finished 保持 false，避免永久封盘")


# ─────────────────────────────────────────
# 用例：OccupationSystem 集成（占领与胜负解耦）
# ─────────────────────────────────────────

## 8. try_occupy 翻转敌方核心成功，但不再触发胜负 sink
func _test_occupation_integration_flip_no_victory() -> void:
	print("-- OccupationSystem 集成：翻敌方核心不再触发胜负")
	_reset()
	var core: PersistentSlot = PersistentSlot.new()
	core.type = PersistentSlot.Type.CORE_TOWN
	core.owner_faction = Faction.ENEMY_1
	core.position = Vector2i(0, 0)
	core.initial_range = 1
	core.max_range = 3

	var flipped: bool = OccupationSystem.try_occupy(core, Faction.PLAYER)
	_assert(flipped, "翻转成功")
	_assert(core.owner_faction == Faction.PLAYER, "核心归属已切到 PLAYER")
	_assert(_captured.is_empty(), "占领与胜负解耦：不触发 sink")
	_assert(not VictoryJudge.is_finished(), "_finished 保持 false")


## 9. 同阵营"占据"返回 false 且不触发 sink
func _test_occupation_same_faction_no_flip() -> void:
	print("-- 同阵营占据不翻转 / 不触发 sink")
	_reset()
	var core: PersistentSlot = PersistentSlot.new()
	core.type = PersistentSlot.Type.CORE_TOWN
	core.owner_faction = Faction.PLAYER
	core.initial_range = 1
	core.max_range = 3

	var flipped: bool = OccupationSystem.try_occupy(core, Faction.PLAYER)
	_assert(not flipped, "同阵营返回 false")
	_assert(_captured.is_empty(), "sink 未触发")


## 10. 非核心 slot 经 try_occupy 翻转不触发 sink
func _test_occupation_village_flip_no_victory() -> void:
	print("-- 非核心 slot 翻转不触发 sink")
	_reset()
	var village: PersistentSlot = PersistentSlot.new()
	village.type = PersistentSlot.Type.VILLAGE
	village.owner_faction = Faction.ENEMY_1
	village.initial_range = 1
	village.max_range = 2

	var flipped: bool = OccupationSystem.try_occupy(village, Faction.PLAYER)
	_assert(flipped, "村庄翻转成功")
	_assert(_captured.is_empty(), "sink 未触发（非核心城镇）")


# ─────────────────────────────────────────
# 辅助
# ─────────────────────────────────────────

## 重置测试上下文：清理 VictoryJudge 静态态 + sink 捕获列表 + 重新注册 sink + 清据点态
func _reset() -> void:
	VictoryJudge.clear_sink()
	_captured = []
	VictoryJudge.register_sink(_on_sink)
	# 据点态清零（占领集成用例不依赖据点；保持干净起点）
	RunState._has_stronghold = false
	RunState._stronghold_pos = Vector2i.ZERO


## sink 捕获回调
func _on_sink(winner: int) -> void:
	_captured.append(winner)


## 构造指定类型 + 归属的 PersistentSlot（owner_faction 已设置为"翻转后"的状态）
func _make_slot(type: int, owner: int) -> PersistentSlot:
	var s: PersistentSlot = PersistentSlot.new()
	s.type = type
	s.owner_faction = owner
	return s


func _assert(cond: bool, msg: String) -> void:
	if cond:
		print("  ✓ " + msg)
	else:
		printerr("  ✗ " + msg)
		_failed += 1
