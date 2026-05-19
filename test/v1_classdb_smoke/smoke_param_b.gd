## [已知技术储备 - 当前未启用] 详见 base_param_resource_v1.gd 文件头说明
## D.1-V1 测试子类 B：模拟整局参数 Resource
class_name SmokeParamB
extends BaseParamResourceV1

@export_range(1, 10) var max_cycles: int = 3
@export var some_color: Color = Color(1, 0, 0)


func _init() -> void:
	_panel_group = &"smokeB组"
