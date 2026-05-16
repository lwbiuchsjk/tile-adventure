extends CanvasLayer
##
## 入口 2 MVP 2.1 议题 5：全屏过渡组件（autoload 单例）
##
## 复用场景：
##   - 队长 coma → respawn 合并过渡（双句，含 midpoint reload）
##   - 游戏开始过渡（单句，从黑屏起手揭幕）
##
## 为什么是 autoload：coma → respawn 流程要 reload_current_scene，
## 若组件挂在 WorldMap 下会被一起销毁；autoload 让组件跨场景持久存在，
## 黑屏 phase 期间正好覆盖 reload 的全部加载耗时。
##
## 预制件化（MVP-α.5 / 2026-05-14）：节点结构在 res://scenes/ui/OverlayTransitionUI.tscn；
## project.godot autoload 路径从 .gd 改 .tscn（脚本附在 CanvasLayer 根上，行为等价）；
## 关键时序保留：_ready 内 _blackout.modulate.a = 1.0 仍能在 main_scene 第一帧前生效，
## 掩盖应用启动到 main_scene `_ready` 之间的加载耗时。
##
## 节点结构（与 .tscn 一一对应）：
##   self (CanvasLayer, layer=1000)
##   └─ Root (Control, anchor=full_rect)
##      ├─ BlackoutRect (ColorRect, color=Color(0,0,0,1))
##      └─ Center (CenterContainer)
##         └─ VBox
##            ├─ IconRow (HBox, [IconLabel "🔥"] [CountLabel "× N"])
##            └─ Lines (VBox, 动态创建 LineN 标签)
##
## 详见 [[../../tile-advanture-design/事件流程与队长过渡_MVP]]
##

# ─────────────────────────────────────
# 信号
# ─────────────────────────────────────

## 内部使用：WorldMap _ready 末尾调 notify_world_ready 时 emit
## play() 的 phase B 等这个信号通过（让 reload 后新场景就绪后才进 phase C）
signal world_ready

## 整段过渡完成（phase D fade out 末尾）；外部可监听
signal finished

# 内部信号：当前 step（line fade-in / line hold）完成（自然完成或 SPACE 跳过）
signal step_advanced

# ─────────────────────────────────────
# 配置常量（默认值，跑测可调）
# ─────────────────────────────────────

const FADE_IN_DURATION: float = 0.4
const FADE_OUT_DURATION: float = 0.4
const LINE_FADE_IN_DURATION: float = 0.4
const LINE_HOLD_DURATION: float = 1.5
const ICON_FADE_IN_DURATION: float = 0.2

## phase B 超时兜底（codex review P0-2 修复 2026-05-10）：
## 防止 _pending_respawn_intro 未被置 true 等极端边界让 await world_ready 永久挂起
## 5s 是设计经验值：reload + _ready 应在 1-2s 内完成；超时即 fallback 进 phase C
const PHASE_B_TIMEOUT_SEC: float = 5.0

const ICON_FALLBACK: String = "🔥"
const ICON_FONT_SIZE: int = 48
const COUNT_FONT_SIZE: int = 32
const LINE_FONT_SIZE: int = 24
const LINE_COLOR: Color = Color(1, 1, 1, 1)

# Phase 枚举
const PHASE_IDLE: int = 0
const PHASE_A: int = 1   # fade in
const PHASE_B: int = 2   # 全黑期 await midpoint
const PHASE_C: int = 3   # 文字逐句
const PHASE_D: int = 4   # fade out

# ─────────────────────────────────────
# 节点引用 / 状态
# ─────────────────────────────────────

@onready var _root: Control = $Root
@onready var _blackout: ColorRect = $Root/BlackoutRect
@onready var _icon_row: HBoxContainer = $Root/Center/VBox/IconRow
@onready var _icon_label: Label = $Root/Center/VBox/IconRow/IconLabel
@onready var _count_label: Label = $Root/Center/VBox/IconRow/CountLabel
@onready var _lines_box: VBoxContainer = $Root/Center/VBox/Lines

var _phase: int = PHASE_IDLE
var _line_labels: Array[Label] = []
var _current_line_index: int = 0
var _current_step_tween: Tween = null
var _step_emitted: bool = false  # 防 double emit（tween 自然完成 vs SPACE 跳过）
var _initial_play_done: bool = false  # 首次启动游戏时的过渡是否已触发


# ─────────────────────────────────────
# 生命周期
# ─────────────────────────────────────

