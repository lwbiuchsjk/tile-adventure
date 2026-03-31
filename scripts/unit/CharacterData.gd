class_name CharacterData
extends RefCounted
## 角色数据
## 每个角色有唯一 ID 和一个部队槽位。
## 仅装配了部队的角色可以参与战斗。

## 角色唯一标识
var id: int = 0

## 部队槽位（null 表示未装配）
var troop: TroopData = null

## 判断是否已装配部队
func has_troop() -> bool:
	return troop != null

## 清空部队槽位（部队被击败时调用）
func clear_troop() -> void:
	troop = null
