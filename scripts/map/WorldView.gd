class_name WorldView
extends RefCounted
## 世界视图 facade（MVP-β）
##
## 设计原文：
##   tile-advanture-design/代码健康度回看/MVP-β_WorldView接口层.md
##   tile-advanture-design/代码健康度回看/01_结构维度报告.md §4.2
##
## 职责：
##   作为 EnemyAI / EnemyReinforcement 访问世界的唯一入口。这两个 AI 模块原先
##   直接读 WorldMap 的私有字段（`_world_map._schema` / `world_map.get("_schema")`），
##   字符串穿透无编译期校验、WorldMap 字段一改即坏。本 facade 把"AI 需要的世界
##   视图 + 命令"收敛成一组带类型的方法，AI 强类型 against WorldView，访问点
##   编译期可校验。
##
## 设计要点：
##   - facade（读 + 命令），非纯只读视图——AI 既查询世界也命令世界（add_stone 等）。
##   - backing 字段 `_wm` 故意不强类型（Object）：WorldView 是单文件边界层，内部用
##     `.get()` / `.call()` 动态访问 WorldMap，这样测试可注入鸭类型 mock（test_m7
##     的 _MockWorld 不必继承 WorldMap）。关键的编译期校验在下游 AI 那一侧。
##
## 不在本类解决（→ δ 批）：
##   - get_level_slots() 等返回字典引用仍可被调用方 mutate（EnemyReinforcement 会写回）。
##     本批只消除字符串穿透，引用可变性与 EnemyMovement 直接 mutate 同源，δ 批统一收口。


## WorldMap 宿主引用（init 时注入）
## 不强类型——见类注释"设计要点"
var _wm: Object = null


## 注入世界宿主引用
## 调用方：WorldMap._init_subsystems
func init(world: Object) -> void:
	_wm = world


# ─────────────────────────────────────────
# 读访问（10 个）—— 转发 WorldMap 私有字段
# ─────────────────────────────────────────

## 地图 schema
func get_schema() -> MapSchema:
	return _wm.get("_schema") as MapSchema


## 回合管理器
func get_turn_manager() -> TurnManager:
	return _wm.get("_turn_manager") as TurnManager


## 敌方核心 PCG 原始位置（spawn 锚，不查 owner）
func get_enemy_core_origin_pos() -> Vector2i:
	return _wm.get("_enemy_core_origin_pos")


## 关卡 slot 字典（position -> LevelSlot）
func get_level_slots() -> Dictionary:
	return _wm.get("_level_slots") as Dictionary


## 资源 slot 字典（null 兜底为空字典，与旧 EnemyReinforcement 实现保持严格等价）
func get_resource_slots() -> Dictionary:
	var raw: Variant = _wm.get("_resource_slots")
	return raw if raw != null else {}


## 玩家单位
func get_unit() -> UnitData:
	return _wm.get("_unit") as UnitData


## 世界级 RNG
func get_world_rng() -> RandomNumberGenerator:
	return _wm.get("_world_rng") as RandomNumberGenerator


## 敌方部队生成器
func get_enemy_generator() -> EnemyTroopGenerator:
	return _wm.get("_enemy_generator") as EnemyTroopGenerator


## 敌方 tier 配比配置行（按 cycle 加权抽 tier 用）
func get_enemy_tier_ratio_rows() -> Array:
	return _wm.get("_enemy_tier_ratio_rows") as Array


## slot 原始地形类型记录（增援写回 FUNCTION 标记前缓存原类型）
func get_original_slot_types() -> Dictionary:
	return _wm.get("_original_slot_types") as Dictionary


# ─────────────────────────────────────────
# 命令转发（3 个）—— 转发 WorldMap 公共方法
# ─────────────────────────────────────────

## 给指定势力石料库存入账
func add_stone(faction: int, amount: int) -> void:
	_wm.call("add_stone", faction, amount)


## 尝试从指定势力石料库存扣款，成功返回 true
func try_spend_stone(faction: int, amount: int) -> bool:
	return _wm.call("try_spend_stone", faction, amount)


## 启动敌方移动阶段
func start_enemy_move_phase() -> void:
	_wm.call("start_enemy_move_phase")


# ─────────────────────────────────────────
# 渲染读访问（MVP-γ 阶段 2 追加）—— 转发 WorldMap 私有字段
# 供 WorldMapRenderer 在 _draw 入口缓存热路径成员；WorldView 升格为
# "世界读取的唯一入口"（AI 与渲染层共用一套只读视图）。
# ─────────────────────────────────────────

## 探索态可达高亮格集合
func get_reachable_tiles() -> Dictionary:
	return _wm.get("_reachable_tiles") as Dictionary


## 玩家单位插值绘制位置（像素）
func get_unit_visual_pos() -> Vector2:
	return _wm.get("_unit_visual_pos")


