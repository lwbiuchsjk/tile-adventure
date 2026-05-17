extends SceneTree
## MVP-C.1 修补验证：_dump_resource_fields 字段完整性
##
## 加载 unit_enemy_config.tres / influence_config.tres 实例 → 调 dump → 验证字段数 + 关键字段存在
## 不实际写 .tres 文件（避免污染源文件）；只验证 dump 输出文本

const ControllerScript: GDScript = preload("res://scripts/ui/ParamPanelController.gd")


func _init() -> void:
	var panel: Node = Node.new()
	panel.set_script(ControllerScript)
	var ok: bool = true
	# unit_enemy schema 14 @export 字段（REPELLED 清理批已移除 repelled_border_color）
	ok = _test_dump(panel, "res://assets/config/unit_enemy_config.tres", 14, [
		"unit_color", "unit_shadow_color", "unit_margin", "unit_player_ring_width",
		"challenged_dim", "enemy_slot_color", "enemy_border_color",
		"tier_border_color", "tier_border_widths", "tier_dot_color",
		"tier_dot_size_ratio", "tier_slot_margins",
		"enemy_move_color", "enemy_glow_color",
	]) and ok
	ok = _test_dump(panel, "res://assets/config/influence_config.tres", 12, [
		"faction_colors", "influence_alpha_outer", "influence_alpha_mid", "influence_alpha_inner",
		"influence_border_alpha", "influence_border_width",
		"core_town_border", "core_town_emblem_size",
		"persistent_ring_width", "persistent_separator_color",
		"persistent_separator_width", "persistent_inner_bg",
	]) and ok
	ok = _test_dump(panel, "res://assets/config/night_vision_config.tres", 10, [
		"vision_radius_grids", "fog_falloff_grids", "fade_duration",
		"blink_base_alpha", "blink_period",
	]) and ok
	# Dict 完整性验证（faction_colors 三 key 都在）
	ok = _test_dict_keys(panel, "res://assets/config/influence_config.tres",
		"faction_colors", [0, 1, 2]) and ok
	# Dict 完整性验证（tier_border_widths 0-3）
	ok = _test_dict_keys(panel, "res://assets/config/unit_enemy_config.tres",
		"tier_border_widths", [0, 1, 2, 3]) and ok
	# 端到端：复制源 .tres 到 user:// + 调 _save_dirty_resource_custom + 验证字段数保持
	ok = _test_e2e_save(panel, "res://assets/config/unit_enemy_config.tres") and ok
	ok = _test_e2e_save(panel, "res://assets/config/influence_config.tres") and ok
	ok = _test_e2e_save(panel, "res://assets/config/night_vision_config.tres") and ok
	# Roundtrip：dump 后加载回来字段值与原 instance 严格相等（验证序列化格式正确性）
	ok = _test_e2e_roundtrip(panel, "res://assets/config/unit_enemy_config.tres") and ok
	ok = _test_e2e_roundtrip(panel, "res://assets/config/influence_config.tres") and ok
	ok = _test_e2e_roundtrip(panel, "res://assets/config/night_vision_config.tres") and ok
	ok = _test_e2e_roundtrip(panel, "res://assets/config/battle_visual_config.tres") and ok
	ok = _test_e2e_roundtrip(panel, "res://assets/config/battle_anim_config.tres") and ok
	ok = _test_e2e_roundtrip(panel, "res://assets/config/map_base_config.tres") and ok
	ok = _test_e2e_roundtrip(panel, "res://assets/config/overlay_transition_config.tres") and ok
	ok = _test_e2e_roundtrip(panel, "res://assets/config/resource_render_config.tres") and ok
	if ok:
		print("[test_param_panel_dump] 全部通过")
		quit(0)
	else:
		print("[test_param_panel_dump] 有失败项")
		quit(1)


## 端到端 e2e：复制源 .tres 到 user:// + 调 _save_dirty_resource_custom 实际写回 + 验证字段数保持
func _test_e2e_save(panel: Node, src_path: String) -> bool:
	var tmp_path: String = "user://test_save_%s" % src_path.get_file()
	# 复制源文本到临时
	var src_file: FileAccess = FileAccess.open(src_path, FileAccess.READ)
	if src_file == null:
		print("[FAIL] e2e 源文件读失败：", src_path)
		return false
	var src_text: String = src_file.get_as_text()
	src_file.close()
	var tmp_file: FileAccess = FileAccess.open(tmp_path, FileAccess.WRITE)
	tmp_file.store_string(src_text)
	tmp_file.close()
	# 加载原 instance
	var instance: Resource = load(src_path)
	if instance == null:
		print("[FAIL] e2e instance 加载失败：", src_path)
		return false
	# 调用 dump 写回临时
	var err_v: Variant = panel.call("_save_dirty_resource_custom", tmp_path, instance)
	var err: int = err_v as int
	if err != OK:
		print("[FAIL] e2e dump 写回 err=", err)
		return false
	# 读 dump 输出 + 比对字段数
	var dump_file: FileAccess = FileAccess.open(tmp_path, FileAccess.READ)
	var dump_text: String = dump_file.get_as_text()
	dump_file.close()
	var orig_count: int = _count_field_lines(src_text)
	var dump_count: int = _count_field_lines(dump_text)
	if orig_count != dump_count:
		print("[FAIL] e2e %s 字段数：原 %d dump %d" % [src_path.get_file(), orig_count, dump_count])
		print("  --- dump 内容预览（前 40 行）---")
		var dump_lines: PackedStringArray = dump_text.split("\n")
		for i in min(40, dump_lines.size()):
			print("    ", dump_lines[i])
		return false
	print("[PASS] e2e %s 字段数 %d ✓" % [src_path.get_file(), dump_count])
	return true


