extends SceneTree
## RunState 跨场景整局态冒烟测试（MVP-ε P3 测试补全）
##
## 运行：tools/run_godot.ps1 --headless -s test/test_run_state.gd
##
## 验证范围（RunState 核心 API）：
##   1. ensure_initialized / reset 生命周期
##   2. 周期推进 cycle_index / is_last_cycle / respawns_left / advance_cycle
##   3. 英雄池抽取 draw_new_leader / draw_recruit / used_hero_ids 跟踪
##   4. 重生事件占位 consume_pending_respawn_intro 幂等清零
##   5. 扎营计数 record_camp / get_current_cycle_camp_count
##   6. 里程碑入队 check_recruit_milestone + 同周期去重 + 池耗尽兜底
##   7. sink 注册 / 清理 / advance_cycle 触发

var _failed: int = 0

## sink 捕获
var _cycle_advance_captured: Array[Dictionary] = []
var _recruit_captured: Array[Dictionary] = []
var _stronghold_captured: Array[Vector2i] = []


func _init() -> void:
	print("=== RunState 冒烟测试 ===")

	_test_initial_state_after_init()
	_test_reset_clears_state()
	_test_advance_cycle_basic()
	_test_is_last_cycle_boundary()
	_test_respawns_left_calculation()
	_test_draw_new_leader_marks_used()
	_test_draw_new_leader_exhaust_fallback()
	_test_draw_recruit_excludes_team()
	_test_pending_respawn_intro_consume()
	_test_record_camp_advance_cycle_milestone()
	_test_check_recruit_milestone_same_cycle_dedupe()
	_test_sinks_register_and_clear()
	_test_stronghold_set_query_reset()
	_test_stronghold_set_sink()
	_test_stronghold_cross_init_preserved()
	_test_consume_respawn_life()
	_test_consume_respawn_life_preserves_stronghold()

	if _failed > 0:
		printerr("✗ 共 %d 项失败" % _failed)
		quit(1)
	else:
		print("✓ 全部通过")
		quit(0)


# ─────────────────────────────────────
# 用例
# ─────────────────────────────────────

## 1. ensure_initialized 写入默认状态
func _test_initial_state_after_init() -> void:
	print("-- ensure_initialized 写入默认状态")
	_reset()
	_assert(RunState.cycle_index() == 0, "cycle_index 初始为 0")
	_assert(RunState.max_cycles() == 3, "max_cycles = 3")
	_assert(not RunState.is_last_cycle(), "非末周期（cycle 0 / max 3）")
	_assert(RunState.respawns_left() == 2, "respawns_left = max - 1 - cycle = 2")
	_assert(not RunState.is_pending_respawn_intro(), "重生占位标志初始 false")
	_assert(RunState.get_current_cycle_camp_count() == 0, "本周期扎营计数 = 0")


## 2. reset 清整局态，下次 ensure_initialized 可重新写入
func _test_reset_clears_state() -> void:
	print("-- reset 清整局态")
	_reset()
	RunState.advance_cycle()
	RunState.record_camp()
	_assert(RunState.cycle_index() == 1, "advance 后 cycle = 1")
	_assert(RunState.get_current_cycle_camp_count() == 1, "扎营 1 次")
	RunState.reset()
	_assert(RunState.cycle_index() == 0, "reset 后 cycle 归零")
	_assert(RunState.active_used_hero_ids().is_empty(), "used_hero_ids 清空")
	# 再次 ensure_initialized 写入新数据
	RunState.ensure_initialized(5, _mock_hero_pool(), _make_rng(42))
	_assert(RunState.max_cycles() == 5, "reset 后 ensure_initialized 写入 max=5")


## 3. advance_cycle 推进 + emit signal
func _test_advance_cycle_basic() -> void:
	print("-- advance_cycle 推进")
	_reset()
	_cycle_advance_captured = []
	RunState.register_cycle_advance_sink(_on_cycle_advance)
	RunState.advance_cycle()
	_assert(RunState.cycle_index() == 1, "cycle 推进到 1")
	_assert(RunState.is_pending_respawn_intro(), "_pending_respawn_intro 置 true")
	_assert(_cycle_advance_captured.size() == 1, "sink 被调一次")
	_assert(int(_cycle_advance_captured[0]["prev"]) == 0, "sink prev=0")
	_assert(int(_cycle_advance_captured[0]["new"]) == 1, "sink new=1")


