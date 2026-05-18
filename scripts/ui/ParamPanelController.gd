extends Node
## MVP-C.1 调参面板主控制器：扫场景目录 → F1 唤起 → ImGui 渲染 → 数据流写回
##
## 不写 class_name —— 本脚本作 autoload (ParamPanelController) 使用，
## autoload 名称已是全局符号；写 class_name 会触发 "hides an autoload singleton" parse error。
##
## 设计原文：
##   tile-advanture-design/参数Resource化/MVP-C_运行时调参面板.md §6 数据流架构
##
## 唤起 / 保存快捷键：
##   F1 = 切换面板显示
##   F2 = 写回所有 dirty 的 .tres（避免与 imgui Ctrl+S 内部行为冲突）
##
## 依赖：
##   - addons/imgui-godot v6.3.2（ImGuiRoot autoload）
##   - assets/config/param_panel/*.tres 场景目录（ParamPanelScene 实例）
##
## release 守卫：非 editor 构建直接 queue_free，玩家版无面板。


## 场景目录扫描根路径
const SCENE_DIR: String = "res://assets/config/param_panel/"


# ─────────────────────────────────────────
# 状态
# ─────────────────────────────────────────

## 面板是否可见
var _visible: bool = false

## 已加载的所有场景（顺序 = 文件名字母序）
var _scenes: Array[ParamPanelScene] = []

## 按 category 大类分组的场景索引：category(String) → Array[ParamPanelScene]
var _scenes_by_category: Dictionary = {}

## 已被修改的 Resource：resource_path(String) → Resource 实例
var _dirty_resources: Dictionary = {}

## 帧末 defer 的 redraw 目标节点名集合：node_name(String) → true（Dict 去重）
var _pending_redraw: Dictionary = {}

## ImGui 控件的 binding 缓存：state_key(String) → Array[float/int]
## state_key = "<resource_path>::<field_name>::<dict_key>"
## 首次创建时从 Resource 实例当前值读入；之后由 imgui 控件管理
var _control_state: Dictionary = {}

## 字段值快照（用于「重置到打开前值」）：state_key(String) → Variant（原始值的副本）
## 启动时 + 每次 F2 写回成功后重新捕获 —— "打开前快照" = 上次保存时的状态 或 Godot 启动时的初始值
var _opened_snapshot: Dictionary = {}


# ─────────────────────────────────────────
# 生命周期
# ─────────────────────────────────────────

func _ready() -> void:
	# Release 守卫：非 editor 构建直接清退（Web 导出 + 玩家版）
	if not OS.has_feature("editor"):
		queue_free()
		return
	_load_all_scenes()
	_capture_snapshot()
	print("[ParamPanel] 已加载 %d 场景（F1 唤起 / F2 保存）" % _scenes.size())


## 遍历所有场景全字段读当前 preload 实例值 → 存入 _opened_snapshot
## 时机：启动时 + 每次 F2 写回成功后（即"打开前值" = 上次保存的状态）
func _capture_snapshot() -> void:
	_opened_snapshot.clear()
	for scene_any in _scenes:
		var scene: ParamPanelScene = scene_any as ParamPanelScene
		for field in _get_snapshot_fields(scene):
			var instance: Resource = load(field.target_resource_path)
			if instance == null:
				continue
			var key: String = _make_state_key(field)
			var val: Variant = _read_field_value(instance, field)
			# P2 修复：Dictionary / Array 是引用类型，必须 deep duplicate 避免 snapshot 与 instance 共享引用
			# 否则用户改字段会同步修改 snapshot 内的"原始值"，reset 时回不到打开前状态
			# Color / float / int / String / bool 是值类型，直接赋值即可
			if val is Dictionary:
				_opened_snapshot[key] = (val as Dictionary).duplicate(true)
			elif val is Array:
				_opened_snapshot[key] = (val as Array).duplicate(true)
			else:
				_opened_snapshot[key] = val


## 扫描 SCENE_DIR 下所有 .tres 加载为 ParamPanelScene
func _load_all_scenes() -> void:
	var dir: DirAccess = DirAccess.open(SCENE_DIR)
	if dir == null:
		push_warning("[ParamPanel] 场景目录不存在 %s（首次启动可忽略）" % SCENE_DIR)
		return
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while fname != "":
		if fname.ends_with(".tres") and not dir.current_is_dir():
			var res: Resource = load(SCENE_DIR + fname)
			if res is ParamPanelScene:
				var scene: ParamPanelScene = res as ParamPanelScene
				_scenes.append(scene)
				if not _scenes_by_category.has(scene.category):
					_scenes_by_category[scene.category] = []
				(_scenes_by_category[scene.category] as Array).append(scene)
		fname = dir.get_next()
	dir.list_dir_end()


# ─────────────────────────────────────────
# 输入：F1 切换 / F2 保存
# ─────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key_event: InputEventKey = event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	match key_event.keycode:
		KEY_F1:
			_visible = not _visible
			get_viewport().set_input_as_handled()
		KEY_F2:
			_save_dirty_resources()
			get_viewport().set_input_as_handled()


# ─────────────────────────────────────────
# 主帧循环：ImGui 渲染 + redraw flush
# ─────────────────────────────────────────

