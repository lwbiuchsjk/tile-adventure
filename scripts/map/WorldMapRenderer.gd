class_name WorldMapRenderer
extends Node2D
## 大地图渲染层（MVP-γ 阶段 2）
##
## 设计原文：
##   tile-advanture-design/代码健康度回看/MVP-γ_拆分批1.md §核心概念 / §接口设计
##   tile-advanture-design/代码健康度回看/01_结构维度报告.md §2.2 方案 A
##
## 职责：
##   承接原 WorldMap 的全部 _draw 渲染逻辑（_draw 主入口 + 24 个 _draw_* 函数）。
##   作为 WorldMap 的子 Node2D，在同一坐标空间内绘制；WorldMap 自身不再承载 _draw，
##   改为在状态变化时调用 _renderer.queue_redraw()。
##
## 设计要点：
##   - 探索态经 WorldView 读取、战斗态经 BattleViewState 读取，两者由 WorldMap
##     在 _ready 时经 setup() 注入。
##   - _draw 入口一次性把 WorldView 的热路径字段缓存进 typed 成员（_schema 等），
##     _draw_* helper 继续读成员字段 —— 函数签名零改动，_draw_tile 等热路径不走
##     WorldView 动态访问。
##   - 渲染层对世界态零写操作（已逐函数核实）。
##   - 调参 const 全部走独立 Resource preload（MVP-B 阶段 3+4 / MVP-B.2 全 4 阶段迁出），
##     仅 TILE_SIZE 保留 `const X := WorldMap.X` 桥接（基线锚点不可调参）。

# ─────────────────────────────────────────
# 调参 Resource preload + 仅存的 TILE_SIZE 桥接
# ─────────────────────────────────────────
## MVP-B 阶段 4 / MVP-B.2 全 4 阶段：Resource 调参 preload（独立访问，不走 WorldMap const 桥接中转）
const VISUAL_CFG: BattleVisualConfig = preload("res://assets/config/battle_visual_config.tres")
const MAP_BASE_CFG: MapBaseConfig = preload("res://assets/config/map_base_config.tres")
const UNIT_ENEMY_CFG: UnitEnemyConfig = preload("res://assets/config/unit_enemy_config.tres")
const RESOURCE_RENDER_CFG: ResourceRenderConfig = preload("res://assets/config/resource_render_config.tres")
const INFLUENCE_CFG: InfluenceConfig = preload("res://assets/config/influence_config.tres")
## 仅保留 TILE_SIZE 桥接（不迁，全项目尺寸锚点；MVP-B.2 设计 Q4 拍板）
const TILE_SIZE := WorldMap.TILE_SIZE

# ─────────────────────────────────────────
# 注入引用（WorldMap._init_subsystems 经 setup 注入）
# ─────────────────────────────────────────

## 世界视图 facade（探索态只读入口）
var _world_view: WorldView = null

## 战斗瞬时视觉态载体（战斗动画 3 字典，BattleAnimDirector 写、本层读）
var _battle_view: BattleViewState = null

# ─────────────────────────────────────────
# WorldView 探索态缓存（_draw 入口每帧刷新；_draw_* 直接读成员，避免热路径动态访问）
# ─────────────────────────────────────────
var _schema: MapSchema = null
var _label_font: Font = null
var _reachable_tiles: Dictionary = {}
var _level_slots: Dictionary = {}
var _resource_slots: Dictionary = {}
var _battle_trigger_range: int = 0
var _unit_visual_pos: Vector2 = Vector2.ZERO
var _unit: UnitData = null
var _enemy_movement: EnemyMovement = null
var _turn_manager: TurnManager = null
var _battle_force_day: bool = false
var _current_cycle_has_enemy_core: bool = false
var _battle_zoom_active: bool = false
var _battle_arena_range: int = 0
var _battle_center_grid: Vector2i = Vector2i.ZERO
var _battle_session: BattleSession = null

## 改动2（视觉与操作改进 §2.2）：地格四角呼吸角标相位（_process 推进，正弦驱动内外收缩）
var _select_bracket_phase: float = 0.0


## 注入世界视图 + 战斗视图（WorldMap._init_subsystems 调用一次，跨战斗复用）
func setup(world_view: WorldView, battle_view: BattleViewState) -> void:
	_world_view = world_view
	_battle_view = battle_view


## 改动2（视觉与操作改进 §2.2）：呼吸角标相位驱动
## 仅在"应显示角标"窗口（玩家回合 + 战斗未结束 + 当前 actor 静止）推进相位并重绘，
## 避免无谓全局重绘；其它时段不动相位、不请求重绘（静止时的呼吸由本函数独占驱动）
func _process(delta: float) -> void:
	if _battle_session == null or _battle_session.is_ended() or not _battle_session.is_player_turn():
		return
	var actor: BattleUnit = _battle_session.current_actor()
	if actor == null or not actor.is_active or not actor.is_alive():
		return
	if _battle_view != null and _battle_view.unit_visual_offsets.has(actor):
		return  # 单位动画中 → 角标隐藏，不驱动呼吸
	_select_bracket_phase += delta * VISUAL_CFG.select_bracket_speed
	if _select_bracket_phase > TAU:
		_select_bracket_phase -= TAU
	queue_redraw()


## Godot 生命周期：主 _draw 入口，从 WorldView 缓存热路径成员后调度 _draw_* 子区块
func _draw() -> void:
	if _world_view == null:
		return
	# 从 WorldView 一次性缓存探索态热路径成员：_draw_tile 等每帧 N² 次读 _schema，
	# 走 WorldView 动态访问有可测开销，入口缓存后 _draw_* 直接读 typed 成员
	_schema = _world_view.get_schema()
	_label_font = _world_view.get_label_font()
	_reachable_tiles = _world_view.get_reachable_tiles()
	_level_slots = _world_view.get_level_slots()
	_resource_slots = _world_view.get_resource_slots()
	_battle_trigger_range = _world_view.get_battle_trigger_range()
	_unit_visual_pos = _world_view.get_unit_visual_pos()
	_unit = _world_view.get_unit()
	_enemy_movement = _world_view.get_enemy_movement()
	_turn_manager = _world_view.get_turn_manager()
	_battle_force_day = _world_view.is_battle_force_day()
	_current_cycle_has_enemy_core = _world_view.is_current_cycle_has_enemy_core()
	_battle_zoom_active = _world_view.is_battle_zoom_active()
	_battle_arena_range = _world_view.get_battle_arena_range()
	_battle_center_grid = _world_view.get_battle_center_grid()
	_battle_session = _world_view.get_battle_session()

	if _schema == null:
		return

	# 第一层：地形底色 + Slot 标记
	for y in range(_schema.height):
		for x in range(_schema.width):
			_draw_tile(x, y)

	# 第 1.6 层：资源点标记 + 文字
	_draw_resource_slots()

	# 第 1.7 层：持久 slot 影响范围覆盖层（M4；半透明势力色）
	_draw_persistent_influence_ranges()

	# 第 1.75 层：敌方威胁圈（入口 1.1；半透明红色叠层，曼哈顿圆 ≤ _battle_trigger_range）
	# 设计依据：tile-advanture-design/战斗信息传达_探索阶段_MVP.md §5 改动 1
	# 渲染顺序在持久 slot 影响范围之后、持久 slot 本体之前，确保后续玩家移动范围
	# （MAP_BASE_CFG.reachable_color 白 alpha 0.18）压在威胁圈（红 alpha 0.20）之上时自然叠加为粉色，
	# 保留"既能去又危险"的可识别性
	_draw_enemy_threat_zones()

	# 第 1.8 层：持久 slot 本体标记（M4；外框色块 + 核心城镇金边 + 类型等级文字）
	_draw_persistent_slots()

	# 第 1.85 层：敌方关卡（入口 4 MVP 2026-05-09 抽出）
	# 必须在持久 slot 影响范围 / 本体之后画 —— 否则菱形被半透明红色影响范围吞没
	_draw_level_slots()

	# 第二层：可达范围高亮
	# UI 重构步骤 7：可达范围双通道渲染
	#   - 整格铺 MAP_BASE_CFG.reachable_color（alpha 0.08，轻量背景提示）
	#   - 外边界描边（只画邻居不在集合内的那条边），蓝白冷调
	# 视觉效果：弱铺色提供"整体可达感"，描边提供"清晰边界"
	for tile_pos in _reachable_tiles:
		var pos: Vector2i = tile_pos as Vector2i
		if _unit != null and pos == _unit.position:
			continue  ## 当前位置不叠加高亮
		var rect: Rect2 = Rect2(
			pos.x * TILE_SIZE,
			pos.y * TILE_SIZE,
			TILE_SIZE - 1,
			TILE_SIZE - 1
		)
		draw_rect(rect, MAP_BASE_CFG.reachable_color)

		# 边界描边：4 邻居中不在集合内的方向画一条边
		var px: float = float(pos.x * TILE_SIZE)
		var py: float = float(pos.y * TILE_SIZE)
		var pw: float = float(TILE_SIZE)
		# 上邻
		if not _reachable_tiles.has(Vector2i(pos.x, pos.y - 1)):
			draw_line(Vector2(px, py), Vector2(px + pw, py),
				MAP_BASE_CFG.reachable_border_color, MAP_BASE_CFG.reachable_border_width)
		# 下邻
		if not _reachable_tiles.has(Vector2i(pos.x, pos.y + 1)):
			draw_line(Vector2(px, py + pw), Vector2(px + pw, py + pw),
				MAP_BASE_CFG.reachable_border_color, MAP_BASE_CFG.reachable_border_width)
		# 左邻
		if not _reachable_tiles.has(Vector2i(pos.x - 1, pos.y)):
			draw_line(Vector2(px, py), Vector2(px, py + pw),
				MAP_BASE_CFG.reachable_border_color, MAP_BASE_CFG.reachable_border_width)
		# 右邻
		if not _reachable_tiles.has(Vector2i(pos.x + 1, pos.y)):
			draw_line(Vector2(px + pw, py), Vector2(px + pw, py + pw),
				MAP_BASE_CFG.reachable_border_color, MAP_BASE_CFG.reachable_border_width)

	# 第三层：敌方关卡移动动画标记
	if _enemy_movement.get_moving_level() != null:
		_draw_enemy_move_marker()

	# 第四层：单位标记（基于视觉位置）
	# E MVP：战斗态由 _draw_battle_overlay 渲染战场上的队长（按 battle_position），
	# 跳过探索态单位 marker，避免与战场队长重叠
	# 门控用 `_battle_session == null`（对象不存在）而非 `is_in_battle()`（!is_ended()）——
	# 让 COMA 的 await 致命一击动画期间（session 已 ended 但还没置 null）仍走战场渲染
	if _unit != null and _battle_session == null:
		_draw_unit_marker()

	# 第五层：夜晚效果（已上移至 night_overlay CanvasLayer=5，本 _draw 不再处理）
	# 入口 4 后段第 1 份（夜晚视野 MVP，2026-05-11）：原 D MVP 深蓝半透 draw_rect 占位删除；
	# 替换为屏幕空间 shader（assets/shader/night_overlay.gdshader）+ 玩家光源 + 浓雾近黑
	# 实装位置：_setup_night_overlay / _process / _on_day_night_phase_changed / _fade_phase_alpha

	# 第 5.5 层：入口 4 MVP（2026-05-09 追加）战场外压暗 overlay
	# 战斗态时画半透明黑覆盖战场之外；战场内不画 → 视觉聚焦战场
	# 顺序：夜晚滤镜之后（让战场外 = 夜晚 + 压暗双层；战场内 = 仅夜晚保留昼夜感）
	#       战场 overlay 之前（战斗单位 / 高亮 / HP 条画在压暗之上）
	_draw_battle_dim_overlay()

	# 第六层：E MVP 战场叠加（战斗态时渲染战场边框 / 单位 / 移动+攻击高亮 / HP 条）
	# 渲染顺序在夜晚滤镜之后：让战场单位 / 高亮不被夜晚色调遮罩，保证战斗操作的可见性
	# 门控用 `_battle_session != null`：COMA await 致命一击动画期间 session 已 ended 但
	# 还没置 null，仍需画战场单位 / 攻击动画偏移 / HP 补间（设计 §致命一击）
	if _battle_session != null:
		_draw_battle_overlay()

