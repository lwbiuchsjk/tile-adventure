extends SceneTree
## 据点机制 + 多源视野绑定冒烟测试（L1.2 Phase 2）
##
## 运行：tools/run_godot.ps1 --headless -s test/test_stronghold_mechanic.gd
##
## 验证范围（StrongholdVisionBinding + VisionSystem 多源）：
##   1. 据点选定 → register 据点视野源（半径 = stronghold_vision_radius）
##   2. 占领 slot 翻转 PLAYER → register 占领视野源（半径 = occupied_slot_vision_radius）
##   3. 占领 slot 翻转非 PLAYER（敌方夺走）→ unregister 占领视野源
##   4. 据点格不重复注册占领源（据点格被占领事件命中时跳过）
##   5. 先占领再设据点同格 → 占领源升级为据点源（不双源）
##   6. 多源覆盖并集（VisionSystem 多源 NORMAL 集合 = 各源覆盖并集）

var _failed: int = 0


func _init() -> void:
	print("=== 据点机制 + 多源视野 冒烟测试 ===")

	_test_stronghold_set_registers_source()
	_test_occupy_player_registers_source()
	_test_occupy_non_player_unregisters_source()
	_test_stronghold_pos_skips_occupy_source()
	_test_occupy_then_stronghold_same_pos_upgrades()
	_test_multi_source_coverage_union()

	if _failed > 0:
		printerr("✗ 共 %d 项失败" % _failed)
		quit(1)
	else:
		print("✓ 全部通过")
		quit(0)


# ─────────────────────────────────────
# 用例
# ─────────────────────────────────────

## 1. 据点选定 → register 据点视野源
func _test_stronghold_set_registers_source() -> void:
	print("-- 据点选定注册视野源")
	var ctx: Dictionary = _make_binding()
	var binding: StrongholdVisionBinding = ctx["binding"]
	var vs: VisionSystem = ctx["vs"]
	_assert(not binding.has_stronghold_source(), "初始无据点源")
	_assert(vs.get_sources().is_empty(), "初始 VisionSystem 无源")

	binding.on_stronghold_set(Vector2i(10, 10))
	_assert(binding.has_stronghold_source(), "据点源已注册")
	_assert(vs.get_sources().size() == 1, "VisionSystem 有 1 源")
	# 据点视野半径 = config.stronghold_vision_radius (7)
	var src: VisionSource = vs.get_sources()[0]
	_assert(src.radius == 7, "据点源半径 = stronghold_vision_radius(7)")
	_assert(src.position == Vector2i(10, 10), "据点源位置正确")


## 2. 占领 slot 翻转 PLAYER → register 占领视野源
func _test_occupy_player_registers_source() -> void:
	print("-- 占领翻转注册视野源")
	var ctx: Dictionary = _make_binding()
	var binding: StrongholdVisionBinding = ctx["binding"]
	var vs: VisionSystem = ctx["vs"]

	var slot: PersistentSlot = _make_slot(Vector2i(3, 5), Faction.PLAYER)
	binding.on_slot_owner_changed(slot)
	_assert(binding.occupied_source_count() == 1, "占领源数 = 1")
	_assert(vs.get_sources().size() == 1, "VisionSystem 有 1 源")
	_assert(vs.get_sources()[0].radius == 4, "占领源半径 = occupied_slot_vision_radius(4)")

	# 幂等：同 slot 再翻一次 PLAYER 不重复注册
	binding.on_slot_owner_changed(slot)
	_assert(binding.occupied_source_count() == 1, "重复占领幂等，仍 1 源")


## 3. 占领 slot 翻转非 PLAYER → unregister
func _test_occupy_non_player_unregisters_source() -> void:
	print("-- 敌方夺走移除视野源")
	var ctx: Dictionary = _make_binding()
	var binding: StrongholdVisionBinding = ctx["binding"]
	var vs: VisionSystem = ctx["vs"]

	var slot: PersistentSlot = _make_slot(Vector2i(3, 5), Faction.PLAYER)
	binding.on_slot_owner_changed(slot)
	_assert(binding.occupied_source_count() == 1, "占领后 1 源")

	# 敌方夺走（owner 翻成 ENEMY_1）
	slot.owner_faction = Faction.ENEMY_1
	binding.on_slot_owner_changed(slot)
	_assert(binding.occupied_source_count() == 0, "敌方夺走后 0 源")
	_assert(vs.get_sources().is_empty(), "VisionSystem 无源")


