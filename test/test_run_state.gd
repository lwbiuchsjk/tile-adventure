extends SceneTree
## RunState 跨场景整局态冒烟测试（MVP-ε P3 + L1.3a 阶段 D 改写）
##
## 运行：tools/run_godot.ps1 --headless -s test/test_run_state.gd
##
## 验证范围（RunState 核心 API，L1.3a 阶段 D cycle 范式退役后）：
##   1. ensure_initialized / reset 生命周期（cycle_index 冻结 0 / 命数 K 注入）
##   2. 独立命数 respawns_left / consume_respawn_life（脱钩 cycle）
##   3. 英雄池抽取 draw_new_leader / draw_recruit / used_hero_ids 跟踪
##   4. 重生事件占位 consume_pending_respawn_intro 幂等清零（冻结保留）
##   5. 扎营计数 record_camp / get_current_cycle_camp_count / total_camp_count
##   6. recruit 适配 check_recruit_milestone（按 interval 命中 + lifetime 去重 + 招募次数硬上限）
##   7. sink 注册 / 清理（recruit / stronghold）

var _failed: int = 0

## sink 捕获
var _recruit_captured: Array[Dictionary] = []
var _stronghold_captured: Array[Vector2i] = []


func _init() -> void:
	print("=== RunState 冒烟测试 ===")

	_test_initial_state_after_init()
	_test_reset_clears_state()
	_test_respawns_left_calculation()
	_test_draw_new_leader_marks_used()
	_test_draw_new_leader_exhaust_fallback()
	_test_draw_recruit_excludes_team()
	_test_pending_respawn_intro_consume()
	_test_record_camp()
	_test_check_recruit_milestone_interval_dedupe()
	_test_recruit_max_count_cap()
	_test_recruit_sink_clear()
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
	_assert(RunState.cycle_index() == 0, "cycle_index 冻结为 0")
	_assert(RunState.respawns_left() == 3, "respawns_left = 独立命数 K（默认 3，脱钩 cycle）")
	_assert(not RunState.is_pending_respawn_intro(), "重生占位标志初始 false")
	_assert(RunState.get_current_cycle_camp_count() == 0, "扎营计数 = 0")
	_assert(RunState.total_camp_count() == 0, "lifetime 主时钟 = 0")


## 2. reset 清整局态，下次 ensure_initialized 可重新写入
func _test_reset_clears_state() -> void:
	print("-- reset 清整局态")
	_reset()
	RunState.record_camp()
	RunState.draw_new_leader()
	_assert(RunState.get_current_cycle_camp_count() == 1, "扎营 1 次")
	_assert(not RunState.active_used_hero_ids().is_empty(), "used_hero_ids 非空")
	RunState.reset()
	_assert(RunState.get_current_cycle_camp_count() == 0, "reset 后扎营计数归零")
	_assert(RunState.total_camp_count() == 0, "reset 后 lifetime 主时钟归零")
	_assert(RunState.active_used_hero_ids().is_empty(), "used_hero_ids 清空")
	# 再次 ensure_initialized 写入新数据
	RunState.ensure_initialized(5, _mock_hero_pool(), _make_rng(42))
	_assert(RunState.max_cycles() == 5, "reset 后 ensure_initialized 写入 max=5")


## 3. respawns_left 递减（L1.3a：独立命数，consume_respawn_life 扣减、脱钩 cycle）
func _test_respawns_left_calculation() -> void:
	print("-- respawns_left 递减（独立命数）")
	_reset()
	_assert(RunState.respawns_left() == 3, "初始 3 次（独立命数 K）")
	RunState.consume_respawn_life()
	_assert(RunState.respawns_left() == 2, "consume → 2 次")
	RunState.consume_respawn_life()
	RunState.consume_respawn_life()
	_assert(RunState.respawns_left() == 0, "扣到 0")
	RunState.consume_respawn_life()
	_assert(RunState.respawns_left() == 0, "归零后再扣 maxi 兜底为 0")


## 4. draw_new_leader 标 used + 不重复抽
func _test_draw_new_leader_marks_used() -> void:
	print("-- draw_new_leader 标 used")
	_reset()
	var leader1: Dictionary = RunState.draw_new_leader()
	_assert(not leader1.is_empty(), "首次抽取非空")
	var used_after1: Array[int] = RunState.active_used_hero_ids()
	_assert(used_after1.size() == 1, "used_hero_ids 加入 1 个")
	_assert(used_after1[0] == int(leader1["id"]), "used_id 与抽取的 id 一致")
	var leader2: Dictionary = RunState.draw_new_leader()
	_assert(int(leader2["id"]) != int(leader1["id"]), "二次抽取得到不同英雄")


