class_name RewardGenerator
extends RefCounted
## 通用奖励生成器
## 从随机池按权重抽取道具，生成 ItemData 列表。
## 关卡奖励、轮次奖励、回合奖励共用此生成器，传入不同的池数据和数量配置。

## 道具配置模板字典 {item_id: ItemData}
var _item_templates: Dictionary = {}

## 从 item_config.csv 行数据加载道具模板
func load_item_templates(rows: Array) -> void:
	_item_templates = {}
	for entry in rows:
		var row: Dictionary = entry as Dictionary
		var item: ItemData = ItemData.from_config(row)
		_item_templates[item.item_id] = item

## 获取道具模板（供外部使用，如装配管理创建部队道具）
func get_template(item_id: int) -> ItemData:
	if _item_templates.has(item_id):
		return _item_templates[item_id] as ItemData
	return null

## 从随机池生成奖励列表
## pool_rows: 奖励池配置行（包含 round_id, item_id, count, weight 字段）
## round_id: 当前轮次 ID（用于过滤池，从 1 开始）
## reward_count: 抽取次数
## 返回生成的 ItemData 列表
func generate_rewards(pool_rows: Array, round_id: int, reward_count: int) -> Array[ItemData]:
	var rewards: Array[ItemData] = []

	# 按 round_id 过滤池条目
	var filtered_pool: Array[Dictionary] = []
	var total_weight: int = 0
	for entry in pool_rows:
		var row: Dictionary = entry as Dictionary
		var rid: int = int(row.get("round_id", "0"))
		if rid == round_id:
			filtered_pool.append(row)
			total_weight += int(row.get("weight", "1"))

	if filtered_pool.is_empty() or total_weight <= 0:
		return rewards

	# 按权重抽取指定次数
	for i in range(reward_count):
		var item: ItemData = _pick_from_pool(filtered_pool, total_weight)
		if item != null:
			rewards.append(item)

	return rewards

## 从随机池生成奖励（数量范围版本）
## count_min / count_max: 抽取数量的随机范围
func generate_rewards_range(pool_rows: Array, round_id: int, count_min: int, count_max: int) -> Array[ItemData]:
	var count: int = randi_range(count_min, count_max)
	return generate_rewards(pool_rows, round_id, count)

## 按权重从池中抽取一个道具
func _pick_from_pool(pool: Array[Dictionary], total_weight: int) -> ItemData:
	var roll: int = randi_range(1, total_weight)
	var cumulative: int = 0
	for row in pool:
		cumulative += int(row.get("weight", "1"))
		if roll <= cumulative:
			var item_id: int = int(row.get("item_id", "0"))
			var count: int = int(row.get("count", "1"))
			# 从模板创建道具实例
			if _item_templates.has(item_id):
				var template: ItemData = _item_templates[item_id] as ItemData
				var item: ItemData = template.duplicate_item()
				item.stack_count = count
				return item
			else:
				push_warning("RewardGenerator: 未找到道具模板 item_id=%d" % item_id)
				return null
	return null
