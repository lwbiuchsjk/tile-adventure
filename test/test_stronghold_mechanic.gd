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
	_test_init_scan_registers_preoccupied()
	_test_init_scan_with_stronghold()
	_test_stronghold_capture_unregisters_source()

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


## 7. init_scan 补登开局已占领 slot（Phase 3 修复：地图预染玩家 slot 视野漏激活）
func _test_init_scan_registers_preoccupied() -> void:
	print("-- init_scan 补登开局占领（无据点）")
	var ctx: Dictionary = _make_binding()
	var binding: StrongholdVisionBinding = ctx["binding"]
	var vs: VisionSystem = ctx["vs"]
	# 无据点场景
	RunState.reset()
	RunState.ensure_initialized(_mock_hero_pool(), _make_rng(1))
	# 2 个玩家占领 + 1 敌方 + 1 中立
	var slots: Array[PersistentSlot] = [
		_make_slot(Vector2i(2, 2), Faction.PLAYER),
		_make_slot(Vector2i(4, 7), Faction.PLAYER),
		_make_slot(Vector2i(9, 9), Faction.ENEMY_1),
		_make_slot(Vector2i(1, 8), Faction.NONE),
	]
	binding.init_scan(slots)
	_assert(binding.occupied_source_count() == 2, "仅 2 个玩家 slot 补登占领源")
	_assert(not binding.has_stronghold_source(), "无据点 → 无据点源")
	_assert(vs.get_sources().size() == 2, "VisionSystem 2 源（敌方/中立不登）")


## 8. init_scan 据点优先 + 据点格不重复登占领源
func _test_init_scan_with_stronghold() -> void:
	print("-- init_scan 据点优先")
	var ctx: Dictionary = _make_binding()
	var binding: StrongholdVisionBinding = ctx["binding"]
	var vs: VisionSystem = ctx["vs"]
	RunState.reset()
	RunState.ensure_initialized(_mock_hero_pool(), _make_rng(1))
	# 据点格 (5,5) 必须是 CORE_TOWN/PLAYER 才被据点分支命中
	var stronghold_slot: PersistentSlot = _make_slot(Vector2i(5, 5), Faction.PLAYER)
	stronghold_slot.type = PersistentSlot.Type.CORE_TOWN
	var slots: Array[PersistentSlot] = [
		stronghold_slot,
		_make_slot(Vector2i(2, 2), Faction.PLAYER),
	]
	RunState.set_stronghold(Vector2i(5, 5))
	binding.init_scan(slots)
	_assert(binding.has_stronghold_source(), "据点源已补登")
	_assert(binding.occupied_source_count() == 1, "据点格不重复登占领源，仅另 1 个玩家 slot")
	_assert(vs.get_sources().size() == 2, "共 2 源（据点 + 1 占领）")
	# 据点源半径 7
	var has_r7: bool = false
	for src in vs.get_sources():
		if src.radius == 7:
			has_r7 = true
	_assert(has_r7, "存在半径 7 的据点源")
	RunState.reset()


## 9. 据点失守撤视野 + 夺回重注册（codex P1-3 修复）
func _test_stronghold_capture_unregisters_source() -> void:
	print("-- 据点失守撤视野 / 夺回重注册")
	var ctx: Dictionary = _make_binding()
	var binding: StrongholdVisionBinding = ctx["binding"]
	var vs: VisionSystem = ctx["vs"]
	# 设据点
	binding.on_stronghold_set(Vector2i(3, 3))
	_assert(binding.has_stronghold_source(), "据点源已注册")
	_assert(vs.get_sources().size() == 1, "1 源")
	# 据点被敌方攻占（owner→ENEMY）→ 据点源注销
	var captured: PersistentSlot = _make_slot(Vector2i(3, 3), Faction.ENEMY_1)
	captured.type = PersistentSlot.Type.CORE_TOWN
	binding.on_slot_owner_changed(captured)
	_assert(not binding.has_stronghold_source(), "失守后据点源已注销")
	_assert(vs.get_sources().is_empty(), "失守后 0 源")
	# 玩家夺回（owner→PLAYER）→ 据点源重注册
	var retaken: PersistentSlot = _make_slot(Vector2i(3, 3), Faction.PLAYER)
	retaken.type = PersistentSlot.Type.CORE_TOWN
	binding.on_slot_owner_changed(retaken)
	_assert(binding.has_stronghold_source(), "夺回后据点源重注册")
	_assert(vs.get_sources().size() == 1, "夺回后 1 源")
	_assert(vs.get_sources()[0].radius == 7, "重注册仍为据点半径 7")


# ─────────────────────────────────────
# 辅助
# ─────────────────────────────────────

## 4 个英雄 mock 池（ensure_initialized 需要）
func _mock_hero_pool() -> Array:
	return [
		{"id": 0, "name": "A", "troop_type": "SWORD", "troop_quality": "T1"},
		{"id": 1, "name": "B", "troop_type": "BOW", "troop_quality": "T1"},
	]


func _make_rng(seed_value: int) -> RandomNumberGenerator:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng

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