func _process(_delta: float) -> void:
	if _visible:
		_render_panel()
	# 每帧末把累计的 redraw 目标合并去重触发（即使不显示面板，也要 flush 上一帧的）
	_flush_pending_redraw()


## ImGui 主面板：按 category 大类 → scene 二级 TreeNode 渲染
func _render_panel() -> void:
	if not ImGui.Begin("调参面板  [F1 关闭] [F2 保存]"):
		ImGui.End()
		return
	# 顶部状态行
	var dirty_count: int = _dirty_resources.size()
	if dirty_count > 0:
		ImGui.TextColored(Color(1.0, 0.7, 0.2, 1.0), "* 未保存改动：%d 份 Resource（按 F2 写回）" % dirty_count)
	else:
		ImGui.Text("无未保存改动")
	# 全部重置按钮（重置到打开前快照 = 上次 F2 保存后状态 或 启动初始值）
	ImGui.SameLine()
	if ImGui.SmallButton("全部重置##reset_all"):
		_reset_all()
	if ImGui.IsItemHovered():
		ImGui.SetTooltip("重置所有字段到打开前快照（= 上次 F2 保存后的状态 或 Godot 启动初始值）")
	ImGui.Separator()
	# 按 category 大类展开
	for category in _scenes_by_category.keys():
		if ImGui.TreeNode(category as String):
			var scenes: Array = _scenes_by_category[category]
			for scene_any in scenes:
				var scene: ParamPanelScene = scene_any as ParamPanelScene
				if ImGui.TreeNode(scene.display_name):
					_render_scene(scene)
					ImGui.TreePop()
			ImGui.TreePop()
	ImGui.End()


## 渲染单个场景的字段列表（连续相同 group_name 自动 SeparatorText 分隔）
func _render_scene(scene: ParamPanelScene) -> void:
	var current_group: String = ""
	for field_any in scene.fields:
		var field: ParamFieldMapping = field_any as ParamFieldMapping
		if field == null:
			continue
		# group_name 切换 → 插分隔
		if field.group_name != current_group:
			if field.group_name != "":
				ImGui.SeparatorText(field.group_name)
			current_group = field.group_name
		_render_field(scene, field)
	for group_any in scene.dict_combo_groups:
		var group: DictComboGroup = group_any as DictComboGroup
		if group == null:
			continue
		_render_dict_combo_group(scene, group)


## 渲染单个字段控件（按 control_type 分发）+ hover 路径 tooltip + [↻] [复制] 按钮
func _render_field(scene: ParamPanelScene, field: ParamFieldMapping) -> void:
	var instance: Resource = load(field.target_resource_path)
	if instance == null:
		ImGui.TextColored(Color(1.0, 0.3, 0.3, 1.0), "[err] %s 加载失败" % field.target_resource_path)
		return
	var state_key: String = _make_state_key(field)
	match field.control_type:
		"SliderFloat":
			_render_slider_float(scene, field, instance, state_key)
		"SliderInt":
			_render_slider_int(scene, field, instance, state_key)
		"ColorEdit3":
			_render_color_edit(scene, field, instance, state_key, false)
		"ColorEdit4":
			_render_color_edit(scene, field, instance, state_key, true)
		"InputText":
			_render_input_text(scene, field, instance, state_key)
		_:
			ImGui.Text("%s [未支持控件: %s]" % [field.display_label, field.control_type])
	# hover 控件 → 弹路径 tooltip + 用户自定义 tooltip（B1 需求：位置查看）
	if ImGui.IsItemHovered():
		ImGui.BeginTooltip()
		if field.tooltip != "":
			ImGui.Text(field.tooltip)
			ImGui.Separator()
		ImGui.Text("字段位置：")
		ImGui.Text(field.target_resource_path)
		var dict_suffix: String = "[%s]" % str(field.dict_key) if field.dict_key != null else ""
		ImGui.Text("    -> %s%s" % [field.field_name, dict_suffix])
		ImGui.EndTooltip()
	# 右侧 [重置] reset 单字段（A1 需求：重置到打开前快照）
	# 用中文按钮避免 SourceHanSansSC 字体缺 ↻ / emoji 字符（实测显示为 [?]）
	ImGui.SameLine()
	if ImGui.SmallButton("重置##reset_" + state_key):
		_reset_field(scene, field)
	if ImGui.IsItemHovered():
		ImGui.SetTooltip("重置该字段到打开前快照值")
	# 右侧 [复制] 复制完整位置到剪贴板（B3 需求：便于 git 查询）
	ImGui.SameLine()
	if ImGui.SmallButton("复制##copy_" + state_key):
		var dict_suffix: String = "[%s]" % str(field.dict_key) if field.dict_key != null else ""
		var copy_text: String = "%s -> %s%s" % [field.target_resource_path, field.field_name, dict_suffix]
		DisplayServer.clipboard_set(copy_text)
		print("[ParamPanel] 已复制：%s" % copy_text)
	if ImGui.IsItemHovered():
		ImGui.SetTooltip("复制「字段位置」到剪贴板（便于粘贴到 git log 命令）")


