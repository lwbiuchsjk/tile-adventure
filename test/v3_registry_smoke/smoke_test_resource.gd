## [D.1.c smoke test - 可保留作 registry 添加范例 或 D.4 后清理]
##
## MVP-D D.1.c：Pull 通道端到端 smoke test 资源
##
## 验证目标：普通 `extends Resource`（零调参意识）+ 加入 _panel_registry.tres 1 个 entry
## → F1 面板自动出现「smoke 测试」分组 + 3 字段（含 float / bool / Color 三种自省类型）
## → 字段调参 → realtime=false 默认带 ⚠ 重启生效后缀 → F2 写盘 → 重启验证持久化
##
## 剥离体现：本文件没有 BaseParamResource 基类、没有 _panel_group 字段、没有 _init 钩子
## —— 完全是普通 Resource，调参面板的纳入是另一边的事
class_name SmokeTestResource
extends Resource


## 范围有 hint：渲染 SliderFloat 用 hint 解析 min/max（推断验证）
@export_range(0.0, 10.0) var float_with_range: float = 3.14

## 范围无 hint：渲染 SliderFloat 用默认 [0, 100] 范围
@export var float_no_range: float = 50.0

## bool 字段：渲染 Checkbox（D.1.b 新增控件）
@export var bool_flag: bool = false

## Color 字段：渲染 ColorEdit4
@export var color_rgba: Color = Color(0.5, 0.7, 0.9, 1.0)

## int 字段（带 range hint）：渲染 SliderInt
@export_range(0, 200) var int_with_range: int = 42

## String 字段：渲染 InputText
@export var some_text: String = "hello"

## 此字段用于验证 skip_fields 功能（D.1.c smoke 默认不 skip；可在 registry 加 skip_fields=["skipped_field"] 验证）
@export var skipped_field: int = 999
