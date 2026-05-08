class_name BattleSession
extends RefCounted
## 战斗会话（E 战斗就地展开 MVP §4.4）
##
## 设计原文：tile-advanture-design/探索体验实装/E_战斗就地展开_MVP.md
##
## 职责：
##   - 战斗内的所有状态载体：战场 Rect2i / 玩家方 + 敌方 BattleUnit 列表 / 当前回合 / 行动顺序
##   - 启动时执行队员 + 敌方展开（§2.4 全局占位字典）
##   - 提供玩家方单步行动接口（移动 / 攻击 / 跳过）+ 敌方回合自动调度
##   - 战斗结束检测（敌方全灭自动退出 / 队长昏迷阈值 / 玩家手动退出）
##
## 与 UI / WorldMap 的关系（E1 仅数据骨架）：
##   - WorldMap 持有 _battle_session: BattleSession
##   - BattleHUD（E2）通过 BattleSession 接口查询渲染数据 + 注入玩家点击动作
##   - 战斗结束时调 on_battle_ended sink，WorldMap 接收并执行收尾（奖励 / 队员位置回正 / 重生分支）


# ─────────────────────────────────────
# 枚举
# ─────────────────────────────────────

## 战斗阶段（玩家行动 → 敌方行动 → 玩家行动 ...）
enum Phase { PLAYER_TURN = 0, ENEMY_TURN = 1, ENDED = 2 }

## 战斗结束原因
enum EndReason { VICTORY = 0, MANUAL_EXIT = 1, COMA = 2 }


# ─────────────────────────────────────
# 字段
# ─────────────────────────────────────

## 战场范围（玩家中心 ±arena_range，与地图边界做交集）
var arena: Rect2i = Rect2i()

## 复用世界 schema（查地形 cost / 高度 / 持久 slot 占据格）
var schema: MapSchema = null

## 玩家方上场单位列表（队长 [0] + 已展开队员）
var player_units: Array[BattleUnit] = []

## 敌方上场单位列表（各 LevelSlot 的 troops 展开后）
var enemy_units: Array[BattleUnit] = []

## 未上场玩家队员（CharacterData 数据保留 / 战斗中不参与）
var inactive_player_chars: Array[CharacterData] = []

## 未上场敌方 troops（保留在 LevelSlot.troops 中 / 战斗中不参与）
## 结构：{ LevelSlot: Array[TroopData] }
var inactive_enemy_troops: Dictionary = {}

## 当前阶段
var current_phase: Phase = Phase.PLAYER_TURN

## 当前行动单位在 player_units / enemy_units 中的索引
var current_actor_index: int = 0

## 战斗回合数（玩家 + 敌方各行动一次 = 1 回合）
var battle_round: int = 1

## 参战 LevelSlot 列表（用于战斗胜利时遍历清理 / 发奖励）
var participating_packs: Array[LevelSlot] = []

## 兵种战斗参数缓存：{ TroopType_int : Dictionary{"move_range": int, "attack_range": int} }
## 注：Godot 4.6 typed Dictionary 在嵌套类型上存在限制，保持无类型 Dictionary 但靠注释 + 入参约束保证结构
var unit_config: Dictionary = {}

## 战斗参数（伤害公式用）
## 结构：String 键 → String 值（直接来自 ConfigLoader.load_csv_kv）
var battle_config: Dictionary = {}

## 地形高度差伤害修正系数（默认 0.10）
var terrain_altitude_step: float = 0.10

## 队长昏迷阈值（current_hp / max_hp ≤ 该值触发 COMA 结束）
## 由 WorldMap 在 start 时注入，与 B MVP 的 _coma_hp_threshold_ratio 同步
var coma_hp_threshold_ratio: float = 0.2

## 关卡难度 / 难度递增（与 BattleResolver.resolve 同语义）
var difficulty: int = 0
var damage_increment: float = 0.0


# ─────────────────────────────────────
# 信号 sink（WorldMap 注入）
# ─────────────────────────────────────

## 战斗结束回调；签名 func(reason: EndReason, defeated_packs: Array[LevelSlot]) -> void
var on_battle_ended: Callable = Callable()

## 状态变化时回调（HUD redraw 触发）；无参数
var on_redraw_requested: Callable = Callable()


