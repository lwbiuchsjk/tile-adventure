class_name EventPanelUI
extends Node
## 事件面板 UI（探索体验·F MVP）
##
## 设计原文：
##   tile-advanture-design/探索体验实装/F_事件面板基础_MVP.md
##
## 职责：
##   - 维护事件 FIFO 队列；面板未打开时直接显示队首
##   - 程序化构建 Control 树：半透明遮罩 + 居中面板（标题 / 叙事文本 / 动态按钮）
##   - 玩家点 action → 调 result_callback → 出队 → 队列非空显示下一条；空则关闭面板
##
## 复用 / 隔离：
##   - 与 _show_notice 共存：_show_notice 用于非阻塞提示，事件面板用于阻塞性叙事呈现
##   - 与 ManageUI / BuildPanelUI 等 UI 同 ui_layer，挂载顺序保证渲染在它们之上
##   - 低于 VictoryUI（胜负覆盖事件面板），由 _init_subsystems 中挂载顺序保证
##
## 程序化创建，对齐项目既有 UI 子系统（ManageUI / BuildPanelUI / VictoryUI）
## 不使用 .tscn


## 对外暴露：面板是否正在显示
## 风格对齐 VictoryUI.is_open（字段而非方法），便于 WorldMap 输入锁定判断
var is_open: bool = false


## 入口 4 MVP（2026-05-09 BUG 修复）：面板关闭时 emit
## 触发：_hide_panel 内（队列空时调用）
## 监听方：WorldMap → _update_explore_action_button + queue_redraw
##   修复 BUG：踩即时 slot 后补给 0，事件面板关闭后扎营按钮未刷新
signal closed


# ─────────────────────────────────────
# 入口 2 MVP 2.2 视觉规格常量（2026-05-10）
# 跑测调参 / 美术接入时改这里;后续可被 .tres 资源替换
# ─────────────────────────────────────

## 整段 fade in 时长 —— 实际调用 UIFadeHelper.DEFAULT_FADE_IN_DURATION
## 不在此处再重声明常量(GDScript const 要求常量表达式,跨 class_name 引用不算)

## Panel 最小尺寸(让圆角 + 阴影 + 内边距撑开后不挤)
const PANEL_MIN_SIZE: Vector2 = Vector2(360, 220)

## StyleBoxFlat 视觉规格
const PANEL_BG_COLOR: Color = Color(0.13, 0.09, 0.05, 0.92)
const PANEL_BORDER_COLOR: Color = Color(0.78, 0.62, 0.32, 1.0)
const PANEL_BORDER_WIDTH: int = 2
const PANEL_CORNER_RADIUS: int = 8
const PANEL_CONTENT_MARGIN_H: int = 20
const PANEL_CONTENT_MARGIN_V: int = 18
const PANEL_SHADOW_COLOR: Color = Color(0, 0, 0, 0.5)
const PANEL_SHADOW_SIZE: int = 8
const PANEL_SHADOW_OFFSET: Vector2 = Vector2(0, 4)

## 字号 / 字色
const TITLE_FONT_SIZE: int = 18
const TITLE_FONT_COLOR: Color = Color(1.0, 0.92, 0.65, 1.0)
const NARRATIVE_FONT_SIZE: int = 14
const NARRATIVE_FONT_COLOR: Color = Color(0.92, 0.90, 0.85, 1.0)
const BUTTON_FONT_SIZE: int = 14

## 叙事 Label 宽度 = PANEL_MIN_SIZE.x - PANEL_CONTENT_MARGIN_H * 2 = 360 - 40 = 320
const NARRATIVE_LABEL_WIDTH: int = 320


# ─────────────────────────────────────
# 队列与当前事件
# ─────────────────────────────────────

## FIFO 队列；push_event 入队（面板已打开时）
var _event_queue: Array[Dictionary] = []

## 当前正在显示的事件（按钮回调时取 payload / result_callback 用）
var _current_event: Dictionary = {}


# ─────────────────────────────────────
# 节点引用（程序化构建）
# ─────────────────────────────────────

## 全屏根容器（吸收点击防止穿透到地图 / 下层 UI）
var _root: Control = null

## 中心面板
var _panel: PanelContainer = null

