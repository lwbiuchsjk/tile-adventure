class_name BuildPanelUI
extends Node
## 建造面板 UI（M5）
##
## 设计原文：
##   tile-advanture-design/城建锚实装/M5_升级建造系统.md §UI 前置
##   tile-advanture-design/持久slot升级建造设计.md §六 每级质变
##
## 职责：
##   - 全局列出玩家所有持久 slot：位置 / 类型 + 等级 / 状态 / 升级按钮
##   - 石料数字顶部展示
##   - 升级按钮点击 → emit upgrade_requested(slot) 由 WorldMap 路由到 BuildSystem
##
## 与 ManageUI 的关系：
##   独立面板，职责正交；UI 互斥通过 `is_open` 字段对外暴露
##
## MVP 限制：
##   - 槽位恒 1（PersistentSlot.build_slot_count）
##   - 列表按 _schema.persistent_slots 原顺序展示，不排序


## 面板关闭
signal closed
## 升级请求（升级按钮点击时发射）；WorldMap 路由给 BuildSystem.start_upgrade
signal upgrade_requested(slot: PersistentSlot)


# ─────────────────────────────────────
# 状态
# ─────────────────────────────────────

## 面板根节点
var _panel: PanelContainer = null

## 对外暴露：是否正在显示
var is_open: bool = false

## 渲染数据（open / refresh 时由 WorldMap 注入）
var _slots: Array[PersistentSlot] = []
var _stone_amount: int = 0

## 节点缓存
var _title_label: Label = null
var _stone_label: Label = null
var _list_area: VBoxContainer = null
var _btn_close: Button = null


# ─────────────────────────────────────
# 初始化
# ─────────────────────────────────────

## 程序化创建面板并挂载到 CanvasLayer
func create_ui(ui_layer: CanvasLayer) -> void:
	_panel = PanelContainer.new()
	_panel.name = "BuildPanel"
	_panel.visible = false
	_panel.set_anchors_and_offsets_preset(
		Control.PRESET_CENTER, Control.PRESET_MODE_KEEP_SIZE
	)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_panel.custom_minimum_size = Vector2(460, 560)

	var outer_vbox: VBoxContainer = VBoxContainer.new()
	outer_vbox.add_theme_constant_override("separation", 8)

	# 标题
	_title_label = Label.new()
	_title_label.text = "建造"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 18)
	_title_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.30))
	outer_vbox.add_child(_title_label)

	# 石料数字（顶部，居中）
	_stone_label = Label.new()
	_stone_label.text = "石料 0"
	_stone_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stone_label.add_theme_font_size_override("font_size", 14)
	_stone_label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.80))
	outer_vbox.add_child(_stone_label)

	outer_vbox.add_child(_make_separator())

	# slot 列表（可滚动）
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list_area = VBoxContainer.new()
	_list_area.name = "SlotList"
	_list_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_area.add_theme_constant_override("separation", 4)
	scroll.add_child(_list_area)
	outer_vbox.add_child(scroll)

	outer_vbox.add_child(_make_separator())

	# 底部关闭按钮
	_btn_close = Button.new()
	_btn_close.text = "关闭 [B]"
	_btn_close.custom_minimum_size = Vector2(0, 32)
	_btn_close.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	_btn_close.add_theme_color_override("font_hover_color", Color(0.75, 0.75, 0.75))
	_btn_close.pressed.connect(_on_close_pressed)
	outer_vbox.add_child(_btn_close)

	_panel.add_child(outer_vbox)
	ui_layer.add_child(_panel)


# ─────────────────────────────────────
# 打开 / 关闭 / 刷新
# ─────────────────────────────────────

## 打开面板
## slots: 要显示的 slot 列表（已由调用方按归属过滤，通常只含 PLAYER 侧）
## stone: 当前势力石料数
func open(slots: Array[PersistentSlot], stone: int) -> void:
	_slots = slots
	_stone_amount = stone
	is_open = true
	refresh(_slots, _stone_amount)
	_panel.visible = true


## 关闭面板
func close() -> void:
	if _panel != null:
		_panel.visible = false
	is_open = false
	closed.emit()


## 刷新：重建列表项
func refresh(slots: Array[PersistentSlot], stone: int) -> void:
	if _panel == null:
		return
	_slots = slots
	_stone_amount = stone

	_stone_label.text = "石料 %d" % stone

	# 清空旧列表
	for child in _list_area.get_children():
		_list_area.remove_child(child)
		child.queue_free()

	if _slots.is_empty():
		var hint: Label = Label.new()
		hint.text = "（暂无己方持久 slot）"
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint.add_theme_color_override("font_color", Color(0.50, 0.50, 0.50))
		_list_area.add_child(hint)
		return

	for slot in _slots:
		_list_area.add_child(_make_slot_row(slot, stone))


# ─────────────────────────────────────
# 列表项构造
# ─────────────────────────────────────

## 单条 slot 行：左边文字描述，右边状态/按钮
func _make_slot_row(slot: PersistentSlot, stone: int) -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	# 左：位置 + 类型 + 等级
	var info: Label = Label.new()
	info.text = "%s L%d  (%d,%d)" % [
		slot.get_type_name(), slot.level, slot.position.x, slot.position.y
	]
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_color_override("font_color", Color(0.90, 0.90, 0.90))
	row.add_child(info)

	# 右：状态 / 按钮
	if slot.has_active_build():
		# 在建中：显示剩余回合
		var status: Label = Label.new()
		status.text = "建造中 %d 回合" % slot.active_build.remaining_turns
		status.add_theme_color_override("font_color", Color(0.95, 0.75, 0.35))
		row.add_child(status)
	elif BuildSystem.is_at_cap(slot):
		# 已满级：核心 L3 或村庄/城镇 L3
		var status: Label = Label.new()
		status.text = "已满级"
		status.add_theme_color_override("font_color", Color(0.60, 0.60, 0.60))
		row.add_child(status)
	else:
		# 可升级：显示按钮（石料不足时 disabled）
		var cost: int = BuildSystem.get_upgrade_cost(slot)
		var affordable: bool = stone >= cost
		var btn: Button = Button.new()
		btn.text = "升级 → L%d（%d 石料）" % [slot.level + 1, cost]
		btn.custom_minimum_size = Vector2(200, 28)
		btn.disabled = not affordable
		if affordable:
			btn.add_theme_color_override("font_color", Color(0.85, 0.95, 0.85))
			btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))
		else:
			btn.add_theme_color_override("font_color", Color(0.50, 0.40, 0.40))
		var bound_slot: PersistentSlot = slot
		btn.pressed.connect(func() -> void: upgrade_requested.emit(bound_slot))
		row.add_child(btn)

	return row


# ─────────────────────────────────────
# 工具
# ─────────────────────────────────────

## 构造面板分隔线（复用 ManageUI 同款风格）
func _make_separator() -> HSeparator:
	var sep: HSeparator = HSeparator.new()
	sep.add_theme_constant_override("separation", 4)
	return sep


## 底部关闭按钮点击回调：仅关闭面板，不做其他处理
func _on_close_pressed() -> void:
	close()
