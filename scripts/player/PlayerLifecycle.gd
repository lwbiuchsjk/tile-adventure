class_name PlayerLifecycle
extends Node
## 玩家 lifecycle 子系统（MVP-δ 阶段 2 抽出）
##
## 设计原文：
##   tile-advanture-design/代码健康度回看/MVP-δ_拆分批2.md §核心概念 - PlayerLifecycle
##
## 职责：
##   - 玩家角色 / 队伍状态（_characters / _total_max_hp / _leader_display_name）
##   - 队长抽取 + 初始部队装配（原 _init_player）
##   - 文案构造（原 _format_coma_line / _format_respawn_line_for_current_leader）
##   - 兵种 / 品质解析（原 _parse_troop_type / _parse_troop_quality）
##   - 队员入队（原 _on_recruit_confirmed 末尾的 append 部分 → add_character）
##   - 队伍状态评估（原 _evaluate_party_state）
##   - 昏迷触发 + 末周期失败（原 _trigger_coma_or_lose）
##
## 与 UI 系统 + 场景生命周期完整解耦（MVP-δ codex review P1 修复）：
##   所有 UI 调用（OverlayTransitionUI.play / VictoryUI / VictoryJudge）通过 signal 发出，
##   由 WorldMap 接 sink 后调用对应 autoload / 节点。
##   COMA 重生流的 midpoint 闭包（含 RunState.advance_cycle + reload_current_scene +
##   返回 OverlayTransitionUI.world_ready）整体由 WorldMap 在 sink handler 内构造，
##   PlayerLifecycle 不引用 OverlayTransitionUI / get_tree().reload —— 彻底独立于 UI/场景。
##
## 职责切分：
##   PlayerLifecycle = 队伍/coma 状态判定 + 发信号
##   WorldMap        = UI 过渡 + 场景 reload + 时序协调


# ─────────────────────────────────────────
# 信号（与 UI / VictoryJudge 解耦）
# ─────────────────────────────────────────

## 队长昏迷复活触发（L1.2 Phase 3：取代原 coma_triggered 的 reload 范式）
##
## 设计：tile-advanture-design/无限地图实装/L1.2_多源视野与据点机制_MVP.md §2.3 / §5 改动 4
## 三条复活路径统一走本信号（target_pos = 传送目标）：
##   - is_stronghold == true ：有效据点 → 零代价原地传送（不扣命数、不 reload、简版黑屏无火苗）
##   - is_stronghold == false：无据点 fallback → 扣命数（deduct_life）+ 原地传送（不 reload、火苗显示）
## WorldMap 接 sink → 构造"传送 midpoint"闭包（不 reload）+ 播 OverlayTransitionUI.play
##
## 与原 coma_triggered（MVP-δ）的区别：原范式 midpoint 内 advance_cycle + reload_current_scene 重生整图；
## L1.2 据点机制要求"昏迷不重置地图"，故 reload 范式整体退役，分流决策前移到 trigger_coma_or_lose 内
signal coma_respawn_triggered(target_pos: Vector2i, deduct_life: bool, is_stronghold: bool)

## 末周期失败触发（_trigger_coma_or_lose 内 respawns_left == 0 分支）
## WorldMap 接 sink → 调 _on_victory_decided(faction) 走 VictoryUI 失败遮罩
signal defeat_triggered(faction: int)

## 新场景启动时 respawn 文案就绪（setup 内消费 _pending_respawn_intro 命中）
## WorldMap 接 sink → 调 OverlayTransitionUI.notify_world_ready(1, respawn_line)
signal respawn_intro_ready(respawn_line: String)

## 新场景启动时周期胜利推进就绪（L1.3）：setup 内消费 _pending_cycle_victory_intro 命中
## WorldMap 接 sink → 调 OverlayTransitionUI.notify_world_ready() 解除 phase B await
## （周期胜利文案在 WorldMap 过渡触发时已构造，队长跨周期不变，故本信号无需传文案）
signal cycle_victory_intro_ready()


# ─────────────────────────────────────────
# 状态
# ─────────────────────────────────────────

