class_name ParamPresetManager
extends Object
## MVP-D D.1.a Preset 子系统管理器：从 ParamPanelController 抽出的 UI、cache 与 backend 逻辑。
##
## 管理器不入场景树；通过 controller 引用复用现有字段读写、dirty 标记、控件缓存与 redraw 链路。


## preset 子目录根（每 scene_id 一级子目录）
const PRESET_ROOT: String = "res://assets/config/presets/"

## 所属 ParamPanelController；保持动态类型以访问脚本内下划线成员
var _controller

## preset 缓存：scene_id(String) → Array[ParamPreset]（按文件名字母序）
## 避免每帧扫盘 + load；缓存失效时机：新建 / 删除 / 重命名后调 _refresh_preset_cache
var _preset_cache: Dictionary = {}

## 当前选中的 preset 路径：scene_id(String) → preset_path(String)
## "" = 无 preset 选中（即 Combo 显示「默认」表示当前是手动调过的状态）
var _active_preset_path: Dictionary = {}

## Combo 当前选中 index 缓存：scene_id(String) → Array[int]（ImGui Combo binding）
## index 0 固定 = 「默认」；1..N = preset 列表
var _preset_combo_state: Dictionary = {}

## 新建 / 重命名 popup 输入缓冲：scene_id(String) → Array[String]（ImGui InputText binding）
var _preset_name_buffer: Dictionary = {}

## 切换 preset 待确认动作：scene_id(String) → String（待切换的 preset_path；空 = 待切到「默认」）
## has_unsaved_dirty 时弹 confirm popup，用户确认后取此值执行
var _preset_pending_switch: Dictionary = {}


## 保存 controller 引用，供 preset apply / capture 复用 Controller 的字段链路
func _init(controller: Node) -> void:
	_controller = controller


# ─────────────────────────────────────────
# Public UI
# ─────────────────────────────────────────

## 渲染场景顶部 preset 下拉栏，对外入口保持无下划线命名
func render_bar(scene: ParamPanelScene) -> void:
	_render_preset_bar(scene)


## 渲染场景 preset 相关 popup，对外入口保持无下划线命名
func render_popups(scene: ParamPanelScene) -> void:
	_render_preset_popups(scene)


# ─────────────────────────────────────────
# Preset UI（MVP-C.2 阶段 3）：场景顶部下拉栏 + 4 个模态对话框
#
# UI 布局：[Preset: 默认 ▼] [新建] [删除] [重命名]
# 4 个 popup：preset_new_<scene_id> / preset_delete_<scene_id> / preset_rename_<scene_id> / preset_switch_<scene_id>
# popup 命名按 scene_id 隔离，避免跨场景串扰
# ─────────────────────────────────────────


## 渲染场景顶部 preset 下拉栏：Combo + 新建 / 删除 / 重命名 三按钮
## Combo 选择切换：检查 has_unsaved_dirty → 是则 OpenPopup confirm；否则直接 apply_preset
## 「默认」= index 0，表示不应用任何 preset（保持当前状态；不会触发 apply）
func _render_preset_bar(scene: ParamPanelScene) -> void:
	var sid: String = scene.scene_id
	# 1. 准备 preset 列表 + Combo 选项
	var presets: Array = _get_or_load_preset_cache(sid)
	var combo_items: PackedStringArray = ["默认"]
	for p_any in presets:
		var p: ParamPreset = p_any as ParamPreset
		combo_items.append(p.display_name if p.display_name != "" else "(无名)")
	# 2. 维护 Combo state（[selected_index]）
	if not _preset_combo_state.has(sid):
		_preset_combo_state[sid] = [0]
	var state_arr: Array = _preset_combo_state[sid]
	# 同步外部切换（apply / cancel）：根据 _active_preset_path 重新定位 index
	var active_path: String = _active_preset_path.get(sid, "") as String
	var resolved_index: int = 0
	if active_path != "":
		for i in presets.size():
			var p: ParamPreset = presets[i] as ParamPreset
			# 比对路径需用与 list 返回一致的形式
			if _preset_path_for(p, sid) == active_path:
				resolved_index = i + 1
				break
	state_arr[0] = resolved_index
	# 3. Combo + 三按钮
	ImGui.SetNextItemWidth(180.0)
	if ImGui.Combo("##preset_combo_%s" % sid, state_arr, combo_items):
		_handle_preset_combo_change(scene, presets, state_arr[0] as int)
	ImGui.SameLine()
	if ImGui.Button("新建##preset_new_btn_%s" % sid):
		# 初始化输入缓冲为默认名建议（如「v3」自动递增 = 当前 preset 数 + 1）
		_preset_name_buffer[sid] = ["v%d" % (presets.size() + 1)]
		ImGui.OpenPopup("preset_new_%s" % sid)
	ImGui.SameLine()
	# 删除 / 重命名仅在 active preset 非空时启用
	var has_active: bool = active_path != ""
	if not has_active:
		ImGui.BeginDisabled()
	if ImGui.Button("删除##preset_del_btn_%s" % sid):
		ImGui.OpenPopup("preset_delete_%s" % sid)
	ImGui.SameLine()
	if ImGui.Button("重命名##preset_ren_btn_%s" % sid):
		# 初始化为当前 preset display_name
		var current_name: String = _get_active_preset_display_name(sid, presets)
		_preset_name_buffer[sid] = [current_name]
		ImGui.OpenPopup("preset_rename_%s" % sid)
	if not has_active:
		ImGui.EndDisabled()


