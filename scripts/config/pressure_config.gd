class_name PressureConfig
extends Resource
## @tunable: 整局节奏
## 暗影压力分段参数（L1.3d-1 阶段 A：压力标量 P = camp_level + vision_level）
##
## 设计原文：tile-advanture-design/无限地图实装/L1.3d-1_暗影压力引擎_MVP.md §三 / §六
##
## 用法：使用方 `const CFG: PressureConfig = preload("res://assets/config/pressure_config.tres")`，
##   经 ShadowPressure 静态类消费（compute_pressure）。
##
## ⚠ 结构性参数说明：两条阈值数组决定难度曲线的分段边界，改动 = 换一条压力递增曲线；
##   阈值升序排列（ShadowPressure._level_from_thresholds 依赖升序提前 break），重启生效。

## 扎营分段阈值（升序）：扎营次数 → camp_level。
## 默认 [3, 6, 9] 表示 <3→0 / 3-5→1 / 6-8→2 / 9+→3。长度 = 段数 - 1。
@export var camp_level_thresholds: Array[int] = [3, 6, 9]

## 视野分段阈值（升序）：视野源数（VisionSource 个数）→ vision_level。
## 默认 [2, 4] 表示 1→0 / 2-3→1 / 4+→2。长度 = 段数 - 1。
@export var vision_level_thresholds: Array[int] = [2, 4]
