class_name MapBootstrap
extends RefCounted
## WorldMap 启动协调器（一次性流程对象，跑完即弃）
##
## 设计原文：
##   tile-advanture-design/WorldMap二次重构/批1_MapBootstrap_MVP.md
##
## 形态：RefCounted 实例方法（持有 _world_map 引用 + 中间状态如 map_cfg / terrain_costs 等）
##
## 启动期职责（每阶段一个方法）：
##   阶段 a `load_configs()` ✅ —— CSV 加载 + 数值校验/回退/钳制 + 写入 _world_map 配置字段
##   阶段 b（未实装）—— cycle 应用 + 地图加载（_apply_cycle_config / _load_pcg / _load_json / _cache_enemy_core_origin_pos）
##   阶段 c（未实装）—— 世界状态创建（_world_rng / _unit / _turn_manager / RunState.ensure_initialized）
##   阶段 d（未实装）—— 子系统实例化（_init_subsystems 全段 14 子模块）
##   阶段 e（未实装）—— 启动末尾（_deploy_initial_enemy_packs / 首回合启动 / OverlayTransitionUI 揭幕）
##
## 字段归属约定：
##   WorldMap 的字段（22 子模块字段 + 57 状态字段）仍声明在 WorldMap.gd 内；
##   本类通过 `_world_map._xxx = ...` 写入。
##   本类自己持有的中间状态（map_cfg / terrain_costs / unit_cfg / hero_pool_rows / battle_unit_rows /
##   town_pool_rows / enemy_pool_rows / enemy_tier_rows 等）仅在 _ready 流程内被 WorldMap 后续阶段直读访问
##   （`bootstrap.map_cfg` 等）；run 结束后整个 bootstrap 实例被丢弃，GC 回收所有中间数据。


# ─────────────────────────────────────
# 持有引用 + 中间数据
# ─────────────────────────────────────

## 启动期被启动的 WorldMap（写字段通过 `_world_map._xxx = ...`）
var _world_map: WorldMap

# 阶段 a 产物：CSV 加载中间数据，供后续阶段 b/c/d/e 读
# 命名风格保留原 WorldMap._ready 的本地变量名（迁移摩擦最小）
var map_cfg: Dictionary = {}
var terrain_rows: Array = []
var slot_rows: Array = []
var unit_cfg: Dictionary = {}
var counter_rows: Array = []
var enemy_pool_rows: Array = []
var item_rows: Array = []
var terrain_costs: Dictionary = {}
var slot_allowed: Dictionary = {}
var enemy_tier_rows: Array = []
var hero_pool_rows: Array = []
var narrative_rows: Array = []
var battle_unit_rows: Array = []
var town_pool_rows: Array = []


# ─────────────────────────────────────
# 入口
# ─────────────────────────────────────

func _init(world_map: WorldMap) -> void:
	_world_map = world_map


# ─────────────────────────────────────
# 阶段 a：配置加载
# ─────────────────────────────────────

