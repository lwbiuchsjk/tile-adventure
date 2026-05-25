class_name RunParamResource
extends Resource
## @tunable: 整局节奏

## 整局参数 Resource（MVP-D D.2 批 2：run_config.csv 迁出，3 字段）
##
## 消费方（全链类型化，沿用批 1 模式）：
##   WorldMap → RunState.ensure_initialized(max_cycles)（int 传递）
##   WorldMap → PlayerLifecycle.setup(run_cfg: RunParamResource)（读 coma 两字段）

## 整局最大周期数（0 = 首发；max_cycles - 1 = 末周期无保护）
@export_range(1, 20, 1) var max_cycles: int = 3
## 昏迷过渡时长（秒）
@export_range(0.0, 10.0, 0.1) var coma_duration_sec: float = 1.5
## 昏迷判定的 HP 比例阈值（current_hp / max_hp ≤ 此值 → 昏迷）
@export_range(0.0, 1.0, 0.01) var coma_hp_threshold_ratio: float = 0.5
