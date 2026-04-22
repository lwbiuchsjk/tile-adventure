class_name Faction
extends RefCounted
## 势力枚举（以常量集合形式提供，易扩展到 N 方）
## 设计原文：tile-advanture-design/敌方AI基础行为设计.md §4.2
## 用途：标识 PersistentSlot.owner_faction、LevelSlot.faction、敌方部队归属等
##
## 约定：
##   NONE     —— 中立 / 未归属
##   PLAYER   —— 玩家势力（MVP 单玩家）
##   ENEMY_1  —— 敌方势力 1（MVP 两方对峙时唯一敌方）
## 后续扩展按 ENEMY_2 / ENEMY_3 顺延即可，无需改既有判断分支

const NONE: int = 0
const PLAYER: int = 1
const ENEMY_1: int = 2

## 势力显示名称映射（用于 UI / 调试）
## 注：保持 const Dictionary 形式与项目其它枚举（如 ResourceSlot.RESOURCE_TYPE_NAMES）一致
const FACTION_NAMES: Dictionary = {
	NONE:    "中立",
	PLAYER:  "玩家",
	ENEMY_1: "敌方",
}


## 获取势力显示名称
## 未知势力 ID 返回"未知"，便于 UI 容错
## 注：方法名避开 Object.get_name() 冲突，统一用 faction_name(id)
static func faction_name(faction: int) -> String:
	return FACTION_NAMES.get(faction, "未知") as String


## 判断两个势力是否敌对（不同且都非 NONE 视为敌对）
## MVP 阶段所有非同方势力都互为敌对；后续可改为势力关系矩阵
static func is_hostile(a: int, b: int) -> bool:
	if a == NONE or b == NONE:
		return false
	return a != b
