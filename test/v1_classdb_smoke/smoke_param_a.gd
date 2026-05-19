## [已知技术储备 - 当前未启用] 详见 base_param_resource_v1.gd 文件头说明
## D.1-V1 测试子类 A：模拟战斗参数 Resource
class_name SmokeParamA
extends BaseParamResourceV1

@export_range(0, 5000) var base_damage: int = 500
@export_range(0.0, 1.0) var quality_k: float = 0.2
@export var enemy_movement_enabled: bool = true


func _init() -> void:
	_panel_group = &"smokeA组"
