class_name MapBootstrap
extends RefCounted

## 世界内容生成参数（L1.3c 阶段 A：网格抖动撒点；结构性参数，改 = 换内容分布，重启生效）
const CONTENT_CFG: ContentConfig = preload("res://assets/config/content_config.tres")
## WorldMap 启动协调器（一次性流程对象，跑完即弃）
##
## 设计原文：
##   tile-advanture-design/WorldMap二次重构/批1_MapBootstrap_MVP.md
##
## 形态：RefCounted 实例方法（持有 _world_map 引用 + 中间状态如 map_cfg / terrain_costs 等）
##
## 启动期职责（每阶段一个方法）：
##   阶段 a `load_configs()` ✅ —— CSV 加载 + 数值校验/回退/钳制 + 写入 _world_map 配置字段
##   阶段 b（未实装）—— cycle 应用 + 地图加载（_apply_cycle_config / _load_pcg / _load_json）
##   阶段 c（未实装）—— 世界状态创建（_world_rng / _unit / _turn_manager / RunState.ensure_initialized）
##   阶段 d（未实装）—— 子系统实例化（_init_subsystems 全段 14 子模块）
##   阶段 e（未实装）—— 启动末尾（首回合启动 / ContentSpawner 接线 / 视野启动 / OverlayTransitionUI 揭幕）
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
	# L1.3a 阶段 A：命数独立计数 K 从 run_cfg 注入（脱钩 cycle，收口待跟踪 P1-2）
	var no_stronghold_respawns_v: int = WorldMap.RUN_PARAM_CFG.no_stronghold_respawns
	# MVP-δ 阶段 2：coma_duration_sec / coma_hp_threshold_ratio 从 run_cfg 注入移到
	# PlayerLifecycle.setup 内（_player_lifecycle 在 _init_player 调用点创建）
	# rng 传 null：RunState 内部 randomize 一个独立 RNG，不被地图 PCG seed 干扰
	# （重生抽队长应与地图 PCG 解耦，否则同 seed 重开会抽到同一队长序列）
	RunState.ensure_initialized(max_cycles_v, hero_pool_rows, null, no_stronghold_respawns_v)

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

## 阶段 b 入口：cycle 应用 + 起终点读取 + 地图加载 + schema 配置注入
## 抽离自 WorldMap._ready 原 L468-L499 区段（含 _apply_cycle_config / _load_pcg /
## _load_json 3 个函数）
##
## 内部按顺序：
##   1. _apply_cycle_config_internal —— cycle_config 覆盖 self.map_cfg + 写 _world_map._current_cycle_*
##   2. 读取出生点首选坐标 → _world_map._start_pos
##   3. _load_pcg_internal / _load_json_internal 分流 → 写 _world_map._schema 与 _world_rng
##   4. 注入 _world_map._schema.terrain_costs / slot_allowed_terrains
##
## 失败：_world_map._schema 保持 null；调用方 _ready 据此报错跳出
func load_map() -> void:
	_apply_cycle_config_internal()

	# 读取出生点首选坐标（经 _apply_cycle_config 注入后，map_cfg 已包含本周期值）
	# L1.3c 阶段 A：出生居中——默认世界原点 (0,0)，实际落位由 _resolve_spawn 局部校验微调
	_world_map._start_pos = Vector2i(
		int(map_cfg.get("start_x", "0")),
		int(map_cfg.get("start_y", "0"))
	)
	# _end_pos 已随阶段 B 资源生成改道退役（L1.3b 起即死字段；CSV 的 end_x/y 列保留不再消费）

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
	# L1.3c 阶段 C：敌核心锚缓存已退役——增援改从玩家视野外暗影环带采样（EnemyReinforcement.spawn_batch），
	# 不再依赖 PCG 后缓存的固定锚位置


