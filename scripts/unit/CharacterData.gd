class_name CharacterData
extends RefCounted
## 角色数据
## 每个角色有唯一 ID 和一个部队槽位。
## 仅装配了部队的角色可以参与战斗。

## 角色唯一标识
var id: int = 0

## hero_pool.csv 中的英雄 ID（-1 = 未关联，老调用路径或测试构造时的默认值）
## C MVP 起 RunState.draw_recruit 用此值排除当前在队英雄；队长 / 入队队员都需要写入
var hero_id: int = -1

## 部队槽位（null 表示未装配）
var troop: TroopData = null

## 判断是否已装配部队
func has_troop() -> bool:
	return troop != null

## 清空部队槽位（部队被击败时调用）
func clear_troop() -> void:
	troop = null
