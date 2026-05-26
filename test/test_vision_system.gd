extends SceneTree
## VisionSystem 视野状态机冒烟测试（L1.1 §7 场景 1/4/5）
##
## 运行：
##   /mnt/e/Godot/.../Godot.exe --headless --path "E:\Godot\project\tile-adventure" -s test/test_vision_system.gd
##
## 验证范围：
##   1. 注册视野源 → 覆盖范围内格子转 NORMAL
##   2. 圆形覆盖判定（不是方形）
##   3. 多源覆盖求并集
##   4. 视野源移动 → 旧位置 NORMAL 标记"离开"
##   5. NORMAL → FOG 滞回延迟（fog_delay_turns）
##   6. FOG → SHADOW 退化时钟（shadow_decay_turns）
##   7. FOG → NORMAL 可逆（重新覆盖）
##   8. aggregate_tiles 聚合规则
##   9. tile_state_changed signal 发射

var _failed: int = 0
var _signal_captured: Array[Dictionary] = []


func _init() -> void:
	print("=== VisionSystem 冒烟测试 ===")

	_test_register_source_covers_normal()
	_test_circular_coverage_not_square()
	_test_multi_source_union()
	_test_source_move_marks_leave()
	_test_fog_delay_decay()
	_test_shadow_decay_after_fog()
	_test_fog_to_normal_reversible()
	_test_aggregate_tiles_rule()
	_test_signal_emitted_on_state_change()
	_test_get_all_normal_tiles()

	if _failed > 0:
		printerr("✗ 共 %d 项失败" % _failed)
		quit(1)
	else:
		print("✓ 全部通过")
		quit(0)


# ─────────────────────────────────────
# 用例
# ─────────────────────────────────────

## 1. 注册源 → 覆盖范围内格子转 NORMAL
func _test_register_source_covers_normal() -> void:
	print("-- 注册源覆盖 NORMAL")
	var vs: VisionSystem = _make_system(3, 5)
	var src: VisionSource = VisionSource.new(Vector2i(0, 0), 3)
	vs.register_source(src)

	_assert(vs.get_tile_state(Vector2i(0, 0)) == VisionSystem.TileState.NORMAL, "原点 NORMAL")
	_assert(vs.get_tile_state(Vector2i(3, 0)) == VisionSystem.TileState.NORMAL, "(3,0) NORMAL（r=3 圆边）")
	_assert(vs.get_tile_state(Vector2i(4, 0)) == VisionSystem.TileState.SHADOW, "(4,0) SHADOW（圆外）")


## 2. 圆形覆盖（不是方形）—— 对角线远比正交近
func _test_circular_coverage_not_square() -> void:
	print("-- 圆形覆盖判定")
	var vs: VisionSystem = _make_system(3, 5)
	var src: VisionSource = VisionSource.new(Vector2i.ZERO, 3)
	vs.register_source(src)

	# (3,3) 距原点 sqrt(18) ≈ 4.24 > 3 → SHADOW
	_assert(vs.get_tile_state(Vector2i(3, 3)) == VisionSystem.TileState.SHADOW, "(3,3) SHADOW（对角线外）")
	# (2,2) 距原点 sqrt(8) ≈ 2.83 < 3 → NORMAL
	_assert(vs.get_tile_state(Vector2i(2, 2)) == VisionSystem.TileState.NORMAL, "(2,2) NORMAL（对角线内）")


## 3. 多源覆盖求并集
func _test_multi_source_union() -> void:
	print("-- 多源覆盖求并集")
	var vs: VisionSystem = _make_system(3, 5)
	vs.register_source(VisionSource.new(Vector2i(0, 0), 2))
	vs.register_source(VisionSource.new(Vector2i(10, 0), 2))

	_assert(vs.get_tile_state(Vector2i(0, 0)) == VisionSystem.TileState.NORMAL, "源 1 中心 NORMAL")
	_assert(vs.get_tile_state(Vector2i(10, 0)) == VisionSystem.TileState.NORMAL, "源 2 中心 NORMAL")
	_assert(vs.get_tile_state(Vector2i(5, 0)) == VisionSystem.TileState.SHADOW, "(5,0) 两源都覆盖不到 → SHADOW")


