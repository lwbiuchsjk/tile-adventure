class_name BattleAnimDirector
extends Node
## 战斗单位动画编排器（MVP-γ 阶段 1）
##
## 设计原文：
##   tile-advanture-design/代码健康度回看/MVP-γ_拆分批1.md §核心概念 / §接口设计
##   tile-advanture-design/代码健康度回看/01_结构维度报告.md §2.2 方案 B
##
## 职责：
##   承接原 WorldMap 区块 12 中"BattleSession 单位事件 sink → Tween 动画"的适配逻辑。
##   接收 BattleSession 发来的单位事件（moved/attacked/skipped/died），翻译成 Tween
##   动画，把瞬时视觉态写入 BattleViewState，动画期间锁 BattleHUD 输入，动画队列
##   清空后 emit anims_drained 让 WorldMap 接驳敌方回合下一步。
##
## 设计要点：
##   - 是 Node 而非 RefCounted：动画依赖 create_tween() / await get_tree().process_frame，
##     需挂在场景树内。由 WorldMap 在 _init_subsystems 创建为子节点、跨战斗复用。
##   - 不含 _on_battle_session_ended：战斗结束后的奖励/镜头/coma 重生属"世界态操作"，
##     留在 WorldMap。
##   - 不含敌方回合调度（_try_schedule_next_enemy_step / _run_enemy_turn_async）：
##     那属世界态，留在 WorldMap，本类只在动画清空时 emit anims_drained。
##   - 战斗动画常量（TILE_SIZE / BATTLE_*）仍读 WorldMap 的 const（编译期常量，
##     跨 class_name 引用）。常量集中化是诊断报告 P3 议题，本批不动。


## 动画队列清空（_anim_count == 0 且 _anim_queue 为空）时 emit
## WorldMap 连接此信号 → _try_schedule_next_enemy_step（敌方回合接驳）
signal anims_drained


## ─────────────────────────────────────
## 注入引用（WorldMap 在每场战斗 setup 时注入）
## ─────────────────────────────────────

## 重绘目标 + BattleFloatText 父节点
## 阶段 1 = WorldMap 自身；阶段 2 = WorldMapRenderer。必须是 Node2D（飘字需坐标空间）
var _redraw_target: Node2D = null

## 战斗内 HUD，动画期间锁 / 解锁玩家输入
var _battle_hud = null

## 战斗瞬时视觉态载体（写方）
var _view_state: BattleViewState = null

## 地形高度步长（飘字副行"+X% 高度"计算用），战斗内常量
var _terrain_altitude_step: float = 0.0


## ─────────────────────────────────────
## 入口 1.2 战斗动画并发控制 + 串行队列
##
## 设计意图：
##   - 同一 anim runner 内的多个 Tween（推冲 + 颤抖 + HP 补间）并行播放，整体作为一个 anim
##   - 不同行动的 anim 通过 queue 串行：避免敌方"先移动后攻击"两个事件 emit 时偏移互覆盖
##   - HUD 锁输入由 _anim_count 决定（>0 锁，归零解锁）
##
## 飘字（BattleFloatText）单独走异步生命周期，不计入 _anim_count、不入 queue
## ─────────────────────────────────────

## 动画并发计数：> 0 时 BattleHUD 锁输入，回到 0 时解锁
var _anim_count: int = 0

## 动画串行化队列：sink 不立即启动 Tween 而是入队；前一个 anim 全部 _end 后 drain 下一个
var _anim_queue: Array[Callable] = []


## 注入战斗上下文（每场战斗开始时由 WorldMap._start_battle_session / _start_passive_battle 调用）
func setup(
	redraw_target: Node2D, battle_hud, view_state: BattleViewState,
	terrain_altitude_step: float
) -> void:
	_redraw_target = redraw_target
	_battle_hud = battle_hud
	_view_state = view_state
	_terrain_altitude_step = terrain_altitude_step


## 战斗结束 / 中断时复位动画并发状态（计数 + 队列）
## 3 个视觉态字典由 BattleViewState.clear() 单独清，本方法不碰
func reset() -> void:
	_anim_count = 0
	_anim_queue.clear()


