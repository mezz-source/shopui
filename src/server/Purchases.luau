local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ShopRemotes = ReplicatedStorage:WaitForChild("ShopRemotes")
local Purchases = {}

local DataAPI = require(game.ServerScriptService.DataAPI.API)
local ShopTypes = require(game.ReplicatedStorage.ShopClient.ShopTypes)

local ShopBindables = ServerStorage.ShopBindables

local function getWeaponInfo(weaponName: string): ShopTypes.WeaponInfo?
	local GetWeaponInfoBindable = ShopBindables.GetWeaponInfo
	local response = GetWeaponInfoBindable:Invoke(weaponName)
	return response
end

local function getPlayerCredits(player: Player): number
	local credits = DataAPI.getPlayerInfo(player, "Credits")
	return credits or 0
end

local function getPlayerLevel(player: Player): number
	local level = DataAPI.getPlayerInfo(player, "Level")
	return level or 0
end

local function hasBadgeUnlocked(_player: Player, _badgeTag: string): boolean
	-- Stubbed for now; replace with your badge ownership logic.
	return false
end

local function passesSpecialUnlockRequirement(player: Player, itemInfo: ShopTypes.WeaponInfo): boolean
	local badgeTag = itemInfo.BadgeTag
	local groupId = itemInfo.GroupId

	if badgeTag == nil and groupId == nil then
		return true
	end

	local badgeUnlocked = false
	if badgeTag ~= nil and badgeTag ~= "" then
		badgeUnlocked = hasBadgeUnlocked(player, badgeTag)
	end

	local groupUnlocked = false
	if groupId ~= nil and groupId > 0 then
		groupUnlocked = player:IsInGroupAsync(groupId)
	end

	return badgeUnlocked or groupUnlocked
end

local function addOwnedItem(player: Player, weaponName: string): (boolean, string)
	local ownedItems = DataAPI.getPlayerOwnedItems(player) :: { string }?
	if not ownedItems then
		ownedItems = {}
	end

	if table.find(ownedItems, weaponName) then
		warn("Already owned")
		return false, "Item already owned"
	end

	DataAPI.addPlayerOwnedItem(player, weaponName)

	return true, "Item added to inventory"
end

local function purchaseRequest(player: Player, itemName: string)
	local itemInfo = getWeaponInfo(itemName)
	if not itemInfo then
		return false, "Item not found"
	end

	local playerCredits = getPlayerCredits(player)
	if playerCredits < itemInfo.Price then
		return false, "Not enough credits"
	end

	local playerLevel = getPlayerLevel(player)
	if playerLevel < itemInfo.Level then
		return false, "Player level too low"
	end

	if not passesSpecialUnlockRequirement(player, itemInfo) then
		return false, "Special unlock requirement not met"
	end

	-- attempt to remove credits
	local success, err = DataAPI.incrementPlayerInfo(player, "Credits", -itemInfo.Price)
	if not success then
		return false, err
	end

	local ownedSuccess, message = addOwnedItem(player, itemName)

	if not ownedSuccess then
		return false, message
	end

	ShopRemotes.ItemPurchased:FireClient(player, itemName)

	return true, "Purchase successful"
end

function Purchases.load()
	ShopRemotes.RequestPurchase.OnServerInvoke = purchaseRequest
end

return Purchases
