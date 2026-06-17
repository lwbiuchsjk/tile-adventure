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

## 压力分段配置。用 static var preload（非 const）：调参面板 entry_pressure 设 realtime=true，
## 面板反射 set 拖滑块即时改难度曲线——避开 const 编译期内联（D5 const cache bug）。
static var CFG: PressureConfig = preload("res://assets/config/pressure_config.tres")


## 计算当前压力等级 P = camp_level + vision_level。
## camp_count：来自 RunState.total_camp_count()（lifetime 扎营计数）。
## source_count：来自 VisionSystem.get_sources().size()（据点 + 占领 slot + 玩家队伍各一源）。
static func compute_pressure(camp_count: int, source_count: int) -> int:
	return camp_level(camp_count) + vision_level(source_count)


## 扎营轴分段：扎营次数 → camp_level（0-3 档，累计 >= 比较，依赖阈值升序）。
static func camp_level(camp_count: int) -> int:
	var level: int = 0
	if camp_count >= CFG.camp_threshold_1:
		level += 1
	if camp_count >= CFG.camp_threshold_2:
		level += 1
	if camp_count >= CFG.camp_threshold_3:
		level += 1
	return level


## 视野轴分段：视野源数 → vision_level（0-2 档，累计 >= 比较，依赖阈值升序）。
static func vision_level(source_count: int) -> int:
	var level: int = 0
	if source_count >= CFG.vision_threshold_1:
		level += 1
	if source_count >= CFG.vision_threshold_2:
		level += 1
	return level
