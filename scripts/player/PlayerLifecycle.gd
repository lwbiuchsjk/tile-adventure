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

## 队长昏迷过渡触发（_trigger_coma_or_lose 内 respawns_left > 0 分支）
## 参数：黑屏文案双句 + 火苗团数据
## WorldMap 接 sink → 自行构造 midpoint 闭包（含 RunState.advance_cycle + reload_current_scene +
## 返回 OverlayTransitionUI.world_ready），再调 OverlayTransitionUI.play
##
## MVP-δ codex review P1 修复：原 signal 含 midpoint 参数 + PlayerLifecycle 内构造闭包引用
## OverlayTransitionUI；现 payload 减为 2 参，midpoint 全部迁到 WorldMap.sink handler 构造
signal coma_triggered(lines: PackedStringArray, icon_data: Dictionary)

## 末周期失败触发（_trigger_coma_or_lose 内 respawns_left == 0 分支）
## WorldMap 接 sink → 调 _on_victory_decided(faction) 走 VictoryUI 失败遮罩
signal defeat_triggered(faction: int)

## 新场景启动时 respawn 文案就绪（setup 内消费 _pending_respawn_intro 命中）
## WorldMap 接 sink → 调 OverlayTransitionUI.notify_world_ready(1, respawn_line)
signal respawn_intro_ready(respawn_line: String)


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
func setup(player_cfg: Dictionary, run_cfg: Dictionary) -> void:
	_coma_duration_sec = float(run_cfg.get("coma_duration_sec", "1.5"))
	_coma_hp_threshold_ratio = float(run_cfg.get("coma_hp_threshold_ratio", "0.2"))

	# 默认品质：hero_pool 行未填或解析失败时回退
	var default_quality: int = int(player_cfg.get("initial_troop_quality", "0"))

	_characters = []
	_total_max_hp = 0

	# 从 RunState 抽未使用的英雄；返回的 leader_row 浅拷贝
	# RunState.ensure_initialized 已在 _ready 早期调用过；此处直接 draw
	var leader_row: Dictionary = RunState.draw_new_leader()
	_leader_display_name = String(leader_row.get("name", "队长"))

	# 单角色：队长占据 _characters[0]，其余空位由 C MVP 入队事件追加
	var ch: CharacterData = CharacterData.new()
	ch.id = 1
	# C MVP：写入 hero_id，让 draw_recruit 能正确排除当前在队英雄
	ch.hero_id = int(leader_row.get("id", "-1"))
	var troop: TroopData = TroopData.new()
	troop.troop_type = parse_troop_type(String(leader_row.get("troop_type", "SWORD")))
	troop.quality = parse_troop_quality(String(leader_row.get("troop_quality", "")), default_quality)
	ch.troop = troop
	_total_max_hp += troop.max_hp
	_characters.append(ch)

	# 重生事件（B MVP → 入口 2 MVP 2.1 议题 5 升级）
	# RunState.advance_cycle 时置 _pending_respawn_intro=true；
	# 新场景 setup 末尾消费一次后清零
	#
	# MVP-δ 阶段 2：emit signal 让 WorldMap 接 → 调 OverlayTransitionUI.notify_world_ready
	# PlayerLifecycle 不直接依赖 UI 系统
	if RunState.consume_pending_respawn_intro():
		var respawn_line: String = format_respawn_line_for_current_leader(leader_row)
		respawn_intro_ready.emit(respawn_line)


## 当前是否处于昏迷过渡态
func is_in_coma() -> bool:
	return _is_in_coma


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
	# 1. 队员阵亡 → 从队伍移除（倒序避免索引漂移）
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


## B 重生周期 MVP：队长昏迷或末周期失败分支
##
## 路径：
##   - RunState.respawns_left() > 0 → 进入昏迷态 + emit coma_triggered(lines, icon_data)
##                                    WorldMap.sink → 构造 midpoint 闭包 + OverlayTransitionUI.play
##                                    midpoint 内 advance_cycle + reload；新场景 setup 调
##                                    respawn_intro_ready 让 phase B 通过
##   - 否则                          → 末周期失败 → emit defeat_triggered(ENEMY_1)
##                                    WorldMap 接 → _on_victory_decided(ENEMY_1) 走 VictoryUI
##
## MVP-δ 阶段 2 + codex review P1 修复：
##   PlayerLifecycle 完全不引用 OverlayTransitionUI / get_tree().reload；
##   原 midpoint 闭包整体迁到 WorldMap._on_player_coma_triggered 内构造（含 advance_cycle +
##   reload_current_scene + 返回 world_ready）—— 职责切分清晰：
##     PlayerLifecycle = 队伍/coma 状态判定 + 发信号
##     WorldMap        = UI 过渡 + 场景 reload + 时序协调
##
## 幂等：_is_in_coma 守卫，重复调用不重复触发；_game_finished 守卫由 WorldMap 调用方负责
func trigger_coma_or_lose() -> void:
	if _is_in_coma:
		return
	if RunState.respawns_left() > 0:
		_is_in_coma = true
		# 双句：第 1 句"X 失去了意识"立即可定；
		# 第 2 句留空占位，reload 后 setup 内 emit respawn_intro_ready 替换为"队长 Y 开启了旅程"
		var coma_line: String = format_coma_line(_leader_display_name)
		var lines: PackedStringArray = PackedStringArray([coma_line, ""])
		# 火苗团数 = 过渡完成后的玩家总命数
		# coma 触发会消耗 1 命（advance_cycle 把 _cycle_index +1），advance 后 respawns_left + 1 = 调用时的 respawns_left
		# 例：max_cycles=3, _cycle_index=0 时触发：调用时 respawns_left=2 → 显示 2 团（advance 后剩 1 + 当前新队长）
		var icon_data: Dictionary = {"icon": "🔥", "count": RunState.respawns_left()}
		coma_triggered.emit(lines, icon_data)
	else:
		# 末周期无保护 → 整局失败（沿用现有 VictoryUI 失败遮罩，由 WorldMap 接 sink 处理）
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