# ─────────────────────────────────────
# 启动 / 结束
# ─────────────────────────────────────

## 启动战斗会话
##
## 参数：
##   characters         —— 玩家方 _characters 数组（队长 [0] + 队员）
##   player_pos         —— 玩家当前世界格坐标（队长展开位置）
##   packs              —— 参战的 LevelSlot 列表
##   schema_ref         —— 世界 MapSchema 引用
##   arena_range        —— 战场半径（默认 6）
##   unit_cfg           —— battle_unit_config 解析后字典 { troop_type_int: {move_range, attack_range} }
##   bcfg               —— battle_config（伤害公式参数）
##   altitude_step      —— terrain_altitude_step
##   diff               —— 难度（关卡轮次索引）
##   dmg_increment      —— 难度递增伤害
func start(
	characters: Array[CharacterData],
	player_pos: Vector2i,
	packs: Array[LevelSlot],
	schema_ref: MapSchema,
	arena_range: int,
	unit_cfg: Dictionary,
	bcfg: Dictionary,
	altitude_step: float,
	coma_threshold: float,
	diff: int,
	dmg_increment: float
) -> void:
	schema = schema_ref
	unit_config = unit_cfg
	battle_config = bcfg
	terrain_altitude_step = altitude_step
	coma_hp_threshold_ratio = coma_threshold
	difficulty = diff
	damage_increment = dmg_increment
	participating_packs = packs.duplicate()
	current_phase = Phase.PLAYER_TURN
	current_actor_index = 0
	battle_round = 1

	# 战场 Rect2i = 玩家中心 ±arena_range 与地图边界交集
	arena = _compute_arena(player_pos, arena_range, schema)

	# 全局占位字典（展开期间维护）
	var occupied: Dictionary = {}

	# 玩家方展开
	player_units = []
	inactive_player_chars = []
	_deploy_player_side(characters, player_pos, occupied)

	# 敌方展开（按参战 LevelSlot 顺序）
	enemy_units = []
	inactive_enemy_troops = {}
	for pack in packs:
		_deploy_enemy_pack(pack, occupied)


## 结束战斗会话；触发 on_battle_ended sink
##
## defeated_packs：胜利时被歼灭的 LevelSlot 列表（含上场 + 未上场 troops 全部消灭）
##                 手动退出时传空数组（敌方残余保留）
##                 COMA 时不关心（场景 reload 后 BattleSession 销毁）
func end(reason: EndReason, defeated_packs: Array[LevelSlot]) -> void:
	current_phase = Phase.ENDED
	if on_battle_ended.is_valid():
		on_battle_ended.call(reason, defeated_packs)


# ─────────────────────────────────────
# 状态查询
# ─────────────────────────────────────

func is_player_turn() -> bool:
	return current_phase == Phase.PLAYER_TURN


func is_enemy_turn() -> bool:
	return current_phase == Phase.ENEMY_TURN


func is_ended() -> bool:
	return current_phase == Phase.ENDED


## 当前行动单位（玩家方或敌方按 phase 决定）
## 索引越界 / 阶段已结束时返回 null
func current_actor() -> BattleUnit:
	if is_ended():
		return null
	var arr: Array[BattleUnit] = player_units if is_player_turn() else enemy_units
	if current_actor_index < 0 or current_actor_index >= arr.size():
		return null
	return arr[current_actor_index]


## 战场内是否还有敌方存活（用于退出条件 §2.7）
func has_enemy_in_arena() -> bool:
	for u in enemy_units:
		if u.is_active and u.is_alive() and arena.has_point(u.battle_position):
			return true
	return false


## 战场内是否所有敌方已歼灭（自动胜利条件）
func is_all_enemies_defeated() -> bool:
	for u in enemy_units:
		if u.is_alive():
			return false
	# 未上场敌方 troops 也视为可消灭（设计 §2.4 战斗胜利时一并算）
	# 这里只检查上场单位是否全死；未上场由 EndReason.VICTORY 路径自然处理
	return true


# ─────────────────────────────────────
# 玩家方单步接口（E1 仅暴露 API；E3 由 WorldMap / BattleHUD 调用）
# ─────────────────────────────────────

