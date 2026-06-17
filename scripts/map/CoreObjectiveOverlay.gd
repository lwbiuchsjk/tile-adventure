class_name CoreObjectiveOverlay
extends Node
## 核心目标传达 L1.5（核心目标传达_MVP §2.3）：大地图边缘带 + 离屏关键目标方向标记
##
## 设计原文：tile-advanture-design/核心目标传达_MVP.md §2.3
##
## 思路（桌面跑测三轮定稿，用户拍板）：不重构相机；在大地图 HUD 上方加一层"边缘带"——
## 屏幕四周一圈窄而实体的深色边框带（地图区 = 内缩矩形），离屏目标方向在带上画光晕。
## **光晕用 clip_children 遮罩裁到边框带内**——只在带内显式、不溢进地图区，醒目感 + 方向性兼得。
## 该带是可复用的"地图外指示区"：当前画 **我方据点（黄）+ climax boss（红）** 两个关键目标方向，日后可摆各类地标 ICON。
##   （L1.3d 起：原"敌方核心"目标随 L1.3c 敌方固定核心退役而失效，复用本机制改指据点 + climax boss；两者可同屏并存）
## 仅大地图态显示：战斗中相机 zoom 到战场、指引无意义 → 隐藏整层（set_battle_active）。
##
## 结构：本体 Node 持 CanvasLayer=7；内含 BandNode（Node2D，画边框带 + clip_children 裁剪）；
## BandNode 子 GlowNode（Node2D，画方向光晕 → 被裁到边框带内）。
## 层级：世界 layer=0 → 夜晚遮罩 5/6 → 本层 7 → UILayer 10


## 边框带节点：画四周深色带，clip_children 把子节点（光晕）裁到带内
class BandNode extends Node2D:
	var owner_overlay: CoreObjectiveOverlay = null

	func _draw() -> void:
		if owner_overlay != null:
			owner_overlay.draw_band(self)


## 光晕节点：画黄色方向光晕（作为 BandNode 子节点 → 被裁到边框带内）
class GlowNode extends Node2D:
	var owner_overlay: CoreObjectiveOverlay = null

	func _draw() -> void:
		if owner_overlay != null:
			owner_overlay.draw_glow(self)


# ─────────────────────────────────────────
# 可调参数（节点 .new() 创建 → 取脚本默认值；后续可 Resource 化，见待跟踪 P3）
# ─────────────────────────────────────────

## 边框带：窄而实体（桌面定稿：更窄 + 更实底）+ 内沿分隔线
@export var band_color: Color = Color(0.05, 0.04, 0.03, 0.90)
@export_range(6.0, 80.0, 1.0) var band_width: float = 15.0
@export var band_inner_line_color: Color = Color(1.0, 0.86, 0.30, 0.22)
@export_range(0.0, 4.0, 0.5) var band_inner_line_width: float = 1.0

## 底部 HUD 预留（px）：**兜底值**——仅在 HudBar 引用缺失 / 隐藏时使用
## 正常态边框下边界跟随 _hud_bar 实际顶沿（见 _frame_rect），无需手调此值
@export_range(0.0, 200.0, 2.0) var bottom_reserve: float = 32.0

## 离屏目标方向标记：黄色光晕（我方据点）+ 红色光晕（climax boss）；外晕 + 亮核，由 clip_children 裁到边框带内
## 据点（黄）
@export var marker_core_color: Color = Color(1.0, 0.88, 0.15, 1.0)
@export var marker_glow_color: Color = Color(1.0, 0.80, 0.0, 0.50)
## climax boss（红）
@export var marker_boss_core_color: Color = Color(1.0, 0.22, 0.18, 1.0)
@export var marker_boss_glow_color: Color = Color(1.0, 0.10, 0.10, 0.50)
## 半径两色共用
@export_range(4.0, 40.0, 1.0) var marker_core_radius: float = 13.0
@export_range(8.0, 80.0, 1.0) var marker_glow_radius: float = 30.0


# ─────────────────────────────────────────
# 内部 + 注入
# ─────────────────────────────────────────

var _layer: CanvasLayer = null
var _band_node: BandNode = null
var _glow_node: GlowNode = null
var _battle_active: bool = false

var _camera: Camera2D = null
var _world_view: WorldView = null
var _tile_size: int = 0
## 底部 HUD 引用（$UILayer/HudBar）：边框下边界跟随其实际顶沿，替代 bottom_reserve 手调
var _hud_bar: Control = null