## 把 BattleSession 的 6 个单位动画 sink 指向本类方法
## 由 WorldMap._bind_battle_session_sinks 调用；on_battle_ended / on_redraw_requested
## 仍由 WorldMap 自己绑定（属世界态收尾，不进 Director）
func bind_unit_sinks(battle_session) -> void:
	battle_session.on_unit_moved = _on_battle_unit_moved
	battle_session.on_unit_attacked = _on_battle_unit_attacked
	battle_session.on_unit_skipped = _on_battle_unit_skipped
	battle_session.on_unit_died = _on_battle_unit_died
	battle_session.on_phase_changed = _on_battle_phase_changed
	battle_session.on_round_started = _on_battle_round_started


## 是否有动画在进行（_anim_count > 0 或队列非空）
## 替代原 WorldMap 直读 _battle_anim_count / _battle_anim_queue 的守卫
func is_animating() -> bool:
	return _anim_count > 0 or not _anim_queue.is_empty()


func _begin_battle_anim() -> void:
	_anim_count += 1
	if _anim_count == 1 and _battle_hud != null:
		_battle_hud.set_actions_enabled(false)


func _end_battle_anim() -> void:
	_anim_count = maxi(0, _anim_count - 1)
	if _anim_count == 0:
		if _battle_hud != null:
			_battle_hud.set_actions_enabled(true)
		# 优先排队中的下一个动画；queue 空 → emit 让 WorldMap 推敌方回合下一个 step
		if not _anim_queue.is_empty():
			_drain_battle_anim_queue()
		else:
			anims_drained.emit()


## 入队一个 anim runner 并尝试启动；runner 必须自身负责 _begin_battle_anim / _end_battle_anim 配对
func _enqueue_battle_anim(runner: Callable) -> void:
	_anim_queue.append(runner)
	# 当前空闲 → 立即出队执行；否则等 _end_battle_anim 触发 drain
	if _anim_count == 0:
		_drain_battle_anim_queue()


## 出队一个 anim runner 并执行；调用前应保证 _anim_count == 0
func _drain_battle_anim_queue() -> void:
	if _anim_count > 0:
		return
	if _anim_queue.is_empty():
		return
	var runner: Callable = _anim_queue.pop_front()
	runner.call()


## 入口 2 MVP 2.1 议题 5（2026-05-10）：等待战斗动画队列完全跑完
##
## 用于 COMA 触发时让玩家看到致命一击的完整动画再进入黑屏
## 完成条件：_anim_count == 0 且 _anim_queue 为空
##
## 实现：每帧 polling；典型动画 0.3-0.6s，polling 帧数 < 60
## safety_cap 保险：单 Tween 卡死时不让此函数永久 await
##
## codex review P2-2 限制说明（2026-05-10）：本函数用 get_tree().process_frame 推进，
## Director 是普通 Node（非 PROCESS_MODE_ALWAYS）—— 若未来引入 pause 机制（暂停菜单等），
## tree paused 时 process_frame 不会推进，本函数会卡死。届时需改为 SceneTreeTimer 或将
## process_mode 改为 ALWAYS
func await_anims_finished() -> void:
	var safety_frames: int = 600  # 10s @ 60fps；正常动画绝不会跑这么久
	var n: int = 0
	while (_anim_count > 0 or not _anim_queue.is_empty()) and n < safety_frames:
		await get_tree().process_frame
		n += 1
	if n >= safety_frames:
		push_warning("BattleAnimDirector.await_anims_finished: 超时 %d 帧，强制退出（_anim_count=%d / queue.size=%d）" % [safety_frames, _anim_count, _anim_queue.size()])


## ─────────────────────────────────────
## 入口 1.2 行动事件 sink（接 BattleSession 信号 → 入队 anim runner）
## 设计依据：tile-advanture-design/战斗信息传达_战斗内_MVP.md §5 改动 2
##
## 共同模式：sink 仅做参数捕获 + 入队；实际 Tween 启动在 _run_xxx_anim 内
## 入队 + 串行化保证：同一 actor 的连续行动（敌方 ATTACK 含 move + attack）不会偏移互覆盖
## ─────────────────────────────────────

## 入队"立即占位"原则（修跑测发现的视觉跳点）：
## sink 触发时 BattleSession 已更新数据（actor.battle_position / troop.current_hp / hp ≤ 0），
## 但 anim runner 因前一个动画还在跑而排队。在 runner 出队前的窗口期，_draw 会用最新数据
## 渲染（actor 闪现 to_pos / HP 条跳新值 / 单位直接消失）。
##
## 修复：sink 入队时立即设视觉状态字典（offset / displayed_hp / dying_alpha），
##       runner 出队后只负责启动 Tween。

