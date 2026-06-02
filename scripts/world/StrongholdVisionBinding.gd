class_name StrongholdVisionBinding
extends RefCounted
## 据点 + 占领 slot ↔ VisionSource 注册绑定（L1.2 Phase 2）
##
## 设计原文：
##   tile-advanture-design/无限地图实装/L1.2_多源视野与据点机制_MVP.md §3.10 / §4.2
##
## 职责：
##   - 把"据点 / 玩家占领的持久 slot"映射为 VisionSystem 的 VisionSource，owner 变更时增量 register/unregister
##   - 纯事件驱动：据点靠 RunState.set_stronghold sink、占领靠 OccupationSystem.try_occupy 翻转 sink
##     不做 init 扫描补登（MVP 目标体验：首周期玩家无占领；实现不依赖开局占领状态）
##
## 形态：RefCounted（运行时短生命周期；随 WorldMap reload 一起释放）
##
## 与 VisionSystem 的关系：本类只负责"何时该有/没有某个视野源"，覆盖计算 / chunk 聚合由
## VisionSystem + ChunkManager 承接（register/unregister 内部自动触发 _recompute_coverage）


## 占领 slot 位置 → VisionSource 实例（便于 owner 变更时定位 unregister）
## key 用 Vector2i position（与 PersistentSlot.position 对齐）
var _slot_sources: Dictionary = {}

## 据点 VisionSource（0 或 1 个；据点选定时创建，本局不主动 unregister）
var _stronghold_source: VisionSource = null

## 据点位置（用于占领事件去重：据点格不进 _slot_sources，避免与据点源双源重叠）
var _stronghold_pos: Vector2i = Vector2i.ZERO
var _has_stronghold: bool = false

## 注入引用（不持有所有权）
var _vision_system: VisionSystem = null
var _vision_config: VisionConfig = null


## 初始化注入（EC.init_vision_runtime 调一次）
func setup(vision_system: VisionSystem, vision_config: VisionConfig) -> void:
	_vision_system = vision_system
	_vision_config = vision_config


## 据点选定回调（订阅 RunState.register_stronghold_set_sink）
##
## 创建据点 VisionSource（radius = stronghold_vision_radius）register 到 VisionSystem。
## 据点格若此前已作为占领 slot 注册过视野源（玩家先占领该 slot 再设为据点），先移除占领源
## 避免同格双源（据点源半径更大，覆盖占领源即可）。
func on_stronghold_set(pos: Vector2i) -> void:
	if _vision_system == null or _vision_config == null:
		return
	# 据点格此前若有占领源 → 先移除（升级为据点源）
	if _slot_sources.has(pos):
		var old: VisionSource = _slot_sources[pos] as VisionSource
		if old != null:
			_vision_system.unregister_source(old)
		_slot_sources.erase(pos)
	# 已有据点源（MVP 一次性，理论不会重复进；防御性）→ 先移除旧的
	if _stronghold_source != null:
		_vision_system.unregister_source(_stronghold_source)
		_stronghold_source = null
	_stronghold_pos = pos
	_has_stronghold = true
	_stronghold_source = VisionSource.new(
		pos, _vision_config.stronghold_vision_radius, Faction.PLAYER, null
	)
	_vision_system.register_source(_stronghold_source)


## 占领 slot 归属翻转回调（订阅 OccupationSystem.register_slot_owner_changed_sink）
##
## owner == PLAYER 且未注册 → register 占领 slot 视野源
## owner != PLAYER 且已注册 → unregister（敌方夺走 / 中立化）
## 据点格跳过：据点源由 on_stronghold_set 单独管理，不受占领事件干扰
##   （据点被敌占翻成 ENEMY_1 时，据点源仍保留——昏迷复活校验失效降级是 Phase 3 的逻辑，
##    Phase 2 不在占领事件里动据点源，保持职责单一）
func on_slot_owner_changed(slot: PersistentSlot) -> void:
	if _vision_system == null or _vision_config == null or slot == null:
		return
	var pos: Vector2i = slot.position
	# 据点格不走占领源路径（避免与据点源重叠 / 误删据点源）
	if _has_stronghold and pos == _stronghold_pos:
		return

	if slot.owner_faction == Faction.PLAYER:
		# 玩家占领 → 注册（已有则跳过，幂等）
		if _slot_sources.has(pos):
			return
		var src: VisionSource = VisionSource.new(
			pos, _vision_config.occupied_slot_vision_radius, Faction.PLAYER, null
		)
		_slot_sources[pos] = src
		_vision_system.register_source(src)
	else:
		# 非玩家（敌方夺走 / 中立）→ 移除占领源（若有）
		if _slot_sources.has(pos):
			var src: VisionSource = _slot_sources[pos] as VisionSource
			if src != null:
				_vision_system.unregister_source(src)
			_slot_sources.erase(pos)


## 当前占领 slot 视野源数量（测试 / 诊断用）
func occupied_source_count() -> int:
	return _slot_sources.size()


## 是否已注册据点源（测试 / 诊断用）
func has_stronghold_source() -> bool:
	return _stronghold_source != null
