class_name PersistentSlot
extends RefCounted
## 持久 slot 数据
## 持久 slot 是城建锚的载体：村庄 / 城镇 / 核心城镇三类，等级 0-3，
## 提供影响范围、归属切换、扎营产出、升级建造等系统能力。
##
## 设计原文：
##   tile-advanture-design/持久slot基础功能设计.md §三 状态维度
##   tile-advanture-design/持久slot升级建造设计.md §三/§四 建造槽位与在建动作
##
## 与 ResourceSlot 的关系：
##   原 ResourceSlot.is_persistent=true 分支已迁移到本类；
##   ResourceSlot 回归一次性资源点语义，二者不再共用类型。
##
## 本模块（M1）只定义字段契约，行为方法由后续模块实装：
##   生成   → M2 地图生成
##   归属切换 / 影响范围增长 → M4 占据归属与影响范围
##   建造 tick / 升级完成   → M3 回合框架 + M5 升级建造
##   扎营产出 → M6 产出结算

## 持久 slot 类型
## CORE_TOWN 单独枚举，是否独立 CSV 行由 M5 决定（待跟踪事项索引 P1）
enum Type {
	VILLAGE   = 0,  ## 村庄（小型聚落）
	TOWN      = 1,  ## 城镇（中型聚落）
	CORE_TOWN = 2,  ## 核心城镇（势力首都，MVP 初始 L3）
}

## 类型显示名称映射（用于 UI / 调试）
const TYPE_NAMES: Dictionary = {
	Type.VILLAGE:   "村庄",
	Type.TOWN:     "城镇",
	Type.CORE_TOWN: "核心城镇",
}

## 地图短标签映射（用于地图格内文字标注）
## 与 ResourceSlot.RESOURCE_MAP_LABELS 风格保持一致，字数精简
## M8 扩展后地图改用 display_id 渲染，此常量保留做兜底 / fallback
const TYPE_MAP_LABELS: Dictionary = {
	Type.VILLAGE:   "村",
	Type.TOWN:     "镇",
	Type.CORE_TOWN: "核",
}

# ─────────────────────────────────────────
# 设计 §三 七字段（核心契约）
# ─────────────────────────────────────────

## 人类可读 ID（地图格 + 建造面板共用，解决"坐标查询反人类"）
## 格式：
##   村庄 / 城镇：`类型名 + 势力内序号`（如 "村庄1", "城镇2"）；每势力各自从 1 开始
##   核心城镇：`核心`（每势力只有一个，不加序号）
## 由 PersistentSlotGenerator 在生成完成后按 (势力, 类型, position y→x) 稳定排序分配，
## 保证 seed 复现两次得到相同 ID；M8 前未分配时为空串、UI 回退到 get_map_label
var display_id: String = ""

## 在地图上的格坐标
var position: Vector2i = Vector2i.ZERO

## 类型（村庄 / 城镇 / 核心城镇）
var type: Type = Type.VILLAGE

## 当前等级（0..3；村庄/城镇 0 为占位未建造，核心城镇 MVP 初始 3）
var level: int = 0

## 归属势力 ID（Faction.NONE / PLAYER / ENEMY_1 ...）
## NONE 表示中立，由 M4 占据触发后切换归属
var owner_faction: int = Faction.NONE

## 驻扎累计回合数（占据状态的持续回合快照）
## 离开时清零；由 M4 回合末快照写入
var garrison_turns: int = 0

## 占据累计回合数（与归属切换判定相关）
## 由 M4 占据触发流程维护
var occupy_turns: int = 0

## 当前影响半径（曼哈顿距离，由 M4 范围增长更新）
## 初始等于 initial_range，随回合按 growth_rate 增长直至 max_range
var influence_range: int = 0

## 驻扎单位增长（扩展占位，后续可用于驻军兵力随驻扎回合增长的机制）
## MVP 暂不参与计算
var garrison_unit_growth: int = 0

# ─────────────────────────────────────────
# 影响范围辅助字段（M4 使用，由配置注入）
# ─────────────────────────────────────────

## 影响范围初始值（类型 + 等级决定，由配置加载）
var initial_range: int = 0

## 影响范围上限（类型 + 等级决定，由配置加载）
var max_range: int = 0

## 影响范围增长速率（每回合涨多少；M4 使用）
var growth_rate: int = 1

# ─────────────────────────────────────────
# 建造系统字段（M5 使用）
# ─────────────────────────────────────────

## 建造槽位数（MVP 恒为 1，预留多槽扩展）
## 设计：升级建造设计 §三
var build_slot_count: int = 1

## 当前在建动作；null 表示空闲
## 同时只允许一个动作（受 build_slot_count 限制）
var active_build: BuildAction = null

# ─────────────────────────────────────────
# 字段访问辅助方法
# ─────────────────────────────────────────

## 获取类型显示名称（用于 UI）
func get_type_name() -> String:
	return TYPE_NAMES.get(type, "未知") as String


## 获取地图短标签（用于地图格文字标注）
func get_map_label() -> String:
	return TYPE_MAP_LABELS.get(type, "?") as String


## 获取归属势力显示名称
func get_owner_name() -> String:
	return Faction.faction_name(owner_faction)


## 是否处于建造空闲状态（无在建动作）
func is_build_idle() -> bool:
	return active_build == null


## 是否有在建动作
func has_active_build() -> bool:
	return active_build != null
