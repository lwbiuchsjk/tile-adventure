extends SceneTree
## 持久 slot 援军纯数据逻辑冒烟测试（持久slot援军_MVP / L1.2）
##
## 运行：tools/run_godot.ps1 --headless -s test/test_reinforcement.gd
##
## 验证范围（合议 §8.2 / L1.2 §7.1 三段纯数据逻辑 + 敌方援军_MVP §8.1）：
##   T1 抽样快照  —— ReinforcementRoster.build_config / sample：数量范围 / 品质区间 / 兵种来源 / 未配置返回空
##   T2 触发判定  —— ReinforcementRoster.is_in_trigger_range：曼哈顿点到矩形最近距离边界
##   T3 储备扣减  —— ReinforcementRoster.apply_consumption：已入场条目移除 / 未入场条目保留
##   T4 敌方独立表（L1.4）—— 敌方表数值独立于玩家表（同 type×P 区间不同；敌方配核心行玩家表无）
##   T6 工厂阵营化（L1.4）—— make_reinforcement_unit：默认 PLAYER / 显式 ENEMY_1；source_level=null / character=null

var _failed: int = 0


func _init() -> void:
	print("=== 持久 slot 援军冒烟测试 ===")

	_test_build_config()
	_test_build_config_swaps_reversed_range()
	_test_sample_count_range()
	_test_sample_quality_range()
	_test_sample_troop_type_from_pool()
	_test_sample_unconfigured_returns_empty()
	_test_sample_count_min_eq_max_deterministic()
	_test_trigger_range_inside_arena()
	_test_trigger_range_boundary()
	_test_trigger_range_diagonal()
	_test_consumption_full()
	_test_consumption_partial_retains()
	_test_enemy_table_independent_strength()
	_test_make_reinforcement_unit_faction()

	if _failed > 0:
		printerr("✗ 共 %d 项失败" % _failed)
		quit(1)
	else:
		print("✓ 全部通过")
		quit(0)


# ─────────────────────────────────────
# T1 抽样快照
# ─────────────────────────────────────

## build_config 把原始行解析为嵌套查表字典
func _test_build_config() -> void:
	print("-- build_config 嵌套查表")
	var cfg: Dictionary = ReinforcementRoster.build_config(_mock_garrison_rows())
	_assert(cfg.has(1), "解析出 slot_type=1（城镇）")
	var by_pressure: Dictionary = cfg[1] as Dictionary
	_assert(by_pressure.has(0), "城镇含 P=0")
	var entry: Dictionary = by_pressure[0] as Dictionary
	_assert(int(entry["count_min"]) == 2 and int(entry["count_max"]) == 2, "城镇 P0 数量 2-2")
	_assert(int(entry["quality_min"]) == 0 and int(entry["quality_max"]) == 0, "城镇 P0 品质 0-0")


## build_config 对写反的区间（min>max）交换 + 告警（codex P3 守卫）
func _test_build_config_swaps_reversed_range() -> void:
	print("-- build_config 反向区间交换守卫（下面 2 条 push_warning 为预期）")
	var rows: Array = [
		{"slot_type": "0", "pressure_level": "0", "count_min": "3", "count_max": "1", "quality_min": "2", "quality_max": "0"},
	]
	var cfg: Dictionary = ReinforcementRoster.build_config(rows)
	var entry: Dictionary = (cfg[0] as Dictionary)[0] as Dictionary
	_assert(int(entry["count_min"]) == 1 and int(entry["count_max"]) == 3, "count 区间从 3-1 交换为 1-3")
	_assert(int(entry["quality_min"]) == 0 and int(entry["quality_max"]) == 2, "quality 区间从 2-0 交换为 0-2")


## sample 数量落在 [count_min, count_max]（多次抽样统计）
func _test_sample_count_range() -> void:
	print("-- sample 数量范围")
	var cfg: Dictionary = ReinforcementRoster.build_config(_mock_garrison_rows())
	var rng: RandomNumberGenerator = _seeded_rng(1)
	# 城镇 P1 = count 2-3
	for i in range(50):
		var roster: Array = ReinforcementRoster.sample(1, 1, cfg, _mock_pool_rows(), rng)
		if roster.size() < 2 or roster.size() > 3:
			_assert(false, "城镇 P1 数量越界：%d（应 2-3）" % roster.size())
			return
	_assert(true, "城镇 P1 数量 50 次均落在 2-3")


