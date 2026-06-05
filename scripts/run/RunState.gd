class_name RunState
extends RefCounted
## 跨场景整局态（B 重生周期 MVP）
##
## 设计原文：
##   tile-advanture-design/探索体验实装/B_重生周期主框架_MVP.md
##
## 职责：
##   - 维护周期编号 / 重生保护剩余次数（作整局时间轴）
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
## 生命周期对照（L1.3a 阶段 D：cycle 范式退役，run 内已无 reload——一局一张连续世界）：
##   首次进入：_initialized=false → ensure_initialized 写入 hero_pool / 命数 K / 计数清零
##   run 内昏迷复活：原地传送不 reload（L1.2 Phase 3），整局态原样保持，不经 ensure_initialized
##   主动重开（唯一 reload）：_on_restart_pressed 先调 reset() 再 reload_current_scene = 新 run


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

## 当前累计扎营次数；record_camp 时 +1（L1.3a 阶段 D：cycle 范式退役后 == _total_camp_count，
## 冗余保留供 HUD / 调试读取当前扎营计数；不再被任何"周期归零"清零）
static var _current_cycle_camp_count: int = 0

## 重生事件占位标志（昏迷 reload 范式遗留）；L1.3a 阶段 D 后 advance_cycle 退役、已无人置位（冻结保留，
## 不级联清理 WorldMap respawn_intro 信号线）。用 consume_pending_respawn_intro 取值并清零
static var _pending_respawn_intro: bool = false

## L1.3a 阶段 D recruit 适配：已触发过入队的扎营计数集（lifetime 去重）。
## 单图无 cycle，取代原 per-cycle _already_triggered_this_cycle；同一扎营计数命中只触发 1 次入队
static var _already_recruited_camps: Array[int] = []


# ─────────────────────────────────────
# 信号沉降（Callable-sink）
# ─────────────────────────────────────

## 入队事件回调；签名 func(hero_dict: Dictionary, milestone: int) -> void
## hero_dict 来自 hero_pool 行（含 id / name / troop_type / troop_quality 等）
## milestone 是命中的扎营里程碑值，用于叙事文本
##
## C MVP：WorldMap 注册后由 EventPanelUI 承接弹窗；玩家确认后执行装配
static var _on_recruit_triggered_sink: Callable = Callable()

## 据点选定回调（L1.2 Phase 1）；签名 func(pos: Vector2i) -> void
## set_stronghold 命中时触发；Phase 2 由 StrongholdVisionBinding 承接（register 据点 VisionSource）
## Phase 1 暂无订阅方（仅数据 + UI 流程），sink 为空 noop
static var _on_stronghold_set_sink: Callable = Callable()


# ─────────────────────────────────────
# 据点（L1.2 Phase 1）
# ─────────────────────────────────────

## 当前局玩家选定的据点格坐标（Vector2i 世界格）
## 未选定时 _stronghold_pos 值无意义，须由 _has_stronghold 判定（避免 sentinel 值耦合，
## 与现有 _initialized / _pending_*_intro 命名风格一致）
## 命名用 position 语义（与 PersistentSlot.position 字段对齐；设计文档伪代码 s.tile 为笔误）
static var _stronghold_pos: Vector2i = Vector2i.ZERO

## 据点是否已选定
static var _has_stronghold: bool = false


# ─────────────────────────────────────
# L1.3a 扎营主时钟 / 命数独立 / climax（子 MVP ① 阶段 A 数据层）
# ─────────────────────────────────────
##
## 阶段 A 立数据层（字段 + 查询 + 注入/清零）；阶段 B 已切换命数消费方
## （respawns_left / consume_respawn_life 走 _respawns_remaining，脱钩 cycle）。
## 剩余 cycle 方法退役 + climax 实际触发由阶段 C/D 完成（设计 §10）。
## 设计原文：tile-advanture-design/无限地图实装/L1.3a_扎营时钟与胜负模型_MVP.md §3.1

## 整局累计扎营次数（lifetime，不随任何"周期"清零；取代 _cycle_index 作主时钟）
## record_camp 时 +1；advance_cycle / consume_respawn_life 均不动此值
static var _total_camp_count: int = 0

## 命数独立计数（脱钩 cycle，收口待跟踪 §十六 P1-2）：无据点昏迷复活容错预算
## ensure_initialized 注入 run_cfg.no_stronghold_respawns（默认 K=3）；
## 阶段 B 已接通消费方：respawns_left 读它、consume_respawn_life 扣它（无据点复活 -1）
static var _respawns_remaining: int = 3