## 4. is_last_cycle 边界判定（cycle = max-1 时 true）
func _test_is_last_cycle_boundary() -> void:
	print("-- is_last_cycle 边界")
	_reset()
	_assert(not RunState.is_last_cycle(), "cycle 0 非末周期")
	RunState.advance_cycle()
	_assert(not RunState.is_last_cycle(), "cycle 1 非末周期")
	RunState.advance_cycle()
	_assert(RunState.is_last_cycle(), "cycle 2 = max-1 是末周期")


## 5. respawns_left 计算（递减）
func _test_respawns_left_calculation() -> void:
	print("-- respawns_left 递减")
	_reset()
	_assert(RunState.respawns_left() == 2, "初始 2 次")
	RunState.advance_cycle()
	_assert(RunState.respawns_left() == 1, "cycle 1 → 1 次")
	RunState.advance_cycle()
	_assert(RunState.respawns_left() == 0, "末周期 → 0 次")


## 6. draw_new_leader 标 used + 不重复抽
func _test_draw_new_leader_marks_used() -> void:
	print("-- draw_new_leader 标 used")
	_reset()
	var leader1: Dictionary = RunState.draw_new_leader()
	_assert(not leader1.is_empty(), "首次抽取非空")
	var used_after1: Array[int] = RunState.active_used_hero_ids()
	_assert(used_after1.size() == 1, "used_hero_ids 加入 1 个")
	_assert(used_after1[0] == int(leader1["id"]), "used_id 与抽取的 id 一致")
	# 再抽一次，应该是不同的 hero（在 hero_pool ≥ 2 时）
	var leader2: Dictionary = RunState.draw_new_leader()
	_assert(int(leader2["id"]) != int(leader1["id"]), "二次抽取得到不同英雄")


## 7. draw_new_leader 兜底：未使用池耗尽时允许重复
func _test_draw_new_leader_exhaust_fallback() -> void:
	print("-- draw_new_leader 池耗尽兜底")
	_reset()
	# 4 个英雄全部抽出
	var picked: Array[int] = []
	for i in range(4):
		var hero: Dictionary = RunState.draw_new_leader()
		picked.append(int(hero["id"]))
	# 第 5 次抽取：兜底允许重复
	var fallback: Dictionary = RunState.draw_new_leader()
	_assert(not fallback.is_empty(), "兜底分支返回非空（允许重复）")
	_assert(picked.has(int(fallback["id"])), "兜底返回的英雄确实在 picked 列表中")


## 8. draw_recruit 排除当前队伍成员
func _test_draw_recruit_excludes_team() -> void:
	print("-- draw_recruit 排除当前队伍")
	_reset()
	var team_ids: Array[int] = [0, 1]
	var recruit: Dictionary = RunState.draw_recruit(team_ids)
	_assert(not recruit.is_empty(), "抽取非空")
	_assert(not team_ids.has(int(recruit["id"])), "抽到的不在 team_ids 内")
	# 全员都在队 → 返回空
	var all_in_team: Array[int] = [0, 1, 2, 3]
	var empty_recruit: Dictionary = RunState.draw_recruit(all_in_team)
	_assert(empty_recruit.is_empty(), "全员在队时返回空")


## 9. consume_pending_respawn_intro 幂等清零
func _test_pending_respawn_intro_consume() -> void:
	print("-- consume_pending_respawn_intro 幂等")
	_reset()
	_assert(not RunState.consume_pending_respawn_intro(), "初始 false")
	RunState.advance_cycle()
	_assert(RunState.is_pending_respawn_intro(), "advance 后 true")
	_assert(RunState.consume_pending_respawn_intro(), "consume 返回 true")
	_assert(not RunState.consume_pending_respawn_intro(), "再 consume 返回 false（已清零）")
	_assert(not RunState.is_pending_respawn_intro(), "是非读 false")