## sample 品质落在 [quality_min, quality_max]
func _test_sample_quality_range() -> void:
	print("-- sample 品质区间")
	var cfg: Dictionary = ReinforcementRoster.build_config(_mock_garrison_rows())
	var rng: RandomNumberGenerator = _seeded_rng(2)
	# 城镇 P2 = quality 1-1（恒 SR）
	for i in range(50):
		var roster: Array = ReinforcementRoster.sample(1, 2, cfg, _mock_pool_rows(), rng)
		for entry_v in roster:
			var entry: Dictionary = entry_v as Dictionary
			if int(entry["quality"]) != 1:
				_assert(false, "城镇 P2 品质越界：%d（应恒 1）" % int(entry["quality"]))
				return
	_assert(true, "城镇 P2 品质 50 次均为 1（SR）")


## sample 抽出的 troop_type 必来自池
func _test_sample_troop_type_from_pool() -> void:
	print("-- sample 兵种来源")
	var cfg: Dictionary = ReinforcementRoster.build_config(_mock_garrison_rows())
	var rng: RandomNumberGenerator = _seeded_rng(3)
	# mock 池只有 troop_type 0 与 3
	var allowed: Array[int] = [0, 3]
	for i in range(50):
		var roster: Array = ReinforcementRoster.sample(1, 1, cfg, _mock_pool_rows(), rng)
		for entry_v in roster:
			var entry: Dictionary = entry_v as Dictionary
			if not allowed.has(int(entry["troop_type"])):
				_assert(false, "兵种 %d 不在池内" % int(entry["troop_type"]))
				return
	_assert(true, "兵种 50 次均来自池 {0,3}")


## 未配置的 type×P 返回空数组
func _test_sample_unconfigured_returns_empty() -> void:
	print("-- 未配置 type×P 返回空")
	var cfg: Dictionary = ReinforcementRoster.build_config(_mock_garrison_rows())
	var rng: RandomNumberGenerator = _seeded_rng(4)
	# mock 配置无 slot_type=2（核心）行
	var roster: Array = ReinforcementRoster.sample(2, 0, cfg, _mock_pool_rows(), rng)
	_assert(roster.is_empty(), "核心（未配置）返回空 roster")
	# 配置内无 P=9
	var roster2: Array = ReinforcementRoster.sample(1, 9, cfg, _mock_pool_rows(), rng)
	_assert(roster2.is_empty(), "城镇 P9（未配置）返回空 roster")


## count_min==count_max 时数量确定
func _test_sample_count_min_eq_max_deterministic() -> void:
	print("-- count_min==count_max 数量确定")
	var cfg: Dictionary = ReinforcementRoster.build_config(_mock_garrison_rows())
	var rng: RandomNumberGenerator = _seeded_rng(5)
	# 村庄 P0 = count 1-1
	for i in range(20):
		var roster: Array = ReinforcementRoster.sample(0, 0, cfg, _mock_pool_rows(), rng)
		if roster.size() != 1:
			_assert(false, "村庄 P0 数量应恒 1，实得 %d" % roster.size())
			return
	_assert(true, "村庄 P0 数量恒 1")


# ─────────────────────────────────────
# T2 触发判定
# ─────────────────────────────────────

## slot 在 arena 内 → 距离 0 → 命中
func _test_trigger_range_inside_arena() -> void:
	print("-- 触发判定：slot 在 arena 内")
	var arena: Rect2i = Rect2i(5, 5, 7, 7)  # 覆盖 x∈[5,11] y∈[5,11]
	_assert(ReinforcementRoster.is_in_trigger_range(Vector2i(8, 8), arena, 2), "arena 内 slot 命中")
	_assert(ReinforcementRoster.is_in_trigger_range(Vector2i(5, 5), arena, 0), "arena 角格 slot 即使 range=0 也命中")


