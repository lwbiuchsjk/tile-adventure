class_name RunState
extends RefCounted
## 跨场景整局态（B 重生周期 MVP）
##
## 设计原文：
##   tile-advanture-design/探索体验实装/B_重生周期主框架_MVP.md
##
## 职责：
##   - 维护周期编号 / 重生保护剩余次数（替代 RoundManager 多轮关卡作整局时间轴）
##   - 英雄池抽取（draw_new_leader 从未使用池里挑一个标 used 后返回）
##   - 累积扎营里程碑（数据结构在本期定义；实际填写由 [[C_扎营里程碑入队_MVP]] 完成）
##   - 重生事件占位标志（_pending_respawn_intro 由新场景 _ready 消费做"新指挥官接过指挥权"提示）
##
## 架构选择（与 VictoryJudge / DayNightState 对齐）：
##   静态类 + Callable 沉降回调
##   - 避免 Autoload 污染 project.godot
##   - 对 headless 测试友好（无需 SceneTree 即可触发）
##   - WorldMap._exit_tree 调 clear_sinks 清回调，不清整局态（重生场景重载需要保持 _used_hero_ids / _cycle_index）
##   - 玩家主动重开走 reset()，把整局态 + _initialized 一并清掉
##
## 生命周期对照：
##   首次进入：_initialized=false → ensure_initialized 写入 max_cycles / hero_pool / 计数清零
##   重生 reload：advance_cycle 后 reload_current_scene；新 _ready 调 ensure_initialized 时
##                _initialized=true 直接 return，整局态保持
##   主动重开：_on_restart_pressed 先调 reset() 再 reload_current_scene


# ─────────────────────────────────────
# 静态字段（跨场景态）
# ─────────────────────────────────────

## 是否已完成首次初始化；reset() 清掉，ensure_initialized 写入
static var _initialized: bool = false

## 英雄池（来自 hero_pool.csv）；reset 清空，ensure_initialized 重新写入
## 元素结构：{id: int, name: String, troop_type: String, troop_quality: String}
static var _hero_pool: Array[Dictionary] = []

## 已担任过队长的英雄 ID 列表
static var _used_hero_ids: Array[int] = []

## 当前周期编号（0 = 首发；max_cycles - 1 = 末周期无保护）
static var _cycle_index: int = 0

## 整局最多周期数（含末周期）；ensure_initialized 写入
static var _max_cycles: int = 3

## 累积扎营里程碑列表（每个周期结束时 push 当前周期扎营计数）
## 结构定义在 B 期，填写 / 触发由 [[C_扎营里程碑入队_MVP]] 实装
static var _camp_milestones: Array[int] = []

## 当前周期内累计扎营次数（advance_cycle 时归零）
static var _current_cycle_camp_count: int = 0

## 重生事件占位标志：advance_cycle 时置 true，新场景 _ready 消费后清零
## 用 consume_pending_respawn_intro 取值并清零，避免读写两步
static var _pending_respawn_intro: bool = false

## 本周期已触发过入队事件的里程碑值；advance_cycle / reset 时清空
## 用途：去重保护——同周期内即使 _camp_milestones 含重复值（如 [5, 3, 5]），
## 当前周期到达扎营第 5 次时只触发 1 次入队事件
##
## 设计文档：[[C_扎营里程碑入队_MVP]] §2「同周期同数值不重复触发」
static var _already_triggered_this_cycle: Array[int] = []


# ─────────────────────────────────────
# 信号沉降（Callable-sink）
# ─────────────────────────────────────

## 周期推进回调；签名 func(previous_cycle: int, new_cycle: int) -> void
## C MVP 入队事件 / D MVP 阶段切换都可挂在这里；当前 B MVP 不强依赖
static var _on_cycle_advance_sink: Callable = Callable()