## Roundtrip 验证：dump 写回临时 path + 重新加载 + 字段值与原严格相等
## 8 份 Resource 全做（捕获 Color / Dict / float / int / String / bool 各类型序列化问题）
func _test_e2e_roundtrip(panel: Node, src_path: String) -> bool:
	var tmp_path: String = "user://test_rt_%s" % src_path.get_file()
	# 复制源到临时（dump 函数需要原 .tres 拿 header）
	var src_file: FileAccess = FileAccess.open(src_path, FileAccess.READ)
	if src_file == null:
		return false
	var src_text: String = src_file.get_as_text()
	src_file.close()
	var tmp_file: FileAccess = FileAccess.open(tmp_path, FileAccess.WRITE)
	tmp_file.store_string(src_text)
	tmp_file.close()
	var instance_a: Resource = load(src_path)
	if instance_a == null:
		return false
	# Dump 写回临时
	var err_v: Variant = panel.call("_save_dirty_resource_custom", tmp_path, instance_a)
	if (err_v as int) != OK:
		print("[FAIL] roundtrip %s dump err=%d" % [src_path.get_file(), err_v as int])
		return false
	# 重新加载临时 path（CACHE_MODE_IGNORE 强制重新解析 .tres）
	var instance_b: Resource = ResourceLoader.load(tmp_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if instance_b == null:
		print("[FAIL] roundtrip %s dump 后加载失败" % src_path.get_file())
		return false
	# 比对所有 @export 字段值
	var diffs: int = 0
	for prop_any in instance_a.get_script().get_script_property_list():
		var prop: Dictionary = prop_any
		var usage: int = prop.get("usage", 0) as int
		if not (usage & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		if usage & (PROPERTY_USAGE_CATEGORY | PROPERTY_USAGE_GROUP | PROPERTY_USAGE_SUBGROUP):
			continue
		var pname: String = prop.get("name", "") as String
		var va: Variant = instance_a.get(pname)
		var vb: Variant = instance_b.get(pname)
		if va != vb:
			diffs += 1
			print("  [diff] %s: a=%s b=%s" % [pname, str(va), str(vb)])
	if diffs > 0:
		print("[FAIL] roundtrip %s 有 %d 字段不一致" % [src_path.get_file(), diffs])
		return false
	print("[PASS] roundtrip %s 全字段值匹配" % src_path.get_file())
	return true


## 数 .tres 内 "fieldname = " 行（排除 script= 行）
func _count_field_lines(text: String) -> int:
	var c: int = 0
	for line in text.split("\n"):
		var s: String = line as String
		if s.contains(" = ") and not s.begins_with("script = "):
			c += 1
	return c


func _test_dump(panel: Node, path: String, expected_field_count: int, must_have: Array) -> bool:
	var instance: Resource = load(path)
	if instance == null:
		print("[FAIL] 加载失败: ", path)
		return false
	var lines_v: Variant = panel.call("_dump_resource_fields", instance)
	if not lines_v is PackedStringArray:
		print("[FAIL] dump 返回非 PackedStringArray: ", typeof(lines_v))
		return false
	var lines: PackedStringArray = lines_v as PackedStringArray
	# 数 "field_name = " 行数
	var field_lines: int = 0
	for line in lines:
		# Dict 内 "0: 2.0," 行也在 lines 内（多行 Dict），过滤
		if (line as String).contains(" = "):
			field_lines += 1
	var pass_count: bool = field_lines == expected_field_count
	if not pass_count:
		print("[FAIL] %s 字段数：期望 %d 实际 %d" % [path.get_file(), expected_field_count, field_lines])
		print("  输出预览（前 40 行）：")
		for i in min(40, lines.size()):
			print("    ", lines[i])
		return false
	# 验证必有字段全都在 dump 输出内
	var dump_text: String = "\n".join(lines)
	for field_name in must_have:
		if not dump_text.contains("%s = " % field_name):
			print("[FAIL] %s 缺关键字段：%s" % [path.get_file(), field_name])
			return false
	print("[PASS] %s 字段数 %d ✓ + %d 个关键字段全在" % [path.get_file(), field_lines, must_have.size()])
	return true


func _test_dict_keys(panel: Node, path: String, field_name: String, expected_keys: Array) -> bool:
	var instance: Resource = load(path)
	if instance == null:
		return false
	var lines_v: Variant = panel.call("_dump_resource_fields", instance)
	var lines: PackedStringArray = lines_v as PackedStringArray
	var dump_text: String = "\n".join(lines)
	for k in expected_keys:
		var pattern: String = "%s: " % str(k)
		if not dump_text.contains(pattern):
			print("[FAIL] %s Dict 字段 %s 缺 key %s" % [path.get_file(), field_name, str(k)])
			return false
	print("[PASS] %s.%s Dict %d 个 key 全在" % [path.get_file(), field_name, expected_keys.size()])
	return true