## 4. 视野源移动 → 旧位置标记"离开"
func _test_source_move_marks_leave() -> void:
	print("-- 视野源移动")
	var vs: VisionSystem = _make_system(3, 5)
	var src: VisionSource = VisionSource.new(Vector2i(0, 0), 2)
	vs.register_source(src)

	_assert(vs.get_tile_state(Vector2i(0, 0)) == VisionSystem.TileState.NORMAL, "移动前原点 NORMAL")

	# 移动到 (10, 0)
	src.position = Vector2i(10, 0)
	vs.notify_source_moved()

	# 原位置（0,0）仍是 NORMAL，但已被标"离开"——等 fog_delay 后才转 FOG
	# 新位置 (10,0) 是 NORMAL
	_assert(vs.get_tile_state(Vector2i(10, 0)) == VisionSystem.TileState.NORMAL, "新位置 NORMAL")
	_assert(vs.get_tile_state(Vector2i(0, 0)) == VisionSystem.TileState.NORMAL, "旧位置仍 NORMAL（待滞回到期）")


## 5. NORMAL → FOG 滞回延迟
func _test_fog_delay_decay() -> void:
	print("-- NORMAL → FOG 滞回")
	var vs: VisionSystem = _make_system(1, 5)  # fog_delay=1
	var src: VisionSource = VisionSource.new(Vector2i.ZERO, 2)
	vs.register_source(src)

	# turn 0：覆盖
	# turn 1：源移走（标记离开时刻 turn=1）
	vs.advance_turn(1)
	src.position = Vector2i(100, 100)
	vs.notify_source_moved()
	# 此时旧位置 (0,0) NORMAL，离开时刻 turn=1，fog_delay=1
	_assert(vs.get_tile_state(Vector2i(0, 0)) == VisionSystem.TileState.NORMAL, "刚离开 NORMAL 保持")

	# turn 2：1-1 = 0 < fog_delay 1，未到期
	# 实际语义：advance_turn 调 _apply_decay，判断 current_turn - normal_left_turn >= fog_delay
	vs.advance_turn(2)
	_assert(vs.get_tile_state(Vector2i(0, 0)) == VisionSystem.TileState.FOG, "turn 2 (2-1>=1) 应转 FOG")


## 6. FOG → SHADOW 退化时钟
func _test_shadow_decay_after_fog() -> void:
	print("-- FOG → SHADOW 退化")
	var vs: VisionSystem = _make_system(0, 3)  # fog_delay=0 立即进 FOG, shadow_decay=3
	var src: VisionSource = VisionSource.new(Vector2i.ZERO, 1)
	vs.register_source(src)

	# turn 0：source 在 (0,0)
	vs.advance_turn(0)
	# turn 1：source 移走，立即进 FOG（fog_delay=0）
	src.position = Vector2i(100, 100)
	vs.notify_source_moved()
	vs.advance_turn(1)
	_assert(vs.get_tile_state(Vector2i(0, 0)) == VisionSystem.TileState.FOG, "turn 1 进 FOG（fog_delay=0）")

	# 进入 FOG 的时刻 = turn 1；shadow_decay=3，需 turn 4 才到期
	vs.advance_turn(2)
	_assert(vs.get_tile_state(Vector2i(0, 0)) == VisionSystem.TileState.FOG, "turn 2 仍 FOG")
	vs.advance_turn(4)
	_assert(vs.get_tile_state(Vector2i(0, 0)) == VisionSystem.TileState.SHADOW, "turn 4 (4-1>=3) 转 SHADOW")


