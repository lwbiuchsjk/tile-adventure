class_name BattleUI
extends Node
## 战斗确认面板子系统
## 负责战斗预览弹板的创建、显示、结果预览格式化。
## 玩家选择后发出信号，由 WorldMap 处理战斗结算逻辑。

## 玩家选择击退
signal repel_chosen
## 玩家选择击败
signal defeat_chosen
## 玩家取消战斗
signal cancelled

# ─────────────────────────────────────
# 状态
# ─────────────────────────────────────

## 战斗面板引用
var _panel: PanelContainer = null

## 是否正在等待玩家选择
var is_pending: bool = false

## 是否为强制战斗（敌方主动触发，禁止取消）
var is_forced: bool = false

## 当前待确认的关卡
var pending_level: LevelSlot = null

## 预计算的完整战斗结果（100% 伤害）
var pending_full_result: BattleResolver.BattleResult = null

## 缓存的配置
var _repel_player_rate: float = 0.6
var _repel_enemy_rate: float = 0.6

# ─────────────────────────────────────
# 初始化
# ─────────────────────────────────────

## 初始化配置参数（在 WorldMap._ready 中调用一次）
func init_config(repel_player_rate: float, repel_enemy_rate: float) -> void:
	_repel_player_rate = repel_player_rate
	_repel_enemy_rate = repel_enemy_rate


## 程序化创建战斗确认弹板，挂载到指定 CanvasLayer
func create_ui(ui_layer: CanvasLayer) -> void:
	_panel = PanelContainer.new()
	_panel.visible = false
	_panel.set_anchors_and_offsets_preset(
		Control.PRESET_CENTER, Control.PRESET_MODE_KEEP_SIZE
	)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_panel.custom_minimum_size = Vector2(360, 0)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 6)

	# 标题
	var title: Label = Label.new()
	title.name = "BattleTitleLabel"
	title.text = "遭遇战斗"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(1.0, 0.92, 0.30))
	vbox.add_child(title)

	# 分隔线
	var sep1: HSeparator = HSeparator.new()
	sep1.add_theme_constant_override("separation", 8)
	vbox.add_child(sep1)

	# 战斗信息标签（敌方部队 + 奖励）
	var battle_label: Label = Label.new()
	battle_label.name = "BattleInfoLabel"
	battle_label.text = ""
	battle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(battle_label)

	# 分隔线
	var sep2: HSeparator = HSeparator.new()
	sep2.add_theme_constant_override("separation", 6)
	vbox.add_child(sep2)

	# 击退预览标签（蓝色调表示保守选项）
	var repel_label: Label = Label.new()
	repel_label.name = "RepelPreviewLabel"
	repel_label.text = ""
	repel_label.add_theme_color_override("font_color", Color(0.65, 0.80, 0.95))
	vbox.add_child(repel_label)

	# 击败预览标签（橙色调表示激进选项）
	var defeat_label: Label = Label.new()
	defeat_label.name = "DefeatPreviewLabel"
	defeat_label.text = ""
	defeat_label.add_theme_color_override("font_color", Color(0.95, 0.75, 0.45))
	vbox.add_child(defeat_label)

	# 分隔线
	var sep3: HSeparator = HSeparator.new()
	sep3.add_theme_constant_override("separation", 6)
	vbox.add_child(sep3)

	# 按钮区域
	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.name = "BattleButtonArea"
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 12)

	# 击退按钮（蓝色调）
	var btn_repel: Button = Button.new()
	btn_repel.name = "BtnRepel"
	btn_repel.text = "击退"
	btn_repel.custom_minimum_size = Vector2(80, 32)
	btn_repel.add_theme_color_override("font_color", Color(0.65, 0.80, 0.95))
	btn_repel.add_theme_color_override("font_hover_color", Color(0.80, 0.92, 1.0))
	btn_repel.pressed.connect(_on_repel_pressed)
	hbox.add_child(btn_repel)

	# 击败按钮（橙色调）
	var btn_defeat: Button = Button.new()
	btn_defeat.name = "BtnDefeat"
	btn_defeat.text = "击败"
	btn_defeat.custom_minimum_size = Vector2(80, 32)
	btn_defeat.add_theme_color_override("font_color", Color(0.95, 0.75, 0.45))
	btn_defeat.add_theme_color_override("font_hover_color", Color(1.0, 0.85, 0.55))
	btn_defeat.pressed.connect(_on_defeat_pressed)
	hbox.add_child(btn_defeat)

	# 取消按钮（灰色调）
	var btn_cancel: Button = Button.new()
	btn_cancel.name = "BtnCancel"
	btn_cancel.text = "取消"
	btn_cancel.custom_minimum_size = Vector2(80, 32)
	btn_cancel.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	btn_cancel.add_theme_color_override("font_hover_color", Color(0.75, 0.75, 0.75))
	btn_cancel.pressed.connect(_on_cancel_pressed)
	hbox.add_child(btn_cancel)

	vbox.add_child(hbox)
	_panel.add_child(vbox)
	ui_layer.add_child(_panel)

# ─────────────────────────────────────
# 显示 / 隐藏
# ─────────────────────────────────────