## 绘制单格地形色块及 Slot 标记
func _draw_tile(x: int, y: int) -> void:
	var terrain: MapSchema.TerrainType = _schema.get_terrain(x, y)
	var base_color: Color = MAP_BASE_CFG.terrain_colors.get(terrain, Color.MAGENTA) as Color

	# UI 重构步骤 9：基于 (x, y) 哈希给地形加轻量亮度噪声 ±5%
	# 同 seed 结果一致（不闪烁），只为打破整齐色块的"表格感"
	var noise: float = _terrain_brightness_noise(x, y)
	base_color = Color(
		clampf(base_color.r + noise, 0.0, 1.0),
		clampf(base_color.g + noise, 0.0, 1.0),
		clampf(base_color.b + noise, 0.0, 1.0),
		base_color.a
	)

	# 绘制地形底色（留 1px 间隙形成网格线视觉效果）
	var tile_rect: Rect2 = Rect2(
		x * TILE_SIZE,
		y * TILE_SIZE,
		TILE_SIZE - 1,
		TILE_SIZE - 1
	)
	draw_rect(tile_rect, base_color)

	# 若有非敌方关卡 Slot，在格中央叠加色块标记（兜底矩形渲染）
	# 入口 4 MVP（2026-05-09）：敌方关卡（LevelSlot）渲染抽出到独立的 _draw_level_slots()
	# 原因：原渲染层级低于持久 slot 影响范围（半透明红色块），同色叠加导致菱形被吞
	# 新顺序：地形 → 兜底 slot → 影响范围 → 威胁圈 → 持久 slot 本体 → **敌方关卡** → 可达 → ...
	var slot: MapSchema.SlotType = _schema.get_slot(x, y)
	if slot != MapSchema.SlotType.NONE:
		var pos: Vector2i = Vector2i(x, y)
		# 敌方关卡格本格在此层不画（由 _draw_level_slots 在更高层处理）
		if _world_view.get_level_at(pos) != null:
			return
		var slot_color: Color = MAP_BASE_CFG.slot_colors.get(slot, Color.WHITE) as Color
		var slot_rect: Rect2 = Rect2(
			x * TILE_SIZE + MAP_BASE_CFG.slot_margin,
			y * TILE_SIZE + MAP_BASE_CFG.slot_margin,
			TILE_SIZE - MAP_BASE_CFG.slot_margin * 2 - 1,
			TILE_SIZE - MAP_BASE_CFG.slot_margin * 2 - 1
		)
		draw_rect(slot_rect, slot_color)


## 入口 4 MVP（2026-05-09）：敌方关卡渲染独立层
## 抽出原因：原 _draw_tile 内画法处于第一层（最低），被持久 slot 影响范围（半透明红色块）+
##           持久 slot 本体（不透明）从上方覆盖。同色 / 强色叠加导致菱形被视觉吞没
## 新位置：_draw() 内置于第 1.85 层 —— 持久 slot 本体之后、可达范围 / 单位 marker 之前
## 守卫与原 _draw_tile 一致：跳过移动中关卡（_draw_enemy_move_marker 负责）+ 跳过参战关卡（BattleUnit 独占）
func _draw_level_slots() -> void:
	if _schema == null:
		return
	for pos_v in _level_slots:
		var pos: Vector2i = pos_v as Vector2i
		var level: LevelSlot = _level_slots[pos] as LevelSlot
		if level == null:
			continue
		# 正在移动的关卡跳过静态渲染（由 _draw_enemy_move_marker 负责）
		if level == _enemy_movement.get_moving_level():
			continue
		# 战斗态：参战 LevelSlot 跳过（BattleUnit 圆形独占视觉，避免红菱形+红圆形分身感）
		if _world_view.is_pack_in_battle(pos):
			continue

		var is_defeated: bool = level.is_defeated()

		# 入口 4 后段第 1 份（夜晚视野 MVP，codex P0 修复 2026-05-11）：
		# 浓雾外敌方关卡在世界层完全跳过渲染——夜晚遮罩 CanvasLayer=5 会盖在世界层之上，
		# 即使这里画了闪烁敌人也会被纯黑遮罩完全遮掉。浓雾外的敌人信号改由
		# _fog_signal_node（CanvasLayer=6 浮层）画屏幕空间闪烁信号
		var center_world: Vector2 = _world_view.grid_to_pixel_center(pos)
		if DayNightState.is_night(_turn_manager) and (not _battle_force_day) and _world_view.is_in_fog(center_world):
			continue

		var slot_color: Color = UNIT_ENEMY_CFG.enemy_slot_color
		if is_defeated:
			# 已击败：变暗显示
			slot_color = slot_color.darkened(UNIT_ENEMY_CFG.challenged_dim)

		# 菱形按 tier 取尺寸梯度（弱 75% → 超 90%）；击败态用统一 MAP_BASE_CFG.slot_margin
		# ⚠ MVP-C.2 调参面板 bug 修复：const Resource.Dict[索引] 二级表达式会 cache 旧引用；
		#   必须先把 Dict 字段赋给中间 var 再索引
		var rect_margin: int = MAP_BASE_CFG.slot_margin
		var tier_slot_margins_ref: Dictionary = UNIT_ENEMY_CFG.tier_slot_margins
		if not is_defeated and tier_slot_margins_ref.has(level.tier):
			rect_margin = tier_slot_margins_ref.get(level.tier, MAP_BASE_CFG.slot_margin) as int
		var slot_rect: Rect2 = Rect2(
			pos.x * TILE_SIZE + rect_margin,
			pos.y * TILE_SIZE + rect_margin,
			TILE_SIZE - rect_margin * 2 - 1,
			TILE_SIZE - rect_margin * 2 - 1
		)
		# 底色菱形
		_draw_diamond(slot_rect, slot_color)

		# 描边永远画（防御性兼容：DEFEATED slot 通常已 _level_slots.erase 不可达）
		# 米字仅活跃状态画
		var border_color: Color = UNIT_ENEMY_CFG.tier_border_color
		var border_width: float = UNIT_ENEMY_CFG.tier_border_widths.get(level.tier, 2.5)
		_draw_diamond(slot_rect, border_color, false, border_width)
		if not is_defeated:
			_draw_enemy_tier_pattern(slot_rect, level.tier)


## 绘制资源点标记方块 + 文字
## M6 P1 修复：即时 slot 采集走 4 项等权池（忽略 slot 自身 resource_type），
## 视觉上若按类型着色会误导玩家（以为是定向资源），故统一为盲盒灰色 + "?"
## 原按类型着色的 RESOURCE_*_COLOR 常量保留以备他处引用，但本函数不再使用
##
## UI 重构步骤 5：箱体感 —— 浅灰底 + 白描边 + "?"
## 形状保持方块（不改菱形，避免和敌方混淆）；语义上仍是盲盒不泄露类型
func _draw_resource_slots() -> void:
	for pos in _resource_slots:
		var rs: ResourceSlot = _resource_slots[pos] as ResourceSlot
		# 已采集的资源点不渲染
		if rs.is_collected:
			continue
		var p: Vector2i = pos as Vector2i

		var rs_rect: Rect2 = Rect2(
			p.x * TILE_SIZE + MAP_BASE_CFG.slot_margin,
			p.y * TILE_SIZE + MAP_BASE_CFG.slot_margin,
			TILE_SIZE - MAP_BASE_CFG.slot_margin * 2 - 1,
			TILE_SIZE - MAP_BASE_CFG.slot_margin * 2 - 1
		)
		# 箱体：浅灰底 + 白描边 + 内部 "?"
		draw_rect(rs_rect, RESOURCE_RENDER_CFG.blind_box_color)
		draw_rect(rs_rect, RESOURCE_RENDER_CFG.blind_box_outline, false, RESOURCE_RENDER_CFG.blind_box_outline_width)

		if _label_font != null:
			_draw_slot_label(
				Vector2(p.x * TILE_SIZE + TILE_SIZE / 2.0, p.y * TILE_SIZE + TILE_SIZE / 2.0),
				"?",
				Color(0.05, 0.05, 0.05)
			)

# ─────────────────────────────────────────
# 持久 slot 渲染（M4）
# ─────────────────────────────────────────


