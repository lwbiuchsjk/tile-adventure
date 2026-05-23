class_name BattleHUD
extends Control
## 战斗内 HUD（探索体验·E MVP）
##
## 设计原文：
##   tile-advanture-design/探索体验实装/E_战斗就地展开_MVP.md §5 改动 2
##   tile-advanture-design/进度/探索体验_重生周期_推进进度.md "E2 拆 3 块"
##
## 职责：
##   - 战斗态时显示顶部状态栏（战斗回合 / 当前行动单位 hp）
##   - 底部行动按钮：[攻击] / [结束行动] / [退出战斗]
##   - 通过信号通知 WorldMap 玩家操作意图（不直接调 BattleSession，便于 WorldMap 统一调度）
##   - 通过 refresh(session) 接收 BattleSession 状态变化拉新
##
## 与 BattleSession / WorldMap 的关系：
##   - BattleSession.on_redraw_requested → WorldMap → BattleHUD.refresh(session)
##   - BattleHUD 按钮按下 → emit 信号 → WorldMap 路由到 BattleSession 接口
##
## 预制件化（MVP-α.5 / 2026-05-14）：节点结构在 res://scenes/ui/BattleHUD.tscn；
## 根 Control 自身 mouse_filter = IGNORE 让点击穿透到地图，仅 PanelContainer 子节点拦截。


# ─────────────────────────────────────
# 信号
# ─────────────────────────────────────

## 玩家点击 [攻击] 按钮（攻击范围内 hp 最低的敌方单位作目标）
signal attack_pressed

## 玩家点击 [结束行动] 按钮（当前单位本回合行动结束）
## 内部信号名 skip_pressed 保留为逻辑语义，UI 文案为"结束行动"
signal skip_pressed

## 玩家点击 [结束回合] 按钮 / 按 Enter（战斗单位视觉与操作改进_MVP §2.3）
## WorldMap 路由：先批量结束已移动单位 → 剩余未移动则守卫弹板，否则结束回合切敌方
signal end_turn_pressed

## 玩家点击 [退出战斗] 或 [撤离] 按钮（按 mode 区分）
##   mode == "exit"   —— 战场内无敌时主动退场（对应 BattleSession.try_manual_exit）
##   mode == "retreat" —— 战斗中队长站在战场边界主动撤离（对应 BattleSession.try_retreat）
## 持久 slot 战场参与设计 L1.1 扩展为携带 mode 参数
signal exit_pressed(mode: String)


# ─────────────────────────────────────
# 字段
# ─────────────────────────────────────

## 是否当前可见（HUD 显示中）
var is_open: bool = false

## 持久 slot 战场参与设计 L1.1（UX）：撤离可用时按钮高亮 modulate（青绿提亮，分量 >1 过曝增强醒目度）
## 其他状态（退出战斗 / 置灰 / 非撤离）按钮 modulate 恢复 Color.WHITE
const RETREAT_READY_MODULATE: Color = Color(0.55, 1.45, 1.2)


# ─────────────────────────────────────
# 节点引用（@onready 从预制件结构拿）
# ─────────────────────────────────────

@onready var _status_label: Label = $BattleStatusPanel/StatusLabel
@onready var _attack_btn: Button = $BattleActionPanel/HBox/AttackButton
@onready var _skip_btn: Button = $BattleActionPanel/HBox/SkipButton
@onready var _end_turn_btn: Button = $BattleActionPanel/HBox/EndTurnButton
@onready var _exit_btn: Button = $BattleActionPanel/HBox/ExitButton

## 入口 1.2：战斗动画期间锁输入（设计 §5 改动 6）
## true 时所有行动按钮强制 disabled，覆盖 refresh 中按 session 状态算出的可用性
var _actions_locked: bool = false

## 入口 1.2：缓存最近一次 refresh 的 session 引用，set_actions_enabled 解锁时主动 refresh 用
var _session_ref: BattleSession = null

## 持久 slot 战场参与设计 L1.1：当前 ExitButton 的行为模式
##   "exit"    —— 战场内无敌，点击触发 try_manual_exit
##   "retreat" —— 战斗中队长在边界，点击触发 try_retreat
##   ""        —— 按钮不可用（已 hide）
## refresh() 中根据 session 状态实时计算 + 写入；_on_button_pressed("exit") 时连同 emit
var _exit_mode: String = ""


# ─────────────────────────────────────
# 初始化
# ─────────────────────────────────────

## 预制件挂到 ui_layer 后自动调用；接按钮信号 + 默认隐藏
func _ready() -> void:
	visible = false
	is_open = false
	# 根 Control mouse_filter = IGNORE 让点击穿透到地图（.tscn 已设但兜底）
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_attack_btn.pressed.connect(_on_button_pressed.bind("attack"))
	_skip_btn.pressed.connect(_on_button_pressed.bind("skip"))
	_end_turn_btn.pressed.connect(_on_button_pressed.bind("end_turn"))
	_exit_btn.pressed.connect(_on_button_pressed.bind("exit"))


# ─────────────────────────────────────
# 公开接口
# ─────────────────────────────────────

## 战斗启动：显示 HUD + 拉首帧状态
func show_hud(session: BattleSession) -> void:
	visible = true
	is_open = true
	# 战斗启动时清除残留锁定（防止上一场战斗结束时仍在锁动画状态）
	_actions_locked = false
	refresh(session)


## 战斗结束：隐藏 HUD
func hide_hud() -> void:
	visible = false
	is_open = false
	_actions_locked = false
	_session_ref = null