## 玩家角色列表（_characters[0] 是队长，其余为入队队员）
var _characters: Array[CharacterData] = []
## 队伍总最大 hp 累计（HUD 显示 + 评分计算用）
var _total_max_hp: int = 0
## 当前队长显示名（来自 RunState.draw_new_leader 的 hero_pool 行 name 字段）
var _leader_display_name: String = ""
## 昏迷态守门：true 期间锁所有输入，等 OverlayTransitionUI midpoint 走完后 reload 场景
var _is_in_coma: bool = false
## 队长昏迷阈值（current_hp / max_hp ≤ 该值触发昏迷）；setup 时由 run_cfg 注入
var _coma_hp_threshold_ratio: float = 0.2
## 昏迷过渡持续秒数（OverlayTransitionUI phase A → midpoint 间隔参考值）；setup 时由 run_cfg 注入
var _coma_duration_sec: float = 1.5
## L1.2 Phase 3：昏迷复活目标解析器（由 WorldMap 注入；PlayerLifecycle 不持 _world_map / 持久 slot 引用）
## 返回 Dictionary {has_stronghold: bool, stronghold_pos: Vector2i, fallback_pos: Vector2i}
## 据点校验（slot 仍为 CORE_TOWN/PLAYER）+ fallback 最近占领 slot 解析都在 WorldMap 侧（数据在手边）
var _coma_respawn_resolver: Callable = Callable()


# ─────────────────────────────────────────
# 公开接口
# ─────────────────────────────────────────

## 初始化（WorldMap._ready → _init_subsystems 调一次）
##
## 流程：
##   1. 从 run_cfg 注入 coma 配置（hp 阈值 + 过渡时长）
##   2. 从 RunState.draw_new_leader 抽队长 + 装配初始部队
##   3. consume RunState._pending_respawn_intro：命中则 emit respawn_intro_ready signal
##
## 参数 player_cfg 保留作未来 hero_pool 缺省时的兜底字段来源；本期仅读 initial_troop_quality
func setup(player_cfg: PlayerParamResource, run_cfg: RunParamResource) -> void:
	_coma_duration_sec = run_cfg.coma_duration_sec
	_coma_hp_threshold_ratio = run_cfg.coma_hp_threshold_ratio

	# 默认品质：hero_pool 行未填或解析失败时回退
	var default_quality: int = player_cfg.initial_troop_quality

	_characters = []
	_total_max_hp = 0

	# L1.3 周期胜利目标：先判断是否周期胜利推进（保留队长）——优先于昏迷重生（抽新队长）
	# 一次只有一种推进；命中胜利推进则从 RunState 快照重建队长，否则走 draw_new_leader
	# consumed_cycle_victory 记录"原始 pending 命中"——即使快照为空退回抽新队长，过渡仍按周期胜利分支解除 await（P1-2）
	var consumed_cycle_victory: bool = RunState.consume_pending_cycle_victory_intro()
	var is_cycle_victory: bool = consumed_cycle_victory
	var victory_snapshot: Dictionary = {}
	if consumed_cycle_victory:
		victory_snapshot = RunState.get_victory_leader_snapshot()
		if victory_snapshot.is_empty():
			# 异常兜底：标志命中但快照为空 → 队长重建退回抽新队长（但过渡仍走胜利分支 emit，见末尾）
			push_error("PlayerLifecycle.setup: 周期胜利标志命中但快照为空，退回 draw_new_leader")
			is_cycle_victory = false

	# 队长来源：胜利推进用快照 hero_id 查行（拿 name 等展示字段）；否则从 RunState 抽未使用英雄
	# RunState.ensure_initialized 已在 _ready 早期调用过；此处直接 draw / 查行
	var leader_row: Dictionary
	if is_cycle_victory:
		var snap_hero_id: int = int(victory_snapshot.get("hero_id", -1))
		leader_row = RunState.find_hero_row(snap_hero_id)
		if leader_row.is_empty():
			leader_row = {"id": snap_hero_id, "name": "队长"}
	else:
		leader_row = RunState.draw_new_leader()
	_leader_display_name = String(leader_row.get("name", "队长"))

	# 单角色：队长占据 _characters[0]，其余空位由 C MVP 入队事件追加
	var ch: CharacterData = CharacterData.new()
	ch.id = 1
	# C MVP：写入 hero_id，让 draw_recruit 能正确排除当前在队英雄
	ch.hero_id = int(leader_row.get("id", "-1"))
	var troop: TroopData = TroopData.new()
	if is_cycle_victory:
		# 周期胜利：用快照兵种 + 已 +1 封顶的品质重建；TroopData.new() 默认 current_hp==max_hp 即满血
		troop.troop_type = int(victory_snapshot.get("troop_type", 0)) as TroopData.TroopType
		troop.quality = int(victory_snapshot.get("quality", 0)) as TroopData.Quality
	else:
		troop.troop_type = parse_troop_type(String(leader_row.get("troop_type", "SWORD")))
		troop.quality = parse_troop_quality(String(leader_row.get("troop_quality", "")), default_quality)
	ch.troop = troop
	_total_max_hp += troop.max_hp
	_characters.append(ch)

	# 推进事件占位（B MVP 重生 → 入口 2 MVP 2.1 / L1.3 周期胜利）
	# 新场景 setup 末尾消费一次；emit signal 让 WorldMap 调 OverlayTransitionUI.notify_world_ready
	# PlayerLifecycle 不直接依赖 UI 系统
	if consumed_cycle_victory:
		# L1.3：周期胜利文案已由 WorldMap 在过渡触发时（reload 前）构造，这里仅发信号解除 phase B await
		# P1-2（codex）：用 consumed_cycle_victory（原始命中）而非 is_cycle_victory——快照空退回抽新队长时仍 emit，避免 timeout
		cycle_victory_intro_ready.emit()
	elif RunState.consume_pending_respawn_intro():
		var respawn_line: String = format_respawn_line_for_current_leader(leader_row)
		respawn_intro_ready.emit(respawn_line)


