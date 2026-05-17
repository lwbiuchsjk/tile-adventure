class_name NightVisionLayer
extends Node
## 夜晚视野子系统（MVP-δ 阶段 2 抽出）
##
## 设计原文：
##   tile-advanture-design/代码健康度回看/MVP-δ_拆分批2.md §核心概念 - NightVisionLayer
##   tile-advanture-design/夜晚视野_MVP.md
##
## 职责：
##   - 夜晚遮罩 CanvasLayer (layer=5) + ColorRect ShaderMaterial（玩家光源 + 浓雾衰减）
##   - 浓雾外敌人信号 CanvasLayer (layer=6) + Node2D 屏幕空间菱形（绕开夜晚遮罩黑幕）
##   - DAY ↔ NIGHT phase 平滑 fade（_phase_alpha Tween）
##   - 战斗中强制白天遮罩（_battle_force_day），战斗结束按战斗前 phase fade 回去
##   - 浓雾像素判定（is_in_fog）+ 闪烁敌人 redraw 驱动（_process 帧驱动）
##
## 与 WorldMap 的接线（NightVisionLayer 不依赖 UI 系统，所有外部依赖经 setup 注入）：
##   - setup(turn_manager, camera, world_view, tile_size, enemy_slot_color, enemy_move_color)
##   - 战斗开始 / 结束：WorldMap._start_battle_camera / _end_battle_camera 调
##     set_battle_force_day_on() / resync_to_post_battle_state()
##   - 浓雾像素判定：WorldMap.WorldView.is_in_fog 转发到本节点 is_in_fog
##   - 信号节点 _draw 回调：FogSignalNode 持有本节点引用，调 collect_fog_signals 拿数据


# ─────────────────────────────────────────
# 调参 Resource + 资源引用
# ─────────────────────────────────────────

## 调参 Resource（MVP-B 阶段 1：10 个原 const 迁出）—— 双击 .tres 在 inspector 编辑字段
## schema: scripts/config/night_vision_config.gd；instance: assets/config/night_vision_config.tres
const CFG: NightVisionConfig = preload("res://assets/config/night_vision_config.tres")

## 夜晚遮罩 ShaderMaterial 资源（preload 让编辑期校验路径）
## 2026-05-11 跑测修复：shader 从 vec4[N] 多光源数组简化为单光源 UV 空间；
## 多光源扩展接口（玩家方城建 slot 等）记入待跟踪事项索引 §十一 P3
const NIGHT_OVERLAY_MATERIAL: ShaderMaterial = preload("res://assets/shader/night_overlay.tres")


# ─────────────────────────────────────────
# 内嵌类型：浓雾外敌人信号节点（原 WorldMap.FogSignalNode 迁过来）
# ─────────────────────────────────────────

## 浮层节点：CanvasLayer=6 内含的 Node2D，专门画浓雾外敌人闪烁信号
## _draw 调宿主 NightVisionLayer.collect_fog_signals 拿数据 → 画屏幕空间菱形
## 与世界层渲染解耦，绕开 CanvasLayer=5 夜晚遮罩黑幕的遮挡
class FogSignalNode extends Node2D:
	## 宿主 NightVisionLayer 引用（弱引用语义；父节点退出场景时整个浮层一起 free）
	## MVP-δ 阶段 2：从原 WorldMap 引用改为 NightVisionLayer
	var owner_layer: NightVisionLayer = null

	func _draw() -> void:
		if owner_layer == null:
			return
		var signals: Array = owner_layer.collect_fog_signals()
		for s_v in signals:
			var s: Dictionary = s_v as Dictionary
			var center: Vector2 = s.get("center", Vector2.ZERO) as Vector2
			var half: float = s.get("half", 8.0) as float
			var color: Color = s.get("color", Color.RED) as Color
			# 屏幕空间小菱形：四顶点取 (center ± half) 的上下左右
			var pts: PackedVector2Array = PackedVector2Array([
				Vector2(center.x, center.y - half),
				Vector2(center.x + half, center.y),
				Vector2(center.x, center.y + half),
				Vector2(center.x - half, center.y),
			])
			draw_colored_polygon(pts, color)