## 绘制所有已占据持久 slot 的影响范围覆盖层（曼哈顿菱形内所有格）
## 中立 slot / influence_range <= 0 不渲染
## 覆盖层先于 slot 本体绘制，保证本体图案可见；相邻 slot 覆盖区域色彩叠加属预期
##
## Civ 化阶段 A：硬外缘 + 内向渐变
##   填充：每格按"距菱形边界距离 d_to_edge = r - (|dx|+|dy|)"分层 alpha
##         外圈（d=0）OUTER 0.22 → 次外（d=1）MID 0.12 → 内层（d≥2）INNER 0.05
##         视觉：势力辐射从据点向外扩散，外圈最亮形成菱形"光环"
##         同势力 slot 重叠区填充 alpha 自然叠加变亮，语义即"势力辐射加成"
##   描边：势力合集化 —— 先构建每势力的全格 Dictionary 集合，
##         再对菱形内每格检查 4 邻居是否仍在该势力合集中；
##         不在 → 该边为合集外缘，用势力色原色 alpha 1.0 实线画出
##         效果：同势力相邻 / 重叠 slot 自动合并为单一外轮廓，无内部双线
##         跨势力相邻仍各画各的外缘 → 形成敌我双线，分清势力区
func _draw_persistent_influence_ranges() -> void:
	if _schema == null:
		return

	# 第一遍：按势力构建影响范围全格合集（Dictionary[Vector2i, bool] 去重）
	# 用于第二遍判定"邻居是否仍在该势力影响范围内"
	var faction_cells: Dictionary = {}
	for entry in _schema.persistent_slots:
		var slot: PersistentSlot = entry as PersistentSlot
		if slot == null:
			continue
		if slot.owner_faction == Faction.NONE:
			continue
		if slot.influence_range <= 0:
			continue
		var faction_id: int = slot.owner_faction
		if not faction_cells.has(faction_id):
			faction_cells[faction_id] = {}
		var cells: Dictionary = faction_cells[faction_id] as Dictionary
		var r0: int = slot.influence_range
		var cx0: int = slot.position.x
		var cy0: int = slot.position.y
		for dy0 in range(-r0, r0 + 1):
			var y0: int = cy0 + dy0
			if y0 < 0 or y0 >= _schema.height:
				continue
			var dx0_max: int = r0 - absi(dy0)
			for dx0 in range(-dx0_max, dx0_max + 1):
				var x0: int = cx0 + dx0
				if x0 < 0 or x0 >= _schema.width:
					continue
				cells[Vector2i(x0, y0)] = true

	# 第二遍：每个 slot 独立画填充（按距自己菱形边界分层），描边查询势力合集
	for entry in _schema.persistent_slots:
		var slot: PersistentSlot = entry as PersistentSlot
		if slot == null:
			continue
		if slot.owner_faction == Faction.NONE:
			continue
		if slot.influence_range <= 0:
			continue
		var base: Color = INFLUENCE_CFG.faction_colors.get(slot.owner_faction, Color.MAGENTA) as Color
		# 描边色：势力色原色 + alpha 1.0，地形已去饱和，原色最跳
		var border: Color = Color(base.r, base.g, base.b, INFLUENCE_CFG.influence_border_alpha)
		var cells: Dictionary = faction_cells[slot.owner_faction] as Dictionary
		var r: int = slot.influence_range
		var cx: int = slot.position.x
		var cy: int = slot.position.y
		# 曼哈顿菱形：|dx| + |dy| <= r
		for dy in range(-r, r + 1):
			var y: int = cy + dy
			if y < 0 or y >= _schema.height:
				continue
			var dx_max: int = r - absi(dy)
			for dx in range(-dx_max, dx_max + 1):
				var x: int = cx + dx
				if x < 0 or x >= _schema.width:
					continue
				# 距菱形外边界的曼哈顿距离：r 圈最外为 0、向内逐层递增
				var d_to_edge: int = r - (absi(dx) + absi(dy))
				var fill_alpha: float
				if d_to_edge == 0:
					fill_alpha = INFLUENCE_CFG.influence_alpha_outer
				elif d_to_edge == 1:
					fill_alpha = INFLUENCE_CFG.influence_alpha_mid
				else:
					fill_alpha = INFLUENCE_CFG.influence_alpha_inner
				var overlay: Color = Color(base.r, base.g, base.b, fill_alpha)
				var rect: Rect2 = Rect2(
					x * TILE_SIZE,
					y * TILE_SIZE,
					TILE_SIZE - 1,
					TILE_SIZE - 1
				)
				draw_rect(rect, overlay)

				# 描边：合集化判定 —— 邻居不在该势力影响合集 → 该边为合集外缘
				# 同势力相邻 / 重叠 slot 自动合并为单一外轮廓
				# 跨势力或地图边界保持外缘画线
				var px: float = float(x * TILE_SIZE)
				var py: float = float(y * TILE_SIZE)
				var pw: float = float(TILE_SIZE)
				# 上邻
				if not cells.has(Vector2i(x, y - 1)):
					draw_line(Vector2(px, py), Vector2(px + pw, py),
						border, INFLUENCE_CFG.influence_border_width)
				# 下邻
				if not cells.has(Vector2i(x, y + 1)):
					draw_line(Vector2(px, py + pw), Vector2(px + pw, py + pw),
						border, INFLUENCE_CFG.influence_border_width)
				# 左邻
				if not cells.has(Vector2i(x - 1, y)):
					draw_line(Vector2(px, py), Vector2(px, py + pw),
						border, INFLUENCE_CFG.influence_border_width)
				# 右邻
				if not cells.has(Vector2i(x + 1, y)):
					draw_line(Vector2(px + pw, py), Vector2(px + pw, py + pw),
						border, INFLUENCE_CFG.influence_border_width)


## 绘制敌方威胁圈（入口 1.1 战斗信息传达 探索阶段）
##
## 设计依据：tile-advanture-design/战斗信息传达_探索阶段_MVP.md §5 改动 1 / §8 视觉规格基准
##
## 行为：
##   - 遍历 _level_slots，筛选 faction != PLAYER 且 is_interactable() 的候选
##     （注：LevelSlot 的归属字段是 `faction`，与 PersistentSlot 的 `owner_faction` 名不同；见 Faction.gd 头注）
##     （is_interactable() 自动排除 DEFEATED 等不可触发战斗的状态）
##   - 对每个候选，枚举曼哈顿距离 ≤ _battle_trigger_range 的格集合，每格画半透明红
##   - 多个敌方威胁圈重叠时按调用顺序自然叠加（深红），无特殊合成
##
## 视觉规格：
##   - 颜色 Color(1, 0, 0, 0.20)（红 alpha 0.20）—— 与战斗内攻击范围（红 alpha 0.28）共享色调
##   - 单格 Rect2(p.x*TILE_SIZE+2, p.y*TILE_SIZE+2, TILE_SIZE-4, TILE_SIZE-4) —— 与玩家移动范围风格一致
##
## 战斗态：探索阶段专属信息层，战斗中不画（避免与战场视觉混淆）
func _draw_enemy_threat_zones() -> void:
	if _schema == null:
		return
	# 战斗态不画：探索阶段专属（含 COMA await 期间 —— session 已 ended 但还没置 null）
	if _battle_session != null:
		return
	const THREAT_COLOR: Color = Color(1, 0, 0, 0.20)
	for pos in _level_slots:
		var lv: LevelSlot = _level_slots[pos] as LevelSlot
		if lv == null:
			continue
		if lv.faction == Faction.PLAYER:
			continue
		if not lv.is_interactable():
			continue
		var origin: Vector2i = pos as Vector2i
		# 曼哈顿圆枚举：|dx| + |dy| ≤ R
		for dx in range(-_battle_trigger_range, _battle_trigger_range + 1):
			var remain: int = _battle_trigger_range - absi(dx)
			for dy in range(-remain, remain + 1):
				var p: Vector2i = Vector2i(origin.x + dx, origin.y + dy)
				# 边界裁剪：超出地图范围不画
				if p.x < 0 or p.y < 0 or p.x >= _schema.width or p.y >= _schema.height:
					continue
				var rect: Rect2 = Rect2(
					float(p.x * TILE_SIZE + 2),
					float(p.y * TILE_SIZE + 2),
					float(TILE_SIZE - 4),
					float(TILE_SIZE - 4)
				)
				draw_rect(rect, THREAT_COLOR)


## 绘制所有持久 slot 的本体标记
## UI 重构步骤 1：双层结构 —— 外环势力色 + 内底中性米白 + 核心城镇金边 + 中心徽记
##
## 设计理由（[[地图视觉表现优化方案]] §三）：
##   原整块势力色会让文字对比度随势力色变化，且远看只有"颜色块"；
##   双层后外环负责归属识别，内底承载文字高对比度，据点升级为"结构化地图对象"
##
## 归属翻转时势力色立即反映（由 try_occupy 触发 queue_redraw）
func _draw_persistent_slots() -> void:
	if _schema == null:
		return
	for entry in _schema.persistent_slots:
		var slot: PersistentSlot = entry as PersistentSlot
		if slot == null:
			continue
		var p: Vector2i = slot.position
		var outer: Rect2 = Rect2(
			p.x * TILE_SIZE + 1,
			p.y * TILE_SIZE + 1,
			TILE_SIZE - 3,
			TILE_SIZE - 3
		)
		var color: Color = INFLUENCE_CFG.faction_colors.get(slot.owner_faction, Color.MAGENTA) as Color

		# 三层结构：外环势力色 → 白分离线 → 内底米白
		# 即使势力色和地形色相近（如玩家蓝 ↔ 洼地蓝），白分离线也能清晰勾出据点边界
		draw_rect(outer, color)
		var ring: int = INFLUENCE_CFG.persistent_ring_width
		var separator_rect: Rect2 = Rect2(
			outer.position + Vector2(ring, ring),
			outer.size - Vector2(ring * 2, ring * 2)
		)
		if separator_rect.size.x > 0 and separator_rect.size.y > 0:
			draw_rect(separator_rect, INFLUENCE_CFG.persistent_separator_color)
			# 内底再内缩 separator_width，米白承载文字
			var sep: int = INFLUENCE_CFG.persistent_separator_width
			var inner: Rect2 = Rect2(
				separator_rect.position + Vector2(sep, sep),
				separator_rect.size - Vector2(sep * 2, sep * 2)
			)
			if inner.size.x > 0 and inner.size.y > 0:
				draw_rect(inner, INFLUENCE_CFG.persistent_inner_bg)

		# 持久slot援军 L1.2 / 敌方援军 L1.4：玩家方 + 敌方 owned slot 援军未耗尽 → 底部画"援军"条带（耗尽则不画）
		# 玩家方绿条带 / 敌方红条带（常显，F4）；条带在名称下方、不撞右上等级角标
		if not slot.reinforcement_roster.is_empty():
			if slot.owner_faction == Faction.PLAYER:
				_draw_reinforcement_band(outer, VISUAL_CFG.reinforcement_fill_color)
			elif slot.owner_faction == Faction.ENEMY_1:
				_draw_reinforcement_band(outer, VISUAL_CFG.enemy_reinforcement_band_color)

		# 核心城镇第二识别特征：金色外描边 + 下方小金菱形徽记
		# 徽记偏下（主字居中占主视觉），避免被文字压住
		# P0 第二阶段：CORE_TOWN 视觉双态 —— 仅 has_enemy_core 周期激活（P1-2a 修复：配置驱动）
		# 前两周期 CORE_TOWN 数据层仍是 CORE_TOWN（PCG / VictoryJudge / reinforcement 锚都依赖），
		# 视觉降级为普通 TOWN：跳过金边 / 徽记，主字改用 TOWN 短标签
		var is_core_town: bool = slot.type == PersistentSlot.Type.CORE_TOWN
		var is_core_town_activated: bool = is_core_town and _current_cycle_has_enemy_core
		if is_core_town_activated:
			draw_rect(outer, INFLUENCE_CFG.core_town_border, false, 2.0)
			var emblem_pos: Vector2 = outer.get_center() + Vector2(0, 12)
			_draw_core_town_emblem(emblem_pos)

		# 主字（display_id）+ 等级角标
		# display_id 落在内底米白上（任何势力色下对比度都最优）
		# legacy fallback（未分配 display_id）保留旧行为 main_text 含 level
		# P0 第二阶段：非末周期 CORE_TOWN 伪装为普通 TOWN —— 跳过 display_id 用 TOWN 短标签
		if _label_font != null:
			var center_px: Vector2 = outer.get_center()
			var main_text: String
			if is_core_town and not is_core_town_activated:
				# 伪装：主字用 TOWN 短标签 + level（"镇3"），不画等级角标避免暴露 display_id
				main_text = PersistentSlot.TYPE_MAP_LABELS.get(PersistentSlot.Type.TOWN, "镇") + str(slot.level)
			else:
				main_text = slot.display_id if slot.display_id != "" else (slot.get_map_label() + str(slot.level))
			_draw_slot_label(center_px, main_text, Color(0.05, 0.05, 0.05))

			# 等级角标：仅 display_id 模式画；CORE_TOWN 伪装态走 fallback 主字不再画角标
			if slot.display_id != "" and not (is_core_town and not is_core_town_activated):
				_draw_level_badge(p, slot.level)