## P0 第二阶段（整局节奏重设计）：用 cycle_config.csv 覆盖 map_cfg 的周期级字段
##
## 处理流程：
##   1. 加载 cycle_config.csv → _world_map._cycle_config_rows
##   2. 恒读 cycle 0 行（L1.3a 阶段 D 固定单图）
##   3. 找到则把 map_width / map_height / start_x/y / end_x/y 覆盖到 self.map_cfg 字典
##      （L1.3c 阶段 A：persistent_* 数量覆盖随八阶段生成器退役删除，撒点参数走 content_config.tres）
##   4. 缓存 initial_enemy_pack_count / reinforcement_interval / has_enemy_core 到 _world_map 字段
##   5. 找不到则 push_warning，map_cfg 字段保留原值（map_config 兜底）；spawn 节奏字段用默认
##
## 设计意图：把"按 cycle 切配置"对调用方透明——后续 _load_pcg_internal 读 map_cfg 时拿到的是本周期值
func _apply_cycle_config_internal() -> void:
	_world_map._cycle_config_rows = ConfigLoader.load_csv(WorldMap.CONFIG_CYCLE)
	# L1.3a 阶段 D：固定单图——一局一张连续世界，恒读 cycle 0 行（不再按 RunState.cycle_index() 取行）。
	# 周期递增=地图尺寸递减的挂载点退役；敌方威胁递增改扎营时钟驱动留子 MVP ②。
	var current_cycle: int = 0
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
	# L1.3c 阶段 A：persistent_* 数量/配额覆盖随八阶段生成器退役删除——
	# 撒点参数（cell_size / spawn_rate / town_ratio）改由 content_config.tres 提供，
	# cycle_config 中的 persistent_total/town/village_count 列保留但不再被消费
	var override_keys: Array[String] = [
		"map_width", "map_height", "start_x", "start_y", "end_x", "end_y",
	]
	for key in override_keys:
		if cycle_row.has(key):
			map_cfg[key] = str(cycle_row[key])

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

	# 出生点首选坐标（L1.3c 阶段 A：出生居中，默认原点）
	config.start = _world_map._start_pos

	# PCG 生成参数
	# 【L1.3b 阶段 A】地形阈值/频率随地形权威收敛到 ChunkPCG 已退役，不再从 pcg_config 读（codex P1-2）
	config.max_retries = int(pcg_cfg.get("max_retries", "10"))

	# 注入地形消耗配置（出生局部校验 / 撒点可走判定需要）
	config.terrain_costs = terrain_costs

	# L1.3c 阶段 A：撒点参数来自 content_config.tres（剥离原则：schema @export + @tunable 埋点）
	# 旧八阶段流水线的 13 个 persistent_* CSV 键随生成器重写退役
	config.persistent_cell_size = CONTENT_CFG.cell_size
	config.persistent_slot_spawn_rate = CONTENT_CFG.slot_spawn_rate
	config.persistent_town_ratio = CONTENT_CFG.town_ratio

	_world_map._schema = MapGenerator.generate(config)
	if _world_map._schema == null:
		push_error("WorldMap: PCG 地图生成失败")
		return
	# 【L1.3b 阶段 A】回读局部出生校验解析出的出生点（缺陷 5）：
	# 无限模式地形固定不可 reseed，出生点可能被微调到附近可走点，需覆盖 _start_pos
	# 使玩家 spawn（finalize 阶段 _unit.position = _start_pos）与首个视野源落在可走开阔地
	_world_map._start_pos = _world_map._schema.spawn_pos


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


## L1.3c 阶段 B：创建 ContentSpawner 并订阅 chunk 首次生成信号
##
## 时机约束：finalize_startup 内、EC.init_vision_runtime（玩家视野源注册 = 首批 chunk
## 生成触发点）之前——订阅晚了首批 chunk 信号就漏掉了。
## 撒点参数与开局批共用同一来源（CONTENT_CFG + world_seed），保证规则同一套。
func _wire_content_spawner_internal() -> void:
	if _world_map._schema == null or _world_map._chunk_manager == null:
		push_warning("MapBootstrap: schema / chunk_manager 未就绪，跳过 ContentSpawner 接线")
		return

	# 撒点参数：与 _load_pcg_internal 装载的开局批同源（cell 纯函数 → 新旧区域天然一致）
	var gcfg: PersistentSlotGenerator.GenConfig = PersistentSlotGenerator.GenConfig.new()
	gcfg.seed = _world_map._chunk_manager._world_seed
	gcfg.cell_size = CONTENT_CFG.cell_size
	gcfg.slot_spawn_rate = CONTENT_CFG.slot_spawn_rate
	gcfg.town_ratio = CONTENT_CFG.town_ratio

	# 玩家锚点：距出生点最近的玩家方持久 slot（此时占领未发生，唯一 PLAYER slot 即开局锚点）
	var anchor_pos: Vector2i = PersistentSlotGenerator.NO_POS
	var anchor_dist: int = 2147483647
	for entry in _world_map._schema.persistent_slots:
		var slot: PersistentSlot = entry as PersistentSlot
		if slot == null or slot.owner_faction != Faction.PLAYER:
			continue
		var dist: int = absi(slot.position.x - _world_map._start_pos.x) \
			+ absi(slot.position.y - _world_map._start_pos.y)
		if dist < anchor_dist:
			anchor_dist = dist
			anchor_pos = slot.position

	var chunk_size: int = WorldMap.VISION_CFG.chunk_size if WorldMap.VISION_CFG.chunk_size > 0 \
		else ChunkManager.DEFAULT_CHUNK_SIZE

	var spawner: ContentSpawner = ContentSpawner.new()
	spawner.setup(
		_world_map._schema, gcfg, anchor_pos, chunk_size,
		_world_map._resource_slots, _world_map._level_slots,
		_world_map._resource_slot_config_rows, CONTENT_CFG.resource_quota_per_chunk,
		_world_map._garrison_config, town_pool_rows,
		Callable(_world_map._renderer, "queue_redraw")
	)
	spawner.attach(_world_map._chunk_manager)
	_world_map._content_spawner = spawner


# ─────────────────────────────────────
# 阶段 c：世界状态创建
# ─────────────────────────────────────