# ─────────────────────────────────────────
# 内部状态
# ─────────────────────────────────────────

## 夜晚遮罩 CanvasLayer 容器（layer=5）+ 全屏 ColorRect（持 night_overlay ShaderMaterial）
var _night_overlay_layer: CanvasLayer = null
var _night_overlay_rect: ColorRect = null
## 当前 shader 的 phase_alpha 因子（0=白天 / 1=夜晚 / 中间值 = Tween 进行中）
var _phase_alpha: float = 0.0
## 昼夜 fade Tween 引用（任意时刻只允许一个 Tween）
var _phase_alpha_tween: Tween = null
## 战斗中强制白天遮罩（force-day）
## true 期间所有 phase_changed 仅更新 _pending_post_battle_phase，不动 Tween
var _battle_force_day: bool = false
## 战斗中收到的最后 phase 切换（DAY=0 / NIGHT=1）；战斗结束时按此 fade 回去
var _pending_post_battle_phase: int = 0

## 浓雾外敌人信号浮层（CanvasLayer=6）+ 内含 Node2D 画屏幕空间菱形
var _fog_signal_layer: CanvasLayer = null
var _fog_signal_node: FogSignalNode = null

# ─────────────────────────────────────────
# 注入依赖（setup 时传入；NightVisionLayer 不持有 WorldMap 引用，所有访问经 WorldView）
# ─────────────────────────────────────────

var _turn_manager: TurnManager = null
var _camera: Camera2D = null
var _world_view: WorldView = null
var _tile_size: int = 0
## 浓雾外信号菱形颜色（WorldMap 渲染常量经 setup 注入；避免 NightVisionLayer 持有 WorldMap 颜色常量副本）
var _enemy_slot_color: Color = Color.RED
var _enemy_move_color: Color = Color.RED


# ─────────────────────────────────────────
# 公开接口
# ─────────────────────────────────────────

## 初始化（WorldMap._init_subsystems 调一次）
##
## 流程：
##   1. _setup_night_overlay —— 挂 CanvasLayer=5 + ColorRect ShaderMaterial
##   2. _setup_fog_signal_layer —— 挂 CanvasLayer=6 + FogSignalNode（必须在 1 之后）
##
## phase_changed sink 注册不在本节点内进行：DayNightState 是单 sink 模型（后 register 覆盖前者），
## NightVisionLayer 与 WorldMap 不能各注册一个；改由 WorldMap 注册组合 sink 派发，本节点暴露
## on_phase_changed 公开方法供 WorldMap 内部调用（同时驱动 Renderer redraw）。
func setup(turn_manager: TurnManager, camera: Camera2D, world_view: WorldView,
		tile_size: int, enemy_slot_color: Color, enemy_move_color: Color) -> void:
	_turn_manager = turn_manager
	_camera = camera
	_world_view = world_view
	_tile_size = tile_size
	_enemy_slot_color = enemy_slot_color
	_enemy_move_color = enemy_move_color
	_setup_night_overlay()
	_setup_fog_signal_layer()


## 浓雾像素判定（WorldMap / WorldView.is_in_fog 转发；WorldMapRenderer 经 WorldView 间接调）
##
## 仅当夜晚 + 非 force-day 时返回有意义结果（其他情况返回 false，调用方应短路判断）
## 距离 > 视野半径 + 过渡带 → 完全在浓雾外（GDScript 端等价于 shader smoothstep 衰减完成处）
##
## codex P1-1 修复：与 shader 光源对齐，移动中用 unit_visual_pos；保证视觉与判定同步
func is_in_fog(world_pos: Vector2) -> bool:
	if _world_view == null:
		return false
	var unit: UnitData = _world_view.get_unit()
	if unit == null:
		return false
	var light_center: Vector2 = _player_light_world_center()
	var threshold_px: float = (CFG.vision_radius_grids + CFG.fog_falloff_grids) * float(_tile_size)
	return world_pos.distance_to(light_center) > threshold_px