## 绘制核心城镇中心金色菱形徽记（UI 重构步骤 1 · 核心第二识别特征）
## 叠加在主字"核心"之下作为装饰层；靠形状 + 金色拉开和普通据点的区别
## center_px: 格子像素中心
func _draw_core_town_emblem(center_px: Vector2) -> void:
	var s: float = float(INFLUENCE_CFG.core_town_emblem_size)
	var half: float = s / 2.0
	# 菱形 4 顶点（上 / 右 / 下 / 左）
	var pts: PackedVector2Array = PackedVector2Array([
		Vector2(center_px.x, center_px.y - half),
		Vector2(center_px.x + half, center_px.y),
		Vector2(center_px.x, center_px.y + half),
		Vector2(center_px.x - half, center_px.y),
	])
	draw_colored_polygon(pts, INFLUENCE_CFG.core_town_border)


## 持久 slot 援军条带（持久slot援军_MVP / L1.2；敌方援军_MVP / L1.4 阵营化）
## slot 援军未耗尽时在底边画"援军"条带；调用方已守卫 roster 非空 + owner 为玩家 / 敌方
## band_color: 玩家方传援军绿 reinforcement_fill_color / 敌方传红 enemy_reinforcement_band_color
## outer: slot 据点外框 Rect2（与三层结构同一矩形）
func _draw_reinforcement_band(outer: Rect2, band_color: Color) -> void:
	var band_h: float = float(INFLUENCE_CFG.reinforcement_band_height)
	var band_rect: Rect2 = Rect2(
		outer.position.x, outer.end.y - band_h,
		outer.size.x, band_h
	)
	draw_rect(band_rect, band_color)
	if _label_font == null:
		return
	# "援军"文字垂直居中于条带（基线 = 条带中心 + (ascent-descent)/2）
	var fsize: int = INFLUENCE_CFG.reinforcement_band_font_size
	var ascent: float = _label_font.get_ascent(fsize)
	var descent: float = _label_font.get_descent(fsize)
	var baseline_y: float = band_rect.get_center().y + (ascent - descent) / 2.0
	draw_string(
		_label_font,
		Vector2(band_rect.position.x, baseline_y),
		"援军",
		HORIZONTAL_ALIGNMENT_CENTER,
		band_rect.size.x,
		fsize,
		INFLUENCE_CFG.reinforcement_band_text_color
	)


## 绘制正在移动的敌方关卡标记（基于动画位置）
## 使用更大标记 + 外圈光晕 + 亮红橙色，突出移动中的敌方
func _draw_enemy_move_marker() -> void:
	var enemy_vis_pos: Vector2 = _enemy_movement.get_visual_pos()
	# 入口 4 后段第 1 份（夜晚视野 MVP，codex P0 修复 2026-05-11）：
	# 浓雾外移动中敌方在世界层完全跳过；屏幕空间信号由 _fog_signal_node 浮层接管
	if DayNightState.is_night(_turn_manager) and (not _battle_force_day) and _world_view.is_in_fog(enemy_vis_pos):
		return
	# 外圈光晕菱形（比标记更大，半透明）
	var glow_margin: int = 2
	var glow_rect: Rect2 = Rect2(
		enemy_vis_pos.x - TILE_SIZE / 2 + glow_margin,
		enemy_vis_pos.y - TILE_SIZE / 2 + glow_margin,
		TILE_SIZE - glow_margin * 2 - 1,
		TILE_SIZE - glow_margin * 2 - 1
	)
	_draw_diamond(glow_rect, UNIT_ENEMY_CFG.enemy_glow_color)
	# 核心菱形标记（标准大小，亮红橙色）
	var rect: Rect2 = Rect2(
		enemy_vis_pos.x - TILE_SIZE / 2 + MAP_BASE_CFG.slot_margin,
		enemy_vis_pos.y - TILE_SIZE / 2 + MAP_BASE_CFG.slot_margin,
		TILE_SIZE - MAP_BASE_CFG.slot_margin * 2 - 1,
		TILE_SIZE - MAP_BASE_CFG.slot_margin * 2 - 1
	)
	_draw_diamond(rect, UNIT_ENEMY_CFG.enemy_move_color)
	# 菱形边框描边
	_draw_diamond(rect, UNIT_ENEMY_CFG.enemy_border_color, false, 1.0)

## 绘制菱形（以 Rect2 区域的中心为菱形中心，四个顶点取矩形边中点）
## filled=true 时填充，filled=false 时仅描边
func _draw_diamond(rect: Rect2, color: Color, filled: bool = true, width: float = 1.0) -> void:
	# 防御退化矩形：尺寸为零时菱形顶点重合，跳过绘制
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var cx: float = rect.position.x + rect.size.x / 2.0
	var cy: float = rect.position.y + rect.size.y / 2.0
	var hw: float = rect.size.x / 2.0  # 水平半宽
	var hh: float = rect.size.y / 2.0  # 垂直半高
	# 四个顶点：上、右、下、左
	var points: PackedVector2Array = PackedVector2Array([
		Vector2(cx, cy - hh),       # 上
		Vector2(cx + hw, cy),       # 右
		Vector2(cx, cy + hh),       # 下
		Vector2(cx - hw, cy),       # 左
	])
	if filled:
		draw_colored_polygon(points, color)
	else:
		# 描边：绘制闭合折线
		var outline: PackedVector2Array = points
		outline.append(points[0])
		draw_polyline(outline, color, width)


## 绘制敌方 tier 米字小菱形图形（按 tier 累积点亮）
## 弱档（tier 0）特殊处理：单菱形**居外菱形正中**，与外菱形已显著缩小（67% 占格）共同强化"弱"语义
## 中/强/超档：按米字 4 方向（上/下/左/右）累积点亮，每个小菱形为外菱形 UNIT_ENEMY_CFG.tier_dot_size_ratio 倍尺寸
##
## 点亮策略：
##   tier 0 弱：1 个**居中**小菱形 —— "小且单点居中"语义
##   tier 1 中：上 + 下 2 个（垂直对称，米字方向）
##   tier 2 强：上 + 左 + 右 3 个（T 型，米字方向）
##   tier 3 超：4 个全亮（米字阵列）
##
## 弱档单独居中而非"上"的理由：1 个 vs 3 个的位置完全不同（中央 vs 米字外缘），
##                            视觉语义不会模糊（中点单兵 vs 外缘环绕）
##
## 颜色：金色填充（无描边）—— 与红底高对比，不喧宾夺主
func _draw_enemy_tier_pattern(outer_rect: Rect2, tier: int) -> void:
	var px: float = outer_rect.position.x
	var py: float = outer_rect.position.y
	var w: float = outer_rect.size.x
	var h: float = outer_rect.size.y
	# 小菱形尺寸 + 半边距
	var dot_size: Vector2 = Vector2(w, h) * UNIT_ENEMY_CFG.tier_dot_size_ratio
	var dot_half: Vector2 = dot_size * 0.5
	# 弱档：居外菱形正中
	if tier == 0:
		var center_pt: Vector2 = Vector2(px + w / 2.0, py + h / 2.0)
		var center_rect: Rect2 = Rect2(center_pt - dot_half, dot_size)
		_draw_diamond(center_rect, UNIT_ENEMY_CFG.tier_dot_color)
		return
	# 中/强/超：米字 4 方向中心点（上/下偏移 h/4，左/右偏移 w/4）
	var top_center: Vector2 = Vector2(px + w / 2.0, py + h / 4.0)
	var bottom_center: Vector2 = Vector2(px + w / 2.0, py + h * 3.0 / 4.0)
	var left_center: Vector2 = Vector2(px + w / 4.0, py + h / 2.0)
	var right_center: Vector2 = Vector2(px + w * 3.0 / 4.0, py + h / 2.0)
	# 4 个小菱形 rect
	var top_rect: Rect2 = Rect2(top_center - dot_half, dot_size)
	var bottom_rect: Rect2 = Rect2(bottom_center - dot_half, dot_size)
	var left_rect: Rect2 = Rect2(left_center - dot_half, dot_size)
	var right_rect: Rect2 = Rect2(right_center - dot_half, dot_size)
	# 按 tier 收集要点亮的小菱形
	var lit: Array[Rect2] = []
	if tier == 1:
		lit.append(top_rect)
		lit.append(bottom_rect)
	elif tier == 2:
		lit.append(top_rect)
		lit.append(left_rect)
		lit.append(right_rect)
	elif tier == 3:
		lit.append(top_rect)
		lit.append(bottom_rect)
		lit.append(left_rect)
		lit.append(right_rect)
	else:
		return
	# 每个小菱形：金色实心填充，无描边
	for r in lit:
		_draw_diamond(r, UNIT_ENEMY_CFG.tier_dot_color)