## 渲染 DictComboGroup：先选 dict_key，再用运行时字段副本复用普通字段控件链路
func _render_dict_combo_group(scene: ParamPanelScene, group: DictComboGroup) -> void:
	if group.dict_keys.is_empty() or group.linked_fields.is_empty():
		return
	if group.group_label != "":
		ImGui.SeparatorText(group.group_label)
	var combo_key: String = _make_combo_state_key(scene, group)
	if not _control_state.has(combo_key):
		_control_state[combo_key] = [0]
	var current_index_arr: Array = _control_state[combo_key]
	var old_index: int = clampi(int(current_index_arr[0]), 0, group.dict_keys.size() - 1)
	current_index_arr[0] = old_index
	var labels: PackedStringArray = _get_combo_display_names(group)
	if ImGui.Combo("%s##%s" % [group.group_label, combo_key], current_index_arr, labels):
		# Combo 切 key 后清掉所有联动字段缓存；下帧会从新 dict_key 重新读值。
		_invalidate_combo_linked_field_state(group)
	var selected_index: int = clampi(int(current_index_arr[0]), 0, group.dict_keys.size() - 1)
	var selected_key: Variant = group.dict_keys[selected_index]
	for field_any in group.linked_fields:
		var linked_field: ParamFieldMapping = field_any as ParamFieldMapping
		if linked_field == null:
			continue
		var runtime_field: ParamFieldMapping = _make_combo_runtime_field(linked_field, selected_key, group.group_label)
		_render_field(scene, runtime_field)


## ImGui label 加 "##<state_key>" 后缀：## 后内容不显示但参与 widget ID 计算
## 解决 4 Tier 重名「描边宽度 / 外菱形占格比」等场景 ID 冲突
func _make_imgui_label(field: ParamFieldMapping, state_key: String) -> String:
	return "%s##%s" % [field.display_label, state_key]


func _render_slider_float(scene: ParamPanelScene, field: ParamFieldMapping, instance: Resource, state_key: String) -> void:
	if not _control_state.has(state_key):
		var raw: Variant = _read_field_value(instance, field)
		if raw == null:
			ImGui.TextColored(Color(1.0, 0.3, 0.3, 1.0), "[err] %s 值为 null（dict_key 配错？）" % field.display_label)
			return
		# 用 float() 显式 conversion 而非 as float —— int→float 通过；as float 对 int 返回 null
		_control_state[state_key] = [float(raw)]
	var arr: Array = _control_state[state_key]
	if ImGui.SliderFloat(_make_imgui_label(field, state_key), arr, field.slider_min, field.slider_max):
		_on_field_changed(scene, field, arr[0])


func _render_slider_int(scene: ParamPanelScene, field: ParamFieldMapping, instance: Resource, state_key: String) -> void:
	if not _control_state.has(state_key):
		var raw: Variant = _read_field_value(instance, field)
		if raw == null:
			ImGui.TextColored(Color(1.0, 0.3, 0.3, 1.0), "[err] %s 值为 null（dict_key 配错？）" % field.display_label)
			return
		_control_state[state_key] = [int(raw)]
	var arr: Array = _control_state[state_key]
	if ImGui.SliderInt(_make_imgui_label(field, state_key), arr, int(field.slider_min), int(field.slider_max)):
		_on_field_changed(scene, field, arr[0])


## Color 字段渲染（ColorEdit3 = 不含 alpha / ColorEdit4 = 含 alpha）
## 关键陷阱：必须传 Array[float]，不能直接传 Color 对象（Phase 2 预研踩过，binding 用 INT_MIN 占位卡死 UI）
func _render_color_edit(scene: ParamPanelScene, field: ParamFieldMapping, instance: Resource, state_key: String, with_alpha: bool) -> void:
	var raw_color: Variant = _read_field_value(instance, field)
	if raw_color == null or not raw_color is Color:
		ImGui.TextColored(Color(1.0, 0.3, 0.3, 1.0), "[err] %s 非 Color 字段（dict_key 配错？）" % field.display_label)
		return
	var current_color: Color = raw_color as Color
	if not _control_state.has(state_key):
		if with_alpha:
			_control_state[state_key] = [current_color.r, current_color.g, current_color.b, current_color.a]
		else:
			_control_state[state_key] = [current_color.r, current_color.g, current_color.b]
	var arr: Array = _control_state[state_key]
	var changed: bool = false
	var label: String = _make_imgui_label(field, state_key)
	if with_alpha:
		changed = ImGui.ColorEdit4(label, arr)
		if changed:
			_on_field_changed(scene, field, Color(arr[0], arr[1], arr[2], arr[3]))
	else:
		changed = ImGui.ColorEdit3(label, arr)
		if changed:
			# 保留原 alpha（如字段是 Color 含 alpha 但 ColorEdit3 不编辑）
			_on_field_changed(scene, field, Color(arr[0], arr[1], arr[2], current_color.a))