## 入队事件回调；签名 func(hero_dict: Dictionary, milestone: int) -> void
## hero_dict 来自 hero_pool 行（含 id / name / troop_type / troop_quality 等）
## milestone 是命中的扎营里程碑值，用于叙事文本
##
## C MVP：WorldMap 注册后由 EventPanelUI 承接弹窗；玩家确认后执行装配
static var _on_recruit_triggered_sink: Callable = Callable()


# ─────────────────────────────────────
# RNG
# ─────────────────────────────────────

## 抽队长用的随机源；ensure_initialized 注入；调用方未传时内部新建并 randomize
## 设计取舍：与 _world_rng 隔离 —— 重生抽队长不应受地图 PCG seed 干扰
static var _rng: RandomNumberGenerator = null


# ─────────────────────────────────────
# 初始化 / 重置
# ─────────────────────────────────────

## 首次进入或重生场景重载时调用
## - _initialized=false：写入 max_cycles / hero_pool / 全部计数清零
## - _initialized=true：原样返回（重生 reload 走到这里，保持 _used_hero_ids / _cycle_index 等）
##
## hero_pool_rows 期望来自 ConfigLoader.load_csv("hero_pool.csv")；浅拷贝以避免外部修改穿透
static func ensure_initialized(max_cycles_value: int, hero_pool_rows: Array, rng: RandomNumberGenerator) -> void:
	if _initialized:
		return
	_max_cycles = maxi(1, max_cycles_value)
	# ConfigLoader.load_csv 返回无类型 Array，逐行强转为 Dictionary 写入 typed _hero_pool
	# 这样后续读取 _hero_pool 时无需再次 cast，对齐项目 CLAUDE.md 类型化规范
	_hero_pool = []
	for entry in hero_pool_rows:
		_hero_pool.append(entry as Dictionary)
	_used_hero_ids = []
	_cycle_index = 0
	_camp_milestones = []
	_current_cycle_camp_count = 0
	_pending_respawn_intro = false
	_already_triggered_this_cycle = []
	# rng 缺省时内部建一个并 randomize；显式传入时保留调用方掌控
	if rng == null:
		var fallback: RandomNumberGenerator = RandomNumberGenerator.new()
		fallback.randomize()
		_rng = fallback
	else:
		_rng = rng
	_initialized = true


## 整局重置（玩家主动重开）
## - _initialized 清空，下一次 ensure_initialized 重新写入
## - _used_hero_ids / _camp_milestones 等整局态清掉
## - rng 保留：重开后随机仍延续——不强行 reseed 避免"重开恰好抽到同一队长"看起来像 bug
##
## 注意：本函数不清 _on_cycle_advance_sink；那是场景生命周期范畴，由 clear_sinks 处理
static func reset() -> void:
	_initialized = false
	_hero_pool = []
	_used_hero_ids = []
	_cycle_index = 0
	_camp_milestones = []
	_current_cycle_camp_count = 0
	_pending_respawn_intro = false
	_already_triggered_this_cycle = []
	# _max_cycles 不重设；下一次 ensure_initialized 会按新配置覆盖


# ─────────────────────────────────────
# 周期 / 重生保护查询
# ─────────────────────────────────────

## 当前周期编号
static func cycle_index() -> int:
	return _cycle_index


## 整局最多周期数
static func max_cycles() -> int:
	return _max_cycles


## 是否处于末周期（无重生保护）
static func is_last_cycle() -> bool:
	return _cycle_index >= _max_cycles - 1


## 剩余重生保护次数（末周期返回 0）
static func respawns_left() -> int:
	return maxi(0, _max_cycles - 1 - _cycle_index)


# ─────────────────────────────────────
# 周期推进
# ─────────────────────────────────────