## UI 重构步骤 9：地形亮度噪声辅助函数
## 基于 (x, y) 的确定性哈希返回 ±MAP_BASE_CFG.terrain_noise_range 范围内的亮度偏移
## 同 seed 结果一致，不闪烁；目的只为打破"整齐表格感"
func _terrain_brightness_noise(x: int, y: int) -> float:
	# 素数混合 → [0, 100) 整数 → 归一化到 [-1, 1]
	var h: int = (x * 73856093) ^ (y * 19349663)
	var bucket: int = absi(h) % 100
	var normalized: float = (float(bucket) / 50.0) - 1.0    # [-1, 1]
	return normalized * MAP_BASE_CFG.terrain_noise_range


## 绘制持久 slot 等级角标（格子右上角小字 "L0/1/2/3"）
## grid_pos —— 该 slot 的格坐标，函数内自行算像素偏移
## 字体使用 MAP_BASE_CFG.level_badge_font_size（9px）；颜色与主字同深色以保持一致
## 位置：格子右上距边 2-3px，不覆盖势力金边 / 外框
func _draw_level_badge(grid_pos: Vector2i, level: int) -> void:
	if _label_font == null:
		return
	var text: String = "L%d" % level
	# 角标宽度估算（英文+数字约为字号 × 字符数 × 0.5）；右上靠边距 3px
	var badge_px: Vector2 = Vector2(
		grid_pos.x * TILE_SIZE + TILE_SIZE - 3,
		grid_pos.y * TILE_SIZE + 3 + MAP_BASE_CFG.level_badge_font_size
	)
	# 右对齐：draw_string 的起点是 baseline-left；向左偏移一个字串宽度
	# 无需精确文本宽度测量——用负 offset 让 CENTER 区域右对齐到 badge_px
	draw_string(
		_label_font,
		Vector2(badge_px.x - 16, badge_px.y),    # 16px 宽度区域，右对齐到 badge_px.x
		text,
		HORIZONTAL_ALIGNMENT_RIGHT,
		16,
		MAP_BASE_CFG.level_badge_font_size,
		Color(0.05, 0.05, 0.05)
	)


## 在指定像素中心绘制居中文字标签
## center_px: 格的像素中心坐标；使用字体 ascent/descent 精确计算垂直基线位置
func _draw_slot_label(center_px: Vector2, text: String, color: Color) -> void:
	if _label_font == null:
		return
	var ascent: float = _label_font.get_ascent(MAP_BASE_CFG.label_font_size)
	var descent: float = _label_font.get_descent(MAP_BASE_CFG.label_font_size)
	# 基线 = 中心点 + (ascent - descent) / 2，使文字视觉上精确居中
	var baseline_y: float = center_px.y + (ascent - descent) / 2.0
	# 文字区域从中心点左侧半格开始，宽度一格，CENTER 对齐实现水平居中
	var left_x: float = center_px.x - TILE_SIZE / 2.0
	draw_string(
		_label_font,
		Vector2(left_x, baseline_y),
		text,
		HORIZONTAL_ALIGNMENT_CENTER,
		TILE_SIZE,
		MAP_BASE_CFG.label_font_size,
		color
	)


## 绘制单位标记（基于视觉位置，支持动画中的平滑移动）
## UI 重构步骤 3：加深色描边 + 投影，消除"漂浮感"，让单位稳定为第一视觉锚点
##
## 绘制顺序（自底向上）：
##   1. 投影：圆形右下偏移 +2px 的半透明黑
##   2. 玩家蓝外环：实色大圆，承担"我方"身份识别
##   3. 白色内圆：内底，承载"我"字 + 与地形保持对比度
##   4. 文字：居中"我"字
##
## 形状选择圆而非方：
##   - 与玩家建筑（方/菱）形成"形状即语义"区分，避免远观混淆
##   - 与可达范围白色硬边（矩形格 4 邻接拼成的矩形轮廓）形态不同，不被吞没
##   - 圆形契合"棋子"语义
func _draw_unit_marker() -> void:
	var center: Vector2 = Vector2(_unit_visual_pos.x, _unit_visual_pos.y)
	var radius: float = float(TILE_SIZE - UNIT_ENEMY_CFG.unit_margin * 2) * 0.5

	# 投影：右下偏移 2px、半透明黑；圆形棋子感
	draw_circle(center + Vector2(2, 2), radius, UNIT_ENEMY_CFG.unit_shadow_color)

	# 玩家蓝外环（实色大圆）—— 与玩家建筑外环同色，统一"我方"语义
	# ⚠ MVP-C.2 调参面板 bug 修复：禁止 `INFLUENCE_CFG.faction_colors[X]` 二级表达式形式（GDScript
	#   对 const Resource 的二级索引会 cache 旧 Dict 引用，ImGui 改字段后不会同步）。
	#   必须先把 Dict 字段赋给中间 var，再索引取值。同 _draw_persistent_influence_ranges 套路。
	var faction_colors_ref: Dictionary = INFLUENCE_CFG.faction_colors
	var ring_color: Color = faction_colors_ref.get(Faction.PLAYER, Color.MAGENTA) as Color
	draw_circle(center, radius, ring_color)

	# 白色内圆（半径减环宽）—— 在地形上保留对比度，并承载文字
	draw_circle(center, radius - UNIT_ENEMY_CFG.unit_player_ring_width, UNIT_ENEMY_CFG.unit_color)

	# "我"字居中
	if _label_font != null:
		_draw_slot_label(_unit_visual_pos, "我", Color(0.15, 0.15, 0.15))


# ─────────────────────────────────────────
# E 战斗就地展开 MVP — 战场叠加渲染
# ─────────────────────────────────────────
#
# 设计原文：tile-advanture-design/探索体验实装/E_战斗就地展开_MVP.md §5 改动 2 / §2.5
#
# 渲染顺序（_draw 末尾追加）：
#   1. 战场范围内填充 + 边框（黄色 alpha 0.6 / 宽 2px）
#   2. 当前玩家单位的可达格（白色 alpha 0.15）
#   3. 当前玩家单位的可攻击目标格（红色 alpha 0.22）
#   4. 玩家方 / 敌方所有上场单位（圆形 + 阵营色 + 当前 actor 加粗白环）
#   5. 单位下方 HP 条（绿/黄/红按 hp_ratio）


## 战场叠加主入口：按层渲染战斗内的所有视觉元素
func _draw_battle_overlay() -> void:
	if _battle_session == null:
		return
	var arena: Rect2i = _battle_session.arena
	if arena.size.x <= 0 or arena.size.y <= 0:
		return

	# 1. 战场边框（黄色描边）
	var arena_px: Rect2 = Rect2(
		Vector2(arena.position.x * TILE_SIZE, arena.position.y * TILE_SIZE),
		Vector2(arena.size.x * TILE_SIZE, arena.size.y * TILE_SIZE)
	)
	draw_rect(arena_px, VISUAL_CFG.arena_border_color, false, VISUAL_CFG.arena_border_width)

	# 2/3. 当前玩家单位的可达 / 可攻击高亮（仅玩家回合）
	if _battle_session.is_player_turn():
		# 可达格（白色 alpha 0.16 填充 + 4 邻外边界白描边，复用探索阶段双通道风格）
		# 修跑测反馈：单层填充 0.16 alpha 在战场背景下不够醒目；加描边强化边界识别
		var reachable: Array[Vector2i] = _battle_session.get_reachable_for_current()
		# 转 Dictionary 便于 has() 查邻居（探索阶段同套手法，见第 3514 行 _reachable_tiles）
		var reach_set: Dictionary = {}
		for pos in reachable:
			reach_set[pos] = true
		for pos in reachable:
			var rect: Rect2 = Rect2(
				pos.x * TILE_SIZE + 2, pos.y * TILE_SIZE + 2,
				TILE_SIZE - 4, TILE_SIZE - 4
			)
			draw_rect(rect, VISUAL_CFG.reachable_color)
			# 4 邻外边界描边：邻居不在集合内 → 该侧画线
			var px: float = float(pos.x * TILE_SIZE)
			var py: float = float(pos.y * TILE_SIZE)
			var pw: float = float(TILE_SIZE)
			if not reach_set.has(Vector2i(pos.x, pos.y - 1)):
				draw_line(Vector2(px, py), Vector2(px + pw, py),
					MAP_BASE_CFG.reachable_border_color, MAP_BASE_CFG.reachable_border_width)
			if not reach_set.has(Vector2i(pos.x, pos.y + 1)):
				draw_line(Vector2(px, py + pw), Vector2(px + pw, py + pw),
					MAP_BASE_CFG.reachable_border_color, MAP_BASE_CFG.reachable_border_width)
			if not reach_set.has(Vector2i(pos.x - 1, pos.y)):
				draw_line(Vector2(px, py), Vector2(px, py + pw),
					MAP_BASE_CFG.reachable_border_color, MAP_BASE_CFG.reachable_border_width)
			if not reach_set.has(Vector2i(pos.x + 1, pos.y)):
				draw_line(Vector2(px + pw, py), Vector2(px + pw, py + pw),
					MAP_BASE_CFG.reachable_border_color, MAP_BASE_CFG.reachable_border_width)
		# 可攻击目标格（红 alpha 0.28 填充 + 4 邻外边界黄描边）
		# 与移动范围白描边对称的双通道风格；黄描边避免与敌方阵营红 + 红填充叠加导致边界模糊
		var targets: Array[BattleUnit] = _battle_session.get_attackable_targets()
		var attack_set: Dictionary = {}
		for tgt in targets:
			attack_set[tgt.battle_position] = true
		for tgt in targets:
			var p: Vector2i = tgt.battle_position
			var rect: Rect2 = Rect2(
				p.x * TILE_SIZE + 2, p.y * TILE_SIZE + 2,
				TILE_SIZE - 4, TILE_SIZE - 4
			)
			draw_rect(rect, VISUAL_CFG.attackable_color)
			# 4 邻外边界黄描边（与移动范围同套手法）
			var ax: float = float(p.x * TILE_SIZE)
			var ay: float = float(p.y * TILE_SIZE)
			var aw: float = float(TILE_SIZE)
			if not attack_set.has(Vector2i(p.x, p.y - 1)):
				draw_line(Vector2(ax, ay), Vector2(ax + aw, ay),
					VISUAL_CFG.attackable_border_color, VISUAL_CFG.attackable_border_width)
			if not attack_set.has(Vector2i(p.x, p.y + 1)):
				draw_line(Vector2(ax, ay + aw), Vector2(ax + aw, ay + aw),
					VISUAL_CFG.attackable_border_color, VISUAL_CFG.attackable_border_width)
			if not attack_set.has(Vector2i(p.x - 1, p.y)):
				draw_line(Vector2(ax, ay), Vector2(ax, ay + aw),
					VISUAL_CFG.attackable_border_color, VISUAL_CFG.attackable_border_width)
			if not attack_set.has(Vector2i(p.x + 1, p.y)):
				draw_line(Vector2(ax + aw, ay), Vector2(ax + aw, ay + aw),
					VISUAL_CFG.attackable_border_color, VISUAL_CFG.attackable_border_width)

	# 3.5 撤退提示（持久 slot 战场参与设计 L1.1 UX）：仅玩家回合，引导玩家往哪走可撤退
	# 放在单位渲染前 → 边界格高亮在单位下层不挡视线；方向文字在战场外围不被单位覆盖
	if _battle_session.is_player_turn():
		_draw_retreat_hints(arena)

	# 4/5. 单位渲染 + HP 条（玩家方 → 敌方顺序，确保当前 actor 高亮在最上）
	var current_actor: BattleUnit = _battle_session.current_actor()
	# 改动2（视觉与操作改进 §2.2）：当前 actor 地格四角呼吸角标（画在单位下层、地格四角不被棋子遮挡）
	# 仅玩家回合 + 未结束 + 当前 actor 静止（无移动/攻击 visual_offset）时显示；动画期间自动隐藏
	if _battle_session.is_player_turn() and not _battle_session.is_ended() \
			and current_actor != null and current_actor.is_active and current_actor.is_alive() \
			and not _battle_view.unit_visual_offsets.has(current_actor):
		_draw_battle_selected_brackets(current_actor.battle_position)
	for u in _battle_session.player_units:
		_draw_battle_unit(u, current_actor)
	for u in _battle_session.enemy_units:
		_draw_battle_unit(u, current_actor)

	# 6. 死亡渐隐单位（入口 1.2；独立渲染层，不经 _draw_battle_unit 早期 return）
	# _battle_view.dying_units 内的 BattleUnit hp 已 ≤ 0、is_alive() 为 false，本层用 alpha 渐隐替代消失
	# P2-2：迭代时复制 keys 防御 Tween 同步 erase 字典的脆弱依赖
	for dying_unit in _battle_view.dying_units.keys():
		if not _battle_view.dying_units.has(dying_unit):
			continue
		_draw_battle_dying_unit(dying_unit as BattleUnit, _battle_view.dying_units[dying_unit] as float)