## 5. draw_new_leader 兜底：未使用池耗尽时允许重复
func _test_draw_new_leader_exhaust_fallback() -> void:
	print("-- draw_new_leader 池耗尽兜底")
	_reset()
	var picked: Array[int] = []
	for i in range(4):
		var hero: Dictionary = RunState.draw_new_leader()
		picked.append(int(hero["id"]))
	var fallback: Dictionary = RunState.draw_new_leader()
	_assert(not fallback.is_empty(), "兜底分支返回非空（允许重复）")
	_assert(picked.has(int(fallback["id"])), "兜底返回的英雄确实在 picked 列表中")


## 6. draw_recruit 排除当前队伍成员
func _test_draw_recruit_excludes_team() -> void:
	print("-- draw_recruit 排除当前队伍")
	_reset()
	var team_ids: Array[int] = [0, 1]
	var recruit: Dictionary = RunState.draw_recruit(team_ids)
	_assert(not recruit.is_empty(), "抽取非空")
	_assert(not team_ids.has(int(recruit["id"])), "抽到的不在 team_ids 内")
	var all_in_team: Array[int] = [0, 1, 2, 3]
	var empty_recruit: Dictionary = RunState.draw_recruit(all_in_team)
	_assert(empty_recruit.is_empty(), "全员在队时返回空")


## 7. consume_pending_respawn_intro 幂等清零（L1.3a 阶段 D：advance_cycle 退役，直接置位测幂等）
func _test_pending_respawn_intro_consume() -> void:
	print("-- consume_pending_respawn_intro 幂等")
	_reset()
	_assert(not RunState.consume_pending_respawn_intro(), "初始 false")
	# 生产中 _pending_respawn_intro 已无人置位（冻结保留）；测试直接置位验证 consume 幂等
	RunState._pending_respawn_intro = true
	_assert(RunState.is_pending_respawn_intro(), "置位后 true")
	_assert(RunState.consume_pending_respawn_intro(), "consume 返回 true")
	_assert(not RunState.consume_pending_respawn_intro(), "再 consume 返回 false（已清零）")
	_assert(not RunState.is_pending_respawn_intro(), "只读查询 false")


## 8. record_camp 累加（per-camp 计数 + lifetime 主时钟）
func _test_record_camp() -> void:
	print("-- record_camp 累加")
	_reset()
	RunState.record_camp()
	RunState.record_camp()
	RunState.record_camp()
	_assert(RunState.get_current_cycle_camp_count() == 3, "扎营累计 3 次")
	_assert(RunState.total_camp_count() == 3, "lifetime 主时钟 = 3")


## 9. check_recruit_milestone 适配（L1.3a 阶段 D：按 interval 命中 + lifetime 去重）
func _test_check_recruit_milestone_interval_dedupe() -> void:
	print("-- check_recruit_milestone 按 interval 命中 + lifetime 去重")
	_reset()
	_recruit_captured = []
	RunState.register_recruit_sink(_on_recruit)
	# 守卫：interval<=0 不触发
	RunState.check_recruit_milestone([0], 0, 10)
	_assert(_recruit_captured.is_empty(), "interval<=0 不触发")
	# 守卫：扎营 0 次不触发（_total_camp_count==0）
	RunState.check_recruit_milestone([0], 2, 10)
	_assert(_recruit_captured.is_empty(), "扎营 0 次不触发")
	# interval=2：扎营到第 2 次命中
	RunState.record_camp()  # total=1
	RunState.check_recruit_milestone([0], 2, 10)
	_assert(_recruit_captured.is_empty(), "扎营 1 次未命中 interval=2")
	RunState.record_camp()  # total=2
	RunState.check_recruit_milestone([0], 2, 10)
	_assert(_recruit_captured.size() == 1, "扎营 2 次命中 interval=2")
	_assert(int(_recruit_captured[0]["milestone"]) == 2, "milestone=2（全局扎营计数）")
	# 同一扎营计数再 check 不重复（lifetime 去重）
	RunState.check_recruit_milestone([0], 2, 10)
	_assert(_recruit_captured.size() == 1, "同扎营计数再 check 不触发（去重）")
	# 扎营到第 4 次再命中
	RunState.record_camp()  # 3
	RunState.record_camp()  # 4
	RunState.check_recruit_milestone([0], 2, 10)
	_assert(_recruit_captured.size() == 2, "扎营 4 次再命中")
	_assert(int(_recruit_captured[1]["milestone"]) == 4, "milestone=4")