## 抽离自 WorldMap._ready 原 L475-L503 区段（29 行）
##
## 副作用（写 _world_map）：
##   _unit / _player_lifecycle / _unit_visual_pos / _turn_manager
##
## 顺序固定（不能调）：
##   1. _unit 创建（PlayerLifecycle 不依赖；后续 _turn_manager.register_unit 依赖）
##   2. _player_lifecycle 创建 + sink 接线 + setup
##      ↑ 必须在 _turn_manager 创建之前——setup 内可能 emit signal（respawn_intro_ready /
##        coma_triggered 等），sink 要先接线否则首次 emit 会丢
##   3. _unit_visual_pos 初始化（_grid_to_pixel_center 依赖 _world_map._start_pos）
##   4. _turn_manager 创建 + register_unit + faction_turn_started sink
func create_world_state() -> void:
	# 初始化单位（移动系统）
	var default_movement: int = int(unit_cfg.get("default_movement", "6"))
	_world_map._unit = UnitData.new()
	_world_map._unit.position = _world_map._start_pos
	_world_map._unit.max_movement = default_movement
	_world_map._unit.current_movement = default_movement

	# MVP-δ 阶段 2：玩家 lifecycle 子系统创建 + setup（原 _init_player 主体迁入）
	# 必须在 _turn_manager 创建之前——setup 内 emit respawn_intro_ready / coma_triggered 等
	# 信号目前不立即触发，但 sink 接线要在 setup 之前完成，否则首次 emit 会丢
	_world_map._player_lifecycle = PlayerLifecycle.new()
	_world_map._player_lifecycle.name = "PlayerLifecycle"
	_world_map.add_child(_world_map._player_lifecycle)
	# Sink 接线：信号让 PlayerLifecycle 不直接依赖 OverlayTransitionUI / VictoryJudge / 持久 slot 表
	# L1.2 Phase 3：coma_triggered（reload 范式）退役 → coma_respawn_triggered（传送范式）+ 注入复活目标解析器
	_world_map._player_lifecycle.coma_respawn_triggered.connect(_world_map._on_player_coma_respawn_triggered)
	_world_map._player_lifecycle.register_coma_respawn_resolver(_world_map._resolve_coma_respawn)
	_world_map._player_lifecycle.defeat_triggered.connect(_world_map._on_player_defeat_triggered)
	_world_map._player_lifecycle.respawn_intro_ready.connect(_world_map._on_player_respawn_intro_ready)
	_world_map._player_lifecycle.setup(WorldMap.PLAYER_PARAM_CFG, WorldMap.RUN_PARAM_CFG)

	# 视觉位置初始化到起点像素中心
	_world_map._unit_visual_pos = _world_map._grid_to_pixel_center(_world_map._start_pos)

	# 初始化回合管理器
	_world_map._turn_manager = TurnManager.new()
	_world_map._turn_manager.register_unit(_world_map._unit)
	# WorldMap 二次重构 批 3 阶段 f：faction_turn_started.connect 已迁到 EC.attach_sinks()
	# 本处保留空行（EC 在 init_world_subsystems 末尾创建并 attach，时序仍正确）
	# 敌方侧由 EnemyAI 自己 connect 不变


# ─────────────────────────────────────
# 阶段 d：子系统实例化（含建造/roster/Tick/Camera 杂项 + _init_subsystems 主体）
# ─────────────────────────────────────