## 撤退提示（持久 slot 战场参与设计 L1.1 UX）
##   1. 可撤退边界格青绿高亮（提示"站这里能撤退"）
##   2. 每条可撤退边外侧中点画方向文字（"↑/↓/←/→ 撤退"）
## 可撤退方向 = arena 四条边中未被地图边界裁剪的边（见 BattleSession.get_retreat_directions）
func _draw_retreat_hints(arena: Rect2i) -> void:
	if _battle_session == null:
		return
	var dirs: Dictionary = _battle_session.get_retreat_directions()

	# 1. 收集所有可撤退边界格（用 Dictionary 去重，避免角格被两条边重复绘制致 alpha 叠深）
	var retreat_cells: Dictionary = {}
	if bool(dirs["left"]):
		for y in range(arena.position.y, arena.end.y):
			retreat_cells[Vector2i(arena.position.x, y)] = true
	if bool(dirs["right"]):
		for y in range(arena.position.y, arena.end.y):
			retreat_cells[Vector2i(arena.end.x - 1, y)] = true
	if bool(dirs["up"]):
		for x in range(arena.position.x, arena.end.x):
			retreat_cells[Vector2i(x, arena.position.y)] = true
	if bool(dirs["down"]):
		for x in range(arena.position.x, arena.end.x):
			retreat_cells[Vector2i(x, arena.end.y - 1)] = true
	# 绘制边界格填充 + 描边
	for cell in retreat_cells:
		var c: Vector2i = cell as Vector2i
		var rect: Rect2 = Rect2(
			c.x * TILE_SIZE + 2, c.y * TILE_SIZE + 2,
			TILE_SIZE - 4, TILE_SIZE - 4
		)
		draw_rect(rect, VISUAL_CFG.retreat_cell_color)
		draw_rect(rect, VISUAL_CFG.retreat_cell_border_color, false, VISUAL_CFG.retreat_cell_border_width)

	# 2. 方向文字（每条可撤退边外侧；文字完全在战场外，不与 arena 重叠）
	#    左右用 RIGHT/LEFT 对齐贴边外侧（避免居中框越界进战场）；上下用 CENTER 水平居中
	if _label_font == null:
		return
	var off: float = VISUAL_CFG.retreat_hint_offset_px
	var fsize: int = VISUAL_CFG.retreat_hint_font_size
	var fcolor: Color = VISUAL_CFG.retreat_hint_text_color
	var box_w: float = float(fsize) * 6.0     # 容纳"箭头 + 空格 + 2 汉字"
	# arena 四边 + 中心像素坐标
	var cx_px: float = (float(arena.position.x) + float(arena.size.x) * 0.5) * TILE_SIZE
	var cy_px: float = (float(arena.position.y) + float(arena.size.y) * 0.5) * TILE_SIZE
	var left_px: float = float(arena.position.x) * TILE_SIZE
	var right_px: float = float(arena.end.x) * TILE_SIZE
	var top_px: float = float(arena.position.y) * TILE_SIZE
	var bottom_px: float = float(arena.end.y) * TILE_SIZE
	# 左右文字垂直居中基线微调（draw_string 的 y 是基线，加 ~0.35 字号让文字视觉居中于 cy）
	var v_center_y: float = cy_px + float(fsize) * 0.35
	# 上：水平居中，基线落在上边界外侧（off 间距让文字主体在战场上方）
	if bool(dirs["up"]):
		_draw_retreat_label(Vector2(cx_px - box_w * 0.5, top_px - off), "↑ 撤离",
			fsize, fcolor, HORIZONTAL_ALIGNMENT_CENTER, box_w)
	# 下：水平居中，基线再下移一个字号高度让文字主体整体落在下边界外
	if bool(dirs["down"]):
		_draw_retreat_label(Vector2(cx_px - box_w * 0.5, bottom_px + off + float(fsize)), "↓ 撤离",
			fsize, fcolor, HORIZONTAL_ALIGNMENT_CENTER, box_w)
	# 左：右对齐，文字框右端贴左边界外侧（left - off），整体在战场左侧
	if bool(dirs["left"]):
		_draw_retreat_label(Vector2(left_px - off - box_w, v_center_y), "← 撤离",
			fsize, fcolor, HORIZONTAL_ALIGNMENT_RIGHT, box_w)
	# 右：左对齐，文字框左端贴右边界外侧（right + off），整体在战场右侧
	if bool(dirs["right"]):
		_draw_retreat_label(Vector2(right_px + off, v_center_y), "→ 撤离",
			fsize, fcolor, HORIZONTAL_ALIGNMENT_LEFT, box_w)


## 撤离方向文字绘制：按指定水平对齐 + 文字框宽度绘制
## 左右贴边（RIGHT/LEFT 对齐）、上下水平居中（CENTER）由调用方传 align + pos 决定
func _draw_retreat_label(pos: Vector2, text: String, font_size: int, color: Color, align: int, box_w: float) -> void:
	draw_string(_label_font, pos, text, align, box_w, font_size, color)


## 渲染单个战场单位：圆形阵营色 + 当前 actor 白环 + HP 条
##
## 未上场（is_active = false）/ 已死（is_alive = false）单位不渲染
## 当前 actor（is current）加粗白外环 3px，提示玩家"轮到此单位"
##
## 入口 1.2：center 叠加 _battle_view.unit_visual_offsets[u] 视觉偏移（移动 Tween / 推冲 / 颤抖）
func _draw_battle_unit(u: BattleUnit, current_actor: BattleUnit) -> void:
	if u == null or not u.is_active or not u.is_alive():
		return
	var center: Vector2 = Vector2(
		u.battle_position.x * TILE_SIZE + TILE_SIZE * 0.5,
		u.battle_position.y * TILE_SIZE + TILE_SIZE * 0.5
	)
	if _battle_view.unit_visual_offsets.has(u):
		center += _battle_view.unit_visual_offsets[u] as Vector2
	# 改动1（视觉与操作改进 §2.1）：半径按品质缩放——高品质棋子更大更显眼
	var base_radius: float = float(TILE_SIZE - UNIT_ENEMY_CFG.unit_margin * 2) * 0.5
	var radius: float = _quality_scaled_radius(base_radius, u.troop)
	# 投影
	draw_circle(center + Vector2(2, 2), radius, UNIT_ENEMY_CFG.unit_shadow_color)
	# 阵营色填充
	# 入口 1.2 补充需求 2：玩家方已行动单位用 VISUAL_CFG.player_acted_color（灰）代替阵营色
	# 玩家回合开始 reset_turn_flags 后 has_attacked = false → 自动恢复阵营色
	var fill: Color = INFLUENCE_CFG.faction_colors.get(u.owner_faction, Color.MAGENTA) as Color
	# 持久slot援军 L1.2：援军（玩家阵营且无 CharacterData）用专属祖母绿，与本队青蓝区分
	if u.owner_faction == Faction.PLAYER and u.character == null:
		fill = VISUAL_CFG.reinforcement_fill_color
	# 入口 1.2 补充需求 2：玩家方已行动单位用灰代替阵营色（援军同样转灰 → 方案 a，与本队一致）
	if u.owner_faction == Faction.PLAYER and u.has_attacked:
		fill = VISUAL_CFG.player_acted_color
	draw_circle(center, radius, fill)
	# 改动1（视觉与操作改进 §2.1）：品质描边环（按品质宽度/色，越高越粗越醒目；R 不画）
	_draw_quality_border(center, radius, u.troop, 1.0)
	# 改动2（视觉与操作改进 §2.2）：当前 actor 选中表现已从棋子白环移到地格四角呼吸角标
	# （见绘制主流程 _draw_battle_selected_brackets）；此处不再画棋子白环
	# HP 条（单位下方）—— 入口 1.2 P1-5：传 unit 而非 troop，让函数内部决定是否补间
	# 入口 4 MVP：_draw_battle_hp_bar 内部判断队长身份并加金边（替换原银三角方案）
	# codex P2（视觉与操作改进）：HP 条用 base_radius 锚定——品质放大只长身体，外挂元素位置稳定不溢格
	_draw_battle_hp_bar(center, base_radius, u)
	# 视觉与操作改进 §2.4：HP 条左侧行动状态标记（仅玩家单位，区分未移动/已移动未攻击/已结束）
	_draw_action_state_marker(center, base_radius, u)
	# 入口 1.2 视觉层：兵种字符 + 克制图标（队长银三角已移除，改为 HP 条金边，详见 §8 视觉规格基准）
	_draw_battle_troop_glyph(center, u.troop)
	# 敌方援军 L1.4 §3.5：全单位品质角标（本队 / 我方援军 / 敌方 / 敌方援军统一画）；角标贴身体角 → 用缩放 radius
	_draw_quality_badge(center, radius, u.troop, 1.0)
	# 克制图标 2 个：仅在敌方单位 + 玩家回合 + 战斗未结束 + 当前 actor 为玩家方时画
	if u.owner_faction != Faction.PLAYER \
			and _battle_session.is_player_turn() \
			and not _battle_session.is_ended() \
			and current_actor != null \
			and current_actor.owner_faction == Faction.PLAYER:
		# codex P2：克制图标用 base_radius 锚定，避免 SSR 放大把图标推出格上沿
		_draw_counter_icons(center, base_radius, current_actor, u)


