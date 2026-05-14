class_name ManageUI
extends PanelContainer
## 装配管理面板子系统
##
## 负责管理面板的刷新、操作卡片生成；装配/使用操作通过信号通知 WorldMap 处理实际逻辑。
##
## 预制件化（MVP-α.5 / 2026-05-14）：节点结构在 res://scenes/ui/ManageUI.tscn；
## 根类型 Node → PanelContainer（自身即面板，由 anchor PRESET_CENTER 居中）；
## CharArea / InventoryArea 内的角色按钮 / 道具按钮仍按数据动态生成。

## 面板关闭
signal closed
## 请求装配部队（角色, 道具）
signal equip_requested(character: CharacterData, item: ItemData)
## 请求使用道具（角色, 道具）
signal use_item_requested(character: CharacterData, item: ItemData)

# ─────────────────────────────────────
# 状态
# ─────────────────────────────────────

## 是否正在显示面板
var is_open: bool = false

## 缓存的角色和背包引用（open 时传入）
var _characters: Array[CharacterData] = []
var _inventory: Inventory = null

## 是否为扎营养成模式（true=显示全部操作，false=仅显示部队替换）
var _camp_mode: bool = false

## 当前选中的角色索引（-1 = 未选中）
var _selected_char_index: int = -1

## 角色区和背包区节点缓存（@onready 从预制件结构拿）
@onready var _title_label: Label = $VBox/TitleLabel
@onready var _char_area: VBoxContainer = $VBox/CharArea
@onready var _inv_area: VBoxContainer = $VBox/ScrollContainer/InventoryArea
@onready var _btn_close: Button = $VBox/CloseButton

## 入口 2 MVP 2.2（2026-05-11）：fade in 状态(与 EventPanelUI 共用 UIFadeHelper)
## 屏蔽 close 路径:防玩家在过渡内按 SPACE / 点关闭按钮立即跳过仪式感
## 角色装配 / 道具使用按钮在 fade 期间不强制屏蔽(0.4s 内偶尔盲点容忍,玩家停留时间长)
var _is_fading_in: bool = false
var _fade_tween: Tween = null

# ─────────────────────────────────────
# 初始化
# ─────────────────────────────────────

## 预制件挂到 ui_layer 后自动调用；接关闭按钮信号 + 默认隐藏
func _ready() -> void:
	visible = false
	is_open = false
	_btn_close.pressed.connect(_on_close_pressed)

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
	# 入口 4 MVP（2026-05-09）：扎营态绑 SPACE 快捷键，按钮文字带 [Space] 标识
	_btn_close.text = "确认结束 [Space]" if camp_mode else "关闭 [M]"
	refresh()
	visible = true

	# 入口 2 MVP 2.2（2026-05-11）：整段 fade in 0.4s,与 EventPanelUI 共用 UIFadeHelper
	# self.modulate 沿层级穿透,标题 / 角色区 / 背包区 / 按钮整体淡入
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_is_fading_in = true
	_fade_tween = UIFadeHelper.fade_in(
		self,
		UIFadeHelper.DEFAULT_FADE_IN_DURATION,
		_on_fade_in_finished
	)


## fade in 完成回调:解除输入屏蔽
func _on_fade_in_finished() -> void:
	_is_fading_in = false


## 关闭管理面板
##
## 入口 2 MVP 2.2 (2026-05-11):fade in 期间(_is_fading_in)屏蔽 close 路径
## 防玩家在 0.4s 过渡内按 SPACE / 点关闭按钮立即跳过仪式感
func close() -> void:
	if _is_fading_in:
		return
	visible = false
	is_open = false
	# 清理 fade in 状态
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = null
	_is_fading_in = false
	closed.emit()


## 入口 4 MVP：是否处于扎营养成模式（用于 SPACE 路由判定）
func is_camp_mode() -> bool:
	return _camp_mode


## 刷新面板内容（装配/使用后调用）
func refresh() -> void:
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

# ─────────────────────────────────────
# 内部回调
# ─────────────────────────────────────

## 关闭按钮回调
func _on_close_pressed() -> void:
	close()