## 标题 Label
var _title_label: Label = null

## 叙事文本 Label（自动换行）
var _narrative_label: Label = null

## 按钮容器（动态按 actions 重建）
var _button_box: HBoxContainer = null

## 入口 2 MVP 2.2（2026-05-10）：fade in 状态
## _is_fading_in == true 时屏蔽所有"确认"输入(SPACE / 按钮点击 / SHIFT+SPACE 批量)
## 0.4s fade in 完成后置 false,玩家正常交互
var _is_fading_in: bool = false
var _fade_tween: Tween = null


# ─────────────────────────────────────
# 初始化
# ─────────────────────────────────────

## 程序化创建 UI 并挂载到 ui_layer
## 调用方：WorldMap._init_subsystems
## 挂载顺序需在 ManageUI / BuildPanelUI 之后、VictoryUI 之前——
## 同 CanvasLayer 内 z_index 相同时按子节点顺序渲染，后挂者在上
func create_ui(ui_layer: CanvasLayer) -> void:
	_root = Control.new()
	_root.name = "EventPanelOverlay"
	_root.visible = false
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# STOP 拦截输入；面板打开时阻止地图 / 其他 UI 穿透点击
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	ui_layer.add_child(_root)

	# 半透明黑色遮罩（按 F MVP §2 视觉规格 0.55 alpha）
	var dim: ColorRect = ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)

	# 居中容器（锚定屏幕中心）
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)

	# 中央面板：360×220，暖金描边 + 圆角 + 阴影（入口 2 MVP 2.2 视觉规格升级 2026-05-10）
	_panel = PanelContainer.new()
	_panel.name = "EventPanel"
	_panel.custom_minimum_size = PANEL_MIN_SIZE
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = PANEL_BG_COLOR
	# 暖金描边(2px)
	sb.border_width_left = PANEL_BORDER_WIDTH
	sb.border_width_right = PANEL_BORDER_WIDTH
	sb.border_width_top = PANEL_BORDER_WIDTH
	sb.border_width_bottom = PANEL_BORDER_WIDTH
	sb.border_color = PANEL_BORDER_COLOR
	# 圆角(8px)
	sb.corner_radius_top_left = PANEL_CORNER_RADIUS
	sb.corner_radius_top_right = PANEL_CORNER_RADIUS
	sb.corner_radius_bottom_left = PANEL_CORNER_RADIUS
	sb.corner_radius_bottom_right = PANEL_CORNER_RADIUS
	# 阴影(黑色 alpha 0.5 / 8px / 向下偏 4px)
	sb.shadow_color = PANEL_SHADOW_COLOR
	sb.shadow_size = PANEL_SHADOW_SIZE
	sb.shadow_offset = PANEL_SHADOW_OFFSET
	# 内边距(更"空气感")
	sb.content_margin_left = PANEL_CONTENT_MARGIN_H
	sb.content_margin_right = PANEL_CONTENT_MARGIN_H
	sb.content_margin_top = PANEL_CONTENT_MARGIN_V
	sb.content_margin_bottom = PANEL_CONTENT_MARGIN_V
	_panel.add_theme_stylebox_override("panel", sb)
	center.add_child(_panel)

	# 内层 VBox：标题 / 叙事 / 按钮三段
	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	_panel.add_child(vbox)

	# 标题（顶部，18pt 米色 — MVP 2.2 视觉规格 2026-05-10）
	_title_label = Label.new()
	_title_label.name = "TitleLabel"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	_title_label.add_theme_color_override("font_color", TITLE_FONT_COLOR)
	vbox.add_child(_title_label)

	# 叙事文本（中央，14pt，自动换行 — MVP 2.2 视觉规格 2026-05-10）
	# custom_minimum_size 配合 panel 的 content_margin 留出 320px 文字宽
	_narrative_label = Label.new()
	_narrative_label.name = "NarrativeLabel"
	_narrative_label.add_theme_font_size_override("font_size", NARRATIVE_FONT_SIZE)
	_narrative_label.add_theme_color_override("font_color", NARRATIVE_FONT_COLOR)
	_narrative_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_narrative_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_narrative_label.custom_minimum_size = Vector2(NARRATIVE_LABEL_WIDTH, 0)
	vbox.add_child(_narrative_label)

	# 按钮容器（底部居中；MVP 通常仅 1 项"确认"，预留 ≥1 按钮的 HBox）
	_button_box = HBoxContainer.new()
	_button_box.name = "ButtonBox"
	_button_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_button_box.add_theme_constant_override("separation", 12)
	vbox.add_child(_button_box)