## climax 已触发标志（一局一次，防重复 spawn boss）；阶段 C 接 EC 扎营触发后写入
static var _climax_triggered: bool = false


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
##
## L1.3a 阶段 A：新增可选参 no_stronghold_respawns_value 注入命数独立计数（默认 3 保持向后兼容，
## 老调用方 / 测试不传时退回默认；MapBootstrap 显式传 run_cfg.no_stronghold_respawns）
static func ensure_initialized(max_cycles_value: int, hero_pool_rows: Array, rng: RandomNumberGenerator, no_stronghold_respawns_value: int = 3) -> void:
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
	_current_cycle_camp_count = 0
	_pending_respawn_intro = false
	_already_recruited_camps = []
	# L1.2 Phase 1：据点跨周期 reload 保留靠 _initialized=true 直接 return（上方 line 112-113）；
	# 此处清零是"首次进入"的初始态，与 _used_hero_ids / _cycle_index 同语义
	_stronghold_pos = Vector2i.ZERO
	_has_stronghold = false
	# L1.3a 阶段 A：扎营主时钟 / 命数独立 / climax 标志的"首次进入"初始态
	_total_camp_count = 0
	_respawns_remaining = maxi(0, no_stronghold_respawns_value)
	_climax_triggered = false
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
static func reset() -> void:
	_initialized = false
	_hero_pool = []
	_used_hero_ids = []
	_cycle_index = 0
	_current_cycle_camp_count = 0
	_pending_respawn_intro = false
	_already_recruited_camps = []
	# L1.2 Phase 1：整局重开清据点（与 _used_hero_ids 等整局态同语义）
	_stronghold_pos = Vector2i.ZERO
	_has_stronghold = false
	# L1.3a 阶段 A：清零扎营主时钟 / 命数 / climax；命数由下一次 ensure_initialized 按 run_cfg 重新注入
	_total_camp_count = 0
	_respawns_remaining = 0
	_climax_triggered = false
	# _max_cycles 不重设；下一次 ensure_initialized 会按新配置覆盖


# ─────────────────────────────────────
# 周期 / 重生保护查询
# ─────────────────────────────────────

## 当前周期编号（L1.3a 阶段 D：cycle 范式退役，_cycle_index 冻结在 0——无人推进；
## 保留访问器供 EnemyReinforcement 抽 tier / MapBootstrap / ReinforcementRoster 读固定单图配置；
## tier 随周期递增的逻辑退役，敌方威胁改扎营时钟驱动留子 MVP ②）
static func cycle_index() -> int:
	return _cycle_index


## 整局最多周期数（L1.3a 阶段 D：cycle 退役后冻结，仅 ensure_initialized 签名兼容保留）
static func max_cycles() -> int:
	return _max_cycles


## 剩余重生保护次数
##
## L1.3a 阶段 B「命数源切换」：从 cycle 派生（max-1-cycle）切到独立计数 _respawns_remaining，
## 脱钩 cycle（收口待跟踪 §十六 P1-2）。活调用方（WorldMap 火苗 / PlayerLifecycle 复活门槛）透明跟随，
## 调用点无需改动；语义不变（"还剩几条命"），仅起始值由 cycle 派生改为 run_cfg 注入的 K。
static func respawns_left() -> int:
	return _respawns_remaining


# ─────────────────────────────────────
# L1.3a 扎营主时钟 / 命数独立 / climax 查询（阶段 A）
# ─────────────────────────────────────

## 整局累计扎营次数（lifetime 主时钟）；阶段 C climax 触发判定 / 阶段 D recruit 适配读此值
static func total_camp_count() -> int:
	return _total_camp_count


## 命数独立计数当前值（脱钩 cycle）；阶段 B respawns_left 切到此源后供 UI / 门槛读取
static func respawns_remaining() -> int:
	return _respawns_remaining


## climax 是否已触发（一局一次）
static func is_climax_triggered() -> bool:
	return _climax_triggered


## 标记 climax 已触发；阶段 C 由 EC 扎营计数命中 climax_camp_threshold 时调用（幂等）
static func mark_climax_triggered() -> void:
	_climax_triggered = true


# ─────────────────────────────────────
# 命数消耗（L1.2 Phase 3 / L1.3a 阶段 B）
# ─────────────────────────────────────
#
# L1.3a 阶段 D：cycle 范式退役——advance_cycle / advance_cycle_on_victory 已移除
# （周期推进 + run 内 reload 整体退役，一局一张连续世界；唯一 reload = 玩家"重开"= 新 run）。

## L1.2 Phase 3 / L1.3a 阶段 B：无据点昏迷复活——扣 1 命数（不 reload、不重抽队长）
##
## L1.3a 阶段 B「命数源切换」：从"推 _cycle_index"改为"独立计数 _respawns_remaining -= 1"，
## 彻底脱钩 cycle（收口待跟踪 §十六 P1-2，修订 L1.2 拍板表 row 11——命数不移除，改作无据点容错预算）。
##   - 不再推 _cycle_index：扣命数不再污染敌方强度（EnemyReinforcement 读 cycle_index）/ 地图配置行
##   - 不置 _pending_respawn_intro：无新场景消费（不 reload）
##   - maxi(0, …) 兜底：归零后不为负；归零时下一次昏迷由 PlayerLifecycle 走失败①（respawns_left == 0 分支）
static func consume_respawn_life() -> void:
	_respawns_remaining = maxi(0, _respawns_remaining - 1)


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