## 当前是否处于战斗强制白天态（WorldView.is_battle_force_day 转发）
func is_battle_force_day() -> bool:
	return _battle_force_day


## 浓雾外敌方信号数据（FogSignalNode._draw 回调）
##
## 返回需要画的浓雾外敌方信号列表，每项 = { center: Vector2(屏幕坐标), half: float, color: Color }
##
## 跑测修复（2026-05-11 第 2 轮）：守卫从 is_night 改为 _phase_alpha > 0.001
##   并把信号 alpha 乘以 _phase_alpha，让 fade 过程中浮层信号与背景遮罩同步渐隐
##   force-day 期间 _phase_alpha 在 Tween 中 fade 到 0，自然不画 → 与战斗白天语义一致
func collect_fog_signals() -> Array:
	var out: Array = []
	if _battle_force_day:
		return out
	if _phase_alpha < 0.001:
		return out
	if _world_view == null:
		return out
	var level_slots: Dictionary = _world_view.get_level_slots()
	if level_slots == null or level_slots.is_empty():
		return out
	if _camera == null:
		return out
	# 信号菱形屏幕像素半径 = TILE_SIZE × camera.zoom.x × 缩放比例
	# 战斗 zoom 时（zoom < 1）信号会更小，但战斗中 force-day 已 return，此分支主要服务探索态
	var screen_half: float = float(_tile_size) * 0.5 * _camera.zoom.x * CFG.fog_signal_diamond_scale

	# 静态敌方关卡
	var enemy_movement: EnemyMovement = _world_view.get_enemy_movement()
	var moving_level: LevelSlot = enemy_movement.get_moving_level() if enemy_movement != null else null
	for pos_v in level_slots:
		var pos: Vector2i = pos_v as Vector2i
		var level: LevelSlot = level_slots[pos] as LevelSlot
		if level == null:
			continue
		# 击败态敌方不再是"威胁信号"，浓雾中不画（与世界层视野内一致）
		if level.is_defeated():
			continue
		# 移动中关卡由下方独立分支处理（避免 visual_pos 与 grid 位置不一致时重复画）
		if level == moving_level:
			continue
		# 战斗中参战 LevelSlot 跳过（视野内由 BattleUnit 独占；浓雾外不画信号避免重复）
		if _world_view.is_pack_in_battle(pos):
			continue
		var world_center: Vector2 = _world_view.grid_to_pixel_center(pos)
		if not is_in_fog(world_center):
			continue
		var seed: int = level.get_instance_id()
		var blink_a: float = _compute_blink_alpha(seed) * _phase_alpha
		var screen_center: Vector2 = _world_to_screen(world_center)
		out.append({
			"center": screen_center,
			"half": screen_half,
			"color": Color(_enemy_slot_color.r, _enemy_slot_color.g, _enemy_slot_color.b, blink_a),
		})

	# 移动中敌方关卡（codex P1 修复：用 LevelSlot.get_instance_id 作 seed，移动中相位稳定）
	if moving_level != null and enemy_movement != null:
		var enemy_vis_pos: Vector2 = enemy_movement.get_visual_pos()
		if is_in_fog(enemy_vis_pos):
			var seed: int = moving_level.get_instance_id()
			var blink_a: float = _compute_blink_alpha(seed) * _phase_alpha
			var screen_center: Vector2 = _world_to_screen(enemy_vis_pos)
			out.append({
				"center": screen_center,
				"half": screen_half,
				"color": Color(_enemy_move_color.r, _enemy_move_color.g, _enemy_move_color.b, blink_a),
			})

	return out