## String 字段渲染：用于 OverlayTransitionConfig.icon_fallback 这类短文本参数
func _render_input_text(scene: ParamPanelScene, field: ParamFieldMapping, instance: Resource, state_key: String) -> void:
	if not _control_state.has(state_key):
		var raw: Variant = _read_field_value(instance, field)
		if raw == null:
			ImGui.TextColored(Color(1.0, 0.3, 0.3, 1.0), "[err] %s 值为 null" % field.display_label)
			return
		_control_state[state_key] = [str(raw)]
	var arr: Array = _control_state[state_key]
	# imgui-godot v6.3.2 binding：InputText(label, text_array, buffer_size)，buffer 为 String 字节长度上限
	if ImGui.InputText(_make_imgui_label(field, state_key), arr, 256):
		_on_field_changed(scene, field, str(arr[0]))


# ─────────────────────────────────────────
# 数据流核心：写实例 + 标 dirty + 标 redraw pending
# ─────────────────────────────────────────

## 字段变更触发：写回 preload 实例属性 + 标 dirty + 收集 redraw 目标
func _on_field_changed(scene: ParamPanelScene, field: ParamFieldMapping, new_value: Variant) -> void:
	var instance: Resource = load(field.target_resource_path)
	if instance == null:
		return
	if field.dict_key == null:
		instance.set(field.field_name, new_value)
	else:
		# Dict 字段：必须 get 出 Dict 再修改，因 Godot Dict 是引用类型，修改后无需 set
		var dict: Dictionary = instance.get(field.field_name)
		dict[field.dict_key] = new_value
	_dirty_resources[field.target_resource_path] = instance
	if not field.passive:
		var targets: Array[String] = _get_effective_redraw_targets(scene, field)
		for t in targets:
			_pending_redraw[t] = true


## 计算有效 redraw 目标：场景级 default + 字段级 override
func _get_effective_redraw_targets(scene: ParamPanelScene, field: ParamFieldMapping) -> Array[String]:
	if not field.redraw_targets_override.is_empty():
		return field.redraw_targets_override
	return scene.default_redraw_targets


## 帧末 defer redraw：合并去重 → 逐节点 find_child + queue_redraw
## 节点不存在 = print warning 跳过（场景目录与节点解耦，节点未实例化时宽松处理）
func _flush_pending_redraw() -> void:
	if _pending_redraw.is_empty():
		return
	var tree: SceneTree = get_tree()
	if tree == null or tree.root == null:
		_pending_redraw.clear()
		return
	for node_name_any in _pending_redraw.keys():
		var node_name: String = node_name_any as String
		var node: Node = tree.root.find_child(node_name, true, false)
		if node == null:
			push_warning("[ParamPanel] redraw_target '%s' 未找到（场景未加载？），跳过" % node_name)
			continue
		if node.has_method("queue_redraw"):
			node.queue_redraw()
		else:
			push_warning("[ParamPanel] redraw_target '%s' 无 queue_redraw 方法，跳过" % node_name)
	_pending_redraw.clear()


# ─────────────────────────────────────────
# 持久化：F2 写回所有 dirty .tres
# ─────────────────────────────────────────

## F2 写回原 .tres，仅写回 dirty 的（避免无意义 git diff）
## 写回成功后重新捕获快照 —— 新的"打开前快照" = 此次保存后的状态
##
## ⚠ 不能用 ResourceSaver.save：Godot 4 默认行为是省略 ==script_default_value 字段，
##   导致 .tres 从原 N 字段瘦身到仅 dirty 字段，git diff 一改就是几十行噪音。
##   改用 _save_dirty_resource_custom（保留原 header 含注释 + ext_resource，重新 dump 所有 @export 字段）。
func _save_dirty_resources() -> void:
	if _dirty_resources.is_empty():
		print("[ParamPanel] F2 触发但无未保存改动")
		return
	var saved_paths: PackedStringArray = []
	var failed: int = 0
	for path_any in _dirty_resources.keys():
		var path: String = path_any as String
		var err: int = _save_dirty_resource_custom(path, _dirty_resources[path])
		if err == OK:
			saved_paths.append(path)
		else:
			failed += 1
			push_error("[ParamPanel] 写回失败 %s (err=%d)" % [path, err])
	print("[ParamPanel] F2 写回 %d 份 Resource（失败 %d）" % [saved_paths.size(), failed])
	# P0 修复：仅清除保存成功的 dirty path；失败项保留以便用户再次 F2 重试，避免改动丢失
	for path in saved_paths:
		_dirty_resources.erase(path)
	# 仅在全部成功时重新 snapshot；部分失败则保持原 snapshot
	# 否则失败项的内存值会被错误标成"已保存基准"，reset 无法回到打开前值
	if failed == 0 and saved_paths.size() > 0:
		_capture_snapshot()
		print("[ParamPanel] 快照已更新（reset 基准 = 此次保存后的状态）")
	elif failed > 0:
		print("[ParamPanel] 因 %d 份保存失败，未更新快照（reset 基准保持原值）" % failed)


# ─────────────────────────────────────────
# 自定义 .tres dump（绕过 ResourceSaver 省略默认值的行为）
# ─────────────────────────────────────────

