extends SceneTree
## L1.3a 扎营时钟 + 命数独立 + climax 标志 数据层冒烟测试（子 MVP ① 阶段 A）
##
## 运行：tools/run_godot.ps1 --headless -s test/test_l13a_camp_clock.gd
##
## 设计：tile-advanture-design/无限地图实装/L1.3a_扎营时钟与胜负模型_MVP.md §3.1 / §10 阶段 A
##
## 验证范围（仅数据层；消费方源切换在阶段 B，本批不覆盖）：
##   1. ensure_initialized 注入命数 K（可选参 + 默认值）
##   2. record_camp 累加 lifetime 主时钟 _total_camp_count（不随 advance_cycle 归零）
##   3. _total_camp_count 与 cycle 解耦（advance_cycle / consume_respawn_life 均不动它）
##   4. climax 标志：初始 false / mark 后 true / 幂等
##   5. reset 清零三个新字段
##   6. 命数独立计数 respawns_remaining 与 cycle 解耦（阶段 A 仅就位 + 查询，不消费）

var _failed: int = 0


func _init() -> void:
	print("=== L1.3a 扎营时钟 / 命数独立 / climax 数据层冒烟测试（阶段 A）===")

	_test_respawns_remaining_inject()
	_test_total_camp_count_accumulate()
	_test_total_camp_count_survives_cycle()
	_test_climax_flag()
	_test_reset_clears_new_fields()
	_test_respawns_remaining_decoupled_from_cycle()

	if _failed > 0:
		printerr("✗ 共 %d 项失败" % _failed)
		quit(1)
	else:
		print("✓ 全部通过")
		quit(0)


# ─────────────────────────────────────
# 用例
# ─────────────────────────────────────

## 1. ensure_initialized 注入命数 K（可选参 + 默认）
func _test_respawns_remaining_inject() -> void:
	print("-- ensure_initialized 注入命数 K")
	# 显式传入 K=5
	RunState.reset()
	RunState.ensure_initialized(3, _mock_hero_pool(), _make_rng(42), 5)
	_assert(RunState.respawns_remaining() == 5, "显式传入 K=5 → respawns_remaining=5")
	# 默认参（不传）→ 3
	RunState.reset()
	RunState.ensure_initialized(3, _mock_hero_pool(), _make_rng(42))
	_assert(RunState.respawns_remaining() == 3, "默认参 → respawns_remaining=3")
	# 负值兜底 → 0
	RunState.reset()
	RunState.ensure_initialized(3, _mock_hero_pool(), _make_rng(42), -2)
	_assert(RunState.respawns_remaining() == 0, "负值 K → maxi 兜底为 0")


## 2. record_camp 累加 lifetime 主时钟
func _test_total_camp_count_accumulate() -> void:
	print("-- record_camp 累加 _total_camp_count")
	_reset()
	_assert(RunState.total_camp_count() == 0, "初始 total_camp_count=0")
	RunState.record_camp()
	RunState.record_camp()
	RunState.record_camp()
	_assert(RunState.total_camp_count() == 3, "扎营 3 次 → total_camp_count=3")
	# 与 per-cycle 计数并存（不冲突）
	_assert(RunState.get_current_cycle_camp_count() == 3, "per-cycle 计数同步 = 3")


## 3. _total_camp_count 不随 advance_cycle 归零（lifetime 语义）
func _test_total_camp_count_survives_cycle() -> void:
	print("-- _total_camp_count 跨 advance_cycle 不归零")
	_reset()
	RunState.record_camp()
	RunState.record_camp()
	RunState.advance_cycle()  # per-cycle 归零，但 lifetime 主时钟保留
	_assert(RunState.get_current_cycle_camp_count() == 0, "advance 后 per-cycle 归零")
	_assert(RunState.total_camp_count() == 2, "advance 后 lifetime 主时钟保留=2")
	RunState.record_camp()
	_assert(RunState.total_camp_count() == 3, "跨周期继续累加=3")
	# codex P2：consume_respawn_life（命数路径）同样不应污染 lifetime 主时钟。
	# 阶段 B/D 改写 consume_respawn_life 时，本断言可抓住"误清零/误改 total"的回归
	RunState.consume_respawn_life()
	_assert(RunState.total_camp_count() == 3, "consume_respawn_life 不影响 lifetime 主时钟（仍 3）")


## 4. climax 标志：初始 false / mark 后 true / 幂等
func _test_climax_flag() -> void:
	print("-- climax 标志 mark / 幂等")
	_reset()
	_assert(not RunState.is_climax_triggered(), "初始 climax 未触发")
	RunState.mark_climax_triggered()
	_assert(RunState.is_climax_triggered(), "mark 后 climax 触发")
	RunState.mark_climax_triggered()  # 幂等
	_assert(RunState.is_climax_triggered(), "重复 mark 仍 true（幂等）")


## 5. reset 清零三个新字段
func _test_reset_clears_new_fields() -> void:
	print("-- reset 清零新字段")
	_reset()
	RunState.record_camp()
	RunState.record_camp()
	RunState.mark_climax_triggered()
	RunState.reset()
	_assert(RunState.total_camp_count() == 0, "reset 后 total_camp_count=0")
	_assert(RunState.respawns_remaining() == 0, "reset 后 respawns_remaining=0（待 ensure 重新注入）")
	_assert(not RunState.is_climax_triggered(), "reset 后 climax=false")


## 6. 命数独立计数与 cycle 解耦（阶段 A：advance_cycle / consume_respawn_life 不动 respawns_remaining）
##
## 注：阶段 A 消费方未切换——consume_respawn_life 仍推 _cycle_index（旧逻辑），
## 故本用例验证"新计数器不被旧 cycle 路径污染"，命数实际消费的源切换在阶段 B 覆盖
func _test_respawns_remaining_decoupled_from_cycle() -> void:
	print("-- respawns_remaining 与 cycle 解耦")
	_reset()
	_assert(RunState.respawns_remaining() == 3, "初始 respawns_remaining=3")
	RunState.advance_cycle()
	RunState.consume_respawn_life()  # 阶段 A 仍走 _cycle_index += 1
	_assert(RunState.respawns_remaining() == 3, "cycle 推进不影响独立命数计数（仍 3）")


# ─────────────────────────────────────
# 辅助
# ─────────────────────────────────────

## 重置测试上下文：reset + ensure_initialized（默认 K=3）
func _reset() -> void:
	RunState.clear_sinks()
	RunState.reset()
	RunState.ensure_initialized(3, _mock_hero_pool(), _make_rng(42))


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
