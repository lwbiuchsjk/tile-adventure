class_name DictComboGroup
extends Resource
## MVP-C.2 Dict 字段紧凑 Combo 模式：把同场景内多 Dict 字段共 key 的情况折叠为「Combo + N Slider」
##
## 适用：>=2 个 Dict 字段共用同一组 key（典型：UnitEnemyConfig.tier_border_widths + tier_slot_margins 共用 tier 0/1/2/3）
## 不适用：单字段多 key 场景（如 MapBaseConfig.terrain_colors，Combo 反而增加交互负担）


## 组名（UI 显示用，如「Tier 选择」）
@export var group_label: String = ""

## Combo 候选 dict key 列表（如 [0, 1, 2, 3]）
@export var dict_keys: Array = []

## 候选 key 在 Combo 下拉中的显示名（与 dict_keys 一一对应，如 ["Tier 1", "Tier 2", "Tier 3", "Tier 4"]）
@export var key_display_names: Array[String] = []

## 联动字段列表：每个 ParamFieldMapping 的 dict_key 在运行时由 Combo 选中值覆盖
## ParamFieldMapping.dict_key 在此场景下应留空（null），运行时由 Combo 当前选中值赋值
@export var linked_fields: Array[ParamFieldMapping] = []
