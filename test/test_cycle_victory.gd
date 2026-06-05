extends SceneTree
## 周期胜利目标 MVP 冒烟测试（L1.3 持久 slot 战场参与 · 入口 5）
##
## 运行：tools/run_godot.ps1 --headless -s test/test_cycle_victory.gd
##
## 设计原文：tile-advanture-design/周期胜利目标_MVP.md §8.1
##
## 验证范围（headless 可测）：
##   A. TroopData.raise_quality_one_step —— 升一级 + SSR 硬封顶 + exp 归零
##   B. RunState.advance_cycle_on_victory —— cycle+1 / 保留队长快照 / pending 标志 / quality+1 / 不动 used_hero_ids
##
## L1.3a 阶段 B：原 C 段「VictoryJudge 占核心分流」已随占核心胜负语义移除而删除（见 test_m8_victory_judge
## 新口径）；本文件 A/B 段测的 advance_cycle_on_victory 在阶段 D cycle 范式退役时整体清理。
##
## 不在本测覆盖（依赖 SceneTree / WorldMap / OverlayTransitionUI 时序，留桌面跑测）：
##   - PlayerLifecycle.setup 快照重建队长（满血恢复 / draw_new_leader 分流）
##   - 黑屏过渡 phase 时序 / 末周期 VictoryUI 表现

var _failed: int = 0


func _init() -> void:
	print("=== 周期胜利目标 冒烟测试 ===")

	# A. TroopData 升品封顶
	_test_raise_quality_one_step()
	_test_raise_quality_cap_ssr()
	_test_raise_quality_resets_exp()

	# B. RunState 周期胜利推进
	_test_advance_victory_cycle_and_pending()
	_test_advance_victory_keeps_leader()
	_test_advance_victory_quality_plus_one_capped()
	_test_advance_victory_vs_coma_used_ids()

	if _failed > 0:
		printerr("✗ 共 %d 项失败" % _failed)
		quit(1)
	else:
		print("✓ 全部通过")
		quit(0)


# ─────────────────────────────────────
# A. TroopData.raise_quality_one_step
# ─────────────────────────────────────

## R → SR → SSR 逐级提升，返回 true
func _test_raise_quality_one_step() -> void:
	print("-- raise_quality_one_step 逐级提升")
	var troop: TroopData = TroopData.new()
	troop.quality = TroopData.Quality.R
	var r1: bool = troop.raise_quality_one_step()
	_assert(r1, "R 升级返回 true")
	_assert(troop.quality == TroopData.Quality.SR, "R → SR")
	var r2: bool = troop.raise_quality_one_step()
	_assert(r2, "SR 升级返回 true")
	_assert(troop.quality == TroopData.Quality.SSR, "SR → SSR")


## SSR 硬封顶：不再提升，返回 false
func _test_raise_quality_cap_ssr() -> void:
	print("-- raise_quality_one_step SSR 硬封顶")
	var troop: TroopData = TroopData.new()
	troop.quality = TroopData.Quality.SSR
	var r: bool = troop.raise_quality_one_step()
	_assert(not r, "SSR 升级返回 false（封顶）")
	_assert(troop.quality == TroopData.Quality.SSR, "SSR 维持 SSR，不越界")


## 升品后 exp 归零（与 add_exp 升品语义一致）
func _test_raise_quality_resets_exp() -> void:
	print("-- raise_quality_one_step 升品归零 exp")
	var troop: TroopData = TroopData.new()
	troop.quality = TroopData.Quality.R
	troop.exp = 80
	troop.raise_quality_one_step()
	_assert(troop.exp == 0, "升品后 exp 归零")
	# SSR 封顶时不改 exp（不升品）
	var ssr: TroopData = TroopData.new()
	ssr.quality = TroopData.Quality.SSR
	ssr.exp = 50
	ssr.raise_quality_one_step()
	_assert(ssr.exp == 50, "SSR 封顶不升品时 exp 维持")


# ─────────────────────────────────────
# B. RunState.advance_cycle_on_victory
# ─────────────────────────────────────

## cycle_index +1 + 置 _pending_cycle_victory_intro（不置 respawn）
func _test_advance_victory_cycle_and_pending() -> void:
	print("-- advance_cycle_on_victory 推进周期 + pending 标志")
	_reset_run_state()
	var leader: CharacterData = _make_leader(1, TroopData.Quality.R, TroopData.TroopType.SWORD)
	RunState.advance_cycle_on_victory(leader)
	_assert(RunState.cycle_index() == 1, "cycle 推进到 1")
	_assert(not RunState.is_pending_respawn_intro(), "不置昏迷重生标志")
	# consume 周期胜利标志：首次 true，再 consume false（幂等清零）
	_assert(RunState.consume_pending_cycle_victory_intro(), "consume 周期胜利标志返回 true")
	_assert(not RunState.consume_pending_cycle_victory_intro(), "再 consume 返回 false（已清零）")


