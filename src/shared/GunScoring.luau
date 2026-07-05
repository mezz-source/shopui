--!strict

--[[
	GunScoring
	----------
	Converts a GunSettings record into five 0 -> 1 "quality" bars for the
	weapon UI:

		DMG    - damage potential per trigger pull
		RATE   - how fast the gun cycles
		HANDLE - how controllable the gun is (inverse of recoil)
		CLIP   - magazine capacity
		ZOOM   - how much the iron sight zooms in (inverse of FOV)

	1 is always "best", 0 is always "worst" - matches the createBar(name, score)
	calls already in your weapon UI code.

	Everything is normalized against WEAPON_RANGE below: a set of expected
	min/max values pulled from across your whole gun roster (weakest pistol
	up to your beefiest explosive launcher). If you add a gun that blows
	past the current extremes, widen the range - otherwise every other gun's
	bars will visually compress toward one end.
]]

local GunScoring = {}

export type GunSettings = {
	BaseDamage: number,
	Auto: boolean,
	BurstFireEnabled: boolean,
	BulletPerBurst: number,
	FireRate: number,
	ReloadTime: number,
	AmmoPerMag: number,
	Spread: number,
	IdleAnimationID: number,
	EquippedAnimationID: number,
	ShotgunEnabled: boolean,
	BulletPerShot: number,
	Recoil: number,
	Range: number,
	ExplosiveEnabled: boolean,
	ExplosionRadius: number,
	FieldOfViewIS: number,
}

export type GunScores = {
	DMG: number,
	RATE: number,
	HANDLE: number,
	CLIP: number,
	ZOOM: number,
}

-- ============================================================
-- TUNABLE RANGES
-- ============================================================
-- Every stat gets clamped into [Min, Max] then mapped onto 0 -> 1.
-- Pull these numbers from the weakest/strongest gun currently in your game.
-- (Recoil bounds below mirror the comment already in your gun settings
-- file: "50 = Normal, 150 = Shotgun/Heavy Pistol, 250 = Heavy Sniper".)

local WEAPON_RANGE = {
	-- Damage a single trigger-pull can put out (BaseDamage * pellets/burst).
	EffectiveDamage = { Min = 8, Max = 200 },

	-- Rounds per second the gun can physically cycle at.
	RoundsPerSecond = { Min = 0.5, Max = 20 },

	-- Straight from GunSettings.Recoil.
	Recoil = { Min = 15, Max = 250 },

	-- Magazine size. math.huge (infinite ammo) auto-scores a perfect 1.
	AmmoPerMag = { Min = 1, Max = 100 },

	-- Iron sight FOV. Lower = tighter zoom = better ZOOM score.
	FieldOfViewIS = { Min = 15, Max = 70 },
}

-- Small bonus applied to effective damage when a shot can hit a whole group
-- at once - purely a "feels strong" nudge for the DMG bar. Set to 1 if you
-- don't want explosives to out-score their raw per-target damage.
local EXPLOSIVE_DAMAGE_BONUS = 1.25

-- ============================================================
-- HELPERS
-- ============================================================

local function clamp01(value: number): number
	if value < 0 then
		return 0
	elseif value > 1 then
		return 1
	end
	return value
end

-- Maps `value` from [range.Min, range.Max] onto [0, 1].
-- Set `invert` to true for stats where LOWER is better (Recoil, FieldOfViewIS).
local function normalize(value: number, range: { Min: number, Max: number }, invert: boolean?): number
	if value ~= value then -- NaN guard
		return 0
	end

	if value == math.huge then
		return if invert then 0 else 1
	end

	local min, max = range.Min, range.Max
	if max <= min then
		return 1
	end

	local t = clamp01((value - min) / (max - min))

	if invert then
		t = 1 - t
	end

	return t
end

-- ============================================================
-- INDIVIDUAL SCORES
-- ============================================================

local function getDamageScore(gun: GunSettings): number
	local projectiles = 1

	if gun.ShotgunEnabled and gun.BulletPerShot > 0 then
		projectiles = gun.BulletPerShot
	elseif gun.BurstFireEnabled and gun.BulletPerBurst > 0 then
		projectiles = gun.BulletPerBurst
	end

	local effectiveDamage = gun.BaseDamage * projectiles

	if gun.ExplosiveEnabled then
		effectiveDamage *= EXPLOSIVE_DAMAGE_BONUS
	end

	return normalize(effectiveDamage, WEAPON_RANGE.EffectiveDamage)
end

local function getRateScore(gun: GunSettings): number
	if gun.FireRate <= 0 then
		return 1
	end

	local roundsPerSecond = 1 / gun.FireRate

	-- FireRate is the mechanical cycle speed regardless of Auto/Burst, so we
	-- score that directly rather than trying to guess sustained trigger DPS.
	return normalize(roundsPerSecond, WEAPON_RANGE.RoundsPerSecond)
end

local function getHandleScore(gun: GunSettings): number
	-- Higher recoil = worse handling, so invert.
	return normalize(gun.Recoil, WEAPON_RANGE.Recoil, true)
end

local function getClipScore(gun: GunSettings): number
	return normalize(gun.AmmoPerMag, WEAPON_RANGE.AmmoPerMag)
end

local function getZoomScore(gun: GunSettings): number
	-- Lower FOV = tighter zoom = better, so invert.
	return normalize(gun.FieldOfViewIS, WEAPON_RANGE.FieldOfViewIS, true)
end

-- ============================================================
-- PUBLIC API
-- ============================================================

function GunScoring.Score(gun: GunSettings): GunScores
	return {
		DMG = getDamageScore(gun),
		RATE = getRateScore(gun),
		HANDLE = getHandleScore(gun),
		CLIP = getClipScore(gun),
		ZOOM = getZoomScore(gun),
	}
end

-- Exposed individually too, in case you only need one bar or want to unit
-- test a single stat without building a whole GunSettings table.
GunScoring.getDamageScore = getDamageScore
GunScoring.getRateScore = getRateScore
GunScoring.getHandleScore = getHandleScore
GunScoring.getClipScore = getClipScore
GunScoring.getZoomScore = getZoomScore

return GunScoring