## 推进到下一周期
## - 当前周期扎营计数 push 入 milestones（C MVP 后续读取）
## - cycle_index += 1
## - 置 _pending_respawn_intro = true，给新场景 _ready 看
## - 触发 _on_cycle_advance_sink 通知订阅方（若有）
##
## 调用方约定：本函数只动数据；reload_current_scene 等场景操作由调用方负责
static func advance_cycle() -> void:
	_camp_milestones.append(_current_cycle_camp_count)
	_current_cycle_camp_count = 0
	var prev: int = _cycle_index
	_cycle_index += 1
	_pending_respawn_intro = true
	# C MVP：新周期重新累计入队触发；不清 _camp_milestones（跨周期累积是设计意图）
	_already_triggered_this_cycle = []
	if _on_cycle_advance_sink.is_valid():
		_on_cycle_advance_sink.call(prev, _cycle_index)


# ─────────────────────────────────────
# 英雄池抽取
# ─────────────────────────────────────

## 从未使用英雄池中随机抽一个，标 used 后返回该行的浅拷贝
##
## 兜底：未使用候选为空时（max_cycles > hero_pool.size 时可能触发）允许重复，全池随机
## MVP 数据约束：hero_pool ≥ 4 + max_cycles=3，正常路径不会进入兜底
static func draw_new_leader() -> Dictionary:
	if _hero_pool.is_empty():
		push_error("RunState.draw_new_leader: _hero_pool 为空，无法抽取队长")
		return {}
	# 收集未使用候选
	var candidates: Array[Dictionary] = []
	for row in _hero_pool:
		var hero_id: int = int(row.get("id", "-1"))
		if hero_id < 0:
			continue
		if not _used_hero_ids.has(hero_id):
			candidates.append(row)
	# 兜底：未使用池空 → 允许重复，从全池抽
	if candidates.is_empty():
		push_warning("RunState.draw_new_leader: 未使用英雄池已空，进入允许重复兜底分支")
		candidates = _hero_pool
	var rng: RandomNumberGenerator = _ensure_rng()
	var idx: int = rng.randi_range(0, candidates.size() - 1)
	var picked: Dictionary = candidates[idx]
	var picked_id: int = int(picked.get("id", "-1"))
	# 标 used；兜底分支抽到已 used 时不重复 append
	if picked_id >= 0 and not _used_hero_ids.has(picked_id):
		_used_hero_ids.append(picked_id)
	return picked.duplicate()


## 已使用英雄 ID 列表浅拷贝（防止外部修改穿透）
static func active_used_hero_ids() -> Array[int]:
	return _used_hero_ids.duplicate()


# ─────────────────────────────────────
# 重生事件占位
# ─────────────────────────────────────

## 取值并清零（同一帧内幂等）；新场景 _ready 调一次决定是否播 "新指挥官接过指挥权" 占位
## 用 consume 模式而非 read + clear 两步，避免读写竞争
static func consume_pending_respawn_intro() -> bool:
	var v: bool = _pending_respawn_intro
	_pending_respawn_intro = false
	return v


## 只读查询（不清零）；调试 / 日志使用
static func is_pending_respawn_intro() -> bool:
	return _pending_respawn_intro


# ─────────────────────────────────────
# 扎营计数（C MVP 实装填写）
# ─────────────────────────────────────

## 累加当前周期扎营次数；由 WorldMap._start_camp 调用
## advance_cycle 时该值 push 入 milestones 后归零
static func record_camp() -> void:
	_current_cycle_camp_count += 1


## 累积里程碑列表浅拷贝（C MVP 入队判定用）
static func get_milestones_snapshot() -> Array[int]:
	return _camp_milestones.duplicate()


## 当前周期内已累计的扎营次数
static func get_current_cycle_camp_count() -> int:
	return _current_cycle_camp_count


# ─────────────────────────────────────
# 扎营里程碑入队（C MVP）
# ─────────────────────────────────────