## 战斗触发：force-day 启动（WorldMap._start_battle_camera 调）
##
## 记录战斗开始前的目标 phase（用于战斗结束时回到原状态）；fade 出夜晚遮罩到 alpha=0
## 0.3s 与 zoom Tween 同步完成；force=true 表示无视 _battle_force_day 限制（本路径就是要设它）
## 跑测修复（2026-05-11 第 2 轮）：force-day 启动时强制清浮层信号
##   与 phase_changed 边沿触发同理——避免战斗触发瞬间浮层菱形残留
func set_battle_force_day_on() -> void:
	_pending_post_battle_phase = int(DayNightState.current(_turn_manager))
	_battle_force_day = true
	_fade_phase_alpha(0.0, CFG.battle_force_day_duration, true)
	if _fog_signal_node != null:
		_fog_signal_node.queue_redraw()


## 战斗结束：force-day 解除 + fade 回正确 phase（WorldMap._end_battle_camera 调）
##
## codex P1-4 修复：在 _end_battle_camera 顶部调用，先于所有 early return；保证 force-day 总能被解除
## 即使 _battle_zoom_active=false 或 _camera==null 也走完整的"解除 + fade 回正确 phase"逻辑
## 跑测修复（2026-05-11 第 2 轮）：force-day 解除时强制刷浮层
##   退战回到夜晚时让浮层重新渲染信号；退战回到白天时让浮层清空
func resync_to_post_battle_state() -> void:
	if not _battle_force_day:
		return
	_battle_force_day = false
	var resync_target: float = 1.0 if _pending_post_battle_phase == int(DayNightState.Phase.NIGHT) else 0.0
	_fade_phase_alpha(resync_target, CFG.fade_duration, true)
	if _fog_signal_node != null:
		_fog_signal_node.queue_redraw()


## 场景退出清理（WorldMap._exit_tree 调）
##
## DayNightState 是静态 autoload，phase_changed_sink 不清会导致 reload_current_scene 后旧 Callable 触发
## _phase_alpha_tween 不杀会让 Tween 在场景退出后继续 set_shader_parameter 触发野指针
func clear() -> void:
	DayNightState.clear_sinks()
	if _phase_alpha_tween != null and _phase_alpha_tween.is_valid():
		_phase_alpha_tween.kill()
	_phase_alpha_tween = null


# ─────────────────────────────────────────
# _process 帧驱动（shader uniform 更新 + 闪烁敌人 redraw）
# ─────────────────────────────────────────

## 每帧驱动 shader uniform + 闪烁敌人 redraw
##
## 性能守卫：
##   - shader uniform 更新仅在 _phase_alpha > 0.001（fade 中或夜晚）时执行，白天空转跳过
##   - queue_redraw 仅在 is_night + 非 force-day + 视野外有敌方 slot 时触发
func _process(_delta: float) -> void:
	if _night_overlay_rect == null:
		return
	# 守卫：白天且非 fade 中 → 全跳过（_phase_alpha 已是 0，shader 输出 alpha=0）
	if _phase_alpha < 0.001 and not _is_phase_alpha_tween_active():
		return
	_update_night_shader_uniforms()
	# 闪烁敌人需要每帧 redraw 驱动 sin 动画
	if _need_blinking_redraw():
		if _fog_signal_node != null:
			_fog_signal_node.queue_redraw()


# ─────────────────────────────────────────
# 内部实装
# ─────────────────────────────────────────