## 边界值：恰好 == range 命中，range+1 不命中
func _test_trigger_range_boundary() -> void:
	print("-- 触发判定：边界值")
	var arena: Rect2i = Rect2i(5, 5, 7, 7)  # max_x=11 max_y=11
	# slot 在 arena 右侧水平方向
	_assert(ReinforcementRoster.is_in_trigger_range(Vector2i(13, 8), arena, 2), "距 arena 右边 2 格 → range=2 命中")
	_assert(not ReinforcementRoster.is_in_trigger_range(Vector2i(14, 8), arena, 2), "距 arena 右边 3 格 → range=2 不命中")
	# slot 在 arena 左侧
	_assert(ReinforcementRoster.is_in_trigger_range(Vector2i(3, 8), arena, 2), "距 arena 左边 2 格 → range=2 命中")


## 对角方向：曼哈顿距离 = dx+dy
func _test_trigger_range_diagonal() -> void:
	print("-- 触发判定：对角曼哈顿")
	var arena: Rect2i = Rect2i(5, 5, 7, 7)  # 右下角 (11,11)
	# slot 在右下对角：(12,12) → dx=1 dy=1 → 距离 2
	_assert(ReinforcementRoster.is_in_trigger_range(Vector2i(12, 12), arena, 2), "右下对角距离 2 → range=2 命中")
	_assert(not ReinforcementRoster.is_in_trigger_range(Vector2i(13, 13), arena, 2), "右下对角 (13,13) 距离 4 → range=2 不命中")


# ─────────────────────────────────────
# T3 储备扣减
# ─────────────────────────────────────

## 全部入场 → roster 清空
func _test_consumption_full() -> void:
	print("-- 扣减：全部入场清空")
	var roster: Array = [
		{"troop_type": 0, "quality": 0},
		{"troop_type": 1, "quality": 0},
		{"troop_type": 3, "quality": 1},
	]
	var consumed: Array = [roster[0], roster[1], roster[2]]
	ReinforcementRoster.apply_consumption(roster, consumed)
	_assert(roster.is_empty(), "全部入场后 roster 清空")


## 部分入场（1 条未入场）→ 未入场条目保留
func _test_consumption_partial_retains() -> void:
	print("-- 扣减：部分入场保留未入场")
	var kept: Dictionary = {"troop_type": 4, "quality": 0}
	var roster: Array = [
		{"troop_type": 0, "quality": 0},
		{"troop_type": 1, "quality": 0},
		kept,  # 这条未入场（如找不到空格）
	]
	# consumed 只含前两条
	var consumed: Array = [roster[0], roster[1]]
	ReinforcementRoster.apply_consumption(roster, consumed)
	_assert(roster.size() == 1, "扣减后剩 1 条未入场条目")
	if roster.size() == 1:
		var remain: Dictionary = roster[0] as Dictionary
		_assert(int(remain["troop_type"]) == 4, "保留的是未入场的盾兵（troop_type=4）")


# ─────────────────────────────────────
# T4 敌方独立表（敌方援军_MVP / L1.4）
# ─────────────────────────────────────

## 敌方表数值独立于玩家表：同 type×P 抽样区间不同 + 敌方配核心行（玩家 mock 表无）
func _test_enemy_table_independent_strength() -> void:
	print("-- 敌方独立表：数值独立于玩家表")
	var player_cfg: Dictionary = ReinforcementRoster.build_config(_mock_garrison_rows())
	var enemy_cfg: Dictionary = ReinforcementRoster.build_config(_mock_enemy_garrison_rows())
	var rng: RandomNumberGenerator = _seeded_rng(11)
	# 玩家 mock 表无核心（slot_type=2）行 → 返回空；敌方表有核心 P0 = count 3-4 / quality 1-1
	var player_core: Array = ReinforcementRoster.sample(2, 0, player_cfg, _mock_pool_rows(), rng)
	_assert(player_core.is_empty(), "玩家表无核心行 → 核心抽样空")
	for i in range(50):
		var enemy_core: Array = ReinforcementRoster.sample(2, 0, enemy_cfg, _mock_pool_rows(), rng)
		if enemy_core.size() < 3 or enemy_core.size() > 4:
			_assert(false, "敌方核心 P0 数量越界：%d（应 3-4）" % enemy_core.size())
			return
		for entry_v in enemy_core:
			var entry: Dictionary = entry_v as Dictionary
			if int(entry["quality"]) != 1:
				_assert(false, "敌方核心 P0 品质越界：%d（应恒 1）" % int(entry["quality"]))
				return
	_assert(true, "敌方核心 P0 50 次均落在 count 3-4 / quality 1（独立于玩家表）")


