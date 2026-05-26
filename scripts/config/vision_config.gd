class_name VisionConfig
extends Resource
## @tunable: 视野循环
## 视野循环 + chunk 三态机制 调参（L1.1 §3.7 / §8）
##
## 设计原文：
##   tile-advanture-design/无限地图实装/L1.1_视野循环与chunk底座_MVP.md §3.7 / §8
##
## 用法：
##   const CFG: VisionConfig = preload("res://assets/config/vision_config.tres")
##   var radius: int = CFG.player_vision_radius
##
## 调参面板（剥离原则）：L1.1 不立即接入面板；待 L1.1 全部跑通整理时再纳入 _panel_registry.tres
## 接入时建议 group="视野循环"，realtime=false（重启生效；fog_delay/shadow_decay 实时调可能让活动 chunk 紊乱）


@export_group("视野发出者")

## 玩家队伍视野半径（格，欧氏圆形）
## L1.1 单源；L1.2 扩展据点 + 占领点视野半径
@export_range(1, 16, 1) var player_vision_radius: int = 5


@export_group("视野状态机时钟")

## NORMAL → FOG 滞回延迟（回合）
## 玩家离开视野后等待该回合数才退化为 FOG；避免边缘抖动
## L1.1 用"回合"占位；L1.3 接入扎营时钟后改"次扎营"单位
@export_range(0, 5, 1) var fog_delay_turns: int = 1

## FOG → SHADOW 退化时钟（回合）
## 进入 FOG 后持续该回合数后退化为 SHADOW（chunk 可卸载）
@export_range(1, 30, 1) var shadow_decay_turns: int = 5


@export_group("chunk 配置")

## chunk 边长（格）；L1.1 占位 16，暂不开放调整
## 16 × 16 = 256 格/chunk，与屏幕 17×10 显示量级接近
## 注：ChunkSchema / ChunkManager 内部仍硬编码 CHUNK_SIZE=16，此字段当前不被消费
## 留作未来可调切换；改时需同步两个 const
@export_range(8, 32, 1) var chunk_size: int = 16


@export_group("PCG 生成")

## 每 chunk 生成 POI 的概率（L1.1 极简：只生成 NEUTRAL_VILLAGE 一种）
## L1.1 后期独立"PCG 内容质量"批升级为完整分布规则（密度梯度 / 多类型）
@export_range(0.0, 1.0, 0.05) var poi_spawn_rate_per_chunk: float = 0.3