## 当前是否处于昏迷过渡态
func is_in_coma() -> bool:
	return _is_in_coma


## L1.2 Phase 3：注册昏迷复活目标解析器（MapBootstrap 在 setup 前接线）
func register_coma_respawn_resolver(resolver: Callable) -> void:
	_coma_respawn_resolver = resolver


## L1.2 Phase 3：解除昏迷锁
##
## 原 coma 路径靠 reload_current_scene 重建 PlayerLifecycle 实例（新实例 _is_in_coma 默认 false）来解锁；
## L1.2 传送路径不 reload → 同一实例，须在 OverlayTransitionUI 过渡播完后由 WorldMap sink 显式调用，
## 否则 _is_in_coma 永久 true 锁死所有输入（_unhandled_key_input / _on_abandon 等守卫）
func clear_coma() -> void:
	_is_in_coma = false


## 当前队长显示名
func current_leader_name() -> String:
	return _leader_display_name


## 队伍总最大 hp（HUD / 评分用）
func total_max_hp() -> int:
	return _total_max_hp


## 队长昏迷阈值（current_hp / max_hp ≤ 该值触发昏迷）
## BattleSession.start 调用方读，用于在战斗内判定队长是否进入 COMA
func coma_hp_threshold_ratio() -> float:
	return _coma_hp_threshold_ratio


## 玩家角色列表（_characters[0] 是队长）
##
## 注：返回引用，调用方可 mutate（与 MVP-β WorldView.get_level_slots 同源问题）；
## ε 批集中收口"引用可变性"议题（详见设计文档 §不在本批解决）
func characters() -> Array[CharacterData]:
	return _characters


## 判断是否有任意角色已装配部队
func has_any_troop() -> bool:
	for ch in _characters:
		if ch.has_troop():
			return true
	return false


## 收集当前队伍中所有有 hero_id 的成员 ID（用于 RunState.draw_recruit 排除）
## hero_id == -1 的角色（老路径 / 测试构造）跳过——不会影响"未在队伍中"判定
func get_team_hero_ids() -> Array[int]:
	var ids: Array[int] = []
	for ch in _characters:
		if ch == null:
			continue
		if ch.hero_id >= 0:
			ids.append(ch.hero_id)
	return ids


## 入队新成员（_on_recruit_confirmed 调；append 到 _characters + 累计 _total_max_hp）
func add_character(member: CharacterData) -> void:
	if member == null:
		return
	if member.troop != null:
		_total_max_hp += member.troop.max_hp
	_characters.append(member)


