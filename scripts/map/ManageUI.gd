class_name ManageUI
extends Node
## 装配管理面板子系统
## 负责管理面板的创建、刷新、操作卡片生成。
## 装配/使用操作通过信号通知 WorldMap 处理实际逻辑。

## 面板关闭
signal closed
## 请求装配部队（角色, 道具）
signal equip_requested(character: CharacterData, item: ItemData)
## 请求使用道具（角色, 道具）
signal use_item_requested(character: CharacterData, item: ItemData)

# ─────────────────────────────────────
# 状态
# ─────────────────────────────────────

## 管理面板引用
var _panel: PanelContainer = null

## 是否正在显示面板
var is_open: bool = false

## 缓存的角色和背包引用（open 时传入）
var _characters: Array[CharacterData] = []
var _inventory: Inventory = null

## 是否为扎营养成模式（true=显示全部操作，false=仅显示部队替换）
var _camp_mode: bool = false

## 当前选中的角色索引（-1 = 未选中）
var _selected_char_index: int = -1

## 角色区和背包区节点缓存（create_ui 时赋值，避免 find_child 查找）
var _title_label: Label = null
var _char_area: VBoxContainer = null
var _inv_area: VBoxContainer = null
var _btn_close: Button = null

# ─────────────────────────────────────
# 初始化
# ─────────────────────────────────────

## 程序化创建装配管理面板，挂载到指定 CanvasLayer
func create_ui(ui_layer: CanvasLayer) -> void:
	_panel = PanelContainer.new()
	_panel.name = "ManagePanel"
	_panel.visible = false
	_panel.set_anchors_and_offsets_preset(
		Control.PRESET_CENTER, Control.PRESET_MODE_KEEP_SIZE
	)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_panel.custom_minimum_size = Vector2(420, 560)

	# 外层 VBox
	var outer_vbox: VBoxContainer = VBoxContainer.new()
	outer_vbox.add_theme_constant_override("separation", 8)

	# 标题
	_title_label = Label.new()
	_title_label.text = "装配管理"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 18)
	_title_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.30))
	outer_vbox.add_child(_title_label)

	outer_vbox.add_child(_make_separator())

	# 上区：角色选择（固定，不滚动）
	_char_area = VBoxContainer.new()
	_char_area.name = "CharArea"
	_char_area.add_theme_constant_override("separation", 4)
	outer_vbox.add_child(_char_area)

	outer_vbox.add_child(_make_separator())

	# 下区：背包道具（可垂直滚动，占满剩余高度）
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL

	_inv_area = VBoxContainer.new()
	_inv_area.name = "InventoryArea"
	_inv_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inv_area.add_theme_constant_override("separation", 4)
	scroll.add_child(_inv_area)
	outer_vbox.add_child(scroll)

	outer_vbox.add_child(_make_separator())

	# 底部确认/关闭按钮
	_btn_close = Button.new()
	_btn_close.text = "关闭 [M]"
	_btn_close.custom_minimum_size = Vector2(0, 32)
	_btn_close.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	_btn_close.add_theme_color_override("font_hover_color", Color(0.75, 0.75, 0.75))
	_btn_close.pressed.connect(_on_close_pressed)
	outer_vbox.add_child(_btn_close)

	_panel.add_child(outer_vbox)
	ui_layer.add_child(_panel)

# ─────────────────────────────────────
# 打开 / 关闭
# ─────────────────────────────────────

## 打开管理面板
## camp_mode: true=扎营养成模式（全部操作），false=非扎营（仅替换）
func open(characters: Array[CharacterData], inventory: Inventory, camp_mode: bool = false) -> void:
	_characters = characters
	_inventory = inventory
	_camp_mode = camp_mode
	_selected_char_index = -1
	is_open = true
	_title_label.text = "扎营 - 养成" if camp_mode else "装配管理"
	_btn_close.text = "确认结束" if camp_mode else "关闭 [M]"
	refresh()
	_panel.visible = true


## 关闭管理面板
func close() -> void:
	if _panel != null:
		_panel.visible = false
	is_open = false
	closed.emit()


## 刷新面板内容（装配/使用后调用）
func refresh() -> void:
	if _panel == null:
		return
	_rebuild_char_area()
	_rebuild_inventory_interactive()

# ─────────────────────────────────────
# 上区：角色选择
# ─────────────────────────────────────

## 重建角色选择按钮区
func _rebuild_char_area() -> void:
	for child in _char_area.get_children():
		_char_area.remove_child(child)
		child.queue_free()

	for i in range(_characters.size()):
		var ch: CharacterData = _characters[i]
		var label: String
		if ch.has_troop():
			var t: TroopData = ch.troop
			var threshold: int = t.get_upgrade_threshold()
			var exp_info: String = "经验 %d/%d" % [t.exp, threshold] if threshold > 0 else "已满级"
			label = "角色%d  %s  兵力 %d/%d  %s" % [
				i + 1, t.get_display_text(), t.current_hp, t.max_hp, exp_info
			]
		else:
			label = "角色%d  空槽位" % (i + 1)

		var btn: Button = Button.new()
		btn.text = label
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(0, 30)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if i == _selected_char_index:
			btn.add_theme_color_override("font_color", Color(1.0, 0.92, 0.30))
		else:
			btn.add_theme_color_override("font_color", Color(0.85, 0.82, 0.75))

		var bound_i: int = i
		btn.pressed.connect(func() -> void: _on_char_selected(bound_i))
		_char_area.add_child(btn)

