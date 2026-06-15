extends SceneTree
## L1.3d-1 暗影压力引擎 数据层冒烟测试（阶段 A）
##
## 运行：tools/run_godot.ps1 --headless -s test/test_l13d1_pressure.gd
##
## 设计：tile-advanture-design/无限地图实装/L1.3d-1_暗影压力引擎_MVP.md §三 / §七（headless 场景 1-3）
##
## 验证范围（ShadowPressure 纯函数 + PressureConfig 分段；阶段 B 后含威胁表查表）：
##   1. P 分段相加：compute_pressure = camp_level + vision_level，阈值边界前后分段正确
##   2. 扎营轴单调：固定视野源，扎营次数递增 → P 不减，跨阈值 +1
##   3. 视野轴单调：固定扎营，视野源递增 → P 不减，跨阈值 +1

var _failed: int = 0


func _init() -> void:
	print("=== L1.3d-1 暗影压力引擎 数据层冒烟测试（阶段 A）===")

	_test_pressure_sum_and_boundaries()
	_test_camp_axis_monotonic()
	_test_vision_axis_monotonic()

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