## 抽离自 WorldMap._ready 原 L456-L605 区段（150 行）
##
## 范围：CSV 加载 + 数值校验/回退/钳制 + 写入 _world_map 配置字段 + 注入静态系统
##
## 副作用（写入 _world_map）：
##   _enemy_tier_ratio_rows / _level_reward_pool_rows / _level_reward_count_* /
##   _turn_reward_pool_rows / _turn_reward_count /
##   _supply / _camp_restore / _damage_increment /
##   _enemy_movement_enabled / _enemy_movement_points / _enemy_target_switch_range /
##   _forced_battle_range / _battle_trigger_range / _battle_arena_range /
##   _terrain_altitude_step / _active_battle_supply_cost / _passive_battle_supply_cost /
##   _garrison_trigger_range / _garrison_total_cap / _battle_unit_config /
##   _resource_slot_config_rows / _reward_generator / _inventory / _enemy_generator /
##   _garrison_config / _enemy_garrison_config
##
## 副作用（静态系统）：
##   BattleResolver.load_counter_matrix / load_hp_ratio_config / NarrativeProvider.ensure_loaded /
##   RunState.ensure_initialized / TroopData.load_upgrade_config / ProductionSystem.load_troop_pool
##
## 中间数据写入 self（供后续阶段读）：
##   map_cfg / terrain_rows / slot_rows / unit_cfg / counter_rows / enemy_pool_rows /
##   item_rows / terrain_costs / slot_allowed / enemy_tier_rows / hero_pool_rows /
##   narrative_rows / battle_unit_rows / town_pool_rows
func load_configs() -> void:
	# 基础配置 CSV 加载
	map_cfg = ConfigLoader.load_csv_kv(WorldMap.CONFIG_MAP)
	terrain_rows = ConfigLoader.load_csv(WorldMap.CONFIG_TERRAIN)
	slot_rows = ConfigLoader.load_csv(WorldMap.CONFIG_SLOT)
	unit_cfg = ConfigLoader.load_csv_kv(WorldMap.CONFIG_UNIT)
	counter_rows = ConfigLoader.load_csv(WorldMap.CONFIG_COUNTER)
	enemy_pool_rows = ConfigLoader.load_csv(WorldMap.CONFIG_ENEMY_POOL)
	item_rows = ConfigLoader.load_csv(WorldMap.CONFIG_ITEM)

	# 加载奖励池配置（缓存行数据供后续按轮次过滤）
	_world_map._level_reward_pool_rows = ConfigLoader.load_csv(WorldMap.CONFIG_LEVEL_REWARD_POOL)
	_world_map._level_reward_count_min = WorldMap.LEVEL_REWARD_PARAM_CFG.reward_count_min
	_world_map._level_reward_count_max = WorldMap.LEVEL_REWARD_PARAM_CFG.reward_count_max

	_world_map._turn_reward_pool_rows = ConfigLoader.load_csv(WorldMap.CONFIG_TURN_REWARD_POOL)
	_world_map._turn_reward_count = WorldMap.TURN_REWARD_PARAM_CFG.reward_count

	# 构建地形消耗表和 Slot 允许表
	# 注：_build_terrain_costs / _build_slot_allowed 是 WorldMap 的私有方法（L3276+ 段，配置构建工具）
	# 本批保留在 WorldMap.gd 内，MapBootstrap 通过对象方法引用调用
	terrain_costs = _world_map._build_terrain_costs(terrain_rows)
	slot_allowed = _world_map._build_slot_allowed(slot_rows)

	# 加载克制矩阵
	BattleResolver.load_counter_matrix(counter_rows)

	# 加载兵力系数分段配置
	var hp_ratio_rows: Array = ConfigLoader.load_csv(WorldMap.CONFIG_HP_RATIO)
	BattleResolver.load_hp_ratio_config(hp_ratio_rows)

	# 加载补给配置
	_world_map._supply = WorldMap.SUPPLY_PARAM_CFG.initial_supply
	_world_map._camp_restore = WorldMap.SUPPLY_PARAM_CFG.camp_restore

	# 加载敌人强度配置（generator 初始化后再注入，见下方）
	enemy_tier_rows = ConfigLoader.load_csv(WorldMap.CONFIG_ENEMY_TIER)

	# P0 第二阶段：加载 enemy_tier_ratio_config（按 cycle 抽 tier 用，EnemyReinforcement.spawn_batch 消费）
	_world_map._enemy_tier_ratio_rows = ConfigLoader.load_csv(WorldMap.CONFIG_ENEMY_TIER_RATIO)

	# B 重生周期 MVP：英雄池 + 整局周期参数
	# RunState.ensure_initialized 幂等：首次进入写入；重生场景 reload 时
	# _initialized=true，沿用上一周期累积的 _cycle_index / _used_hero_ids 等
	hero_pool_rows = ConfigLoader.load_csv(WorldMap.CONFIG_HERO_POOL)
	# 入口 2 MVP 2.3(2026-05-11):加载事件叙事池(NarrativeProvider 静态工具类内部 _initialized 防重复加载)
	narrative_rows = ConfigLoader.load_csv(WorldMap.CONFIG_NARRATIVE_POOL)
	NarrativeProvider.ensure_loaded(narrative_rows)
	var max_cycles_v: int = WorldMap.RUN_PARAM_CFG.max_cycles
	# MVP-δ 阶段 2：coma_duration_sec / coma_hp_threshold_ratio 从 run_cfg 注入移到
	# PlayerLifecycle.setup 内（_player_lifecycle 在 _init_player 调用点创建）
	# rng 传 null：RunState 内部 randomize 一个独立 RNG，不被地图 PCG seed 干扰
	# （重生抽队长应与地图 PCG 解耦，否则同 seed 重开会抽到同一队长序列）
	RunState.ensure_initialized(max_cycles_v, hero_pool_rows, null)

	# 加载资源点配置
	_world_map._resource_slot_config_rows = ConfigLoader.load_csv(WorldMap.CONFIG_RESOURCE_SLOT)

	# 加载品质升级配置
	TroopData.load_upgrade_config(WorldMap.QUALITY_UPGRADE_PARAM_CFG)

	# 加载难度配置
	_world_map._damage_increment = WorldMap.DIFFICULTY_PARAM_CFG.damage_increment

	# 加载敌方移动配置（MVP-D D.2：类型化 Resource 直读，bool/int 字段无需转换）
	_world_map._enemy_movement_enabled = WorldMap.BATTLE_PARAM_CFG.enemy_movement_enabled
	_world_map._enemy_movement_points = WorldMap.BATTLE_PARAM_CFG.enemy_movement_points

	# 审查 P2 修复：阈值失效会让 AI 几乎永远推核心
	# 校验保留：.tres 被设为非法值（< 1）时回退到默认 10 + push_warning 便于排障
	var raw_switch_range: int = WorldMap.BATTLE_PARAM_CFG.enemy_target_switch_range
	if raw_switch_range < 1:
		push_warning("WorldMap: battle_param.enemy_target_switch_range 非法值 %d，回退到 10" % raw_switch_range)
		_world_map._enemy_target_switch_range = 10
	else:
		_world_map._enemy_target_switch_range = raw_switch_range

	# 强制战斗触发距离（A 基线收束 MVP）
	# 默认 3；.tres 写坏（≤ 0）时回退到默认 + push_warning，参考上面 enemy_target_switch_range 的兜底
	var raw_force_range: int = WorldMap.BATTLE_PARAM_CFG.forced_battle_range
	if raw_force_range < 1:
		push_warning("WorldMap: battle_param.forced_battle_range 非法值 %d，回退到 3" % raw_force_range)
		_world_map._forced_battle_range = 3
	else:
		_world_map._forced_battle_range = raw_force_range

	# E 战斗就地展开 MVP 配置（E1 仅加载到字段，E3 实装时由 BattleSession 消费）
	# battle_trigger_range 下限 1（maxi 钳制，防 .tres 设为 0）
	var raw_trigger: int = WorldMap.BATTLE_PARAM_CFG.battle_trigger_range
	_world_map._battle_trigger_range = maxi(1, raw_trigger)
	var raw_arena: int = WorldMap.BATTLE_PARAM_CFG.battle_arena_range
	_world_map._battle_arena_range = maxi(_world_map._battle_trigger_range, raw_arena)  # 战场至少不小于触发距离
	_world_map._terrain_altitude_step = WorldMap.BATTLE_PARAM_CFG.terrain_altitude_step
	_world_map._active_battle_supply_cost = maxi(0, WorldMap.BATTLE_PARAM_CFG.active_battle_supply_cost)
	_world_map._passive_battle_supply_cost = maxi(0, WorldMap.BATTLE_PARAM_CFG.passive_battle_supply_cost)

	# 持久 slot 援军（L1.2）触发参数
	# 下限 0（不同于 _battle_trigger_range 的下限 1）：range=0 表示"仅战场覆盖 slot 格才触发"，是有效旋钮
	_world_map._garrison_trigger_range = maxi(0, WorldMap.BATTLE_PARAM_CFG.garrison_trigger_range)
	_world_map._garrison_total_cap = maxi(0, WorldMap.BATTLE_PARAM_CFG.garrison_total_cap)

	# E MVP：兵种战斗参数（移动 / 攻击范围）解析为 { TroopType_int : Dictionary }
	# 兵种名 → ID 复用 BattleResolver.TROOP_NAME_TO_ID
	# 配置下限：move_range >= 1（移动力不能为 0，否则单位被卡住）
	#         attack_range >= 1（攻击范围不能为 0，否则单位无法攻击）
	# 非法值回退到 SWORD 默认（3/1）+ push_warning
	battle_unit_rows = ConfigLoader.load_csv(WorldMap.CONFIG_BATTLE_UNIT)
	_world_map._battle_unit_config = {}
	for entry in battle_unit_rows:
		var row: Dictionary = entry as Dictionary
		var unit_name: String = String(row.get("troop_type", ""))
		if not BattleResolver.TROOP_NAME_TO_ID.has(unit_name):
			push_warning("WorldMap: battle_unit_config 未知兵种 '%s'，跳过" % unit_name)
			continue
		var key: int = int(BattleResolver.TROOP_NAME_TO_ID[unit_name])
		var raw_move: int = int(row.get("move_range", "3"))
		var raw_attack: int = int(row.get("attack_range", "1"))
		var move_v: int = raw_move
		var attack_v: int = raw_attack
		if raw_move < 1:
			push_warning("WorldMap: battle_unit_config[%s].move_range 非法值 %d，回退到 3" % [unit_name, raw_move])
			move_v = 3
		if raw_attack < 1:
			push_warning("WorldMap: battle_unit_config[%s].attack_range 非法值 %d，回退到 1" % [unit_name, raw_attack])
			attack_v = 1
		_world_map._battle_unit_config[key] = {
			"move_range": move_v,
			"attack_range": attack_v,
		}

	# 初始化奖励生成器
	_world_map._reward_generator = RewardGenerator.new()
	_world_map._reward_generator.load_item_templates(item_rows)

	# 初始化背包
	_world_map._inventory = Inventory.new()
	_world_map._inventory.init_from_config(WorldMap.INVENTORY_PARAM_CFG)

	# 初始化敌方部队生成器
	_world_map._enemy_generator = EnemyTroopGenerator.new()
	_world_map._enemy_generator.init_from_config(enemy_pool_rows, WorldMap.ENEMY_SPAWN_PARAM_CFG)
	_world_map._enemy_generator.load_tier_config(enemy_tier_rows)

	# M6: 产出结算——城镇部队道具池走独立 CSV（不污染敌方生成权重）
	town_pool_rows = ConfigLoader.load_csv(WorldMap.CONFIG_TOWN_TROOP_POOL)
	if town_pool_rows.is_empty():
		push_error("WorldMap: town_troop_pool.csv 加载失败或为空；城镇 / 核心城镇产出会静默无输出")
	ProductionSystem.load_troop_pool(town_pool_rows)

	# 持久 slot 援军（L1.2）：加载 garrison_config 并解析为嵌套查表字典（slot_type → cycle → cfg）
	# 储备名册抽样在下方地图装配阶段（owner 染色完成后）逐 slot 执行
	_world_map._garrison_config = ReinforcementRoster.build_config(ConfigLoader.load_csv(WorldMap.CONFIG_GARRISON))
	# 敌方援军（L1.4）：加载敌方独立强度表（结构同上），抽样时按 slot 初始 owner 选用
	_world_map._enemy_garrison_config = ReinforcementRoster.build_config(ConfigLoader.load_csv(WorldMap.CONFIG_ENEMY_GARRISON))


