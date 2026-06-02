class_name VisionSystem
extends Node
## 视野状态机（L1.1 §2.1 / §3.1）
##
## 设计原文：
##   tile-advanture-design/无限地图实装/L1.1_视野循环与chunk底座_MVP.md §2.1 / §3.1 / §4.2
##
## 职责：
##   - 维护全图格子级视野状态（NORMAL / FOG / SHADOW）
##   - 多源视野（VisionSource 列表）覆盖求并集
##   - 滞回时钟（fog_delay）防边缘抖动
##   - 退化时钟（shadow_decay）让 FOG 自然消散
##   - 不直接管理 chunk —— chunk 聚合由 ChunkManager 主导，本系统仅暴露格子级状态
##
## 与 ChunkManager 的关系：
##   - 本系统是"事实源"（格子级状态）
##   - ChunkManager 是"消费者"（按聚合规则决定 chunk 三态）
##   - 两者职责分离，单点耦合在"聚合规则"（聚合判定时调 aggregate_tiles）
##
## L1.1 单源限制：本份仅接入"玩家队伍"一个源；架构上 _sources: Array[VisionSource] 支持多源。
## L1.2 据点 + 占领点接入时不需要改本系统。


## 格子视野状态
enum TileState { SHADOW, FOG, NORMAL }


## 全局格子视野表：Vector2i → TileState
## 不在表内 = 默认 SHADOW（节省内存：未触及的远处不建条目）
var _tile_state: Dictionary = {}

## 进入 FOG 的回合号：Vector2i → int
## 用于判断 FOG → SHADOW 退化时机
var _fog_entered_turn: Dictionary = {}

## 离开 NORMAL 的回合号：Vector2i → int
## 用于判断 NORMAL → FOG 滞回触发时机
var _normal_left_turn: Dictionary = {}

## 视野源列表（L1.1 注册 1 个：玩家队伍）
var _sources: Array[VisionSource] = []

## 配置引用（外部传入，不持有所有权）
var _config: VisionConfig = null

## 当前回合号（外部 advance_turn 推进）
var _current_turn: int = 0


## 信号：格子视野状态变化时发射，供 ChunkManager 增量聚合
## 参数：tile（世界格）、new_state、old_state
signal tile_state_changed(tile: Vector2i, new_state: int, old_state: int)


# ─────────────────────────────────────
# 生命周期
# ─────────────────────────────────────

## 注入配置（必须在 register_source 之前调用）
func setup(config: VisionConfig) -> void:
	_config = config


# ─────────────────────────────────────
# 视野源管理
# ─────────────────────────────────────

func register_source(source: VisionSource) -> void:
	if _sources.has(source):
		return
	_sources.append(source)
	_recompute_coverage()


func unregister_source(source: VisionSource) -> void:
	_sources.erase(source)
	_recompute_coverage()


## 视野源移动后调用（VisionSource.position 已被外部改写后通知本系统）
func notify_source_moved() -> void:
	_recompute_coverage()


## 返回当前所有已注册视野源的快照引用（L1.2 §3.6 新增）
## 顺序：注册顺序（L1.1 阶段 2 约定 _sources[0] = 玩家队伍源；据点 / 占领 slot 依次 append）
## NightVisionLayer 每帧调用喂 shader lights[]，需保持轻量——直接返回内部数组引用（不拷贝）；
## 调用方只读迭代，不得修改返回数组（增删源须经 register/unregister_source 走覆盖重算）
func get_sources() -> Array[VisionSource]:
	return _sources


# ─────────────────────────────────────
# 状态查询
# ─────────────────────────────────────

func get_tile_state(tile: Vector2i) -> int:
	return int(_tile_state.get(tile, TileState.SHADOW))