## 清理阵亡队员（HP<=0 / null / 无 troop），不做队长昏迷判定（持久 slot 战场参与设计 L1.1）
##
## 撤离（RETREAT）收尾用：撤离 ≠ 昏迷，只清理阵亡队员、保留低 HP 队长——
## 不能复用 evaluate_party_state（后者会在队长低于阈值时触发昏迷，违反撤离语义）。
## evaluate_party_state 步骤 1 也复用本方法，避免清理逻辑两处重复。
## 倒序遍历避免 remove_at 索引漂移；从 index 1 起（index 0 是队长，存亡由 evaluate_party_state 单独判定）。
func cleanup_dead_members() -> void:
	for i in range(_characters.size() - 1, 0, -1):
		var ch_member: CharacterData = _characters[i]
		if ch_member == null:
			_characters.remove_at(i)
			continue
		if not ch_member.has_troop():
			_characters.remove_at(i)
			continue
		if ch_member.troop.current_hp <= 0:
			_characters.remove_at(i)


## B 重生周期 MVP：评估队伍状态（队员阵亡移除 + 队长昏迷阈值判定）
##
## 流程：
##   1. 倒序遍历 _characters[1..]：troop == null 或 current_hp <= 0 → 移除（队员阵亡不复活）
##   2. 检查 _characters[0] 队长：troop == null 或 current_hp / max_hp ≤ _coma_hp_threshold_ratio
##      → 调 trigger_coma_or_lose
##
## 返回 true 表示已触发昏迷态或失败遮罩，调用方应中断后续流程。
##
## 触发挂点：WorldMap._apply_player_damages / _on_use_item / _on_equip_troop 末尾。
##
## 守卫（MVP-δ codex review P0 修复）：
##   - 内部守 _is_in_coma（lifecycle 自身已进入昏迷态）
##   - 外部传 skip_if_finished（WorldMap 的 _game_finished 顶层游戏结束态；
##     防胜负判定后调用本方法触发 race condition —— 末敌包清空 + 队长血量阈值同帧）
##   接口参数化让调用方不必每点重复守卫；未来若引入 GameState autoload，改读 GameState 即可
func evaluate_party_state(skip_if_finished: bool = false) -> bool:
	if skip_if_finished or _is_in_coma:
		return true
	# 1. 队员阵亡清理（复用 cleanup_dead_members，撤离收尾走同一逻辑）
	cleanup_dead_members()
	# 2. 队长检查
	if _characters.is_empty():
		# 极端态：连队长都没了 → 走兜底重生 / 失败分支
		trigger_coma_or_lose()
		return true
	var leader: CharacterData = _characters[0]
	if leader == null or not leader.has_troop():
		trigger_coma_or_lose()
		return true
	var troop: TroopData = leader.troop
	if troop.max_hp <= 0:
		# 数据异常；不强制触发昏迷以免误判，写日志
		push_warning("PlayerLifecycle.evaluate_party_state: 队长 max_hp <= 0，跳过阈值判定")
		return false
	var ratio: float = float(troop.current_hp) / float(troop.max_hp)
	if ratio <= _coma_hp_threshold_ratio:
		trigger_coma_or_lose()
		return true
	return false


