class_name BattleHUD
extends Node
## 战斗内 HUD（探索体验·E MVP）
##
## 设计原文：
##   tile-advanture-design/探索体验实装/E_战斗就地展开_MVP.md §5 改动 2
##   tile-advanture-design/进度/探索体验_重生周期_推进进度.md "E2 拆 3 块"
##
## 职责：
##   - 战斗态时显示顶部状态栏（战斗回合 / 当前行动单位 hp）
##   - 底部行动按钮：[攻击] / [跳过] / [退出战斗]
##   - 通过信号通知 WorldMap 玩家操作意图（不直接调 BattleSession，便于 WorldMap 统一调度）
##   - 通过 refresh(session) 接收 BattleSession 状态变化拉新
##
## 与 BattleSession / WorldMap 的关系：
##   - BattleSession.on_redraw_requested → WorldMap → BattleHUD.refresh(session)
##   - BattleHUD 按钮按下 → emit 信号 → WorldMap 路由到 BattleSession 接口
##
## 程序化创建（不使用 .tscn），对齐项目既有 UI 风格（EventPanelUI / VictoryUI）


# ─────────────────────────────────────
# 信号
# ─────────────────────────────────────

## 玩家点击 [攻击] 按钮（攻击范围内 hp 最低的敌方单位作目标）
signal attack_pressed

## 玩家点击 [跳过] 按钮（当前单位本回合行动结束）
signal skip_pressed

## 玩家点击 [退出战斗] 按钮（手动退出尝试）
signal exit_pressed


# ─────────────────────────────────────
# 字段
# ─────────────────────────────────────

## 是否当前可见（HUD 显示中）
var is_open: bool = false


# ─────────────────────────────────────
# 节点引用
# ─────────────────────────────────────

## 全屏根容器（不拦截点击；战斗中地图点击仍要透传到 WorldMap）
var _root: Control = null

## 顶部状态栏
var _top_panel: PanelContainer = null
var _status_label: Label = null

## 底部行动栏
var _bottom_panel: PanelContainer = null
var _attack_btn: Button = null
var _skip_btn: Button = null
var _exit_btn: Button = null


# ─────────────────────────────────────
# 初始化
# ─────────────────────────────────────

## 程序化构建 UI 并挂到 ui_layer；调用方 = WorldMap._init_subsystems
##
## 初始 hidden；战斗启动时由 show_hud(session) 切显示
func create_ui(ui_layer: CanvasLayer) -> void:
	# 全屏 root：mouse_filter = IGNORE，让点击穿透到地图（玩家点格移动 / 攻击）
	# 仅"按钮区"自身 STOP 拦截
	_root = Control.new()
	_root.name = "BattleHUDOverlay"
	_root.visible = false
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_layer.add_child(_root)

	# 顶部状态栏：横幅式，锚定屏幕顶部居中
	_top_panel = PanelContainer.new()
	_top_panel.name = "BattleStatusPanel"
	_top_panel.anchor_left = 0.5
	_top_panel.anchor_right = 0.5
	_top_panel.anchor_top = 0.0
	_top_panel.anchor_bottom = 0.0
	_top_panel.offset_top = 8
	# 拦截点击避免误触地图
	_top_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	# 应用样式
	var top_sb: StyleBoxFlat = _make_panel_style()
	_top_panel.add_theme_stylebox_override("panel", top_sb)
	_root.add_child(_top_panel)

	_status_label = Label.new()
	_status_label.name = "StatusLabel"
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 14)
	_status_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.65, 1.0))
	_top_panel.add_child(_status_label)

	# 居中横向布局：通过设置 size + 锚点偏移让 Panel 自身居中
	# Godot 4 中 PanelContainer 的最小宽由内容决定，这里靠 status_label 的文本宽自适应
	# 用 size_flags_horizontal = SHRINK_CENTER 让其在 anchor_left=0.5 锚点附近居中
	_top_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	# 通过 offset_left / offset_right 配合 grow_horizontal 实现居中
	_top_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH

	# 底部行动栏：HBox，3 按钮，锚定屏幕底部居中
	_bottom_panel = PanelContainer.new()
	_bottom_panel.name = "BattleActionPanel"
	_bottom_panel.anchor_left = 0.5
	_bottom_panel.anchor_right = 0.5
	_bottom_panel.anchor_top = 1.0
	_bottom_panel.anchor_bottom = 1.0
	_bottom_panel.offset_bottom = -8
	_bottom_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var bottom_sb: StyleBoxFlat = _make_panel_style()
	_bottom_panel.add_theme_stylebox_override("panel", bottom_sb)
	_root.add_child(_bottom_panel)
	_bottom_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_bottom_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN

	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	_bottom_panel.add_child(hbox)

	_attack_btn = _make_button("攻击", "attack")
	hbox.add_child(_attack_btn)
	_skip_btn = _make_button("跳过", "skip")
	hbox.add_child(_skip_btn)
	_exit_btn = _make_button("退出战斗", "exit")
	hbox.add_child(_exit_btn)


