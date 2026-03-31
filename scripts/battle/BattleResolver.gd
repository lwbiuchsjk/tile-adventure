class_name BattleResolver
extends RefCounted
## 战斗结算接口
## MVP 阶段：固定胜利 + 固定兵损。
## 后续接入战斗引擎时，替换 resolve() 内部实现即可。

## 战斗结果数据
class BattleResult extends RefCounted:
	## 是否胜利
	var victory: bool = true
	## 我方承受的兵力损耗
	var damage_taken: int = 0

## 执行战斗结算
## character: 参战角色数据
## level: 目标关卡数据
## config: 战斗配置字典（从 battle_config.csv 加载）
## 返回 BattleResult
static func resolve(_character: CharacterData, _level: LevelSlot, config: Dictionary) -> BattleResult:
	var result: BattleResult = BattleResult.new()
	## MVP：固定胜利
	result.victory = true
	## 从配置读取固定兵损值，默认 100
	result.damage_taken = int(config.get("fixed_damage", "100"))
	return result
