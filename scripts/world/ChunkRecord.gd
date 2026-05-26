class_name ChunkRecord
extends RefCounted
## chunk 状态承载（L1.1 §3.3）
##
## 设计原文：
##   tile-advanture-design/无限地图实装/L1.1_视野循环与chunk底座_MVP.md §3.3 / §2.2
##
## 三态：
##   UNLOADED —— 仅保留 coord，无 schema、无实例（最经济，dict 中不存在即等价）
##   DORMANT  —— 保留 schema（地形 + POI 静态），无实例（不渲染、不模拟）
##   ACTIVE   —— 保留 schema + 实例化（渲染中）
##
## 形态选择：RefCounted —— ChunkRecord 是 ChunkManager 内部状态承载，
## 不参与跨场景持久化；reload 时随 ChunkManager 一同重建。

enum State { UNLOADED, DORMANT, ACTIVE }


## chunk 坐标
var coord: Vector2i

## 当前状态
var state: int = State.UNLOADED

## chunk 内容快照；UNLOADED 状态下为 null（节省内存）
var schema: ChunkSchema = null

## 上次进入 ACTIVE 的回合号；用于诊断 / 后续可挂淘汰策略
var last_active_turn: int = -1


func _init(p_coord: Vector2i = Vector2i.ZERO) -> void:
	coord = p_coord
