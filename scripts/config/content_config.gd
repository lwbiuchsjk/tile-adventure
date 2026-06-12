class_name ContentConfig
extends Resource
## @tunable: 整局节奏
## 世界内容生成参数（L1.3c 阶段 A：网格抖动撒点）
##
## 设计原文：tile-advanture-design/无限地图实装/L1.3c_世界内容地基_MVP.md §六
##
## ⚠ 结构性参数说明：cell_size / slot_spawn_rate / town_ratio 参与确定性撒点子 seed 消费序列，
## 改动 = 换一局内容分布（同 seed 折返基准变化），与普通数值调参不同；重启生效。

## 撒点 cell 边长（≈ 持久 slot 期望间距，曼哈顿间距下界 = 3 由 PAD 保证）
@export_range(3, 12) var cell_size: int = 5

## 每 cell 出点概率
@export_range(0.0, 1.0) var slot_spawn_rate: float = 0.85

## 出点时为 TOWN 的概率（其余为 VILLAGE）
@export_range(0.0, 1.0) var town_ratio: float = 0.27

## 每 chunk 资源 slot 配额（L1.3c 阶段 B；0 = 不生成资源 slot）
@export_range(0, 4) var resource_quota_per_chunk: int = 1