## 10. record_camp + advance_cycle push milestone
func _test_record_camp_advance_cycle_milestone() -> void:
	print("-- record_camp + milestone push")
	_reset()
	RunState.record_camp()
	RunState.record_camp()
	RunState.record_camp()
	_assert(RunState.get_current_cycle_camp_count() == 3, "本周期累计 3 次")
	RunState.advance_cycle()
	_assert(RunState.get_current_cycle_camp_count() == 0, "advance 后归零")
	var snapshot: Array[int] = RunState.get_milestones_snapshot()
	_assert(snapshot.size() == 1, "milestones push 1 项")
	_assert(snapshot[0] == 3, "milestone 值 = 3")


## 11. check_recruit_milestone 命中 + 同周期去重
func _test_check_recruit_milestone_same_cycle_dedupe() -> void:
	print("-- check_recruit_milestone 命中 + 同周期去重")
	_reset()
	_recruit_captured = []
	RunState.register_recruit_sink(_on_recruit)
	# 第一周期扎营 2 次后推周期（push milestone=2）
	RunState.record_camp()
	RunState.record_camp()
	RunState.advance_cycle()
	# 第二周期再扎 2 次 → 命中 milestone=2 触发
	RunState.record_camp()
	RunState.record_camp()
	RunState.check_recruit_milestone([0])
	_assert(_recruit_captured.size() == 1, "首次命中触发 sink")
	_assert(int(_recruit_captured[0]["milestone"]) == 2, "milestone=2")
	# 同一周期再 check 不重复触发（已 dedupe）
	RunState.check_recruit_milestone([0])
	_assert(_recruit_captured.size() == 1, "同周期再 check 不触发")


## 12. sink 注册 / 清理
func _test_sinks_register_and_clear() -> void:
	print("-- sinks 注册 / 清理")
	_reset()
	_cycle_advance_captured = []
	_recruit_captured = []
	RunState.register_cycle_advance_sink(_on_cycle_advance)
	RunState.register_recruit_sink(_on_recruit)
	RunState.clear_sinks()
	RunState.advance_cycle()
	_assert(_cycle_advance_captured.is_empty(), "clear_sinks 后 advance 不触发 cycle sink")
	# 重新注册后 advance 又能触发
	RunState.register_cycle_advance_sink(_on_cycle_advance)
	RunState.advance_cycle()
	_assert(_cycle_advance_captured.size() == 1, "重新注册后 advance 触发 1 次")


# ─────────────────────────────────────
# 用例：据点（L1.2 Phase 1）
# ─────────────────────────────────────

## 8. 据点 set / 查询 / reset 清零
func _test_stronghold_set_query_reset() -> void:
	_reset()
	_assert(not RunState.has_stronghold(), "初始无据点")
	RunState.set_stronghold(Vector2i(7, 3))
	_assert(RunState.has_stronghold(), "set_stronghold 后 has_stronghold=true")
	_assert(RunState.stronghold_pos() == Vector2i(7, 3), "stronghold_pos 返回设定值")
	# reset（整局重开）清零
	RunState.reset()
	_assert(not RunState.has_stronghold(), "reset 后据点清零")


## 9. 据点 sink 触发：set_stronghold 命中已注册 sink
func _test_stronghold_set_sink() -> void:
	_reset()
	_stronghold_captured = []
	RunState.register_stronghold_set_sink(_on_stronghold_set)
	RunState.set_stronghold(Vector2i(2, 9))
	_assert(_stronghold_captured.size() == 1, "sink 被调一次")
	_assert(_stronghold_captured[0] == Vector2i(2, 9), "sink 收到正确坐标")
	# clear_sinks 后不再触发
	RunState.clear_sinks()
	RunState.set_stronghold(Vector2i(5, 5))
	_assert(_stronghold_captured.size() == 1, "clear_sinks 后 sink 不再触发")


## 10. 据点跨 ensure_initialized 保留（模拟 cycle reload：_initialized=true 直接 return）
func _test_stronghold_cross_init_preserved() -> void:
	_reset()
	RunState.set_stronghold(Vector2i(4, 4))
	_assert(RunState.has_stronghold(), "设定据点")
	# 再次 ensure_initialized（不 reset）—— 模拟 reload 走到 ensure_initialized 但 _initialized=true
	# 直接 return，据点字段不被清（与 _used_hero_ids / _cycle_index 同语义）
	RunState.ensure_initialized(3, _mock_hero_pool(), _make_rng(42))
	_assert(RunState.has_stronghold(), "跨 ensure_initialized（reload）据点保留")
	_assert(RunState.stronghold_pos() == Vector2i(4, 4), "据点坐标保留")


