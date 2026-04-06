class_name ItemData
extends RefCounted
## 道具数据
## 统一基类，通过 type 枚举区分三种道具类型：
##   TROOP: 部队道具（不可堆叠），装配到角色槽位
##   EXP: 部队经验道具（可堆叠），消耗后为已装配部队增加经验
##   HP_RESTORE: 兵力恢复道具（可堆叠），消耗后回复兵力
## 经验道具和兵力恢复道具支持限定规则（兵种、品质）。

## 道具类型枚举
enum ItemType {
	TROOP      = 0,  ## 部队道具
	EXP        = 1,  ## 部队经验道具
	HP_RESTORE = 2,  ## 兵力恢复道具
}

## 道具类型名称映射（用于配置解析）
const TYPE_NAME_MAP: Dictionary = {
	"TROOP": ItemType.TROOP,
	"EXP": ItemType.EXP,
	"HP_RESTORE": ItemType.HP_RESTORE,
}

## 道具唯一 ID（对应配置表中的 item_id）
var item_id: int = 0

## 道具类型（存储为 int 以避免 Variant/enum 比较问题）
var type: int = ItemType.TROOP

## 部队道具专用：兵种 ID（-1 表示非部队道具）
var troop_type: int = -1

## 部队道具专用：品质 ID（-1 表示非部队道具）
var quality: int = -1

## 部队道具专用：保存的当前兵力（-1 表示未保存，装备时使用满血）
var troop_current_hp: int = -1

## 部队道具专用：保存的最大兵力
var troop_max_hp: int = 1000

## 部队道具专用：保存的经验值
var troop_exp: int = 0

## 显示名称
var display_name: String = ""

## 效果数值（EXP = 经验值，HP_RESTORE = 回复兵力值，TROOP 不使用）
var value: int = 0

## 限定兵种（-1 = 不限制，具体兵种 ID 时仅对该兵种生效）
var restrict_troop: int = -1

## 限定品质（-1 = 不限制，具体品质 ID 时仅当配置品质 ≥ 部队品质时可用）
var restrict_quality: int = -1

## 堆叠数量（可堆叠道具使用，不可堆叠道具固定为 1）
var stack_count: int = 1

## 判断是否可堆叠
func is_stackable() -> bool:
	return type != ItemType.TROOP

## 判断该道具是否可对指定部队使用
## 用于经验道具和兵力恢复道具的限定规则校验
func can_use_on(troop: TroopData) -> bool:
	if troop == null:
		return false
	# 部队道具通过装配使用，不走此方法
	if type == ItemType.TROOP:
		return false
	# 经验道具：已达最高品质时不可消耗
	if type == ItemType.EXP and troop.quality == TroopData.Quality.SSR:
		return false
	# 兵力恢复道具：兵力已满时不可消耗
	if type == ItemType.HP_RESTORE and troop.current_hp >= troop.max_hp:
		return false
	# 限定兵种检查
	if restrict_troop >= 0 and int(troop.troop_type) != restrict_troop:
		return false
	# 限定品质检查：配置品质 ≥ 部队品质时可用
	if restrict_quality >= 0 and restrict_quality < int(troop.quality):
		return false
	return true

## 获取显示文本（用于 UI 展示）
func get_display_text() -> String:
	if type == ItemType.TROOP:
		var type_name: String = TroopData.TROOP_TYPE_NAMES.get(troop_type, "未知") as String
		var quality_name: String = TroopData.QUALITY_NAMES.get(quality, "?") as String
		# 有保存的兵力状态时显示
		if troop_current_hp >= 0 and troop_current_hp < troop_max_hp:
			return "%s(%s) %d/%d" % [type_name, quality_name, troop_current_hp, troop_max_hp]
		return "%s(%s)" % [type_name, quality_name]
	elif type == ItemType.EXP:
		return "%s(经验+%d)" % [display_name, value]
	elif type == ItemType.HP_RESTORE:
		return "%s(兵力+%d)" % [display_name, value]
	return display_name

## 从配置行创建道具实例
static func from_config(row: Dictionary) -> ItemData:
	var item: ItemData = ItemData.new()
	item.item_id = int(row.get("item_id", "0"))
	var type_str: String = row.get("type", "TROOP") as String
	item.type = int(TYPE_NAME_MAP.get(type_str, ItemType.TROOP))
	item.troop_type = int(row.get("troop_type", "-1"))
	item.quality = int(row.get("quality", "-1"))
	item.display_name = row.get("display_name", "") as String
	item.value = int(row.get("value", "0"))
	item.restrict_troop = int(row.get("restrict_troop", "-1"))
	item.restrict_quality = int(row.get("restrict_quality", "-1"))
	return item

## 创建此道具的副本（用于从配置模板生成实际道具实例）
func duplicate_item() -> ItemData:
	var copy: ItemData = ItemData.new()
	copy.item_id = item_id
	copy.type = type
	copy.troop_type = troop_type
	copy.quality = quality
	copy.display_name = display_name
	copy.value = value
	copy.restrict_troop = restrict_troop
	copy.restrict_quality = restrict_quality
	copy.stack_count = stack_count
	copy.troop_current_hp = troop_current_hp
	copy.troop_max_hp = troop_max_hp
	copy.troop_exp = troop_exp
	return copy
