extends SceneTree
## 昏迷复活分流冒烟测试（L1.2 Phase 3）
##
## 运行：tools/run_godot.ps1 --headless -s test/test_coma_respawn.gd
##
## 验证范围（PlayerLifecycle.trigger_coma_or_lose 三路 fork + 命数语义）：
##   设计：tile-advanture-design/无限地图实装/L1.2_多源视野与据点机制_MVP.md §2.3
##   ① 有有效据点          → coma_respawn_triggered(据点位, deduct=false, stronghold=true)，无视命数
##   ② 无据点 + 命数 > 0    → coma_respawn_triggered(fallback位, deduct=true, stronghold=false)
##   ③ 无据点 + 命数耗尽    → defeat_triggered(ENEMY_1)
##   ④ 幂等：_is_in_coma 期间重复调用不重复 emit
##   ⑤ resolver 未注册退化：等价"无据点"路径
##
## 说明：trigger_coma_or_lose 已与 UI/场景/持久 slot 表解耦（目标解析交注入 resolver），
## 故可不经 setup 直接构造 PlayerLifecycle 单元测试分流逻辑。
## 实际传送（位置/满血/相机）由 WorldMap+EC 集成路径承担，走桌面跑测验收（headless 不覆盖 GUI/视图）。

var _failed: int = 0

## 信号捕获
var _respawn_captured: Array[Dictionary] = []
var _defeat_captured: Array[int] = []


func _init() -> void:
	print("=== 昏迷复活分流冒烟测试（L1.2 Phase 3）===")

	_test_stronghold_zero_cost_respawn()
	_test_stronghold_ignores_exhausted_lives()
	_test_no_stronghold_deduct_life()
	_test_no_stronghold_exhausted_defeat()
	_test_coma_idempotent()
	_test_resolver_unregistered_degrades_to_fallback()

	if _failed > 0:
		printerr("✗ 共 %d 项失败" % _failed)
		quit(1)
	else:
		print("✓ 全部通过")
		quit(0)


# ─────────────────────────────────────
# 用例
# ─────────────────────────────────────

## ① 有有效据点 → 零代价原地传送（deduct=false, stronghold=true），无视命数
func _test_stronghold_zero_cost_respawn() -> void:
	print("-- 有据点：零代价传送")
	var lc: PlayerLifecycle = _make_lifecycle({
		"has_stronghold": true,
		"stronghold_pos": Vector2i(7, 3),
		"fallback_pos": Vector2i(0, 0),
	})
	lc.trigger_coma_or_lose()
	_assert(_respawn_captured.size() == 1, "emit coma_respawn 一次")
	_assert(_defeat_captured.is_empty(), "不 emit defeat")
	_assert(bool(_respawn_captured[0]["is_stronghold"]), "is_stronghold=true")
	_assert(not bool(_respawn_captured[0]["deduct_life"]), "deduct_life=false（不扣命数）")
	_assert(_respawn_captured[0]["target_pos"] == Vector2i(7, 3), "传送目标=据点位")
	_assert(lc.is_in_coma(), "进入昏迷态")
	lc.free()


## ② 据点路径无视命数耗尽：末周期有据点仍传送，不 defeat
func _test_stronghold_ignores_exhausted_lives() -> void:
	print("-- 有据点：末周期仍传送（不 defeat）")
	var lc: PlayerLifecycle = _make_lifecycle({
		"has_stronghold": true,
		"stronghold_pos": Vector2i(4, 4),
		"fallback_pos": Vector2i(0, 0),
	})
	# 构造后推到末周期（_make_lifecycle 内 reset 已把 cycle 清零）
	RunState.advance_cycle()
	RunState.advance_cycle()
	_assert(RunState.respawns_left() == 0, "前置：命数耗尽")
	lc.trigger_coma_or_lose()
	_assert(_respawn_captured.size() == 1, "据点路径仍 emit coma_respawn")
	_assert(_defeat_captured.is_empty(), "命数耗尽但有据点 → 不 defeat")
	_assert(bool(_respawn_captured[0]["is_stronghold"]), "is_stronghold=true")
	lc.free()


## ③ 无据点 + 命数 > 0 → 扣命数 fallback 传送（deduct=true, stronghold=false）
func _test_no_stronghold_deduct_life() -> void:
	print("-- 无据点 + 命数>0：扣命数传送")
	var lc: PlayerLifecycle = _make_lifecycle({
		"has_stronghold": false,
		"stronghold_pos": Vector2i(0, 0),
		"fallback_pos": Vector2i(9, 1),
	})
	_assert(RunState.respawns_left() == 2, "前置：命数 2")
	lc.trigger_coma_or_lose()
	_assert(_respawn_captured.size() == 1, "emit coma_respawn 一次")
	_assert(_defeat_captured.is_empty(), "不 emit defeat")
	_assert(not bool(_respawn_captured[0]["is_stronghold"]), "is_stronghold=false")
	_assert(bool(_respawn_captured[0]["deduct_life"]), "deduct_life=true（扣命数）")
	_assert(_respawn_captured[0]["target_pos"] == Vector2i(9, 1), "传送目标=fallback位")
	_assert(lc.is_in_coma(), "进入昏迷态")
	lc.free()