## 取一组格子的状态聚合（任一 NORMAL → NORMAL；否则任一 FOG → FOG；都 SHADOW → SHADOW）
## 供 ChunkManager 做 chunk 聚合判定
func aggregate_tiles(tiles: Array[Vector2i]) -> int:
	var has_fog: bool = false
	for t in tiles:
		var s: int = get_tile_state(t)
		if s == TileState.NORMAL:
			return TileState.NORMAL
		elif s == TileState.FOG:
			has_fog = true
	return TileState.FOG if has_fog else TileState.SHADOW


## 取当前所有 NORMAL 格的集合（供外部诊断 / 渲染层迭代）
## 注意：返回大量数据时调用方需自负性能
func get_all_normal_tiles() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for t in _tile_state.keys():
		if _tile_state[t] == TileState.NORMAL:
			result.append(t)
	return result


# ─────────────────────────────────────
# 时钟推进
# ─────────────────────────────────────

func advance_turn(new_turn: int) -> void:
	_current_turn = new_turn
	_apply_decay()


func get_current_turn() -> int:
	return _current_turn


# ─────────────────────────────────────
# 内部 —— 覆盖计算
# ─────────────────────────────────────

## 重算所有视野源的覆盖并集，更新格子状态
## 触发：register/unregister/notify_source_moved
## 复杂度：O(N_sources × R²) 收集覆盖 + O(N_known_tiles) 扫描离开
func _recompute_coverage() -> void:
	# 1. 收集本次所有视野源覆盖的格子
	var covered_now: Dictionary = {}
	for src in _sources:
		for t in src.get_covered_tiles():
			covered_now[t] = true

	# 2. 新覆盖的格（之前不在 NORMAL）→ 立即转 NORMAL
	for t in covered_now.keys():
		var old: int = get_tile_state(t)
		if old != TileState.NORMAL:
			_set_tile(t, TileState.NORMAL)
			# 重新覆盖：清离开/进雾时钟
			_normal_left_turn.erase(t)
			_fog_entered_turn.erase(t)

	# 3. 之前 NORMAL、现不在 covered_now → 标记"离开时间"
	#    实际 NORMAL → FOG 转换由 advance_turn 推进
	#    迭代 _tile_state.keys() 的快照避免边遍历边改
	var to_check: Array = _tile_state.keys().duplicate()
	for t in to_check:
		if _tile_state.get(t, TileState.SHADOW) == TileState.NORMAL and not covered_now.has(t):
			# 首次离开记录当前回合（后续仍未覆盖则不重置）
			if not _normal_left_turn.has(t):
				_normal_left_turn[t] = _current_turn


## 推进 fog_delay + shadow_decay 两条时钟
func _apply_decay() -> void:
	if _config == null:
		return

	# NORMAL → FOG（滞回时钟到期）
	var to_fog: Array[Vector2i] = []
	for t in _normal_left_turn.keys():
		if get_tile_state(t) != TileState.NORMAL:
			# 已转其他态（如重新被覆盖），跳过；时钟由 _set_tile 处清理
			continue
		if _current_turn - int(_normal_left_turn[t]) >= _config.fog_delay_turns:
			to_fog.append(t)
	for t in to_fog:
		_set_tile(t, TileState.FOG)
		_normal_left_turn.erase(t)
		_fog_entered_turn[t] = _current_turn

	# FOG → SHADOW（退化时钟到期）
	var to_shadow: Array[Vector2i] = []
	for t in _fog_entered_turn.keys():
		if get_tile_state(t) != TileState.FOG:
			continue
		if _current_turn - int(_fog_entered_turn[t]) >= _config.shadow_decay_turns:
			to_shadow.append(t)
	for t in to_shadow:
		_set_tile(t, TileState.SHADOW)
		_fog_entered_turn.erase(t)


## 设置格子状态 + 发射 signal
## SHADOW 时从 dict 移除（节省内存：默认即 SHADOW）
func _set_tile(tile: Vector2i, new_state: int) -> void:
	var old: int = get_tile_state(tile)
	if old == new_state:
		return
	if new_state == TileState.SHADOW:
		_tile_state.erase(tile)
	else:
		_tile_state[tile] = new_state
	tile_state_changed.emit(tile, new_state, old)