## 当前玩家单位的可达格集合（移动力内 + 战场内 + 不被占）
## E2 BattleHUD 用作高亮渲染
func get_reachable_for_current() -> Array[Vector2i]:
	var actor: BattleUnit = current_actor()
	if actor == null or not is_player_turn() or actor.has_moved:
		return []
	return _bfs_reachable(actor)


## 当前玩家单位的攻击范围内敌方目标
## E2 BattleHUD 用作高亮渲染
func get_attackable_targets() -> Array[BattleUnit]:
	var actor: BattleUnit = current_actor()
	if actor == null or not is_player_turn() or actor.has_attacked:
		return []
	var targets: Array[BattleUnit] = []
	for enemy in enemy_units:
		if not enemy.is_active or not enemy.is_alive():
			continue
		if _manhattan(actor.battle_position, enemy.battle_position) <= actor.attack_range:
			targets.append(enemy)
	return targets


## 玩家点击格尝试移动；返回是否移动成功
func try_player_move(target_pos: Vector2i) -> bool:
	var actor: BattleUnit = current_actor()
	if actor == null or not is_player_turn() or actor.has_moved or actor.has_attacked:
		return false
	var reachable: Array[Vector2i] = get_reachable_for_current()
	if not reachable.has(target_pos):
		return false
	# 更新位置；occupied 字典在每帧重新由 BattleSession 维护无需手动同步（_bfs_reachable 实时查 enemy/player_units）
	actor.battle_position = target_pos
	actor.has_moved = true
	_request_redraw()
	return true


## 玩家点击攻击目标；返回是否攻击成功 + 伤害值（用于 HUD 飘字 / 日志）
##
## 攻击执行：
##   1. 阵营校验（target 必须是敌方，防 UI 误传）
##   2. 计算地形高度差
##   3. BattleResolver.calculate_single_attack 得伤害
##   4. target.troop.take_damage
##   5. actor.has_attacked = true（攻击后回合结束）
##   6. 调用 _check_battle_end_after_action 看是否触发胜利
##
## 攻击后未自动推进 actor —— 由调用方决定（玩家可能想看完伤害再点"下一个"）
func try_player_attack(target: BattleUnit) -> Dictionary:
	var actor: BattleUnit = current_actor()
	if actor == null or not is_player_turn() or actor.has_attacked:
		return {"success": false, "damage": 0}
	if target == null or not target.is_active or not target.is_alive():
		return {"success": false, "damage": 0}
	# 阵营校验：避免 UI 误传友军单位作目标
	if target.owner_faction == actor.owner_faction:
		push_warning("BattleSession.try_player_attack: target 与 actor 同阵营，拒绝")
		return {"success": false, "damage": 0}
	if _manhattan(actor.battle_position, target.battle_position) > actor.attack_range:
		return {"success": false, "damage": 0}
	var damage: int = _calc_attack_damage(actor, target)
	target.troop.take_damage(damage)
	actor.has_attacked = true
	_request_redraw()
	# 胜利 / 昏迷自动结束判定
	_check_battle_end_after_action()
	return {"success": true, "damage": damage}


## 跳过当前单位本回合行动（先移动后攻击都不做 / 移动后不攻击）
func skip_current_unit() -> void:
	var actor: BattleUnit = current_actor()
	if actor == null or not is_player_turn():
		return
	actor.has_moved = true
	actor.has_attacked = true


## 推进到下一个玩家单位；当前玩家全员行动完 → 切到敌方回合
##
## 调用方 = BattleHUD"下一个"按钮 / 攻击或移动后自动推进
##
## 推进顺序：跳过未上场 / 已死 / 已结束行动的单位
func advance_to_next_player_unit() -> void:
	if not is_player_turn():
		return
	current_actor_index = _find_next_actor_index(player_units, current_actor_index + 1)
	if current_actor_index < 0:
		# 玩家全员完成 → 切敌方回合
		_start_enemy_turn()
	else:
		_request_redraw()


## 玩家按 [F] 尝试退出战斗（§2.7 手动退出）
##
## 战场内还有敌方 → 返回 false（调用方 _show_notice 提示）
## 战场内无敌方 → end(MANUAL_EXIT)，返回 true
func try_manual_exit() -> bool:
	if not is_player_turn():
		return false
	if has_enemy_in_arena():
		return false
	end(EndReason.MANUAL_EXIT, [])
	return true


