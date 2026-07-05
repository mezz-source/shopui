local MeleeScoring = {}

local ShopTypes = require(script.Parent.ShopTypes)
type MeleeInfo = ShopTypes.MeleeInfo

local DAMAGE_BASELINE = 130
local SPEED_BASELINE = 0.4
local KNOCKBACK_BASELINE = 1200
local MAX_DEVIATION = 35

function MeleeScoring.getDamageScore(meleeInfo: MeleeInfo): number
	if not meleeInfo or not meleeInfo.DamageAmount then
		return 0
	end

	return meleeInfo.DamageAmount / DAMAGE_BASELINE
end

function MeleeScoring.getSpeedScore(meleeInfo: MeleeInfo): number
	if not meleeInfo or not meleeInfo.Debounce then
		return 0
	end

	local totalDebounce = meleeInfo.Debounce + meleeInfo.SignalessEndTime + meleeInfo.SignalessSwingTime
	return SPEED_BASELINE / math.max(totalDebounce, 0.01)
end

function MeleeScoring.getKnockbackScore(meleeInfo: MeleeInfo): number
	if not meleeInfo or not meleeInfo.KnockbackPower then
		return 0
	end

	return meleeInfo.KnockbackPower / KNOCKBACK_BASELINE
end

function MeleeScoring.getReliabilityScore(meleeInfo: MeleeInfo): number
	if not meleeInfo or not meleeInfo.DamageDeviation then
		return 0
	end

	return math.clamp(1 - (meleeInfo.DamageDeviation / MAX_DEVIATION), 0, 1)
end

return MeleeScoring
