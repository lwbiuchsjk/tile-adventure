class_name TroopData
extends RefCounted
## 部队数据
## 部队装配在角色上，为角色提供战斗能力。
## MVP 阶段仅实现 1 种兵种、1 种品质。

## 兵种类型（MVP 仅剑兵）
enum TroopType {
	SWORD = 0,  ## 剑兵
}

## 品质等级（MVP 仅 R）
enum Quality {
	R   = 0,  ## 普通
	SR  = 1,  ## 稀有（预留）
	SSR = 2,  ## 传说（预留）
}

## 兵种类型
var troop_type: TroopType = TroopType.SWORD

## 品质
var quality: Quality = Quality.R

## 最大兵力
var max_hp: int = 1000

## 当前兵力
var current_hp: int = 1000

## 受到兵力伤害，兵力不会低于 0
func take_damage(damage: int) -> void:
	current_hp = maxi(0, current_hp - damage)

## 判断部队是否被击败（兵力归零）
func is_defeated() -> bool:
	return current_hp <= 0