# ─────────────────────────────────────
# 阶段 b：cycle 应用 + 地图加载
# ─────────────────────────────────────

## 阶段 b 入口：cycle 应用 + 起终点读取 + 地图加载 + schema 配置注入 + enemy_core 缓存
## 抽离自 WorldMap._ready 原 L468-L499 区段（含 _apply_cycle_config / _load_pcg /
## _load_json / _cache_enemy_core_origin_pos 4 个函数）
##
## 内部按顺序：
##   1. _apply_cycle_config_internal —— cycle_config 覆盖 self.map_cfg + 写 _world_map._current_cycle_*
##   2. 读取 start/end → _world_map._start_pos / _end_pos
##   3. _load_pcg_internal / _load_json_internal 分流 → 写 _world_map._schema 与 _world_rng
##   4. 注入 _world_map._schema.terrain_costs / slot_allowed_terrains
##   5. _cache_enemy_core_origin_pos_internal —— 缓存 _world_map._enemy_core_origin_pos
##
## 失败：_world_map._schema 保持 null；调用方 _ready 据此报错跳出
func load_map() -> void:
	_apply_cycle_config_internal()

	# 读取起终点坐标（经 _apply_cycle_config 注入后，map_cfg 已包含本周期值）
	_world_map._start_pos = Vector2i(
		int(map_cfg.get("start_x", "1")),
		int(map_cfg.get("start_y", "1"))
	)
	_world_map._end_pos = Vector2i(
		int(map_cfg.get("end_x", "30")),
		int(map_cfg.get("end_y", "22"))
	)

	# 根据配置选择加载模式
	var is_random: bool = map_cfg.get("random_generate", "true") == "true"
	if is_random:
		_load_pcg_internal()
	else:
		_load_json_internal()

	# 将配置注入到 schema
	if _world_map._schema != null:
		_world_map._schema.terrain_costs = terrain_costs
		_world_map._schema.slot_allowed_terrains = slot_allowed

	# P0 第二阶段：PCG 完成后缓存敌方 CORE_TOWN 原始位置
	# 供 EnemyReinforcement.spawn_batch 用作 spawn 锚（不查 owner，避免玩家占领后失效）
	_cache_enemy_core_origin_pos_internal()