## 挂载夜晚遮罩 CanvasLayer
##
## 层级关系：世界 layer=0 → night_overlay layer=5 → UILayer layer=10
## ColorRect 默认 mouse_filter = MOUSE_FILTER_STOP 会吞下输入 → 改为 IGNORE
##
## ShaderMaterial 资源通过 const preload，编辑期校验路径；
## duplicate() 是为了让每个 NightVisionLayer 实例独立持有 shader 参数副本，
## 避免跨场景 reload 时 set_shader_parameter 影响到旧场景
func _setup_night_overlay() -> void:
	_night_overlay_layer = CanvasLayer.new()
	_night_overlay_layer.name = "NightOverlayLayer"
	_night_overlay_layer.layer = CFG.overlay_canvas_layer
	add_child(_night_overlay_layer)

	_night_overlay_rect = ColorRect.new()
	_night_overlay_rect.name = "NightOverlayRect"
	# 用基础颜色 + shader；shader 输出 alpha 接管最终可见度，ColorRect 本身的颜色不影响最终结果
	_night_overlay_rect.color = Color(1.0, 1.0, 1.0, 1.0)
	_night_overlay_rect.material = NIGHT_OVERLAY_MATERIAL.duplicate() as ShaderMaterial
	_night_overlay_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_night_overlay_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_night_overlay_layer.add_child(_night_overlay_rect)

	# 初始全部清零：白天 phase_alpha=0 → shader 输出 alpha=0，遮罩完全透明
	_apply_phase_alpha_to_shader()


## 挂载浓雾外敌人信号浮层（CanvasLayer=6）
##
## 与 _setup_night_overlay 配对，必须在其之后挂——layer=6 > layer=5 → 信号画在遮罩之上
## 信号 Node2D 持有 owner_layer 引用（指向本 NightVisionLayer），_draw 时回调 collect_fog_signals 拿数据
func _setup_fog_signal_layer() -> void:
	_fog_signal_layer = CanvasLayer.new()
	_fog_signal_layer.name = "FogSignalLayer"
	_fog_signal_layer.layer = CFG.fog_signal_canvas_layer
	add_child(_fog_signal_layer)

	_fog_signal_node = FogSignalNode.new()
	_fog_signal_node.name = "FogSignalNode"
	_fog_signal_node.owner_layer = self
	_fog_signal_layer.add_child(_fog_signal_node)


## 每帧把玩家队伍像素位置 + 视野半径转 UV 空间，喂给 shader
##
## 2026-05-11 跑测修复：从"viewport pixel + vec4 数组"切换到"UV 空间 + 单光源"
## 详见原 WorldMap._update_night_shader_uniforms 注释
##
## codex P2-6 修复：_unit == null 时把 phase_alpha 归零，避免启动早期 1 帧整屏全黑
func _update_night_shader_uniforms() -> void:
	var mat: ShaderMaterial = _night_overlay_rect.material as ShaderMaterial
	if mat == null:
		return
	# _unit == null 守卫：临时把 phase_alpha 归零（光源缺失 = 看不到，不如让玩家有"白天感"）
	var unit: UnitData = _world_view.get_unit() if _world_view != null else null
	if unit == null:
		mat.set_shader_parameter("phase_alpha", 0.0)
		return
	if _camera == null:
		return
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	if vp_size.x <= 0.0 or vp_size.y <= 0.0:
		return

	# 光源在世界空间的坐标（移动中用 unit_visual_pos，静止用格中心）
	var light_world: Vector2 = _player_light_world_center()

	# world → viewport pixel → UV
	# canvas_transform 已自动包含 Camera2D position / zoom / rotation / offset 全部变换
	var canvas_t: Transform2D = _camera.get_canvas_transform()
	var light_vp: Vector2 = canvas_t * light_world
	var light_uv: Vector2 = light_vp / vp_size

	# 半径锚点 = 光源右侧 CFG.vision_radius_grids 格的世界位置
	# 经过同一 canvas_transform 后，距离 = 半径在 viewport pixel 空间的值
	var radius_anchor_world: Vector2 = light_world + Vector2(CFG.vision_radius_grids * float(_tile_size), 0.0)
	var radius_anchor_vp: Vector2 = canvas_t * radius_anchor_world
	var radius_vp_px: float = light_vp.distance_to(radius_anchor_vp)
	# 用 viewport 高度归一化：与 shader 内 d.x *= aspect_xy 的基准（Y = 高度）对齐
	var radius_uv: float = radius_vp_px / vp_size.y

	var falloff_anchor_world: Vector2 = light_world + Vector2(CFG.fog_falloff_grids * float(_tile_size), 0.0)
	var falloff_anchor_vp: Vector2 = canvas_t * falloff_anchor_world
	var falloff_vp_px: float = light_vp.distance_to(falloff_anchor_vp)
	var falloff_uv: float = falloff_vp_px / vp_size.y

	# 宽高比：让 shader 内距离 X 方向按 aspect 拉伸，圆始终是正圆而非椭圆
	var aspect_xy: float = vp_size.x / vp_size.y

	mat.set_shader_parameter("light_uv", light_uv)
	mat.set_shader_parameter("light_radius_uv", radius_uv)
	mat.set_shader_parameter("fog_falloff_uv", falloff_uv)
	mat.set_shader_parameter("aspect_xy", aspect_xy)
	mat.set_shader_parameter("phase_alpha", _phase_alpha)


