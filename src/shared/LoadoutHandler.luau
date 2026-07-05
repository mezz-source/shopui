local LoadoutHandler = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ShopRemotes = ReplicatedStorage:WaitForChild("ShopRemotes")
local ValidateLoadoutFunction = ShopRemotes:WaitForChild("ValidateLoadout") :: RemoteFunction

local ShopTypes = require(script.Parent.ShopTypes)

type Loadout = ShopTypes.Loadout
type WeaponSlot = ShopTypes.WeaponSlot

--- Confirm with the server this loadout is okay, and if not, why
local function validateLoadout(loadoutName: string, loadout: Loadout): { Success: boolean, Reason: string? }
	local result = ValidateLoadoutFunction:InvokeServer(loadoutName, loadout)
	return result
end

local function getLoadoutFromSlots(slots: { WeaponSlot }): Loadout
	local loadout: Loadout = {}
	for _, slot in slots do
		loadout[slot.SlotIndex] = slot.CurrentItem
	end
	return loadout
end

function LoadoutHandler.saveCurrentLoadout(
	loadoutName: string,
	currentSlots: { WeaponSlot }
): { Success: boolean, Reason: string? }
	local loadout = getLoadoutFromSlots(currentSlots)
	return validateLoadout(loadoutName, loadout)
end
