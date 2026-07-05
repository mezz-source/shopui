local MeleeScoring = {}

local ShopTypes = require(script.Parent.ShopTypes)
type MeleeInfo = ShopTypes.MeleeInfo

local DAMAGE_BASELINE = 130
local SPEED_BASELINE = 0.4
local DEBOUNCE_BASELINE = 0.5
local KNOCKBACK_BASELINE = 900
local DEVIATION_BASSLINE = 10

function MeleeScoring.getDamageScore(meleeInfo: MeleeInfo): number
	return meleeInfo.DamageAmount / DAMAGE_BASELINE
end

function MeleeScoring.getSpeedScore(meleeInfo: MeleeInfo): number
	local totalDebounce = meleeInfo.Debounce + meleeInfo.SignalessEndTime + meleeInfo.SignalessSwingTime
	return SPEED_BASELINE / math.max(totalDebounce, 0.01)
end

function MeleeScoring.getKnockbackScore(meleeInfo: MeleeInfo): number
	return meleeInfo.KnockbackPower / KNOCKBACK_BASELINE
end

function MeleeScoring.getReliabilityScore(meleeInfo: MeleeInfo): number
	local deviation = math.abs(meleeInfo.Debounce - DEBOUNCE_BASELINE)
	return math.max(0, 1 - (deviation / DEVIATION_BASSLINE))
end

return MeleeScoring
