class_name RoundManager
extends RefCounted
## 轮次管理器
## 管理多轮次流程推进：每轮包含若干关卡，全部挑战后推进至下一轮。
## 末轮通关则流程胜利。
## 预留 on_round_transition() 干预接口，方便后续扩展轮次间结算。

## 轮次开始信号，参数：轮次索引（从 0 开始）
signal round_started(round_index: int)

## 所有轮次通关信号
signal all_rounds_cleared

# ─────────────────────────────────────────
# 轮次配置数据
# ─────────────────────────────────────────

## 每轮关卡数量列表，索引即轮次索引
var _round_level_counts: Array[int] = []

## 当前轮次索引（从 0 开始）
var _current_round: int = 0

## 当前轮已挑战的关卡数
var _cleared_count: int = 0

## 当前轮次的预生成胜利奖励
var _round_rewards: Array[ItemData] = []

# ─────────────────────────────────────────
# 初始化
# ─────────────────────────────────────────

## 从 round_config.csv 的行数据初始化轮次配置
## rows: ConfigLoader.load_csv() 返回的 Array[Dictionary]
func init_from_config(rows: Array) -> void:
	_round_level_counts = []
	for entry in rows:
		var row: Dictionary = entry as Dictionary
		var count: int = int(row.get("level_count", "3"))
		_round_level_counts.append(count)
	_current_round = 0
	_cleared_count = 0

# ─────────────────────────────────────────
# 查询接口
# ─────────────────────────────────────────

## 获取当前轮次索引（从 0 开始）
func get_current_round() -> int:
	return _current_round

## 获取总轮次数
func get_total_rounds() -> int:
	return _round_level_counts.size()

## 获取当前轮的关卡总数
func get_current_level_count() -> int:
	if _current_round < _round_level_counts.size():
		return _round_level_counts[_current_round]
	return 0

## 覆写当前轮的关卡总数（当实际生成数量与配置不同时调用）
func override_current_level_count(count: int) -> void:
	if _current_round < _round_level_counts.size():
		_round_level_counts[_current_round] = count

## 获取当前轮已挑战的关卡数
func get_cleared_count() -> int:
	return _cleared_count

## 判断是否为最后一轮
func is_last_round() -> bool:
	return _current_round >= _round_level_counts.size() - 1

# ─────────────────────────────────────────
# 流程推进
# ─────────────────────────────────────────

## 启动当前轮次，发出 round_started 信号
## 调用方收到信号后执行关卡生成
func start_current_round() -> void:
	_cleared_count = 0
	round_started.emit(_current_round)

## 通知一个关卡已挑战
## 返回值：true = 本轮全部挑战完毕，false = 本轮还有剩余
func on_level_cleared() -> bool:
	_cleared_count += 1
	return _cleared_count >= get_current_level_count()

## 尝试推进至下一轮
## 返回值：true = 成功推进至下一轮，false = 已是末轮（流程胜利）
func advance_round() -> bool:
	# 轮次切换干预点：后续可在此处插入轮次间结算、确认等逻辑
	if not on_round_transition():
		return false

	if is_last_round():
		all_rounds_cleared.emit()
		return false

	_current_round += 1
	start_current_round()
	return true

## 轮次切换干预接口（预留）
## 返回 true 允许切换，false 阻止切换
## 后续可覆写此方法实现：切换确认弹板、轮次间结算等
func on_round_transition() -> bool:
	return true

# ─────────────────────────────────────────
# 轮次奖励
# ─────────────────────────────────────────

## 设置当前轮次的预生成奖励（由外部在轮次开始时调用）
func set_round_rewards(rewards: Array[ItemData]) -> void:
	_round_rewards = rewards

## 获取当前轮次的预生成奖励
func get_round_rewards() -> Array[ItemData]:
	return _round_rewards