## Combo 切换分发：
##   - 选 index=0「默认」= 不 apply（_active_preset_path 清空）
##   - 选 index≥1 = 检查 has_unsaved_dirty → 否则直接 apply / 是则弹 confirm
func _handle_preset_combo_change(scene: ParamPanelScene, presets: Array, new_index: int) -> void:
	var sid: String = scene.scene_id
	if new_index == 0:
		# 切回「默认」：清 active path，不 apply 任何 preset（保持当前状态）
		_active_preset_path[sid] = ""
		return
	if new_index < 1 or new_index > presets.size():
		push_warning("[ParamPanel] preset Combo index 越界 %d / %d" % [new_index, presets.size()])
		return
	var preset: ParamPreset = presets[new_index - 1] as ParamPreset
	var preset_path: String = _preset_path_for(preset, sid)
	# 未保存检查
	if has_unsaved_dirty():
		_preset_pending_switch[sid] = preset_path
		ImGui.OpenPopup("preset_switch_%s" % sid)
		return
	# 无未保存，直接 apply
	apply_preset(scene, preset)
	_active_preset_path[sid] = preset_path


## 渲染 4 个 popup（OpenPopup 在按钮回调触发；BeginPopupModal 在此处定义内容）
##
## ImGui popup 模型：OpenPopup 在 ID 栈某层触发，BeginPopupModal 同层级匹配
## 同一帧内必须调 BeginPopupModal（即使未 open）以参与 popup 栈，否则 popup 不显示
func _render_preset_popups(scene: ParamPanelScene) -> void:
	var sid: String = scene.scene_id
	_render_preset_new_popup(scene, sid)
	_render_preset_delete_popup(scene, sid)
	_render_preset_rename_popup(scene, sid)
	_render_preset_switch_confirm_popup(scene, sid)


## 新建 popup：InputText 输入 preset 名 → 确定 → capture + sanitize + save + refresh cache + 选中新 preset
func _render_preset_new_popup(scene: ParamPanelScene, sid: String) -> void:
	if not ImGui.BeginPopupModal("preset_new_%s" % sid, [], ImGui.WindowFlags_AlwaysAutoResize):
		return
	ImGui.Text("新建 preset（保存当前场景所有字段值为快照）")
	if not _preset_name_buffer.has(sid):
		_preset_name_buffer[sid] = [""]
	var arr: Array = _preset_name_buffer[sid]
	ImGui.SetNextItemWidth(220.0)
	# Enter 触发提交：ImGui.InputTextFlags_EnterReturnsTrue
	var submitted: bool = ImGui.InputText("##preset_new_input_%s" % sid, arr, 64,
		ImGui.InputTextFlags_EnterReturnsTrue)
	var confirm_clicked: bool = ImGui.Button("确定##preset_new_ok_%s" % sid)
	ImGui.SameLine()
	if ImGui.Button("取消##preset_new_cancel_%s" % sid):
		ImGui.CloseCurrentPopup()
		ImGui.EndPopup()
		return
	if submitted or confirm_clicked:
		var raw: String = str(arr[0])
		var fname: String = sanitize_preset_filename(raw)
		if fname == "":
			ImGui.TextColored(Color(1.0, 0.3, 0.3, 1.0), "[err] 名字为空或全是非法字符")
		else:
			var preset: ParamPreset = capture_scene_as_preset(scene, raw)
			var err: int = save_preset_to_disk(preset, fname)
			if err == OK:
				_refresh_preset_cache(sid)
				# 选中新 preset：从新 cache 中找匹配路径
				var new_path: String = "%s%s.tres" % [_preset_dir_for_scene(sid), fname]
				_active_preset_path[sid] = new_path
				ImGui.CloseCurrentPopup()
			else:
				ImGui.TextColored(Color(1.0, 0.3, 0.3, 1.0), "[err] 保存失败 err=%d" % err)
	ImGui.EndPopup()