## 角色按钮点击回调（toggle 选中）
func _on_char_selected(index: int) -> void:
	if _selected_char_index == index:
		_selected_char_index = -1
	else:
		_selected_char_index = index
	refresh()

# ─────────────────────────────────────
# 下区：背包道具交互列表
# ─────────────────────────────────────

## 重建背包道具交互列表
func _rebuild_inventory_interactive() -> void:
	for child in _inv_area.get_children():
		_inv_area.remove_child(child)
		child.queue_free()

	if _inventory.get_used_slots() == 0:
		var hint: Label = Label.new()
		hint.text = "（背包为空）"
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint.add_theme_color_override("font_color", Color(0.50, 0.50, 0.50))
		_inv_area.add_child(hint)
		return

	# 获取选中角色数据（用于可用性判断）
	var sel_ch: CharacterData = null
	var sel_troop: TroopData = null
	if _selected_char_index >= 0 and _selected_char_index < _characters.size():
		sel_ch = _characters[_selected_char_index]
		if sel_ch.has_troop():
			sel_troop = sel_ch.troop

	# 部队道具
	var troop_items: Array[ItemData] = _inventory.get_items_by_type(ItemData.ItemType.TROOP)
	if troop_items.size() > 0:
		_inv_area.add_child(_make_group_label("── 部队 ──"))
		for item in troop_items:
			# 有选中角色时可用（空槽位=装配，有部队=替换）
			var enabled: bool = sel_ch != null
			var bound_ch: CharacterData = sel_ch
			var bound_item: ItemData = item
			var btn: Button = _make_item_button(item, enabled)
			if enabled:
				btn.pressed.connect(func() -> void: equip_requested.emit(bound_ch, bound_item))
			_inv_area.add_child(btn)

	# 经验道具（仅扎营模式）
	if _camp_mode:
		var exp_items: Array[ItemData] = _inventory.get_items_by_type(ItemData.ItemType.EXP)
		if exp_items.size() > 0:
			_inv_area.add_child(_make_group_label("── 经验道具 ──"))
			for item in exp_items:
				var enabled: bool = sel_troop != null and item.can_use_on(sel_troop)
				var bound_ch: CharacterData = sel_ch
				var bound_item: ItemData = item
				var btn: Button = _make_item_button(item, enabled)
				if enabled:
					btn.pressed.connect(func() -> void: use_item_requested.emit(bound_ch, bound_item))
				_inv_area.add_child(btn)

	# 兵力恢复道具（仅扎营模式）
	if _camp_mode:
		var hp_items: Array[ItemData] = _inventory.get_items_by_type(ItemData.ItemType.HP_RESTORE)
		if hp_items.size() > 0:
			_inv_area.add_child(_make_group_label("── 兵力恢复 ──"))
			for item in hp_items:
				var enabled: bool = sel_troop != null and item.can_use_on(sel_troop)
				var bound_ch: CharacterData = sel_ch
				var bound_item: ItemData = item
				var btn: Button = _make_item_button(item, enabled)
				if enabled:
					btn.pressed.connect(func() -> void: use_item_requested.emit(bound_ch, bound_item))
				_inv_area.add_child(btn)

# ─────────────────────────────────────
# 工具方法
# ─────────────────────────────────────

## 创建分组标题 Label
func _make_group_label(text: String) -> Label:
	var lbl: Label = Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_color_override("font_color", Color(0.75, 0.85, 0.95))
	lbl.add_theme_font_size_override("font_size", 13)
	return lbl

## 创建道具按钮
func _make_item_button(item: ItemData, enabled: bool) -> Button:
	var display: String = item.get_display_text()
	if item.stack_count > 1:
		display = "%s ×%d" % [display, item.stack_count]

	var btn: Button = Button.new()
	btn.text = "  %s" % display
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.custom_minimum_size = Vector2(0, 28)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.disabled = not enabled
	if enabled:
		btn.add_theme_color_override("font_color", Color(0.90, 0.90, 0.90))
		btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))
	else:
		btn.add_theme_color_override("font_color", Color(0.40, 0.40, 0.40))
	return btn

## 创建分隔线
func _make_separator() -> HSeparator:
	var sep: HSeparator = HSeparator.new()
	sep.add_theme_constant_override("separation", 4)
	return sep

# ─────────────────────────────────────
# 内部回调
# ─────────────────────────────────────

## 关闭按钮回调
func _on_close_pressed() -> void:
	close()