## P0 第二阶段（整局节奏重设计）：用 cycle_config.csv 覆盖 map_cfg 的周期级字段
##
## 处理流程：
##   1. 加载 cycle_config.csv → _world_map._cycle_config_rows
##   2. 按 RunState.cycle_index() 找对应行
##   3. 找到则把 map_width / map_height / start_x/y / end_x/y / persistent_total_count
##      / persistent_town_count / persistent_village_count 字段覆盖到 self.map_cfg 字典；
##      has_enemy_core 推导 persistent_core_count = "1"（始终生成 1 个敌方 CORE_TOWN）
##   4. 缓存 initial_enemy_pack_count / reinforcement_interval / has_enemy_core 到 _world_map 字段
##   5. 找不到则 push_warning，map_cfg 字段保留原值（map_config 兜底）；spawn 节奏字段用默认
##
## 设计意图：把"按 cycle 切配置"对调用方透明——后续 _load_pcg_internal 读 map_cfg 时拿到的是本周期值
func _apply_cycle_config_internal() -> void:
	_world_map._cycle_config_rows = ConfigLoader.load_csv(WorldMap.CONFIG_CYCLE)
	var current_cycle: int = RunState.cycle_index()
	var cycle_row: Dictionary = {}
	for entry in _world_map._cycle_config_rows:
		var row: Dictionary = entry as Dictionary
		if row == null:
			continue
		if int(row.get("cycle_index", "-1")) == current_cycle:
			cycle_row = row
			break

	if cycle_row.is_empty():
		push_warning("WorldMap: cycle_config 未找到 cycle_index=%d 对应行，使用 map_config 兜底" % current_cycle)
		# 兜底：spawn 节奏字段用默认值（initial pack 5 / interval 5）
		_world_map._current_cycle_initial_pack_count = 5
		_world_map._current_cycle_reinforcement_interval = 5
		_world_map._current_cycle_has_enemy_core = false
		return

	# 用 cycle row 覆盖 map_cfg 中对应字段（后续 _load_pcg 读 map_cfg 拿到本周期值）
	# persistent_total_count 不在此列表 —— 由 core(1) + town + village 自动推导避免配置错位
	var override_keys: Array[String] = [
		"map_width", "map_height", "start_x", "start_y", "end_x", "end_y",
		"persistent_town_count", "persistent_village_count",
	]
	for key in override_keys:
		if cycle_row.has(key):
			map_cfg[key] = str(cycle_row[key])

	# has_enemy_core 推导 persistent_core_count（数据层始终生成 1 个，视觉 / 判定由 has_enemy_core 控制）
	# 当前 MVP：始终 1（has_enemy_core=false 时仅视觉走普通 TOWN + VictoryJudge cycle 过滤拦截胜利）
	map_cfg["persistent_core_count"] = "1"

	# P0 第二阶段（跑测 BUG 修复 2026-05-11）：persistent_total_count 由 1 + town + village 自动推导
	# 原因：csv 中 total 与 town/village 是冗余双写，用户手动调整时极易错位（如 cycle_config
	# 调整地图大小时改了 total 忘改 town/village），导致 PCG 校验失败
	# cycle_config.csv 中 persistent_total_count 字段保留作"目标参考"（编辑时可见目标总数），
	# 但 PCG 实际用推导值；字段值与推导值不一致时 push_warning 提示
	var derived_town: int = int(map_cfg.get("persistent_town_count", "7"))
	var derived_village: int = int(map_cfg.get("persistent_village_count", "18"))
	var derived_total: int = 1 + derived_town + derived_village
	if cycle_row.has("persistent_total_count"):
		var declared_total: int = int(cycle_row.get("persistent_total_count", "0"))
		if declared_total != derived_total:
			push_warning("WorldMap: cycle_config[%d].persistent_total_count=%d 与 1+town(%d)+village(%d)=%d 不一致；以推导值 %d 为准" % [
				current_cycle, declared_total, derived_town, derived_village, derived_total, derived_total
			])
	map_cfg["persistent_total_count"] = str(derived_total)

	# 缓存周期级字段
	# initial_enemy_pack_count: 钳制 ≥ 0（0 = 本周期不预置初始 pack，合理边界）
	# reinforcement_interval: 钳制 ≥ 1（避免 EnemyAI._step_reinforcement 的 count % interval 除零崩溃）
	var raw_pack: int = int(cycle_row.get("initial_enemy_pack_count", "5"))
	var raw_interval: int = int(cycle_row.get("reinforcement_interval", "5"))
	if raw_pack < 0:
		push_warning("WorldMap: cycle_config[%d].initial_enemy_pack_count 非法 %d，钳制为 0" % [current_cycle, raw_pack])
	if raw_interval < 1:
		push_warning("WorldMap: cycle_config[%d].reinforcement_interval 非法 %d，钳制为 1 防除零" % [current_cycle, raw_interval])
	_world_map._current_cycle_initial_pack_count = maxi(0, raw_pack)
	_world_map._current_cycle_reinforcement_interval = maxi(1, raw_interval)

	# P0 第二阶段 P1-2a 修复：缓存 has_enemy_core，视觉绘制改用该字段（替代硬编码 is_last_cycle()）
	# VictoryJudge.check_on_slot_owner_changed 仍用 RunState.is_last_cycle()——static 路径不便注入
	# MVP 期 has_enemy_core 与 is_last_cycle() 同义；若未来配置错位需 VictoryJudge 也切到该字段
	_world_map._current_cycle_has_enemy_core = str(cycle_row.get("has_enemy_core", "false")).to_lower() == "true"


