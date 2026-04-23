class_name VictoryUI
extends Node
## 胜负遮罩 UI（M8）
##
## 设计原文：
##   tile-advanture-design/城建锚实装/M8_胜负与最小验证.md §交付物
##
## 职责：
##   - 全屏半透明遮罩 + 胜负文字 + 重开按钮
##   - 重开按钮点击 → emit restart_pressed（由 WorldMap 路由到 reload_current_scene）
##
## 约定：
##   本 UI 只承担 M8 核心城镇翻转的胜负展示；
##   原有 `_show_victory_text` / `_show_defeat_text`（轮次通关 / 部队全灭 / 放弃）保留不动，
##   避免扩大 M8 影响面；两套提示并存，显示顺序由 WorldMap 控制（MVP 不会同时触发）。
##
## 程序化创建，对齐项目既有 UI 子系统（BuildPanelUI / ManageUI / BattleUI）
## 不使用 .tscn（M8 设计文档示意用的 .tscn 与项目实际约定不一致，此处按项目约定落地）


## 重开按钮点击信号（WorldMap 路由 get_tree().reload_current_scene）
signal restart_pressed


## 对外暴露：遮罩是否正在显示
var is_open: bool = false


# ─────────────────────────────────────
# 节点引用
# ─────────────────────────────────────

## 全屏根容器（Control，点击拦截）
var _root: Control = null

## 中心面板（显示文字 + 按钮）
var _panel: PanelContainer = null

## 胜负主文本（"胜利！" / "失败..."）
var _title_label: Label = null

## 副文本（回合数 / 说明）
var _subtitle_label: Label = null

## 重开按钮
var _btn_restart: Button = null


# ─────────────────────────────────────
# 初始化
# ─────────────────────────────────────

## 程序化创建 UI 并挂载到 CanvasLayer（由 WorldMap._init_subsystems 调用）
## ui_layer 应与 HUD 同层（layer=10），但挂在 HUD 之上以遮罩输入
func create_ui(ui_layer: CanvasLayer) -> void:
	_root = Control.new()
	_root.name = "VictoryOverlay"
	_root.visible = false
	# 全屏铺满；mouse_filter = STOP 吸收点击，阻止穿透到地图
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	ui_layer.add_child(_root)

	# 半透明黑色遮罩（ColorRect 充当背景）
	var dim: ColorRect = ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.0, 0.0, 0.0, 0.60)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)

	# 中央容器（锚定屏幕中心）
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)

	# 结果面板（层级：PanelContainer → MarginContainer → VBoxContainer）
	# 面板样式沿用默认 Theme 的 Panel
	_panel = PanelContainer.new()
	_panel.name = "ResultPanel"
	center.add_child(_panel)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	_panel.add_child(margin)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	vbox.custom_minimum_size = Vector2(320, 0)
	margin.add_child(vbox)

	# 主标题
	_title_label = Label.new()
	_title_label.name = "TitleLabel"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 32)
	vbox.add_child(_title_label)

	# 副标题（回合数 / 说明文字）
	_subtitle_label = Label.new()
	_subtitle_label.name = "SubtitleLabel"
	_subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle_label.add_theme_font_size_override("font_size", 14)
	_subtitle_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.90, 1.0))
	vbox.add_child(_subtitle_label)

	# 重开按钮
	_btn_restart = Button.new()
	_btn_restart.name = "RestartButton"
	_btn_restart.text = "重开"
	_btn_restart.custom_minimum_size = Vector2(160, 40)
	_btn_restart.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_btn_restart.pressed.connect(_on_restart_pressed)
	vbox.add_child(_btn_restart)


# ─────────────────────────────────────
# 显示 / 隐藏
# ─────────────────────────────────────

## 显示胜利遮罩
## subtitle 通常传回合数 / 评分文本，MVP 可为空字符串
func show_victory(subtitle: String = "") -> void:
	if _root == null:
		push_warning("VictoryUI.show_victory: create_ui 未调用，遮罩不显示")
		return
	_title_label.text = "胜利！"
	_title_label.add_theme_color_override("font_color", Color(1.0, 0.90, 0.25, 1.0))
	_subtitle_label.text = subtitle
	_root.visible = true
	is_open = true
	_btn_restart.grab_focus()


## 显示失败遮罩
func show_defeat(subtitle: String = "") -> void:
	if _root == null:
		push_warning("VictoryUI.show_defeat: create_ui 未调用，遮罩不显示")
		return
	_title_label.text = "失败..."
	_title_label.add_theme_color_override("font_color", Color(1.0, 0.40, 0.40, 1.0))
	_subtitle_label.text = subtitle
	_root.visible = true
	is_open = true
	_btn_restart.grab_focus()


## 隐藏遮罩（重开前调用，或调试用）
func hide_overlay() -> void:
	if _root == null:
		return
	_root.visible = false
	is_open = false


# ─────────────────────────────────────
# 信号回调
# ─────────────────────────────────────

## 重开按钮点击：向 WorldMap 发信号
func _on_restart_pressed() -> void:
	restart_pressed.emit()