# ─────────────────────────────────────
# T6 工厂阵营化（敌方援军_MVP / L1.4）
# ─────────────────────────────────────

## make_reinforcement_unit：默认 PLAYER / 显式 ENEMY_1；两者 source_level=null + character=null
func _test_make_reinforcement_unit_faction() -> void:
	print("-- 工厂阵营化：默认 PLAYER / 显式 ENEMY_1")
	var troop_p: TroopData = TroopData.new()
	troop_p.troop_type = TroopData.TroopType.SWORD
	troop_p.quality = TroopData.Quality.R
	# 默认阵营 = PLAYER（不破坏 L1.2 调用）
	var unit_p: BattleUnit = BattleDeploy.make_reinforcement_unit(troop_p, Vector2i(3, 3), {})
	_assert(unit_p.owner_faction == Faction.PLAYER, "默认阵营 = PLAYER")
	_assert(unit_p.character == null, "玩家援军 character == null")
	_assert(unit_p.source_level == null, "玩家援军 source_level == null")
	# 显式 ENEMY_1（敌方援军，AI 驱动）
	var troop_e: TroopData = TroopData.new()
	troop_e.troop_type = TroopData.TroopType.SWORD
	troop_e.quality = TroopData.Quality.SR
	var unit_e: BattleUnit = BattleDeploy.make_reinforcement_unit(troop_e, Vector2i(4, 4), {}, Faction.ENEMY_1)
	_assert(unit_e.owner_faction == Faction.ENEMY_1, "显式阵营 = ENEMY_1")
	_assert(unit_e.character == null, "敌方援军 character == null")
	_assert(unit_e.source_level == null, "敌方援军 source_level == null（不进 _level_slots / 不计周期胜利口径）")


# ─────────────────────────────────────
# 辅助 / mock 数据
# ─────────────────────────────────────

## mock garrison_config 行（村庄 P0 + 城镇 P0/1/2；无核心行）
func _mock_garrison_rows() -> Array:
	return [
		{"slot_type": "0", "pressure_level": "0", "count_min": "1", "count_max": "1", "quality_min": "0", "quality_max": "0"},
		{"slot_type": "1", "pressure_level": "0", "count_min": "2", "count_max": "2", "quality_min": "0", "quality_max": "0"},
		{"slot_type": "1", "pressure_level": "1", "count_min": "2", "count_max": "3", "quality_min": "0", "quality_max": "1"},
		{"slot_type": "1", "pressure_level": "2", "count_min": "3", "count_max": "3", "quality_min": "1", "quality_max": "1"},
	]


## mock enemy_garrison_config 行（含核心 P0 = count 3-4 / quality 1-1，区别于玩家表）
func _mock_enemy_garrison_rows() -> Array:
	return [
		{"slot_type": "2", "pressure_level": "0", "count_min": "3", "count_max": "4", "quality_min": "1", "quality_max": "1"},
	]


## mock town_troop_pool 行（仅 troop_type 0 与 3）
func _mock_pool_rows() -> Array:
	return [
		{"troop_type": "0", "quality": "0", "weight": "3"},
		{"troop_type": "3", "quality": "0", "weight": "2"},
	]


## 定 seed 的 rng（保证测试可复现）
func _seeded_rng(s: int) -> RandomNumberGenerator:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = s
	return rng


func _assert(cond: bool, msg: String) -> void:
	if cond:
		print("  ✓ " + msg)
	else:
		printerr("  ✗ " + msg)
		_failed += 1
