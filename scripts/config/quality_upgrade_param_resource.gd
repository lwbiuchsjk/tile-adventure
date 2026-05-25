class_name QualityUpgradeParamResource
extends Resource

## 品质升级参数 Resource（MVP-D D.2 批 3：quality_upgrade_config.csv 迁出，2 字段）
## 消费方：WorldMap → TroopData.load_upgrade_config(cfg: QualityUpgradeParamResource)

## R → SR 升级所需经验
@export_range(1, 10000, 1) var exp_r_to_sr: int = 100
## SR → SSR 升级所需经验
@export_range(1, 10000, 1) var exp_sr_to_ssr: int = 300