## 9b. 招募次数硬上限 max_count（到上限即停，避免无限扎营抽干池）
func _test_recruit_max_count_cap() -> void:
	print("-- check_recruit_milestone 招募次数硬上限")
	_reset()
	_recruit_captured = []
	RunState.register_recruit_sink(_on_recruit)
	# max_count=1：interval=2 扎营 2 次招 1 次，第 4 次到上限不再招
	RunState.record_camp()
	RunState.record_camp()  # total=2
	RunState.check_recruit_milestone([0], 2, 1)
	_assert(_recruit_captured.size() == 1, "扎营 2 次招 1 次")
	RunState.record_camp()
	RunState.record_camp()  # total=4
	RunState.check_recruit_milestone([0], 2, 1)
	_assert(_recruit_captured.size() == 1, "已达上限 1，扎营 4 次不再招")
	# max_count=0：从不招
	_reset()
	_recruit_captured = []
	RunState.register_recruit_sink(_on_recruit)
	RunState.record_camp()
	RunState.record_camp()
	RunState.check_recruit_milestone([0], 2, 0)
	_assert(_recruit_captured.is_empty(), "max_count=0 从不招")


## 10. clear_sinks 清 recruit sink
func _test_recruit_sink_clear() -> void:
	print("-- clear_sinks 清 recruit sink")
	_reset()
	_recruit_captured = []
	RunState.register_recruit_sink(_on_recruit)
	RunState.clear_sinks()
	# clear 后命中 interval 也不 emit（sink 已清；仍会标去重 + push_warning）
	RunState.record_camp()
	RunState.record_camp()
	RunState.check_recruit_milestone([0], 2, 10)
	_assert(_recruit_captured.is_empty(), "clear_sinks 后命中不触发（sink 已清）")


# ─────────────────────────────────────
# 用例：据点（L1.2 Phase 1）
# ─────────────────────────────────────

## 11. 据点 set / 查询 / reset 清零
func _test_stronghold_set_query_reset() -> void:
	_reset()
	_assert(not RunState.has_stronghold(), "初始无据点")
	RunState.set_stronghold(Vector2i(7, 3))
	_assert(RunState.has_stronghold(), "set_stronghold 后 has_stronghold=true")
	_assert(RunState.stronghold_pos() == Vector2i(7, 3), "stronghold_pos 返回设定值")
	RunState.reset()
	_assert(not RunState.has_stronghold(), "reset 后据点清零")


## 12. 据点 sink 触发：set_stronghold 命中已注册 sink
func _test_stronghold_set_sink() -> void:
	_reset()
	_stronghold_captured = []
	RunState.register_stronghold_set_sink(_on_stronghold_set)
	RunState.set_stronghold(Vector2i(2, 9))
	_assert(_stronghold_captured.size() == 1, "sink 被调一次")
	_assert(_stronghold_captured[0] == Vector2i(2, 9), "sink 收到正确坐标")
	RunState.clear_sinks()
	RunState.set_stronghold(Vector2i(5, 5))
	_assert(_stronghold_captured.size() == 1, "clear_sinks 后 sink 不再触发")


## 13. 据点跨 ensure_initialized 保留（_initialized=true 直接 return）
func _test_stronghold_cross_init_preserved() -> void:
	_reset()
	RunState.set_stronghold(Vector2i(4, 4))
	_assert(RunState.has_stronghold(), "设定据点")
	# 再次 ensure_initialized（不 reset）—— _initialized=true 直接 return，据点字段不被清
	RunState.ensure_initialized(3, _mock_hero_pool(), _make_rng(42))
	_assert(RunState.has_stronghold(), "跨 ensure_initialized 据点保留")
	_assert(RunState.stronghold_pos() == Vector2i(4, 4), "据点坐标保留")


# ─────────────────────────────────────
# 用例：无据点昏迷扣命数（L1.2 Phase 3 / L1.3a 阶段 B）
# ─────────────────────────────────────

## 14. consume_respawn_life 扣 1 命数（独立计数，脱钩 cycle）不触发 reload 范式副作用
func _test_consume_respawn_life() -> void:
	print("-- consume_respawn_life 扣独立命数不触发 reload 副作用")
	_reset()
	RunState.record_camp()
	RunState.record_camp()
	_assert(RunState.respawns_left() == 3, "初始命数 3（独立计数 K）")
	RunState.consume_respawn_life()
	_assert(RunState.cycle_index() == 0, "consume 不推 cycle（脱钩，cycle 冻结 0）")
	_assert(RunState.respawns_left() == 2, "命数 3 → 2")
	_assert(not RunState.is_pending_respawn_intro(), "不置 _pending_respawn_intro（无 reload）")
	_assert(RunState.get_current_cycle_camp_count() == 2, "扎营计数不被归零")
	# 扣到命数耗尽
	RunState.consume_respawn_life()
	RunState.consume_respawn_life()
	_assert(RunState.respawns_left() == 0, "扣到命数 0（下次昏迷走 defeat）")


## 15. consume_respawn_life 不影响据点
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