## autoload 加载后调用，main_scene 第一帧前置黑屏掩盖加载耗时
##
## 关键时序：_blackout.modulate.a = 1.0 必须在 main_scene._ready() 第一次绘制前生效。
## autoload 加载顺序早于 main_scene，CanvasLayer layer=1000 渲染在最顶，
## 配合 process_mode = ALWAYS 不受 pause 影响。
func _ready() -> void:
	# autoload 不应被场景 pause / process_mode 影响
	process_mode = Node.PROCESS_MODE_ALWAYS
	# 应用启动即黑屏起手；等首次 WorldMap.notify_world_ready 后才推进
	# 设计意图：掩盖应用启动到首场景 _ready 之间的加载耗时
	_root.visible = true
	_blackout.modulate.a = 1.0
	# codex review P3 备忘（2026-05-10）：_lines_box 容器 alpha=1，但 _ready 时 _line_labels 还为空，
	# 实际显示由后续 _setup_content 创建的各 Label 自身 modulate.a = 0.0 控制。容器维持 1.0 让 phase C
	# 直接 fade in 各 Label 即可，无需再处理容器 alpha
	_lines_box.modulate.a = 1.0
	_icon_row.modulate.a = 0.0
	_phase = PHASE_IDLE


# ─────────────────────────────────────
# 公开 API
# ─────────────────────────────────────

## 是否已经触发过游戏开始过渡
## WorldMap _ready 末尾用此判断：未触发则调 play_with_blackout_start；已触发则调 notify_world_ready
func is_initial_play_done() -> bool:
	return _initial_play_done


## 完整四相位 play：透明 → fade in → midpoint await → 文字逐句 → fade out
##
## lines：要逐句显示的文字（数组顺序）
## icon_data：{"icon": String, "count": int}；空字段走 fallback
## on_midpoint：phase B 内调用的 Callable；可返回 Signal 让本方法 await
##              用于 coma → respawn：内部做 RunState.advance_cycle + reload_current_scene + 返回 world_ready
##
## 不并发：已在过渡中再次调用会被拒绝（push_warning + return）
func play(lines: PackedStringArray, icon_data: Dictionary, on_midpoint: Callable) -> void:
	if _phase != PHASE_IDLE:
		push_warning("OverlayTransitionUI.play: 已有过渡进行中，忽略本次调用")
		return
	_setup_content(lines, icon_data)
	_root.visible = true

	# Phase A：fade in
	_phase = PHASE_A
	_blackout.modulate.a = 0.0
	_icon_row.modulate.a = 0.0
	for lbl in _line_labels:
		lbl.modulate.a = 0.0
	var fade_in_tween: Tween = create_tween()
	fade_in_tween.tween_property(_blackout, "modulate:a", 1.0, FADE_IN_DURATION)
	await fade_in_tween.finished

	# Phase B：全黑期，await midpoint
	_phase = PHASE_B
	if on_midpoint.is_valid():
		var ret: Variant = on_midpoint.call()
		if ret is Signal:
			await _await_signal_with_timeout(ret, PHASE_B_TIMEOUT_SEC)

	# Phase C + D
	await _run_lines_and_fade_out()


## 从全黑起手 → 文字逐句 → fade out（phase A、B 跳过）
##
## 用于游戏开始过渡：应用启动即黑屏（_ready 已置 alpha=1），等首场景 _ready 后揭幕
## 首次调用置 _initial_play_done = true，避免重复触发
func play_with_blackout_start(lines: PackedStringArray, icon_data: Dictionary) -> void:
	if _phase != PHASE_IDLE:
		push_warning("OverlayTransitionUI.play_with_blackout_start: 已有过渡进行中，忽略")
		return
	_initial_play_done = true
	_setup_content(lines, icon_data)
	_root.visible = true
	_blackout.modulate.a = 1.0
	_icon_row.modulate.a = 0.0
	for lbl in _line_labels:
		lbl.modulate.a = 0.0

	# 直接进 Phase C + D
	await _run_lines_and_fade_out()