## 死亡渐隐单位渲染（入口 1.2 §5 改动 2 配套）
##
## 简化策略：渐隐期间仅画半透明阵营色圆 + 兵种字符（不画 HP 条 / 队长三角 / 克制图标 / 白环）
## - 这些细节随死亡消失即可，避免在死亡 0.3s 内仍出现"克制图标 / 白环"等暗示"还可交互"的元素
## - alpha 直接乘填充色 / 字色，与字典中维护的 0.0-1.0 渐变值同步
func _draw_battle_dying_unit(u: BattleUnit, alpha: float) -> void:
	if u == null:
		return
	var center: Vector2 = Vector2(
		u.battle_position.x * TILE_SIZE + TILE_SIZE * 0.5,
		u.battle_position.y * TILE_SIZE + TILE_SIZE * 0.5
	)
	if _battle_view.unit_visual_offsets.has(u):
		center += _battle_view.unit_visual_offsets[u] as Vector2
	# 改动1（视觉与操作改进 §2.1）：渐隐单位半径同样按品质缩放
	var base_radius: float = float(TILE_SIZE - UNIT_ENEMY_CFG.unit_margin * 2) * 0.5
	var radius: float = _quality_scaled_radius(base_radius, u.troop)
	var fill: Color = INFLUENCE_CFG.faction_colors.get(u.owner_faction, Color.MAGENTA) as Color
	# 持久slot援军 L1.2：援军阵亡渐隐时保持祖母绿，不回退到本队青蓝
	if u.owner_faction == Faction.PLAYER and u.character == null:
		fill = VISUAL_CFG.reinforcement_fill_color
	fill.a *= alpha
	draw_circle(center, radius, fill)
	# 改动1：品质描边环随死亡渐隐
	_draw_quality_border(center, radius, u.troop, alpha)
	# 兵种字符同步渐隐
	if _label_font != null and u.troop != null:
		var full_name: String = TroopData.TROOP_TYPE_NAMES.get(u.troop.troop_type, "?") as String
		var glyph: String = full_name.substr(0, 1) if full_name.length() > 0 else "?"
		var label_color: Color = VISUAL_CFG.troop_label_color
		label_color.a *= alpha
		_draw_slot_label(center, glyph, label_color)
	# 敌方援军 L1.4 §3.5：品质角标随死亡渐隐（与单位整体 alpha 同步）
	_draw_quality_badge(center, radius, u.troop, alpha)


## 地格四角呼吸角标（视觉与操作改进_MVP §2.2）：当前 actor 选中表现（替换棋子白环）
## 在 cell 四角画 L 形 bracket；内缩量按正弦相位脉动产生"内外收缩"呼吸感
## 调用方已守卫：玩家回合 + 战斗未结束 + 当前 actor 静止（无 visual_offset）
func _draw_battle_selected_brackets(cell: Vector2i) -> void:
	var x0: float = float(cell.x * TILE_SIZE)
	var y0: float = float(cell.y * TILE_SIZE)
	var x1: float = x0 + float(TILE_SIZE)
	var y1: float = y0 + float(TILE_SIZE)
	# 呼吸内缩：base ± amp·sin(phase)，clamp ≥0 防越出格角
	var inset: float = maxf(0.0,
		VISUAL_CFG.select_bracket_base_inset + VISUAL_CFG.select_bracket_amp * sin(_select_bracket_phase))
	var arm: float = VISUAL_CFG.select_bracket_arm
	var col: Color = VISUAL_CFG.select_bracket_color
	var w: float = VISUAL_CFG.select_bracket_width
	# 四角各画一个 L（两条短线段，沿格边内收）
	var tl: Vector2 = Vector2(x0 + inset, y0 + inset)        # 左上
	draw_line(tl, tl + Vector2(arm, 0), col, w)
	draw_line(tl, tl + Vector2(0, arm), col, w)
	var tr: Vector2 = Vector2(x1 - inset, y0 + inset)        # 右上
	draw_line(tr, tr + Vector2(-arm, 0), col, w)
	draw_line(tr, tr + Vector2(0, arm), col, w)
	var bl: Vector2 = Vector2(x0 + inset, y1 - inset)        # 左下
	draw_line(bl, bl + Vector2(arm, 0), col, w)
	draw_line(bl, bl + Vector2(0, -arm), col, w)
	var br: Vector2 = Vector2(x1 - inset, y1 - inset)        # 右下
	draw_line(br, br + Vector2(-arm, 0), col, w)
	draw_line(br, br + Vector2(0, -arm), col, w)


## 品质棋子半径缩放（视觉与操作改进_MVP §2.1）：基准半径 × quality_radius_scale[quality]
## 高品质棋子更大更显眼；troop 为 null 或未配置时回退基准
func _quality_scaled_radius(base_radius: float, troop: TroopData) -> float:
	if troop == null or VISUAL_CFG.quality_radius_scale.is_empty():
		return base_radius
	var q: int = clampi(troop.quality as int, 0, VISUAL_CFG.quality_radius_scale.size() - 1)
	return base_radius * VISUAL_CFG.quality_radius_scale[q]


## 品质描边环（视觉与操作改进_MVP §2.1）：棋子外缘按品质画描边，越高品质越粗
## 颜色复用 quality_badge_colors（与角标单一来源）；宽度 0 = 不画（R 默认无边）；alpha 供渐隐
func _draw_quality_border(center: Vector2, radius: float, troop: TroopData, alpha: float) -> void:
	if troop == null or VISUAL_CFG.quality_border_width.is_empty():
		return
	var q: int = clampi(troop.quality as int, 0, VISUAL_CFG.quality_border_width.size() - 1)
	var width: float = VISUAL_CFG.quality_border_width[q]
	if width <= 0.0:
		return
	var col: Color = Color.WHITE
	if not VISUAL_CFG.quality_badge_colors.is_empty():
		col = VISUAL_CFG.quality_badge_colors[clampi(q, 0, VISUAL_CFG.quality_badge_colors.size() - 1)]
	col.a *= alpha
	# 描边环中线置于 radius + width/2 → 内缘贴合填充圆外缘
	draw_arc(center, radius + width * 0.5, 0.0, TAU, 48, col, width)


## 行动状态标记（视觉与操作改进_MVP §2.4）：HP 条左侧小方块，区分玩家单位本回合行动态
## 状态：0=未移动（绿）/ 1=已移动未攻击（黄）/ 2=已攻击·已结束（灰）
## 仅玩家单位画（玩家管理自己的回合行动，尤其多援军时一眼分辨哪些已动）；用 base_radius 锚定与 HP 条对齐
func _draw_action_state_marker(center: Vector2, base_radius: float, unit: BattleUnit) -> void:
	if unit == null or unit.owner_faction != Faction.PLAYER:
		return
	if VISUAL_CFG.action_marker_colors.size() < 3:
		return
	var state: int = 0
	if unit.has_attacked:
		state = 2
	elif unit.has_moved:
		state = 1
	var col: Color = VISUAL_CFG.action_marker_colors[state]
	var size: float = VISUAL_CFG.action_marker_size
	# 与 HP 条同一锚点（_draw_battle_hp_bar：bar_y = center.y + base_radius + 4）；标记置于 HP 条左侧
	var bar_y: float = center.y + base_radius + 4.0
	var bar_h: float = float(VISUAL_CFG.hp_bar_height)
	var bar_x: float = center.x - float(VISUAL_CFG.hp_bar_width) * 0.5
	var marker_x: float = bar_x - VISUAL_CFG.action_marker_gap - size
	# 垂直与 HP 条居中对齐
	var marker_y: float = bar_y + bar_h * 0.5 - size * 0.5
	draw_rect(Rect2(marker_x, marker_y, size, size), col)


## 全单位品质显式角标（敌方援军_MVP / L1.4 §3.5）：单位格左上角画品质标识（R/SR/SSR 三档色 + 字母）
## 品质与阵营色正交——阵营=填充色，品质=角标；覆盖本队 / 我方援军 / 敌方 / 敌方援军全部单位
## center/radius: 单位圆心与半径；troop: 取 quality + 名称；alpha: 渐隐单位传 <1.0，活单位传 1.0
func _draw_quality_badge(center: Vector2, radius: float, troop: TroopData, alpha: float) -> void:
	if troop == null or VISUAL_CFG.quality_badge_colors.is_empty():
		return
	var q_idx: int = clampi(troop.quality as int, 0, VISUAL_CFG.quality_badge_colors.size() - 1)
	var bg: Color = VISUAL_CFG.quality_badge_colors[q_idx]
	bg.a *= alpha
	var label: String = troop.get_quality_name()
	var fsize: int = VISUAL_CFG.quality_badge_font_size
	# 角标尺寸按文字宽度自适应（容纳最长的 "SSR"）；高度按字体高
	var pad_x: float = 3.0
	var pad_y: float = 1.0
	var text_w: float = float(fsize) * float(label.length()) * 0.62 if _label_font == null \
		else _label_font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fsize).x
	var text_h: float = float(fsize) if _label_font == null else _label_font.get_height(fsize)
	var badge_w: float = text_w + pad_x * 2.0
	var badge_h: float = text_h + pad_y * 2.0
	# 锚点：单位圆左上角（避开右上等级角标 / 底边援军条带）
	var badge_pos: Vector2 = Vector2(center.x - radius, center.y - radius)
	draw_rect(Rect2(badge_pos, Vector2(badge_w, badge_h)), bg)
	if _label_font != null:
		var text_color: Color = VISUAL_CFG.quality_badge_text_color
		text_color.a *= alpha
		var baseline_y: float = badge_pos.y + pad_y + _label_font.get_ascent(fsize)
		draw_string(
			_label_font,
			Vector2(badge_pos.x + pad_x, baseline_y),
			label,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1.0,
			fsize,
			text_color
		)