# ─────────────────────────────────────
# 敌方回合自动执行（E1 提供完整流程；E3 由 WorldMap 在玩家回合切换时调用）
# ─────────────────────────────────────

## 切到敌方回合 + 重置敌方所有单位 has_moved / has_attacked + 索引归零
func _start_enemy_turn() -> void:
	current_phase = Phase.ENEMY_TURN
	current_actor_index = 0
	for unit in enemy_units:
		unit.reset_turn_flags()
	# 寻找第一个可行动的敌方单位
	current_actor_index = _find_next_actor_index(enemy_units, 0)
	_request_redraw()


## 敌方一个单位执行其决策（E3 由 WorldMap / Timer 串行调用）
##
## 返回是否还有下一个敌方单位（true 时调用方继续；false 时切回玩家回合）
##
## 流程：
##   1. BattleAI.decide → action 字典
##   2. 执行 action（移动 + 攻击）
##   3. has_attacked = true（动作完毕）
##   4. 推进 current_actor_index
func step_enemy_turn() -> bool:
	if not is_enemy_turn():
		return false
	var actor: BattleUnit = current_actor()
	if actor == null:
		_start_player_turn()
		return false
	var decision: Dictionary = BattleAI.decide(
		actor, player_units, arena, schema, _build_occupied()
	)
	var action: int = int(decision.get("action", BattleAI.Action.SKIP))
	match action:
		BattleAI.Action.MOVE:
			actor.battle_position = decision["move_to"] as Vector2i
			actor.has_moved = true
			actor.has_attacked = true  # 仅移动 = 本回合行动结束
		BattleAI.Action.ATTACK:
			# 先移动到指定格（可能与原位相同）
			var move_to: Vector2i = decision["move_to"] as Vector2i
			if move_to != actor.battle_position:
				actor.battle_position = move_to
				actor.has_moved = true
			# 攻击
			var target: BattleUnit = decision["target"] as BattleUnit
			if target != null and target.is_active and target.is_alive():
				var damage: int = _calc_attack_damage(actor, target)
				target.troop.take_damage(damage)
			actor.has_attacked = true
		BattleAI.Action.SKIP:
			actor.has_attacked = true

	# 胜利 / 昏迷判定（敌方攻击后队长可能跌阈值）
	_check_battle_end_after_action()
	if is_ended():
		return false

	# 推进
	current_actor_index = _find_next_actor_index(enemy_units, current_actor_index + 1)
	_request_redraw()
	if current_actor_index < 0:
		_start_player_turn()
		return false
	return true


## 切回玩家回合 + 重置玩家所有单位行动标记 + 推进战斗回合数
func _start_player_turn() -> void:
	current_phase = Phase.PLAYER_TURN
	current_actor_index = 0
	for unit in player_units:
		unit.reset_turn_flags()
	current_actor_index = _find_next_actor_index(player_units, 0)
	battle_round += 1
	_request_redraw()


## 战斗结束判定（每次攻击 / 单位死亡后调用）
##
## 判定顺序（决定 EndReason 优先级）：
##   1. 队长昏迷阈值命中 → COMA（B MVP 重生分支衔接）
##   2. 战场内敌方上场单位全死 → VICTORY（携带 participating_packs）
##
## 队长昏迷优先于胜利：极端情况下"敌方最后一击命中队长 + 顺便消灭最后一个敌方"
##                     按 COMA 处理（玩家本局结束）；视作队长牺牲换胜利的极端剧情
##
## 已结束（current_phase == ENDED）时直接返回，避免重复 end
func _check_battle_end_after_action() -> void:
	if is_ended():
		return
	# 1. 队长昏迷判定
	if _is_leader_in_coma():
		end(EndReason.COMA, [])
		return
	# 2. 胜利判定：上场敌方全部死亡（未上场敌方 troop 由 VICTORY 路径在 WorldMap 收尾时一并消灭）
	var any_enemy_alive: bool = false
	for u in enemy_units:
		if u.is_alive():
			any_enemy_alive = true
			break
	if not any_enemy_alive:
		end(EndReason.VICTORY, participating_packs)


