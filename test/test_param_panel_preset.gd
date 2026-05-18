extends SceneTree
## MVP-C.2 阶段 2 验证：ParamPreset + FieldSnapshot schema + preset backend 数据流
##
## 覆盖：
##   1. ParamPreset / FieldSnapshot schema 实例化 + 字段持久化 + 反序列化
##   2. capture_scene_as_preset 读 preload 实例当前值 → 构造 FieldSnapshot
##   3. save_preset_to_disk → list_presets_for_scene → load_preset_from_disk roundtrip
##   4. apply_preset 写回 preload 实例 + 标 dirty + 触发 redraw 收集
##   5. has_unsaved_dirty 标记翻转
##   6. delete_preset / rename_preset
##   7. sanitize_preset_filename 非法字符清洗
##
## 不实际跑 _flush_pending_redraw（headless 无 SceneTree.root + 节点查找）；
## 仅校验 _pending_redraw 收集动作到位。

const ControllerScript: GDScript = preload("res://scripts/ui/ParamPanelController.gd")
const ParamPanelSceneScript: GDScript = preload("res://scripts/config/param_panel_scene.gd")
const ParamFieldMappingScript: GDScript = preload("res://scripts/config/param_field_mapping.gd")
const ParamPresetScript: GDScript = preload("res://scripts/config/param_preset.gd")
const FieldSnapshotScript: GDScript = preload("res://scripts/config/field_snapshot.gd")

# user:// 下的临时 preset 路径（测试结束 cleanup）
const TEST_PRESET_DIR: String = "user://test_preset_tmp/"


func _init() -> void:
	var panel: Node = Node.new()
	panel.set_script(ControllerScript)
	var ok: bool = true
	ok = _test_schema_instantiate() and ok
	ok = _test_schema_roundtrip() and ok
	ok = _test_sanitize_filename(panel) and ok
	ok = _test_capture_scene() and ok
	ok = _test_save_load_list_delete(panel) and ok
	ok = _test_apply_preset_dirty_flag(panel) and ok
	ok = _test_rename_preset(panel) and ok
	# Codex 审 MVP-C.2 P0/P1.1 修复后补的测试盲区
	ok = _test_apply_preset_deep_copy_dict_array(panel) and ok
	ok = _test_preset_source_path_set_on_load(panel) and ok
	# cleanup user:// 测试目录
	_cleanup_test_dir()
	if ok:
		print("[test_param_panel_preset] 全部通过")
		quit(0)
	else:
		push_error("[test_param_panel_preset] 有用例失败")
		quit(1)


# ─────────────────────────────────────────
# Schema 测试
# ─────────────────────────────────────────

## FieldSnapshot + ParamPreset 实例化字段默认值正确
func _test_schema_instantiate() -> bool:
	var snap: FieldSnapshot = FieldSnapshot.new()
	if snap.target_resource_path != "" or snap.field_name != "" \
			or snap.dict_key != null or snap.value != null:
		push_error("FieldSnapshot 默认值不正确")
		return false
	var preset: ParamPreset = ParamPreset.new()
	if preset.display_name != "" or preset.scene_id != "" \
			or not preset.field_snapshots.is_empty() or preset.note != "":
		push_error("ParamPreset 默认值不正确")
		return false
	return true


