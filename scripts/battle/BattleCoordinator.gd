class_name BattleCoordinator
extends RefCounted
## WorldMap 战斗会话编排器（常驻，由 WorldMap 持有引用）
##
## 设计原文：
##   tile-advanture-design/WorldMap二次重构/批2_BattleCoordinator_MVP.md
##
## 职责（按设计 §范围划分，分 6 阶段逐步迁入）：
##   - 阶段 a：战斗查询工具（is_in_battle / get_packs_in_range / _is_pack_in_battle / _get_battle_unit_at_pos）
##   - 阶段 b：战斗 Camera/zoom 动画
##   - 阶段 c：战斗会话启动 + 援军注入
##   - 阶段 d：战斗会话 sink + 结算（_on_battle_session_ended 145 行）
##   - 阶段 e：战斗内推进 + 敌方阶段
##   - 阶段 f：BattleHUD sink + 守卫弹板
##
## 形态：RefCounted 实例（被 WorldMap._battle_coordinator 持有）
##
## 字段归属（沿用批 1 哲学）：
##   - WorldMap 字段（_battle_session / _battle_zoom_active / _battle_zoom_tween /
##     _battle_center_grid / _reinforcement_hit_slots 等）仍声明在 WorldMap.gd
##   - 本类通过 `_world_map._xxx = ...` 读写
##   - 本类自持 `_world_map` 引用 + 任何战斗会话内的临时中间状态

var _world_map: WorldMap


func _init(world_map: WorldMap) -> void:
	_world_map = world_map


## 由 MapBootstrap.init_world_subsystems() 末尾调一次
##
## BC 自己接 BattleHUD / BattleAnimDirector / EnemyMovement / BattleSession 的 signal
## 阶段 a：先留空骨架；阶段 e/f 迁入对应 signal 接线
func attach_sinks() -> void:
	# 阶段 a：暂无 signal 接线；阶段 e 接 EnemyMovement.phase_finished + BattleAnimDirector.anims_drained
	# 阶段 f 接 BattleHUD 4 sink。BattleSession sinks 由 _bind_battle_session_sinks 在每次战斗启动时绑定
	pass


# ─────────────────────────────────────
# 阶段 a：战斗查询工具
# ─────────────────────────────────────

## 战斗态判定：_battle_session 已创建且尚未结束
##
## 探索态守卫语义：所有面板 / 探索输入在 is_in_battle() 期间被拦截
## （参见 WorldMap._handle_click / _on_build_button_pressed / _start_camp 等）
func is_in_battle() -> bool:
	return _world_map._battle_session != null and not _world_map._battle_session.is_ended()


## 扫描指定坐标曼哈顿距离 ≤ range 内的敌方关卡（LevelSlot）
##
## 用于 [F] 主动战斗触发候选 + 后续 E4 被动战斗保护区扫描复用
##
## 命中条件：
##   - 在距离阈值内
##   - level.is_interactable() = true（UNCHALLENGED）
func get_packs_in_range(origin: Vector2i, search_range: int) -> Array[LevelSlot]:
	var result: Array[LevelSlot] = []
	for pos in _world_map._level_slots:
		var p: Vector2i = pos as Vector2i
		var dist: int = absi(p.x - origin.x) + absi(p.y - origin.y)
		if dist > search_range:
			continue
		var lv: LevelSlot = _world_map._level_slots[p] as LevelSlot
		if lv == null or not lv.is_interactable():
			continue
		result.append(lv)
	return result


## 检查指定格上是否有正在参战的敌方 LevelSlot
##
## 战斗中两个独立视觉层（探索态 LevelSlot 红菱形 + BattleUnit 红圆形）会重叠在 LevelSlot 原格，
## 看起来像"敌方分身"。此 helper 让 _draw_tile 在战斗中跳过参战 LevelSlot 的渲染，
## 让战场内视觉只剩 BattleUnit 圆形 + HP 条
##
## 战斗结束 sink 调 _level_slots.erase + 清空 _battle_session 后，本函数自然返回 false，
## _draw_tile 恢复正常渲染
func _is_pack_in_battle(pos: Vector2i) -> bool:
	if _world_map._battle_session == null:
		return false
	for pack in _world_map._battle_session.participating_packs:
		if pack != null and pack.position == pos:
			return true
	return false


## 在战场上（含玩家方 / 敌方）查找指定格上的存活单位
##
## _handle_click 战斗态分流用：点击格 → 是否敌方单位 → 攻击；否则当作移动目标
func _get_battle_unit_at_pos(pos: Vector2i) -> BattleUnit:
	if _world_map._battle_session == null:
		return null
	for u in _world_map._battle_session.player_units:
		if u != null and u.is_active and u.is_alive() and u.battle_position == pos:
			return u
	for u in _world_map._battle_session.enemy_units:
		if u != null and u.is_active and u.is_alive() and u.battle_position == pos:
			return u
	return null
