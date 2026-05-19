## [已知限制根因附件 - 持续保留] 详见 test/test_v2_cache_repro.gd 文件头说明
## D.1-V2 cache bug 最小 repro Resource
class_name CacheSmokeResource
extends Resource

@export var test_float: float = 1.0
@export var test_int: int = 1
@export var test_color: Color = Color(1, 1, 1, 1)
@export var test_dict: Dictionary = {}
@export var test_array: Array = []
