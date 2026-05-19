## [已知技术储备 - 当前未启用] MVP-D v0.2 走变体 A 弃用变体 B 基类自省
## 本文件保留作为"未来升级到变体 B"的技术参考
##
## D.1-V1 验证用基类（变体 B 草案）—— v0.2 未启用
class_name BaseParamResourceV1
extends Resource

## 调参面板分组名（场景标签页归属），子类必须 override；空字符串视为不进面板
@export var _panel_group: StringName = &""

## 子类可显式指定 .tres 实例路径；空字符串则按 class_name 推断
@export var _panel_resource_path: String = ""
