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
## 程序化创建，对齐项目既有 UI 子系统（BattleUI / ManageUI / BuildPanelUI / VictoryUI）
## 不使用 .tscn


## 对外暴露：面板是否正在显示
## 风格对齐 VictoryUI.is_open（字段而非方法），便于 WorldMap 输入锁定判断
var is_open: bool = false


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

	# 中央面板：300×200，深棕底（StyleBoxFlat 实装 §2 色号占位）
	_panel = PanelContainer.new()
	_panel.name = "EventPanel"
	_panel.custom_minimum_size = Vector2(300, 200)
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.15, 0.10, 0.05, 0.95)
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.border_color = Color(0.45, 0.30, 0.15, 1.0)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	_panel.add_theme_stylebox_override("panel", sb)
	center.add_child(_panel)

	# 内层 VBox：标题 / 叙事 / 按钮三段
	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	_panel.add_child(vbox)

	# 标题（顶部，16pt 粗体 — 项目无独立粗体字体，靠 font_size 区分）
	_title_label = Label.new()
	_title_label.name = "TitleLabel"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 16)
	_title_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.65, 1.0))
	vbox.add_child(_title_label)

	# 叙事文本（中央，12pt，自动换行）
	# custom_minimum_size 配合 panel 的 content_margin 留出 268px 文字宽
	_narrative_label = Label.new()
	_narrative_label.name = "NarrativeLabel"
	_narrative_label.add_theme_font_size_override("font_size", 12)
	_narrative_label.add_theme_color_override("font_color", Color(0.92, 0.90, 0.85, 1.0))
	_narrative_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_narrative_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_narrative_label.custom_minimum_size = Vector2(268, 0)
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


## 隐藏面板（仅在队列已空时调用）
func _hide_panel() -> void:
	if _root != null:
		_root.visible = false
	is_open = false
	_current_event = {}
	_clear_action_buttons()


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
	btn.text = label
	btn.custom_minimum_size = Vector2(120, 32)
	btn.pressed.connect(_on_action_clicked.bind(result))
	_button_box.add_child(btn)


## 玩家点击 action 回调
## 1) 调用 result_callback（如有）
## 2) 队列非空 → 显示下一条；空 → 关闭面板
##
## 注意：result_callback 内部可能再次 push_event（链式触发），
## 这里保存本地 event 副本后再切换，避免引用错乱
func _on_action_clicked(action_result: String) -> void:
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