## 玩家队伍火把光源世界坐标（格中心像素）
##
## codex P1-1 修复：移动中读 _unit_visual_pos（Tween 动画位置），静止时读 _unit.position 的格中心
## 防御：_unit == null 时返回 _unit_visual_pos（启动时默认 _start_pos 像素）
func _player_light_world_center() -> Vector2:
	if _world_view == null:
		return Vector2.ZERO
	var unit: UnitData = _world_view.get_unit()
	var unit_visual_pos: Vector2 = _world_view.get_unit_visual_pos()
	if unit == null:
		return unit_visual_pos
	if _world_view.is_player_moving():
		return unit_visual_pos
	return _world_view.grid_to_pixel_center(unit.position)


## 把世界坐标转屏幕像素坐标
## 用 _camera.get_canvas_transform()：返回的是 Canvas → Viewport 的变换
## 屏幕像素 = canvas_transform * world_pos
func _world_to_screen(world_pos: Vector2) -> Vector2:
	if _camera == null:
		return world_pos
	return _camera.get_canvas_transform() * world_pos


## 把 _phase_alpha 当前值写入 shader uniform
## 由 Tween tween_method 每帧调用 + _setup_night_overlay 初始化时调用
func _apply_phase_alpha_to_shader() -> void:
	if _night_overlay_rect == null:
		return
	var mat: ShaderMaterial = _night_overlay_rect.material as ShaderMaterial
	if mat == null:
		return
	mat.set_shader_parameter("phase_alpha", _phase_alpha)