## 初始化（WorldMap._init_subsystems 调一次）：挂 CanvasLayer=7 + BandNode（裁剪）+ GlowNode 子节点
## hud_bar：底部 HUD（$UILayer/HudBar），边框下边界跟随其顶沿；传 null 则回退 bottom_reserve
func setup(camera: Camera2D, world_view: WorldView, tile_size: int, hud_bar: Control = null) -> void:
	_camera = camera
	_world_view = world_view
	_tile_size = tile_size
	_hud_bar = hud_bar
	_layer = CanvasLayer.new()
	_layer.name = "CoreObjectiveCanvas"
	_layer.layer = 7
	add_child(_layer)
	_band_node = BandNode.new()
	_band_node.name = "BandNode"
	_band_node.owner_overlay = self
	# 关键：边框带绘制自身 + 裁剪子节点到自身绘制区 → 光晕只在带内显示
	_band_node.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	_layer.add_child(_band_node)
	_glow_node = GlowNode.new()
	_glow_node.name = "GlowNode"
	_glow_node.owner_overlay = self
	_band_node.add_child(_glow_node)


## 战斗态切换（WorldMap._start_battle_camera / _end_battle_camera 调）：战斗隐藏整层
func set_battle_active(active: bool) -> void:
	_battle_active = active
	if _layer != null:
		_layer.visible = not active


## 每帧重绘（相机 position_smoothing 跟随玩家，核心方位连续变化）
func _process(_delta: float) -> void:
	if _battle_active:
		return
	if _band_node != null:
		_band_node.queue_redraw()
	if _glow_node != null:
		_glow_node.queue_redraw()


# ─────────────────────────────────────────
# 绘制（由内部节点 _draw 回调）
# ─────────────────────────────────────────

## 边框带：四周一圈窄实体深色带（框在 HUD 之上的可视区 fr 内）+ 内沿分隔线
func draw_band(canvas: Node2D) -> void:
	var fr: Rect2 = _frame_rect(canvas)
	var w: float = _band_w(fr.size)
	if w <= 0.0:
		return
	var x0: float = fr.position.x
	var y0: float = fr.position.y
	var sx: float = fr.size.x
	var sy: float = fr.size.y
	canvas.draw_rect(Rect2(x0, y0, sx, w), band_color)                          # 上
	canvas.draw_rect(Rect2(x0, y0 + sy - w, sx, w), band_color)                # 下（落在 HUD 顶沿）
	canvas.draw_rect(Rect2(x0, y0 + w, w, sy - w * 2.0), band_color)           # 左
	canvas.draw_rect(Rect2(x0 + sx - w, y0 + w, w, sy - w * 2.0), band_color)  # 右
	if band_inner_line_width > 0.0:
		var inner: Rect2 = Rect2(x0 + w, y0 + w, sx - w * 2.0, sy - w * 2.0)
		canvas.draw_rect(inner, band_inner_line_color, false, band_inner_line_width)


## 方向光晕：两个关键目标各画一个离屏方向标记（均仅离屏才画，可同屏并存）
##   黄 = 我方据点（设据点后才有目标）；红 = climax boss（触发 climax 后才有，被消灭即消失）
func draw_glow(canvas: Node2D) -> void:
	if _camera == null:
		return
	var fr: Rect2 = _frame_rect(canvas)
	var w: float = _band_w(fr.size)
	# 黄 = 我方据点
	var stronghold_world: Vector2 = _find_stronghold_world()
	if stronghold_world.x >= 0.0:
		_draw_marker(canvas, stronghold_world, fr, w, marker_core_color, marker_glow_color)
	# 红 = climax boss（实时位置，跟随其移动；被消灭后从 _level_slots 消失 → 自动不画）
	var boss_world: Vector2 = _find_climax_boss_world()
	if boss_world.x >= 0.0:
		_draw_marker(canvas, boss_world, fr, w, marker_boss_core_color, marker_boss_glow_color)


