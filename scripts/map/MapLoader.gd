class_name MapLoader
## 静态地图 JSON 加载器
## 解析 JSON 文件或字符串，填充并返回 MapSchema。
## 支持手工编写的测试地图与关卡编辑器导出的关卡文件。
##
## JSON 格式规范：
## {
##   "width":  int,                              // 地图列数
##   "height": int,                              // 地图行数
##   "cells":  [[int, ...], ...],                // 行优先，值为 TerrainType 枚举整数
##   "slots":  [{"x": int, "y": int, "type": int}, ...]  // 可选，SlotType 枚举整数
## }

# ─────────────────────────────────────────
# 公共接口
# ─────────────────────────────────────────

## 从文件路径加载地图。成功返回 MapSchema，失败返回 null。
static func load_from_file(path: String) -> MapSchema:
	if not FileAccess.file_exists(path):
		push_error("MapLoader: 文件不存在 -> " + path)
		return null

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("MapLoader: 无法打开文件 -> " + path)
		return null

	var text: String = file.get_as_text()
	file.close()

	return load_from_json_string(text)

## 从 JSON 字符串加载地图。成功返回 MapSchema，失败返回 null。
static func load_from_json_string(json_text: String) -> MapSchema:
	var json: JSON = JSON.new()
	var err: int = json.parse(json_text)
	if err != OK:
		push_error("MapLoader: JSON 解析失败，错误码=%d，行=%d" % [err, json.get_error_line()])
		return null

	var data: Dictionary = json.data as Dictionary
	if not _validate_data(data):
		return null

	var width: int = int(data["width"])
	var height: int = int(data["height"])
	var schema: MapSchema = MapSchema.new()
	schema.init(width, height)

	# 填充地形网格
	var cells: Array = data["cells"] as Array
	for y in range(height):
		var row: Array = cells[y] as Array
		for x in range(width):
			var terrain_id: int = int(row[x])
			schema.set_terrain(x, y, terrain_id as MapSchema.TerrainType)

	# 填充插槽（可选字段）
	if data.has("slots"):
		var slots: Array = data["slots"] as Array
		for entry in slots:
			var sd: Dictionary = entry as Dictionary
			var sx: int = int(sd["x"])
			var sy: int = int(sd["y"])
			var slot_id: int = int(sd["type"])
			schema.set_slot(sx, sy, slot_id as MapSchema.SlotType)

	return schema

# ─────────────────────────────────────────
# 私有：数据校验
# ─────────────────────────────────────────

## 校验 JSON 数据结构合法性
static func _validate_data(data: Dictionary) -> bool:
	# 检查必要字段
	for field in ["width", "height", "cells"]:
		if not data.has(field):
			push_error("MapLoader: JSON 缺少必要字段：" + field)
			return false

	var width: int = int(data["width"])
	var height: int = int(data["height"])
	var cells: Array = data["cells"] as Array

	# 检查行数与 height 匹配
	if cells.size() != height:
		push_error("MapLoader: cells 行数（%d）与 height（%d）不匹配" % [cells.size(), height])
		return false

	# 检查每行列数与 width 匹配
	for y in range(height):
		var row: Array = cells[y] as Array
		if row.size() != width:
			push_error("MapLoader: 第 %d 行列数（%d）与 width（%d）不匹配" % [y, row.size(), width])
			return false

	return true