## 队长昏迷判定：player_units[0] 始终是队长（_deploy_player_side 约定）
##
## 命中条件（与 B MVP _evaluate_party_state 一致）：
##   - troop == null 或 current_hp <= 0：视作昏迷
##   - 或 current_hp / max_hp ≤ coma_hp_threshold_ratio
func _is_leader_in_coma() -> bool:
	if player_units.is_empty():
		return true
	var leader: BattleUnit = player_units[0]
	if leader == null or leader.troop == null:
		return true
	if leader.troop.current_hp <= 0:
		return true
	if leader.troop.max_hp <= 0:
		return false
	var ratio: float = float(leader.troop.current_hp) / float(leader.troop.max_hp)
	return ratio <= coma_hp_threshold_ratio


# ─────────────────────────────────────
# 内部 helper：展开
# ─────────────────────────────────────

## 计算战场 Rect2i：玩家中心 ±arena_range 与地图边界做交集（§2.1）
static func _compute_arena(center: Vector2i, arena_range: int, schema: MapSchema) -> Rect2i:
	var raw: Rect2i = Rect2i(
		center.x - arena_range, center.y - arena_range,
		arena_range * 2 + 1, arena_range * 2 + 1
	)
	var map_rect: Rect2i = Rect2i(0, 0, schema.width, schema.height)
	# Rect2i.intersection 在 Godot 4 中可用，返回交集
	return raw.intersection(map_rect)


## 玩家方展开：队长留原位，队员按 4邻 → 8邻 找空位
func _deploy_player_side(
	characters: Array[CharacterData], player_pos: Vector2i, occupied: Dictionary
) -> void:
	if characters.is_empty():
		return
	# 队长（[0]）
	var leader_char: CharacterData = characters[0]
	if leader_char != null and leader_char.has_troop():
		var leader_unit: BattleUnit = _make_player_unit(leader_char, player_pos)
		player_units.append(leader_unit)
		occupied[player_pos] = leader_unit
	else:
		# 队长无部队 → 战斗刚启动就走失败分支；这里不展开，调用方应在 start 前检查
		push_warning("BattleSession._deploy_player_side: 队长无部队，玩家方未展开任何单位")
		return
	# 队员（[1..]）
	for i in range(1, characters.size()):
		var ch: CharacterData = characters[i]
		if ch == null or not ch.has_troop():
			continue
		var slot: Vector2i = _find_deploy_slot(player_pos, occupied)
		if not _is_valid_slot(slot, occupied):
			push_warning("BattleSession: 队员 %s 找不到展开位，标记未上场" % ch.id)
			inactive_player_chars.append(ch)
			continue
		var unit: BattleUnit = _make_player_unit(ch, slot)
		unit.is_active = true
		player_units.append(unit)
		occupied[slot] = unit


## 敌方 LevelSlot 展开：首 troop 留原格 + 其余 4邻→8邻→16邻 找空位
func _deploy_enemy_pack(pack: LevelSlot, occupied: Dictionary) -> void:
	if pack == null or pack.troops.is_empty():
		return
	var pack_pos: Vector2i = pack.position
	var inactive_for_pack: Array[TroopData] = []

	# 首 troop
	var first_troop: TroopData = pack.troops[0]
	var first_pos: Vector2i = pack_pos
	if not _can_deploy_at(first_pos, occupied):
		# 极端：原格已被占（例如另一 LevelSlot 同位 / 玩家展开占了——理论极少）
		first_pos = _find_deploy_slot(pack_pos, occupied)
	if _is_valid_slot(first_pos, occupied):
		var first_unit: BattleUnit = _make_enemy_unit(first_troop, pack, first_pos)
		enemy_units.append(first_unit)
		occupied[first_pos] = first_unit
	else:
		push_warning("BattleSession: pack %s 首 troop 找不到展开位，标记未上场" % pack_pos)
		inactive_for_pack.append(first_troop)

	# 其余 troops
	for i in range(1, pack.troops.size()):
		var troop: TroopData = pack.troops[i]
		var slot: Vector2i = _find_deploy_slot(pack_pos, occupied, 4)  # 4 = 16 格内
		if not _is_valid_slot(slot, occupied):
			push_warning("BattleSession: pack %s 第 %d 个 troop 找不到展开位，标记未上场" % [pack_pos, i])
			inactive_for_pack.append(troop)
			continue
		var unit: BattleUnit = _make_enemy_unit(troop, pack, slot)
		enemy_units.append(unit)
		occupied[slot] = unit

	if not inactive_for_pack.is_empty():
		inactive_enemy_troops[pack] = inactive_for_pack


