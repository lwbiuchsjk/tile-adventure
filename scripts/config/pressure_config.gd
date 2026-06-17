class_name PressureConfig
extends Resource
## @tunable: 整局节奏
## 暗影压力分段参数（L1.3d-1：压力标量 P = camp_level + vision_level）
##
## 设计原文：tile-advanture-design/无限地图实装/L1.3d-1_暗影压力引擎_MVP.md §三 / §六
##
## 用法：ShadowPressure 静态类经 static var preload 消费（realtime 调参——拖滑块即时改难度曲线）。
##
## ⚠ 阈值升序（th1 ≤ th2 ≤ th3 / th1 ≤ th2）：camp/vision_level 用累计 `>=` 比较，升序才单调。
## P 是派生量（每次 compute_pressure 实时算），改阈值不参与确定性撒点 → realtime 安全、不破折返一致。
##
## 阶段 B 回写：原为 Array[int] 两条阈值数组（imgui 面板不支持数组自省），拆为标量字段以纳入调参面板。
## 段数固定（camp 0-3 / vision 0-2 → P 0-5），与威胁表 P=0..5 结构对齐。

## 扎营分段阈值（升序）：扎营次数 ≥ 各阈值则 camp_level 累加 1（0-3 档）
@export_range(1, 50, 1) var camp_threshold_1: int = 3   ## ≥ 此 → camp_level ≥ 1
@export_range(1, 50, 1) var camp_threshold_2: int = 6   ## ≥ 此 → camp_level ≥ 2
@export_range(1, 50, 1) var camp_threshold_3: int = 9   ## ≥ 此 → camp_level = 3

## 视野分段阈值（升序）：视野源数 ≥ 各阈值则 vision_level 累加 1（0-2 档）
@export_range(1, 30, 1) var vision_threshold_1: int = 2 ## ≥ 此 → vision_level ≥ 1
@export_range(1, 30, 1) var vision_threshold_2: int = 4 ## ≥ 此 → vision_level = 2
