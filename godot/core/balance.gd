extends RefCounted

const CRIT_MULT := 1.5
const JIANYI_BASE := 30
const REGEN_PER_RECOVERY := 2
const LEVEL_BONUS := 0.04  # 已弃用：熟练度伤害加成改由 data/mastery.json 提供
const MAX_ROUNDS := 200
const MAX_LEVEL := 10
const FORESIGHT_ROUNDS := 2


static func heal_amount(base: int, recovery: int, realm_scale: float) -> int:
	return floori(float(base) * realm_scale * (1.0 + float(recovery) / 25.0))