## 敌方移动子系统（绘制移动标记 / 查询移动态用）
func get_enemy_movement() -> EnemyMovement:
	return _wm.get("_enemy_movement") as EnemyMovement


## 文字标签字体
func get_label_font() -> Font:
	return _wm.get("_label_font") as Font


## 当前周期是否含敌方核心（持久 slot 绘制分支）
func is_current_cycle_has_enemy_core() -> bool:
	return _wm.get("_current_cycle_has_enemy_core")


## 主动 / 被动战斗触发 + 玩家保护区半径（敌方威胁区绘制用）
func get_battle_trigger_range() -> int:
	return _wm.get("_battle_trigger_range")


## 战斗态是否强制白昼（关卡 slot / 移动标记昼夜分支）
## MVP-δ 阶段 2：转发改指向 NightVisionLayer.is_battle_force_day（保持调用方 API 不变）
func is_battle_force_day() -> bool:
	var nv: NightVisionLayer = _wm.get("_night_vision") as NightVisionLayer
	if nv == null:
		return false
	return nv.is_battle_force_day()


## 当前战斗会话（战斗叠加层绘制用；非战斗态为 null）
func get_battle_session() -> BattleSession:
	return _wm.get("_battle_session") as BattleSession


## 战场暗角遮罩是否激活
func is_battle_zoom_active() -> bool:
	return _wm.get("_battle_zoom_active")


## 战场半径（玩家中心 ±N）
func get_battle_arena_range() -> int:
	return _wm.get("_battle_arena_range")


## 战场中心格（暗角遮罩挖空中心）
func get_battle_center_grid() -> Vector2i:
	return _wm.get("_battle_center_grid")


# ─────────────────────────────────────────
# 渲染辅助方法转发（MVP-γ 阶段 2 追加）—— 转发 WorldMap 方法
# ─────────────────────────────────────────

## 是否处于战斗态
func is_in_battle() -> bool:
	return _wm.call("_is_in_battle")


## 世界像素坐标是否落在浓雾内
## MVP-δ 阶段 2：转发改指向 NightVisionLayer.is_in_fog（保持调用方 API 不变）
func is_in_fog(world_pos: Vector2) -> bool:
	var nv: NightVisionLayer = _wm.get("_night_vision") as NightVisionLayer
	if nv == null:
		return false
	return nv.is_in_fog(world_pos)


## 玩家单位是否正在移动（用于 NightVisionLayer 计算光源位置 —— 移动中读 unit_visual_pos）
## MVP-δ 阶段 2 追加
func is_player_moving() -> bool:
	return _wm.get("_is_moving")


## 取指定格的 LevelSlot（无则 null）
func get_level_at(pos: Vector2i) -> LevelSlot:
	return _wm.call("_get_level_at", pos) as LevelSlot


## 指定格的敌方包是否正在战斗中
func is_pack_in_battle(pos: Vector2i) -> bool:
	return _wm.call("_is_pack_in_battle", pos)


## 格坐标 → 像素中心
func grid_to_pixel_center(grid_pos: Vector2i) -> Vector2:
	return _wm.call("_grid_to_pixel_center", grid_pos)


# ─────────────────────────────────────────
# 写命令端（MVP-δ 阶段 1 追加）—— 转发 WorldMap 私有方法
# EnemyMovement 不再直接 mutate 外部引用（_level_slots / _schema / _original_slot_types），
# 改为通过本段写命令把整组原子写一次性提交到 WorldMap 内部。
# ─────────────────────────────────────────

## 提交一次敌方关卡移动（包整组 7 行原子写）
## 由 EnemyMovement._process_next_move 在选定新位置后调用
##
## 内部行为（详见 WorldMap._commit_enemy_move 实现）：
##   - _level_slots erase(old) / set(new, level)
##   - level.position = new_pos
##   - _schema.set_slot(old, restored_original_type) / set_slot(new, FUNCTION)
##   - _original_slot_types erase(old) / 条件 set(new, schema 当前类型)
func commit_enemy_move(level: LevelSlot, old_pos: Vector2i, new_pos: Vector2i) -> void:
	_wm.call("_commit_enemy_move", level, old_pos, new_pos)


## 尝试让指定势力占据指定位置的持久 slot
## 由 EnemyMovement._try_enemy_occupy_at 在移动动画末尾调用
##
## 内部行为（详见 WorldMap._try_enemy_occupy_persistent_slot 实现）：
##   - 扫 _schema.persistent_slots 找匹配位置
##   - 调 OccupationSystem.try_occupy(ps, faction)
##   - 成功时 WorldMap 内调 _renderer.queue_redraw()（EnemyMovement 侧不再 emit redraw）
func try_enemy_occupy_persistent_slot(pos: Vector2i, faction: int) -> void:
	_wm.call("_try_enemy_occupy_persistent_slot", pos, faction)
