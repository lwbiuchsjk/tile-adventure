class_name NarrativeProvider
extends RefCounted
##
## 入口 2 MVP 2.3 叙事文本随机池(2026-05-11)
##
## 6 个事件场景按情境差异化叙事文本,每个场景 5 条起步,等概率随机抽取 + 占位符替换
## 设计文档:[[../../tile-advanture-design/事件叙事池_MVP]]
##
## 使用模式:
##   # 应用启动一次性加载
##   var rows: Array = ConfigLoader.load_csv("res://assets/config/event_narrative_pool.csv")
##   NarrativeProvider.ensure_loaded(rows)
##
##   # 触发点抽取
##   var ctx: Dictionary = {"leader_name": "陈青锋", "item": "草药", "count": 2}
##   var narrative: String = NarrativeProvider.pick("camp_wild", ctx)
##
## 6 个 scenario 枚举:camp_wild / camp_village / camp_town / resource_slot_pickup
## / recruit_event / battle_victory
##

# ─────────────────────────────────────
# 静态状态
# ─────────────────────────────────────

## 文本池:scenario(String) → Array[String]
## ensure_loaded 时一次性填充,后续场景 reload 不重复加载
static var _pool: Dictionary = {}

## 防重复加载 flag
static var _initialized: bool = false

## 池中无该 scenario 文本 / pick 异常时的 fallback 模板
## 占位符仍会被替换(如果 ctx 提供了 leader_name)
const FALLBACK_NARRATIVE: String = "{leader_name} 获得了一些物资。"


# ─────────────────────────────────────
# 公开 API
# ─────────────────────────────────────

## 从 csv 行加载文本池;只首次调用生效(后续 reload 场景时不重复加载)
##
## rows 期望来自 ConfigLoader.load_csv("event_narrative_pool.csv")
## 每行字典含 scenario / narrative_template 两个字段
##
## 加载规则:
##   - 同 scenario 多行 append 到 Array[String]
##   - 模板字符串原样保存(占位符替换在 pick 时进行)
##   - 行字段缺失或为空 push_warning 后跳过
static func ensure_loaded(rows: Array) -> void:
	if _initialized:
		return
	_pool = {}
	for entry in rows:
		var row: Dictionary = entry as Dictionary
		var scenario: String = String(row.get("scenario", "")).strip_edges()
		var template: String = String(row.get("narrative_template", "")).strip_edges()
		if scenario.is_empty() or template.is_empty():
			push_warning("NarrativeProvider.ensure_loaded: 行缺失 scenario / narrative_template,跳过 — %s" % str(row))
			continue
		if not _pool.has(scenario):
			_pool[scenario] = []
		(_pool[scenario] as Array).append(template)
	_initialized = true


## 抽取 scenario 池一条文本并替换占位符
##
## scenario:6 个场景之一(camp_wild / camp_village / camp_town / resource_slot_pickup
##          / recruit_event / battle_victory)
## context:占位符值字典,key 与模板 `{key}` 对应
##
## 行为:
##   1. 池中无该 scenario(或为空):返回 FALLBACK_NARRATIVE 替换占位符,push_warning
##   2. 池中有:等概率随机选一条(用 randi_range)
##   3. 替换 ctx 内出现的 `{key}` 占位符
##   4. 替换后仍有 `{...}` 残留(模板写了 ctx 没填的 key):保留原样 + push_warning
##
## 等概率抽取:正常池容量 5 条,连续抽 2 次相同概率 1/5 = 20%(MVP 容忍)
static func pick(scenario: String, context: Dictionary) -> String:
	var template: String = ""
	if not _pool.has(scenario) or (_pool[scenario] as Array).is_empty():
		push_warning("NarrativeProvider.pick: scenario '%s' 池为空,走 fallback" % scenario)
		template = FALLBACK_NARRATIVE
	else:
		var pool_array: Array = _pool[scenario] as Array
		var idx: int = randi() % pool_array.size()
		template = pool_array[idx] as String

	return _format_template(template, context)


# ─────────────────────────────────────
# 内部
# ─────────────────────────────────────

## 用 String.replace 把 `{key}` 替换为 context[key]
##
## GDScript 4 String.format 不支持 `{key}` 命名参数,只支持 `{0}` 位置参数
## 自己实现:遍历 context 每个 key,把模板里的 `{key}` 替换为 str(value)
##
## 替换后用 regex 检查残留 `{...}`:命中则 push_warning(便于内容设计者排错模板拼写)
static func _format_template(template: String, context: Dictionary) -> String:
	var text: String = template
	for key in context:
		var key_str: String = String(key)
		text = text.replace("{" + key_str + "}", str(context[key]))
	# 检测残留占位符
	var regex: RegEx = RegEx.new()
	regex.compile("\\{[^{}]+\\}")
	var residual: RegExMatch = regex.search(text)
	if residual != null:
		push_warning("NarrativeProvider._format_template: 模板含未替换占位符 '%s' — 模板: '%s'" % [residual.get_string(), template])
	return text
