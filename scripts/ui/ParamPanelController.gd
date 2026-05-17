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
		for field_any in scene.fields:
			var field: ParamFieldMapping = field_any as ParamFieldMapping
			if field == null:
				continue
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


## Variant serializer：处理 schema 用到的类型（float / int / Color / Dictionary / String / bool）
## 保持与 Godot ResourceSaver 文本风格一致（整数浮点写为 "1" 而非 "1.0"）
func _serialize_value(val: Variant) -> String:
	if val is Color:
		var c: Color = val as Color
		return "Color(%s, %s, %s, %s)" % [_fmt_color_component(c.r), _fmt_color_component(c.g), _fmt_color_component(c.b), _fmt_color_component(c.a)]
	if val is Dictionary:
		var d: Dictionary = val as Dictionary
		var parts: PackedStringArray = ["{"]
		for k in d.keys():
			parts.append("%s: %s," % [_serialize_value(k), _serialize_value(d[k])])
		parts.append("}")
		return "\n".join(parts)
	if val is bool:
		return "true" if val else "false"
	if val is String or val is StringName:
		# P2 修复：完整转义 —— 先 \ 再 " 再 \n（顺序重要，避免重复处理）
		var s: String = str(val)
		s = s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")
		return '"%s"' % s
	if val is int:
		return str(val)
	if val is float:
		return _fmt_num(val)
	# fallback：未处理类型用 str() —— 后续如需 Vector2 / Array 等再扩
	return str(val)


## float 格式化：用 str() + 保留 ".0" 后缀
## Godot ResourceSaver 风格：Dict 内浮点 2.0 写 "2.0"，Color 内整数浮点 1.0 写 "1"（Color 特殊处理）
## 本函数用于非 Color 字段；Color 内 component 用 _fmt_color_component
func _fmt_num(n: float) -> String:
	var s: String = str(n)
	# str(1.0) 在 GDScript 4 输出 "1"，需要加 ".0" 保持浮点字面
	if not s.contains(".") and not s.contains("e"):
		s += ".0"
	return s


## Color component 格式化：整数浮点 1.0 → "1"（与原 .tres Color(1, 1, 1, 1) 风格一致）
func _fmt_color_component(n: float) -> String:
	return str(n)


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
		for field_any in scene.fields:
			var field: ParamFieldMapping = field_any as ParamFieldMapping
			if field == null:
				continue
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
