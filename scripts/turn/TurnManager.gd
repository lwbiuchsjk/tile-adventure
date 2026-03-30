class_name TurnManager
extends RefCounted
## 回合管理器
## 管理回合计数，在 tick 时执行全局属性变更。
## 当前 tick 仅重置单位移动力，预留后续扩展接口（资源产出、野怪刷新等）。

## 回合结束信号，参数为新的回合编号
signal turn_ended(turn_number: int)

## 当前回合编号（从 0 开始，首次 end_turn 后变为 1）
var current_turn: int = 0

## 已注册的单位列表
var _units: Array = []

# ─────────────────────────────────────────
# 公共接口
# ─────────────────────────────────────────

## 注册单位到回合管理器，tick 时会重置其移动力
func register_unit(unit: UnitData) -> void:
	_units.append(unit)

## 结束当前回合，执行 tick 后推进回合计数
func end_turn() -> void:
	current_turn += 1
	_tick()
	turn_ended.emit(current_turn)

# ─────────────────────────────────────────
# 私有：tick 逻辑
# ─────────────────────────────────────────

## 回合 tick：执行所有回合结算逻辑
## 扩展点：后续在此处追加资源结算、野怪刷新等逻辑
func _tick() -> void:
	# 重置所有注册单位的移动力
	for entry in _units:
		var unit: UnitData = entry as UnitData
		unit.current_movement = unit.max_movement
