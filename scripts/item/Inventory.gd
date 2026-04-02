class_name Inventory
extends RefCounted
## 背包容器
## 存储玩家获得的道具，支持容量上限。
## 不可堆叠道具（部队）每个占 1 格。
## 可堆叠道具（经验、兵力恢复）同 item_id 占 1 格，叠加数量。

## 背包容量上限
var max_capacity: int = 20

## 道具列表（每个元素为 ItemData 实例）
## 可堆叠道具通过 stack_count 管理数量，不可堆叠道具 stack_count 固定为 1
var _items: Array[ItemData] = []

## 从配置初始化背包容量
func init_from_config(cfg: Dictionary) -> void:
	max_capacity = int(cfg.get("max_capacity", "20"))

## 获取所有道具列表（只读）
func get_items() -> Array[ItemData]:
	return _items

## 获取当前占用格数
func get_used_slots() -> int:
	return _items.size()

## 判断背包是否已满
func is_full() -> bool:
	return _items.size() >= max_capacity

## 添加道具到背包
## 返回 true 表示成功添加，false 表示背包已满（溢出丢弃）
func add_item(item: ItemData) -> bool:
	if item == null:
		return false
	# 可堆叠道具：查找同 item_id 的已有条目，叠加数量
	if item.is_stackable():
		for existing in _items:
			if existing.item_id == item.item_id:
				existing.stack_count += item.stack_count
				return true
		# 没有同 ID 条目，作为新格存入
	# 检查容量
	if is_full():
		return false
	_items.append(item)
	return true

## 批量添加道具列表，返回实际添加成功的数量
func add_items(items: Array[ItemData]) -> int:
	var added: int = 0
	for item in items:
		if add_item(item):
			added += 1
	return added

## 移除指定道具（不可堆叠道具直接移除，可堆叠道具减少数量）
## amount: 移除数量，默认 1
func remove_item(item: ItemData, amount: int = 1) -> void:
	if item == null:
		return
	if item.is_stackable():
		item.stack_count -= amount
		if item.stack_count <= 0:
			_items.erase(item)
	else:
		_items.erase(item)

## 获取所有道具列表
func get_all_items() -> Array[ItemData]:
	return _items

## 按类型过滤道具（使用 int 比较避免 Variant/enum 问题）
func get_items_by_type(item_type: int) -> Array[ItemData]:
	var result: Array[ItemData] = []
	for item in _items:
		if item.type == item_type:
			result.append(item)
	return result

## 判断背包中是否有部队道具
func has_troop_items() -> bool:
	for item in _items:
		if item.type == ItemData.ItemType.TROOP:
			return true
	return false

## 获取背包内容的显示文本（用于 UI）
func get_display_text() -> String:
	if _items.is_empty():
		return "背包为空"
	var parts: Array[String] = []
	for item in _items:
		if item.stack_count > 1:
			parts.append("%s×%d" % [item.get_display_text(), item.stack_count])
		else:
			parts.append(item.get_display_text())
	return ", ".join(parts)