func _on_battle_unit_moved(actor: BattleUnit, from_pos: Vector2i, to_pos: Vector2i) -> void:
	if actor == null or from_pos == to_pos:
		_redraw_target.queue_redraw()
		return
	# 立即占位：把视觉偏移设为 (from - to)，让 _draw 显示在 from_pos
	# 否则若前一个 anim 还在跑，actor 会先闪现在 to_pos 一段时间才回到 from_pos 开始 Tween
	var initial_offset: Vector2 = Vector2(
		float((from_pos.x - to_pos.x) * WorldMap.TILE_SIZE),
		float((from_pos.y - to_pos.y) * WorldMap.TILE_SIZE)
	)
	_view_state.unit_visual_offsets[actor] = initial_offset
	_redraw_target.queue_redraw()
	var runner: Callable = func() -> void: _run_move_anim(actor, from_pos, to_pos)
	_enqueue_battle_anim(runner)


func _on_battle_unit_attacked(
	actor: BattleUnit, target: BattleUnit,
	damage: int, counter_factor: float, altitude_diff: int,
	is_killing_blow: bool
) -> void:
	if actor == null or target == null:
		_redraw_target.queue_redraw()
		return
	# HP 补间起点：补间未完成时取字典中的"显示中 HP"，否则取攻击前的 hp（current_hp + damage）
	var hp_before: float = float(_view_state.displayed_hps.get(target, target.troop.current_hp + damage))
	var hp_after: float = float(target.troop.current_hp)
	# 立即占位：HP 条锁在旧值，runner 启动时再 Tween 到新值
	# 否则若前一个 anim 还在跑，HP 条会先跳到新值再回到旧值补间，体感"双跳"
	_view_state.displayed_hps[target] = hp_before
	_redraw_target.queue_redraw()
	var runner: Callable = func() -> void:
		_run_attack_anim(actor, target, damage, counter_factor, altitude_diff, hp_before, hp_after, is_killing_blow)
	_enqueue_battle_anim(runner)


func _on_battle_unit_skipped(actor: BattleUnit) -> void:
	if actor == null:
		_redraw_target.queue_redraw()
		return
	# 跳过 actor 的 battle_position 不变，无需占位
	var runner: Callable = func() -> void: _run_skip_anim(actor)
	_enqueue_battle_anim(runner)


func _on_battle_unit_died(unit: BattleUnit) -> void:
	if unit == null:
		_redraw_target.queue_redraw()
		return
	# 立即占位：unit hp 已 ≤ 0，is_alive() 为 false，_draw_battle_unit 早期 return
	# 不占位则 runner 出队前单位"消失"；占位后渲染走 _draw_battle_dying_unit 半透明圆
	_view_state.dying_units[unit] = 1.0
	_redraw_target.queue_redraw()
	var runner: Callable = func() -> void: _run_die_anim(unit)
	_enqueue_battle_anim(runner)


## 阶段切换 sink（MVP 暂 noop；接口留给未来阶段切换横幅 / 提示音等扩展）
func _on_battle_phase_changed(_new_phase: int) -> void:
	_redraw_target.queue_redraw()


## 新一轮玩家回合 sink（MVP 暂 noop；接口留给未来轮次飘字 / HUD 提示）
func _on_battle_round_started(_round_num: int) -> void:
	_redraw_target.queue_redraw()


## ─────────────────────────────────────
## 入口 1.2 anim runner 实现
## 每个 runner 调用 _begin_battle_anim 一次（每个 Tween）+ 完成回调 _end_battle_anim
## ─────────────────────────────────────