## 入口 1.2：动画期间锁输入（设计 §5 改动 6）
##   enabled=false → 所有行动按钮强制 disabled，覆盖 session 状态算出的可用性
##   enabled=true  → 解锁后主动 refresh，让按钮按当前 session 状态恢复
##                   （动画完成后玩家应能立即操作，无需等下一次 redraw）
func set_actions_enabled(enabled: bool) -> void:
	_actions_locked = not enabled
	if _session_ref != null:
		refresh(_session_ref)
	elif _actions_locked:
		# 兜底：若 session 未缓存（show_hud 之前），仍主动设 disabled
		if _attack_btn != null:
			_attack_btn.disabled = true
		if _skip_btn != null:
			_skip_btn.disabled = true
		if _end_turn_btn != null:
			_end_turn_btn.disabled = true
		if _exit_btn != null:
			_exit_btn.disabled = true


## 状态变化时拉新：状态栏文字 + 按钮可用性
##
## 状态栏：战斗回合 X / 当前：[兵种 hp/max] / 阶段（玩家行动 / 敌方行动 / 已结束）
## [攻击] 按钮：玩家回合 + 当前 actor 攻击范围内有敌方目标 → 启用
## [结束行动] 按钮：玩家回合 + 当前 actor 未结束 → 启用
## [退出战斗 / 撤离] 按钮：见 _refresh_exit_button 内文档
func refresh(session: BattleSession) -> void:
	if session == null or _status_label == null:
		return
	# 入口 1.2：缓存 session 引用供 set_actions_enabled 主动 refresh 用
	_session_ref = session
	_status_label.text = _format_status_text(session)
	# 按钮启用判断
	var is_player: bool = session.is_player_turn() and not session.is_ended()
	var actor: BattleUnit = session.current_actor()
	var has_actor: bool = actor != null and actor.is_active and actor.is_alive() and not actor.has_attacked
	# 攻击按钮：玩家回合 + 当前单位未攻击 + 攻击范围内有目标
	var has_target: bool = false
	if is_player and has_actor:
		has_target = not session.get_attackable_targets().is_empty()
	# 入口 1.2：_actions_locked 为 true 时强制 disable 所有按钮（覆盖 session 状态判断）
	if _attack_btn != null:
		_attack_btn.disabled = _actions_locked or not (is_player and has_actor and has_target)
	# 结束行动按钮：玩家回合 + 当前单位未结束
	if _skip_btn != null:
		_skip_btn.disabled = _actions_locked or not (is_player and has_actor)
	# 结束回合按钮（视觉与操作改进 §2.3）：回合级动作，玩家回合 + 未结束即可用（不依赖当前 actor）
	if _end_turn_btn != null:
		_end_turn_btn.disabled = _actions_locked or not is_player
	# 退出战斗 / 撤离按钮：按 session 状态切换文字 + 显隐
	_refresh_exit_button(session, is_player)


## 持久 slot 战场参与设计 L1.1（UX 调整）：ExitButton 常驻可见，按上下文切换文字 + enable/disable
##   分支 A: 战场内无敌        → 文字"退出战斗"，mode="exit"，enabled（走 try_manual_exit）
##   分支 B: 有敌 + 队长可撤退   → 文字"撤离"，mode="retreat"，enabled 高亮（走 try_retreat）
##   分支 C: 有敌 + 队长不可撤退 → 文字"撤离"，mode="retreat"，disabled 置灰（提示按钮存在但当前不可用）
##
## 按钮始终 visible；可用性由 disabled 控制；_actions_locked（动画期间）/ 非玩家回合一律置灰
func _refresh_exit_button(session: BattleSession, is_player: bool) -> void:
	if _exit_btn == null:
		return
	# 常驻可见
	_exit_btn.visible = true
	# 非玩家回合：保留文字、置灰 + 取消高亮
	if not is_player:
		_exit_btn.disabled = true
		_exit_btn.modulate = Color.WHITE
		return
	var enemy_remaining: bool = session.has_enemy_in_arena()
	if not enemy_remaining:
		# 分支 A：战场内无敌 → 退出战斗（可用，普通样式）
		_exit_btn.text = "退出战斗"
		_exit_mode = "exit"
		_exit_btn.disabled = _actions_locked
		_exit_btn.modulate = Color.WHITE
	else:
		# 分支 B/C：有敌 → 撤离；按队长是否在可撤退边界格决定 enabled / disabled
		_exit_btn.text = "撤离"
		_exit_mode = "retreat"
		var can_retreat: bool = session.can_leader_retreat()
		_exit_btn.disabled = _actions_locked or not can_retreat
		# UX-3：撤离真正可用（未锁 + 可撤退）时按钮高亮加强；否则恢复普通样式
		var retreat_ready: bool = can_retreat and not _actions_locked
		_exit_btn.modulate = RETREAT_READY_MODULATE if retreat_ready else Color.WHITE


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
##
## exit 类按钮按下时，携带 _refresh_exit_button 计算出的当前 _exit_mode
##（"exit" / "retreat"），由 WorldMap 路由到对应 BattleSession 接口
func _on_button_pressed(kind: String) -> void:
	match kind:
		"attack":
			attack_pressed.emit()
		"skip":
			skip_pressed.emit()
		"end_turn":
			end_turn_pressed.emit()
		"exit":
			# _exit_mode 为空时按 mode="exit" 兜底（防御性，正常路径 refresh 会保证非空）
			var mode: String = _exit_mode if _exit_mode != "" else "exit"
			exit_pressed.emit(mode)