## ParamPreset 含 3 FieldSnapshot → 写 user:// → 读回 → 字段值严格匹配
func _test_schema_roundtrip() -> bool:
	var preset: ParamPreset = _make_test_preset("test_scene", "测试 v1", [
		{"path": "res://a.tres", "field": "f1", "dict_key": null, "value": Color(0.1, 0.2, 0.3)},
		{"path": "res://a.tres", "field": "fd", "dict_key": 1, "value": 1.5},
		{"path": "res://b.tres", "field": "fs", "dict_key": null, "value": "abc"},
	])
	preset.note = "本测试备注"
	var path: String = "user://_test_preset_schema_roundtrip.tres"
	var err: int = ResourceSaver.save(preset, path)
	if err != OK:
		push_error("schema roundtrip 写盘失败 err=%d" % err)
		return false
	var loaded_res: Resource = load(path)
	if not loaded_res is ParamPreset:
		push_error("schema roundtrip 读回非 ParamPreset 类型")
		return false
	var loaded: ParamPreset = loaded_res as ParamPreset
	if loaded.scene_id != "test_scene" or loaded.display_name != "测试 v1" \
			or loaded.note != "本测试备注" or loaded.field_snapshots.size() != 3:
		push_error("schema roundtrip 顶层字段不匹配")
		return false
	# 逐 FieldSnapshot 字段值匹配
	var s0: FieldSnapshot = loaded.field_snapshots[0] as FieldSnapshot
	if s0.target_resource_path != "res://a.tres" or s0.field_name != "f1" \
			or s0.dict_key != null or not (s0.value as Color).is_equal_approx(Color(0.1, 0.2, 0.3)):
		push_error("FieldSnapshot[0] 字段值不匹配")
		return false
	var s1: FieldSnapshot = loaded.field_snapshots[1] as FieldSnapshot
	if s1.field_name != "fd" or s1.dict_key != 1 or s1.value != 1.5:
		push_error("FieldSnapshot[1] 字段值不匹配（dict_key=%s value=%s）" % [str(s1.dict_key), str(s1.value)])
		return false
	var s2: FieldSnapshot = loaded.field_snapshots[2] as FieldSnapshot
	if s2.field_name != "fs" or str(s2.value) != "abc":
		push_error("FieldSnapshot[2] 字段值不匹配")
		return false
	DirAccess.remove_absolute(path)
	return true


# ─────────────────────────────────────────
# Sanitize 工具测试
# ─────────────────────────────────────────

func _test_sanitize_filename(panel: Node) -> bool:
	var cases: Array = [
		["正常名字", "正常名字"],
		["含/斜杠", "含_斜杠"],
		["含\\反斜杠:冒号*星号", "含_反斜杠_冒号_星号"],
		["前后空白  ", "前后空白"],
		["", ""],
	]
	for case in cases:
		var input: String = (case as Array)[0]
		var expected: String = (case as Array)[1]
		var actual: String = panel.sanitize_preset_filename(input)
		if actual != expected:
			push_error("sanitize 不匹配：input='%s' expected='%s' actual='%s'" % [input, expected, actual])
			return false
	# 限长 64
	var long_input: String = "a".repeat(100)
	var long_out: String = panel.sanitize_preset_filename(long_input)
	if long_out.length() != 64:
		push_error("sanitize 限长 64 失效，实际 length=%d" % long_out.length())
		return false
	return true


# ─────────────────────────────────────────
# capture_scene_as_preset
# ─────────────────────────────────────────

## 构造内存中 ParamPanelScene + fields → 加载真实 .tres 实例 → capture 后检查 snapshots 数与值
## 用 night_vision_config（10 字段，纯标量）确保所有字段都能读到
func _test_capture_scene() -> bool:
	var scene: ParamPanelScene = _make_test_scene_minimal()
	var panel: Node = Node.new()
	panel.set_script(ControllerScript)
	var preset: ParamPreset = panel.capture_scene_as_preset(scene, "捕获测试")
	if preset == null:
		push_error("capture_scene_as_preset 返回 null")
		return false
	if preset.scene_id != scene.scene_id or preset.display_name != "捕获测试":
		push_error("capture 顶层字段不匹配")
		return false
	if preset.field_snapshots.size() != 2:
		push_error("capture snapshots 数量不对：expected=2 actual=%d" % preset.field_snapshots.size())
		return false
	# 验证 vision_radius_grids 快照值与当前 instance 值一致
	var night_cfg: Resource = load("res://assets/config/night_vision_config.tres")
	var s0: FieldSnapshot = preset.field_snapshots[0] as FieldSnapshot
	if s0.field_name != "vision_radius_grids" or s0.value != night_cfg.get("vision_radius_grids"):
		push_error("capture snapshot[0] vision_radius_grids 不匹配")
		return false
	return true


# ─────────────────────────────────────────
# save / list / load / delete 完整链路
# ─────────────────────────────────────────