## 抽离自 WorldMap._ready 原 L478-L533（中段杂项 56 行）+ 原 _init_subsystems 函数体（207 行）
##
## 副作用（写 _world_map，按顺序）：
##   1. M5 建造：BuildSystem.load_level_config / _stone_by_faction
##   2. PCG 后字段装配：BuildSystem.apply_level_fields per slot
##   3. 持久 slot 援军 roster 抽样（按 owner 选 enemy/player 强度表）
##   4. Tick 注册：TickRegistry.register × 2（_on_build_tick / _on_faction_tick）
##   5. Camera 初始位置 + offset
##   6. 14 子模块创建 + add_child + 信号接线：
##      _renderer / _world_view / _enemy_movement / _manage_ui / _build_panel_ui /
##      _enemy_ai / _event_panel / _battle_hud / _battle_view / _battle_anim_director /
##      _renderer.setup(world_view, battle_view) / _night_vision / _core_objective_overlay /
##      _explore_action_bar + _explore_attack_btn + _explore_camp_btn / _victory_ui
##   7. 静态系统 sink 注册：
##      VictoryJudge.register_sink /
##      DayNightState.attach_to_turn_manager / register_phase_changed_sink /
##      RunState.register_recruit_sink
##
## 顺序约束（不能调）：
##   - _world_view 必须先于 _renderer.setup（renderer.setup 需 world_view）
##   - _world_view 也必须先于 _enemy_movement 创建（EnemyMovement 隐式引用）
##   - _battle_view 必须先于 _renderer.setup
##   - _night_vision 创建必须在 _turn_manager / _world_view 之后（setup 注入）
##   - VictoryJudge / DayNightState / RunState 静态 sink 在子模块创建后注册
func init_world_subsystems() -> void:
	# M5: 加载升级配置 + 石料库存 + 注册建造 tick
	# 顺序固定：先 BuildSystem.load_level_config（tick 依赖配置），再 register
	BuildSystem.load_level_config(ConfigLoader.load_persistent_slot_config())
	_world_map._stone_by_faction = {
		Faction.PLAYER: WorldMap.BUILD_PARAM_CFG.player_initial_stone,
		Faction.ENEMY_1: WorldMap.BUILD_PARAM_CFG.enemy_initial_stone,
	}

	# 地图生成后字段装配（M2/M4 遗留缺口修复）：
	#   PersistentSlotGenerator._build_slot 只填 type / level / owner_faction，
	#   initial_range / max_range / growth_rate / influence_range 全留默认 0。
	#   核心城镇 L3 永不升级 → 影响范围永远不渲染；初始归属村庄/城镇同理。
	#   此处按每个 slot 的当前 level 从配置注入，让影响范围系统在首个回合前就位。
	# 依赖 BuildSystem.load_level_config 已完成（查 apply_level_fields 走 _world_map._level_config 读）
	# 持久 slot 援军（L1.2）：抽样 rng 优先复用 _world_map._world_rng（保证同 seed 复现）；
	# JSON 加载路径下 _world_map._world_rng 为 null，回退到 randomize 的独立 rng
	var roster_rng: RandomNumberGenerator = _world_map._world_rng
	if roster_rng == null:
		roster_rng = RandomNumberGenerator.new()
		roster_rng.randomize()
	if _world_map._schema != null:
		for entry in _world_map._schema.persistent_slots:
			var slot: PersistentSlot = entry as PersistentSlot
			if slot == null:
				continue
			BuildSystem.apply_level_fields(slot, slot.level)
			# 持久 slot 援军（L1.2）：按 type × 当前周期抽样储备名册（此时 owner 染色已完成）
			# 对所有 slot 抽样——玩家方直接用；中立 / 敌方 slot 被玩家占据后也能提供援军。
			# 敌方援军（L1.4）：按 slot PCG 初始 owner 选表——初始敌方 owned 用独立强度表 _world_map._enemy_garrison_config，
			#   初始中立 / 玩家用 _world_map._garrison_config。储备一旦快照即固定（归属透明），后续切阵营不重抽。
			var roster_cfg: Dictionary = _world_map._enemy_garrison_config if slot.owner_faction == Faction.ENEMY_1 else _world_map._garrison_config
			slot.reinforcement_roster = ReinforcementRoster.sample(
				slot.type as int, RunState.cycle_index(),
				roster_cfg, town_pool_rows, roster_rng
			)

	# ⚠ Tick 注册顺序固定：M5 → M4（TickRegistry 按 FIFO 执行）
	# 自阵营回合开始时先跑 M5 建造完成（可能刷 max_range），
	# 再跑 M4 占据快照（用新 max_range 增长）
	TickRegistry.register(_world_map._on_build_tick)

	# WorldMap 二次重构 批 3 阶段 f：TickRegistry.register(_on_faction_tick) 已迁到 EC.attach_sinks()
	# 本处保留空行（EC 在 init_world_subsystems 末尾创建并 attach，时序仍正确）

	# Camera 初始位置直接设到单位位置（首帧不需要平滑）
	_world_map._camera.position = _world_map._unit_visual_pos
	# 入口 4 MVP（2026-05-09 跑测补丁）：Camera offset 向下偏 RESERVE/2
	# 让玩家在屏幕几何中心上方 OFFSET → 远离底部 HudBar；战斗 zoom 期间 offset 仍生效
	# 视觉效果：地图渲染区中心从屏幕几何中心上移，HUD 在玩家下方独立条带不重叠
	_world_map._camera.offset = Vector2(0, float(WorldMap.EXPLORE_HUD_OFFSET_PX))

	# ─── 子系统实例化段（已 inline 抽自原 _init_subsystems 函数体）───
	var ui_layer: CanvasLayer = (_world_map.get_node("UILayer") as CanvasLayer)

	# MVP-γ 阶段 2：渲染层子节点（承接全部 _world_map._draw_*）—— 先于一切创建，
	# 使后续 redraw_requested 连接 / queue_redraw 转发都有非空目标；
	# setup() 注入 WorldView / BattleViewState 在本函数末尾（届时两者已就绪）
	_world_map._renderer = WorldMapRenderer.new()
	_world_map._renderer.name = "WorldMapRenderer"
	_world_map.add_child(_world_map._renderer)

	# 世界视图 facade（MVP-β）—— MVP-δ 阶段 1 提前到 EnemyMovement 创建之前，
	# 让 start_enemy_move_phase 注入 _world_map._world_view 时引用已就绪
	_world_map._world_view = WorldView.new()
	_world_map._world_view.init(_world_map)

	# 敌方移动子系统（注入格子尺寸，保证视觉位置计算与 WorldMap 一致）
	# 同时注入摄像机引用：EnemyMovement 用其计算视口可见矩形，
	# 路径全在视口外时跳过 Tween 直接结算（详见 EnemyMovement._start_animation）
	_world_map._enemy_movement = EnemyMovement.new()
	_world_map._enemy_movement.name = "EnemyMovement"
	_world_map._enemy_movement.tile_size = WorldMap.TILE_SIZE
	_world_map._enemy_movement._camera = _world_map._camera
	_world_map.add_child(_world_map._enemy_movement)
	# WorldMap 二次重构 批 2 阶段 e：phase_finished.connect 已迁到 BattleCoordinator.attach_sinks()
	# 本处保留空行（BC 在 init_world_subsystems 末尾创建并 attach，时序仍正确）
	_world_map._enemy_movement.redraw_requested.connect(_world_map._renderer.queue_redraw)

	# 装配管理面板子系统 —— MVP-α.5：切预制件实例化
	_world_map._manage_ui = preload("res://scenes/ui/ManageUI.tscn").instantiate()
	_world_map._manage_ui.name = "ManageUI"
	ui_layer.add_child(_world_map._manage_ui)
	_world_map._manage_ui.closed.connect(_world_map._on_manage_closed)
	_world_map._manage_ui.equip_requested.connect(_world_map._on_equip_troop)
	_world_map._manage_ui.use_item_requested.connect(_world_map._on_use_item)

	# 建造面板子系统（M5）—— MVP-α.5：切预制件实例化
	_world_map._build_panel_ui = preload("res://scenes/ui/BuildPanelUI.tscn").instantiate()
	_world_map._build_panel_ui.name = "BuildPanelUI"
	ui_layer.add_child(_world_map._build_panel_ui)
	_world_map._build_panel_ui.closed.connect(_world_map._on_build_panel_closed)
	_world_map._build_panel_ui.upgrade_requested.connect(_world_map._on_upgrade_requested)

	# 敌方 AI（M7）—— _world_map._world_view 已在 _world_map._renderer 之后提前创建（MVP-δ 阶段 1）
	_world_map._enemy_ai = EnemyAI.new()
	_world_map._enemy_ai.name = "EnemyAI"
	_world_map.add_child(_world_map._enemy_ai)
	_world_map._enemy_ai.init(_world_map._world_view, _world_map._turn_manager)
	# L1.3c 阶段 C：增援间隔注入已退役——改由 EnemyReinforcement.SPAWN_CFG 实时读（调参面板可调）
	# cycle_config.csv 的 reinforcement_interval 列 + _current_cycle_reinforcement_interval 字段
	# 就此 superseded（vestige，留 ③ L1.3d 重做威胁曲线时随 cycle 表一并清）

	# 事件面板 UI（探索体验·F MVP）—— MVP-α.5：切预制件实例化
	# 挂载位置：所有交互面板之后、VictoryUI 之前——
	#   层级覆盖 ManageUI / BuildPanelUI（玩家先确认事件再操作其他面板），
	#   但低于 VictoryUI（胜负遮罩可覆盖未确认的事件）
	_world_map._event_panel = preload("res://scenes/ui/EventPanelUI.tscn").instantiate()
	_world_map._event_panel.name = "EventPanelUI"
	ui_layer.add_child(_world_map._event_panel)
	# 入口 4 MVP（2026-05-09 BUG 修复）：事件面板关闭时刷新探索态行动按钮
	# 修复 BUG：补给 0 时踩即时 slot 触发事件，关闭事件面板后扎营按钮未显示
	_world_map._event_panel.closed.connect(_world_map._on_event_panel_closed)

	# E 战斗就地展开 MVP：战斗内 HUD —— MVP-α.5：切预制件实例化
	# 挂载位置：EventPanelUI 之后、VictoryUI 之前
	#   战斗态时高于 EventPanelUI（战斗中事件面板被冻结，理论不会同时弹出）
	#   低于 VictoryUI（极端时序下战斗失败 + 末周期失败可能并发，胜负遮罩压顶）
	# 与 _world_map._battle_session 同生命周期；HUD 节点常驻但只在战斗态可见
	_world_map._battle_hud = preload("res://scenes/ui/BattleHUD.tscn").instantiate()
	_world_map._battle_hud.name = "BattleHUD"
	ui_layer.add_child(_world_map._battle_hud)
	# WorldMap 二次重构 批 2 阶段 f：BattleHUD 4 signal connect 已迁到 BattleCoordinator.attach_sinks()
	# 本处保留空行（BC 在 init_world_subsystems 末尾创建并 attach，时序仍正确）

	# MVP-γ 阶段 1：战斗瞬时视觉态 + 动画编排器（跨战斗复用，每场战斗 setup 注入上下文）
	_world_map._battle_view = BattleViewState.new()
	_world_map._battle_anim_director = BattleAnimDirector.new()
	_world_map._battle_anim_director.name = "BattleAnimDirector"
	_world_map.add_child(_world_map._battle_anim_director)
	# WorldMap 二次重构 批 2 阶段 d：anims_drained.connect 已迁到 BattleCoordinator.attach_sinks()
	# 本处保留空行（BC 在 init_world_subsystems 末尾创建并 attach，时序仍正确）

	# MVP-γ 阶段 2：渲染层注入 —— WorldView（探索态只读入口）+ BattleViewState（战斗态）
	# 均已在本函数前文创建（_world_map._world_view / _world_map._battle_view），此处一次性注入，跨战斗复用
	_world_map._renderer.setup(_world_map._world_view, _world_map._battle_view)

	# MVP-δ 阶段 2：夜晚视野子系统（NightVisionLayer）—— 子 Node，持 CanvasLayer=5 / =6 浮层
	# 注入 turn_manager / camera / world_view / tile_size + 浓雾外信号颜色（敌方 slot / 移动色）
	# setup 只挂 CanvasLayer + 初始化 shader uniform；DayNightState phase_changed sink 由
	# WorldMap 在下方注册组合派发（DayNightState 单 sink 模型，注册覆盖语义）
	_world_map._night_vision = NightVisionLayer.new()
	_world_map._night_vision.name = "NightVisionLayer"
	_world_map.add_child(_world_map._night_vision)
	_world_map._night_vision.setup(_world_map._turn_manager, _world_map._camera, _world_map._world_view, WorldMap.TILE_SIZE,
		WorldMap.UNIT_ENEMY_CFG.enemy_slot_color, WorldMap.UNIT_ENEMY_CFG.enemy_move_color)

	# 核心目标传达 L1.5（§2.3）：暗角 + 离屏核心方向箭头（CanvasLayer=7，居夜晚遮罩之上、UILayer 之下）
	_world_map._core_objective_overlay = CoreObjectiveOverlay.new()
	_world_map._core_objective_overlay.name = "CoreObjectiveOverlay"
	_world_map.add_child(_world_map._core_objective_overlay)
	# 传底部 HudBar 引用：边框下边界跟随其实际顶沿（布局自然，替代 bottom_reserve 手调）
	_world_map._core_objective_overlay.setup(_world_map._camera, _world_map._world_view, WorldMap.TILE_SIZE, _world_map.get_node_or_null("UILayer/HudBar"))

	# 入口 4 MVP（2026-05-09）：探索态行动栏 HBoxContainer（攻击 + 扎营平行排布）
	# 居中屏幕底部偏上；child 数 0 / 1 / 2 都自然布局
	_world_map._explore_action_bar = HBoxContainer.new()
	_world_map._explore_action_bar.name = "ExploreActionBar"
	_world_map._explore_action_bar.add_theme_constant_override("separation", 12)
	_world_map._explore_action_bar.anchor_left = 0.5
	_world_map._explore_action_bar.anchor_right = 0.5
	_world_map._explore_action_bar.anchor_top = 1.0
	_world_map._explore_action_bar.anchor_bottom = 1.0
	_world_map._explore_action_bar.offset_bottom = -64
	_world_map._explore_action_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_world_map._explore_action_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	ui_layer.add_child(_world_map._explore_action_bar)

	# E MVP 探索态【攻击】按钮：玩家回合且触发距离内有敌方包时显示，醒目红色
	# 屏幕中央偏下浮动；与 BattleHUD 行动栏不会同时显示（战斗态时本按钮隐藏）
	_world_map._explore_attack_btn = Button.new()
	_world_map._explore_attack_btn.name = "ExploreAttackBtn"
	# 入口 4 MVP（2026-05-10）：emoji 前缀通过 main_font.tres 的 NotoColorEmoji fallback 渲染
	_world_map._explore_attack_btn.text = "⚔ 攻击 [F]"
	_world_map._explore_attack_btn.visible = false
	_world_map._explore_attack_btn.custom_minimum_size = Vector2(160, 44)
	_world_map._explore_attack_btn.add_theme_font_size_override("font_size", 18)
	_world_map._explore_attack_btn.add_theme_color_override("font_color", Color(1.0, 0.95, 0.85, 1.0))
	# 醒目红色背景 + 金边
	var btn_normal: StyleBoxFlat = StyleBoxFlat.new()
	btn_normal.bg_color = Color(0.78, 0.18, 0.20, 0.95)
	btn_normal.border_width_left = 2
	btn_normal.border_width_right = 2
	btn_normal.border_width_top = 2
	btn_normal.border_width_bottom = 2
	btn_normal.border_color = Color(1.0, 0.84, 0.0, 1.0)
	btn_normal.content_margin_left = 16
	btn_normal.content_margin_right = 16
	btn_normal.content_margin_top = 8
	btn_normal.content_margin_bottom = 8
	_world_map._explore_attack_btn.add_theme_stylebox_override("normal", btn_normal)
	var btn_hover: StyleBoxFlat = btn_normal.duplicate() as StyleBoxFlat
	btn_hover.bg_color = Color(0.92, 0.25, 0.27, 0.98)
	_world_map._explore_attack_btn.add_theme_stylebox_override("hover", btn_hover)
	var btn_pressed: StyleBoxFlat = btn_normal.duplicate() as StyleBoxFlat
	btn_pressed.bg_color = Color(0.62, 0.12, 0.14, 1.0)
	_world_map._explore_attack_btn.add_theme_stylebox_override("pressed", btn_pressed)
	# 入口 4 MVP（2026-05-09）：挂到 HBox（位置由容器管理，不再单独设 anchor）
	_world_map._explore_action_bar.add_child(_world_map._explore_attack_btn)
	_world_map._explore_attack_btn.pressed.connect(_world_map._on_explore_attack_pressed)

	# 入口 4 MVP（2026-05-09）：探索态【扎营】按钮（与攻击按钮同位置 / 互斥）
	# 配色：泥土棕 + 米色描边 —— 与攻击按钮的"红 + 金边"形成色相区分（紧迫 vs 安静）
	_world_map._explore_camp_btn = Button.new()
	_world_map._explore_camp_btn.name = "ExploreCampBtn"
	# 入口 4 MVP（2026-05-10）：emoji 前缀通过 main_font.tres 的 NotoColorEmoji fallback 渲染
	_world_map._explore_camp_btn.text = "⛺ 扎营 [Space]"
	_world_map._explore_camp_btn.visible = false
	_world_map._explore_camp_btn.custom_minimum_size = Vector2(160, 44)
	_world_map._explore_camp_btn.add_theme_font_size_override("font_size", 18)
	_world_map._explore_camp_btn.add_theme_color_override("font_color", Color(1.0, 0.95, 0.85, 1.0))
	var camp_normal: StyleBoxFlat = StyleBoxFlat.new()
	camp_normal.bg_color = Color(0.42, 0.30, 0.18, 0.95)
	camp_normal.border_width_left = 2
	camp_normal.border_width_right = 2
	camp_normal.border_width_top = 2
	camp_normal.border_width_bottom = 2
	camp_normal.border_color = Color(0.92, 0.82, 0.62, 1.0)
	camp_normal.content_margin_left = 16
	camp_normal.content_margin_right = 16
	camp_normal.content_margin_top = 8
	camp_normal.content_margin_bottom = 8
	_world_map._explore_camp_btn.add_theme_stylebox_override("normal", camp_normal)
	var camp_hover: StyleBoxFlat = camp_normal.duplicate() as StyleBoxFlat
	camp_hover.bg_color = Color(0.55, 0.40, 0.25, 0.98)
	_world_map._explore_camp_btn.add_theme_stylebox_override("hover", camp_hover)
	var camp_pressed: StyleBoxFlat = camp_normal.duplicate() as StyleBoxFlat
	camp_pressed.bg_color = Color(0.32, 0.22, 0.12, 1.0)
	_world_map._explore_camp_btn.add_theme_stylebox_override("pressed", camp_pressed)
	# 挂到同一 HBox（与攻击按钮平行排布）
	_world_map._explore_action_bar.add_child(_world_map._explore_camp_btn)
	_world_map._explore_camp_btn.pressed.connect(_world_map._on_explore_camp_pressed)

	# 胜负遮罩 UI（M8）—— MVP-α.5：从 .new() + create_ui() 改为预制件实例化
	# 挂载顺序放在所有 UI 面板之后，保证遮罩渲染在最上层（吸收点击）
	# 父节点从 self(Node2D) 调整为 ui_layer(CanvasLayer)：因根类型已改 extends Control，
	# Control 锚定到 CanvasLayer 的视口；逻辑等价，节点结构扁平
	_world_map._victory_ui = preload("res://scenes/ui/VictoryUI.tscn").instantiate()
	_world_map._victory_ui.name = "VictoryUI"
	ui_layer.add_child(_world_map._victory_ui)
	_world_map._victory_ui.restart_pressed.connect(_world_map._on_restart_pressed)

	# M8：注册胜负回调；OccupationSystem.try_occupy 翻转核心城镇时触发
	# reload_current_scene 后新的 _world_map._ready 会重新注册，_world_map._exit_tree 会 clear_sink 避免悬空
	# L1.3a 阶段 D：cycle 退役——周期推进出口（register_cycle_victory_sink）已移除；
	# 唯一胜利出口 = VictoryJudge.dispatch_climax_victory（climax 决战，BattleCoordinator 调用）
	VictoryJudge.register_sink(_world_map._on_victory_decided)

	# D MVP：把 TurnManager.faction_turn_started 包装为 phase_changed
	# attach 内部对同一 turn_manager 重复挂接是幂等的；reload 后旧 turn_manager
	# 会先被 clear_sinks 解绑（_world_map._exit_tree 中处理），新场景再 attach 新实例
	DayNightState.attach_to_turn_manager(_world_map._turn_manager)
	# 阶段切换时立即触发 redraw，保证夜晚滤镜在 faction 切换瞬间出现
	# （否则要等 EnemyMovement 第一次 redraw_requested 才更新视觉）
	DayNightState.register_phase_changed_sink(_world_map._on_day_night_phase_changed)

	# C MVP：扎营里程碑入队 sink 注册——RunState 命中里程碑时回调 _world_map._on_recruit_triggered
	# 解绑由 RunState.clear_sinks 在 _world_map._exit_tree 处理，与其他 sink 同生命周期
	RunState.register_recruit_sink(_world_map._on_recruit_triggered)

	# L1.1 阶段 2：视野循环 + chunk 三态系统创建（无限地图实装）
	# 设计：tile-advanture-design/无限地图实装/L1.1_视野循环与chunk底座_MVP.md §4.1 / §5
	# 创建时机：在协调器之前，确保后续 EC.init_vision_runtime 可见 _vision_system / _chunk_manager
	# 包裹叠加：本阶段仅启动子系统数据流；阶段 3+ 接渲染分层 / 移动钩子 / 回合钩子
	_world_map._vision_system = VisionSystem.new()
	_world_map._vision_system.name = "VisionSystem"
	_world_map.add_child(_world_map._vision_system)
	_world_map._vision_system.setup(WorldMap.VISION_CFG)

	# L1.2 Phase 0：把 _vision_system 注入 NightVisionLayer（多源 shader 光源数据源）
	# 时序：NightVisionLayer 在上方 §渲染层创建段先 setup（早于此处），此时注入晚于其 setup —— 见
	# NightVisionLayer.set_vision_system 注释。注入后 shader lights[] 从单玩家源升级为多源数据源
	if _world_map._night_vision != null:
		_world_map._night_vision.set_vision_system(_world_map._vision_system)

	# world_seed 来源（codex P1 修复 2026-05-28）：
	#   PCG 路径下复用 _world_rng.seed 保证 chunk noise 与 PCG 同源 + 折返一致
	#   JSON 路径下 _world_rng 为 null（_load_json_internal 不创建），改用 Time 派生
	#   （与 _load_pcg_internal random_seed=-1 时的自动 seed 同机制）
	var world_seed: int = 0
	if _world_map._world_rng != null:
		world_seed = int(_world_map._world_rng.seed)
	else:
		world_seed = int(Time.get_ticks_usec())

	_world_map._chunk_manager = ChunkManager.new()
	_world_map._chunk_manager.name = "ChunkManager"
	_world_map.add_child(_world_map._chunk_manager)
	_world_map._chunk_manager.setup(WorldMap.VISION_CFG, _world_map._vision_system, world_seed)

	# WorldMap 二次重构 批 2 阶段 a：创建 BattleCoordinator + attach_sinks
	# 设计：tile-advanture-design/WorldMap二次重构/批2_BattleCoordinator_MVP.md
	# 必须在所有战斗子模块（_battle_session / _battle_hud / _battle_anim_director /
	# _enemy_movement）创建 + add_child + 信号 connect 完成**之后**调用，否则
	# BC.attach_sinks() 接到的子模块字段为 null（见实装包 §风险与回滚 #4）
	# 阶段 a：attach_sinks 暂为空骨架，仅迁出 4 个查询函数；阶段 e/f 再接 signal
	_world_map._battle_coordinator = BattleCoordinator.new(_world_map)
	_world_map._battle_coordinator.attach_sinks()

	# WorldMap 二次重构 批 3 阶段 a：创建 ExplorationCoordinator + attach_sinks
	# 设计：tile-advanture-design/WorldMap二次重构/批3_ExplorationCoordinator_MVP.md
	# 必须在 BC 创建 + attach 之后调用，确保 EC 内部访问 BC 时不悬空
	# 阶段 a：attach_sinks 暂为空骨架，仅迁出 4 个移动 + 可达性函数；阶段 f 接 TurnManager / TickRegistry
	_world_map._exploration_coordinator = ExplorationCoordinator.new(_world_map)
	_world_map._exploration_coordinator.attach_sinks()