# ─────────────────────────────────────
# 公开接口
# ─────────────────────────────────────

## 推送事件
## - 面板未打开：直接展示，不入队
## - 面板已打开：入队等待，玩家确认当前事件后自动接续
##
## 事件结构（详见 F MVP §2 / §4）：
##   {
##     "type": String,                    # "reward" / "recruit" / "respawn" / ...
##     "title": String,                   # 标题
##     "narrative": String,               # 叙事文本
##     "actions": Array[Dictionary],      # [{"label": "确认", "result": "confirm"}]
##     "payload": Dictionary,             # 类型特定数据
##     "result_callback": Callable,       # func(result: String, payload: Dictionary) -> void；可选
##   }
func push_event(event: Dictionary) -> void:
	if _root == null:
		push_warning("EventPanelUI.push_event: create_ui 未调用，事件丢弃")
		return
	if not is_open:
		_show_event(event)
	else:
		_event_queue.append(event)


# ─────────────────────────────────────
# 内部
# ─────────────────────────────────────

## 显示事件：写文字 + 重建按钮 + 显示 _root
## 调用前 _current_event 可能是上一条已确认事件，这里覆盖
func _show_event(event: Dictionary) -> void:
	_current_event = event
	_title_label.text = event.get("title", "") as String
	_narrative_label.text = event.get("narrative", "") as String

	_clear_action_buttons()
	var actions: Array = event.get("actions", []) as Array
	if actions.is_empty():
		# 兜底：至少给一个"确认"，避免事件无按钮卡死
		_add_action_button("确认", "confirm")
	else:
		for action in actions:
			var action_dict: Dictionary = action as Dictionary
			var label: String = action_dict.get("label", "确认") as String
			var result: String = action_dict.get("result", "confirm") as String
			_add_action_button(label, result)

	_root.visible = true
	is_open = true

	# 入口 2 MVP 2.2（2026-05-10）：整段 fade in 0.4s
	# panel + 标题 + 叙事 + 按钮整体淡入(modulate 沿层级穿透)
	# fade in 期间 _is_fading_in == true,屏蔽确认输入(防误跳)
	# 2026-05-11 抽 UIFadeHelper 共用工具:与 ManageUI / 后续 UI 表现一致
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_is_fading_in = true
	_fade_tween = UIFadeHelper.fade_in(
		_root,
		UIFadeHelper.DEFAULT_FADE_IN_DURATION,
		_on_fade_in_finished
	)


## fade in 完成回调:解除输入屏蔽
func _on_fade_in_finished() -> void:
	_is_fading_in = false


## 隐藏面板（仅在队列已空时调用）
func _hide_panel() -> void:
	if _root != null:
		_root.visible = false
	is_open = false
	_current_event = {}
	_clear_action_buttons()
	# MVP 2.2:清理 fade in 状态(避免下次开面板时残留)
	_is_fading_in = false
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = null
	# 入口 4 MVP（2026-05-09 BUG 修复）：emit closed 让 WorldMap 刷新探索态行动按钮
	# 修复 BUG：补给 0 时踩即时 slot 触发事件，关闭事件面板后扎营按钮未显示
	closed.emit()


## 清空按钮容器（事件切换 / 关闭前）
func _clear_action_buttons() -> void:
	if _button_box == null:
		return
	for child in _button_box.get_children():
		_button_box.remove_child(child)
		child.queue_free()


## 创建单个 action 按钮并接 pressed 信号
## 用 Callable.bind 把 result 绑入回调，避免 lambda 捕获散落
func _add_action_button(label: String, result: String) -> void:
	var btn: Button = Button.new()
	# 入口 4 MVP（2026-05-09）：第一个 action 绑 SPACE 快捷键
	# 多 action 事件（如"是 / 否"）SPACE 走第一项，玩家鼠标可选其他
	var is_first: bool = _button_box.get_child_count() == 0
	btn.text = (label + " [Space]") if is_first else label
	btn.custom_minimum_size = Vector2(120, 32)
	# 入口 2 MVP 2.2(2026-05-10):按钮字号 14pt(默认偏小,贴合 TILE_SIZE=72 新规格)
	btn.add_theme_font_size_override("font_size", BUTTON_FONT_SIZE)
	btn.pressed.connect(_on_action_clicked.bind(result))
	_button_box.add_child(btn)


