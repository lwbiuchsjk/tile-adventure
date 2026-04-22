extends SceneTree
## M3 回合框架与 Tick 冒烟测试
## 运行：tools/run_godot.ps1 --headless -s test/test_m3_turn_framework.gd
##
## 验证范围（对应 M3 验收标准）：
##   1. TickRegistry register / unregister / run_ticks 基础行为
##   2. tick handler 收到正确的 faction 参数
##   3. tick 在 faction_turn_started 信号之前执行（顺序保证）
##   4. 切换 10 回合无 crash、计数正确
##   5. tick handler 内部递归 run_ticks 被阻止（防递归）
##   6. tick handler 内部 register / unregister 延迟到本轮结束后生效
##   7. 旧 turn_ended(int) / current_turn / register_unit 接口未被破坏

var _failed: int = 0

# 测试期间累积的事件序列，用于断言顺序
var _events: Array[String] = []
# 当前阵营，供 tick handler 闭包内读取
var _last_tick_faction: int = -1


func _init() -> void:
	print("=== M3 回合框架冒烟测试 ===")

	# 每个 case 之前清空 TickRegistry 状态，避免相互污染
	_test_basic_register()
	TickRegistry.clear_all()

	_test_tick_with_faction()
	TickRegistry.clear_all()

	_test_tick_before_signal()
	TickRegistry.clear_all()

	_test_ten_turn_switch()
	TickRegistry.clear_all()

	_test_recursive_guard()
	TickRegistry.clear_all()

	_test_pending_register_during_run()
	TickRegistry.clear_all()

	_test_legacy_api_intact()

	if _failed > 0:
		printerr("✗ 共 %d 项失败" % _failed)
		quit(1)
	else:
		print("✓ 全部通过")
		quit(0)


# ─────────────────────────────────────────
# 测试用例
# ─────────────────────────────────────────

## 1. 基础 register / unregister / handler_count
func _test_basic_register() -> void:
	_assert(TickRegistry.handler_count() == 0, "初始 handler_count == 0")
	var h: Callable = func(_f: int) -> void: pass
	TickRegistry.register(h)
	_assert(TickRegistry.handler_count() == 1, "register 后 handler_count == 1")
	# 重复 register 不应叠加
	TickRegistry.register(h)
	_assert(TickRegistry.handler_count() == 1, "重复 register 不应叠加")
	TickRegistry.unregister(h)
	_assert(TickRegistry.handler_count() == 0, "unregister 后 handler_count == 0")


## 2. tick handler 收到正确 faction 参数
func _test_tick_with_faction() -> void:
	_last_tick_faction = -1
	var h: Callable = func(faction: int) -> void:
		_last_tick_faction = faction
	TickRegistry.register(h)

	TickRegistry.run_ticks(Faction.PLAYER)
	_assert(_last_tick_faction == Faction.PLAYER, "PLAYER 回合 tick 收到 PLAYER")

	TickRegistry.run_ticks(Faction.ENEMY_1)
	_assert(_last_tick_faction == Faction.ENEMY_1, "ENEMY_1 回合 tick 收到 ENEMY_1")


## 3. tick 在 faction_turn_started 信号之前执行
func _test_tick_before_signal() -> void:
	_events.clear()
	var tm: TurnManager = TurnManager.new()

	var tick_h: Callable = func(_f: int) -> void:
		_events.append("tick")
	TickRegistry.register(tick_h)

	tm.faction_turn_started.connect(func(_f: int) -> void:
		_events.append("signal")
	)

	tm.start_faction_turn(Faction.PLAYER)

	_assert(_events.size() == 2,        "应记录 2 个事件")
	_assert(_events[0] == "tick",       "事件[0] 必须是 tick")
	_assert(_events[1] == "signal",     "事件[1] 必须是 signal")


## 4. 切换 10 个阵营回合无 crash + 计数正确
func _test_ten_turn_switch() -> void:
	var tm: TurnManager = TurnManager.new()
	# 玩家先手 → 敌方 → ... 共 10 回合（5 玩家 + 5 敌方）
	for i in range(10):
		tm.start_faction_turn(tm.current_faction)
		tm.end_faction_turn()
		# 切换到对方阵营准备下一轮
		tm.current_faction = tm.get_opposite_faction()

	_assert(tm.player_faction_turn_count == 5, "玩家累计 5 回合")
	_assert(tm.enemy_faction_turn_count == 5,  "敌方累计 5 回合")


## 5. tick 内部递归调用 run_ticks 被阻止
func _test_recursive_guard() -> void:
	var inner_called: Array[bool] = [false]
	var recurse_h: Callable = func(_f: int) -> void:
		# 期望此调用被 push_error 阻止，不抛异常
		TickRegistry.run_ticks(Faction.PLAYER)
		inner_called[0] = true
	TickRegistry.register(recurse_h)
	# 主动消音 push_error 输出（无原生 API，这里只验证不 crash）
	TickRegistry.run_ticks(Faction.PLAYER)
	_assert(inner_called[0] == true, "外层 handler 仍执行完")
	# 关键：未栈溢出 / crash 即过


## 6. handler 内部 register / unregister 延迟到本轮结束生效
func _test_pending_register_during_run() -> void:
	var added_called: Array[bool] = [false]
	var added_h: Callable = func(_f: int) -> void:
		added_called[0] = true

	var registrar_h: Callable = func(_f: int) -> void:
		# 在 tick 期间动态加一个新 handler
		TickRegistry.register(added_h)

	TickRegistry.register(registrar_h)
	TickRegistry.run_ticks(Faction.PLAYER)

	# 本轮中 added_h 不应被调用（延迟生效）
	_assert(added_called[0] == false, "新加 handler 本轮不触发")
	_assert(TickRegistry.handler_count() == 2, "本轮结束后 handler_count == 2")

	# 下一轮 added_h 应被调用
	TickRegistry.run_ticks(Faction.PLAYER)
	_assert(added_called[0] == true, "新加 handler 下一轮被触发")


## 7. 旧"流程性回合计数"接口未被破坏
func _test_legacy_api_intact() -> void:
	var tm: TurnManager = TurnManager.new()
	var captured: Array[int] = []
	tm.turn_ended.connect(func(n: int) -> void:
		captured.append(n)
	)
	_assert(tm.current_turn == 0, "旧 current_turn 初始 0")
	tm.end_turn()
	_assert(tm.current_turn == 1, "end_turn 后 current_turn == 1")
	tm.end_turn()
	_assert(tm.current_turn == 2, "end_turn 二次后 current_turn == 2")
	_assert(captured == [1, 2],   "旧 turn_ended 信号按序触发并带回合号")


# ─────────────────────────────────────────
# 断言辅助
# ─────────────────────────────────────────

## 简易断言：通过打印 ✓，失败打印 ✗ 并计数
func _assert(cond: bool, msg: String) -> void:
	if cond:
		print("  ✓ " + msg)
	else:
		printerr("  ✗ " + msg)
		_failed += 1
