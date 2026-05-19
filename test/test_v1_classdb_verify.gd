extends SceneTree
## [已知技术储备 - 当前未启用] MVP-D v0.2 走变体 A（中心 registry），变体 B（基类自省）弃用
## 本脚本保留作为"未来若 registry 维护成本爆炸时升级到变体 B"的技术参考
## 详见 MVP-D 设计文档 §风险与回滚 §风险 1
##
## D.1-V1：ClassDB / ProjectSettings 对 GDScript class_name 的枚举行为验证
##
## 目的：决定 MVP-D Pull 模式走变体 B（ClassDB 扫描）还是回退变体 A（中心 manifest）
##
## 验证 3 个候选 API：
##   (1) ClassDB.get_inheriters_from_class("BaseParamResourceV1")
##       —— 已知 Godot 4.x: ClassDB 只对 native class 有效，GDScript class 走 ScriptServer
##   (2) ProjectSettings.get_global_class_list()  / get_setting("_global_script_classes")
##       —— 编辑器扫描注册的 GDScript class_name 列表（含 base 字段）
##   (3) 实例化后 is_class / get_class —— 运行时类型检查回退路径


func _init() -> void:
	print("=== D.1-V1 ClassDB / ProjectSettings 验证 ===")
	print("")

	# --- 候选 1：ClassDB.get_inheriters_from_class ---
	print("[候选 1] ClassDB.get_inheriters_from_class(\"BaseParamResourceV1\")")
	if ClassDB.class_exists("BaseParamResourceV1"):
		var inheriters: PackedStringArray = ClassDB.get_inheriters_from_class("BaseParamResourceV1")
		print("  -> ClassDB 知晓 BaseParamResourceV1: true")
		print("  -> 子类列表: %s" % str(inheriters))
		print("  -> 子类数量: %d（期望 2: SmokeParamA / SmokeParamB）" % inheriters.size())
	else:
		print("  -> ClassDB 不知晓 BaseParamResourceV1（GDScript class 不进 ClassDB）")
	print("")

	# --- 候选 2：ProjectSettings 全局 class 列表 ---
	print("[候选 2] ProjectSettings 全局 class 列表（GDScript class_name 注册中心）")
	# Godot 4.6 推荐 API：ProjectSettings.get_global_class_list()
	var has_method: bool = ProjectSettings.has_method("get_global_class_list")
	print("  -> ProjectSettings.has_method('get_global_class_list'): %s" % has_method)
	if has_method:
		var class_list: Array = ProjectSettings.get_global_class_list()
		print("  -> 全局 class 总数: %d" % class_list.size())
		var matched: Array = []
		for entry: Dictionary in class_list:
			if entry.get("base", "") == "BaseParamResourceV1":
				matched.append(entry)
		print("  -> 继承自 BaseParamResourceV1 的子类条目:")
		for m: Dictionary in matched:
			print("     - class=%s base=%s path=%s" % [m.get("class"), m.get("base"), m.get("path")])
		print("  -> 子类数量: %d（期望 2）" % matched.size())
	print("")

	# --- 候选 3：实例化后 is / get_script ---
	print("[候选 3] 运行时实例化 + is 类型检查")
	var SmokeAScript: GDScript = load("res://test/v1_classdb_smoke/smoke_param_a.gd")
	var SmokeBScript: GDScript = load("res://test/v1_classdb_smoke/smoke_param_b.gd")
	var BaseScript: GDScript = load("res://test/v1_classdb_smoke/base_param_resource_v1.gd")
	var a: Resource = SmokeAScript.new()
	var b: Resource = SmokeBScript.new()
	print("  -> SmokeParamA._panel_group: %s（期望 smokeA组）" % a.get("_panel_group"))
	print("  -> SmokeParamB._panel_group: %s（期望 smokeB组）" % b.get("_panel_group"))

	# 通过 GDScript 关系判断
	var a_script: GDScript = a.get_script() as GDScript
	var a_base_script: GDScript = a_script.get_base_script() as GDScript
	print("  -> SmokeParamA 的 base script == BaseScript: %s" % (a_base_script == BaseScript))
	print("")

	print("=== 验证结论建议 ===")
	print("  - 若候选 1 返回 2 → 走变体 B（最简单）")
	print("  - 若候选 1 返回 0 / 不知晓但候选 2 返回 2 → 走变体 B 的 ProjectSettings 实现版（仍可行）")
	print("  - 若候选 1+2 都不行 → 回退变体 A（中心 manifest）")
	print("")
	quit()
