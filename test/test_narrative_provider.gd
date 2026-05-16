extends SceneTree
## NarrativeProvider 叙事文本随机池冒烟测试（MVP-ε P3 测试补全）
##
## 运行：tools/run_godot.ps1 --headless -s test/test_narrative_provider.gd
##
## 验证范围：
##   1. ensure_loaded 一次性加载 + 幂等（重复调用不重新加载）
##   2. pick 命中池 + 占位符替换
##   3. 未知 scenario 走 FALLBACK_NARRATIVE
##   4. 模板字段缺失行跳过
##   5. 残留占位符（ctx 未提供 key）push_warning 但保留原样

var _failed: int = 0


func _init() -> void:
	print("=== NarrativeProvider 冒烟测试 ===")

	_test_ensure_loaded_basic()
	_test_ensure_loaded_idempotent()
	_test_pick_replaces_placeholder()
	_test_pick_unknown_scenario_fallback()
	_test_pick_missing_context_key_keeps_placeholder()
	_test_empty_row_skipped()

	if _failed > 0:
		printerr("✗ 共 %d 项失败" % _failed)
		quit(1)
	else:
		print("✓ 全部通过")
		quit(0)


# ─────────────────────────────────────
# 用例
# ─────────────────────────────────────

## 1. ensure_loaded 基本路径：池写入正确
func _test_ensure_loaded_basic() -> void:
	print("-- ensure_loaded 写入池")
	_reset()
	NarrativeProvider.ensure_loaded(_mock_rows_basic())
	# pick 验证间接证明池已写入
	var text: String = NarrativeProvider.pick("camp_wild", {"leader_name": "陈青锋"})
	_assert(text.find("陈青锋") >= 0, "pick 返回的文本含 leader_name 替换")
	_assert(text.find("{leader_name}") < 0, "占位符已替换")


## 2. ensure_loaded 幂等：二次调用不重写池
func _test_ensure_loaded_idempotent() -> void:
	print("-- ensure_loaded 幂等")
	_reset()
	NarrativeProvider.ensure_loaded(_mock_rows_basic())
	# 第二次传入完全不同的池，因 _initialized=true 应被忽略
	var different_rows: Array = [
		{"scenario": "camp_wild", "narrative_template": "完全不同的文本 {leader_name}"}
	]
	NarrativeProvider.ensure_loaded(different_rows)
	# 抽取多次，全部应来自第一次的池（不含"完全不同的文本"）
	for i in range(10):
		var text: String = NarrativeProvider.pick("camp_wild", {"leader_name": "X"})
		_assert(text.find("完全不同的文本") < 0, "第二次 ensure_loaded 不生效（幂等）")


## 3. pick 占位符替换覆盖多个 key
func _test_pick_replaces_placeholder() -> void:
	print("-- pick 占位符替换")
	_reset()
	NarrativeProvider.ensure_loaded(_mock_rows_multi_placeholder())
	var ctx: Dictionary = {"leader_name": "李雷", "item": "草药", "count": 2}
	var text: String = NarrativeProvider.pick("resource_slot_pickup", ctx)
	_assert(text.find("李雷") >= 0, "leader_name 替换")
	_assert(text.find("草药") >= 0, "item 替换")
	_assert(text.find("2") >= 0, "count 替换")
	_assert(text.find("{") < 0, "无 { 残留")


## 4. 未知 scenario 走 FALLBACK
func _test_pick_unknown_scenario_fallback() -> void:
	print("-- 未知 scenario fallback")
	_reset()
	NarrativeProvider.ensure_loaded(_mock_rows_basic())
	var text: String = NarrativeProvider.pick("非法场景_xyz", {"leader_name": "韩梅梅"})
	_assert(text.find("韩梅梅") >= 0, "FALLBACK 含 leader_name 替换")
	# FALLBACK_NARRATIVE = "{leader_name} 获得了一些物资。"
	_assert(text.find("获得了一些物资") >= 0, "FALLBACK 模板生效")


## 5. ctx 缺 key 时 placeholder 保留 + push_warning（不中断流程）
func _test_pick_missing_context_key_keeps_placeholder() -> void:
	print("-- ctx 缺 key 保留 placeholder")
	_reset()
	NarrativeProvider.ensure_loaded(_mock_rows_multi_placeholder())
	# ctx 只给 leader_name，缺 item / count
	var ctx: Dictionary = {"leader_name": "王明"}
	var text: String = NarrativeProvider.pick("resource_slot_pickup", ctx)
	_assert(text.find("王明") >= 0, "leader_name 仍替换")
	_assert(text.find("{item}") >= 0 or text.find("{count}") >= 0, "未提供 key 的 placeholder 保留")


## 6. 缺字段行跳过（scenario / narrative_template 之一为空）
func _test_empty_row_skipped() -> void:
	print("-- 缺字段行跳过")
	_reset()
	var rows: Array = [
		{"scenario": "camp_wild", "narrative_template": "正常 {leader_name}"},
		{"scenario": "", "narrative_template": "缺 scenario"},
		{"scenario": "camp_wild", "narrative_template": ""},  # 缺 template
		{"scenario": "camp_village", "narrative_template": "村庄 {leader_name}"},
	]
	NarrativeProvider.ensure_loaded(rows)
	# camp_wild 只剩 1 条有效；camp_village 1 条
	var text_wild: String = NarrativeProvider.pick("camp_wild", {"leader_name": "Z"})
	_assert(text_wild.find("正常 Z") >= 0, "camp_wild 有效条目命中")
	var text_village: String = NarrativeProvider.pick("camp_village", {"leader_name": "Z"})
	_assert(text_village.find("村庄 Z") >= 0, "camp_village 有效条目命中")


# ─────────────────────────────────────
# 辅助
# ─────────────────────────────────────

## 重置 NarrativeProvider 静态状态（_initialized + _pool）
##
## NarrativeProvider 无 reset() 方法（一次性加载是设计意图），测试场景下直接清静态字段
func _reset() -> void:
	NarrativeProvider._initialized = false
	NarrativeProvider._pool = {}


## camp_wild 3 条模板（基础）
func _mock_rows_basic() -> Array:
	return [
		{"scenario": "camp_wild", "narrative_template": "{leader_name} 在野外扎营。"},
		{"scenario": "camp_wild", "narrative_template": "{leader_name} 仰望星空。"},
		{"scenario": "camp_wild", "narrative_template": "{leader_name} 警戒四周。"},
	]


## resource_slot_pickup 含 3 个占位符（leader_name + item + count）
func _mock_rows_multi_placeholder() -> Array:
	return [
		{"scenario": "resource_slot_pickup", "narrative_template": "{leader_name} 拾取了 {item} × {count}。"},
	]


func _assert(cond: bool, msg: String) -> void:
	if cond:
		print("  ✓ " + msg)
	else:
		printerr("  ✗ " + msg)
		_failed += 1
