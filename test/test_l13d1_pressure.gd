extends SceneTree
## L1.3d-1 暗影压力引擎 数据层冒烟测试（阶段 A）
##
## 运行：tools/run_godot.ps1 --headless -s test/test_l13d1_pressure.gd
##
## 设计：tile-advanture-design/无限地图实装/L1.3d-1_暗影压力引擎_MVP.md §三 / §七（headless 场景 1-3）
##
## 验证范围（ShadowPressure 纯函数 + PressureConfig 分段 + 阶段 B 威胁表查表 / interval）：
##   1. P 分段相加：compute_pressure = camp_level + vision_level，阈值边界前后分段正确
##   2. 扎营轴单调：固定视野源，扎营次数递增 → P 不减，跨阈值 +1
##   3. 视野轴单调：固定扎营，视野源递增 → P 不减，跨阈值 +1
##   4. 威胁表查表（阶段 B）：_pick_tier_for_pressure 按 P 加权抽 tier；高 P 解锁高 tier；空/未配置兜底 0
##   5. interval 随 P（阶段 B）：reinforcement_interval_for_pressure 随 P 单调不增 + 下限封底

var _failed: int = 0


func _init() -> void:
	print("=== L1.3d-1 暗影压力引擎 冒烟测试（阶段 A 引擎 + 阶段 B 威胁表/间隔）===")

	_test_pressure_sum_and_boundaries()
	_test_camp_axis_monotonic()
	_test_vision_axis_monotonic()
	_test_pick_tier_for_pressure()
	_test_interval_for_pressure()

	if _failed > 0:
		printerr("✗ 共 %d 项失败" % _failed)
		quit(1)
	else:
		print("✓ 全部通过")
		quit(0)


## 断言辅助：cond 为假则计失败并打印。
func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failed += 1
		printerr("  ✗ " + msg)


# ─────────────────────────────────────
# 用例
# ─────────────────────────────────────

## 1. P = camp_level + vision_level，且各轴在默认阈值（扎营 [3,6,9] / 视野 [2,4]）边界分段正确
func _test_pressure_sum_and_boundaries() -> void:
	print("-- P 分段相加 + 边界")
	# 扎营轴边界：<3→0 / 3-5→1 / 6-8→2 / 9+→3
	_check(ShadowPressure.camp_level(0) == 0, "camp_level(0)=0")
	_check(ShadowPressure.camp_level(2) == 0, "camp_level(2)=0（阈值前）")
	_check(ShadowPressure.camp_level(3) == 1, "camp_level(3)=1（阈值上）")
	_check(ShadowPressure.camp_level(5) == 1, "camp_level(5)=1")
	_check(ShadowPressure.camp_level(6) == 2, "camp_level(6)=2")
	_check(ShadowPressure.camp_level(9) == 3, "camp_level(9)=3")
	_check(ShadowPressure.camp_level(99) == 3, "camp_level(99)=3（封顶）")
	# 视野轴边界：1→0 / 2-3→1 / 4+→2
	_check(ShadowPressure.vision_level(1) == 0, "vision_level(1)=0")
	_check(ShadowPressure.vision_level(2) == 1, "vision_level(2)=1（阈值上）")
	_check(ShadowPressure.vision_level(3) == 1, "vision_level(3)=1")
	_check(ShadowPressure.vision_level(4) == 2, "vision_level(4)=2")
	_check(ShadowPressure.vision_level(10) == 2, "vision_level(10)=2（封顶）")
	# 合成 = 两轴相加
	_check(ShadowPressure.compute_pressure(0, 1) == 0, "P(0扎营,1源)=0")
	_check(ShadowPressure.compute_pressure(5, 3) == 2, "P(5扎营,3源)=1+1=2")
	_check(ShadowPressure.compute_pressure(9, 4) == 5, "P(9扎营,4源)=3+2=5（顶档）")