## 队长 hero_id + 兵种快照保留
func _test_advance_victory_keeps_leader() -> void:
	print("-- advance_cycle_on_victory 队长快照保留")
	_reset_run_state()
	var leader: CharacterData = _make_leader(7, TroopData.Quality.SR, TroopData.TroopType.CAVALRY)
	RunState.advance_cycle_on_victory(leader)
	var snap: Dictionary = RunState.get_victory_leader_snapshot()
	_assert(int(snap.get("hero_id", -1)) == 7, "快照 hero_id 保留 = 7")
	_assert(int(snap.get("troop_type", -1)) == TroopData.TroopType.CAVALRY, "快照兵种保留 CAVALRY")


## quality+1 写入快照，SSR 封顶
func _test_advance_victory_quality_plus_one_capped() -> void:
	print("-- advance_cycle_on_victory quality+1 + 封顶")
	_reset_run_state()
	var leader_r: CharacterData = _make_leader(1, TroopData.Quality.R, TroopData.TroopType.BOW)
	RunState.advance_cycle_on_victory(leader_r)
	var snap_r: Dictionary = RunState.get_victory_leader_snapshot()
	_assert(int(snap_r.get("quality", -1)) == TroopData.Quality.SR, "R 队长推进后快照 quality=SR")
	# SSR 队长推进 → 快照仍 SSR（封顶）
	_reset_run_state()
	var leader_ssr: CharacterData = _make_leader(2, TroopData.Quality.SSR, TroopData.TroopType.SHIELD)
	RunState.advance_cycle_on_victory(leader_ssr)
	var snap_ssr: Dictionary = RunState.get_victory_leader_snapshot()
	_assert(int(snap_ssr.get("quality", -1)) == TroopData.Quality.SSR, "SSR 队长推进后快照仍 SSR（封顶）")


## 胜利推进不动 _used_hero_ids；对照昏迷 draw_new_leader 加 used
func _test_advance_victory_vs_coma_used_ids() -> void:
	print("-- 胜利推进 vs 昏迷重生 used_hero_ids 对照")
	_reset_run_state()
	var leader: CharacterData = _make_leader(5, TroopData.Quality.R, TroopData.TroopType.SWORD)
	var used_before: int = RunState.active_used_hero_ids().size()
	RunState.advance_cycle_on_victory(leader)
	_assert(RunState.active_used_hero_ids().size() == used_before, "胜利推进保留队长，不动 _used_hero_ids")
	# 对照：draw_new_leader（昏迷重生路径）会把抽到的队长标 used
	var before_draw: int = RunState.active_used_hero_ids().size()
	RunState.draw_new_leader()
	_assert(RunState.active_used_hero_ids().size() == before_draw + 1, "昏迷重生 draw_new_leader 加 used")


# ─────────────────────────────────────
# 辅助
# ─────────────────────────────────────

## 重置 RunState：reset + ensure_initialized 写入 4 英雄池 / max=3 / 固定 seed
func _reset_run_state() -> void:
	RunState.clear_sinks()
	RunState.reset()
	RunState.ensure_initialized(3, _mock_hero_pool(), _make_rng(42))


## 构造一个队长 CharacterData（带 troop）
func _make_leader(hero_id: int, quality: TroopData.Quality, troop_type: TroopData.TroopType) -> CharacterData:
	var ch: CharacterData = CharacterData.new()
	ch.id = 1
	ch.hero_id = hero_id
	var troop: TroopData = TroopData.new()
	troop.quality = quality
	troop.troop_type = troop_type
	ch.troop = troop
	return ch


## 4 个英雄的 mock 池
func _mock_hero_pool() -> Array:
	return [
		{"id": 0, "name": "队长 A", "troop_type": "SWORD", "troop_quality": "R"},
		{"id": 1, "name": "队长 B", "troop_type": "BOW", "troop_quality": "R"},
		{"id": 2, "name": "队长 C", "troop_type": "SPEAR", "troop_quality": "SR"},
		{"id": 3, "name": "队长 D", "troop_type": "CAVALRY", "troop_quality": "SR"},
	]


## 固定 seed RNG
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