## 通用面板样式：深棕半透 + 浅棕描边，对齐 EventPanelUI
func _make_panel_style() -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.15, 0.10, 0.05, 0.92)
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.border_color = Color(0.45, 0.30, 0.15, 1.0)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


## 构造单个按钮 + 接信号
## 用 Callable.bind 绑定语义化字符串，避免 lambda 捕获散乱
func _make_button(label: String, kind: String) -> Button:
	var btn: Button = Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(96, 32)
	btn.pressed.connect(_on_button_pressed.bind(kind))
	return btn


# ─────────────────────────────────────
# 公开接口
# ─────────────────────────────────────

## 战斗启动：显示 HUD + 拉首帧状态
func show_hud(session: BattleSession) -> void:
	if _root == null:
		push_warning("BattleHUD.show_hud: create_ui 未调用，忽略")
		return
	_root.visible = true
	is_open = true
	refresh(session)


## 战斗结束：隐藏 HUD
func hide_hud() -> void:
	if _root != null:
		_root.visible = false
	is_open = false


## 状态变化时拉新：状态栏文字 + 按钮可用性
##
## 状态栏：战斗回合 X / 当前：[兵种 hp/max] / 阶段（玩家行动 / 敌方行动 / 已结束）
## [攻击] 按钮：玩家回合 + 当前 actor 攻击范围内有敌方目标 → 启用
## [跳过] 按钮：玩家回合 + 当前 actor 未结束 → 启用
## [退出战斗] 按钮：玩家回合 + 战场内无敌方存活 → 启用（点击后 BattleSession.try_manual_exit）
func refresh(session: BattleSession) -> void:
	if session == null or _status_label == null:
		return
	_status_label.text = _format_status_text(session)
	# 按钮启用判断
	var is_player: bool = session.is_player_turn() and not session.is_ended()
	var actor: BattleUnit = session.current_actor()
	var has_actor: bool = actor != null and actor.is_active and actor.is_alive() and not actor.has_attacked
	# 攻击按钮：玩家回合 + 当前单位未攻击 + 攻击范围内有目标
	var has_target: bool = false
	if is_player and has_actor:
		has_target = not session.get_attackable_targets().is_empty()
	if _attack_btn != null:
		_attack_btn.disabled = not (is_player and has_actor and has_target)
	# 跳过按钮：玩家回合 + 当前单位未结束
	if _skip_btn != null:
		_skip_btn.disabled = not (is_player and has_actor)
	# 退出战斗按钮：玩家回合 + 战场内无敌方
	# 战场内有敌方时仍允许点击，BattleSession.try_manual_exit 返回 false → WorldMap 给 _show_notice
	# 这里不 disable 是为了让玩家有"按了得到反馈"的体验，比 disabled 状态更明确
	if _exit_btn != null:
		_exit_btn.disabled = not is_player


# ─────────────────────────────────────
# 内部
# ─────────────────────────────────────

## 状态栏文本格式化
##
## 玩家回合：「战斗回合 X · 玩家行动 · [兵种 hp/max]」
## 敌方回合：「战斗回合 X · 敌方行动」（不显示具体单位，避免快速切换闪烁）
## 已结束：  「战斗已结束」
func _format_status_text(session: BattleSession) -> String:
	if session.is_ended():
		return "战斗已结束"
	var phase_text: String = "玩家行动" if session.is_player_turn() else "敌方行动"
	var base: String = "战斗回合 %d · %s" % [session.battle_round, phase_text]
	if session.is_player_turn():
		var actor: BattleUnit = session.current_actor()
		if actor != null and actor.troop != null:
			base += " · %s %d/%d" % [
				actor.troop.get_display_text(),
				actor.troop.current_hp,
				actor.troop.max_hp
			]
	return base


## 按钮按下统一回调，按 kind 路由到对应信号
func _on_button_pressed(kind: String) -> void:
	match kind:
		"attack":
			attack_pressed.emit()
		"skip":
			skip_pressed.emit()
		"exit":
			exit_pressed.emit()