## 入口 4 MVP：SPACE 路由触发首个 action（与点击首个按钮等价）
## 由 WorldMap._unhandled_input SPACE 分流时调用；面板关闭时为 noop
##
## 入口 2 MVP 2.2 (2026-05-10):fade in 期间(_is_fading_in == true)屏蔽,防误跳
func confirm_first_action() -> void:
	if _is_fading_in:
		return
	if not is_open or _button_box == null or _button_box.get_child_count() == 0:
		return
	var first: Button = _button_box.get_child(0) as Button
	if first != null:
		first.emit_signal("pressed")


## 入口 2 MVP 2.1 议题 4：批量确认所有单按钮事件
## 由 WorldMap._unhandled_input SHIFT+SPACE 分流时调用
##
## 行为：循环触发首按钮，遇到多按钮（actions.size() > 1）的决策型事件停下
##       —— 玩家在该事件上手动决策；若其后还有单按钮事件，需再按一次 SHIFT+SPACE
##
## codex review P1-4 注释（2026-05-10）：
##   判定多按钮事件用 `_button_box.get_child_count() > 1` 与设计文档"actions.size() > 1"等价：
##   - actions.is_empty() 时 _show_event 兜底加 1 个"确认"按钮 → child_count == 1
##   - actions.size() == 1 → child_count == 1
##   - actions.size() >= 2 → child_count >= 2
##   每轮循环重新读 child_count（confirm_first_action 内部出队 + 新事件 _show_event 重建按钮）
##
## safety_cap：防御性循环上限，正常事件队列 ≤ 10，64 留充足保险
##             避免 result_callback 链式 push_event 导致死循环
func confirm_all_single_action() -> void:
	# 入口 2 MVP 2.2(2026-05-10):fade in 期间屏蔽,防玩家在过渡内连按导致跳过
	if _is_fading_in:
		return
	if not is_open or _button_box == null:
		return
	var safety_cap: int = 64
	var n: int = 0
	while is_open and n < safety_cap:
		if _button_box.get_child_count() > 1:
			# 多按钮决策事件 → 停下，等玩家手动选择
			break
		if _button_box.get_child_count() == 0:
			# 异常态（不应到达），保险退出
			break
		confirm_first_action()
		n += 1


## 玩家点击 action 回调
## 1) 调用 result_callback（如有）
## 2) 队列非空 → 显示下一条；空 → 关闭面板
##
## 注意：result_callback 内部可能再次 push_event（链式触发），
## 这里保存本地 event 副本后再切换，避免引用错乱
##
## 入口 2 MVP 2.2 (2026-05-10):fade in 期间屏蔽,防玩家盲点按钮误跳过
func _on_action_clicked(action_result: String) -> void:
	if _is_fading_in:
		return
	var event: Dictionary = _current_event
	var payload: Dictionary = event.get("payload", {}) as Dictionary
	var cb_variant: Variant = event.get("result_callback")
	if cb_variant is Callable:
		var cb: Callable = cb_variant as Callable
		if cb.is_valid():
			cb.call(action_result, payload)

	# 注意：上面的 callback 可能又调了 push_event；
	# 此时新事件已被加入 _event_queue（因为 is_open 仍为 true）
	# 这里出队即可正确串到新事件之前
	if _event_queue.is_empty():
		_hide_panel()
	else:
		var next_event: Dictionary = _event_queue.pop_front() as Dictionary
		_show_event(next_event)


# ─────────────────────────────────────
# 场景退出清理
# ─────────────────────────────────────

## 场景重载时清空队列、当前事件，避免"上一局事件残留"
## Node 销毁时按钮节点随 _root 一并 queue_free，无需手动 disconnect
func _exit_tree() -> void:
	_event_queue.clear()
	_current_event = {}