## 构造玩家方 BattleUnit：装配 troop_type 对应的 move_range / attack_range
func _make_player_unit(ch: CharacterData, pos: Vector2i) -> BattleUnit:
	var unit: BattleUnit = BattleUnit.new()
	unit.owner_faction = Faction.PLAYER
	unit.troop = ch.troop
	unit.character = ch
	unit.battle_position = pos
	_apply_unit_config(unit)
	return unit


## 构造敌方 BattleUnit
func _make_enemy_unit(troop: TroopData, pack: LevelSlot, pos: Vector2i) -> BattleUnit:
	var unit: BattleUnit = BattleUnit.new()
	unit.owner_faction = Faction.ENEMY_1
	unit.troop = troop
	unit.source_level = pack
	unit.battle_position = pos
	_apply_unit_config(unit)
	return unit


## 从 unit_config 装配 move_range / attack_range
func _apply_unit_config(unit: BattleUnit) -> void:
	var key: int = unit.troop.troop_type as int
	if unit_config.has(key):
		var entry: Dictionary = unit_config[key] as Dictionary
		unit.move_range = int(entry.get("move_range", 3))
		unit.attack_range = int(entry.get("attack_range", 1))
	else:
		# 兜底：未配置兵种默认 SWORD 数值
		unit.move_range = 3
		unit.attack_range = 1


# ─────────────────────────────────────
# 内部 helper：展开位查找
# ─────────────────────────────────────

## 哨兵值：表示"找不到展开位"
const _NO_DEPLOY_SLOT: Vector2i = Vector2i(-9999, -9999)


## 在 anchor 周围找空位：先 4 邻、再 8 邻、可选扩到 max_radius 圈
##
## anchor    —— 锚点（玩家位置 / LevelSlot 位置）
## occupied  —— 全局占位字典
## max_radius—— 搜索半径（默认 2 即覆盖 8 邻；4 = 16 格内）
##
## 返回找到的空格坐标；找不到返回 _NO_DEPLOY_SLOT
func _find_deploy_slot(anchor: Vector2i, occupied: Dictionary, max_radius: int = 2) -> Vector2i:
	# 4 邻优先（与设计 §2.4 一致）
	var four_neighbors: Array[Vector2i] = [
		anchor + Vector2i(0, -1), anchor + Vector2i(0, 1),
		anchor + Vector2i(-1, 0), anchor + Vector2i(1, 0),
	]
	for pos in four_neighbors:
		if _can_deploy_at(pos, occupied):
			return pos
	# 8 邻（含对角）
	if max_radius >= 2:
		var eight_corners: Array[Vector2i] = [
			anchor + Vector2i(-1, -1), anchor + Vector2i(1, -1),
			anchor + Vector2i(-1, 1),  anchor + Vector2i(1, 1),
		]
		for pos in eight_corners:
			if _can_deploy_at(pos, occupied):
				return pos
	# 扩展圈（敌方多 troops 兜底）
	for radius in range(2, max_radius + 1):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if absi(dx) + absi(dy) > radius:
					continue
				if absi(dx) + absi(dy) < radius:
					continue
				var pos: Vector2i = anchor + Vector2i(dx, dy)
				if _can_deploy_at(pos, occupied):
					return pos
	return _NO_DEPLOY_SLOT


## 可占位条件（§2.4 is_valid_deploy_pos）
##   - 战场内 / 地图内
##   - 地形可通行（不是 MOUNTAIN 等）
##   - 不在持久 slot 占据格
##   - 不在 occupied 字典
func _can_deploy_at(pos: Vector2i, occupied: Dictionary) -> bool:
	if not arena.has_point(pos):
		return false
	if not schema.is_in_bounds(pos.x, pos.y):
		return false
	if schema.get_terrain_cost(pos.x, pos.y) >= INF:
		return false
	if occupied.has(pos):
		return false
	# 持久 slot 占据格不可放
	for ps in schema.persistent_slots:
		if ps != null and ps.position == pos:
			return false
	return true


