class_name RunParamResource
extends Resource
## @tunable: 整局节奏

## 整局参数 Resource（MVP-D D.2 批 2：run_config.csv 迁出，3 字段）
##
## 消费方（全链类型化，沿用批 1 模式）：
##   WorldMap → PlayerLifecycle.setup(run_cfg: RunParamResource)（读 coma 两字段）
##   WorldMap → RunState.ensure_initialized（命数 K）/ EC（climax / recruit 字段）

## 昏迷过渡时长（秒）
@export_range(0.0, 10.0, 0.1) var coma_duration_sec: float = 1.5
## 昏迷判定的 HP 比例阈值（current_hp / max_hp ≤ 此值 → 昏迷）
@export_range(0.0, 1.0, 0.01) var coma_hp_threshold_ratio: float = 0.5

## L1.3a 扎营时钟 / 胜负模型（子 MVP ①）
## climax 触发扎营次数 N：累计扎营到此值 → 强敌来袭决战（阶段 C 接 EC 触发）
@export_range(1, 30, 1) var climax_camp_threshold: int = 8
## 无据点命数 K：脱钩 cycle 的独立容错预算（阶段 A 注入 RunState._respawns_remaining）
@export_range(0, 10, 1) var no_stronghold_respawns: int = 3
## 招募扎营间隔：每 N 次扎营触发一次入队事件（阶段 D recruit 适配读 _total_camp_count）
@export_range(1, 20, 1) var recruit_camp_interval: int = 3
## 招募次数硬上限：整局最多招募几次（避免无限扎营抽干英雄池）。默认 2 → 队伍最多 队长+2=3 支。
## 入口 6 事件系统落地后，此控制完整迁入（由事件表条数自然给出），本字段退役
@export_range(0, 20, 1) var recruit_max_count: int = 2
