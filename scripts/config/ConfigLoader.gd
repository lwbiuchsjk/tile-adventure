class_name ConfigLoader
## 通用 CSV 配置文件加载工具
## 支持两种 CSV 格式：
##   表格格式：首行为表头，后续行为数据行 → 返回 Array[Dictionary]
##   键值格式：含 key/value 两列 → 返回扁平 Dictionary

# ─────────────────────────────────────────
# 公共接口
# ─────────────────────────────────────────

## 加载表格格式 CSV。首行作为表头，后续每行返回一个 {header: value} 字典。
## 所有值均为 String，类型转换由调用方负责。
static func load_csv(path: String) -> Array:
	if not FileAccess.file_exists(path):
		push_error("ConfigLoader: 文件不存在 -> " + path)
		return []

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("ConfigLoader: 无法打开文件 -> " + path)
		return []

	var headers: Array[String] = []
	var rows: Array = []
	var is_first_line: bool = true

	while not file.eof_reached():
		var line: String = file.get_line().strip_edges()
		# 跳过空行
		if line.is_empty():
			continue
		# 跳过注释行（以 # 开头）
		if line.begins_with("#"):
			continue

		var fields: PackedStringArray = line.split(",")
		if is_first_line:
			# 首行作为表头
			for f in fields:
				headers.append(f.strip_edges())
			is_first_line = false
			continue

		# 数据行：按表头映射为字典
		var row: Dictionary = {}
		for i in range(mini(headers.size(), fields.size())):
			row[headers[i]] = fields[i].strip_edges()
		rows.append(row)

	file.close()
	return rows

## 加载键值格式 CSV（需含 key、value 两列），返回 {key: value} 扁平字典。
## 所有值均为 String，类型转换由调用方负责。
static func load_csv_kv(path: String) -> Dictionary:
	var rows: Array = load_csv(path)
	var result: Dictionary = {}
	for entry in rows:
		var row: Dictionary = entry as Dictionary
		if row.has("key") and row.has("value"):
			result[row["key"]] = row["value"]
	return result