# ─────────────────────────────────────
# 阶段 e：启动末尾收口
# ─────────────────────────────────────

## 抽离自 WorldMap._ready 原 L481-L503（23 行）
##
## 副作用（按顺序）：
##   1. 写 _world_map._label_font（地图标签字体）
##   2. _world_map._turn_manager.start_faction_turn(PLAYER) —— 启动首个玩家回合
##      （L1.3c 阶段 C：开局预置敌方 pack 已退役，敌人全动态从暗影环带刷出）
##   3. _wire_content_spawner_internal —— chunk 内容钩子接线（玩家视野源注册前）
##   4. _exploration_coordinator.init_vision_runtime —— 注册玩家 VisionSource + 首次 chunk aggregate
##   5. OverlayTransitionUI.play_with_blackout_start —— 揭幕过渡（仅应用首次启动）
##
## 完成后 WorldMap._ready 收口为 ≤ 12 行：
##   var bootstrap: MapBootstrap = MapBootstrap.new(self)
##   bootstrap.load_configs(); bootstrap.load_map(); _setup_camera_limits()
##   bootstrap.create_world_state(); bootstrap.init_world_subsystems()
##   bootstrap.finalize_startup()
func finalize_startup() -> void:
	# 初始化地图标签字体：使用顶部 const MAIN_FONT（preload 形式，编辑期校验路径）
	_world_map._label_font = WorldMap.MAIN_FONT

	# L1.3c 阶段 C：开局预置敌方 pack 已退役——敌人全动态，从玩家视野外暗影环带流式刷出
	# （EnemyReinforcement.spawn_batch 默认分支）。开局保护期"自然成立"：视野外无敌、
	# 视野内永不凭空出怪；末周期强敌承诺由 L1.3a climax boss（anchor 模式分支）承接

	# M7：启动首个玩家回合（TickRegistry 跑 M4/M5 tick → emit faction_turn_started(PLAYER)
	# → _on_faction_turn_started 接管 HUD / reachable 刷新）
	_world_map._turn_manager.start_faction_turn(Faction.PLAYER)

	# L1.3c 阶段 B：chunk 内容钩子接线——必须在玩家 VisionSource 注册之前完成订阅，
	# 否则首批 chunk 的 chunk_first_generated 在订阅前发射，初始区域漏撒资源 slot
	_wire_content_spawner_internal()

	# L1.1 阶段 2：注册玩家 VisionSource + 触发首次 chunk aggregate
	# 时机：所有子系统就绪 + _unit.position 已定 + 初始 pack 部署完毕；视野启动不影响 spawn 判定
	# 包裹叠加阶段：仅启动数据流，不接移动/回合钩子（阶段 3+ 增量接入）
	_world_map._exploration_coordinator.init_vision_runtime()

	# 入口 2 MVP 2.1 议题 5（2026-05-10）：游戏首次启动 → 黑屏揭幕过渡
	# 分流：
	#   - 应用首次启动：is_initial_play_done() == false → play_with_blackout_start 单句揭幕
	#   - reload 触发的新场景：_init_player 内已调 notify_world_ready 推进过渡，本路径跳过
	# OverlayTransitionUI _ready 时已黑屏 alpha=1，掩盖应用启动到此处的全部加载耗时
	if not OverlayTransitionUI.is_initial_play_done():
		var line: String = _world_map._player_lifecycle.format_respawn_line_for_current_leader()
		var lines: PackedStringArray = PackedStringArray([line])
		# 火苗团数 = 过渡完成后的玩家总命数；游戏开始无消耗 → 当前 respawns_left + 1（含当前队长）
		# 例：max_cycles=3, _cycle_index=0 → respawns_left=2 → 显示 3 团火苗
		var icon_data: Dictionary = {"icon": "🔥", "count": RunState.respawns_left() + 1}
		OverlayTransitionUI.play_with_blackout_start(lines, icon_data)