## 删除 popup：confirm「确定删除 <名字>？」→ 确定 → delete_preset + refresh + 清 active
func _render_preset_delete_popup(scene: ParamPanelScene, sid: String) -> void:
	if not ImGui.BeginPopupModal("preset_delete_%s" % sid, [], ImGui.WindowFlags_AlwaysAutoResize):
		return
	var presets: Array = _get_or_load_preset_cache(sid)
	var active_name: String = _get_active_preset_display_name(sid, presets)
	ImGui.Text("确定删除 preset「%s」？此操作不可撤销（文件被删）" % active_name)
	if ImGui.Button("删除##preset_del_ok_%s" % sid):
		var active_path: String = _active_preset_path.get(sid, "") as String
		if active_path != "":
			var err: int = delete_preset(active_path)
			if err == OK:
				_active_preset_path[sid] = ""
				_refresh_preset_cache(sid)
		ImGui.CloseCurrentPopup()
	ImGui.SameLine()
	if ImGui.Button("取消##preset_del_cancel_%s" % sid):
		ImGui.CloseCurrentPopup()
	ImGui.EndPopup()


## 重命名 popup：InputText 输入新 display_name → 确定 → rename_preset（只改 display_name，文件名不动）
func _render_preset_rename_popup(scene: ParamPanelScene, sid: String) -> void:
	if not ImGui.BeginPopupModal("preset_rename_%s" % sid, [], ImGui.WindowFlags_AlwaysAutoResize):
		return
	ImGui.Text("重命名 preset display_name（文件名不动，保 git history 友好）")
	if not _preset_name_buffer.has(sid):
		_preset_name_buffer[sid] = [""]
	var arr: Array = _preset_name_buffer[sid]
	ImGui.SetNextItemWidth(220.0)
	var submitted: bool = ImGui.InputText("##preset_ren_input_%s" % sid, arr, 64,
		ImGui.InputTextFlags_EnterReturnsTrue)
	var confirm_clicked: bool = ImGui.Button("确定##preset_ren_ok_%s" % sid)
	ImGui.SameLine()
	if ImGui.Button("取消##preset_ren_cancel_%s" % sid):
		ImGui.CloseCurrentPopup()
		ImGui.EndPopup()
		return
	if submitted or confirm_clicked:
		var new_name: String = str(arr[0]).strip_edges()
		if new_name == "":
			ImGui.TextColored(Color(1.0, 0.3, 0.3, 1.0), "[err] 新名字不能为空")
		else:
			var active_path: String = _active_preset_path.get(sid, "") as String
			if active_path != "":
				var err: int = rename_preset(active_path, new_name)
				if err == OK:
					_refresh_preset_cache(sid)
					ImGui.CloseCurrentPopup()
				else:
					ImGui.TextColored(Color(1.0, 0.3, 0.3, 1.0), "[err] 重命名失败 err=%d" % err)
	ImGui.EndPopup()


## 切换 confirm popup：has_unsaved_dirty 时弹「未保存改动会丢失，确认切换？」
func _render_preset_switch_confirm_popup(scene: ParamPanelScene, sid: String) -> void:
	if not ImGui.BeginPopupModal("preset_switch_%s" % sid, [], ImGui.WindowFlags_AlwaysAutoResize):
		return
	ImGui.Text("未保存的改动会丢失，确认切换 preset？")
	ImGui.Text("（若想保留改动，先 F2 写回原 .tres，或新建 preset 保存当前状态）")
	if ImGui.Button("确认切换##preset_switch_ok_%s" % sid):
		var target_path: String = _preset_pending_switch.get(sid, "") as String
		if target_path != "":
			var preset: ParamPreset = load_preset_from_disk(target_path)
			if preset != null:
				apply_preset(scene, preset)
				_active_preset_path[sid] = target_path
		_preset_pending_switch.erase(sid)
		ImGui.CloseCurrentPopup()
	ImGui.SameLine()
	if ImGui.Button("取消##preset_switch_cancel_%s" % sid):
		_preset_pending_switch.erase(sid)
		# 取消则 Combo 状态需回退到 _active_preset_path 对应 index（下次 _render_preset_bar 自动同步）
		ImGui.CloseCurrentPopup()
	ImGui.EndPopup()


# ─────────────────────────────────────────
# Cache
# ─────────────────────────────────────────

## 取或加载 preset cache（首次访问时扫盘 + load）
func _get_or_load_preset_cache(scene_id: String) -> Array:
	if _preset_cache.has(scene_id):
		return _preset_cache[scene_id] as Array
	_refresh_preset_cache(scene_id)
	return _preset_cache[scene_id] as Array


## 强制刷新某 scene_id 的 preset cache（新建 / 删除 / 重命名后调）
func _refresh_preset_cache(scene_id: String) -> void:
	var paths: Array[String] = list_presets_for_scene(scene_id)
	var presets: Array = []
	for p in paths:
		var preset: ParamPreset = load_preset_from_disk(p)
		if preset != null:
			presets.append(preset)
	_preset_cache[scene_id] = presets


