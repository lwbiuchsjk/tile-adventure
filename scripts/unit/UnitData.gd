class_name UnitData
extends RefCounted
## 单位数据结构
## 记录单位在地图上的位置与移动力状态。
## 当前为最小实现，后续将扩展为独立角色数据（属性、兵种等）。

## 当前所在格坐标
var position: Vector2i = Vector2i.ZERO

## 每回合最大移动力
var max_movement: int = 6

## 当前剩余移动力
var current_movement: int = 6
