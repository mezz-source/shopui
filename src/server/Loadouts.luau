local Loadouts = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local TextService = game:GetService("TextService")

local ShopTypes = require(ReplicatedStorage.ShopClient.ShopTypes)
local ShopBindables = ServerStorage:WaitForChild("ShopBindables")
local GetAllInfoForCategory = ShopBindables:WaitForChild("GetAllInfoForCategory") :: BindableFunction
local GetPlayerOwnedItems = ShopBindables:WaitForChild("GetPlayerOwnedItems") :: BindableFunction
local LoadoutConfigs = ReplicatedStorage.ShopClient:WaitForChild("LoadoutConfigs")
local ShopRemotes = ReplicatedStorage:WaitForChild("ShopRemotes")
local DataAPI = require(ServerScriptService.DataAPI.API)

type Loadout = ShopTypes.Loadout
type LoadoutConfig = ShopTypes.LoadoutConfig
type WeaponInfo = ShopTypes.WeaponInfo

local itemInfoLibrary: { [string]: WeaponInfo } = {}

local function getLoadoutConfig(): LoadoutConfig
	local gamemode = workspace:GetAttribute("Gamemode")

	if gamemode == "Sandbox" then
		return require(LoadoutConfigs.Sandbox)
	else
		return require(LoadoutConfigs.Survival)
	end
end

local function textIsModerated(fromPlayer: Player, text: string): boolean
	local filteredString = TextService:FilterStringAsync(text, fromPlayer.UserId)
	return filteredString ~= text
end

local function loadInfoLibrary()
	local gunLibrary = GetAllInfoForCategory:Invoke("Guns")
	local meleeLibrary = GetAllInfoForCategory:Invoke("Melees")
	local armorLibrary = GetAllInfoForCategory:Invoke("Armor")

	for gunName, gunInfo in pairs(gunLibrary) do
		itemInfoLibrary[gunName] = gunInfo
	end

	for meleeName, meleeInfo in pairs(meleeLibrary) do
		itemInfoLibrary[meleeName] = meleeInfo
	end

	for armorName, armorInfo in pairs(armorLibrary) do
		itemInfoLibrary[armorName] = armorInfo
	end
end

local function getItemWeight(itemCategory: string, itemName: string, loadoutConfig: LoadoutConfig): number
	if not itemInfoLibrary[itemName] then
		warn("Item info not found for item: " .. itemName)
		return 0
	end

	local weightTier = itemInfoLibrary[itemName].Weight :: "Light" | "Moderate" | "Heavy"
	local map = {
		Light = loadoutConfig.lightWeaponWeight,
		Moderate = loadoutConfig.mediumWeaponWeight,
		Heavy = loadoutConfig.heavyWeaponWeight,
	}
	return map[weightTier] or 0
end

local function itemNameIsValid(itemName: string)
	return itemInfoLibrary[itemName] ~= nil
end

local function getPlayerOwnedItems(player: Player): { string }
	return GetPlayerOwnedItems:Invoke(player)
end

local function getLoadoutWeight(loadout: Loadout, loadoutConfig: LoadoutConfig): number
	local totalWeight = 0
	for _, itemName in ipairs(loadout) do
		if not itemInfoLibrary[itemName] then
			warn("Item info not found for item: " .. itemName)
			continue
		end

		local itemCategory = itemInfoLibrary[itemName].Category
		local itemWeight = getItemWeight(itemCategory, itemName, loadoutConfig)
		totalWeight += itemWeight
	end
	return totalWeight
end

function Loadouts.validateLoadout(
	player: Player,
	loadoutName: string,
	loadout: Loadout
): { Success: boolean, Reason: string? }
	-- Layer 1 -- check to see if they own what they say they do, no duplicates, no invalid items, etc.
	local playerOwnedItems = getPlayerOwnedItems(player)
	local seenItems = {}
	for number, itemName in ipairs(loadout) do
		if seenItems[itemName] then
			return { Success = false, Reason = "Duplicate item found: " .. itemName }
		end
		seenItems[itemName] = true

		if not itemNameIsValid(itemName) then
			return { Success = false, Reason = "Invalid item name: " .. itemName }
		end

		local owns = table.find(playerOwnedItems, itemName)
		if not owns then
			return { Success = false, Reason = "You don't own the item: " .. itemName }
		end
	end

	-- Layer 2 -- does this match the current loadout configuration?
	-- E.G weight check passes. if not, then indicates desync/tamper
	local loadoutConfig = getLoadoutConfig()
	local maxSlots = loadoutConfig.maxSlots

	if #loadout > maxSlots then
		return { Success = false, Reason = "Loadout exceeds maximum slots" }
	end

	local weight = getLoadoutWeight(loadout, loadoutConfig)
	if weight > loadoutConfig.maxWeight then
		return { Success = false, Reason = "Loadout exceeds maximum weight" }
	end

	return { Success = true, Reason = nil }
end

local function serverLoadoutInvoke(
	player: Player,
	loadoutName: string,
	loadout: Loadout
): { Success: boolean, Reason: string? }
	-- Verify the types, and that each one makes sense
	-- if they don't match, very likely tamper
	if typeof(loadoutName) ~= "string" then
		return { Success = false, Reason = "I'm not telling you anything!" }
	end

	if typeof(loadout) ~= "table" then
		return { Success = false, Reason = "I'm not telling you anything!" }
	end

	for _, itemName in ipairs(loadout) do
		if typeof(itemName) ~= "string" then
			return { Success = false, Reason = "I'm not telling you anything!" }
		end
	end

	-- Make sure the name isnt moderated
	if textIsModerated(player, loadoutName) then
		return { Success = false, Reason = "Loadout name was moderated" }
	end

	-- Validate the actual logic of the loadout last
	return Loadouts.validateLoadout(player, loadoutName, loadout)
end

function Loadouts.load()
	loadInfoLibrary()

	ShopRemotes.ValidateLoadout.OnServerInvoke = serverLoadoutInvoke

	print("Loaded shop loadouts system")
end

return Loadouts
