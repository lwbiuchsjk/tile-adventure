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
	_panel.custom_minimum_size = Vector2(420, 480)

	# 外层 VBox：标题 + 滚动区域 + 关闭按钮
	var outer_vbox: VBoxContainer = VBoxContainer.new()
	outer_vbox.add_theme_constant_override("separation", 8)

	# 标题
	var title: Label = Label.new()
	title.text = "装配管理"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(1.0, 0.92, 0.30))
	outer_vbox.add_child(title)

	var sep_top: HSeparator = HSeparator.new()
	sep_top.add_theme_constant_override("separation", 4)
	outer_vbox.add_child(sep_top)

	# 滚动容器
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = "ManageScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 360)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.name = "ManageVBox"
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 6)

	# 角色状态区域
	var char_title: Label = Label.new()
	char_title.name = "CharTitleLabel"
	char_title.text = "部队状态"
	char_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	char_title.add_theme_color_override("font_color", Color(0.75, 0.85, 0.95))
	vbox.add_child(char_title)

	var char_label: Label = Label.new()
	char_label.name = "CharStatusLabel"
	char_label.text = ""
	vbox.add_child(char_label)

	var sep_char: HSeparator = HSeparator.new()
	sep_char.add_theme_constant_override("separation", 6)
	vbox.add_child(sep_char)

	# 背包区域
	var inv_title: Label = Label.new()
	inv_title.name = "InvTitleLabel"
	inv_title.text = "背包"
	inv_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inv_title.add_theme_color_override("font_color", Color(0.75, 0.85, 0.95))
	vbox.add_child(inv_title)

	var inv_label: Label = Label.new()
	inv_label.name = "InventoryLabel"
	inv_label.text = ""
	vbox.add_child(inv_label)

	var sep_inv: HSeparator = HSeparator.new()
	sep_inv.add_theme_constant_override("separation", 6)
	vbox.add_child(sep_inv)

	# 操作区域标题
	var op_title: Label = Label.new()
	op_title.name = "OpTitleLabel"
	op_title.text = "可用操作"
	op_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	op_title.add_theme_color_override("font_color", Color(0.75, 0.85, 0.95))
	vbox.add_child(op_title)

	# 操作按钮区域
	var op_vbox: VBoxContainer = VBoxContainer.new()
	op_vbox.name = "OperationArea"
	op_vbox.add_theme_constant_override("separation", 4)
	vbox.add_child(op_vbox)

	scroll.add_child(vbox)
	outer_vbox.add_child(scroll)

	# 底部分隔线 + 关闭按钮
	var sep_bottom: HSeparator = HSeparator.new()
	sep_bottom.add_theme_constant_override("separation", 4)
	outer_vbox.add_child(sep_bottom)

	var btn_close: Button = Button.new()
	btn_close.text = "关闭 [M]"
	btn_close.custom_minimum_size = Vector2(0, 32)
	btn_close.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	btn_close.add_theme_color_override("font_hover_color", Color(0.75, 0.75, 0.75))
	btn_close.pressed.connect(_on_close_pressed)
	outer_vbox.add_child(btn_close)

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
	is_open = true
	# 更新面板标题
	var title_label: Label = _panel.find_child("ManageTitleLabel", true, false) as Label
	if title_label == null:
		# 兼容：查找第一个标题
		for child in _panel.get_children():
			if child is VBoxContainer:
				for sub in child.get_children():
					if sub is Label and sub.text.begins_with("装配") or sub.text.begins_with("扎营"):
						title_label = sub as Label
						break
	if title_label != null:
		title_label.text = "扎营 - 养成" if camp_mode else "装配管理"
	# 更新关闭按钮文字
	var btn_close: Button = null
	for child in _panel.get_children():
		if child is VBoxContainer:
			for sub in child.get_children():
				if sub is Button and (sub.text.contains("关闭") or sub.text.contains("确认")):
					btn_close = sub as Button
					break
	if btn_close != null:
		btn_close.text = "确认结束" if camp_mode else "关闭 [M]"
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

	# 更新角色状态
	var char_label: Label = _panel.find_child("CharStatusLabel", true, false) as Label
	if char_label != null:
		var lines: Array[String] = []
		for i in range(_characters.size()):
			var ch: CharacterData = _characters[i]
			if ch.has_troop():
				var t: TroopData = ch.troop
				var exp_info: String = ""
				var threshold: int = t.get_upgrade_threshold()
				if threshold > 0:
					exp_info = "  经验 %d/%d" % [t.exp, threshold]
				lines.append("  角色%d: %s  兵力 %d/%d%s" % [
					i + 1, t.get_display_text(), t.current_hp, t.max_hp, exp_info
				])
			else:
				lines.append("  角色%d: 空" % (i + 1))
		char_label.text = "\n".join(lines)

	# 更新背包标题（含容量）
	var inv_title: Label = _panel.find_child("InvTitleLabel", true, false) as Label
	if inv_title != null:
		inv_title.text = "背包 (%d/%d)" % [_inventory.get_used_slots(), _inventory.max_capacity]

	# 更新背包内容
	var inv_label: Label = _panel.find_child("InventoryLabel", true, false) as Label
	if inv_label != null:
		if _inventory.get_used_slots() == 0:
			inv_label.text = "  背包为空"
		else:
			var item_lines: Array[String] = []
			for item in _inventory.get_items():
				if item.stack_count > 1:
					item_lines.append("  · %s ×%d" % [item.get_display_text(), item.stack_count])
				else:
					item_lines.append("  · %s" % item.get_display_text())
			inv_label.text = "\n".join(item_lines)

	# 重建操作区域
	_rebuild_operations()


