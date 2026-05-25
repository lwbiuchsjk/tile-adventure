class_name ScoreParamResource
extends Resource

## 分数参数 Resource（MVP-D D.2 批 2：score_config.csv 迁出，3 字段）
##
## 消费方：WorldMap → ScoreCalculator.calculate(config: ScoreParamResource)
## 评分公式：base + efficiency_k * 效率项 + survival_k * 存活项

## 基础分
@export_range(0.0, 100000.0, 1.0) var base_score: float = 1000.0
## 效率系数（关卡数相关项权重）
@export_range(0.0, 1000.0, 0.1) var efficiency_k: float = 10.0
## 存活系数（HP 保全相关项权重）
@export_range(0.0, 100.0, 0.1) var survival_k: float = 1.0