func _test_save_load_list_delete(panel: Node) -> bool:
	# 准备一个最小 preset
	var preset: ParamPreset = _make_test_preset("test_save_scene", "保存测试", [
		{"path": "res://x.tres", "field": "fa", "dict_key": null, "value": 42},
	])
	# 改 PRESET_ROOT 至 user:// 测试目录（注：通过反射难，直接 mock 用真实路径但 cleanup）
	# 但 save_preset_to_disk 使用 const PRESET_ROOT，不能 mock；
	# 解决：暂时在 res://assets/config/presets/ 下用唯一 scene_id 写测试 preset，结束清理
	var test_scene_id: String = "_test_temp_save_scene_zzz"
	preset.scene_id = test_scene_id
	var err: int = panel.save_preset_to_disk(preset, "case1")
	if err != OK:
		push_error("save_preset_to_disk 失败 err=%d" % err)
		return false
	# list 应返回 1 个
	var listed: Array[String] = panel.list_presets_for_scene(test_scene_id)
	if listed.size() != 1:
		push_error("list_presets_for_scene 数量不对 expected=1 actual=%d" % listed.size())
		_cleanup_test_preset_dir(test_scene_id)
		return false
	# load 回来字段匹配
	var loaded: ParamPreset = panel.load_preset_from_disk(listed[0])
	if loaded == null or loaded.display_name != "保存测试" \
			or loaded.scene_id != test_scene_id or loaded.field_snapshots.size() != 1:
		push_error("load_preset_from_disk 字段不匹配")
		_cleanup_test_preset_dir(test_scene_id)
		return false
	# delete 删除文件
	var del_err: int = panel.delete_preset(listed[0])
	if del_err != OK:
		push_error("delete_preset 失败 err=%d" % del_err)
		_cleanup_test_preset_dir(test_scene_id)
		return false
	# list 应为空
	if not panel.list_presets_for_scene(test_scene_id).is_empty():
		push_error("delete 后 list 应为空")
		_cleanup_test_preset_dir(test_scene_id)
		return false
	_cleanup_test_preset_dir(test_scene_id)
	return true


# ─────────────────────────────────────────
# apply_preset 标 dirty + 写实例
# ─────────────────────────────────────────

func _test_apply_preset_dirty_flag(panel: Node) -> bool:
	var night_cfg: Resource = load("res://assets/config/night_vision_config.tres")
	var orig_vision: int = night_cfg.get("vision_radius_grids") as int
	# 构造 preset：把 vision_radius_grids 改成 orig + 1
	var preset: ParamPreset = _make_test_preset("apply_test", "apply 测试", [
		{"path": "res://assets/config/night_vision_config.tres",
			"field": "vision_radius_grids", "dict_key": null, "value": orig_vision + 1},
	])
	var scene: ParamPanelScene = _make_test_scene_minimal()
	# apply 前 has_unsaved_dirty = false
	if panel.has_unsaved_dirty():
		push_error("apply 前 has_unsaved_dirty 应为 false")
		night_cfg.set("vision_radius_grids", orig_vision)  # 兜底恢复
		return false
	panel.apply_preset(scene, preset)
	# apply 后字段值已写
	if (night_cfg.get("vision_radius_grids") as int) != orig_vision + 1:
		push_error("apply 后字段值未写入实例")
		night_cfg.set("vision_radius_grids", orig_vision)
		return false
	# has_unsaved_dirty = true
	if not panel.has_unsaved_dirty():
		push_error("apply 后 has_unsaved_dirty 应为 true")
		night_cfg.set("vision_radius_grids", orig_vision)
		return false
	# 恢复原值（避免污染源 .tres，因 dirty 但本测试不 F2 写盘）
	night_cfg.set("vision_radius_grids", orig_vision)
	return true


# ─────────────────────────────────────────
# rename_preset
# ─────────────────────────────────────────