## 显示战斗预览弹板
## level: 待交战关卡
## player_troops: 玩家当前参战部队
## battle_config: 战斗配置字典
## damage_increment: 每轮 base_damage 增量
## forced: 是否为敌方主动触发的强制战斗
func show_confirm(level: LevelSlot, player_troops: Array[TroopData],
		battle_config: Dictionary, damage_increment: float,
		forced: bool) -> void:
	is_pending = true
	is_forced = forced
	pending_level = level

	# 预计算完整战斗结果（100% 伤害）
	pending_full_result = BattleResolver.resolve(
		player_troops, level.troops, battle_config,
		level.difficulty, damage_increment
	)

	# 计算击退和击败两套结果
	var repel_result: BattleResolver.BattleResult = pending_full_result.apply_damage_rate(
		_repel_player_rate, _repel_enemy_rate
	)
	var defeat_result: BattleResolver.BattleResult = pending_full_result

	# 判断各倍率下是否能全灭敌方
	var repel_wipes: bool = BattleResolver.would_wipe_enemies(level.troops, repel_result.enemy_damages)
	var defeat_wipes: bool = BattleResolver.would_wipe_enemies(level.troops, defeat_result.enemy_damages)

	# 更新标题（区分主动/被动战斗）
	var title_label: Label = _panel.find_child("BattleTitleLabel", true, false) as Label
	if title_label != null:
		title_label.text = "敌方来袭！" if forced else "遭遇战斗"

	# 更新战斗信息
	var info_label: Label = _panel.find_child("BattleInfoLabel", true, false) as Label
	if info_label != null:
		var text: String = "敌方：%s" % level.get_troops_detail_display()
		if not level.rewards.is_empty():
			text += "\n击败奖励：%s" % level.get_rewards_display()
		info_label.text = text

	# 击退预览（击退全灭时隐藏）
	var repel_label: Label = _panel.find_child("RepelPreviewLabel", true, false) as Label
	if repel_label != null:
		if repel_wipes:
			repel_label.text = ""
			repel_label.visible = false
		else:
			repel_label.text = "── 击退（不获得奖励）──\n%s" % _format_preview(
				player_troops, repel_result, level.troops
			)
			repel_label.visible = true

	# 击败预览
	var defeat_label: Label = _panel.find_child("DefeatPreviewLabel", true, false) as Label
	if defeat_label != null:
		if repel_wipes:
			defeat_label.text = "── 击败（低损耗全灭）──\n%s" % _format_preview(
				player_troops, repel_result, level.troops
			)
			defeat_label.visible = true
		elif defeat_wipes:
			defeat_label.text = "── 击败 ──\n%s" % _format_preview(
				player_troops, defeat_result, level.troops
			)
			defeat_label.visible = true
		else:
			defeat_label.text = ""
			defeat_label.visible = false

	# 按钮可见性
	var btn_repel: Button = _panel.find_child("BtnRepel", true, false) as Button
	if btn_repel != null:
		btn_repel.visible = not repel_wipes
	var btn_defeat: Button = _panel.find_child("BtnDefeat", true, false) as Button
	if btn_defeat != null:
		btn_defeat.visible = repel_wipes or defeat_wipes
	# 强制战斗时隐藏取消按钮
	var btn_cancel: Button = _panel.find_child("BtnCancel", true, false) as Button
	if btn_cancel != null:
		btn_cancel.visible = not forced

	_panel.visible = true


## 隐藏面板并清除状态
func hide() -> void:
	if _panel != null:
		_panel.visible = false
	is_pending = false
	is_forced = false
	pending_level = null
	pending_full_result = null

# ─────────────────────────────────────
# 内部方法
# ─────────────────────────────────────

## 格式化战斗预览文本（展示双方各部队的预计伤害）
func _format_preview(player_troops: Array[TroopData],
		result: BattleResolver.BattleResult,
		enemy_troops: Array[TroopData]) -> String:
	var lines: Array[String] = []
	# 我方伤害预览
	lines.append("  我方损耗：")
	for i in range(player_troops.size()):
		var t: TroopData = player_troops[i]
		var dmg: int = result.damages[i] if i < result.damages.size() else 0
		var remaining: int = maxi(0, t.current_hp - dmg)
		lines.append("    %s: -%d (%d→%d)" % [t.get_display_text(), dmg, t.current_hp, remaining])
	# 敌方伤害预览
	lines.append("  敌方损耗：")
	for i in range(enemy_troops.size()):
		var e: TroopData = enemy_troops[i]
		var dmg: int = result.enemy_damages[i] if i < result.enemy_damages.size() else 0
		var remaining: int = maxi(0, e.current_hp - dmg)
		lines.append("    %s: -%d (%d→%d)" % [e.get_display_text(), dmg, e.current_hp, remaining])
	return "\n".join(lines)


## 击退按钮回调
func _on_repel_pressed() -> void:
	repel_chosen.emit()


## 击败按钮回调
func _on_defeat_pressed() -> void:
	defeat_chosen.emit()


## 取消按钮回调
func _on_cancel_pressed() -> void:
	cancelled.emit()
