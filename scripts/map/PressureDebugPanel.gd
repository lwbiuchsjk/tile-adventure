class_name PressureDebugPanel
extends CanvasLayer
## L1.3d-1 阶段 B 桌面验证工具：暗影压力测试信息面板（Ctrl+I 切换，仅 debug build 创建）
##
## 设计原文：tile-advanture-design/无限地图实装/L1.3d-1_暗影压力引擎_MVP.md §七（桌面验证）
##
## 用途：P=f(扎营,视野源) 暂无正式 UI（前兆信号 = L1.3d-2）；本面板把 P 及其驱动的威胁档
##   （tier 权重 / 增援间隔 / pack 上限）实时显示出来，让「难度随扎营/占领递增」可被直接观测。
##   常驻 CanvasLayer，可见时每帧刷新——扎营 / 占领 slot 后立刻看到 P 与威胁档变化。
##
## 非玩法逻辑：纯只读展示，不写任何状态；release 编译不创建（MapBootstrap 用 OS.is_debug_build() 守卫）。

var _world_view: WorldView = null
var _label: Label = null


func _init() -> void:
	layer = 20  # UILayer=10 / 边缘带=7 之上，确保盖在最上层
	visible = false
	# 半透明深底面板（左上角）
	var panel: PanelContainer = PanelContainer.new()
	panel.position = Vector2(12, 12)
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.0, 0.0, 0.0, 0.72)
	sb.set_content_margin_all(10.0)
	sb.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)
	_label = Label.new()
	_label.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0))
	panel.add_child(_label)


## 注入数据源（WorldView 暴露 P / 视野源数 / tier 表 / level_slots）
func setup(world_view: WorldView) -> void:
	_world_view = world_view


## 切换显示（Ctrl+I）；切到可见时立即刷新一次
func toggle() -> void:
	visible = not visible
	if visible:
		_refresh()


func _process(_delta: float) -> void:
	if visible:
		_refresh()


## 重建面板文本：扎营/视野源 → 各 level → P → 威胁档（tier 权重 / interval / pack）
func _refresh() -> void:
	if _world_view == null or _label == null:
		return
	var camp: int = RunState.total_camp_count()
	var sources: int = _world_view.get_vision_source_count()
	var camp_l: int = ShadowPressure.camp_level(camp)
	var vis_l: int = ShadowPressure.vision_level(sources)
	var p: int = camp_l + vis_l
	var interval: int = EnemyReinforcement.reinforcement_interval_for_pressure(p)
	var packs: int = EnemyReinforcement._count_enemy_packs(_world_view.get_level_slots())
	var cap: int = EnemyReinforcement.SPAWN_CFG.enemy_pack_global_cap
	var base_iv: int = EnemyReinforcement.SPAWN_CFG.enemy_reinforcement_interval
	var min_iv: int = EnemyReinforcement.SPAWN_CFG.enemy_reinforcement_interval_min

	var cfg: PressureConfig = ShadowPressure.CFG
	var camp_th: String = "[%d,%d,%d]" % [cfg.camp_threshold_1, cfg.camp_threshold_2, cfg.camp_threshold_3]
	var vis_th: String = "[%d,%d]" % [cfg.vision_threshold_1, cfg.vision_threshold_2]
	var lines: Array[String] = [
		"══ 暗影压力测试面板 (Ctrl+I) ══",
		"扎营次数: %d  → camp_level %d   阈值 %s" % [camp, camp_l, camp_th],
		"视野源数: %d  → vision_level %d   阈值 %s" % [sources, vis_l, vis_th],
		"压力 P = %d + %d = %d" % [camp_l, vis_l, p],
		"─ P=%d 威胁档 ─" % p,
		"  增援 tier 权重: %s" % _tier_weights_text(p),
		"  增援间隔: %d 回合 (基数 %d - P, 下限 %d)" % [interval, base_iv, min_iv],
		"  场上敌方 pack: %d / %d (cap, 不随 P)" % [packs, cap],
	]
	_label.text = "\n".join(lines)


## 当前 P 段的 tier 权重串（从 tier_ratio 表筛 pressure_level == p 的行）
func _tier_weights_text(pressure: int) -> String:
	var rows: Array = _world_view.get_enemy_tier_ratio_rows()
	var parts: Array[String] = []
	for row_v in rows:
		var row: Dictionary = row_v as Dictionary
		if row == null:
			continue
		if int(row.get("pressure_level", "-1")) != pressure:
			continue
		var count: int = int(row.get("count", "0"))
		if count <= 0:
			continue
		parts.append("t%d×%d" % [int(row.get("tier", "0")), count])
	if parts.is_empty():
		return "(无配置 → 兜底 t0)"
	return " ".join(parts)
