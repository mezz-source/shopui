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
local MAX_LOADOUT_NAME_LENGTH = 32
local MAX_PLAYER_LOADOUTS = 25

local function getLoadoutConfig(): LoadoutConfig
	local gamemode = workspace:GetAttribute("Gamemode")

	if gamemode == "Sandbox" then
		return require(LoadoutConfigs.Sandbox)
	else
		return require(LoadoutConfigs.Survival)
	end
end

local function textIsModerated(fromPlayer: Player, text: string): boolean
	local success, result = pcall(function()
		local filteredString = TextService:FilterStringAsync(text, fromPlayer.UserId) :: TextFilterResult
		local finalString = filteredString:GetNonChatStringForBroadcastAsync()
		return finalString ~= text
	end)

	if not success then
		warn(`Text moderation check failed for loadout name: {result}`)
		return true
	end

	return result
end

local function trimString(value: string): string
	return string.gsub(value, "^%s*(.-)%s*$", "%1")
end

local function validateLoadoutName(loadoutName: string): { Success: boolean, Reason: string? }
	local trimmed = trimString(loadoutName)
	if trimmed == "" then
		return { Success = false, Reason = "Loadout name cannot be empty" }
	end

	if string.len(trimmed) > MAX_LOADOUT_NAME_LENGTH then
		return {
			Success = false,
			Reason = `Loadout name cannot exceed {MAX_LOADOUT_NAME_LENGTH} characters`,
		}
	end

	if not string.match(trimmed, "^[%w _%-]+$") then
		return { Success = false, Reason = "Loadout name contains unsupported characters" }
	end

	return { Success = true, Reason = nil }
end

local function loadInfoLibrary()
	local gunLibrary = GetAllInfoForCategory:Invoke("Gun")
	local meleeLibrary = GetAllInfoForCategory:Invoke("Melee")
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
	-- Also no new empty loadouts
	if #loadout == 0 then
		return { Success = false, Reason = "Loadout cannot be empty" }
	end

	local playerOwnedItems = getPlayerOwnedItems(player)
	local seenItems = {}
	for number, itemName in ipairs(loadout) do
		-- Nothing there, nothing to worry about
		if itemName == "None" then
			continue
		end

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

	return { Success = true, Reason = nil } -- TODO: bully the data API Into saving it
	-- also integrate overwriting existing ones
end

local function serverLoadoutInvoke(
	player: Player,
	loadoutName: string,
	loadout: Loadout
): {
	Success: boolean,
	Reason: string?,
	Loadouts: { [string]: Loadout }?,
	ActiveLoadout: string?,
}
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

	local nameValidation = validateLoadoutName(loadoutName)
	if not nameValidation.Success then
		return nameValidation
	end

	local trimmedName = trimString(loadoutName)

	-- Make sure the name isnt moderated
	if textIsModerated(player, trimmedName) then
		return { Success = false, Reason = "Loadout name was moderated" }
	end

	-- Validate the actual logic of the loadout last
	local validationResult = Loadouts.validateLoadout(player, trimmedName, loadout)
	if not validationResult.Success then
		return validationResult
	end

	return DataAPI.upsertPlayerLoadout(player, trimmedName, loadout, MAX_PLAYER_LOADOUTS)
end

local function getPlayerLoadoutsInvoke(player: Player): {
	Success: boolean,
	Reason: string?,
	Loadouts: { [string]: Loadout }?,
	ActiveLoadout: string?,
}
	return DataAPI.getPlayerLoadoutsResult(player)
end

local function removePlayerLoadoutInvoke(player: Player, loadoutName: string): { Success: boolean, Reason: string? }
	if typeof(loadoutName) ~= "string" then
		return { Success = false, Reason = "Invalid loadout name" }
	end

	if loadoutName == "Default" then
		return { Success = false, Reason = "Cannot remove the default loadout" }
	end

	local nameValidation = validateLoadoutName(loadoutName)
	if not nameValidation.Success then
		return nameValidation
	end

	return DataAPI.removePlayerLoadout(player, trimString(loadoutName))
end

local function setActiveLoadoutInvoke(
	player: Player,
	loadoutName: string
): { Success: boolean, Reason: string?, ActiveLoadout: string? }
	if typeof(loadoutName) ~= "string" then
		return { Success = false, Reason = "Invalid loadout name" }
	end

	local nameValidation = validateLoadoutName(loadoutName)
	if not nameValidation.Success then
		return { Success = false, Reason = nameValidation.Reason }
	end

	local trimmedName = trimString(loadoutName)
	local setActiveSuccess = DataAPI.setPlayerActiveLoadout(player, trimmedName)
	if not setActiveSuccess then
		return { Success = false, Reason = "Failed to set active loadout" }
	end

	return { Success = true, ActiveLoadout = trimmedName }
end

function Loadouts.load()
	loadInfoLibrary()

	ShopRemotes.ValidateLoadout.OnServerInvoke = serverLoadoutInvoke
	ShopRemotes.GetPlayerLoadouts.OnServerInvoke = getPlayerLoadoutsInvoke
	ShopRemotes.RemoveLoadout.OnServerInvoke = removePlayerLoadoutInvoke

	local setActiveRemote = ShopRemotes:FindFirstChild("SetActiveLoadout")
	if setActiveRemote and setActiveRemote:IsA("RemoteFunction") then
		setActiveRemote.OnServerInvoke = setActiveLoadoutInvoke
	else
		warn("ShopRemotes.SetActiveLoadout RemoteFunction is missing")
	end

	local setActiveBindable = ShopBindables:FindFirstChild("SetActiveLoadout")
	if setActiveBindable and setActiveBindable:IsA("BindableFunction") then
		setActiveBindable.OnInvoke = setActiveLoadoutInvoke
	else
		warn("ShopBindables.SetActiveLoadout BindableFunction is missing")
	end

	print("Loaded shop loadouts system")
end

return Loadouts
