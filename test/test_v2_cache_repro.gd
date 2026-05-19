extends SceneTree
## [已知限制根因附件 - 持续保留] MVP-D v0.2 不修 const cache bug，作为已知限制保留
## 通过 registry `realtime: true` 字段让开发者按需付出 const → var 改造代价
## 本脚本是该已知限制的根因复现 + 修法 (a)(b)(c) 副作用验证
## 详见 MVP-D 设计文档 §const Resource cache bug 已知限制（不修，记录根因）
##
## D.1-V2：const Resource 字段访问 cache bug 最小 repro（修订版）
##
## 已知现象（来源待跟踪 §十四）：
##   - `const CFG = preload(...)` 后 `CFG.color_field` 调参后视觉不更新（重启才生效）
##   - `var c = CFG.dict_field; c.get(key)` 拿到新值；`CFG.dict_field.get(key)` 拿到旧值
##
## 修订要点：const 实例不允许直接字段 set（parse 阶段阻断），需走 Resource.set() 反射 API
##   ImGui 调参面板正是走 reflection set 路径（ParamPanelController 用 obj.set(prop_name, value)）
##
## 验证目标：
##   1. 反射 set 后，CFG.field 直读 vs Resource.get(field_name) 反射读 是否一致
##   2. 值类型 vs 引用类型 行为差异
##   3. 候选修法 a/b/c 各自验证

const CFG: Resource = preload("res://test/v2_cache_repro/cache_smoke.tres")


func _init() -> void:
	print("=== D.1-V2 const Resource cache bug repro (rev) ===")
	print("")

	# --- 阶段 1：初始值读取（直读 vs 反射读，应一致）---
	print("[阶段 1] 初始值读取基线")
	print("  CFG.test_float          = %s" % str(CFG.test_float))
	print("  CFG.get('test_float')   = %s" % str(CFG.get("test_float")))
	print("  CFG.test_color          = %s" % str(CFG.test_color))
	print("  CFG.get('test_color')   = %s" % str(CFG.get("test_color")))
	print("  CFG.test_dict           = %s" % str(CFG.test_dict))
	print("  CFG.test_dict.get('k')  = %s" % str(CFG.test_dict.get("k", "MISS")))
	print("")

	# --- 阶段 2：走反射 set 修改（模拟 ImGui 调参写回路径）---
	print("[阶段 2] 走 Resource.set() 反射 API 修改字段")
	CFG.set("test_float", 99.9)
	CFG.set("test_int", 99)
	CFG.set("test_color", Color(0.5, 0.25, 0.75, 1.0))
	# Dict / Array 反射 set 通常是整体替换
	var new_dict: Dictionary = {"k": "modified", "new_key": "added"}
	CFG.set("test_dict", new_dict)
	var new_array: Array = [10, 20, 30, 999]
	CFG.set("test_array", new_array)
	print("  反射 set 完成")
	print("")

	# --- 阶段 3：set 后直读 vs 反射读对比（核心 bug 复现点）---
	print("[阶段 3] 直读 CFG.field vs 反射 CFG.get(field) —— 核心 bug 复现")
	print("  -- 值类型 --")
	print("    CFG.test_float          = %s（直读，bug 假设：返回旧值 1.0）" % str(CFG.test_float))
	print("    CFG.get('test_float')   = %s（反射读，期望新值 99.9）" % str(CFG.get("test_float")))
	print("    CFG.test_int            = %s（直读，bug 假设：返回旧值 1）" % str(CFG.test_int))
	print("    CFG.get('test_int')     = %s（反射读，期望新值 99）" % str(CFG.get("test_int")))
	print("    CFG.test_color          = %s（直读，bug 假设：返回旧值 1,1,1,1）" % str(CFG.test_color))
	print("    CFG.get('test_color')   = %s（反射读，期望新值 0.5,0.25,0.75,1.0）" % str(CFG.get("test_color")))

	print("  -- 引用类型 --")
	print("    CFG.test_dict           = %s（直读，bug 假设：旧 dict）" % str(CFG.test_dict))
	print("    CFG.get('test_dict')    = %s（反射读，期望新 dict）" % str(CFG.get("test_dict")))
	print("    CFG.test_dict.get('new_key') = %s（链式 get，bug 假设：MISS）" % str(CFG.test_dict.get("new_key", "MISS")))
	print("    CFG.test_array.size()   = %s（直读 + 链式 size，bug 假设：3）" % str(CFG.test_array.size()))
	print("    CFG.get('test_array').size() = %s（反射读 + size，期望 4）" % str(CFG.get("test_array").size()))
	print("")

	# --- 阶段 4：中转 var 读 ---
	print("[阶段 4] var 中转后读")
	var v_f: float = CFG.test_float
	var v_c: Color = CFG.test_color
	var v_d: Dictionary = CFG.test_dict
	var v_a: Array = CFG.test_array
	print("    var f = CFG.test_float → %s" % str(v_f))
	print("    var c = CFG.test_color → %s" % str(v_c))
	print("    var d = CFG.test_dict  → %s" % str(v_d))
	print("    var d.get('new_key')   → %s" % str(v_d.get("new_key", "MISS")))
	print("    var a = CFG.test_array → size %s" % str(v_a.size()))
	print("")

	# --- 阶段 5：候选修法 (c) ResourceLoader CACHE_MODE_REPLACE ---
	print("[阶段 5] 候选修法 (c)：ResourceLoader.load(CACHE_MODE_REPLACE) 强 reload")
	var reloaded: Resource = ResourceLoader.load(
		"res://test/v2_cache_repro/cache_smoke.tres",
		"",
		ResourceLoader.CACHE_MODE_REPLACE
	)
	print("    reloaded.test_float   = %s（CACHE_REPLACE 后，期望 .tres 文件初值 1.0）" % str(reloaded.test_float))
	print("    reloaded == CFG ?     = %s" % str(reloaded == CFG))
	print("    CFG.test_float        = %s（reload 后再读 CFG 直读）" % str(CFG.test_float))
	print("    CFG.get('test_float') = %s（reload 后反射读 CFG）" % str(CFG.get("test_float")))
	print("")

	# --- 阶段 6：候选修法 (b) var X = load(...) 运行时 ---
	print("[阶段 6] 候选修法 (b)：var X = load(...) 替代 const preload")
	var VAR_CFG: Resource = load("res://test/v2_cache_repro/cache_smoke.tres")
	print("    VAR_CFG.test_float    = %s（var 持有 + 直读）" % str(VAR_CFG.test_float))
	VAR_CFG.set("test_float", 77.7)
	print("    set VAR_CFG test_float = 77.7（走反射）")
	print("    再读 VAR_CFG.test_float = %s（期望 77.7）" % str(VAR_CFG.test_float))
	print("    再反射读 VAR_CFG.get('test_float') = %s" % str(VAR_CFG.get("test_float")))
	print("")

	print("=== 结论判定提示 ===")
	print("  - 阶段 3 「直读 vs 反射读」差异 → bug 复现 + 根因 = 编译期常量传播")
	print("  - 阶段 3 直读 = 反射读 都为新值 → headless 不复现 bug，需 ImGui / 跨 frame / 渲染路径触发")
	print("  - 阶段 4 var 中转返回新值 + 阶段 3 直读返回旧值 → 修法 (a) 全局加中转 var 可行")
	print("  - 阶段 5 reloaded 拿 .tres 文件值 + CFG 直读跟随更新 → 修法 (c) 可行")
	print("  - 阶段 6 var X = load 持续可写 + 直读跟随 → 修法 (b) 可行")
	print("")
	quit()
