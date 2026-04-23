extends SceneTree
## M8 胜负判定冒烟测试
## 运行：tools/run_godot.ps1 --headless -s test/test_m8_victory_judge.gd
##
## 验证范围（M8 核心逻辑层）：
##   1. VictoryJudge gating：非核心 slot 不触发 / 核心 slot 触发 / _finished 一次性
##   2. sink 注册 + 清理（clear_sink / 重复注册以最后一次为准）
##   3. OccupationSystem.try_occupy 翻转核心城镇 → sink 收到 winner_faction
##   4. 同阵营"占据"（无翻转）不触发 sink
##   5. 非核心持久 slot 翻转不触发 sink

var _failed: int = 0

## sink 捕获：被调时记录 winner 列表
var _captured: Array[int] = []


func _init() -> void:
	print("=== M8 胜负判定冒烟测试 ===")

	_test_non_core_slot_not_triggered()
	_test_core_slot_triggers_player_win()
	_test_core_slot_triggers_enemy_win()
	_test_finished_gate_once_per_game()
	_test_clear_sink()
	_test_sink_last_write_wins()
	_test_occupation_system_integration_player_flip()
	_test_occupation_system_integration_enemy_flip()
	_test_same_faction_occupy_no_trigger()
	_test_non_core_occupy_no_trigger()
	_test_invalid_sink_does_not_lock_finished()

	if _failed > 0:
		printerr("✗ 共 %d 项失败" % _failed)
		quit(1)
	else:
		print("✓ 全部通过")
		quit(0)


# ─────────────────────────────────────────
# 用例
# ─────────────────────────────────────────

## 1. 非核心 slot 翻转不触发 sink
func _test_non_core_slot_not_triggered() -> void:
	print("-- 非核心 slot 不触发")
	_reset()
	var slot: PersistentSlot = _make_slot(PersistentSlot.Type.VILLAGE, Faction.PLAYER)
	VictoryJudge.check_on_slot_owner_changed(slot)
	_assert(_captured.is_empty(), "村庄归属变更不触发 sink")
	_assert(not VictoryJudge.is_finished(), "_finished 仍为 false")

	var town: PersistentSlot = _make_slot(PersistentSlot.Type.TOWN, Faction.PLAYER)
	VictoryJudge.check_on_slot_owner_changed(town)
	_assert(_captured.is_empty(), "城镇归属变更不触发 sink")


## 2. 核心城镇翻转到 PLAYER → sink 收到 PLAYER
func _test_core_slot_triggers_player_win() -> void:
	print("-- 核心城镇翻转 PLAYER 胜")
	_reset()
	var core: PersistentSlot = _make_slot(PersistentSlot.Type.CORE_TOWN, Faction.PLAYER)
	VictoryJudge.check_on_slot_owner_changed(core)
	_assert(_captured.size() == 1,           "sink 被调用一次")
	_assert(_captured[0] == Faction.PLAYER,  "winner 为 PLAYER")
	_assert(VictoryJudge.is_finished(),      "_finished 置 true")


## 3. 核心城镇翻转到 ENEMY_1 → sink 收到 ENEMY_1
func _test_core_slot_triggers_enemy_win() -> void:
	print("-- 核心城镇翻转 ENEMY_1 胜")
	_reset()
	var core: PersistentSlot = _make_slot(PersistentSlot.Type.CORE_TOWN, Faction.ENEMY_1)
	VictoryJudge.check_on_slot_owner_changed(core)
	_assert(_captured.size() == 1,           "sink 被调用一次")
	_assert(_captured[0] == Faction.ENEMY_1, "winner 为 ENEMY_1")


## 4. _finished gate：同一局内第二次调用不触发
func _test_finished_gate_once_per_game() -> void:
	print("-- _finished gate 一局一次")
	_reset()
	var core1: PersistentSlot = _make_slot(PersistentSlot.Type.CORE_TOWN, Faction.PLAYER)
	VictoryJudge.check_on_slot_owner_changed(core1)
	_assert(_captured.size() == 1, "第一次触发")

	var core2: PersistentSlot = _make_slot(PersistentSlot.Type.CORE_TOWN, Faction.ENEMY_1)
	VictoryJudge.check_on_slot_owner_changed(core2)
	_assert(_captured.size() == 1, "第二次被 gate 拦截，sink 仍只 1 次")


## 5. clear_sink 后 sink 与 _finished 都被清理
func _test_clear_sink() -> void:
	print("-- clear_sink 清理")
	_reset()
	var core: PersistentSlot = _make_slot(PersistentSlot.Type.CORE_TOWN, Faction.PLAYER)
	VictoryJudge.check_on_slot_owner_changed(core)
	_assert(VictoryJudge.is_finished(), "触发后 _finished = true")

	VictoryJudge.clear_sink()
	_assert(not VictoryJudge.is_finished(), "clear_sink 后 _finished = false")

	# 重新注册后应能再次触发（模拟重开场景）
	_captured = []
	VictoryJudge.register_sink(_on_sink)
	var core2: PersistentSlot = _make_slot(PersistentSlot.Type.CORE_TOWN, Faction.ENEMY_1)
	VictoryJudge.check_on_slot_owner_changed(core2)
	_assert(_captured.size() == 1 and _captured[0] == Faction.ENEMY_1, "重注册后可再次触发")


