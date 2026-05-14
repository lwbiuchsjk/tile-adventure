class_name VictoryUI
extends Control
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
##   本 UI 承担核心城镇翻转的胜负展示；
##   `_show_defeat_text`（部队全灭 / 放弃路径）走 NoticeBar 文案 + 评分，由 WorldMap 直接路由。
##
## 预制件化（MVP-α.5 / 2026-05-14）：节点结构在 res://scenes/ui/VictoryUI.tscn；
## 业务方法（show_victory / show_defeat / hide_overlay / confirm_restart）接口保持不变；
## 根类型从 extends Node 调整为 extends Control（实装时细化：原 Node 仅作业务壳、
## 与 Control _root 一对一解耦，预制件化后 Node + Control 解耦冗余，直接以 Control 作根）。


## 重开按钮点击信号（WorldMap 路由 get_tree().reload_current_scene）
signal restart_pressed


## 对外暴露：遮罩是否正在显示
var is_open: bool = false


# ─────────────────────────────────────
# 节点引用（@onready 拿预制件子节点）
# ─────────────────────────────────────

## 胜负主文本（"胜利！" / "失败..."）
@onready var _title_label: Label = $Center/ResultPanel/Margin/VBox/TitleLabel

## 副文本（回合数 / 评分说明）
@onready var _subtitle_label: Label = $Center/ResultPanel/Margin/VBox/SubtitleLabel

## 重开按钮
@onready var _btn_restart: Button = $Center/ResultPanel/Margin/VBox/RestartButton


# ─────────────────────────────────────
# 初始化
# ─────────────────────────────────────

## 预制件挂到 ui_layer 后自动调用；连接按钮信号 + 兜底确认可见性默认关闭
func _ready() -> void:
	visible = false
	is_open = false
	# .tscn 已设 mouse_filter = STOP，这里冗余兜底，防止 .tscn 误改时点击穿透
	mouse_filter = Control.MOUSE_FILTER_STOP
	_btn_restart.pressed.connect(_on_restart_pressed)


# ─────────────────────────────────────
# 显示 / 隐藏
# ─────────────────────────────────────

## 显示胜利遮罩
## subtitle 通常传回合数 / 评分文本，MVP 可为空字符串
func show_victory(subtitle: String = "") -> void:
	_title_label.text = "胜利！"
	_title_label.add_theme_color_override("font_color", Color(1.0, 0.90, 0.25, 1.0))
	_subtitle_label.text = subtitle
	visible = true
	is_open = true
	_btn_restart.grab_focus()


## 显示失败遮罩
func show_defeat(subtitle: String = "") -> void:
	_title_label.text = "失败..."
	_title_label.add_theme_color_override("font_color", Color(1.0, 0.40, 0.40, 1.0))
	_subtitle_label.text = subtitle
	visible = true
	is_open = true
	_btn_restart.grab_focus()


## 隐藏遮罩（重开前调用，或调试用）
func hide_overlay() -> void:
	visible = false
	is_open = false


# ─────────────────────────────────────
# 信号回调
# ─────────────────────────────────────

## 重开按钮点击：向 WorldMap 发信号
func _on_restart_pressed() -> void:
	restart_pressed.emit()


## 入口 4 MVP：SPACE 路由触发重开（与点击重开按钮等价）
## 由 WorldMap._unhandled_input SPACE 分流时调用；遮罩不可见时为 noop
func confirm_restart() -> void:
	if not is_open:
		return
	restart_pressed.emit()