## 按 hero_id 查 hero_pool 行（浅拷贝，外部修改不穿透）
##
## 入口 2 MVP 2.1 议题 5（2026-05-10）：让 WorldMap 在不重复加载 csv 的前提下
## 读取 coma_narrative / respawn_narrative 等扩展字段
##
## 未找到（id 越界或池空）返回空 Dictionary
static func find_hero_row(hero_id: int) -> Dictionary:
	if hero_id < 0:
		return {}
	for row in _hero_pool:
		if int(row.get("id", "-1")) == hero_id:
			return row.duplicate()
	return {}


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

## 累加扎营次数；由 EC.start_camp 调用
## L1.3a：同步累加 lifetime 主时钟 _total_camp_count（climax 触发 + recruit 适配读它）；
## _current_cycle_camp_count 冗余跟随（cycle 退役后无归零方，== _total_camp_count）
static func record_camp() -> void:
	_current_cycle_camp_count += 1
	_total_camp_count += 1


## 当前累计扎营次数（HUD / 调试用；== total_camp_count）
static func get_current_cycle_camp_count() -> int:
	return _current_cycle_camp_count


# ─────────────────────────────────────
# 扎营里程碑入队（C MVP）
# ─────────────────────────────────────

## 检查 lifetime 扎营主时钟是否命中招募里程碑（L1.3a 阶段 D recruit 适配）
##
## 取代原 per-cycle _camp_milestones 判定（cycle 退役后 milestone 数组已移除）：
## 改为对全局扎营计数 _total_camp_count 按 interval 取模——每累计 interval 次扎营触发一次入队。
## interval 由调用方（EC）从 run_cfg.recruit_camp_interval 注入（RunState 静态类不直接持配置）。
##
## 命中条件：
##   - interval > 0 且 _total_camp_count > 0 且 _total_camp_count % interval == 0
##   - 且该扎营计数不在 _already_recruited_camps（lifetime 去重，幂等防同次重复）
##
## 命中处置同原逻辑：先标去重 → draw_recruit → 抽到则 sink，抽不到静默跳过（设计文档 §7 场景 5）。
##
## 设计文档：L1.3a_扎营时钟与胜负模型_MVP §3.2 / [[C_扎营里程碑入队_MVP]] §3 / §7
static func check_recruit_milestone(teammates_ids: Array[int], interval: int) -> void:
	# 1. 命中检查：lifetime 扎营计数命中 interval 倍数
	if interval <= 0 or _total_camp_count <= 0 or _total_camp_count % interval != 0:
		return
	var milestone: int = _total_camp_count
	if _already_recruited_camps.has(milestone):
		return
	# 2. 标记已触发；放在抽取之前，保证英雄池耗尽时也不会无限重试
	_already_recruited_camps.append(milestone)
	# 3. 抽人
	var hero_dict: Dictionary = draw_recruit(teammates_ids)
	if hero_dict.is_empty():
		push_warning("RunState.check_recruit_milestone: 命中扎营 %d 但英雄池已耗尽，静默跳过" % milestone)
		return
	# 4. 触发回调
	if _on_recruit_triggered_sink.is_valid():
		_on_recruit_triggered_sink.call(hero_dict, milestone)
	else:
		push_warning("RunState.check_recruit_milestone: sink 未注册，入队事件未分发（扎营 %d）" % milestone)


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

## 注册据点选定回调（L1.2 Phase 1）；多次调用以最后一次为准
## 签名 func(pos: Vector2i) -> void；Phase 2 由 StrongholdVisionBinding 承接
static func register_stronghold_set_sink(sink: Callable) -> void:
	_on_stronghold_set_sink = sink


# ─────────────────────────────────────
# 据点查询 / 设定（L1.2 Phase 1）
# ─────────────────────────────────────

## 据点是否已选定
static func has_stronghold() -> bool:
	return _has_stronghold


## 据点格坐标（调用方需先 has_stronghold 守卫；未选定时返回值无意义）
static func stronghold_pos() -> Vector2i:
	return _stronghold_pos


## 选定据点；写入位置 + 标记 + 触发 sink 通知订阅方（Phase 2 视野绑定）
## MVP 一次性选定（不可更换）——调用方（EC._resolve_stronghold_prompt）已用 has_stronghold 守卫
static func set_stronghold(pos: Vector2i) -> void:
	_stronghold_pos = pos
	_has_stronghold = true
	if _on_stronghold_set_sink.is_valid():
		_on_stronghold_set_sink.call(pos)


## 清理回调（场景 _exit_tree 时调用）
## 注意：仅清回调，不清整局态——重生场景重载时整局态必须保留
static func clear_sinks() -> void:
	_on_recruit_triggered_sink = Callable()
	_on_stronghold_set_sink = Callable()


# ─────────────────────────────────────
# 内部
# ─────────────────────────────────────

## RNG 兜底：极端时序下（未走 ensure_initialized 直接调 draw_new_leader）建一个 randomize 的 fallback
static func _ensure_rng() -> RandomNumberGenerator:
	if _rng == null:
		_rng = RandomNumberGenerator.new()
		_rng.randomize()
	return _rng