## 自定义 .tres 写回：保留原 header（含注释 + ext_resource + [resource] + script= 行）
## 之后用 instance 完整 dump 所有 @export 字段，不省略 ==default 字段
func _save_dirty_resource_custom(path: String, instance: Resource) -> int:
	# 读原 .tres 文本
	var read_file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if read_file == null:
		return ERR_FILE_CANT_OPEN
	var orig_text: String = read_file.get_as_text()
	read_file.close()
	# 定位 header 末尾（"script = ExtResource(...)" 行）
	var lines: PackedStringArray = orig_text.split("\n")
	var script_line_idx: int = -1
	for i in lines.size():
		if (lines[i] as String).begins_with("script = ExtResource("):
			script_line_idx = i
			break
	if script_line_idx == -1:
		push_error("[ParamPanel] %s 未找到 'script = ExtResource(...)' 行，无法保留 header" % path)
		return ERR_FILE_CORRUPT
	# 组装新 .tres = 原 header（截至 script= 行）+ 重新 dump 所有 @export 字段
	var header: PackedStringArray = lines.slice(0, script_line_idx + 1)
	var body: PackedStringArray = _dump_resource_fields(instance)
	var new_text: String = "\n".join(header) + "\n" + "\n".join(body) + "\n"
	# 写回
	var out: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if out == null:
		return ERR_FILE_CANT_WRITE
	out.store_string(new_text)
	out.close()
	return OK