## 2. 扎营轴单调：固定视野源 = 1（vision_level=0），扎营次数 0→12 递增，P 不减
func _test_camp_axis_monotonic() -> void:
	print("-- 扎营轴单调")
	var prev: int = -1
	for camp: int in range(0, 13):
		var p: int = ShadowPressure.compute_pressure(camp, 1)
		_check(p >= prev, "扎营 %d → P=%d 不减" % [camp, p])
		prev = p
	# 顶档不再增（camp 9 与 12 同档）
	_check(ShadowPressure.compute_pressure(9, 1) == ShadowPressure.compute_pressure(12, 1),
		"扎营顶档后 P 不再增")


## 3. 视野轴单调：固定扎营 = 0（camp_level=0），视野源 1→8 递增，P 不减
func _test_vision_axis_monotonic() -> void:
	print("-- 视野轴单调")
	var prev: int = -1
	for src: int in range(1, 9):
		var p: int = ShadowPressure.compute_pressure(0, src)
		_check(p >= prev, "视野源 %d → P=%d 不减" % [src, p])
		prev = p
	# 顶档不再增（src 4 与 8 同档）
	_check(ShadowPressure.compute_pressure(0, 4) == ShadowPressure.compute_pressure(0, 8),
		"视野顶档后 P 不再增")


## 4. 威胁表查表（阶段 B）：_pick_tier_for_pressure 按 P 加权抽 tier
func _test_pick_tier_for_pressure() -> void:
	print("-- 威胁表 P 查表抽 tier")
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 12345
	# mock：P=0 仅 tier0；P=3 仅 tier2/tier3
	var rows: Array = [
		{"pressure_level": "0", "tier": "0", "count": "5"},
		{"pressure_level": "3", "tier": "2", "count": "1"},
		{"pressure_level": "3", "tier": "3", "count": "1"},
	]
	# P=0 大样本必恒 tier0
	var all_zero: bool = true
	for i: int in range(50):
		if EnemyReinforcement._pick_tier_for_pressure(rows, 0, rng) != 0:
			all_zero = false
	_check(all_zero, "P=0 恒抽 tier0")
	# P=3 大样本只出 tier2/tier3，且两者都出现过（高 P 解锁高 tier）
	var seen2: bool = false
	var seen3: bool = false
	var only_high: bool = true
	for i: int in range(80):
		var t: int = EnemyReinforcement._pick_tier_for_pressure(rows, 3, rng)
		if t == 2:
			seen2 = true
		elif t == 3:
			seen3 = true
		else:
			only_high = false
	_check(only_high, "P=3 只抽 tier2/tier3")
	_check(seen2 and seen3, "P=3 两个高 tier 都出现（加权随机生效）")
	# 兜底：空表 / 未配置 P → tier0
	_check(EnemyReinforcement._pick_tier_for_pressure([], 0, rng) == 0, "空表兜底 tier0")
	_check(EnemyReinforcement._pick_tier_for_pressure(rows, 99, rng) == 0, "未配置 P=99 兜底 tier0")


## 5. interval 随 P（阶段 B）：reinforcement_interval_for_pressure 随 P 单调不增 + 下限封底
func _test_interval_for_pressure() -> void:
	print("-- interval 随 P 递减 + 下限")
	var prev: int = 2147483647
	for p: int in range(0, 8):
		var iv: int = EnemyReinforcement.reinforcement_interval_for_pressure(p)
		_check(iv <= prev, "P=%d → interval=%d 不增" % [p, iv])
		_check(iv >= EnemyReinforcement.SPAWN_CFG.enemy_reinforcement_interval_min,
			"P=%d → interval=%d 不低于下限" % [p, iv])
		prev = iv
	# P=0 = 基数；高 P 触底 = 下限
	_check(EnemyReinforcement.reinforcement_interval_for_pressure(0)
		== EnemyReinforcement.SPAWN_CFG.enemy_reinforcement_interval, "P=0 interval = 基数")
	_check(EnemyReinforcement.reinforcement_interval_for_pressure(99)
		== EnemyReinforcement.SPAWN_CFG.enemy_reinforcement_interval_min, "高 P interval 触下限")