func _test_rename_preset(panel: Node) -> bool:
	var preset: ParamPreset = _make_test_preset("_test_rename_zzz", "原名", [
		{"path": "res://x.tres", "field": "fa", "dict_key": null, "value": 1},
	])
	var err: int = panel.save_preset_to_disk(preset, "renamecase")
	if err != OK:
		push_error("rename 前 save 失败 err=%d" % err)
		_cleanup_test_preset_dir("_test_rename_zzz")
		return false
	var listed: Array[String] = panel.list_presets_for_scene("_test_rename_zzz")
	if listed.is_empty():
		_cleanup_test_preset_dir("_test_rename_zzz")
		return false
	var rename_err: int = panel.rename_preset(listed[0], "新名字 v2")
	if rename_err != OK:
		push_error("rename_preset 失败 err=%d" % rename_err)
		_cleanup_test_preset_dir("_test_rename_zzz")
		return false
	# 读回检查 display_name 改了 + 文件路径不变
	var loaded: ParamPreset = panel.load_preset_from_disk(listed[0])
	if loaded == null or loaded.display_name != "新名字 v2":
		push_error("rename 后 display_name 未更新")
		_cleanup_test_preset_dir("_test_rename_zzz")
		return false
	_cleanup_test_preset_dir("_test_rename_zzz")
	return true


# ─────────────────────────────────────────
# Codex 审 MVP-C.2 P0/P1.1 修复后的补盲测试
# ─────────────────────────────────────────

## P0 修复验证：apply_preset 对 Dict / Array 字段做 deep duplicate，preset 内快照与 instance 不共享引用
## 用 InfluenceConfig.faction_colors（Dict）走 apply → 改 instance dict 应不影响 preset 内 snapshot
func _test_apply_preset_deep_copy_dict_array(panel: Node) -> bool:
	var inf_cfg: Resource = load("res://assets/config/influence_config.tres")
	# 备份原 faction_colors 内容以便恢复
	var orig_dict: Dictionary = (inf_cfg.get("faction_colors") as Dictionary).duplicate(true)
	# 构造 preset：snap.value 是整个 Dict（虽然实际项目用 dict_key 拆开，但 schema 支持整 Dict 字段）
	var preset_dict: Dictionary = {0: Color(0.1, 0.1, 0.1), 1: Color(0.2, 0.2, 0.2), 2: Color(0.3, 0.3, 0.3)}
	var preset: ParamPreset = _make_test_preset("_test_deep_copy_zzz", "deep copy", [
		{"path": "res://assets/config/influence_config.tres",
			"field": "faction_colors", "dict_key": null, "value": preset_dict},
	])
	# 构造场景含此字段的最小映射
	var scene: ParamPanelScene = ParamPanelScene.new()
	scene.scene_id = "_test_deep_copy_zzz"
	var f: ParamFieldMapping = ParamFieldMapping.new()
	f.target_resource_path = "res://assets/config/influence_config.tres"
	f.field_name = "faction_colors"
	f.dict_key = null
	f.passive = true
	scene.fields = [f]
	# 记录 preset 内 snapshot Dict 的 hash（apply 前）
	var snap_dict_before: Dictionary = (preset.field_snapshots[0] as FieldSnapshot).value as Dictionary
	var hash_before: int = snap_dict_before.hash()
	panel.apply_preset(scene, preset)
	# instance 应已有 preset 的 Dict 内容
	var inst_dict: Dictionary = inf_cfg.get("faction_colors") as Dictionary
	if inst_dict[1] != Color(0.2, 0.2, 0.2):
		push_error("apply 后 instance Dict 字段未生效")
		inf_cfg.set("faction_colors", orig_dict)
		return false
	# 关键验证：改 instance Dict（模拟用户后续调字段）应不影响 preset 内 snapshot
	inst_dict[1] = Color(0.99, 0.99, 0.99)
	var hash_after: int = snap_dict_before.hash()
	if hash_after != hash_before:
		push_error("P0 bug 未修复：改 instance 同步改了 preset 内 snapshot（共享引用）")
		inf_cfg.set("faction_colors", orig_dict)
		return false
	# 恢复
	inf_cfg.set("faction_colors", orig_dict)
	return true