## 移动 runner：sink 已占位 offset = (from - to)*TILE_SIZE；runner 内 Tween 该值 → Vector2.ZERO
## 兜底：未占位时（直接调用场景）再设一次
func _run_move_anim(actor: BattleUnit, from_pos: Vector2i, to_pos: Vector2i) -> void:
	var initial_offset: Vector2 = Vector2(
		float((from_pos.x - to_pos.x) * WorldMap.TILE_SIZE),
		float((from_pos.y - to_pos.y) * WorldMap.TILE_SIZE)
	)
	if not _view_state.unit_visual_offsets.has(actor):
		_view_state.unit_visual_offsets[actor] = initial_offset
	_begin_battle_anim()
	_redraw_target.queue_redraw()
	var tween: Tween = create_tween()
	tween.tween_method(
		func(progress: float) -> void:
			_view_state.unit_visual_offsets[actor] = initial_offset.lerp(Vector2.ZERO, progress)
			_redraw_target.queue_redraw(),
		0.0, 1.0, WorldMap.BATTLE_MOVE_TWEEN_DURATION
	)
	tween.tween_callback(func() -> void:
		_view_state.unit_visual_offsets.erase(actor)
		_end_battle_anim()
		_redraw_target.queue_redraw()
	)


## 攻击 runner：actor 推冲 + 回弹（串行）；target 颤抖（并行）；飘字 + HP 补间
##
## is_killing_blow=true：本击导致队长 COMA —— 用更慢、幅度更大的参数强化因果感
func _run_attack_anim(
	actor: BattleUnit, target: BattleUnit,
	damage: int, counter_factor: float, altitude_diff: int,
	hp_before: float, hp_after: float, is_killing_blow: bool
) -> void:
	# 致命一击 vs 普通：动画参数选用（普通常量 vs 升级常量）
	var thrust_dur: float = WorldMap.BATTLE_KILLING_THRUST_DURATION if is_killing_blow else WorldMap.BATTLE_THRUST_DURATION
	var thrust_ratio: float = WorldMap.BATTLE_KILLING_THRUST_DISTANCE_RATIO if is_killing_blow else WorldMap.BATTLE_THRUST_DISTANCE_RATIO
	var shake_dur: float = WorldMap.BATTLE_KILLING_SHAKE_DURATION if is_killing_blow else WorldMap.BATTLE_SHAKE_DURATION
	var shake_amp: float = WorldMap.BATTLE_KILLING_SHAKE_AMPLITUDE if is_killing_blow else WorldMap.BATTLE_SHAKE_AMPLITUDE
	var shake_osc: float = WorldMap.BATTLE_KILLING_SHAKE_OSCILLATIONS if is_killing_blow else WorldMap.BATTLE_SHAKE_OSCILLATIONS
	var hp_dur: float = WorldMap.BATTLE_KILLING_HP_TWEEN_DURATION if is_killing_blow else WorldMap.BATTLE_HP_TWEEN_DURATION
	var float_dur: float = WorldMap.BATTLE_KILLING_FLOAT_DAMAGE_DURATION if is_killing_blow else WorldMap.BATTLE_FLOAT_DAMAGE_DURATION

	# 推冲方向：单位差 / 曼哈顿距离（远程兵种斜攻时按斜向单位向量推冲）
	var diff: Vector2i = target.battle_position - actor.battle_position
	var dir: Vector2 = Vector2.ZERO
	var manhattan_d: int = absi(diff.x) + absi(diff.y)
	if manhattan_d > 0:
		dir = Vector2(float(diff.x), float(diff.y)) / float(manhattan_d)
	var thrust_offset: Vector2 = dir * float(WorldMap.TILE_SIZE) * thrust_ratio

	# actor 推冲 + 回弹
	_begin_battle_anim()
	var actor_set_offset: Callable = func(off: Vector2) -> void:
		_view_state.unit_visual_offsets[actor] = off
		_redraw_target.queue_redraw()
	var actor_tween: Tween = create_tween()
	actor_tween.tween_method(
		func(p: float) -> void: actor_set_offset.call(thrust_offset * p),
		0.0, 1.0, thrust_dur
	)
	actor_tween.tween_method(
		func(p: float) -> void: actor_set_offset.call(thrust_offset * (1.0 - p)),
		0.0, 1.0, thrust_dur
	)
	actor_tween.tween_callback(func() -> void:
		_view_state.unit_visual_offsets.erase(actor)
		_end_battle_anim()
		_redraw_target.queue_redraw()
	)

	# target 颤抖（与推冲并行）
	_begin_battle_anim()
	var shake_tween: Tween = create_tween()
	shake_tween.tween_method(
		func(p: float) -> void:
			_view_state.unit_visual_offsets[target] = Vector2(
				shake_amp * sin(p * TAU * shake_osc),
				0.0
			)
			_redraw_target.queue_redraw(),
		0.0, 1.0, shake_dur
	)
	shake_tween.tween_callback(func() -> void:
		_view_state.unit_visual_offsets.erase(target)
		_end_battle_anim()
		_redraw_target.queue_redraw()
	)

	# HP 平滑过渡（P1-5 修复）
	_begin_battle_anim()
	_view_state.displayed_hps[target] = hp_before
	var hp_tween: Tween = create_tween()
	hp_tween.tween_method(
		func(v: float) -> void:
			_view_state.displayed_hps[target] = v
			_redraw_target.queue_redraw(),
		hp_before, hp_after, hp_dur
	)
	hp_tween.tween_callback(func() -> void:
		_view_state.displayed_hps.erase(target)
		_end_battle_anim()
		_redraw_target.queue_redraw()
	)

	# 飘字（异步独立生命周期，不入 _anim_count）
	var float_pos: Vector2 = Vector2(
		float(target.battle_position.x * WorldMap.TILE_SIZE) + float(WorldMap.TILE_SIZE) * 0.5,
		float(target.battle_position.y * WorldMap.TILE_SIZE) - 4.0
	)
	BattleFloatText.spawn_damage(
		_redraw_target, float_pos, str(damage),
		_altitude_subtitle(altitude_diff),
		_attack_float_color(counter_factor),
		float_dur
	)