## PCG 模式加载：FastNoiseLite + 通达性 BFS 校验 + 持久 slot 涌现生成
## 抽离自 WorldMap._load_pcg
func _load_pcg_internal() -> void:
	var pcg_cfg: Dictionary = ConfigLoader.load_csv_kv(WorldMap.CONFIG_PCG)

	var config: MapGenerator.GenerateConfig = MapGenerator.GenerateConfig.new()
	config.width = int(map_cfg.get("map_width", "32"))
	config.height = int(map_cfg.get("map_height", "24"))

	# 种子处理：-1 表示每次自动随机，其他值固定
	# M2 P1#4：自动随机走 Time 派生而非全局 randi()，并显式打印实际 seed 便于复现
	var seed_value: int = int(map_cfg.get("random_seed", "-1"))
	if seed_value == -1:
		config.seed = int(Time.get_ticks_usec())
		print("[WorldMap] 自动 seed = %d（如需复现把 map_config.csv random_seed 改为该值）" % config.seed)
	else:
		config.seed = seed_value
	# 创建本局共享 RNG，注入 seed
	_world_map._world_rng = RandomNumberGenerator.new()
	_world_map._world_rng.seed = config.seed

	# 通达性校验起终点
	config.start = _world_map._start_pos
	config.end = _world_map._end_pos

	# PCG 生成参数
	config.threshold_mountain = float(pcg_cfg.get("threshold_mountain", "0.45"))
	config.threshold_highland = float(pcg_cfg.get("threshold_highland", "0.15"))
	config.threshold_flatland = float(pcg_cfg.get("threshold_flatland", "-0.25"))
	config.noise_frequency = float(pcg_cfg.get("noise_frequency", "0.08"))
	config.max_retries = int(pcg_cfg.get("max_retries", "10"))

	# 注入地形消耗配置（BFS 通达性校验需要）
	config.terrain_costs = terrain_costs

	# M2：从 map_config 加载持久 slot 八阶段参数
	config.persistent_total_count = int(map_cfg.get("persistent_total_count", "26"))
	# P0 X-A 后默认 1 敌方核心 + 7 城镇（含玩家方占位）；CSV 通常会覆盖此处默认
	config.persistent_core_count = int(map_cfg.get("persistent_core_count", "1"))
	config.persistent_town_count = int(map_cfg.get("persistent_town_count", "7"))
	config.persistent_village_count = int(map_cfg.get("persistent_village_count", "18"))
	config.persistent_min_dist_normal = int(map_cfg.get("persistent_min_dist_normal", "3"))
	config.persistent_min_dist_core = int(map_cfg.get("persistent_min_dist_core", "5"))
	config.persistent_emerge_steps = int(map_cfg.get("persistent_emerge_steps", "3"))
	config.persistent_field_radius = int(map_cfg.get("persistent_field_radius", "20"))
	config.persistent_core_zone_min = float(map_cfg.get("persistent_core_zone_min", "0.125"))
	config.persistent_core_zone_max = float(map_cfg.get("persistent_core_zone_max", "0.25"))
	config.persistent_max_retries = int(map_cfg.get("persistent_max_retries", "5"))
	config.persistent_faction_town_quota = int(map_cfg.get("persistent_faction_town_quota", "2"))
	config.persistent_faction_village_quota = int(map_cfg.get("persistent_faction_village_quota", "6"))

	_world_map._schema = MapGenerator.generate(config)
	if _world_map._schema == null:
		push_error("WorldMap: PCG 地图生成失败")