# ─────────────────────────────────────
# 用例：无据点昏迷扣命数（L1.2 Phase 3）
# ─────────────────────────────────────

## 11. consume_respawn_life 扣 1 命数（推 cycle）但不触发 reload 范式副作用
##
## 与 advance_cycle 对比：consume_respawn_life 只推 _cycle_index（命数递减），
## 不置 _pending_respawn_intro（无新场景消费）、不 push 扎营 milestone、不触发 cycle_advance_sink
func _test_consume_respawn_life() -> void:
	print("-- consume_respawn_life 扣命数不触发 reload 副作用")
	_reset()
	_cycle_advance_captured = []
	RunState.register_cycle_advance_sink(_on_cycle_advance)
	# 先扎营 2 次（验证不被 push 进 milestone）
	RunState.record_camp()
	RunState.record_camp()
	_assert(RunState.respawns_left() == 2, "初始命数 2")
	RunState.consume_respawn_life()
	_assert(RunState.cycle_index() == 1, "consume 后 cycle 推进到 1（命数递减）")
	_assert(RunState.respawns_left() == 1, "命数 2 → 1")
	_assert(not RunState.is_pending_respawn_intro(), "不置 _pending_respawn_intro（无 reload）")
	_assert(RunState.get_current_cycle_camp_count() == 2, "扎营计数不被归零（非周期推进）")
	_assert(RunState.get_milestones_snapshot().is_empty(), "不 push 扎营 milestone")
	_assert(_cycle_advance_captured.is_empty(), "不触发 cycle_advance_sink")
	# 再扣一次到末周期
	RunState.consume_respawn_life()
	_assert(RunState.respawns_left() == 0, "再扣 → 命数 0（末周期，下次走 defeat）")


## 12. consume_respawn_life 不影响据点（据点是 reset 才清，扣命数不动）
func _test_consume_respawn_life_preserves_stronghold() -> void:
	print("-- consume_respawn_life 保留据点")
	_reset()
	RunState.set_stronghold(Vector2i(6, 6))
	RunState.consume_respawn_life()
	_assert(RunState.has_stronghold(), "扣命数后据点保留")
	_assert(RunState.stronghold_pos() == Vector2i(6, 6), "据点坐标不变")


# ─────────────────────────────────────
# 辅助
# ─────────────────────────────────────

## 重置测试上下文：reset + ensure_initialized 写入 4 英雄池 / max=3 / 固定 seed RNG
func _reset() -> void:
	RunState.clear_sinks()
	RunState.reset()
	RunState.ensure_initialized(3, _mock_hero_pool(), _make_rng(42))


## 4 个英雄的 mock 池
func _mock_hero_pool() -> Array:
	return [
		{"id": 0, "name": "队长 A", "troop_type": "SWORD", "troop_quality": "T1"},
		{"id": 1, "name": "队长 B", "troop_type": "ARCHER", "troop_quality": "T1"},
		{"id": 2, "name": "队长 C", "troop_type": "SPEAR", "troop_quality": "T1"},
		{"id": 3, "name": "队长 D", "troop_type": "SWORD", "troop_quality": "T2"},
	]


## 固定 seed RNG，保证可重复性
func _make_rng(seed_value: int) -> RandomNumberGenerator:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _on_cycle_advance(prev: int, new_cycle: int) -> void:
	_cycle_advance_captured.append({"prev": prev, "new": new_cycle})


func _on_recruit(hero_dict: Dictionary, milestone: int) -> void:
	_recruit_captured.append({"hero": hero_dict, "milestone": milestone})


func _on_stronghold_set(pos: Vector2i) -> void:
	_stronghold_captured.append(pos)


func _assert(cond: bool, msg: String) -> void:
	if cond:
		print("  ✓ " + msg)
	else:
		printerr("  ✗ " + msg)
		_failed += 1
