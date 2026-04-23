class_name BuildSystem
extends RefCounted
## 升级建造系统（M5）
##
## 设计原文：
##   tile-advanture-design/城建锚实装/M5_升级建造系统.md
##   tile-advanture-design/持久slot升级建造设计.md §三 建造槽位 / §四 建造行为 / §五 升级机制 / §六 每级质变
##
## 职责：
##   - 加载并缓存 persistent_slot_config.csv 的 (type, level) → 数值表
##   - `can_upgrade` / `get_upgrade_cost / _turns` / `is_at_cap` 查询接口（供 UI / 其他模块）
##   - `start_upgrade` 前置校验 + 写 active_build（**不扣石料**，由调用方负责）
##   - `advance_tick` 推进单个 slot 的在建动作，完成时刷 level / max_range / active_build
##   - `cancel_on_takeover` 被敌占清理（语义入口，M4 `OccupationSystem.try_occupy` 内联等价实现）
##
## 不负责：
##   - 石料库存（由 WorldMap 的 `_stone_by_faction` 持有）
##   - TickRegistry 注册（WorldMap orchestrator 做，保持 BuildSystem 无依赖）
##   - UI 渲染（BuildPanelUI 承担）
##   - 产出内容映射（M6 用 output_table_key 自查）
##
## 静态状态 + clear_state：
##   `_level_config` 全局单例；测试场景用 `clear_state()` 重置


# ─────────────────────────────────────────
# 配置缓存
# ─────────────────────────────────────────

## 每级配置表：{ Vector2i(type, level): {initial_range, max_range, growth_rate,
##                                       upgrade_stone_cost, upgrade_turns, output_table_key} }
## 由 load_level_config() 填充；clear_state() 清空
static var _level_config: Dictionary = {}


## 从 ConfigLoader.load_persistent_slot_config() 的返回值加载
## 调用方：WorldMap._ready
static func load_level_config(config_dict: Dictionary) -> void:
	_level_config = config_dict.duplicate(true)


## 清空缓存（仅测试场景）
static func clear_state() -> void:
	_level_config.clear()


## 指定 (type, level) 是否有配置
static func has_level_config(slot_type: int, level: int) -> bool:
	return _level_config.has(Vector2i(slot_type, level))


## 读取指定 (type, level) 的配置字典
## 未配置时返回空字典（调用方用 is_empty() 判断）
static func get_level_config(slot_type: int, level: int) -> Dictionary:
	var key: Vector2i = Vector2i(slot_type, level)
	if not _level_config.has(key):
		return {}
	return _level_config[key] as Dictionary


# ─────────────────────────────────────────
# 查询接口（UI 用）
# ─────────────────────────────────────────

## 下一级升级代价（石料）
## 满级 / 无配置 / 有在建 → 返回 0（UI 侧用 is_at_cap / can_upgrade 判断更精确）
static func get_upgrade_cost(slot: PersistentSlot) -> int:
	if slot == null:
		return 0
	var cfg: Dictionary = get_level_config(slot.type, slot.level)
	if cfg.is_empty():
		return 0
	return int(cfg.get("upgrade_stone_cost", 0))


## 下一级升级耗时（回合）
static func get_upgrade_turns(slot: PersistentSlot) -> int:
	if slot == null:
		return 0
	var cfg: Dictionary = get_level_config(slot.type, slot.level)
	if cfg.is_empty():
		return 0
	return int(cfg.get("upgrade_turns", 0))


## 是否已达等级上限
## 判据：下一级（level + 1）的 (type, level+1) 配置不存在
## 村庄/城镇：L3 之后无 L4 配置 → 上限
## 核心城镇：MVP 仅填 L3 行 → 一来就是上限（L3 锁定）
static func is_at_cap(slot: PersistentSlot) -> bool:
	if slot == null:
		return true
	return not has_level_config(slot.type, slot.level + 1)


# ─────────────────────────────────────────
# 升级启动
# ─────────────────────────────────────────

## 前置校验（不含石料）：归属 / 在建 / 等级上限 / 配置存在
## UI 侧用来决定是否显示升级按钮
static func can_upgrade(slot: PersistentSlot, faction: int) -> bool:
	if slot == null:
		return false
	if faction == Faction.NONE:
		return false
	if slot.owner_faction != faction:
		return false
	if slot.has_active_build():
		return false
	if is_at_cap(slot):
		return false
	# 下一级配置必须存在（is_at_cap 已保证，此处冗余校验）
	return has_level_config(slot.type, slot.level + 1)