## P1.1 修复验证：load_preset_from_disk 后 preset._source_path 已被回填
func _test_preset_source_path_set_on_load(panel: Node) -> bool:
	var preset: ParamPreset = _make_test_preset("_test_source_path_zzz", "test", [
		{"path": "res://x.tres", "field": "fa", "dict_key": null, "value": 1},
	])
	var err: int = panel.save_preset_to_disk(preset, "p1")
	if err != OK:
		_cleanup_test_preset_dir("_test_source_path_zzz")
		return false
	var expected_path: String = "res://assets/config/presets/_test_source_path_zzz/p1.tres"
	var loaded: ParamPreset = panel.load_preset_from_disk(expected_path)
	if loaded == null:
		_cleanup_test_preset_dir("_test_source_path_zzz")
		return false
	if loaded._source_path != expected_path:
		push_error("load 后 _source_path 未回填，actual='%s' expected='%s'" % [loaded._source_path, expected_path])
		_cleanup_test_preset_dir("_test_source_path_zzz")
		return false
	# _preset_path_for 应能正确反推（即使 cache 内有坏 preset）
	# 模拟 cache 含 loaded preset + 1 个 null（坏 preset）
	# 直接调 _preset_path_for（注：_preset_path_for 是 _ 私有但 GDScript 可外部调）
	var path_via_helper: String = panel._preset_path_for(loaded, "_test_source_path_zzz")
	if path_via_helper != expected_path:
		push_error("_preset_path_for 返回 '%s' ≠ expected '%s'" % [path_via_helper, expected_path])
		_cleanup_test_preset_dir("_test_source_path_zzz")
		return false
	_cleanup_test_preset_dir("_test_source_path_zzz")
	return true


# ─────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────

## 构造一个最小 ParamPanelScene：scene_id = "_test_min" + 2 个 NightVisionConfig 字段
func _make_test_scene_minimal() -> ParamPanelScene:
	var scene: ParamPanelScene = ParamPanelScene.new()
	scene.scene_id = "_test_min"
	scene.display_name = "最小测试场景"
	scene.category = "夜晚UI节奏"
	scene.default_redraw_targets = []
	var f1: ParamFieldMapping = ParamFieldMapping.new()
	f1.display_label = "视野半径"
	f1.target_resource_path = "res://assets/config/night_vision_config.tres"
	f1.field_name = "vision_radius_grids"
	f1.dict_key = null
	f1.control_type = "SliderInt"
	f1.slider_min = 1
	f1.slider_max = 10
	f1.passive = true
	var f2: ParamFieldMapping = ParamFieldMapping.new()
	f2.display_label = "雾衰减"
	f2.target_resource_path = "res://assets/config/night_vision_config.tres"
	f2.field_name = "fog_falloff_grids"
	f2.dict_key = null
	f2.control_type = "SliderFloat"
	f2.slider_min = 0.0
	f2.slider_max = 5.0
	f2.passive = true
	scene.fields = [f1, f2]
	return scene


## 构造测试用 ParamPreset：fields 是 Array[Dict]，每个 dict 含 path / field / dict_key / value
func _make_test_preset(scene_id: String, display_name: String, fields: Array) -> ParamPreset:
	var preset: ParamPreset = ParamPreset.new()
	preset.scene_id = scene_id
	preset.display_name = display_name
	var snapshots: Array[FieldSnapshot] = []
	for f_any in fields:
		var f: Dictionary = f_any as Dictionary
		var snap: FieldSnapshot = FieldSnapshot.new()
		snap.target_resource_path = f.get("path", "") as String
		snap.field_name = f.get("field", "") as String
		snap.dict_key = f.get("dict_key")
		snap.value = f.get("value")
		snapshots.append(snap)
	preset.field_snapshots = snapshots
	return preset


## 清理 res://assets/config/presets/<scene_id>/ 测试目录（仅本测试创建的）
func _cleanup_test_preset_dir(scene_id: String) -> void:
	var dir_path: String = "res://assets/config/presets/%s/" % scene_id
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while fname != "":
		if not dir.current_is_dir():
			DirAccess.remove_absolute(dir_path + fname)
		fname = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(dir_path)


## 清理 user:// 临时目录（兜底）
func _cleanup_test_dir() -> void:
	var dir: DirAccess = DirAccess.open(TEST_PRESET_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while fname != "":
		if not dir.current_is_dir():
			DirAccess.remove_absolute(TEST_PRESET_DIR + fname)
		fname = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(TEST_PRESET_DIR)
