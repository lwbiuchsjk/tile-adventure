class_name LevelSlot
extends RefCounted
## 关卡实体数据
## 关卡以 Slot 形式分布在地图上，有"未挑战/已挑战"两种状态。
## 已挑战的关卡不可再次进入。

## 关卡状态
enum State {
	UNCHALLENGED = 0,  ## 未挑战
	CHALLENGED   = 1,  ## 已挑战
}

## 关卡在地图上的格坐标
var position: Vector2i = Vector2i.ZERO

## 当前状态
var state: State = State.UNCHALLENGED

## 判断是否已挑战
func is_challenged() -> bool:
	return state == State.CHALLENGED

## 标记为已挑战
func mark_challenged() -> void:
	state = State.CHALLENGED