## 兵种字符：单位中心绘制 "剑/弓/枪/骑/盾" 单字（取自 TroopData.TROOP_TYPE_NAMES 首字）
## 设计依据：tile-advanture-design/战斗信息传达_战斗内_MVP.md §8 视觉规格基准
##   - 字号 MAP_BASE_CFG.label_font_size=12（落在设计要求 12-14 区间）
##   - 颜色白 Color(1,1,1) 与单位阵营色填充对比
##   - 玩家方 / 敌方均显示
func _draw_battle_troop_glyph(center: Vector2, troop: TroopData) -> void:
	if troop == null or _label_font == null:
		return
	var full_name: String = TroopData.TROOP_TYPE_NAMES.get(troop.troop_type, "?") as String
	# TROOP_TYPE_NAMES 形如 "剑兵" / "弓兵"，取首字以紧凑显示在单位中心
	var glyph: String = full_name.substr(0, 1) if full_name.length() > 0 else "?"
	_draw_slot_label(center, glyph, VISUAL_CFG.troop_label_color)


## 克制图标 2 个：左 = 兵种克制，右 = 地形克制
## 设计依据：tile-advanture-design/战斗信息传达_战斗内_MVP.md §3 / §8
##   - 兵种克制：BattleResolver.get_counter_factor(actor, target) > / = / < 1.0
##   - 地形克制：actor 高度 - target 高度 > / = / < 0
##   - 形状：▲ 优势绿 / ▼ 劣势橙 / ● 中性白
##   - 锚点 center.y - radius - VISUAL_CFG.head_offset（与队长银三角共用轨道，但仅敌方画）
func _draw_counter_icons(center: Vector2, radius: float, actor: BattleUnit, target: BattleUnit) -> void:
	if actor == null or actor.troop == null or target == null or target.troop == null:
		return
	if _battle_session == null or _battle_session.schema == null:
		return
	var anchor_y: float = center.y - radius - VISUAL_CFG.head_offset
	# 兵种克制（左）
	var counter_factor: float = BattleResolver.get_counter_factor(
		actor.troop.troop_type, target.troop.troop_type
	)
	var left_center: Vector2 = Vector2(center.x - VISUAL_CFG.counter_icon_gap * 0.5, anchor_y)
	_draw_counter_glyph(left_center, VISUAL_CFG.counter_icon_size, _factor_to_dir(counter_factor))
	# 地形克制（右）
	var schema_ref: MapSchema = _battle_session.schema
	var actor_alt: int = schema_ref.get_terrain_altitude(
		actor.battle_position.x, actor.battle_position.y
	)
	var target_alt: int = schema_ref.get_terrain_altitude(
		target.battle_position.x, target.battle_position.y
	)
	var altitude_diff: int = actor_alt - target_alt
	var alt_dir: int = 0
	if altitude_diff > 0:
		alt_dir = 1
	elif altitude_diff < 0:
		alt_dir = -1
	var right_center: Vector2 = Vector2(center.x + VISUAL_CFG.counter_icon_gap * 0.5, anchor_y)
	_draw_counter_glyph(right_center, VISUAL_CFG.counter_icon_size, alt_dir)


## counter_factor → 方向枚举
##   返回 1 = 优势（>1.0），-1 = 劣势（<1.0），0 = 中性（=1.0 内 EPS 容差）
func _factor_to_dir(factor: float) -> int:
	if factor > 1.0 + VISUAL_CFG.counter_factor_eps:
		return 1
	if factor < 1.0 - VISUAL_CFG.counter_factor_eps:
		return -1
	return 0


## 绘制单个克制图标：dir=1 ▲ 绿；dir=-1 ▼ 橙；dir=0 ● 白
func _draw_counter_glyph(center: Vector2, size: float, dir: int) -> void:
	var half: float = size * 0.5
	if dir == 0:
		# ● 中性：实心圆
		draw_circle(center, half, VISUAL_CFG.counter_icon_neutral)
	elif dir > 0:
		# ▲ 优势：底在下、顶在上的三角
		var p_left: Vector2 = Vector2(center.x - half, center.y + half)
		var p_right: Vector2 = Vector2(center.x + half, center.y + half)
		var p_top: Vector2 = Vector2(center.x, center.y - half)
		draw_polygon(
			PackedVector2Array([p_left, p_right, p_top]),
			PackedColorArray([VISUAL_CFG.counter_icon_advantage])
		)
	else:
		# ▼ 劣势：底在上、顶在下的三角
		var p_left: Vector2 = Vector2(center.x - half, center.y - half)
		var p_right: Vector2 = Vector2(center.x + half, center.y - half)
		var p_bottom: Vector2 = Vector2(center.x, center.y + half)
		draw_polygon(
			PackedVector2Array([p_left, p_right, p_bottom]),
			PackedColorArray([VISUAL_CFG.counter_icon_disadvantage])
		)


## HP 条：背景黑底 + 前景按 hp_ratio 三段配色
##   ≥ 0.66 绿；0.33 ~ 0.66 黄；< 0.33 红
##
## 入口 1.2 P1-5 修复：被攻击者补间期间从 _battle_view.displayed_hps 字典读 hp（float），
## 平滑过渡到 troop.current_hp；不在字典时直接读 troop.current_hp，与原行为一致
func _draw_battle_hp_bar(center: Vector2, radius: float, unit: BattleUnit) -> void:
	if unit == null or unit.troop == null or unit.troop.max_hp <= 0:
		return
	var troop: TroopData = unit.troop
	var displayed_hp: float = _battle_view.displayed_hps.get(unit, float(troop.current_hp)) as float
	var ratio: float = clampf(displayed_hp / float(troop.max_hp), 0.0, 1.0)
	var bar_w: float = float(VISUAL_CFG.hp_bar_width)
	var bar_h: float = float(VISUAL_CFG.hp_bar_height)
	var bar_x: float = center.x - bar_w * 0.5
	var bar_y: float = center.y + radius + 4.0
	var bar_rect: Rect2 = Rect2(bar_x, bar_y, bar_w, bar_h)
	# 背景
	draw_rect(bar_rect, VISUAL_CFG.hp_bar_bg_color, true)
	# 前景按 hp_ratio
	var fg: Color = VISUAL_CFG.hp_color_low
	if ratio >= 0.66:
		fg = VISUAL_CFG.hp_color_full
	elif ratio >= 0.33:
		fg = VISUAL_CFG.hp_color_mid
	if ratio > 0.0:
		draw_rect(Rect2(bar_x, bar_y, bar_w * ratio, bar_h), fg, true)
	# 入口 4 MVP：队长 HP 条金边（替换原银三角方案）
	# 判断条件：玩家阵营 + player_units[0] = 队长
	# 修正（2026-05-09 跑测）：原 draw_rect 在 bar_rect 边界居中描边会向内压一半 → 血条本身被遮
	# 改为 grow(BORDER_WIDTH) 把描边外扩，金边内侧贴血条外缘 + 完全不覆盖血条本体
	if unit.owner_faction == Faction.PLAYER \
			and _battle_session != null \
			and not _battle_session.player_units.is_empty() \
			and unit == _battle_session.player_units[0]:
		var border_rect: Rect2 = bar_rect.grow(VISUAL_CFG.leader_hp_border_width)
		draw_rect(border_rect, VISUAL_CFG.leader_hp_border_color, false, VISUAL_CFG.leader_hp_border_width)



## 入口 4 MVP（2026-05-09 追加）：战场外压暗 overlay
##
## 战斗 zoom 期间（_battle_zoom_active = true）画 4 个半透明黑色矩形覆盖战场之外
## 战场区域 = 队长 ±_battle_arena_range 格 = (2*range+1)² 矩形
## 实装方式：以战场为中心做"挖空"——画上 / 下 / 左 / 右 4 个矩形，中间留出战场不画
## 覆盖范围：VISUAL_CFG.dim_padding_px 远超 camera 视野（zoom 0.55 + 倾斜 5° 仍可覆盖）
## 调用时机：_draw() 末尾、HUD 之前
func _draw_battle_dim_overlay() -> void:
	if not _battle_zoom_active:
		return
	var r: int = _battle_arena_range
	var cx: int = _battle_center_grid.x
	var cy: int = _battle_center_grid.y
	# 战场矩形（世界像素坐标）
	var bx: int = (cx - r) * TILE_SIZE
	var by: int = (cy - r) * TILE_SIZE
	var bw: int = (2 * r + 1) * TILE_SIZE
	var bh: int = (2 * r + 1) * TILE_SIZE
	# Overlay 总范围（远超 camera 视野；padding 大保证 zoom out + 倾斜后仍覆盖）
	var pad: int = VISUAL_CFG.dim_padding_px
	var ox: int = bx - pad
	var oy: int = by - pad
	var ow: int = bw + 2 * pad
	var oh: int = bh + 2 * pad
	# 四矩形挖空：上 / 下（覆盖战场上下方全宽）+ 左 / 右（仅战场同高范围内）
	# 上方
	draw_rect(Rect2(ox, oy, ow, by - oy), VISUAL_CFG.dim_color, true)
	# 下方
	draw_rect(Rect2(ox, by + bh, ow, (oy + oh) - (by + bh)), VISUAL_CFG.dim_color, true)
	# 左侧（仅战场同高）
	draw_rect(Rect2(ox, by, bx - ox, bh), VISUAL_CFG.dim_color, true)
	# 右侧（仅战场同高）
	draw_rect(Rect2(bx + bw, by, (ox + ow) - (bx + bw), bh), VISUAL_CFG.dim_color, true)