## 启动 _phase_alpha fade Tween
##
## 参数：
##   target：目标 alpha 值（0.0 = 白天 / 1.0 = 夜晚）
##   duration：Tween 时长（秒）
##   force：是否强制启动（force-day fade in/out 用 true 跳过守卫）
##
## 同值守卫：当前 alpha 与目标差 < 0.001 时跳过（避免重复 Tween）；force=true 时不守卫
##
## BUG 修复（2026-05-13）：先 kill 旧 tween，再判断 early return；否则 in-flight tween
## 会绕过守卫继续跑。复现场景见原 WorldMap._fade_phase_alpha 注释。
func _fade_phase_alpha(target: float, duration: float, force: bool) -> void:
	# 先 kill 旧 tween：避免 in-flight tween 绕过守卫继续把 _phase_alpha 推向旧 target
	if _phase_alpha_tween != null and _phase_alpha_tween.is_valid():
		_phase_alpha_tween.kill()
	# 同值守卫（kill 之后判断）：当前 alpha 已经 == target 且 force=false → 不创建新 tween
	if not force and absf(_phase_alpha - target) < 0.001:
		return
	_phase_alpha_tween = create_tween()
	_phase_alpha_tween.tween_method(_set_phase_alpha_value, _phase_alpha, target, duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## Tween tween_method 回调：写入 _phase_alpha 并同步刷 shader
func _set_phase_alpha_value(value: float) -> void:
	_phase_alpha = value
	_apply_phase_alpha_to_shader()


## 判断 _phase_alpha Tween 是否还在进行中
## 用于 _process 的守卫：fade 中需要持续更新 shader uniform（光源位置可能变化）
func _is_phase_alpha_tween_active() -> bool:
	return _phase_alpha_tween != null and _phase_alpha_tween.is_valid() and _phase_alpha_tween.is_running()


## 闪烁敌人 alpha 计算
##
## 公式：alpha = blink_base_alpha + blink_amp * (sin(2π * t / blink_period + phase) * 0.5 + 0.5)
##   - t：当前时间（秒）
##   - phase：按 seed 哈希出的相位偏移，避免所有敌人同步闪烁
##   - 输出范围：[blink_base_alpha, blink_base_alpha + blink_amp]
##
## seed 通常用 LevelSlot 的 unique_id（int）或 instance_id；调用方保证 seed 稳定
func _compute_blink_alpha(seed: int) -> float:
	var t: float = float(Time.get_ticks_msec()) / 1000.0
	var phase_offset: float = float(hash(seed) % 1000) / 1000.0 * TAU
	var sine: float = sin(t * TAU / CFG.blink_period + phase_offset)
	return CFG.blink_base_alpha + CFG.blink_amp * (sine * 0.5 + 0.5)


## 判断当前帧是否需要 redraw 驱动闪烁动画
##
## 仅当 phase_alpha > 0（夜晚或 fade 中）+ 非战斗强制白天 + 视野外有敌方关卡时返回 true
##
## 跑测修复（2026-05-11 第 2 轮）：判断条件从 is_night 改为 _phase_alpha > 0.001
##   原 is_night 在 phase 切换瞬间立即 false，导致 fade 过程中浮层信号 / 闪烁敌人
##   突然消失而不是跟随 0.6s fade 渐隐。改用 phase_alpha 守卫让浮层与背景 shader 同步
func _need_blinking_redraw() -> bool:
	if _phase_alpha < 0.001 and not _is_phase_alpha_tween_active():
		return false
	if _battle_force_day:
		return false
	if _world_view == null:
		return false
	var level_slots: Dictionary = _world_view.get_level_slots()
	if level_slots == null or level_slots.is_empty():
		return false
	# 仅扫一遍 level_slots 找视野外的敌方关卡；视野内的不需要闪烁
	for pos_v in level_slots:
		var pos: Vector2i = pos_v as Vector2i
		var world_pos: Vector2 = _world_view.grid_to_pixel_center(pos)
		if is_in_fog(world_pos):
			return true
	return false


## DayNightState phase_changed 派发入口（由 WorldMap._on_day_night_phase_changed 组合 sink 调用）
##
## 双重职责：
##   1. 浮层 redraw —— phase 边沿触发清菱形信号（跑测修复 2026-05-11 第 2 轮：切到白天后
##      上一帧画的菱形会"卡"在 CanvasLayer 缓冲里不消失，强制 redraw 让浮层跟随 phase_alpha 渐隐）
##   2. _fade_phase_alpha —— 启动夜晚遮罩 fade 0↔1
##
## 战斗中（_battle_force_day = true）：
##   仅记录 _pending_post_battle_phase，不动 Tween（战斗内强制白天，phase 切换不影响遮罩）
##   战斗结束时 WorldMap._end_battle_camera → resync_to_post_battle_state 会 fade 回正确状态
func on_phase_changed(phase: int) -> void:
	if _fog_signal_node != null:
		_fog_signal_node.queue_redraw()
	# 战斗中只记录目标 phase，不动 Tween（force-day 优先级最高）
	if _battle_force_day:
		_pending_post_battle_phase = phase
		return
	# 正常昼夜切换：NIGHT → 遮罩 fade in 到 1.0；DAY → fade out 到 0.0
	var target: float = 1.0 if phase == int(DayNightState.Phase.NIGHT) else 0.0
	_fade_phase_alpha(target, CFG.fade_duration, false)