## 6. sink 多次注册以最后一次为准
func _test_sink_last_write_wins() -> void:
	print("-- sink 最后一次注册为准")
	_reset()
	var first_captured: Array[int] = []
	var first_sink: Callable = func(w: int) -> void: first_captured.append(w)
	VictoryJudge.register_sink(first_sink)
	VictoryJudge.register_sink(_on_sink)  # 覆盖第一个

	var core: PersistentSlot = _make_slot(PersistentSlot.Type.CORE_TOWN, Faction.PLAYER)
	VictoryJudge.check_on_slot_owner_changed(core)
	_assert(first_captured.is_empty(),  "旧 sink 不再收到")
	_assert(_captured.size() == 1,       "新 sink 收到")


## 7. OccupationSystem.try_occupy 翻转核心城镇（PLAYER 攻敌方核心）→ sink PLAYER
func _test_occupation_system_integration_player_flip() -> void:
	print("-- OccupationSystem 集成：玩家翻敌方核心")
	_reset()
	var core: PersistentSlot = PersistentSlot.new()
	core.type = PersistentSlot.Type.CORE_TOWN
	core.owner_faction = Faction.ENEMY_1
	core.position = Vector2i(0, 0)
	core.initial_range = 1
	core.max_range = 3

	var flipped: bool = OccupationSystem.try_occupy(core, Faction.PLAYER)
	_assert(flipped,                          "翻转成功")
	_assert(core.owner_faction == Faction.PLAYER, "核心归属已切到 PLAYER")
	_assert(_captured.size() == 1 and _captured[0] == Faction.PLAYER,
		"sink 收到 PLAYER 胜利")


## 8. OccupationSystem.try_occupy 翻转核心城镇（ENEMY_1 攻玩家核心）→ sink ENEMY_1
func _test_occupation_system_integration_enemy_flip() -> void:
	print("-- OccupationSystem 集成：敌方翻玩家核心")
	_reset()
	var core: PersistentSlot = PersistentSlot.new()
	core.type = PersistentSlot.Type.CORE_TOWN
	core.owner_faction = Faction.PLAYER
	core.position = Vector2i(5, 5)
	core.initial_range = 1
	core.max_range = 3

	var flipped: bool = OccupationSystem.try_occupy(core, Faction.ENEMY_1)
	_assert(flipped,                             "翻转成功")
	_assert(core.owner_faction == Faction.ENEMY_1, "核心归属已切到 ENEMY_1")
	_assert(_captured.size() == 1 and _captured[0] == Faction.ENEMY_1,
		"sink 收到 ENEMY_1 胜利（玩家失败）")


## 9. 同阵营"占据"返回 false 且 sink 不触发
func _test_same_faction_occupy_no_trigger() -> void:
	print("-- 同阵营占据不翻转 / 不触发 sink")
	_reset()
	var core: PersistentSlot = PersistentSlot.new()
	core.type = PersistentSlot.Type.CORE_TOWN
	core.owner_faction = Faction.PLAYER
	core.initial_range = 1
	core.max_range = 3

	var flipped: bool = OccupationSystem.try_occupy(core, Faction.PLAYER)
	_assert(not flipped,           "同阵营返回 false")
	_assert(_captured.is_empty(),  "sink 未触发")


## 11. sink 未注册 / 无效时，_finished 不应被置位（审查 P1 修复回归）
## 理由：旧实现"先置 _finished=true 再 call sink"，sink 失效会导致本局永远不再触发胜负
## 修复后 sink 无效直接 return，留出后续恢复机会
func _test_invalid_sink_does_not_lock_finished() -> void:
	print("-- sink 无效不封盘（P1 修复回归）")
	VictoryJudge.clear_sink()  # 清空 sink，_finished 同时置 false
	_assert(not VictoryJudge.is_finished(), "起点 _finished = false")

	# 不重新 register_sink，直接触发核心城镇翻转
	var core: PersistentSlot = _make_slot(PersistentSlot.Type.CORE_TOWN, Faction.PLAYER)
	VictoryJudge.check_on_slot_owner_changed(core)
	_assert(not VictoryJudge.is_finished(),
		"sink 无效时 _finished 保持 false，避免永久封盘")


## 10. 非核心 slot 经 OccupationSystem.try_occupy 翻转不触发 sink
func _test_non_core_occupy_no_trigger() -> void:
	print("-- 非核心 slot 翻转不触发 sink")
	_reset()
	var village: PersistentSlot = PersistentSlot.new()
	village.type = PersistentSlot.Type.VILLAGE
	village.owner_faction = Faction.ENEMY_1
	village.initial_range = 1
	village.max_range = 2

	var flipped: bool = OccupationSystem.try_occupy(village, Faction.PLAYER)
	_assert(flipped,               "村庄翻转成功")
	_assert(_captured.is_empty(),  "sink 未触发（非核心城镇）")


# ─────────────────────────────────────────
# 辅助
# ─────────────────────────────────────────

## 重置测试上下文：清理 VictoryJudge 静态态 + sink 捕获列表 + 重新注册 sink
func _reset() -> void:
	VictoryJudge.clear_sink()
	_captured = []
	VictoryJudge.register_sink(_on_sink)


## sink 捕获回调
func _on_sink(winner: int) -> void:
	_captured.append(winner)


## 构造指定类型 + 归属的 PersistentSlot（owner_faction 已设置为"翻转后"的状态）
## check_on_slot_owner_changed 读 slot.owner_faction 作为 winner
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