## 重建操作按钮区域
func _rebuild_operations() -> void:
	var old_op_area: VBoxContainer = _panel.find_child("OperationArea", true, false) as VBoxContainer
	if old_op_area == null:
		return

	var parent_vbox: VBoxContainer = old_op_area.get_parent() as VBoxContainer
	var op_index: int = old_op_area.get_index()
	parent_vbox.remove_child(old_op_area)
	old_op_area.queue_free()

	var op_area: VBoxContainer = VBoxContainer.new()
	op_area.name = "OperationArea"
	parent_vbox.add_child(op_area)
	parent_vbox.move_child(op_area, op_index)

	var button_count: int = 0

	for i in range(_characters.size()):
		var ch: CharacterData = _characters[i]
		var ch_name: String = "角色%d" % (i + 1)
		var ch_troop_text: String = ch.troop.get_display_text() if ch.has_troop() else "空"

		if not ch.has_troop():
			# 空槽位 + 背包有部队道具 → 装配按钮
			var troop_items: Array[ItemData] = _inventory.get_items_by_type(ItemData.ItemType.TROOP)
			for item in troop_items:
				var card: VBoxContainer = _create_op_card(
					ch_name, "", "空槽位",
					"装配 %s" % item.get_display_text(),
					Color(0.45, 0.80, 0.50)
				)
				var btn: Button = card.get_child(1) as Button
				# 捕获当前迭代变量
				var bound_ch: CharacterData = ch
				var bound_item: ItemData = item
				btn.pressed.connect(func() -> void: equip_requested.emit(bound_ch, bound_item))
				op_area.add_child(card)
				button_count += 1
		else:
			var t: TroopData = ch.troop

			# 替换部队（任何模式下都可用）
			var troop_items: Array[ItemData] = _inventory.get_items_by_type(ItemData.ItemType.TROOP)
			for item in troop_items:
				var card: VBoxContainer = _create_op_card(
					ch_name, ch_troop_text, "兵力 %d/%d" % [t.current_hp, t.max_hp],
					"替换为 %s（当前回收）" % item.get_display_text(),
					Color(0.95, 0.75, 0.45)
				)
				var btn: Button = card.get_child(1) as Button
				var bound_ch: CharacterData = ch
				var bound_item: ItemData = item
				btn.pressed.connect(func() -> void: equip_requested.emit(bound_ch, bound_item))
				op_area.add_child(card)
				button_count += 1

			# 经验道具（仅扎营养成模式）
			if _camp_mode:
				var exp_threshold: int = t.get_upgrade_threshold()
				var exp_status: String = "经验 %d/%d" % [t.exp, exp_threshold] if exp_threshold > 0 else "已满级"
				var exp_items: Array[ItemData] = _inventory.get_items_by_type(ItemData.ItemType.EXP)
				for item in exp_items:
					if item.can_use_on(t):
						var card: VBoxContainer = _create_op_card(
							ch_name, ch_troop_text, exp_status,
							"使用 %s" % item.get_display_text(),
							Color(0.65, 0.80, 0.95)
						)
						var btn: Button = card.get_child(1) as Button
						var bound_ch: CharacterData = ch
						var bound_item: ItemData = item
						btn.pressed.connect(func() -> void: use_item_requested.emit(bound_ch, bound_item))
						op_area.add_child(card)
						button_count += 1

			# 兵力恢复道具（仅扎营养成模式）
			if _camp_mode:
				var hp_items: Array[ItemData] = _inventory.get_items_by_type(ItemData.ItemType.HP_RESTORE)
				for item in hp_items:
					if item.can_use_on(t):
						var card: VBoxContainer = _create_op_card(
							ch_name, ch_troop_text, "兵力 %d/%d" % [t.current_hp, t.max_hp],
							"使用 %s" % item.get_display_text(),
							Color(0.50, 0.85, 0.50)
						)
						var btn: Button = card.get_child(1) as Button
						var bound_ch: CharacterData = ch
						var bound_item: ItemData = item
						btn.pressed.connect(func() -> void: use_item_requested.emit(bound_ch, bound_item))
						op_area.add_child(card)
						button_count += 1

	# 无可用操作时显示提示
	if button_count == 0:
		var hint: Label = Label.new()
		hint.text = "（当前无可用操作）"
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint.add_theme_color_override("font_color", Color(0.50, 0.50, 0.50))
		op_area.add_child(hint)