## 启动升级：写 active_build
## **不扣石料** —— 调用方先判断石料足够后扣除，再调本函数
## 返回 true = 成功启动，false = 前置失败
##
## 典型调用：
##   if not BuildSystem.can_upgrade(slot, faction): return
##   var cost: int = BuildSystem.get_upgrade_cost(slot)
##   if not stone_ledger.try_spend(faction, cost): return
##   BuildSystem.start_upgrade(slot, faction)
static func start_upgrade(slot: PersistentSlot, faction: int) -> bool:
	if not can_upgrade(slot, faction):
		return false

	var turns: int = get_upgrade_turns(slot)
	if turns <= 0:
		# 配置异常（理论上不会出现，is_at_cap 已拦截）
		push_warning("BuildSystem.start_upgrade: upgrade_turns <= 0，(type=%d, level=%d)" % [slot.type, slot.level])
		return false

	var action: BuildAction = BuildAction.new()
	action.action_type = BuildAction.ActionType.UPGRADE
	action.target_level = slot.level + 1
	action.remaining_turns = turns
	slot.active_build = action
	return true


# ─────────────────────────────────────────
# 回合 tick（由 WorldMap orchestrator 调用）
# ─────────────────────────────────────────

## 推进单个 slot 的在建动作；返回本次 tick 是否触发完成
## 由 WorldMap 的 tick handler 遍历 persistent_slots 时逐个调用
## 归属过滤（只处理 `slot.owner_faction == faction`）由调用方负责
##
## 完成时内部：
##   - slot.level = target_level
##   - 按新等级的 initial_range / max_range / growth_rate 刷字段
##   - max_range 抬升时 influence_range 保持当前值（§六 MVP 边界）
##   - slot.active_build = null
static func advance_tick(slot: PersistentSlot) -> bool:
	if slot == null or slot.active_build == null:
		return false
	var finished: bool = slot.active_build.tick()
	if finished:
		_finish_upgrade(slot)
	return finished


## 完成升级结算（内部）
## 分离出来便于测试单独验证
static func _finish_upgrade(slot: PersistentSlot) -> void:
	if slot == null or slot.active_build == null:
		return
	var target_level: int = slot.active_build.target_level
	slot.level = target_level

	# 按新等级刷影响范围配置 / 兜底 influence_range
	apply_level_fields(slot, target_level)

	slot.active_build = null


## 按 slot.type + level 从 _level_config 读取 initial_range / max_range / growth_rate
## 并赋到 slot；同时把 influence_range 兜底到不低于 initial_range
##
## 用途：
##   - 升级完成（_finish_upgrade 调用）
##   - 地图生成后的字段初始化（WorldMap._ready 对每个 persistent_slot 调一次）
##     否则 L3 初始核心城镇 / L0 初始归属村庄城镇的 range 字段全为 0，
##     影响范围渲染和自阵营快照增长都失效（M2/M4 遗留装配缺口）
##
## influence_range 兜底策略（§六 MVP 边界）：
##   - 不因升级倒退、也不瞬间跃升到 max
##   - 兜底到 initial_range 避免"刚占回的村庄 influence=1、升 L2 后 initial=2"的字段矛盾
##   - 初始化场景下相当于把 influence_range 从 0 拉到 initial_range
static func apply_level_fields(slot: PersistentSlot, level: int) -> void:
	if slot == null:
		return
	var cfg: Dictionary = get_level_config(slot.type, level)
	if cfg.is_empty():
		return
	slot.initial_range = int(cfg.get("initial_range", slot.initial_range))
	slot.max_range = int(cfg.get("max_range", slot.max_range))
	slot.growth_rate = int(cfg.get("growth_rate", slot.growth_rate))
	slot.influence_range = maxi(slot.influence_range, slot.initial_range)


# ─────────────────────────────────────────
# 被敌占取消
# ─────────────────────────────────────────

## 被敌占清零 active_build（不退石料）
## 兼容性入口：M4 `OccupationSystem.try_occupy` 内联等价实现（`slot.active_build = null`），
## 本函数保留作为显式语义入口 / 测试钩子，未来若要聚合更多清理动作在此扩展
static func cancel_on_takeover(slot: PersistentSlot) -> void:
	if slot == null:
		return
	slot.active_build = null