## 单个离屏目标的方向光晕：投影 → 地图区内则不画 → 否则在带中线画光晕（被 clip 裁到带内）
func _draw_marker(canvas: Node2D, target_world: Vector2, fr: Rect2, w: float, core_color: Color, glow_color: Color) -> void:
	var screen_pt: Vector2 = _camera.get_canvas_transform() * target_world
	# 地图区 = 框内再内缩一圈带宽
	var map_area: Rect2 = Rect2(fr.position + Vector2(w, w), fr.size - Vector2(w, w) * 2.0)
	if map_area.has_point(screen_pt):  # 目标在地图区内（已可见）→ 不画方向标记
		return
	# 方向源点 / 落点钳位都用框中心（而非屏幕中心）——底部预留后框不再屏幕居中
	var center: Vector2 = fr.get_center()
	var dir: Vector2 = (screen_pt - center)
	if dir.length() < 0.001:
		return
	dir = dir.normalized()
	# 标记落点：从框中心沿 dir 射线与"边框带中线矩形"的交点（光晕落在带正中，clip 裁到带内）
	var mid: Rect2 = Rect2(fr.position + Vector2(w, w) * 0.5, fr.size - Vector2(w, w))
	var at: Vector2 = _ray_rect_edge(center, dir, mid)
	canvas.draw_circle(at, marker_glow_radius, glow_color)
	canvas.draw_circle(at, marker_glow_radius * 0.6, glow_color)
	canvas.draw_circle(at, marker_core_radius, core_color)


# ─────────────────────────────────────────
# 工具
# ─────────────────────────────────────────

## 边框框定矩形：下边界跟随底部 HUD 实际顶沿（布局自然，无需手调）；HudBar 缺失/隐藏时回退 bottom_reserve
## HudBar 与本覆盖层同为屏幕空间（各自 CanvasLayer，默认无偏移），global_rect.y 即同一屏幕 Y
func _frame_rect(canvas: Node2D) -> Rect2:
	var vp: Vector2 = canvas.get_viewport_rect().size
	var bottom: float = vp.y - bottom_reserve          # 兜底
	if _hud_bar != null and _hud_bar.visible:
		var hud_top: float = _hud_bar.get_global_rect().position.y
		if hud_top > 1.0 and hud_top <= vp.y:          # 布局已就绪 → 跟随 HUD 顶沿
			bottom = hud_top
	return Rect2(0.0, 0.0, vp.x, maxf(bottom, 1.0))


## 边框带实际宽度（钳到框短边的 40% 内，防极端窗口）
func _band_w(size: Vector2) -> float:
	return minf(band_width, minf(size.x, size.y) * 0.4)


## 我方据点世界像素中心；未设据点则返回 (-1,-1)
## L1.3d：复用本机制指向据点（黄）——位置取 RunState（L1.2 据点字段，chunk 外权威）
func _find_stronghold_world() -> Vector2:
	if _world_view == null or not RunState.has_stronghold():
		return Vector2(-1.0, -1.0)
	return _world_view.grid_to_pixel_center(RunState.stronghold_pos())


## climax boss（is_climax_boss 标记的 LevelSlot）世界像素中心；未触发 / 已被消灭则返回 (-1,-1)
## L1.3d：boss 是 _level_slots 里 is_climax_boss=true 的 pack（ExplorationCoordinator 触发时打标记）；
##   读其实时 position → 红光晕跟随 boss 移动；boss 被消灭后从表中消失 → 自动不画
func _find_climax_boss_world() -> Vector2:
	if _world_view == null:
		return Vector2(-1.0, -1.0)
	var level_slots: Dictionary = _world_view.get_level_slots()
	for v in level_slots.values():
		var slot: LevelSlot = v as LevelSlot
		if slot != null and slot.is_climax_boss:
			return _world_view.grid_to_pixel_center(slot.position)
	return Vector2(-1.0, -1.0)


## 从 origin 沿 dir 射线，求与矩形 rect 边界的首个正向交点（dir 已归一）
func _ray_rect_edge(origin: Vector2, dir: Vector2, rect: Rect2) -> Vector2:
	var t_min: float = INF
	var xs: Array[float] = [rect.position.x, rect.end.x]
	var ys: Array[float] = [rect.position.y, rect.end.y]
	if absf(dir.x) > 0.0001:
		for ex: float in xs:
			var t: float = (ex - origin.x) / dir.x
			if t > 0.0:
				var y: float = origin.y + t * dir.y
				if y >= rect.position.y - 0.5 and y <= rect.end.y + 0.5:
					t_min = minf(t_min, t)
	if absf(dir.y) > 0.0001:
		for ey: float in ys:
			var t2: float = (ey - origin.y) / dir.y
			if t2 > 0.0:
				var x: float = origin.x + t2 * dir.x
				if x >= rect.position.x - 0.5 and x <= rect.end.x + 0.5:
					t_min = minf(t_min, t2)
	if t_min == INF:
		return origin
	return origin + dir * t_min
