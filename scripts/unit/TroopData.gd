class_name TroopData
extends RefCounted
## 部队数据
## 部队装配在角色上，为角色提供战斗能力。
## 支持 5 种兵种和 3 级品质。

## 兵种类型
enum TroopType {
	SWORD   = 0,  ## 剑兵
	BOW     = 1,  ## 弓兵
	SPEAR   = 2,  ## 枪兵
	CAVALRY = 3,  ## 骑兵
	SHIELD  = 4,  ## 盾兵
}

## 品质等级
enum Quality {
	R   = 0,  ## 普通
	SR  = 1,  ## 稀有
	SSR = 2,  ## 传说
}

## 兵种名称映射（用于 UI 显示）
const TROOP_TYPE_NAMES: Dictionary = {
	TroopType.SWORD:   "剑兵",
	TroopType.BOW:     "弓兵",
	TroopType.SPEAR:   "枪兵",
	TroopType.CAVALRY: "骑兵",
	TroopType.SHIELD:  "盾兵",
}

## 品质名称映射（用于 UI 显示）
const QUALITY_NAMES: Dictionary = {
	Quality.R:   "R",
	Quality.SR:  "SR",
	Quality.SSR: "SSR",
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

## 获取兵种显示名称
func get_type_name() -> String:
	return TROOP_TYPE_NAMES.get(troop_type, "未知") as String

## 获取品质显示名称
func get_quality_name() -> String:
	return QUALITY_NAMES.get(quality, "?") as String

## 获取完整显示文本（如"剑兵(R)"）
func get_display_text() -> String:
	return "%s(%s)" % [get_type_name(), get_quality_name()]