## 4. 据点格被占领事件命中时跳过（不重复注册占领源）
func _test_stronghold_pos_skips_occupy_source() -> void:
	print("-- 据点格跳过占领源")
	var ctx: Dictionary = _make_binding()
	var binding: StrongholdVisionBinding = ctx["binding"]
	var vs: VisionSystem = ctx["vs"]

	binding.on_stronghold_set(Vector2i(8, 8))
	_assert(vs.get_sources().size() == 1, "据点源 1 个")

	# 据点格上发生占领翻转事件（如敌方占据点后玩家夺回触发翻转）→ 不新增占领源
	var slot: PersistentSlot = _make_slot(Vector2i(8, 8), Faction.PLAYER)
	binding.on_slot_owner_changed(slot)
	_assert(binding.occupied_source_count() == 0, "据点格不注册占领源")
	_assert(vs.get_sources().size() == 1, "仍仅据点源 1 个")


## 5. 先占领再设据点同格 → 占领源升级为据点源（不双源）
func _test_occupy_then_stronghold_same_pos_upgrades() -> void:
	print("-- 先占领再设据点同格升级")
	var ctx: Dictionary = _make_binding()
	var binding: StrongholdVisionBinding = ctx["binding"]
	var vs: VisionSystem = ctx["vs"]

	var slot: PersistentSlot = _make_slot(Vector2i(6, 6), Faction.PLAYER)
	binding.on_slot_owner_changed(slot)
	_assert(binding.occupied_source_count() == 1, "占领源 1 个")
	_assert(vs.get_sources().size() == 1, "VisionSystem 1 源")

	# 同格设为据点 → 占领源移除，据点源注册（总数仍 1，但半径变 7）
	binding.on_stronghold_set(Vector2i(6, 6))
	_assert(binding.occupied_source_count() == 0, "占领源已移除")
	_assert(binding.has_stronghold_source(), "据点源已注册")
	_assert(vs.get_sources().size() == 1, "总源数仍 1（升级非新增）")
	_assert(vs.get_sources()[0].radius == 7, "源半径升级为据点半径 7")


## 6. 多源覆盖并集
func _test_multi_source_coverage_union() -> void:
	print("-- 多源覆盖并集")
	var ctx: Dictionary = _make_binding()
	var binding: StrongholdVisionBinding = ctx["binding"]
	var vs: VisionSystem = ctx["vs"]

	# 据点 (0,0) r=7 + 占领 slot (20,20) r=4，两圆不重叠
	binding.on_stronghold_set(Vector2i(0, 0))
	var slot: PersistentSlot = _make_slot(Vector2i(20, 20), Faction.PLAYER)
	binding.on_slot_owner_changed(slot)
	_assert(vs.get_sources().size() == 2, "2 源并存")

	# 据点中心 + 占领中心都应是 NORMAL（各自圆内）
	_assert(vs.get_tile_state(Vector2i(0, 0)) == VisionSystem.TileState.NORMAL, "据点中心 NORMAL")
	_assert(vs.get_tile_state(Vector2i(20, 20)) == VisionSystem.TileState.NORMAL, "占领中心 NORMAL")
	# 远离两圆的格（50,50）应是 SHADOW（默认）
	_assert(vs.get_tile_state(Vector2i(50, 50)) == VisionSystem.TileState.SHADOW, "圆外格 SHADOW")


# ─────────────────────────────────────
# 辅助
# ─────────────────────────────────────

## 构造 VisionSystem + VisionConfig + StrongholdVisionBinding（默认半径 7/4）
func _make_binding() -> Dictionary:
	var cfg: VisionConfig = VisionConfig.new()
	cfg.stronghold_vision_radius = 7
	cfg.occupied_slot_vision_radius = 4
	cfg.player_vision_radius = 5
	var vs: VisionSystem = VisionSystem.new()
	vs.setup(cfg)
	var binding: StrongholdVisionBinding = StrongholdVisionBinding.new()
	binding.setup(vs, cfg)
	return {"binding": binding, "vs": vs, "cfg": cfg}


## 构造指定位置 + 归属的 PersistentSlot
func _make_slot(pos: Vector2i, owner: int) -> PersistentSlot:
	var s: PersistentSlot = PersistentSlot.new()
	s.position = pos
	s.owner_faction = owner
	s.type = PersistentSlot.Type.TOWN
	return s


func _assert(cond: bool, msg: String) -> void:
	if cond:
		print("  ✓ " + msg)
	else:
		printerr("  ✗ " + msg)
		_failed += 1