## 跳过 runner：actor 头顶飘字 "跳过" + 锁 HUD 0.6s 等飘字播完
func _run_skip_anim(actor: BattleUnit) -> void:
	var float_pos: Vector2 = Vector2(
		float(actor.battle_position.x * WorldMap.TILE_SIZE) + float(WorldMap.TILE_SIZE) * 0.5,
		float(actor.battle_position.y * WorldMap.TILE_SIZE) - 4.0
	)
	BattleFloatText.spawn_text(
		_redraw_target, float_pos, "跳过", WorldMap.BATTLE_FLOAT_COLOR_SKIP,
		WorldMap.BATTLE_FLOAT_SKIP_DURATION
	)
	_begin_battle_anim()
	var skip_tween: Tween = create_tween()
	skip_tween.tween_interval(WorldMap.BATTLE_FLOAT_SKIP_DURATION)
	skip_tween.tween_callback(func() -> void:
		_end_battle_anim()
		_redraw_target.queue_redraw()
	)


## 死亡 runner：alpha 1 → 0 渐隐 0.3s 后从 dying_units 字典移除
## sink 已占位 alpha=1.0，runner 内仅启动 Tween（兜底再赋一次防御直接调用场景）
func _run_die_anim(unit: BattleUnit) -> void:
	if not _view_state.dying_units.has(unit):
		_view_state.dying_units[unit] = 1.0
	_begin_battle_anim()
	_redraw_target.queue_redraw()
	var fade_tween: Tween = create_tween()
	fade_tween.tween_method(
		func(a: float) -> void:
			_view_state.dying_units[unit] = a
			_redraw_target.queue_redraw(),
		1.0, 0.0, WorldMap.BATTLE_DIE_DURATION
	)
	fade_tween.tween_callback(func() -> void:
		_view_state.dying_units.erase(unit)
		_end_battle_anim()
		_redraw_target.queue_redraw()
	)


## counter_factor → 飘字主行颜色（设计 §8 飘字色板）
func _attack_float_color(counter_factor: float) -> Color:
	if counter_factor > 1.0 + WorldMap.BATTLE_COUNTER_FACTOR_EPS:
		return WorldMap.BATTLE_FLOAT_COLOR_ADV
	if counter_factor < 1.0 - WorldMap.BATTLE_COUNTER_FACTOR_EPS:
		return WorldMap.BATTLE_FLOAT_COLOR_DIS
	return WorldMap.BATTLE_FLOAT_COLOR_NEUTRAL


## altitude_diff → 飘字副行字符串（"+X% 高度" / "-X% 高度" / 空）
##   X = |altitude_diff| * terrain_altitude_step * 100，与 BattleResolver 伤害修正口径一致
func _altitude_subtitle(altitude_diff: int) -> String:
	if altitude_diff == 0:
		return ""
	var pct: int = int(round(absf(float(altitude_diff)) * _terrain_altitude_step * 100.0))
	if altitude_diff > 0:
		return "+%d%% 高度" % pct
	return "-%d%% 高度" % pct