## 判断 _find_deploy_slot 返回的坐标是否合法（区分哨兵）
func _is_valid_slot(slot: Vector2i, occupied: Dictionary) -> bool:
	if slot == _NO_DEPLOY_SLOT:
		return false
	return _can_deploy_at(slot, occupied)


# ─────────────────────────────────────
# 内部 helper：移动 / 行动 / 伤害
# ─────────────────────────────────────

## BFS 计算当前 actor 的可达格
##
## 移动 cost 规则（设计 §2.5）：复用 `MapSchema.terrain_costs`
##   - MOUNTAIN cost = INF（不可通行 / 已被 _can_deploy_at 类似逻辑过滤）
##   - HIGHLAND / LOWLAND cost = 2（高地、洼地两倍消耗）
##   - FLATLAND cost = 1
##   move_range 视为整数 budget，BFS 累加 int(get_terrain_cost) 比较
##   注：BattleAI._plan_move_toward 同样按这套规则计算，保持玩家高亮 / AI 决策一致
func _bfs_reachable(actor: BattleUnit) -> Array[Vector2i]:
	var occupied: Dictionary = _build_occupied()
	var visited: Dictionary = {}
	visited[actor.battle_position] = 0
	var frontier: Array[Vector2i] = [actor.battle_position]
	var move_budget: int = actor.move_range
	while not frontier.is_empty():
		var current: Vector2i = frontier.pop_front()
		var current_cost: int = int(visited[current])
		if current_cost >= move_budget:
			continue
		for offset in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
			var next_pos: Vector2i = current + offset
			if visited.has(next_pos):
				continue
			if not arena.has_point(next_pos):
				continue
			if not schema.is_in_bounds(next_pos.x, next_pos.y):
				continue
			var terrain_cost: float = schema.get_terrain_cost(next_pos.x, next_pos.y)
			if terrain_cost >= INF:
				continue
			if occupied.has(next_pos) and next_pos != actor.battle_position:
				continue
			# 累加地形 cost（int 化避免浮点累积误差）
			var step_cost: int = maxi(1, int(terrain_cost))
			var next_cost: int = current_cost + step_cost
			if next_cost > move_budget:
				continue
			visited[next_pos] = next_cost
			frontier.append(next_pos)
	# 返回除起点外的所有可达格（actor 可以"留在原位"由 skip / 不点击表达，不需要列入可达）
	var result: Array[Vector2i] = []
	for pos in visited:
		var p: Vector2i = pos as Vector2i
		if p != actor.battle_position:
			result.append(p)
	return result


## 构建 occupied 字典：所有存活上场单位的位置 → BattleUnit
func _build_occupied() -> Dictionary:
	var d: Dictionary = {}
	for u in player_units:
		if u.is_active and u.is_alive():
			d[u.battle_position] = u
	for u in enemy_units:
		if u.is_active and u.is_alive():
			d[u.battle_position] = u
	return d


## 攻击伤害计算：地形高度差 + BattleResolver 复用
func _calc_attack_damage(attacker: BattleUnit, target: BattleUnit) -> int:
	var attacker_alt: int = schema.get_terrain_altitude(
		attacker.battle_position.x, attacker.battle_position.y
	)
	var target_alt: int = schema.get_terrain_altitude(
		target.battle_position.x, target.battle_position.y
	)
	var altitude_diff: int = attacker_alt - target_alt
	return BattleResolver.calculate_single_attack(
		attacker.troop, target.troop,
		altitude_diff, terrain_altitude_step,
		battle_config, difficulty, damage_increment,
		attacker.owner_faction
	)


## 在 units 数组中从 start_index 起找下一个可行动的单位索引；找不到返回 -1
##
## "可行动" = is_active && is_alive() && !has_attacked
##           （has_moved 不阻止"仅移动后再跳过"路径，因此不作排除条件）
func _find_next_actor_index(units: Array[BattleUnit], start_index: int) -> int:
	for i in range(start_index, units.size()):
		var u: BattleUnit = units[i]
		if u.is_active and u.is_alive() and not u.has_attacked:
			return i
	return -1


## 触发 redraw 回调
func _request_redraw() -> void:
	if on_redraw_requested.is_valid():
		on_redraw_requested.call()


## 曼哈顿距离
static func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)