## 检查当前 _current_cycle_camp_count 是否命中累积里程碑
##
## 命中条件：
##   - _current_cycle_camp_count 出现在 _camp_milestones 中
##   - 且 _current_cycle_camp_count 不在 _already_triggered_this_cycle 中
##
## 命中时：
##   1. 把当前值标入 _already_triggered_this_cycle（即使后续抽人为空，也不重试，避免无限触发）
##   2. 调 draw_recruit 抽一个不在队伍中的英雄；teammates_ids 由调用方提供
##   3. 抽到 → 调 _on_recruit_triggered_sink(hero_dict, milestone)
##   4. 抽不到（英雄池耗尽）→ 静默跳过 + push_warning（设计文档 §7 场景 5）
##
## 设计文档：[[C_扎营里程碑入队_MVP]] §3 / §7
static func check_recruit_milestone(teammates_ids: Array[int]) -> void:
	var milestone: int = _current_cycle_camp_count
	# 1. 命中检查
	if not _camp_milestones.has(milestone):
		return
	if _already_triggered_this_cycle.has(milestone):
		return
	# 2. 标记本周期已触发；放在抽取之前，保证英雄池耗尽时也不会无限重试
	_already_triggered_this_cycle.append(milestone)
	# 3. 抽人
	var hero_dict: Dictionary = draw_recruit(teammates_ids)
	if hero_dict.is_empty():
		push_warning("RunState.check_recruit_milestone: 命中 milestone=%d 但英雄池已耗尽，静默跳过" % milestone)
		return
	# 4. 触发回调
	if _on_recruit_triggered_sink.is_valid():
		_on_recruit_triggered_sink.call(hero_dict, milestone)
	else:
		push_warning("RunState.check_recruit_milestone: sink 未注册，入队事件未分发（milestone=%d）" % milestone)


## 抽取一个不在队伍中的随机英雄
##
## teammates_ids：当前队伍的 hero_id 列表（CharacterData.hero_id）
##
## 与 draw_new_leader 的区别：
##   - draw_new_leader 排除 _used_hero_ids（曾担任过队长的）—— 重生时抽队长用
##   - draw_recruit 仅排除当前在队 —— 入队事件用，曾担任过队长的英雄可能再次以队员身份回归
##
## 返回空 Dictionary 表示池已耗尽（所有 hero_pool 英雄都已在队）
static func draw_recruit(teammates_ids: Array[int]) -> Dictionary:
	if _hero_pool.is_empty():
		push_warning("RunState.draw_recruit: _hero_pool 为空")
		return {}
	var candidates: Array[Dictionary] = []
	for row in _hero_pool:
		var hero_id: int = int(row.get("id", "-1"))
		if hero_id < 0:
			continue
		if not teammates_ids.has(hero_id):
			candidates.append(row)
	if candidates.is_empty():
		# 设计 §7 场景 5：英雄池耗尽 → 静默跳过；调用方靠返回空判断
		return {}
	var rng: RandomNumberGenerator = _ensure_rng()
	var idx: int = rng.randi_range(0, candidates.size() - 1)
	return (candidates[idx] as Dictionary).duplicate()


## 注册入队事件回调；多次调用以最后一次为准
## 签名 func(hero_dict: Dictionary, milestone: int) -> void
static func register_recruit_sink(sink: Callable) -> void:
	_on_recruit_triggered_sink = sink


# ─────────────────────────────────────
# 信号回调
# ─────────────────────────────────────

## 注册周期推进回调；多次调用以最后一次为准
## 签名 func(previous_cycle: int, new_cycle: int) -> void
static func register_cycle_advance_sink(sink: Callable) -> void:
	_on_cycle_advance_sink = sink


## 清理回调（场景 _exit_tree 时调用）
## 注意：仅清回调，不清整局态——重生场景重载时整局态必须保留
static func clear_sinks() -> void:
	_on_cycle_advance_sink = Callable()
	_on_recruit_triggered_sink = Callable()


# ─────────────────────────────────────
# 内部
# ─────────────────────────────────────

## RNG 兜底：极端时序下（未走 ensure_initialized 直接调 draw_new_leader）建一个 randomize 的 fallback
static func _ensure_rng() -> RandomNumberGenerator:
	if _rng == null:
		_rng = RandomNumberGenerator.new()
		_rng.randomize()
	return _rng