## 从 instance + script @export 列表生成字段 dump 行
## 过滤 group / category / subgroup 等非数据属性
func _dump_resource_fields(instance: Resource) -> PackedStringArray:
	var lines: PackedStringArray = []
	var script: Script = instance.get_script()
	if script == null:
		return lines
	for prop_any in script.get_script_property_list():
		var prop: Dictionary = prop_any
		var pname: String = prop.get("name", "") as String
		var usage: int = prop.get("usage", 0) as int
		if not (usage & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		if usage & (PROPERTY_USAGE_CATEGORY | PROPERTY_USAGE_GROUP | PROPERTY_USAGE_SUBGROUP):
			continue
		if pname == "":
			continue
		var val: Variant = instance.get(pname)
		lines.append("%s = %s" % [pname, _serialize_value(val)])
	return lines


## Variant serializer：用 var_to_str 输出 Godot 字面量风格，与 ResourceSaver 文本风格一致
##
## 关键洞察：
##   1. `str(Color.r)` 输出 14 位全精度（如 "0.55000001192093"），噪音；
##      `var_to_str(Color)` 用 Godot 内部"最少可还原 float32 精度"算法，输出 `Color(0.55, 0.55, 0.55, 1)`
##   2. Dict 多行格式手写（var_to_str 默认单行，与原 .tres 多行不一致引入 diff 噪音）
##   3. ImGui ColorEdit3 float-mode 输出本身含长尾（user 选 "0.1" 可能拿到 0.100000046 这种 float32 中间值），
##      dump Color 时主动 snappedf 到 0.001 精度（人眼分辨不出 1/1000 vs 1/256 ≈ 0.004 差别），
##      避免 var_to_str 忠实输出 ImGui 长尾导致 diff 噪音；其他 float 字段（如 tilt_rad）保留精度不截
func _serialize_value(val: Variant) -> String:
	if val is Dictionary:
		# 多行格式匹配 .tres 原风格；内部 key / value 递归调本函数（Color 也截断）
		var d: Dictionary = val as Dictionary
		var parts: PackedStringArray = ["{"]
		for k in d.keys():
			parts.append("%s: %s," % [var_to_str(k), _serialize_value(d[k])])
		parts.append("}")
		return "\n".join(parts)
	if val is Color:
		# Color 各分量截断到 0.001 精度避免 ImGui float-mode 输入产生 0.100000046 长尾噪音
		var c: Color = val as Color
		var snap: Color = Color(
			snappedf(c.r, 0.001),
			snappedf(c.g, 0.001),
			snappedf(c.b, 0.001),
			snappedf(c.a, 0.001)
		)
		return var_to_str(snap)
	# float / int / String / bool / Vector2 等其他类型 var_to_str 输出 Godot 字面量
	return var_to_str(val)


# ─────────────────────────────────────────
# Reset：单字段 / 全部 重置到打开前快照
# ─────────────────────────────────────────

## 重置单字段到快照值 + 触发 redraw + 清 _control_state（下帧重新初始化）
func _reset_field(scene: ParamPanelScene, field: ParamFieldMapping) -> void:
	var key: String = _make_state_key(field)
	if not _opened_snapshot.has(key):
		push_warning("[ParamPanel] reset 失败：state_key '%s' 无快照" % key)
		return
	var snap_val: Variant = _opened_snapshot[key]
	var instance: Resource = load(field.target_resource_path)
	if instance == null:
		return
	if field.dict_key == null:
		instance.set(field.field_name, snap_val)
	else:
		var dict: Dictionary = instance.get(field.field_name)
		dict[field.dict_key] = snap_val
	_control_state.erase(key)
	# 即使是 passive 字段，reset 也触发 redraw 让视觉同步
	var targets: Array[String] = _get_effective_redraw_targets(scene, field)
	for t in targets:
		_pending_redraw[t] = true


## 重置所有字段到打开前快照
## 注意：不能简单遍历 _opened_snapshot 因丢失 scene/field 上下文，需重走 scenes
func _reset_all() -> void:
	var redraw_targets_union: Dictionary = {}
	for scene_any in _scenes:
		var scene: ParamPanelScene = scene_any as ParamPanelScene
		for field in _get_snapshot_fields(scene):
			var key: String = _make_state_key(field)
			if not _opened_snapshot.has(key):
				continue
			var instance: Resource = load(field.target_resource_path)
			if instance == null:
				continue
			var snap_val: Variant = _opened_snapshot[key]
			if field.dict_key == null:
				instance.set(field.field_name, snap_val)
			else:
				var dict: Dictionary = instance.get(field.field_name)
				dict[field.dict_key] = snap_val
			for t in _get_effective_redraw_targets(scene, field):
				redraw_targets_union[t] = true
	_control_state.clear()
	_dirty_resources.clear()
	for t in redraw_targets_union.keys():
		_pending_redraw[t] = true
	print("[ParamPanel] 全部重置完成（%d 字段恢复打开前快照）" % _opened_snapshot.size())


# ─────────────────────────────────────────
# Helper
# ─────────────────────────────────────────

## 收集需要进入快照 / 全部重置的字段；Combo 联动字段按所有候选 dict_key 展开
func _get_snapshot_fields(scene: ParamPanelScene) -> Array[ParamFieldMapping]:
	var result: Array[ParamFieldMapping] = []
	for field_any in scene.fields:
		var field: ParamFieldMapping = field_any as ParamFieldMapping
		if field != null:
			result.append(field)
	for group_any in scene.dict_combo_groups:
		var group: DictComboGroup = group_any as DictComboGroup
		if group == null:
			continue
		for key in group.dict_keys:
			for field_any in group.linked_fields:
				var linked_field: ParamFieldMapping = field_any as ParamFieldMapping
				if linked_field == null:
					continue
				result.append(_make_combo_runtime_field(linked_field, key, group.group_label))
	return result


## 生成 Combo 联动字段运行时副本，只覆盖 dict_key / 分组名，不修改 .tres 中的模板字段
func _make_combo_runtime_field(field: ParamFieldMapping, dict_key: Variant, group_label: String) -> ParamFieldMapping:
	var runtime_field: ParamFieldMapping = field.duplicate(true) as ParamFieldMapping
	runtime_field.dict_key = dict_key
	if runtime_field.group_name == "" and group_label != "":
		runtime_field.group_name = group_label
	return runtime_field


## Combo 控件自身的状态 key：按 scene_id + group_label 隔离，避免不同场景同名组互相污染
func _make_combo_state_key(scene: ParamPanelScene, group: DictComboGroup) -> String:
	return "%s:combo:%s" % [scene.scene_id, group.group_label]


## 生成 Combo 下拉展示名；数量不一致时回退到 dict_key 的字符串值，保证面板仍可用
func _get_combo_display_names(group: DictComboGroup) -> PackedStringArray:
	var labels: PackedStringArray = []
	for i in group.dict_keys.size():
		if i < group.key_display_names.size() and group.key_display_names[i] != "":
			labels.append(group.key_display_names[i])
		else:
			labels.append(str(group.dict_keys[i]))
	return labels


## 清理 Combo 联动字段全部候选 key 的控件缓存，避免切 key 后继续显示上一 key 的 binding 数组
func _invalidate_combo_linked_field_state(group: DictComboGroup) -> void:
	for key in group.dict_keys:
		for field_any in group.linked_fields:
			var linked_field: ParamFieldMapping = field_any as ParamFieldMapping
			if linked_field == null:
				continue
			var runtime_field: ParamFieldMapping = _make_combo_runtime_field(linked_field, key, group.group_label)
			_control_state.erase(_make_state_key(runtime_field))


func _make_state_key(field: ParamFieldMapping) -> String:
	return "%s::%s::%s" % [field.target_resource_path, field.field_name, str(field.dict_key)]


## 读字段值（含 Dict key 访问 + null 守卫）
## 返回 null 的可能：(1) field_name 不存在；(2) dict_key 在 Dict 内不存在；(3) field_name 字段不是 Dictionary 但 dict_key 非空
func _read_field_value(instance: Resource, field: ParamFieldMapping) -> Variant:
	if field.dict_key == null:
		return instance.get(field.field_name)
	var dict_val: Variant = instance.get(field.field_name)
	if not dict_val is Dictionary:
		push_warning("[ParamPanel] field '%s' 不是 Dictionary（dict_key=%s 无意义）" % [field.field_name, str(field.dict_key)])
		return null
	var dict: Dictionary = dict_val as Dictionary
	if not dict.has(field.dict_key):
		push_warning("[ParamPanel] dict '%s' 无 key=%s（available keys: %s）" % [field.field_name, str(field.dict_key), str(dict.keys())])
		return null
	return dict[field.dict_key]


# ─────────────────────────────────────────
# Preset backend（MVP-C.2 阶段 2）
#
# 设计原文：tile-advanture-design/参数Resource化/MVP-C_运行时调参面板.md §7 preset 系统设计
#
# 职责：提供 capture / save / load / apply / list / delete / rename / dirty-check 等纯逻辑接口；
# UI 集成（下拉栏 / 新建按钮 / confirm 对话框）属阶段 3 范围。
# ─────────────────────────────────────────

## preset 子目录根（每 scene_id 一级子目录）
const PRESET_ROOT: String = "res://assets/config/presets/"


## 把当前场景所有字段的 preload 实例当前值打包成 ParamPreset 实例（不写盘）
## 复用 _get_snapshot_fields 把 dict_combo_groups.linked_fields 按所有候选 dict_key 展开
##
## 注意：Color / float / int / String / bool 是值类型，直接赋值不会共享引用；
##       Dictionary / Array 是引用类型须 deep duplicate（与 _capture_snapshot 同套路），
##       否则 apply preset 后用户改字段会污染 preset 内的快照值
func capture_scene_as_preset(scene: ParamPanelScene, display_name: String) -> ParamPreset:
	var preset: ParamPreset = ParamPreset.new()
	preset.scene_id = scene.scene_id
	preset.display_name = display_name
	var snapshots: Array[FieldSnapshot] = []
	for field in _get_snapshot_fields(scene):
		var instance: Resource = load(field.target_resource_path)
		if instance == null:
			continue
		var snap: FieldSnapshot = FieldSnapshot.new()
		snap.target_resource_path = field.target_resource_path
		snap.field_name = field.field_name
		snap.dict_key = field.dict_key
		var val: Variant = _read_field_value(instance, field)
		# 值类型直接赋；引用类型 deep duplicate 避免污染
		if val is Dictionary:
			snap.value = (val as Dictionary).duplicate(true)
		elif val is Array:
			snap.value = (val as Array).duplicate(true)
		else:
			snap.value = val
		snapshots.append(snap)
	preset.field_snapshots = snapshots
	return preset


## 写 preset 到 `<PRESET_ROOT><scene_id>/<filename>.tres`
## filename 由调用方（阶段 3 UI）通过 InputText 取得 + sanitize_preset_filename 清洗
## 子目录不存在自动 make_dir_recursive
##
## 用 ResourceSaver.save（不走 C.1 自定义 dump）：
##   - preset 是新建文件无原 header 可保留
##   - field_snapshots 全部显式赋值不存在"==default 瘦身"问题
func save_preset_to_disk(preset: ParamPreset, filename: String) -> int:
	if preset == null:
		return ERR_INVALID_PARAMETER
	if preset.scene_id == "":
		push_error("[ParamPanel] preset.scene_id 为空，无法定位子目录")
		return ERR_INVALID_PARAMETER
	if filename == "":
		return ERR_INVALID_PARAMETER
	var dir_path: String = _preset_dir_for_scene(preset.scene_id)
	# 确保子目录存在（DirAccess.make_dir_recursive_absolute 接收绝对路径，含 res:// 前缀）
	var err: int = DirAccess.make_dir_recursive_absolute(dir_path)
	if err != OK and err != ERR_ALREADY_EXISTS:
		push_error("[ParamPanel] preset 子目录创建失败 %s (err=%d)" % [dir_path, err])
		return err
	var save_path: String = "%s%s.tres" % [dir_path, filename]
	err = ResourceSaver.save(preset, save_path)
	if err != OK:
		push_error("[ParamPanel] preset 写盘失败 %s (err=%d)" % [save_path, err])
	return err


## 读 preset .tres 为 ParamPreset 实例
## 校验：scene_id 必须与所在子目录名一致（设计文档 §7 要求），不一致 print warning 但仍返回
func load_preset_from_disk(preset_path: String) -> ParamPreset:
	var res: Resource = load(preset_path)
	if res == null:
		push_error("[ParamPanel] preset 加载失败 %s" % preset_path)
		return null
	if not res is ParamPreset:
		push_error("[ParamPanel] %s 不是 ParamPreset 类型" % preset_path)
		return null
	var preset: ParamPreset = res as ParamPreset
	# 校验子目录与 scene_id 一致：先取父目录名
	var parent_dir: String = preset_path.get_base_dir().get_file()
	if parent_dir != preset.scene_id:
		push_warning("[ParamPanel] preset %s 的 scene_id='%s' 与所在子目录名='%s' 不一致" % [preset_path, preset.scene_id, parent_dir])
	return preset


## 应用 preset 到 preload 实例：逐 FieldSnapshot 写值 + 收集 redraw 并集 + 触发 redraw
##
## 流程（沿用 §7 切换 preset 流程）：
## 1. 逐 FieldSnapshot 写入 preload 实例属性（标 dirty 让后续 F2 决定是否持久化到原 .tres）
## 2. 收集对应场景 default_redraw_targets ∪ 各字段 redraw_targets_override 并集去重
## 3. 触发 redraw（走 _pending_redraw + _flush_pending_redraw 帧末 defer）
## 4. 清相关 _control_state 让控件下帧重新从新值读
##
## 关于"不自动 F2"：apply 后字段在内存中已是 preset 值，_dirty_resources 标了；
## 用户后续手动 F2 写回到原 .tres 才持久化（符合 §7「不自动 Ctrl+S」语义）
func apply_preset(scene: ParamPanelScene, preset: ParamPreset) -> void:
	if scene == null or preset == null:
		return
	# 1+2. 逐字段写实例 + 收集 redraw 目标
	# 用临时 ParamFieldMapping 复用 _on_field_changed 链路（自动标 dirty + 加 pending redraw + 处理 override）
	for snap_any in preset.field_snapshots:
		var snap: FieldSnapshot = snap_any as FieldSnapshot
		if snap == null:
			continue
		var instance: Resource = load(snap.target_resource_path)
		if instance == null:
			continue
		# 寻找场景内对应的 ParamFieldMapping 以取得 redraw_targets_override / passive 配置
		var matched_field: ParamFieldMapping = _find_field_for_snapshot(scene, snap)
		if matched_field == null:
			# 字段不在当前场景目录（preset 老版本残留？）— 仍写实例 + 标 dirty，但用场景级 default redraw
			matched_field = ParamFieldMapping.new()
			matched_field.target_resource_path = snap.target_resource_path
			matched_field.field_name = snap.field_name
			matched_field.dict_key = snap.dict_key
			matched_field.passive = false
			push_warning("[ParamPanel] preset 内字段 %s::%s 在当前场景 '%s' 未找到映射，按 default_redraw_targets 处理" % [snap.field_name, str(snap.dict_key), scene.scene_id])
		_on_field_changed(scene, matched_field, snap.value)
		# 清此字段控件缓存（下帧重新从新值读）
		_control_state.erase(_make_state_key(matched_field))
	# 3. _on_field_changed 已把 redraw 加进 _pending_redraw，下帧 _flush_pending_redraw 自动触发；
	#    无需手动调；保留 _pending_redraw → _flush_pending_redraw 帧末合并去重路径
	# 4. apply 完不 _capture_snapshot：reset 基准仍是「面板打开前 / 上次 F2 后」状态，
	#    用户切 preset 不重置 reset 基准（符合"试调几个 preset 后能 reset 回原始"语义）


## 检查当前是否有未保存改动（_dirty_resources 非空）
## 阶段 3 UI 在切换 preset 前调用此检查 → 是则弹 confirm 对话框
func has_unsaved_dirty() -> bool:
	return not _dirty_resources.is_empty()


## 列出某 scene_id 子目录下所有 preset 路径（按文件名字母序）
## 子目录不存在返回空数组（首次启动正常）
func list_presets_for_scene(scene_id: String) -> Array[String]:
	var result: Array[String] = []
	var dir_path: String = _preset_dir_for_scene(scene_id)
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return result
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while fname != "":
		if fname.ends_with(".tres") and not dir.current_is_dir():
			result.append("%s%s" % [dir_path, fname])
		fname = dir.get_next()
	dir.list_dir_end()
	result.sort()
	return result


## 删除某 preset 文件（不撤销已 apply 的字段值）
func delete_preset(preset_path: String) -> int:
	if not FileAccess.file_exists(preset_path):
		return ERR_FILE_NOT_FOUND
	var err: int = DirAccess.remove_absolute(preset_path)
	if err != OK:
		push_error("[ParamPanel] preset 删除失败 %s (err=%d)" % [preset_path, err])
	return err


## 重命名 preset：仅改 display_name 字段，不动文件名（保 git history 友好，符合 §7 D6 拍板）
func rename_preset(preset_path: String, new_display_name: String) -> int:
	if new_display_name == "":
		return ERR_INVALID_PARAMETER
	var preset: ParamPreset = load_preset_from_disk(preset_path)
	if preset == null:
		return ERR_CANT_OPEN
	preset.display_name = new_display_name
	var err: int = ResourceSaver.save(preset, preset_path)
	if err != OK:
		push_error("[ParamPanel] preset 重命名（写回 display_name）失败 %s (err=%d)" % [preset_path, err])
	return err


## sanitize preset 文件名：替换 Windows / Linux 文件系统非法字符为下划线
## 调用方（阶段 3 UI）从 InputText 取用户输入 → sanitize → 喂给 save_preset_to_disk
func sanitize_preset_filename(name: String) -> String:
	if name == "":
		return ""
	var sanitized: String = name
	var illegal: Array[String] = ["/", "\\", ":", "*", "?", "\"", "<", ">", "|", "\n", "\r", "\t"]
	for ch in illegal:
		sanitized = sanitized.replace(ch, "_")
	# 去首尾空白 + 限长（防极端长名占 inode）
	sanitized = sanitized.strip_edges()
	if sanitized.length() > 64:
		sanitized = sanitized.substr(0, 64)
	return sanitized


## 计算某 scene_id 的 preset 子目录绝对路径（含尾部 /）
func _preset_dir_for_scene(scene_id: String) -> String:
	return "%s%s/" % [PRESET_ROOT, scene_id]


## 在场景内查找与 FieldSnapshot 匹配的 ParamFieldMapping（按 target_resource_path + field_name + dict_key 比对）
## 含 dict_combo_groups.linked_fields 展开后的运行时字段
func _find_field_for_snapshot(scene: ParamPanelScene, snap: FieldSnapshot) -> ParamFieldMapping:
	for field in _get_snapshot_fields(scene):
		if field.target_resource_path == snap.target_resource_path \
				and field.field_name == snap.field_name \
				and str(field.dict_key) == str(snap.dict_key):
			return field
	return null
