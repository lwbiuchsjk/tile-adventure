class_name BattleFloatText
extends Node2D
## 战斗飘字组件（入口 1.2 战斗信息传达 战斗内 MVP §5 改动 3）
##
## 设计依据：tile-advanture-design/战斗信息传达_战斗内_MVP.md §5 改动 3 / §8 视觉规格基准
##
## 行为：
##   - 主行 + 副行（可选）垂直布局；副行字号小一档
##   - 起始位置 = 目标 world_pos；持续 duration 秒内 y 上飘 RISE_DISTANCE px + alpha 1.0 → 0.0 渐隐
##   - 不阻塞下一行动（视觉层并行）；Tween 完成自删
##
## 用法（静态工厂）：
##   BattleFloatText.spawn_damage(parent, world_pos, "120", "+10% 高度", Color.GREEN)
##   BattleFloatText.spawn_text(parent, world_pos, "跳过", Color.GRAY, 0.6)

const MAIN_FONT_SIZE: int = 14                 ## 主行字号
const SUBTITLE_FONT_SIZE: int = 10             ## 副行字号
const RISE_DISTANCE: float = 24.0              ## 上飘像素距离
const DEFAULT_DURATION: float = 1.0            ## 默认持续时间（伤害飘字）
const SUBTITLE_LINE_HEIGHT: float = 12.0       ## 主行基线到副行基线垂直间距
const TEXT_WIDTH: float = 200.0                ## 文字水平居中参考宽度（远大于实际飘字宽度，保证 CENTER 对齐生效）

var _main_text: String = ""
var _subtitle: String = ""
var _color: Color = Color.WHITE
var _duration: float = DEFAULT_DURATION
var _font: Font = null


## 显示伤害飘字（主行 + 可选副行）
##   parent      —— 飘字挂载的父节点（通常 = WorldMap 自身，使用世界坐标）
##   world_pos   —— 飘字起始世界坐标（通常 = 被攻击者头顶位置）
##   main_text   —— 主行文字（如伤害数字 "120"）
##   subtitle    —— 副行文字（如 "+10% 高度"）；为空则不画副行
##   color       —— 文字颜色（按 counter_factor 编码：绿/橙/红）
##   duration    —— 持续时间（默认 1.0s）
static func spawn_damage(
	parent: Node, world_pos: Vector2,
	main_text: String, subtitle: String,
	color: Color, duration: float = DEFAULT_DURATION
) -> BattleFloatText:
	var ft: BattleFloatText = BattleFloatText.new()
	ft._main_text = main_text
	ft._subtitle = subtitle
	ft._color = color
	ft._duration = maxf(0.05, duration)
	ft.position = world_pos
	parent.add_child(ft)
	return ft


## 显示通用单行飘字（如"跳过"）
##   color 直接用作字色；duration 默认 1.0s（"跳过"由调用方传 0.6s）
static func spawn_text(
	parent: Node, world_pos: Vector2,
	text: String, color: Color, duration: float = DEFAULT_DURATION
) -> BattleFloatText:
	return spawn_damage(parent, world_pos, text, "", color, duration)


func _ready() -> void:
	_font = ThemeDB.fallback_font
	# 启动 Tween：position.y 上飘 + modulate.a 渐隐；并行执行；finished 后自删
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "position:y", position.y - RISE_DISTANCE, _duration)
	tween.tween_property(self, "modulate:a", 0.0, _duration)
	tween.finished.connect(queue_free)
	# 触发初次绘制
	queue_redraw()


func _draw() -> void:
	if _font == null or _main_text.is_empty():
		return
	# 主行：基线 y=0，宽度 TEXT_WIDTH 内 CENTER 对齐
	draw_string(
		_font,
		Vector2(-TEXT_WIDTH * 0.5, 0.0),
		_main_text,
		HORIZONTAL_ALIGNMENT_CENTER,
		TEXT_WIDTH,
		MAIN_FONT_SIZE,
		_color
	)
	# 副行（可选）：向下偏移 SUBTITLE_LINE_HEIGHT；颜色复用主行
	if not _subtitle.is_empty():
		draw_string(
			_font,
			Vector2(-TEXT_WIDTH * 0.5, SUBTITLE_LINE_HEIGHT),
			_subtitle,
			HORIZONTAL_ALIGNMENT_CENTER,
			TEXT_WIDTH,
			SUBTITLE_FONT_SIZE,
			_color
		)