## WorldMap reload 后调用（旧 WorldMap _exit_tree 后、新 WorldMap _init_player 完成时）
##
## 行为：
##   1. 若指定 replace_line_index ∈ [0, _line_labels.size())：替换该 Label 的 text
##      —— 用于 coma → respawn 流程：第二句"队长 Y 开启了旅程"的 Y 名字只有 reload 后
##         draw_new_leader 抽到才能确定，需在此动态写入
##   2. emit world_ready —— 让 play() 的 phase B `await ret` 通过
##
## 注意：游戏开始首次调用应走 play_with_blackout_start 而非本方法（由 WorldMap 自行分流）
func notify_world_ready(replace_line_index: int = -1, replace_line_text: String = "") -> void:
	if replace_line_index >= 0 and replace_line_index < _line_labels.size():
		_line_labels[replace_line_index].text = replace_line_text
	world_ready.emit()


# ─────────────────────────────────────
# 内部流程
# ─────────────────────────────────────

## Phase C 主循环 + Phase D fade out
func _run_lines_and_fade_out() -> void:
	# Phase C：先 icon row 快速淡入，然后逐句
	_phase = PHASE_C
	if _icon_row.modulate.a < 1.0:
		var icon_tween: Tween = create_tween()
		icon_tween.tween_property(_icon_row, "modulate:a", 1.0, ICON_FADE_IN_DURATION)
		# 不 await，让 icon 与第一句并行淡入

	for i in range(_line_labels.size()):
		_current_line_index = i
		await _await_step(func() -> Tween:
			var t: Tween = create_tween()
			t.tween_property(_line_labels[i], "modulate:a", 1.0, LINE_FADE_IN_DURATION)
			return t
		)
		# 跳过推进时确保 alpha 拉满（防 SPACE 在中段跳过）
		_line_labels[i].modulate.a = 1.0
		await _await_step(func() -> Tween:
			var t: Tween = create_tween()
			t.tween_interval(LINE_HOLD_DURATION)
			return t
		)

	_current_line_index = _line_labels.size()  # 全部句子已显示

	# Phase D：fade out（黑屏 + icon + lines 一起）
	_phase = PHASE_D
	var out_tween: Tween = create_tween().set_parallel(true)
	out_tween.tween_property(_blackout, "modulate:a", 0.0, FADE_OUT_DURATION)
	out_tween.tween_property(_icon_row, "modulate:a", 0.0, FADE_OUT_DURATION)
	for lbl in _line_labels:
		out_tween.tween_property(lbl, "modulate:a", 0.0, FADE_OUT_DURATION)
	await out_tween.finished

	_root.visible = false
	_phase = PHASE_IDLE
	finished.emit()


## 等待一个 step（fade in / hold）完成
##
## tween_factory 是构造 tween 的 Callable —— 因为 tween 在 await 之前要先 connect step_advanced
## 调用方传 lambda 返回新建 tween，本方法接管 connect / await
##
## 跳过路径：_on_space_pressed_in_phase_c 调用 _emit_step_done_once，本方法的 await 立即返回
## 自然完成路径：tween.finished 触发 _emit_step_done_once，同样 emit step_advanced
##
## _step_emitted flag 防止 double emit；CONNECT_ONE_SHOT 保证 tween.finished 只触发一次
## SPACE 跳过时 tween.kill() 不会再 emit finished，靠 _emit_step_done_once 直接 emit step_advanced
##
## codex review P1-1（2026-05-10）：tween_factory.call() 返回值用 `as Tween` 转换，
## 若意外返回非 Tween 类型会得到 null。加 null 守卫直接 emit step_advanced 兜底
func _await_step(tween_factory: Callable) -> void:
	_step_emitted = false
	_current_step_tween = tween_factory.call() as Tween
	if _current_step_tween == null:
		push_warning("OverlayTransitionUI._await_step: tween_factory 返回 null，跳过本 step")
		_emit_step_done_once()
		await step_advanced
		return
	_current_step_tween.finished.connect(_emit_step_done_once, CONNECT_ONE_SHOT)
	await step_advanced
	_current_step_tween = null


## emit step_advanced 信号（dedup 守卫：避免 tween.finished 与手动跳过两条路径双触发）
func _emit_step_done_once() -> void:
	if _step_emitted:
		return
	_step_emitted = true
	step_advanced.emit()