## JSON 模式加载：从配置中读取文件路径后加载
## 抽离自 WorldMap._load_json
func _load_json_internal() -> void:
	var path: String = map_cfg.get("json_path", "") as String
	if path.is_empty():
		push_error("WorldMap: map_config 中未配置 json_path")
		return
	_world_map._schema = MapLoader.load_from_file(path)
	if _world_map._schema == null:
		push_error("WorldMap: JSON 地图加载失败，路径：" + path)


## P0 第二阶段：PCG 生成后从 schema 找敌方 CORE_TOWN 位置缓存到 _enemy_core_origin_pos
##
## 设计原因：EnemyReinforcement.spawn_batch 当前查 owner=ENEMY_1 的 CORE_TOWN 作 spawn 锚，
##           前两周期玩家占领后 owner 翻转 → reinforcement 失效。改为缓存"PCG 生成时的原始位置"，
##           不查 owner——玩家占领后敌方仍从该位置周围 spawn。
##
## 抽离自 WorldMap._cache_enemy_core_origin_pos
func _cache_enemy_core_origin_pos_internal() -> void:
	if _world_map._schema == null:
		_world_map._enemy_core_origin_pos = Vector2i(-1, -1)
		return
	for entry in _world_map._schema.persistent_slots:
		var slot: PersistentSlot = entry as PersistentSlot
		if slot == null:
			continue
		if slot.type == PersistentSlot.Type.CORE_TOWN and slot.owner_faction == Faction.ENEMY_1:
			_world_map._enemy_core_origin_pos = slot.position
			return
	push_warning("WorldMap: PCG 后未找到敌方 CORE_TOWN，_enemy_core_origin_pos 保持 (-1,-1)；reinforcement 将跳过")
	_world_map._enemy_core_origin_pos = Vector2i(-1, -1)