## ④ 无据点 + 命数耗尽 → defeat(ENEMY_1)
func _test_no_stronghold_exhausted_defeat() -> void:
	print("-- 无据点 + 命数耗尽：整局失败")
	var lc: PlayerLifecycle = _make_lifecycle({
		"has_stronghold": false,
		"stronghold_pos": Vector2i(0, 0),
		"fallback_pos": Vector2i(9, 1),
	})
	# 构造后推到末周期（_make_lifecycle 内 reset 已把 cycle 清零）
	RunState.advance_cycle()
	RunState.advance_cycle()
	_assert(RunState.respawns_left() == 0, "前置：命数耗尽")
	lc.trigger_coma_or_lose()
	_assert(_respawn_captured.is_empty(), "不 emit coma_respawn")
	_assert(_defeat_captured.size() == 1, "emit defeat 一次")
	_assert(_defeat_captured[0] == Faction.ENEMY_1, "defeat faction = ENEMY_1")
	_assert(not lc.is_in_coma(), "defeat 路径不进昏迷态")
	lc.free()


## ⑤ 幂等：_is_in_coma 期间重复调用不重复 emit
func _test_coma_idempotent() -> void:
	print("-- 幂等：昏迷态重复调用不重复触发")
	var lc: PlayerLifecycle = _make_lifecycle({
		"has_stronghold": true,
		"stronghold_pos": Vector2i(1, 1),
		"fallback_pos": Vector2i(0, 0),
	})
	lc.trigger_coma_or_lose()
	lc.trigger_coma_or_lose()  # 第二次：_is_in_coma 守卫
	_assert(_respawn_captured.size() == 1, "重复调用只 emit 一次")
	# clear_coma 后可再触发
	lc.clear_coma()
	_assert(not lc.is_in_coma(), "clear_coma 解除昏迷锁")
	lc.trigger_coma_or_lose()
	_assert(_respawn_captured.size() == 2, "clear 后再触发 emit 第二次")
	lc.free()


## ⑥ resolver 未注册 → 退化为"无据点 + fallback=ZERO"路径（命数 > 0 走扣命数兜底）
func _test_resolver_unregistered_degrades_to_fallback() -> void:
	print("-- resolver 未注册：退化为无据点路径")
	_reset_capture()
	RunState.reset()
	RunState.ensure_initialized(3, _mock_hero_pool(), _make_rng(42))
	var lc: PlayerLifecycle = PlayerLifecycle.new()
	lc.coma_respawn_triggered.connect(_on_respawn)
	lc.defeat_triggered.connect(_on_defeat)
	# 不 register_coma_respawn_resolver
	lc.trigger_coma_or_lose()
	_assert(_respawn_captured.size() == 1, "退化路径 emit coma_respawn")
	_assert(not bool(_respawn_captured[0]["is_stronghold"]), "退化为非据点")
	_assert(bool(_respawn_captured[0]["deduct_life"]), "退化为扣命数")
	_assert(_respawn_captured[0]["target_pos"] == Vector2i.ZERO, "退化 fallback=ZERO")
	lc.free()


# ─────────────────────────────────────
# 辅助
# ─────────────────────────────────────

## 构造 PlayerLifecycle：reset RunState（命数满）+ 注入返回固定 resolution 的 resolver + 接信号
func _make_lifecycle(resolution: Dictionary) -> PlayerLifecycle:
	_reset_capture()
	RunState.reset()
	RunState.ensure_initialized(3, _mock_hero_pool(), _make_rng(42))
	var lc: PlayerLifecycle = PlayerLifecycle.new()
	lc.coma_respawn_triggered.connect(_on_respawn)
	lc.defeat_triggered.connect(_on_defeat)
	lc.register_coma_respawn_resolver(func() -> Dictionary: return resolution)
	return lc


## 清空信号捕获缓存（每个用例开头复位）
func _reset_capture() -> void:
	_respawn_captured = []
	_defeat_captured = []


func _on_respawn(target_pos: Vector2i, deduct_life: bool, is_stronghold: bool) -> void:
	_respawn_captured.append({
		"target_pos": target_pos,
		"deduct_life": deduct_life,
		"is_stronghold": is_stronghold,
	})


func _on_defeat(faction: int) -> void:
	_defeat_captured.append(faction)


func _mock_hero_pool() -> Array:
	return [
		{"id": 0, "name": "队长 A", "troop_type": "SWORD", "troop_quality": "T1"},
		{"id": 1, "name": "队长 B", "troop_type": "ARCHER", "troop_quality": "T1"},
		{"id": 2, "name": "队长 C", "troop_type": "SPEAR", "troop_quality": "T1"},
		{"id": 3, "name": "队长 D", "troop_type": "SWORD", "troop_quality": "T2"},
	]


func _make_rng(seed_value: int) -> RandomNumberGenerator:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _assert(cond: bool, msg: String) -> void:
	if cond:
		print("  ✓ " + msg)
	else:
		printerr("  ✗ " + msg)
		_failed += 1