## codex review P0-2 修复（2026-05-10）：等待 signal 或超时,谁先到都解锁
##
## 用 polling get_tree().process_frame 实现"signal vs timer 先到为胜"
## 防止 phase B `await world_ready` 在某些边界场景（_pending_respawn_intro
## 未被置 true / reload 异常）下永久挂起整个过渡组件
##
## 超时时 push_warning 便于排障；正常路径 < 2s 内 signal 即触发,不会进超时分支
func _await_signal_with_timeout(sig: Signal, timeout_sec: float) -> void:
	var got: bool = false
	# 用 dictionary 存 flag，闭包对 dict 的修改能穿透；GDScript 4 直接捕获 bool 也可,但 dict 更稳
	var state: Dictionary = {"got": false}
	var on_signal: Callable = func() -> void:
		state["got"] = true
	sig.connect(on_signal, CONNECT_ONE_SHOT)
	var deadline_ms: float = Time.get_ticks_msec() + timeout_sec * 1000.0
	while not state["got"] and Time.get_ticks_msec() < deadline_ms:
		await get_tree().process_frame
	if not state["got"]:
		push_warning("OverlayTransitionUI._await_signal_with_timeout: 超时 %.1fs，强制进入 phase C（兜底）" % timeout_sec)
		# 断开 callable 避免将来再 emit 时触发 noop
		if sig.is_connected(on_signal):
			sig.disconnect(on_signal)


## 写入文字 / icon 内容；重建 line labels
func _setup_content(lines: PackedStringArray, icon_data: Dictionary) -> void:
	# 清空现有 line labels（避免重复 play 时残留）
	for child in _lines_box.get_children():
		_lines_box.remove_child(child)
		child.queue_free()
	_line_labels = []
	_current_line_index = 0

	for line_text in lines:
		var lbl: Label = Label.new()
		lbl.text = line_text
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", LINE_FONT_SIZE)
		lbl.add_theme_color_override("font_color", LINE_COLOR)
		lbl.modulate.a = 0.0
		_lines_box.add_child(lbl)
		_line_labels.append(lbl)

	# Icon / 命数：按 count 重复火苗 emoji（每团一个），不再用 "× N" 数字显示
	# 语义：count = 当前总命数（含当前队长 + 剩余重生次数）
	# 例：还能重生 2 次 → 总命数 3 → 3 团火苗
	# 由调用方决定 count 值（WorldMap 传 RunState.respawns_left() + 1）
	var icon_str: String = String(icon_data.get("icon", ICON_FALLBACK))
	if icon_str.is_empty():
		icon_str = ICON_FALLBACK
	var count: int = int(icon_data.get("count", 0))
	if count <= 0:
		_icon_label.text = ""
	else:
		# 用空格分隔多个 emoji，让视觉上不挤在一起；HBox separation 保留给 icon vs count 间距
		var parts: PackedStringArray = PackedStringArray()
		for i in range(count):
			parts.append(icon_str)
		_icon_label.text = " ".join(parts)
	# count_label 不再使用（保留节点防 layout 跳动；text 清空 + visible=false）
	_count_label.text = ""
	_count_label.visible = false


# ─────────────────────────────────────
# 输入：顶吸防误触 + Phase C SPACE 打字机跳过
# ─────────────────────────────────────

## 顶吸所有键盘 / 鼠标事件，防止 phase A/B/D 期间误触发 WorldMap 探索 / 战斗逻辑
## phase C 期间 SPACE 走打字机跳过（_on_space_pressed_in_phase_c）
func _input(event: InputEvent) -> void:
	if _phase == PHASE_IDLE:
		return
	# 仅吞键盘 + 鼠标按键（不影响窗口事件等）
	if not (event is InputEventKey or event is InputEventMouseButton):
		return
	if _phase == PHASE_C and event is InputEventKey:
		var key: InputEventKey = event as InputEventKey
		if key.pressed and not key.echo and key.keycode == KEY_SPACE:
			_on_space_pressed_in_phase_c()
	get_viewport().set_input_as_handled()


## Phase C SPACE 行为（打字机式）：
##   - 当前正在淡入：立即设 alpha=1 → 推进到下一 step（hold）
##   - 当前停留中：立即推进到下一句的 fade in
##   - 全部已显示（_current_line_index == size）：推进到 fade out（在 hold 阶段被跳过）
##
## 实现策略：kill 当前 tween + 直接 emit step_advanced（_emit_step_done_once 内部 dedupe）
## 把当前句拉满 alpha 防"半路停下"
func _on_space_pressed_in_phase_c() -> void:
	if _current_step_tween != null and _current_step_tween.is_valid():
		_current_step_tween.kill()
	if _current_line_index < _line_labels.size():
		_line_labels[_current_line_index].modulate.a = 1.0
	_emit_step_done_once()
