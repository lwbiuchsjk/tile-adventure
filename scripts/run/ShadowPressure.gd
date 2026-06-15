class_name ShadowPressure
## 暗影压力引擎（L1.3d-1 阶段 A）：把整局难度收敛为单一整数标量 P。
##
## 设计原文：tile-advanture-design/无限地图实装/L1.3d-1_暗影压力引擎_MVP.md §二 / §三
##
## 模型：P = camp_level + vision_level（两轴先各自分段、再相加，全整数）。
##   - 扎营轴（保底时钟）：扎营次数 → camp_level；龟缩也单调升。
##   - 视野轴（玩家自选）：视野源数（VisionSource 个数）→ vision_level；占领越多越高。
##
## 纯函数静态类（与 RunState / VictoryJudge / DayNightState 同架构）：不持有状态，
##   相同输入恒定输出，便于 headless 测试与 L1.3d-2 前兆显示复用。
##
## 阶段归属：本份（阶段 A）只产出 P；P → 威胁表（tier 权重 + interval）的查表消费在阶段 B 接入。

## 压力分段配置（结构性参数，重启生效；const preload 与项目其余 *_config 一致）。
const CFG: PressureConfig = preload("res://assets/config/pressure_config.tres")


## 计算当前压力等级 P = camp_level + vision_level。
## camp_count：来自 RunState.total_camp_count()（lifetime 扎营计数）。
## source_count：来自 VisionSystem.get_sources().size()（据点 + 占领 slot + 玩家队伍各一源）。
static func compute_pressure(camp_count: int, source_count: int) -> int:
	return camp_level(camp_count) + vision_level(source_count)


## 扎营轴分段：扎营次数 → camp_level（读 CFG.camp_level_thresholds）。
static func camp_level(camp_count: int) -> int:
	return _level_from_thresholds(camp_count, CFG.camp_level_thresholds)


## 视野轴分段：视野源数 → vision_level（读 CFG.vision_level_thresholds）。
static func vision_level(source_count: int) -> int:
	return _level_from_thresholds(source_count, CFG.vision_level_thresholds)


## 升序阈值分段通用算子：返回 value 跨过的阈值个数（= 段位）。
## 依赖 thresholds 升序：一旦 value < 某阈值即可提前 break（后续必更大）。
## 例：thresholds=[3,6,9]，value=5 → 跨过 3，未跨 6 → 段位 1。
static func _level_from_thresholds(value: int, thresholds: Array[int]) -> int:
	var level: int = 0
	for t: int in thresholds:
		if value >= t:
			level += 1
		else:
			break
	return level
