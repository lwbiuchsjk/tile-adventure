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