## B 重生周期 MVP / L1.2 Phase 3：队长昏迷复活分流或末周期失败
##
## 设计：L1.2_多源视野与据点机制_MVP §2.3 昏迷复活分流（PlayerLifecycle 改造）
##
## 三路分流（目标解析交注入的 _coma_respawn_resolver，PlayerLifecycle 不持 _world_map / slot 引用）：
##   ① 有有效据点          → emit coma_respawn_triggered(据点位, deduct=false, stronghold=true)
##                            零代价：无视 respawns_left（据点 = 无限复活锚）、不扣命数、不 reload
##   ② 无据点 + 命数 > 0    → emit coma_respawn_triggered(fallback位, deduct=true, stronghold=false)
##                            扣命数兜底 + 原地传送（不 reload）；fallback = 最近占领 slot / spawn 起点
##   ③ 无据点 + 命数耗尽    → emit defeat_triggered(ENEMY_1) 整局失败
##
## 与原范式（MVP-δ）的区别：原"respawns_left>0 → advance_cycle + reload 重生整图"退役——
## L1.2 据点机制要求"昏迷不重置地图"，reload 范式被原地传送取代（reload 仅保留给 cycle 胜利推进，
## L1.3 统一移除）。WorldMap 仍承担 UI 过渡 + 传送时序；PlayerLifecycle 仍不引用 OverlayTransitionUI/SceneTree。
##
## 解锁约定：传送路径不 reload → 同一实例，WorldMap sink 须在过渡播完后调 clear_coma()（见 clear_coma 注释）
##
## 幂等：_is_in_coma 守卫，重复调用不重复触发；_game_finished 守卫由 WorldMap 调用方负责
func trigger_coma_or_lose() -> void:
	if _is_in_coma:
		return
	# 目标解析（resolver 未注册时退化为"无据点 + fallback=ZERO"，仅测试构造或异常路径出现）
	var resolution: Dictionary = {}
	if _coma_respawn_resolver.is_valid():
		var raw: Variant = _coma_respawn_resolver.call()
		if raw is Dictionary:
			resolution = raw
	# ① 有效据点：零代价原地传送（无视命数）
	if bool(resolution.get("has_stronghold", false)):
		_is_in_coma = true
		var stronghold_pos: Vector2i = resolution.get("stronghold_pos", Vector2i.ZERO)
		coma_respawn_triggered.emit(stronghold_pos, false, true)
		return
	# ②/③ 无据点：扣命数兜底
	if RunState.respawns_left() > 0:
		_is_in_coma = true
		var fallback_pos: Vector2i = resolution.get("fallback_pos", Vector2i.ZERO)
		coma_respawn_triggered.emit(fallback_pos, true, false)
	else:
		# 命数耗尽 → 整局失败（沿用现有 VictoryUI 失败遮罩，由 WorldMap 接 sink 处理）
		defeat_triggered.emit(Faction.ENEMY_1)


## 入口 2 MVP 2.1 议题 5（2026-05-10）：构造 coma 文案
## 查 _characters[0] 的 coma_narrative csv 字段，空则用通用模板
## 通用模板内 {name} 占位会被替换为传入 leader_name
func format_coma_line(leader_name: String) -> String:
	var template: String = ""
	if not _characters.is_empty() and _characters[0] != null:
		var row: Dictionary = RunState.find_hero_row(_characters[0].hero_id)
		template = String(row.get("coma_narrative", ""))
	if template.is_empty():
		return "队长 %s 失去了意识" % leader_name
	return template.replace("{name}", leader_name)


## 入口 2 MVP 2.1 议题 5（2026-05-10）：构造当前队长的 respawn 文案
## leader_row_hint 可由 setup 直接传入（避免 find_hero_row 重复查）；
## 未提供 hint 时用 _characters[0].hero_id 查 RunState
func format_respawn_line_for_current_leader(leader_row_hint: Dictionary = {}) -> String:
	var template: String = String(leader_row_hint.get("respawn_narrative", ""))
	if template.is_empty() and not _characters.is_empty() and _characters[0] != null:
		var row: Dictionary = RunState.find_hero_row(_characters[0].hero_id)
		template = String(row.get("respawn_narrative", ""))
	if template.is_empty():
		return "队长 %s 开启了旅程" % _leader_display_name
	return template.replace("{name}", _leader_display_name)


## 兵种枚举字符串 → TroopData.TroopType
## 解析失败回退到 SWORD（hero_pool.csv 写错字段时不至于崩）
func parse_troop_type(name: String) -> TroopData.TroopType:
	match name.to_upper():
		"SWORD":   return TroopData.TroopType.SWORD
		"BOW":     return TroopData.TroopType.BOW
		"SPEAR":   return TroopData.TroopType.SPEAR
		"CAVALRY": return TroopData.TroopType.CAVALRY
		"SHIELD":  return TroopData.TroopType.SHIELD
		_:
			push_warning("PlayerLifecycle.parse_troop_type: 未知兵种 '%s'，回退 SWORD" % name)
			return TroopData.TroopType.SWORD


## 品质字符串 → TroopData.Quality；空字符串走 default
func parse_troop_quality(name: String, default_quality: int) -> TroopData.Quality:
	if name.is_empty():
		return default_quality as TroopData.Quality
	match name.to_upper():
		"R":   return TroopData.Quality.R
		"SR":  return TroopData.Quality.SR
		"SSR": return TroopData.Quality.SSR
		_:
			push_warning("PlayerLifecycle.parse_troop_quality: 未知品质 '%s'，回退 R" % name)
			return TroopData.Quality.R