## 7. FOG → NORMAL 可逆（重新覆盖）
func _test_fog_to_normal_reversible() -> void:
	print("-- FOG → NORMAL 可逆")
	var vs: VisionSystem = _make_system(0, 10)
	var src: VisionSource = VisionSource.new(Vector2i.ZERO, 1)
	vs.register_source(src)

	# 推进到 FOG
	src.position = Vector2i(100, 100)
	vs.notify_source_moved()
	vs.advance_turn(1)
	_assert(vs.get_tile_state(Vector2i(0, 0)) == VisionSystem.TileState.FOG, "已进 FOG")

	# 源移回 (0,0) → 重新 NORMAL
	src.position = Vector2i(0, 0)
	vs.notify_source_moved()
	_assert(vs.get_tile_state(Vector2i(0, 0)) == VisionSystem.TileState.NORMAL, "重覆盖转 NORMAL")


## 8. aggregate_tiles 聚合规则
func _test_aggregate_tiles_rule() -> void:
	print("-- aggregate_tiles 聚合")
	var vs: VisionSystem = _make_system(0, 10)
	# 手工构造混合状态
	vs._tile_state[Vector2i(0, 0)] = VisionSystem.TileState.NORMAL
	vs._tile_state[Vector2i(1, 0)] = VisionSystem.TileState.FOG
	# (2,0) 不在表 → SHADOW

	# 含 NORMAL → NORMAL
	var tiles_with_normal: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]
	_assert(vs.aggregate_tiles(tiles_with_normal) == VisionSystem.TileState.NORMAL, "含 NORMAL → NORMAL")

	# 含 FOG 无 NORMAL → FOG
	var tiles_fog_only: Array[Vector2i] = [Vector2i(1, 0), Vector2i(2, 0)]
	_assert(vs.aggregate_tiles(tiles_fog_only) == VisionSystem.TileState.FOG, "含 FOG 无 NORMAL → FOG")

	# 全 SHADOW → SHADOW
	var tiles_all_shadow: Array[Vector2i] = [Vector2i(2, 0), Vector2i(3, 0)]
	_assert(vs.aggregate_tiles(tiles_all_shadow) == VisionSystem.TileState.SHADOW, "全 SHADOW → SHADOW")


## 9. tile_state_changed signal 发射
func _test_signal_emitted_on_state_change() -> void:
	print("-- signal 发射")
	var vs: VisionSystem = _make_system(0, 10)
	_signal_captured.clear()
	vs.tile_state_changed.connect(_on_tile_state_changed)

	var src: VisionSource = VisionSource.new(Vector2i.ZERO, 1)
	vs.register_source(src)
	# r=1 覆盖 5 格（中心 + 4 邻），应发射 5 次 SHADOW→NORMAL
	_assert(_signal_captured.size() == 5, "register r=1 发射 5 次 signal（实际 %d）" % _signal_captured.size())

	vs.tile_state_changed.disconnect(_on_tile_state_changed)


## 10. get_all_normal_tiles 查询
func _test_get_all_normal_tiles() -> void:
	print("-- get_all_normal_tiles")
	var vs: VisionSystem = _make_system(0, 10)
	var src: VisionSource = VisionSource.new(Vector2i.ZERO, 1)
	vs.register_source(src)

	var normal_tiles: Array[Vector2i] = vs.get_all_normal_tiles()
	_assert(normal_tiles.size() == 5, "r=1 覆盖 5 格（实际 %d）" % normal_tiles.size())


# ─────────────────────────────────────
# 助手
# ─────────────────────────────────────

func _on_tile_state_changed(tile: Vector2i, new_state: int, old_state: int) -> void:
	_signal_captured.append({
		"tile": tile,
		"new_state": new_state,
		"old_state": old_state,
	})


## 构造一个独立的 VisionSystem 实例（带 config）
func _make_system(fog_delay: int, shadow_decay: int) -> VisionSystem:
	var cfg: VisionConfig = VisionConfig.new()
	cfg.fog_delay_turns = fog_delay
	cfg.shadow_decay_turns = shadow_decay
	var vs: VisionSystem = VisionSystem.new()
	vs.setup(cfg)
	return vs


func _assert(condition: bool, msg: String) -> void:
	if condition:
		print("  ✓ %s" % msg)
	else:
		printerr("  ✗ %s" % msg)
		_failed += 1