# ─────────────────────────────────────
# 操作卡片
# ─────────────────────────────────────

## 创建操作卡片（上方角色/兵种/状态信息 + 下方操作按钮）
## char_name: 角色名称（如 "角色1"）
## troop_name: 兵种显示名（如 "剑兵(R)"），空槽位传空字符串
## status: 数值状态（如 "兵力 15/20"）
## action: 操作描述文字
## color: 按钮颜色
func _create_op_card(char_name: String, troop_name: String,
		status: String, action: String, color: Color) -> VBoxContainer:
	var card: VBoxContainer = VBoxContainer.new()
	card.add_theme_constant_override("separation", 1)

	# 角色 + 兵种 + 状态信息行
	var info_hbox: HBoxContainer = HBoxContainer.new()
	info_hbox.add_theme_constant_override("separation", 4)

	# 角色名称（暖白醒目）
	var name_label: Label = Label.new()
	name_label.text = char_name
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.add_theme_color_override("font_color", Color(0.85, 0.82, 0.75))
	info_hbox.add_child(name_label)

	# 兵种名（金色凸显）
	if troop_name != "":
		var troop_label: Label = Label.new()
		troop_label.text = troop_name
		troop_label.add_theme_font_size_override("font_size", 13)
		troop_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.45))
		info_hbox.add_child(troop_label)

	# 数值状态（灰色辅助）
	if status != "":
		var status_label: Label = Label.new()
		status_label.text = status
		status_label.add_theme_font_size_override("font_size", 13)
		status_label.add_theme_color_override("font_color", Color(0.55, 0.58, 0.55))
		info_hbox.add_child(status_label)

	card.add_child(info_hbox)

	# 操作按钮
	var btn: Button = Button.new()
	btn.text = "  %s" % action
	btn.custom_minimum_size = Vector2(0, 28)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.add_theme_color_override("font_color", color)
	btn.add_theme_color_override("font_hover_color", color.lightened(0.3))
	card.add_child(btn)

	return card

# ─────────────────────────────────────
# 内部回调
# ─────────────────────────────────────

## 关闭按钮回调
func _on_close_pressed() -> void:
	close()