## 给 preset 反推磁盘路径（用于 active_path 比对）
## P1.1 修复（Codex 审 MVP-C.2 2026-05-18）：直读 preset._source_path（load_preset_from_disk 回填的运行时字段），
## 避免原 "cache[i] → paths[i]" 索引反推在 cache 内有坏 preset（load 返回 null 被跳过）时错位
func _preset_path_for(preset: ParamPreset, scene_id: String) -> String:
	if preset == null:
		return ""
	return preset._source_path


## 取当前 active preset 的 display_name（用于 popup 文本显示）
func _get_active_preset_display_name(scene_id: String, presets: Array) -> String:
	var active_path: String = _active_preset_path.get(scene_id, "") as String
	if active_path == "":
		return ""
	for p_any in presets:
		var p: ParamPreset = p_any as ParamPreset
		if _preset_path_for(p, scene_id) == active_path:
			return p.display_name
	return ""


# ─────────────────────────────────────────
# Preset backend（MVP-C.2 阶段 2）
#
# 设计原文：tile-advanture-design/参数Resource化/MVP-C_运行时调参面板.md §7 preset 系统设计
#
# 职责：提供 capture / save / load / apply / list / delete / rename / dirty-check 等纯逻辑接口；
# UI 集成（下拉栏 / 新建按钮 / confirm 对话框）属阶段 3 范围。
# ─────────────────────────────────────────

## 把当前场景所有字段的 preload 实例当前值打包成 ParamPreset 实例（不写盘）
## 复用 Controller._get_snapshot_fields 把 dict_combo_groups.linked_fields 按所有候选 dict_key 展开
##
## 注意：Color / float / int / String / bool 是值类型，直接赋值不会共享引用；
##       Dictionary / Array 是引用类型须 deep duplicate（与 _capture_snapshot 同套路），
##       否则 apply preset 后用户改字段会污染 preset 内的快照值
func capture_scene_as_preset(scene: ParamPanelScene, display_name: String) -> ParamPreset:
	var preset: ParamPreset = ParamPreset.new()
	preset.scene_id = scene.scene_id
	preset.display_name = display_name
	var snapshots: Array[FieldSnapshot] = []
	for field in _controller._get_snapshot_fields(scene):
		var instance: Resource = load(field.target_resource_path)
		if instance == null:
			continue
		var snap: FieldSnapshot = FieldSnapshot.new()
		snap.target_resource_path = field.target_resource_path
		snap.field_name = field.field_name
		snap.dict_key = field.dict_key
		var val: Variant = _controller._read_field_value(instance, field)
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
## P1.1 修复（Codex 审 MVP-C.2 2026-05-18）：load 后回填 _source_path，cache 内坏 preset 跳过时 _preset_path_for 不再索引错位
func load_preset_from_disk(preset_path: String) -> ParamPreset:
	var res: Resource = load(preset_path)
	if res == null:
		push_error("[ParamPanel] preset 加载失败 %s" % preset_path)
		return null
	if not res is ParamPreset:
		push_error("[ParamPanel] %s 不是 ParamPreset 类型" % preset_path)
		return null
	var preset: ParamPreset = res as ParamPreset
	preset._source_path = preset_path
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
		# P0 修复（Codex 审 MVP-C.2 2026-05-18）：Dict/Array 值类型 deep duplicate，避免 preset 内快照与 instance 共享引用
		# 同 _capture_snapshot 套路；Color/float/int/String/bool 是值类型直接传
		var applied_value: Variant = snap.value
		if applied_value is Dictionary:
			applied_value = (applied_value as Dictionary).duplicate(true)
		elif applied_value is Array:
			applied_value = (applied_value as Array).duplicate(true)
		_controller._on_field_changed(scene, matched_field, applied_value)
		# 清此字段控件缓存（下帧重新从新值读）
		_controller._control_state.erase(_controller._make_state_key(matched_field))
	# 3. _on_field_changed 已把 redraw 加进 _pending_redraw，下帧 _flush_pending_redraw 自动触发；
	#    无需手动调；保留 _pending_redraw → _flush_pending_redraw 帧末合并去重路径
	# 4. apply 完不 _capture_snapshot：reset 基准仍是「面板打开前 / 上次 F2 后」状态，
	#    用户切 preset 不重置 reset 基准（符合"试调几个 preset 后能 reset 回原始"语义）


## 检查当前是否有未保存改动（Controller._dirty_resources 非空）
## 阶段 3 UI 在切换 preset 前调用此检查 → 是则弹 confirm 对话框
func has_unsaved_dirty() -> bool:
	return not _controller._dirty_resources.is_empty()


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
	for field in _controller._get_snapshot_fields(scene):
		if field.target_resource_path == snap.target_resource_path \
				and field.field_name == snap.field_name \
				and str(field.dict_key) == str(snap.dict_key):
			return field
	return null
